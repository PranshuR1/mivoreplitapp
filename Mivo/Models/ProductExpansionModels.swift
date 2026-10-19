import Foundation

enum MivoFeatureKey: String, Codable, CaseIterable, Identifiable {
    case todayGuide = "today_guide"
    case recoveryMode = "recovery_mode"
    case liveActivities = "live_activities"
    case appPersonalities = "app_personalities"
    case monthlyEffectReport = "monthly_effect_report"
    case experimentLibrary = "experiment_library"
    case accountabilityPartners = "accountability_partners"
    case diagnostics = "diagnostics"
    case mivoClear = "mivo_clear"
    case mivoClearInstagram = "mivo_clear_instagram"
    case mivoClearTikTok = "mivo_clear_tiktok"
    case mivoClearYouTube = "mivo_clear_youtube"
    case mivoClearSnapchat = "mivo_clear_snapchat"
    case mivoStill = "mivo_still"
    case intentGames = "intent_games"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .todayGuide: return "Today's Guide"
        case .recoveryMode: return "Recovery Mode"
        case .liveActivities: return "Live Activities"
        case .appPersonalities: return "App personalities"
        case .monthlyEffectReport: return "Monthly effect report"
        case .experimentLibrary: return "Experiment library"
        case .accountabilityPartners: return "Accountability partners"
        case .diagnostics: return "Diagnostics"
        case .mivoClear: return "Mivo Clear"
        case .mivoClearInstagram: return "Mivo Clear - Instagram"
        case .mivoClearTikTok: return "Mivo Clear - TikTok"
        case .mivoClearYouTube: return "Mivo Clear - YouTube"
        case .mivoClearSnapchat: return "Mivo Clear - Snapchat"
        case .mivoStill: return "Mivo Still"
        case .intentGames: return "Focus Break TRIAL"
        }
    }
}

struct MivoFeatureFlag: Codable, Identifiable, Equatable {
    let key: String
    var enabled: Bool
    var rolloutPercentage: Int
    var minimumVersion: String?
    var targetRole: String?
    var founderPreview: Bool
    var automaticallyPaused: Bool
    var updatedAt: String?

    var id: String { key }
}

enum TodayGuideKind: String, Codable {
    case expiredSession
    case rescue
    case truthCheck
    case dailySchedule
    case experiment
    case nextWindow
    case complete
}

struct TodayGuide: Codable, Equatable {
    let kind: TodayGuideKind
    let eyebrow: String
    let title: String
    let detail: String
    let actionTitle: String
    let icon: String
    let progress: Double?
}

enum RecoveryPlanStatus: String, Codable {
    case proposed
    case active
    case completed
    case declined
}

struct RecoveryPlan: Codable, Identifiable, Equatable {
    let id: String
    let date: String
    var status: RecoveryPlanStatus
    let reason: String
    let outsideWindowMinutes: Int
    let notWorthwhileExtensionCount: Int
    let createdAt: String
    var resolvedAt: String?
}

enum AppFrictionStrength: String, Codable, CaseIterable, Identifiable {
    case gentle
    case balanced
    case strong

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

struct AppFrictionProfile: Codable, Identifiable, Equatable {
    let id: String
    var appName: String
    var strength: AppFrictionStrength
    var pauseSeconds: Int
    var intentionEveryOpening: Bool
    var rescueAfterMinutes: Int
    var extensionsAllowed: Bool
    var strongerLateNight: Bool
    var userApproved: Bool
}

struct MonthlyEffectReport: Codable, Identifiable, Equatable {
    let id: String
    let monthKey: String
    let validDays: Int
    let sessionCount: Int
    let averageDailyMinutes: Int
    let outsideWindowMinutes: Int
    let scheduleAdherence: Double
    let extensionRate: Double
    let averageTruthError: Double
    let worthwhileRate: Double
    let completedExperiments: Int
    let estimatedReducedMinutes: Int
    let generatedAt: String

    var hasEnoughData: Bool { validDays >= 7 && sessionCount >= 3 }
}

struct ExperimentTemplate: Codable, Identifiable, Equatable {
    let id: String
    let type: WeeklyExperimentType
    let title: String
    let detail: String
    let rule: WeeklyExperimentRule
    let sourceExperimentID: String?
}

enum AccountabilityConnectionStatus: String, Codable {
    case pending
    case active
    case revoked
}

struct AccountabilityConnection: Codable, Identifiable, Equatable {
    let id: String
    let partnerEmailMasked: String
    var status: AccountabilityConnectionStatus
    var automaticSharingEnabled: Bool
    let createdAt: String
    var revokedAt: String?
}

struct SharedWeeklySummary: Codable, Identifiable, Equatable {
    let id: String
    let connectionId: String
    let weekStart: String
    let weekEnd: String
    let plannedMinutes: Int
    let reflectedDays: Int
    let truthAccuracyTrend: String
    let experimentStatus: String
    let encouragement: String
    let expiresAt: String
    let sentAt: String?
}

enum AdminIssueSeverity: String, Codable, CaseIterable {
    case info
    case warning
    case critical
}

struct AdminReliabilityMetric: Codable, Identifiable, Equatable {
    let key: String
    let title: String
    let value: Double
    let unit: String
    let severity: AdminIssueSeverity
    let updatedAt: String

    var id: String { key }
}

struct AdminReleaseHealth: Codable, Identifiable, Equatable {
    let version: String
    let activeUsers: Int
    let crashFreeRate: Double?
    let loginSuccessRate: Double?
    let syncSuccessRate: Double?
    let sessionCompletionRate: Double?
    let retentionRate: Double?
    let source: String

    var id: String { version }
}

struct AdminDataQualityIssue: Codable, Identifiable, Equatable {
    let id: String
    let issueType: String
    let severity: AdminIssueSeverity
    let summary: String
    let affectedUserId: String?
    let status: String
    let autoRepairable: Bool
    let detectedAt: String
}

struct AdminReviewItem: Codable, Identifiable, Equatable {
    let id: String
    let type: String
    let title: String
    let detail: String
    let status: String
    let createdAt: String
}

struct AdminSecurityEvent: Codable, Identifiable, Equatable {
    let id: String
    let action: String
    let actorLabel: String
    let targetLabel: String?
    let occurredAt: String
    let severity: AdminIssueSeverity
}

struct AdminTimelineEvent: Codable, Identifiable, Equatable {
    let type: String
    let at: String
    let status: String
    let durationMinutes: Int?
    let experimentType: String?
    let supportType: String?
    let event: String?

    var id: String { "\(type)-\(at)-\(event ?? status)" }
}

struct AdminExpansionSnapshot: Codable, Equatable {
    let reliability: [AdminReliabilityMetric]
    let releases: [AdminReleaseHealth]
    let dataQualityIssues: [AdminDataQualityIssue]
    let approvals: [AdminReviewItem]
    let securityEvents: [AdminSecurityEvent]
    let appStoreDataAvailable: Bool
    let generatedAt: String

    static let empty = AdminExpansionSnapshot(
        reliability: [], releases: [], dataQualityIssues: [], approvals: [],
        securityEvents: [], appStoreDataAvailable: false,
        generatedAt: ISO8601DateFormatter().string(from: Date())
    )
}
