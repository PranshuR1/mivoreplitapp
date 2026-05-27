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
    let approvedSeconds: Int
    let startTime: String
    let expiresAt: String
    let expiredAt: String?
    let expirationSource: String?
    let state: MivoSessionState
    let accumulatedElapsedSeconds: Int
    let urgeReason: UrgeReason?
    let urgeNote: String?
    let extendedOnce: Bool
    let emergencyUnlockUsed: Bool?
    let emergencyUnlockReason: String?

    init(
        id: String,
        intention: Intention,
        plannedDuration: Int,
        plannedSeconds: Int,
        approvedSeconds: Int? = nil,
        startTime: String,
        expiresAt: String? = nil,
        expiredAt: String? = nil,
        expirationSource: String? = nil,
        state: MivoSessionState = .active,
        accumulatedElapsedSeconds: Int = 0,
        urgeReason: UrgeReason?,
        urgeNote: String?,
        extendedOnce: Bool,
        emergencyUnlockUsed: Bool?,
        emergencyUnlockReason: String?
    ) {
        self.id = id
        self.intention = intention
        self.plannedDuration = plannedDuration
        self.plannedSeconds = plannedSeconds
        self.approvedSeconds = approvedSeconds ?? plannedSeconds
        self.startTime = startTime
        if let expiresAt {
            self.expiresAt = expiresAt
        } else if let startDate = ISO8601DateFormatter().date(from: startTime) {
            self.expiresAt = ISO8601DateFormatter().string(from: startDate.addingTimeInterval(TimeInterval(approvedSeconds ?? plannedSeconds)))
        } else {
            self.expiresAt = startTime
        }
        self.expiredAt = expiredAt
        self.expirationSource = expirationSource
        self.state = state
        self.accumulatedElapsedSeconds = accumulatedElapsedSeconds
        self.urgeReason = urgeReason
        self.urgeNote = urgeNote
        self.extendedOnce = extendedOnce
        self.emergencyUnlockUsed = emergencyUnlockUsed
        self.emergencyUnlockReason = emergencyUnlockReason
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case intention
        case plannedDuration
        case plannedSeconds
        case approvedSeconds
        case startTime
        case expiresAt
        case expiredAt
        case expirationSource
        case state
        case accumulatedElapsedSeconds
        case urgeReason
        case urgeNote
        case extendedOnce
        case emergencyUnlockUsed
        case emergencyUnlockReason
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        intention = try container.decode(Intention.self, forKey: .intention)
        plannedDuration = try container.decode(Int.self, forKey: .plannedDuration)
        plannedSeconds = try container.decode(Int.self, forKey: .plannedSeconds)
        approvedSeconds = try container.decodeIfPresent(Int.self, forKey: .approvedSeconds) ?? plannedSeconds
        startTime = try container.decode(String.self, forKey: .startTime)
        if let storedExpiresAt = try container.decodeIfPresent(String.self, forKey: .expiresAt) {
            expiresAt = storedExpiresAt
        } else if let startDate = ISO8601DateFormatter().date(from: startTime) {
            expiresAt = ISO8601DateFormatter().string(from: startDate.addingTimeInterval(TimeInterval(approvedSeconds)))
        } else {
            expiresAt = startTime
        }
        expiredAt = try container.decodeIfPresent(String.self, forKey: .expiredAt)
        expirationSource = try container.decodeIfPresent(String.self, forKey: .expirationSource)
        state = try container.decodeIfPresent(MivoSessionState.self, forKey: .state) ?? .active
        accumulatedElapsedSeconds = try container.decodeIfPresent(Int.self, forKey: .accumulatedElapsedSeconds) ?? 0
        urgeReason = try container.decodeIfPresent(UrgeReason.self, forKey: .urgeReason)
        urgeNote = try container.decodeIfPresent(String.self, forKey: .urgeNote)
        extendedOnce = try container.decode(Bool.self, forKey: .extendedOnce)
        emergencyUnlockUsed = try container.decodeIfPresent(Bool.self, forKey: .emergencyUnlockUsed)
        emergencyUnlockReason = try container.decodeIfPresent(String.self, forKey: .emergencyUnlockReason)
    }
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

struct DailyScrollSchedule: Codable, Identifiable, Equatable {
    let id: String
    let date: String
    let windows: [ScreenScrollWindow]
    let createdAt: String
}

struct DailyScrollSchedulePrompt: Identifiable, Equatable {
    let id: String
    let date: String
    let recommendedWindows: [ScreenScrollWindow]
    let isRecommendationReady: Bool
    let scheduledHour: Int
    let scheduledMinute: Int
}

/// One-time prompt shown after the 3-day observation completes: tells the user
/// how many days until their personalized plan reaches their daily scroll goal.
struct GoalForecastPrompt: Identifiable, Equatable {
    let id: String
    let observationAverageMinutes: Int
    let goalMinutes: Int
    let daysToReachGoal: Int
    let firstPlanDayTarget: Int
    let oneWeekTarget: Int
    let twoWeekTarget: Int
    let createdAt: String
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
    var checkInIntervalMinutes: Int? = nil
}

struct OnboardingProfile: Codable {
    var primaryIntention: Intention?
    var scrollEstimateMinutes: Int?
    var preferredApps: [String]
    var preferredScrollWindows: [ScreenScrollWindow]?
    // allow multiple intentions to be stored from onboarding
    var intentions: [Intention]
    // optional demographic details
    var age: Int?
    var ageRange: String?
    var checkInIntervalMinutes: Int?
    /// The user's target daily scrolling minutes — the floor that the
    /// personalized plan ramps down to from the observation average.
    var dailyScrollGoalMinutes: Int?

    init(primaryIntention: Intention? = nil, scrollEstimateMinutes: Int? = nil, preferredApps: [String] = [], preferredScrollWindows: [ScreenScrollWindow]? = nil) {
        self.primaryIntention = primaryIntention
        self.scrollEstimateMinutes = scrollEstimateMinutes
        self.preferredApps = preferredApps
        self.preferredScrollWindows = preferredScrollWindows
        self.intentions = []
        self.age = nil
        self.ageRange = nil
        self.checkInIntervalMinutes = nil
        self.dailyScrollGoalMinutes = nil
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

struct ScreenScrollWindow: Codable, Identifiable, Equatable {
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
