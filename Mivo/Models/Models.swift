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
    var displayName: String {
        switch self {
        case .worthIt: return "Worth it"
        case .mixed: return "Partly worth it"
        case .notWorthIt: return "Not worth it"
        }
    }
}

enum WeeklyExperimentType: String, Codable, CaseIterable {
    case protectedWindow = "protected_window"
    case reduceExtensions = "reduce_extensions"
    case strongerFriction = "stronger_friction"
}

enum WeeklyExperimentStatus: String, Codable {
    case proposed
    case active
    case completed
    case declined
}

enum WeeklyExperimentOutcome: String, Codable {
    case helped
    case inconclusive = "no_clear_change"
    case worsened = "made_things_worse"
}

enum WeeklyExperimentDecision: String, Codable {
    case keep
    case adjust
    case stop
}

enum WeeklyExperimentFeedback: String, Codable, CaseIterable, Identifiable {
    case helpful
    case neutral
    case notHelpful = "not_helpful"

    var id: String { rawValue }
}

struct ExperimentMetrics: Codable, Equatable {
    let comparableSessions: Int
    let outsideWindowMinutes: Int
    let extensionRate: Double
    let cancellationRate: Double
    let truthAccuracyMinutes: Double
    let worthwhileRate: Double
}

struct WeeklyExperimentRule: Codable, Equatable {
    var startHour: Int?
    var endHour: Int?
    var allowedMinutes: Int?
    var strongerFrictionEnabled: Bool
}

struct WeeklyExperiment: Codable, Identifiable, Equatable {
    let id: String
    let userId: String?
    let type: WeeklyExperimentType
    var status: WeeklyExperimentStatus
    let title: String
    let reason: String
    let primaryMetric: String
    var rule: WeeklyExperimentRule
    let baselineMetrics: ExperimentMetrics
    var resultMetrics: ExperimentMetrics?
    var startsAt: String?
    var endsAt: String?
    var outcome: WeeklyExperimentOutcome?
    var finalDecision: WeeklyExperimentDecision?
    var userFeedback: WeeklyExperimentFeedback? = nil
    var feedbackNote: String? = nil
    var feedbackSubmittedAt: String? = nil
    let createdAt: String
    var updatedAt: String

    var dayNumber: Int {
        dayNumber(on: Date())
    }

    func dayNumber(on date: Date, calendar: Calendar = .current) -> Int {
        guard let startsAt, let start = Self.experimentDate(from: startsAt) else { return 0 }
        let startDay = calendar.startOfDay(for: start)
        let currentDay = calendar.startOfDay(for: date)
        let elapsedCalendarDays = calendar.dateComponents([.day], from: startDay, to: currentDay).day ?? 0
        return min(7, max(1, elapsedCalendarDays + 1))
    }

    func progress(on date: Date = Date(), calendar: Calendar = .current) -> Double {
        guard status == .active else { return status == .completed ? 1 : 0 }
        return Double(dayNumber(on: date, calendar: calendar)) / 7.0
    }

    static func experimentDate(from value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value) {
            return date
        }

        // Supabase can return microsecond precision and an explicit +00:00 offset.
        // DateFormatter covers those PostgreSQL timestamp variants on older iOS builds.
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        for format in [
            "yyyy-MM-dd'T'HH:mm:ss.SSSSSSXXXXX",
            "yyyy-MM-dd'T'HH:mm:ss.SSSXXXXX",
            "yyyy-MM-dd'T'HH:mm:ssXXXXX"
        ] {
            formatter.dateFormat = format
            if let date = formatter.date(from: value) { return date }
        }
        return nil
    }
}

struct WeeklyExperimentEnforcementPolicy: Equatable {
    let experimentID: String?
    let type: WeeklyExperimentType?
    let rule: WeeklyExperimentRule?

    init(experiment: WeeklyExperiment?) {
        experimentID = experiment?.id
        type = experiment?.type
        rule = experiment?.rule
    }

    var blocksExtensions: Bool {
        type == .reduceExtensions
    }

    var strengthensRepeatedOpenings: Bool {
        type == .strongerFriction && rule?.strongerFrictionEnabled == true
    }

    func protects(hour: Int) -> Bool {
        guard type == .protectedWindow,
              let startHour = rule?.startHour,
              let endHour = rule?.endHour else { return false }
        let start = ((startHour % 24) + 24) % 24
        let end = ((endHour % 24) + 24) % 24
        let current = ((hour % 24) + 24) % 24
        if start == end { return true }
        return start < end
            ? (current >= start && current < end)
            : (current >= start || current < end)
    }
}

struct InterventionAttemptRecord: Codable, Identifiable, Equatable {
    let id: String
    let occurredAt: String
    var continued: Bool?
}

struct InterventionFrictionState: Equatable {
    let level: Int
    let attemptCount: Int
    let waitSeconds: Int
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
    let checkedAt: String?
    let perAppMinutes: [String: Int]?

    init(
        id: String,
        date: String,
        guess: Int,
        actual: Int,
        checkedAt: String? = nil,
        perAppMinutes: [String: Int]? = nil
    ) {
        self.id = id
        self.date = date
        self.guess = guess
        self.actual = actual
        self.checkedAt = checkedAt
        self.perAppMinutes = perAppMinutes
    }
}

struct DailyScreenTimeObservation: Codable, Identifiable, Equatable {
    var id: String { date }
    let date: String
    let minutes: Int
    let recordedAt: String
}

struct ForgottenTimeSlice: Identifiable, Equatable {
    let appName: String
    let minutes: Int
    let share: Double
    var id: String { appName }
}

struct PersonalizedPatternInsight: Identifiable, Equatable {
    let id: String
    let title: String
    let detail: String
    let evidence: String
    let tomorrowExperiment: String
    let icon: String
}

struct DailyTruthSummary {
    let check: TruthCheckGuess
    let accuracyScore: Int
    let forgottenMinutes: Int
    let overestimatedMinutes: Int
    let forgottenBreakdown: [ForgottenTimeSlice]
    let insight: PersonalizedPatternInsight
}

struct WeeklyTruthSummary {
    let checkCount: Int
    let averageAccuracyScore: Int
    let totalForgottenMinutes: Int
    let averageSignedGapMinutes: Int
    let accuracyChangePoints: Int?
    let topForgottenApp: String?
    let dailyAccuracyScores: [(date: String, score: Int)]
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
    var accountRole: String? = nil
}

enum AppAppearanceMode: String, Codable, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
}

struct AppSettings: Codable {
    var onboardingComplete: Bool
    var notificationsEnabled: Bool
    var tutorialComplete: Bool? = nil
    var notificationsChoiceMade: Bool? = nil
    var accountabilityEnabled: Bool? = nil
    var checkInIntervalMinutes: Int? = nil
    var lateNightProtectionEnabled: Bool? = nil
    var lateNightStartHour: Int? = nil
    var lateNightWakeHour: Int? = nil
    var lastScrollNightKey: String? = nil
    var appearanceMode: AppAppearanceMode? = nil
}

struct OnboardingProfile: Codable {
    var observationStartedAt: String?
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
    var referralCode: String?
    var referralSource: String?
    var referralAmbassadorName: String?
    /// The user's target daily scrolling minutes — the floor that the
    /// personalized plan ramps down to from the blended observed baseline.
    var dailyScrollGoalMinutes: Int?

    init(primaryIntention: Intention? = nil, scrollEstimateMinutes: Int? = nil, preferredApps: [String] = [], preferredScrollWindows: [ScreenScrollWindow]? = nil) {
        self.observationStartedAt = nil
        self.primaryIntention = primaryIntention
        self.scrollEstimateMinutes = scrollEstimateMinutes
        self.preferredApps = preferredApps
        self.preferredScrollWindows = preferredScrollWindows
        self.intentions = []
        self.age = nil
        self.ageRange = nil
        self.checkInIntervalMinutes = nil
        self.referralCode = nil
        self.referralSource = nil
        self.referralAmbassadorName = nil
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

struct EmergencyUnlockReview: Equatable {
    let approved: Bool
    let message: String
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

/// The one place that turns a `Date` into the `yyyy-MM-dd` key every stored
/// record is filed under.
///
/// A plain `DateFormatter` renders `yyyy` using whatever calendar the device is
/// set to, so the same instant becomes "2026-08-03" on a Gregorian device and
/// "2569-08-03" on a Buddhist one. Mivo writes day keys from sessions, screen
/// time observations, schedules, and experiments, then matches them by string,
/// so a mismatch between two call sites makes records disappear from Patterns
/// and skews report totals instead of failing loudly. Going through a fixed
/// Gregorian calendar keeps every key comparable regardless of device settings.
enum MivoDay {
    /// Gregorian, pinned to the device's current time zone so a day boundary
    /// still means midnight where the user actually is.
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar
    }

    static func key(_ date: Date) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    static func date(from key: String) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var components = DateComponents()
        components.year = parts[0]
        components.month = parts[1]
        components.day = parts[2]
        return calendar.date(from: components)
    }

    static var todayKey: String { key(Date()) }

    /// A `DateFormatter` producing exactly the same keys as `key(_:)`, for call
    /// sites that format in a loop or need `date(from:)` parsing. A fresh
    /// instance each time, since `DateFormatter` is not thread-safe.
    static var formatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }

    static func key(offsetFromToday days: Int, from reference: Date = Date()) -> String {
        key(calendar.date(byAdding: .day, value: days, to: reference) ?? reference)
    }

    /// Whole days from `key` to today, or nil when the key is unparseable.
    static func daysSince(_ key: String, now: Date = Date()) -> Int? {
        guard let start = date(from: key) else { return nil }
        return calendar.dateComponents([.day], from: start, to: calendar.startOfDay(for: now)).day
    }
}

/// Why a number Mivo would normally show cannot be trusted right now.
///
/// Mivo's headline figures come from Apple's DeviceActivity report, which is
/// absent before authorization, before the first report lands, and whenever the
/// extension hands back a report for a different day. Substituting Mivo's own
/// in-app session minutes in those moments produces a much smaller number that
/// looks authoritative, which is worse than admitting the gap.
enum MivoDataUnavailableReason: String, Codable, Equatable {
    case screenTimeNotAuthorized
    case awaitingFirstReport
    case reportFromAnotherDay

    var title: String { "Data unavailable" }

    var detail: String {
        switch self {
        case .screenTimeNotAuthorized:
            return "Screen Time access is off, so Mivo cannot read your real usage."
        case .awaitingFirstReport:
            return "Apple has not delivered today's Screen Time report yet."
        case .reportFromAnotherDay:
            return "The most recent Screen Time report is from another day."
        }
    }

    var recoveryAction: String? {
        switch self {
        case .screenTimeNotAuthorized: return "Turn on Screen Time"
        case .awaitingFirstReport, .reportFromAnotherDay: return "Refresh"
        }
    }
}

/// A measurement that is either trustworthy or explicitly missing. Callers must
/// handle both, which is what stops a fallback from quietly becoming a fact.
enum MivoMeasurement: Equatable {
    case available(Int)
    case unavailable(MivoDataUnavailableReason)

    var minutes: Int? {
        if case .available(let value) = self { return value }
        return nil
    }

    var reason: MivoDataUnavailableReason? {
        if case .unavailable(let reason) = self { return reason }
        return nil
    }

    var isAvailable: Bool { minutes != nil }
}
