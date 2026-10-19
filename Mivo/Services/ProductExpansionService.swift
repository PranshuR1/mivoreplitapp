import Foundation

enum ProductExpansionError: LocalizedError {
    case unavailable
    case authenticationRequired
    case invalidResponse
    case server(String)

    var errorDescription: String? {
        switch self {
        case .unavailable: return "The online Mivo service is unavailable."
        case .authenticationRequired: return "Sign in again to continue."
        case .invalidResponse: return "Mivo received an unreadable server response."
        case .server(let message): return message.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
}

enum ProductExpansionService {
    private static var baseURL: URL? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "MIVO_SUPABASE_URL") as? String else { return nil }
        let cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/rest/v1/?$", with: "", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return URL(string: cleaned)
    }

    private static var anonKey: String {
        (Bundle.main.object(forInfoDictionaryKey: "MIVO_SUPABASE_ANON_KEY") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private static var accessToken: String? {
        if let token = SecureAuthService.loadRecord()?.remoteAccessToken, !token.isEmpty { return token }
        guard let email = DeviceBindingService.boundEmail else { return nil }
        return SecureAuthService.loadRecord(email: email)?.remoteAccessToken
    }

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()

    static var isConfigured: Bool { baseURL != nil && !anonKey.isEmpty }

    static func myFeatureFlags() async throws -> [MivoFeatureFlag] {
        try await rpc("get_my_feature_flags", body: [:])
    }

    static func adminFeatureFlags() async throws -> [MivoFeatureFlag] {
        try await rpc("admin_feature_flags", body: [:])
    }

    static func updateFeatureFlag(_ flag: MivoFeatureFlag) async throws -> MivoFeatureFlag {
        try await rpc("admin_update_feature_flag", body: [
            "input_key": flag.key,
            "input_enabled": flag.enabled,
            "input_rollout_percentage": max(0, min(100, flag.rolloutPercentage)),
            "input_minimum_version": flag.minimumVersion ?? NSNull(),
            "input_target_role": flag.targetRole ?? NSNull(),
            "input_founder_preview": flag.founderPreview
        ])
    }

    static func adminExpansionSnapshot() async throws -> AdminExpansionSnapshot {
        try await rpc("admin_expansion_dashboard", body: [:])
    }

    static func adminUserTimeline(userID: String) async throws -> [AdminTimelineEvent] {
        try await rpc("admin_sanitized_user_timeline", body: ["input_user_id": userID])
    }

    static func repairDataQualityIssue(id: String) async throws {
        let _: EmptyResponse = try await rpcAllowingEmpty("admin_repair_data_quality_issue", body: ["input_issue_id": id])
    }

    static func resolveReviewItem(id: String, action: String) async throws {
        let _: EmptyResponse = try await rpcAllowingEmpty(
            "admin_resolve_review_item",
            body: ["input_item_id": id, "input_action": action]
        )
    }

    static func saveRecoveryPlan(_ plan: RecoveryPlan) async throws {
        let payload = try jsonObject(plan)
        let _: EmptyResponse = try await rpcAllowingEmpty("save_recovery_plan", body: ["input_plan": payload])
    }

    /// Restores this account's recovery plans on a device that has none
    /// locally yet (reinstall, new device) — `save_recovery_plan` above was
    /// push-only until this was added, so a signed-out device had no way to
    /// get its history back even though Supabase held a full copy the
    /// whole time.
    static func recoveryPlans() async throws -> [RecoveryPlan] {
        try await rpc("get_recovery_plans", body: [:])
    }

    static func saveMonthlyEffectReport(_ report: MonthlyEffectReport) async throws {
        let payload = try jsonObject(report)
        let _: EmptyResponse = try await rpcAllowingEmpty("save_monthly_effect_report", body: ["input_report": payload])
    }

    /// See `recoveryPlans()` above — same push-only gap, same fix.
    static func monthlyEffectReports() async throws -> [MonthlyEffectReport] {
        try await rpc("get_monthly_effect_reports", body: [:])
    }

    static func inviteAccountabilityPartner(email: String, summary: SharedWeeklySummary) async throws -> AccountabilityConnection {
        try await function("accountability-summary", body: [
            "action": "invite",
            "partner_email": email,
            "summary": try jsonObject(summary)
        ])
    }

    static func setAccountabilitySharing(connectionID: String, enabled: Bool) async throws -> AccountabilityConnection {
        try await rpc("set_accountability_sharing", body: [
            "input_connection_id": connectionID,
            "input_enabled": enabled
        ])
    }

    static func revokeAccountabilityConnection(id: String) async throws {
        let _: EmptyResponse = try await rpcAllowingEmpty(
            "revoke_accountability_connection", body: ["input_connection_id": id]
        )
    }

    static func accountabilityConnections() async throws -> [AccountabilityConnection] {
        try await rpc("get_accountability_connections", body: [:])
    }

    static func mivoClearConfigurations() async throws -> [MivoClearPlatformConfiguration] {
        try await rpc("get_mivo_clear_configuration", body: [:])
    }

    static func recordMivoClearSession(_ session: MivoClearSession) async throws {
        let payload = try jsonObject(session)
        let _: EmptyResponse = try await rpcAllowingEmpty(
            "record_mivo_clear_session",
            body: ["input_session": payload]
        )
    }

    /// See `recoveryPlans()` above — same push-only gap, same fix.
    static func mivoClearSessions() async throws -> [MivoClearSession] {
        try await rpc("get_mivo_clear_sessions", body: [:])
    }

    static func ingestDiagnostic(kind: String, payload: [String: Any]) async {
        guard isConfigured else { return }
        let _: EmptyResponse? = try? await rpcAllowingEmpty(
            "ingest_client_health_event",
            body: ["input_kind": kind, "input_payload": payload]
        )
    }

    static func ingestPrivacyRequest(type: String) async throws {
        let _: EmptyResponse = try await rpcAllowingEmpty(
            "create_privacy_request",
            body: ["input_request_type": type]
        )
    }

    private static func jsonObject<T: Encodable>(_ value: T) throws -> Any {
        try JSONSerialization.jsonObject(with: JSONEncoder().encode(value))
    }

    private static func rpc<Response: Decodable>(_ name: String, body: [String: Any]) async throws -> Response {
        try await request(path: "rest/v1/rpc/\(name)", body: body)
    }

    private static func rpcAllowingEmpty<Response: Decodable>(_ name: String, body: [String: Any]) async throws -> Response {
        try await request(path: "rest/v1/rpc/\(name)", body: body, allowEmpty: true)
    }

    private static func function<Response: Decodable>(_ name: String, body: [String: Any]) async throws -> Response {
        try await request(path: "functions/v1/\(name)", body: body)
    }

    private static func request<Response: Decodable>(
        path: String,
        body: [String: Any],
        allowEmpty: Bool = false
    ) async throws -> Response {
        guard let baseURL, !anonKey.isEmpty,
              let url = URL(string: path, relativeTo: baseURL)?.absoluteURL else {
            throw ProductExpansionError.unavailable
        }
        guard let accessToken, !accessToken.isEmpty else { throw ProductExpansionError.authenticationRequired }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 500
        guard (200..<300).contains(status) else {
            let value = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            throw ProductExpansionError.server(value?["message"] as? String ?? value?["error"] as? String ?? "request_failed")
        }
        if allowEmpty && (data.isEmpty || String(data: data, encoding: .utf8) == "null") {
            return try decoder.decode(Response.self, from: Data("{}".utf8))
        }
        guard let decoded = try? decoder.decode(Response.self, from: data) else {
            throw ProductExpansionError.invalidResponse
        }
        return decoded
    }

    private struct EmptyResponse: Decodable { init() {} }
}
