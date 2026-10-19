import CryptoKit
import Foundation
import UIKit

struct ReferralCampaign: Codable, Identifiable, Equatable {
    let id: String
    var name: String
    var description: String
    var status: String
    var startsAt: String?
    var endsAt: String?
    var timezone: String
    var firstPrizeCents: Int
    var secondPrizeCents: Int
    var thirdPrizeCents: Int
    var rewardType: String?
    var rulesPdfUrl: String?
    var rulesVersion: String
    var rulesHash: String?
    var rulesPublishedAt: String?
    var termsUrl: String?

    var isLive: Bool { status == "active" || status == "paused" }
    var isDraft: Bool { status == "draft" || rulesVersion.lowercased().contains("draft") }
    var hasPublishedFinalRules: Bool {
        rulesPdfUrl != nil
            && rulesPublishedAt != nil
            && !rulesVersion.lowercased().contains("draft")
    }
}

struct ReferredCampaignUser: Codable, Identifiable, Equatable {
    let id: String
    let firstName: String
    let status: String
    let date: String
}

struct ReferralSummary: Codable, Equatable {
    let referralCode: String
    let qualifiedCount: Int
    let pendingCount: Int
    let nextMilestone: Int?
    let privateRank: Int?
    let referredUsers: [ReferredCampaignUser]
    let campaign: ReferralCampaign?

    var referralsRemaining: Int? {
        nextMilestone.map { max(0, $0 - qualifiedCount) }
    }
}

struct AdminReferralStanding: Codable, Identifiable {
    let campaignId: String
    let userId: String
    let name: String
    let email: String?
    let referralCode: String?
    let qualifiedCount: Int
    let pendingCount: Int
    let reachedAt: String?

    var id: String { userId }
}

struct AdminCampaignUser: Codable, Identifiable {
    let userId: String
    let email: String
    let name: String
    let createdAt: String?
    let onboardingComplete: Bool
    let sessionCount: Int
    let totalMinutes: Int
    let reflectionCount: Int
    let accountRole: String?
    let lastActiveAt: String?
    let calibrationComplete: Bool?
    let truthCheckCount: Int?
    let interventionCount: Int?
    let referralSource: String?
    let referralAmbassadorName: String?
    let ambassadorUserId: String?
    let ambassadorAccountName: String?
    let ambassadorReferredAt: String?

    var id: String { userId }
}

struct AccountAccess: Codable, Equatable {
    let role: String
    let isSuperAdmin: Bool
    let canManageAnnouncements: Bool
    let canViewAmbassadorDashboard: Bool

    static let user = AccountAccess(
        role: "user",
        isSuperAdmin: false,
        canManageAnnouncements: false,
        canViewAmbassadorDashboard: false
    )
}

struct AmbassadorNameOption: Codable, Identifiable, Hashable {
    let enteredName: String
    let normalizedName: String
    let count: Int

    var id: String { normalizedName }
}

struct AmbassadorAttributionOptions: Codable {
    let assigned: [AmbassadorNameOption]
    let unassigned: [AmbassadorNameOption]
}

struct AmbassadorPerson: Codable, Identifiable {
    let userId: String
    let firstName: String
    let joinedAt: String?
    let onboardingComplete: Bool
    let referralStatus: String

    var id: String { userId }
}

struct AmbassadorDashboard: Codable {
    let totalCount: Int
    let completedCount: Int
    let pendingCount: Int
    let people: [AmbassadorPerson]
}

struct AdminOverviewMetrics: Codable {
    let totalUsers: Int
    let dau: Int
    let mau: Int
    let newToday: Int
    let newWeek: Int
    let newMonth: Int
    let avgSessions: Double?
    let avgTruth: Double?
    let onboardingPct: Double?
    let reflectionPct: Double?
    let avgTruthGap: Double?
}

struct AdminRetentionMetrics: Codable { let d1: Double; let d7: Double; let d30: Double }
struct AdminTimePoint: Codable, Identifiable { let date: String; let downloads: Int; let activeUsers: Int; var id: String { date } }
struct AdminVersionMetric: Codable, Identifiable { let version: String?; let users: Int; var id: String { version ?? "unknown" } }
struct AdminFunnelStage: Codable, Identifiable { let stage: String; let count: Int; var id: String { stage } }
struct AdminSourceMetric: Codable, Identifiable { let source: String; let signups: Int; let onboarded: Int; var id: String { source } }
struct AdminTriggerMetric: Codable, Identifiable { let trigger: String; let count: Int; var id: String { trigger } }

struct AdminProductDashboard: Codable {
    let overview: AdminOverviewMetrics
    let retention: AdminRetentionMetrics
    let timeseries: [AdminTimePoint]
    let versions: [AdminVersionMetric]
    let funnel: [AdminFunnelStage]
    let sources: [AdminSourceMetric]
    let triggers: [AdminTriggerMetric]
}

struct AdminFeedbackItem: Codable, Identifiable {
    let id: String
    let userId: String?
    let type: String
    let subject: String
    let message: String
    let status: String
    let assignedTo: String?
    let internalNotes: String?
    let appVersion: String?
    let deviceInfo: String?
    let createdAt: String
    let updatedAt: String
}

struct ParentalConsentRequest: Codable, Identifiable {
    let id: String
    let parentEmail: String
    let birthMonth: Int
    let birthYear: Int
    let status: String
    let evidenceStoragePath: String?
    let reviewerNote: String?
    let reviewedAt: String?
    let expiresAt: String
    let createdAt: String
}

struct AdminReferralDashboard: Codable {
    let campaigns: [ReferralCampaign]
    let standings: [AdminReferralStanding]
    let consentRequests: [ParentalConsentRequest]
    let users: [AdminCampaignUser]
}

struct ParentalConsentTicket: Codable {
    let requestId: String
    let requestToken: String
    let status: String
}

struct ParentalConsentStatus: Codable {
    let status: String
    let reviewerNote: String?
    let expiresAt: String?
}

struct AdminSessionRecord: Codable, Identifiable {
    let id: String
    let date: String
    let startTime: String
    let endTime: String
    var plannedDuration: Int
    var actualDuration: Int
    let intention: String
    var reflection: String?
    var reflectionNote: String
}

struct AdminUserDetail: Codable {
    let sessions: [AdminSessionRecord]
}

struct MivoAnnouncement: Codable, Identifiable, Equatable {
    let id: String
    let title: String
    let body: String
    let status: String
    let publishedAt: String?
    let expiresAt: String?
    let createdBy: String
    let createdAt: String
    let updatedAt: String
}

enum ReferralCampaignError: LocalizedError {
    case unavailable
    case authenticationRequired
    case server(String)

    var errorDescription: String? {
        switch self {
        case .unavailable: return "The online Mivo campaign service is not configured."
        case .authenticationRequired: return "Sign in again to continue."
        case .server(let message):
            let normalized = message.replacingOccurrences(of: "_", with: " ")
            return normalized.prefix(1).uppercased() + normalized.dropFirst()
        }
    }
}

enum ReferralCampaignService {
    private static var baseURL: URL? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "MIVO_SUPABASE_URL") as? String else { return nil }
        let cleaned = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/rest/v1/?$", with: "", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return URL(string: cleaned)
    }

    private static var anonKey: String {
        (Bundle.main.object(forInfoDictionaryKey: "MIVO_SUPABASE_ANON_KEY") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }

    private static var accessToken: String? {
        if let token = SecureAuthService.loadRecord()?.remoteAccessToken, !token.isEmpty {
            return token
        }
        guard let email = DeviceBindingService.boundEmail else { return nil }
        return SecureAuthService.loadRecord(email: email)?.remoteAccessToken
    }

    private static var currentRemoteUserID: String? {
        if let id = SecureAuthService.loadRecord()?.remoteUserId { return id }
        guard let email = DeviceBindingService.boundEmail else { return nil }
        return SecureAuthService.loadRecord(email: email)?.remoteUserId
    }

    private static func jsonObject<T: Encodable>(_ value: T) throws -> Any {
        let data = try JSONEncoder().encode(value)
        return try JSONSerialization.jsonObject(with: data)
    }

    static var isConfigured: Bool { baseURL != nil && !anonKey.isEmpty }

    static func loadSummary() async throws -> ReferralSummary {
        try await rpc("get_my_referral_summary", body: [:], authenticated: true)
    }

    static func attach(code: String) async throws {
        let _: AttachResponse = try await rpc(
            "attach_referral_code",
            body: ["input_code": code.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)],
            authenticated: true
        )
    }

    static func isSuperAdmin() async throws -> Bool {
        try await rpc("is_app_admin", body: [:], authenticated: true)
    }

    static func currentAccountAccess() async throws -> AccountAccess {
        try await rpc("current_account_access", body: [:], authenticated: true)
    }

    static func loadProductDashboard() async throws -> AdminProductDashboard {
        try await rpc("admin_product_dashboard", body: [:], authenticated: true)
    }

    static func requestNewAccountAlert() async throws {
        guard let userID = currentRemoteUserID else { throw ReferralCampaignError.authenticationRequired }
        let _: AlertRequestResponse = try await rest(
            path: "functions/v1/new-account-alert",
            method: "POST",
            body: ["user_id": userID],
            authenticated: true,
            prefer: nil
        )
    }

    static func loadWeeklyExperiments() async throws -> [WeeklyExperiment] {
        try await rest(
            path: "rest/v1/weekly_experiments?select=*&order=created_at.desc",
            method: "GET",
            body: nil,
            authenticated: true,
            prefer: nil
        )
    }

    static func saveWeeklyExperiment(_ experiment: WeeklyExperiment) async throws -> WeeklyExperiment {
        guard let userID = experiment.userId ?? currentRemoteUserID else {
            throw ReferralCampaignError.authenticationRequired
        }
        let payload: [String: Any] = [
            "id": experiment.id,
            "user_id": userID,
            "type": experiment.type.rawValue,
            "status": experiment.status.rawValue,
            "title": experiment.title,
            "reason": experiment.reason,
            "primary_metric": experiment.primaryMetric,
            "rule": try jsonObject(experiment.rule),
            "baseline_metrics": try jsonObject(experiment.baselineMetrics),
            "result_metrics": try experiment.resultMetrics.map(jsonObject) ?? NSNull(),
            "starts_at": experiment.startsAt ?? NSNull(),
            "ends_at": experiment.endsAt ?? NSNull(),
            "outcome": experiment.outcome?.rawValue ?? NSNull(),
            "final_decision": experiment.finalDecision?.rawValue ?? NSNull(),
            "user_feedback": experiment.userFeedback?.rawValue ?? NSNull(),
            "feedback_note": experiment.feedbackNote ?? NSNull(),
            "feedback_submitted_at": experiment.feedbackSubmittedAt ?? NSNull(),
            "created_at": experiment.createdAt,
            "updated_at": experiment.updatedAt
        ]
        let rows: [WeeklyExperiment] = try await rest(
            path: "rest/v1/weekly_experiments?on_conflict=id",
            method: "POST",
            body: [payload],
            authenticated: true,
            prefer: "resolution=merge-duplicates,return=representation"
        )
        guard let saved = rows.first else { throw ReferralCampaignError.server("experiment_not_saved") }
        return saved
    }

    static func setUserRole(userID: String, role: String) async throws {
        let _: EmptyRPCResponse = try await rpcAllowingEmpty(
            "admin_set_user_role",
            body: ["input_user_id": userID, "input_role": role], authenticated: true
        )
    }

    static func ambassadorAttributionOptions(userID: String) async throws -> AmbassadorAttributionOptions {
        try await rpc(
            "admin_ambassador_attribution_options",
            body: ["input_user_id": userID],
            authenticated: true
        )
    }

    static func setAmbassadorNames(userID: String, normalizedNames: [String]) async throws {
        let _: EmptyRPCResponse = try await rpcAllowingEmpty(
            "admin_set_ambassador_names",
            body: ["input_user_id": userID, "input_normalized_names": normalizedNames],
            authenticated: true
        )
    }

    static func loadAmbassadorDashboard() async throws -> AmbassadorDashboard {
        try await rpc("ambassador_dashboard", body: [:], authenticated: true)
    }

    static func logEvent(_ name: String, source: String? = nil, metadata: [String: Any] = [:]) async {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        var payload = metadata
        payload["app_version"] = version
        let _: EmptyRPCResponse? = try? await rpcAllowingEmpty(
            "log_analytics_event",
            body: ["input_event_name": name, "input_source": source ?? NSNull(), "input_metadata": payload],
            authenticated: true
        )
    }

    @MainActor
    static func submitFeedback(type: String, subject: String, message: String) async throws {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        let device = "\(UIDevice.current.model) · iOS \(UIDevice.current.systemVersion)"
        let feedback: AdminFeedbackItem = try await rpc(
            "submit_feedback",
            body: ["input_type": type, "input_subject": subject, "input_message": message,
                   "input_app_version": version, "input_device_info": device], authenticated: true
        )
        let _: FeedbackEmailResponse = try await rest(
            path: "functions/v1/feedback-email",
            method: "POST",
            body: ["feedback_id": feedback.id],
            authenticated: true,
            prefer: nil
        )
    }

    static func adminFeedback() async throws -> [AdminFeedbackItem] {
        try await rpc("admin_feedback_dashboard", body: [:], authenticated: true)
    }

    static func updateFeedback(id: String, status: String, assignedTo: String, notes: String) async throws {
        let _: EmptyRPCResponse = try await rpcAllowingEmpty(
            "admin_update_feedback",
            body: ["input_id": id, "input_status": status, "input_assigned_to": assignedTo, "input_internal_notes": notes],
            authenticated: true
        )
    }

    static func createParentalConsentRequest(
        parentEmail: String,
        birthMonth: Int,
        birthYear: Int
    ) async throws -> ParentalConsentTicket {
        do {
            return try await rest(
                path: "functions/v1/parental-consent",
                method: "POST",
                body: [
                    "parent_email": parentEmail,
                    "birth_month": birthMonth,
                    "birth_year": birthYear
                ],
                authenticated: false,
                prefer: nil
            )
        } catch {
            return try await rpc(
                "create_parental_consent_request",
                body: [
                    "input_parent_email": parentEmail,
                    "input_birth_month": birthMonth,
                    "input_birth_year": birthYear
                ],
                authenticated: false
            )
        }
    }

    static func parentalConsentStatus(ticket: ParentalConsentTicket) async throws -> ParentalConsentStatus {
        try await rpc(
            "parental_consent_status",
            body: [
                "input_request_id": ticket.requestId,
                "input_request_token": ticket.requestToken
            ],
            authenticated: false
        )
    }

    static func claimApprovedParentalConsent(ticket: ParentalConsentTicket) async throws {
        let _: EmptyRPCResponse = try await rpcAllowingEmpty(
            "claim_approved_parental_consent",
            body: [
                "input_request_id": ticket.requestId,
                "input_request_token": ticket.requestToken
            ],
            authenticated: true
        )
    }

    static func loadAdminDashboard() async throws -> AdminReferralDashboard {
        try await rpc("admin_referral_dashboard", body: [:], authenticated: true)
    }

    static func createCampaign() async throws -> ReferralCampaign {
        try await rpc("admin_create_referral_campaign", body: [:], authenticated: true)
    }

    static func unseenAnnouncements() async throws -> [MivoAnnouncement] {
        try await rpc("get_unseen_announcements", body: [:], authenticated: true)
    }

    static func markAnnouncementSeen(id: String, dismissed: Bool) async throws {
        let _: EmptyRPCResponse = try await rpcAllowingEmpty(
            "mark_announcement_seen",
            body: ["input_announcement_id": id, "input_dismissed": dismissed],
            authenticated: true
        )
    }

    static func adminAnnouncements() async throws -> [MivoAnnouncement] {
        try await rpc("admin_announcement_dashboard", body: [:], authenticated: true)
    }

    static func createAnnouncement(
        title: String,
        body: String,
        expiresAt: Date?,
        publishNow: Bool
    ) async throws -> MivoAnnouncement {
        try await rpc(
            "admin_create_announcement",
            body: [
                "input_title": title,
                "input_body": body,
                "input_expires_at": expiresAt.map(ISO8601DateFormatter().string(from:)) ?? NSNull(),
                "input_publish_now": publishNow
            ],
            authenticated: true
        )
    }

    static func updateAnnouncementDraft(
        id: String,
        title: String,
        body: String,
        expiresAt: Date?
    ) async throws -> MivoAnnouncement {
        try await rpc(
            "admin_update_announcement_draft",
            body: [
                "input_announcement_id": id,
                "input_title": title,
                "input_body": body,
                "input_expires_at": expiresAt.map(ISO8601DateFormatter().string(from:)) ?? NSNull()
            ],
            authenticated: true
        )
    }

    static func setAnnouncementStatus(id: String, status: String) async throws {
        let _: EmptyRPCResponse = try await rpcAllowingEmpty(
            "admin_set_announcement_status",
            body: ["input_announcement_id": id, "input_status": status],
            authenticated: true
        )
    }

    static func registerAdminPushDevice(deviceToken: String, installationID: String) async throws {
        #if DEBUG
        let environment = "sandbox"
        #else
        let environment = "production"
        #endif
        let _: EmptyRPCResponse = try await rpcAllowingEmpty(
            "register_admin_push_device",
            body: [
                "input_installation_id": installationID,
                "input_device_token": deviceToken,
                "input_environment": environment
            ],
            authenticated: true
        )
    }

    static func unregisterAdminPushDevice() async throws {
        let installationID = try DeviceBindingService.installationID()
        let _: EmptyRPCResponse = try await rpcAllowingEmpty(
            "unregister_admin_push_device",
            body: ["input_installation_id": installationID],
            authenticated: true
        )
    }

    static func loadAdminUserDetail(userID: String) async throws -> AdminUserDetail {
        try await rpc("admin_get_user_detail", body: ["input_user_id": userID], authenticated: true)
    }

    static func reviewConsent(id: String, status: String, note: String?) async throws {
        let _: EmptyRPCResponse = try await rpcAllowingEmpty(
            "admin_review_parental_consent",
            body: ["input_request_id": id, "input_status": status, "input_note": note ?? NSNull()],
            authenticated: true
        )
    }

    static func updateCampaign(
        _ campaign: ReferralCampaign,
        startsAt: Date?,
        endsAt: Date?,
        milestones: [Int]
    ) async throws -> ReferralCampaign {
        let formatter = ISO8601DateFormatter()
        let payload: [String: Any] = [
            "name": campaign.name,
            "description": campaign.description,
            "status": campaign.status,
            "starts_at": startsAt.map(formatter.string(from:)) ?? NSNull(),
            "ends_at": endsAt.map(formatter.string(from:)) ?? NSNull(),
            "timezone": campaign.timezone,
            "first_prize_cents": campaign.firstPrizeCents,
            "second_prize_cents": campaign.secondPrizeCents,
            "third_prize_cents": campaign.thirdPrizeCents,
            "reward_type": campaign.rewardType ?? "cash",
            "rules_version": campaign.rulesVersion,
            "terms_url": campaign.termsUrl ?? NSNull(),
            "updated_at": formatter.string(from: Date())
        ]
        let rows: [ReferralCampaign] = try await rest(
            path: "rest/v1/referral_campaigns?id=eq.\(campaign.id)",
            method: "PATCH",
            body: payload,
            authenticated: true,
            prefer: "return=representation"
        )
        try await replaceMilestones(campaignID: campaign.id, milestones: milestones)
        guard let updated = rows.first else { throw ReferralCampaignError.server("campaign_not_saved") }
        return updated
    }

    static func uploadDraftRules(campaignID: String, fileURL: URL) async throws -> String {
        guard let data = try? Data(contentsOf: fileURL) else {
            throw ReferralCampaignError.server("rules_file_missing")
        }
        let objectPath = "\(campaignID)/Mivo_Referral_Campaign_Official_Rules_Draft_v0.1.pdf"
        let _: Data = try await rawRequest(
            path: "storage/v1/object/campaign-rules/\(objectPath)",
            method: "POST",
            bodyData: data,
            contentType: "application/pdf",
            authenticated: true,
            extraHeaders: ["x-upsert": "true"]
        )
        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let _: [ReferralCampaign] = try await rest(
            path: "rest/v1/referral_campaigns?id=eq.\(campaignID)",
            method: "PATCH",
            body: [
                "rules_pdf_url": "campaign-rules/\(objectPath)",
                "rules_hash": hash,
                "rules_version": "0.1-draft",
                "rules_published_at": ISO8601DateFormatter().string(from: Date()),
                "updated_at": ISO8601DateFormatter().string(from: Date())
            ],
            authenticated: true,
            prefer: "return=representation"
        )
        return objectPath
    }

    static func publishFinalRules(campaignID: String, fileURL: URL, version: String) async throws {
        guard let data = try? Data(contentsOf: fileURL), !data.isEmpty else {
            throw ReferralCampaignError.server("final_rules_file_missing")
        }
        guard !version.lowercased().contains("draft"), !version.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw ReferralCampaignError.server("final_rules_version_required")
        }
        guard let publisherID = SecureAuthService.loadRecord()?.remoteUserId else {
            throw ReferralCampaignError.authenticationRequired
        }
        let safeVersion = version.replacingOccurrences(of: " ", with: "-")
        let objectPath = "\(campaignID)/Mivo_Referral_Campaign_Official_Rules_v\(safeVersion).pdf"
        let _: Data = try await rawRequest(
            path: "storage/v1/object/campaign-rules/\(objectPath)",
            method: "POST",
            bodyData: data,
            contentType: "application/pdf",
            authenticated: true,
            extraHeaders: ["x-upsert": "false"]
        )
        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let _: [RuleVersionResponse] = try await rest(
            path: "rest/v1/campaign_rule_versions",
            method: "POST",
            body: [[
                "campaign_id": campaignID,
                "version": version,
                "storage_path": "campaign-rules/\(objectPath)",
                "sha256": hash,
                "is_draft": false,
                "published_by": publisherID,
                "effective_at": ISO8601DateFormatter().string(from: Date())
            ]],
            authenticated: true,
            prefer: "return=representation"
        )
        let _: [ReferralCampaign] = try await rest(
            path: "rest/v1/referral_campaigns?id=eq.\(campaignID)",
            method: "PATCH",
            body: [
                "rules_pdf_url": "campaign-rules/\(objectPath)",
                "rules_hash": hash,
                "rules_version": version,
                "rules_published_at": ISO8601DateFormatter().string(from: Date()),
                "updated_at": ISO8601DateFormatter().string(from: Date())
            ],
            authenticated: true,
            prefer: "return=representation"
        )
    }

    static func downloadRules(remotePath: String) async throws -> URL {
        let cleanPath = remotePath.replacingOccurrences(of: "campaign-rules/", with: "")
        let data: Data = try await rawRequest(
            path: "storage/v1/object/campaign-rules/\(cleanPath)",
            method: "GET",
            bodyData: nil,
            contentType: nil,
            authenticated: true
        )
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("Mivo_Referral_Campaign_Rules.pdf")
        try data.write(to: destination, options: .atomic)
        return destination
    }

    static func updateSession(
        userID: String,
        session: AdminSessionRecord,
        reason: String
    ) async throws {
        let _: EmptyRPCResponse = try await rpcAllowingEmpty(
            "admin_update_session",
            body: [
                "input_user_id": userID,
                "input_session_id": session.id,
                "input_planned_duration": session.plannedDuration,
                "input_actual_duration": session.actualDuration,
                "input_reflection": session.reflection ?? "",
                "input_reflection_note": session.reflectionNote,
                "input_reason": reason
            ],
            authenticated: true
        )
    }

    static func resetUserProgress(userID: String, reason: String) async throws {
        let _: EmptyRPCResponse = try await rpcAllowingEmpty(
            "admin_reset_user_progress",
            body: ["input_user_id": userID, "input_reason": reason],
            authenticated: true
        )
    }

    static func deleteUser(userID: String, reason: String) async throws {
        let _: EmptyRPCResponse = try await rpcAllowingEmpty(
            "admin_delete_user",
            body: ["input_user_id": userID, "input_reason": reason],
            authenticated: true
        )
    }

    private static func replaceMilestones(campaignID: String, milestones: [Int]) async throws {
        let _: Data = try await rawRequest(
            path: "rest/v1/referral_milestones?campaign_id=eq.\(campaignID)",
            method: "DELETE",
            bodyData: nil,
            contentType: nil,
            authenticated: true
        )
        let rows = Array(Set(milestones.filter { $0 > 0 })).sorted().map {
            ["campaign_id": campaignID, "target_count": $0] as [String: Any]
        }
        guard !rows.isEmpty else { return }
        let _: [MilestoneResponse] = try await rest(
            path: "rest/v1/referral_milestones",
            method: "POST",
            body: rows,
            authenticated: true,
            prefer: "return=representation"
        )
    }

    private static func rpc<Response: Decodable>(
        _ name: String,
        body: [String: Any],
        authenticated: Bool
    ) async throws -> Response {
        try await rest(
            path: "rest/v1/rpc/\(name)",
            method: "POST",
            body: body,
            authenticated: authenticated,
            prefer: nil
        )
    }

    private static func rpcAllowingEmpty<Response: Decodable>(
        _ name: String,
        body: [String: Any],
        authenticated: Bool
    ) async throws -> Response {
        let data: Data = try await rawRequest(
            path: "rest/v1/rpc/\(name)",
            method: "POST",
            bodyData: try JSONSerialization.data(withJSONObject: body),
            contentType: "application/json",
            authenticated: authenticated
        )
        if data.isEmpty || String(data: data, encoding: .utf8) == "null" {
            return try decoder.decode(Response.self, from: Data("{}".utf8))
        }
        return try decoder.decode(Response.self, from: data)
    }

    private static func rest<Response: Decodable>(
        path: String,
        method: String,
        body: Any?,
        authenticated: Bool,
        prefer: String?
    ) async throws -> Response {
        let bodyData = try body.map { try JSONSerialization.data(withJSONObject: $0) }
        let data: Data = try await rawRequest(
            path: path,
            method: method,
            bodyData: bodyData,
            contentType: body == nil ? nil : "application/json",
            authenticated: authenticated,
            extraHeaders: prefer.map { ["Prefer": $0] } ?? [:]
        )
        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            throw ReferralCampaignError.server("invalid_campaign_response")
        }
    }

    private static func rawRequest(
        path: String,
        method: String,
        bodyData: Data?,
        contentType: String?,
        authenticated: Bool,
        extraHeaders: [String: String] = [:]
    ) async throws -> Data {
        guard let baseURL, !anonKey.isEmpty,
              let url = URL(string: path, relativeTo: baseURL)?.absoluteURL else {
            throw ReferralCampaignError.unavailable
        }
        let bearer: String
        if authenticated {
            guard let token = accessToken, !token.isEmpty else { throw ReferralCampaignError.authenticationRequired }
            bearer = token
        } else {
            bearer = anonKey
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = bodyData
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
        if let contentType { request.setValue(contentType, forHTTPHeaderField: "Content-Type") }
        extraHeaders.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw ReferralCampaignError.unavailable
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 500
        guard (200..<300).contains(status) else {
            let payload = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let message = payload?["message"] as? String
                ?? payload?["error"] as? String
                ?? "campaign_request_failed"
            throw ReferralCampaignError.server(message)
        }
        return data
    }

    private struct AttachResponse: Decodable { let status: String }
    private struct AlertRequestResponse: Decodable { let ok: Bool }
    private struct FeedbackEmailResponse: Decodable { let ok: Bool }
    private struct MilestoneResponse: Decodable { let id: String }
    private struct RuleVersionResponse: Decodable { let id: String }
    private struct EmptyRPCResponse: Decodable { init() {} }
}

enum ParentalConsentTicketStore {
    private static let key = "mivo.parentalConsentTicket"

    static func save(_ ticket: ParentalConsentTicket) {
        if let data = try? JSONEncoder().encode(ticket) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    static func load() -> ParentalConsentTicket? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(ParentalConsentTicket.self, from: data)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}

@MainActor
extension AppViewModel {
    func prepareAuthenticatedCampaignSession() async throws {
        guard isLoggedIn, let currentUser = user else {
            throw ReferralCampaignError.authenticationRequired
        }
        guard var record = SecureAuthService.loadRecord(email: currentUser.email),
              record.remoteUserId != nil else {
            throw ReferralCampaignError.authenticationRequired
        }

        do {
            let remoteUser = try await RemoteAuthService.validateStoredSession(record: record)
            record.name = remoteUser.name
            record.createdAt = remoteUser.createdAt
            if remoteUser.isAdmin == true {
                record.isAdmin = true
                record.accountRole = "super_admin"
            }
            record.remoteUserId = remoteUser.remoteUserId ?? record.remoteUserId
            record.remoteAccessToken = remoteUser.accessToken ?? record.remoteAccessToken
            record.remoteRefreshToken = remoteUser.refreshToken ?? record.remoteRefreshToken
            try SecureAuthService.saveRecord(record)

            user = UserProfile(
                email: currentUser.email,
                name: remoteUser.name,
                createdAt: currentUser.createdAt,
                onboardingProfile: currentUser.onboardingProfile,
                isAdmin: record.isAdmin,
                accountRole: record.accountRole
            )
        } catch AppError.invalidCredentials {
            throw ReferralCampaignError.authenticationRequired
        } catch AppError.noAccount {
            throw ReferralCampaignError.authenticationRequired
        }
    }

    func refreshServerAdminRole() async {
        guard isLoggedIn, ReferralCampaignService.isConfigured else { return }
        do {
            let access: AccountAccess
            do {
                access = try await ReferralCampaignService.currentAccountAccess()
            } catch {
                try await prepareAuthenticatedCampaignSession()
                access = try await ReferralCampaignService.currentAccountAccess()
            }
            if var current = user {
                current.isAdmin = access.isSuperAdmin
                current.accountRole = access.role
                user = current
            }
            if var record = SecureAuthService.loadRecord() {
                record.isAdmin = access.isSuperAdmin
                record.accountRole = access.role
                try? SecureAuthService.saveRecord(record)
            }
            await AdminPushNotificationManager.sync(for: access)
        } catch {
            // A temporary network failure must not promote an account. Existing
            // cached admin state is retained until the server can be reached.
        }
    }

    func loadReferralSummary() async throws -> ReferralSummary {
        try await prepareAuthenticatedCampaignSession()
        return try await ReferralCampaignService.loadSummary()
    }

    func attachReferralCode(_ code: String) async throws {
        try await prepareAuthenticatedCampaignSession()
        try await ReferralCampaignService.attach(code: code)
    }
}
