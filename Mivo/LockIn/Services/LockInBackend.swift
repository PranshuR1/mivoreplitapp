import Foundation

/// Everything Lock-in asks the Mivo backend: inviting a keyholder, asking them to
/// unlock, and having Milo look at the evidence. `LockInManager` only talks to this,
/// so the rules can be exercised without a network.
///
/// Every method throws `LockInError` and nothing else.
protocol LockInBackend: AnyObject {
    /// False on a build that has no Mivo backend configured.
    var isAvailable: Bool { get }

    /// Emails the friend a link to agree to be the keyholder.
    func inviteKeyholder(name: String, email: String, ownerName: String) async throws -> LockInKeyholder
    /// Whether the friend has opened the link and agreed yet.
    func keyholderStatus(id: String) async throws -> LockInKeyholder
    func revokeKeyholder(id: String) async throws

    /// Emails the keyholder an unlock request carrying Milo's summary.
    func requestUnlock(
        keyholderID: String,
        lockID: String,
        task: String,
        summary: String,
        endsAt: Date,
        ownerName: String
    ) async throws -> LockInUnlockRequest
    func requestStatus(id: String) async throws -> LockInUnlockRequest

    /// Milo reads the conversation (and any photos) and answers. The photos are
    /// sent once and not stored on the server.
    func reviewProof(
        task: String,
        startedAt: Date,
        messages: [LockInMessage],
        images: [Data]
    ) async throws -> MiloReview
}

final class SupabaseLockInBackend: LockInBackend {
    private struct KeyholderPayload: Decodable {
        let id: String
        let name: String
        let emailMasked: String
        let status: LockInKeyholder.Status

        enum CodingKeys: String, CodingKey {
            case id, name, status
            case emailMasked = "email_masked"
        }

        var keyholder: LockInKeyholder {
            LockInKeyholder(id: id, name: name, emailMasked: emailMasked, status: status)
        }
    }

    private struct RequestPayload: Decodable {
        let id: String
        let status: LockInUnlockRequest.Status
        let note: String?
        let createdAt: String?
        let summary: String?

        enum CodingKeys: String, CodingKey {
            case id, status, note, summary
            case createdAt = "created_at"
        }
    }

    private struct ReviewPayload: Decodable {
        let verdict: MiloVerdict
        let reply: String
        let summary: String
    }

    private var baseURL: URL? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "MIVO_SUPABASE_URL") as? String else { return nil }
        let cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/rest/v1/?$", with: "", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return URL(string: cleaned)
    }

    private var anonKey: String {
        (Bundle.main.object(forInfoDictionaryKey: "MIVO_SUPABASE_ANON_KEY") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private var accessToken: String? {
        if let token = SecureAuthService.loadRecord()?.remoteAccessToken, !token.isEmpty { return token }
        guard let email = DeviceBindingService.boundEmail else { return nil }
        return SecureAuthService.loadRecord(email: email)?.remoteAccessToken
    }

    var isAvailable: Bool { baseURL != nil && !anonKey.isEmpty }

    func inviteKeyholder(name: String, email: String, ownerName: String) async throws -> LockInKeyholder {
        let payload: KeyholderPayload = try await call("lockin-keyholder", body: [
            "action": "invite",
            "keyholder_name": name,
            "keyholder_email": email,
            "owner_name": ownerName
        ])
        return payload.keyholder
    }

    func keyholderStatus(id: String) async throws -> LockInKeyholder {
        let payload: KeyholderPayload = try await call("lockin-keyholder", body: [
            "action": "keyholder_status",
            "keyholder_id": id
        ])
        return payload.keyholder
    }

    func revokeKeyholder(id: String) async throws {
        let _: EmptyPayload = try await call("lockin-keyholder", body: [
            "action": "revoke",
            "keyholder_id": id
        ])
    }

    func requestUnlock(
        keyholderID: String,
        lockID: String,
        task: String,
        summary: String,
        endsAt: Date,
        ownerName: String
    ) async throws -> LockInUnlockRequest {
        let payload: RequestPayload = try await call("lockin-keyholder", body: [
            "action": "request_unlock",
            "keyholder_id": keyholderID,
            "lock_id": lockID,
            "task": task,
            "summary": summary,
            "ends_at": ISO8601DateFormatter().string(from: endsAt),
            "owner_name": ownerName
        ])
        return LockInUnlockRequest(
            id: payload.id,
            sentAt: Self.date(payload.createdAt) ?? Date(),
            status: payload.status,
            keyholderNote: payload.note,
            summary: summary
        )
    }

    func requestStatus(id: String) async throws -> LockInUnlockRequest {
        let payload: RequestPayload = try await call("lockin-keyholder", body: [
            "action": "request_status",
            "request_id": id
        ])
        return LockInUnlockRequest(
            id: payload.id,
            sentAt: Self.date(payload.createdAt) ?? Date(),
            status: payload.status,
            keyholderNote: payload.note,
            summary: payload.summary ?? ""
        )
    }

    func reviewProof(
        task: String,
        startedAt: Date,
        messages: [LockInMessage],
        images: [Data]
    ) async throws -> MiloReview {
        let payload: ReviewPayload = try await call("lockin-milo", timeout: 50, body: [
            "task": task,
            "started_at": ISO8601DateFormatter().string(from: startedAt),
            "messages": messages.map { ["role": $0.role.rawValue, "text": $0.text] },
            "images": images.map { $0.base64EncodedString() }
        ])
        return MiloReview(verdict: payload.verdict, reply: payload.reply, summary: payload.summary)
    }

    // MARK: Transport

    private struct EmptyPayload: Decodable {
        init(from decoder: Decoder) throws {}
    }

    private static func date(_ raw: String?) -> Date? {
        guard let raw else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: raw) ?? ISO8601DateFormatter().date(from: raw)
    }

    private func call<Response: Decodable>(
        _ function: String,
        timeout: TimeInterval = 20,
        body: [String: Any]
    ) async throws -> Response {
        guard let baseURL, !anonKey.isEmpty,
              let url = URL(string: "functions/v1/\(function)", relativeTo: baseURL)?.absoluteURL else {
            throw LockInError.notConfigured
        }
        guard let accessToken, !accessToken.isEmpty else { throw LockInError.signedOut }

        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw error is URLError ? LockInError.offline : LockInError.failed
        }

        let status = (response as? HTTPURLResponse)?.statusCode ?? 500
        guard (200..<300).contains(status) else {
            let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            throw Self.map(status: status, code: json?["error"] as? String)
        }
        guard let decoded = try? JSONDecoder().decode(Response.self, from: data) else {
            throw LockInError.failed
        }
        return decoded
    }

    static func map(status: Int, code: String?) -> LockInError {
        if status == 401 { return .signedOut }
        if status == 429 || code == "rate_limited" { return .rateLimited }
        if code == "valid_email_required" { return .invalidEmail }
        return .failed
    }
}

/// Test double. Answers from whatever the test queued, and records what it was
/// asked.
final class InMemoryLockInBackend: LockInBackend {
    var isAvailable = true
    /// When set, every call throws it (offline, signed out, …).
    var failure: LockInError?

    var invitedKeyholder = LockInKeyholder(id: "kh-1", name: "Dana", emailMasked: "d***@example.com", status: .pending)
    var keyholderStatusAnswer: LockInKeyholder.Status = .active
    var requestAnswer: LockInUnlockRequest.Status = .pending
    var requestNote: String?
    /// Reviews are handed out in order; the last one repeats.
    var reviews: [MiloReview] = [
        MiloReview(verdict: .convinced, reply: "That looks done. Nice work.", summary: "Showed the finished work.")
    ]

    private(set) var invites: [(name: String, email: String)] = []
    private(set) var unlockRequests: [(keyholderID: String, task: String, summary: String)] = []
    private(set) var reviewCalls = 0
    private(set) var lastImageCount = 0
    private(set) var revoked: [String] = []

    func inviteKeyholder(name: String, email: String, ownerName: String) async throws -> LockInKeyholder {
        if let failure { throw failure }
        invites.append((name, email))
        var keyholder = invitedKeyholder
        keyholder.name = name
        return keyholder
    }

    func keyholderStatus(id: String) async throws -> LockInKeyholder {
        if let failure { throw failure }
        return LockInKeyholder(
            id: id, name: invitedKeyholder.name, emailMasked: invitedKeyholder.emailMasked, status: keyholderStatusAnswer
        )
    }

    func revokeKeyholder(id: String) async throws {
        if let failure { throw failure }
        revoked.append(id)
    }

    func requestUnlock(
        keyholderID: String,
        lockID: String,
        task: String,
        summary: String,
        endsAt: Date,
        ownerName: String
    ) async throws -> LockInUnlockRequest {
        if let failure { throw failure }
        unlockRequests.append((keyholderID, task, summary))
        return LockInUnlockRequest(
            id: "req-\(unlockRequests.count)",
            sentAt: Date(),
            status: .pending,
            keyholderNote: nil,
            summary: summary
        )
    }

    func requestStatus(id: String) async throws -> LockInUnlockRequest {
        if let failure { throw failure }
        return LockInUnlockRequest(
            id: id,
            sentAt: Date(),
            status: requestAnswer,
            keyholderNote: requestNote,
            summary: unlockRequests.last?.summary ?? ""
        )
    }

    func reviewProof(
        task: String,
        startedAt: Date,
        messages: [LockInMessage],
        images: [Data]
    ) async throws -> MiloReview {
        if let failure { throw failure }
        reviewCalls += 1
        lastImageCount = images.count
        let index = min(reviewCalls - 1, reviews.count - 1)
        return reviews[index]
    }
}
