import Foundation

// MARK: - Types

enum Intention: String, Codable, CaseIterable {
    case killTime = "Kill time"
    case relax = "Relax"
    case bored = "Bored"
    case lookingForSomethingSpecific = "Looking for something specific"
}

enum ReflectionChoice: String, Codable {
    case yes = "Yes"
    case kindOf = "Kind of"
    case no = "No"
}

enum UrgeReason: String, Codable, CaseIterable, Identifiable {
    case bored = "Bored"
    case stressed = "Stressed"
    case habit = "Habit"
    case message = "Message"
    case specificTask = "Specific task"
    case other = "Other"

    var id: String { rawValue }
}

enum SessionOutcomeScore: String, Codable, CaseIterable, Identifiable {
    case worthIt = "Worth it"
    case mixed = "Mixed"
    case notWorthIt = "Not worth it"

    var id: String { rawValue }
}

enum AppRuleMode: String, Codable, CaseIterable, Identifiable {
    case standardPause = "Standard pause"
    case plannedWindowsOnly = "Planned windows only"
    case emergencyUnlockAllowed = "Emergency unlock allowed"
    case looseTracking = "Loose tracking"

    var id: String { rawValue }
}

// MARK: - Models

struct Session: Codable, Identifiable {
    let id: String
    let date: String
    let startTime: String
    let endTime: String
    let plannedDuration: Int
    let actualDuration: Int
    let intention: Intention
    let extendedOnce: Bool
    let reflection: ReflectionChoice?
    let reflectionNote: String
    let urgeReason: UrgeReason?
    let urgeNote: String?
    let outcomeScore: SessionOutcomeScore?
    let emergencyUnlockUsed: Bool?
    let emergencyUnlockReason: String?
}

struct PendingSessionFeedback: Codable, Identifiable {
    let id: String
    let intention: Intention
    let plannedDuration: Int
    let actualDuration: Int
    let startTime: String
    let endTime: String
    let extendedOnce: Bool
    let urgeReason: UrgeReason?
    let urgeNote: String?
    let emergencyUnlockUsed: Bool?
    let emergencyUnlockReason: String?
}

struct RunningMivoSession: Codable, Identifiable {
    let id: String
    let intention: Intention
    let plannedDuration: Int
    let plannedSeconds: Int
    let startTime: String
    let urgeReason: UrgeReason?
    let urgeNote: String?
    let extendedOnce: Bool
    let emergencyUnlockUsed: Bool?
    let emergencyUnlockReason: String?
}

struct SessionExtensionDecision: Identifiable, Equatable {
    let id = UUID()
    let allowed: Bool
    let addedMinutes: Int
    let title: String
    let message: String
}

struct TruthCheckGuess: Codable, Identifiable {
    let id: String
    let date: String
    let guess: Int
    let actual: Int
}

struct TimeTruthPrompt: Identifiable, Equatable {
    let id: String
    let date: String
    let actualMinutes: Int
    let scheduledHour: Int
    let scheduledMinute: Int
}

struct WeeklyReportSnapshot: Codable, Identifiable {
    let id: String
    let weekStart: String
    let weekEnd: String
    let totalMinutes: Int
    let recoveredMinutes: Int
    let sessionCount: Int
    let topUrgeReason: UrgeReason?
    let hardestWindow: String
    let extendedCount: Int
    let emergencyUnlockCount: Int
    let recommendation: String
}

struct AppInterventionRule: Codable, Identifiable {
    let id: String
    var appName: String
    var mode: AppRuleMode
}

struct AccountabilitySummary: Codable {
    let weekStart: String
    let weekEnd: String
    let shareText: String
}

struct WidgetSharedSummary: Codable {
    let recoveredMinutesToday: Int
    let screenTimeMinutesToday: Int?
    let nextScrollWindow: String
    let planState: String
    let streakText: String
    let updatedAt: String
}

struct UserProfile: Codable {
    let email: String
    let name: String
    let createdAt: String
    // Optional onboarding profile stored with the user so AI and features can use it
    var onboardingProfile: OnboardingProfile?
    var isAdmin: Bool? = nil
}

struct AppSettings: Codable {
    var onboardingComplete: Bool
    var notificationsEnabled: Bool
    var tutorialComplete: Bool? = nil
    var notificationsChoiceMade: Bool? = nil
    var accountabilityEnabled: Bool? = nil
}

struct OnboardingProfile: Codable {
    var primaryIntention: Intention?
    var scrollEstimateMinutes: Int?
    var preferredApps: [String]
    // allow multiple intentions to be stored from onboarding
    var intentions: [Intention]
    // optional demographic details
    var age: Int?
    var ageRange: String?

    init(primaryIntention: Intention? = nil, scrollEstimateMinutes: Int? = nil, preferredApps: [String] = []) {
        self.primaryIntention = primaryIntention
        self.scrollEstimateMinutes = scrollEstimateMinutes
        self.preferredApps = preferredApps
        self.intentions = []
        self.age = nil
        self.ageRange = nil
    }
}

struct StoredCredentials: Codable {
    let email: String
    let passwordHash: String
}

// MARK: - AI

enum FocusMode: String, Codable, CaseIterable {
    case classic, adaptive, open, micro, academic

    var displayName: String {
        switch self {
        case .classic: return "Classic Focus"
        case .adaptive: return "Adaptive Focus"
        case .open: return "Open Focus"
        case .micro: return "Micro Focus"
        case .academic: return "Academic Reset"
        }
    }

    var description: String {
        switch self {
        case .classic: return "Fixed duration and lock selected apps until the timer ends."
        case .adaptive: return "Starts small and extends automatically if you stay focused."
        case .open: return "No preset time. Timer runs until you end it."
        case .micro: return "Quick 5–10 minute protection."
        case .academic: return "A Mivo speciality:\n25/5 sprint system built for distracted brains."
        }
    }
}

struct FocusRecommendation: Codable {
    let mode: FocusMode
    let workMinutes: Int
    let restMinutes: Int
    let rationale: String
    let dailySchedule: String
}

struct ScreenScrollWindow: Codable, Identifiable {
    let id: String
    let title: String
    let startHour: Int
    let endHour: Int
    let minutes: Int
    let reason: String
}

struct ScreenTimeReductionPlan: Codable, Identifiable {
    let id: String
    let collecting: Bool
    let daysCollected: Int
    let daysNeeded: Int
    let dayIndex: Int
    let baselineMinutes: Int
    let targetMinutes: Int
    let strictnessPercent: Int
    let summary: String
    let decisionReason: String
    let windows: [ScreenScrollWindow]
}
