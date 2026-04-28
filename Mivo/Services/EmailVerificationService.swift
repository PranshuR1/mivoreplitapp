import Foundation

enum EmailVerificationService {
    static let senderEmail = "info.mivoapp@gmail.com"

    static func send(code: String, to recipient: String, purpose: TwoFactorChallenge.Purpose) async throws {
        if let endpoint = Bundle.main.object(forInfoDictionaryKey: "MIVO_AUTH_EMAIL_API_URL") as? String,
           !endpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let url = URL(string: endpoint) {
            try await sendViaBackend(code: code, to: recipient, purpose: purpose, endpoint: url)
            return
        }

        #if DEBUG
        print("[Mivo Auth] \(purpose.emailSubject) from \(senderEmail) to \(recipient): \(code)")
        #else
        throw AppError.emailDeliveryUnavailable
        #endif
    }

    private static func sendViaBackend(code: String, to recipient: String, purpose: TwoFactorChallenge.Purpose, endpoint: URL) async throws {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(EmailPayload(
            from: senderEmail,
            to: recipient,
            subject: purpose.emailSubject,
            code: code
        ))

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            if let message = String(data: data, encoding: .utf8), !message.isEmpty {
                print("[Mivo Auth] Email backend failed: \(message)")
            }
            throw AppError.emailDeliveryUnavailable
        }
    }
}

private struct EmailPayload: Encodable {
    let from: String
    let to: String
    let subject: String
    let code: String
}
