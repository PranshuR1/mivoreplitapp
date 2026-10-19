import Foundation

// MARK: - Types

enum Intention: String, Codable, CaseIterable {
    case killTime = "Kill time"
    case relax = "Relax"
    case bored = "Bored"
    case lookingForSomethingSpecific = "Looking for something specific"
    /// Added for the v2 intervention flow's reason step. The raw value is the
    /// storage key and must not change; `flowLabel` below carries the
    /// screen copy so existing raw values (and the historical sessions
    /// already saved under them) don't need to move to stay accurate.
    case replyingToSomeone = "Replying to someone"
    case postingSomething = "Posting something"

    /// The five reason-step options from the v2 design, in the handoff's
    /// order. `killTime` predates that step and is intentionally left out of
    /// it, but still decodes fine wherever an older session referenced it.
    static let flowOptions: [Intention] = [
        .replyingToSomeone, .lookingForSomethingSpecific, .postingSomething, .relax, .bored
    ]

    var flowLabel: String {
        switch self {
        case .lookingForSomethingSpecific: return "Looking something up"
        case .relax: return "Taking a break"
        case .bored: return "Just bored"
        default: return rawValue
        }
    }
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

/// One "what did you just watch?" prompt, asked mid-scroll (see
/// `MidScrollCheckInView`'s recall step) rather than at the end of the day —
/// unlike `TruthCheckGuess` (one guess-vs-actual-minutes check per day), this
/// is a log of many small moments, each capturing what the person *thinks*
/// they just consumed while it's still fresh, so the Attention Receipt can
/// show the gap between that guess and reality without needing any usage
/// telemetry iOS doesn't expose (there is no scroll-count API — see the
/// receipt's real data sources: `AppViewModel.todayPerAppMinutes()` for time,
/// this array for recall).
struct RecallCheckIn: Codable, Identifiable {
    let id: String
    let date: String
    /// Best-effort — the ShieldAction extension reads `Application(token:)`'s
    /// `localizedDisplayName` when it fires the check-in; can be nil.
    let appName: String?
    let guessedCount: Int
    let recalledText: String
    let checkedAt: String

    var recalledSomething: Bool {
        !recalledText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// A real, exact scroll count from one `InstagramWrapperView` session —
/// unlike `RecallCheckIn` (a self-reported guess), this is measured: the
/// wrapper owns the WKWebView Instagram's mobile site renders into, so it
/// can listen for real scroll events the way no view over the native app
/// ever could. Only exists for sessions that went through the wrapper —
/// using the native Instagram app directly still produces zero data, same
/// as always.
/// Everything `InstagramWrapperView` can genuinely measure from owning the
/// WKWebView — real DOM/media events, nothing inferred or guessed. Fields
/// added after the first version use `decodeIfPresent(...) ?? 0` so older
/// locally-stored sessions (missing the newer keys) still decode instead of
/// silently vanishing.
struct InstagramWrapperSession: Codable, Identifiable {
    let id: String
    let date: String
    let startedAt: String
    let endedAt: String
    /// Distinct scroll bursts — the original measured count.
    let scrollCount: Int
    /// Real `<video>` `play` events — the closest thing to an actual "reels
    /// watched" count, since Instagram's mobile reels render as `<video>`
    /// elements Mivo's script can listen to directly.
    let videoPlayCount: Int
    /// Cumulative seconds any video spent actually playing (sum of
    /// play→pause/ended intervals), not just "time the screen was open."
    let videoWatchSeconds: Int
    /// Real `click` events — taps distinct from scroll gestures (likes,
    /// opens, button presses).
    let tapCount: Int
    /// Total scroll distance in points, summed across every scroll delta.
    let scrollDistancePoints: Int
    /// Distinct in-app navigations (feed → profile → search, etc.), counted
    /// via `history.pushState`/`popstate` — Instagram's mobile site is a
    /// single-page app, so this is the real proxy for "how many different
    /// places did you go," not a guess.
    let sectionChanges: Int
    /// The longest gap, in seconds, between two consecutive scroll bursts —
    /// the longest single stretch of not-scrolling during the session.
    let longestPauseSeconds: Int
    /// Seconds between the page loading and the first scroll — how long
    /// before they actually started engaging.
    let firstScrollDelaySeconds: Int

    enum CodingKeys: String, CodingKey {
        case id, date, startedAt, endedAt, scrollCount
        case videoPlayCount, videoWatchSeconds, tapCount
        case scrollDistancePoints, sectionChanges
        case longestPauseSeconds, firstScrollDelaySeconds
    }

    init(
        id: String,
        date: String,
        startedAt: String,
        endedAt: String,
        scrollCount: Int,
        videoPlayCount: Int = 0,
        videoWatchSeconds: Int = 0,
        tapCount: Int = 0,
        scrollDistancePoints: Int = 0,
        sectionChanges: Int = 0,
        longestPauseSeconds: Int = 0,
        firstScrollDelaySeconds: Int = 0
    ) {
        self.id = id
        self.date = date
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.scrollCount = scrollCount
        self.videoPlayCount = videoPlayCount
        self.videoWatchSeconds = videoWatchSeconds
        self.tapCount = tapCount
        self.scrollDistancePoints = scrollDistancePoints
        self.sectionChanges = sectionChanges
        self.longestPauseSeconds = longestPauseSeconds
        self.firstScrollDelaySeconds = firstScrollDelaySeconds
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        date = try container.decode(String.self, forKey: .date)
        startedAt = try container.decode(String.self, forKey: .startedAt)
        endedAt = try container.decode(String.self, forKey: .endedAt)
        scrollCount = try container.decode(Int.self, forKey: .scrollCount)
        videoPlayCount = try container.decodeIfPresent(Int.self, forKey: .videoPlayCount) ?? 0
        videoWatchSeconds = try container.decodeIfPresent(Int.self, forKey: .videoWatchSeconds) ?? 0
        tapCount = try container.decodeIfPresent(Int.self, forKey: .tapCount) ?? 0
        scrollDistancePoints = try container.decodeIfPresent(Int.self, forKey: .scrollDistancePoints) ?? 0
        sectionChanges = try container.decodeIfPresent(Int.self, forKey: .sectionChanges) ?? 0
        longestPauseSeconds = try container.decodeIfPresent(Int.self, forKey: .longestPauseSeconds) ?? 0
        firstScrollDelaySeconds = try container.decodeIfPresent(Int.self, forKey: .firstScrollDelaySeconds) ?? 0
    }
}

/// One "what was on screen N reels ago?" prompt, fired periodically *during*
/// an `InstagramWrapperView` session (as opposed to `RecallCheckIn`, which
/// fires once when a check-in ends a session). `scrollsAgo` is real — it's
/// how many measured scrolls back the question refers to, not a guess.
struct InstagramRecallPrompt: Codable, Identifiable {
    let id: String
    let date: String
    let scrollsAgo: Int
    let answer: String
    let checkedAt: String

    var recalledSomething: Bool {
        !answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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

/// Asks an existing user to pick the daily target that onboarding failed to
/// save for them.
struct ScrollGoalPrompt: Identifiable, Equatable {
    let id: String
    /// Their measured baseline when one exists, so the options can be framed
    /// against reality instead of an arbitrary list.
    let baselineMinutes: Int?
    let options: [Int]
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

/// Today's Mac activity, aggregated client-side by
/// `RemoteAuthService.fetchMacActivitySummary` from the raw
/// `mac_activity_records`/`mac_focus_sessions` rows Mivo for Mac syncs.
struct MacActivitySummary {
    struct AppUsage: Identifiable {
        let name: String
        let minutes: Int
        var id: String { name }
    }

    let totalMinutes: Int
    let focusMinutes: Int
    let driftMinutes: Int
    let topApps: [AppUsage]
    let focusSessionsToday: Int
}

struct WidgetSharedSummary: Codable {
    let recoveredMinutesToday: Int
    let screenTimeMinutesToday: Int?
    let nextScrollWindow: String
    let planState: String
    let streakText: String
    let updatedAt: String
    /// Added for the Mac companion app's pairing feature, which needs a
    /// minimum iPhone version — optional so older, already-persisted
    /// summaries (written before this field existed) still decode.
    let appVersion: String?
    /// Today's Mivo Still minutes — the closest thing this app tracks to a
    /// literal "focused time" number, since Mivo Still is the one feature
    /// that's actually named and framed around focusing (phone face-down),
    /// rather than a proxy like recovered-vs-baseline. Optional for the
    /// same already-persisted-data reason as `appVersion` above.
    let focusedMinutesToday: Int?

    init(
        recoveredMinutesToday: Int,
        screenTimeMinutesToday: Int?,
        nextScrollWindow: String,
        planState: String,
        streakText: String,
        updatedAt: String,
        appVersion: String? = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
        focusedMinutesToday: Int? = nil
    ) {
        self.recoveredMinutesToday = recoveredMinutesToday
        self.screenTimeMinutesToday = screenTimeMinutesToday
        self.nextScrollWindow = nextScrollWindow
        self.planState = planState
        self.streakText = streakText
        self.updatedAt = updatedAt
        self.appVersion = appVersion
        self.focusedMinutesToday = focusedMinutesToday
    }
}

struct UserProfile: Codable {
    let email: String
    var name: String
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

/// How much friction sits between opening a protected app and using it.
enum PauseStyle: String, Codable, CaseIterable, Identifiable {
    case fiveSecond = "five_second"
    case tenSecond = "ten_second"
    case askReason = "ask_reason"
    case countOnly = "count_only"

    var id: String { rawValue }

    /// Seconds the pause screen holds before the app can be opened.
    var waitSeconds: Int {
        switch self {
        case .fiveSecond: return 5
        case .tenSecond: return 10
        case .askReason: return 10
        case .countOnly: return 0
        }
    }

    /// Whether Mivo asks what the user came to do before letting them through.
    var asksReason: Bool { self == .askReason }
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
    var referralSource: String?
    /// The user's target daily scrolling minutes — the floor that the
    /// personalized plan ramps down to from the blended observed baseline.
    var dailyScrollGoalMinutes: Int?

    /// How hard Mivo should push back when a protected app is opened. Chosen in
    /// onboarding and read by `interventionFrictionState`, so the answer changes
    /// real behaviour rather than only being recorded.
    var pauseStyle: PauseStyle?

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
        self.referralSource = nil
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

/// One-time repair for day keys written before `MivoDay` existed.
///
/// Those keys came from `DateFormatter`s that inherited the device calendar, so
/// the same instant was stored as `2026-07-25` on a Gregorian device but
/// `2569-07-25` on a Buddhist one, `0008-07-25` on Japanese, and `1405-05-03`
/// on Persian — and under some locales with non-Latin digits. Now that every
/// key is read back as Gregorian, those records would simply stop matching and
/// the user's history would vanish from Patterns and their reports. This
/// rewrites them in place, once.
enum MivoDayKeyRepair {
    /// Years Mivo could plausibly hold data for. Anything outside this was
    /// written under a different calendar.
    private static let plausibleYears = 2015...2100

    static func needsRepair(_ key: String) -> Bool {
        let parts = key.split(separator: "-")
        guard parts.count == 3, let year = Int(parts[0]) else {
            // Non-numeric, e.g. a locale that rendered non-Latin digits.
            return true
        }
        return !plausibleYears.contains(year)
    }

    /// The canonical key for a record, or nil when it is already correct or
    /// cannot be recovered safely.
    ///
    /// - Parameter timestamp: an unambiguous ISO-8601 instant from the same
    ///   record, when one exists that is guaranteed to fall on the same day.
    ///   Omitted for records whose timestamp can legitimately differ from the
    ///   day they describe, such as an observation written after midnight.
    static func repairedKey(for key: String, timestamp: String? = nil) -> String? {
        guard needsRepair(key) else { return nil }

        if let timestamp, let date = isoDate(from: timestamp) {
            return MivoDay.key(date)
        }

        // Otherwise read the key back with the calendar that wrote it. This is
        // exact while the device calendar is unchanged, and the plausibility
        // check below rejects the result if it is not.
        guard let date = deviceFormatter.date(from: key) else { return nil }
        let repaired = MivoDay.key(date)
        guard !needsRepair(repaired) else { return nil }
        return repaired
    }

    private static var deviceFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = Calendar.current
        formatter.locale = Locale.current
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }

    private static func isoDate(from value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }
}

extension Session {
    /// A copy filed under the canonical day key, or nil when no change is needed.
    func repairingDayKey() -> Session? {
        guard let repaired = MivoDayKeyRepair.repairedKey(for: date, timestamp: startTime) else {
            return nil
        }
        return Session(
            id: id, date: repaired, startTime: startTime, endTime: endTime,
            plannedDuration: plannedDuration, actualDuration: actualDuration,
            intention: intention, extendedOnce: extendedOnce, reflection: reflection,
            reflectionNote: reflectionNote, urgeReason: urgeReason, urgeNote: urgeNote,
            outcomeScore: outcomeScore, emergencyUnlockUsed: emergencyUnlockUsed,
            emergencyUnlockReason: emergencyUnlockReason
        )
    }
}

extension TruthCheckGuess {
    func repairingDayKey() -> TruthCheckGuess? {
        // `checkedAt` is stamped when the guess is made, which is always the
        // day the guess is about, so it is a safe source.
        guard let repaired = MivoDayKeyRepair.repairedKey(for: date, timestamp: checkedAt) else {
            return nil
        }
        return TruthCheckGuess(
            id: id, date: repaired, guess: guess, actual: actual,
            checkedAt: checkedAt, perAppMinutes: perAppMinutes
        )
    }
}

extension DailyScreenTimeObservation {
    func repairingDayKey() -> DailyScreenTimeObservation? {
        // No timestamp is passed: `recordedAt` can land on the following day
        // when a report arrives just after midnight, so it cannot stand in for
        // the day being observed.
        guard let repaired = MivoDayKeyRepair.repairedKey(for: date) else { return nil }
        return DailyScreenTimeObservation(date: repaired, minutes: minutes, recordedAt: recordedAt)
    }
}

extension DailyScrollSchedule {
    func repairingDayKey() -> DailyScrollSchedule? {
        guard let repaired = MivoDayKeyRepair.repairedKey(for: date) else { return nil }
        return DailyScrollSchedule(id: id, date: repaired, windows: windows, createdAt: createdAt)
    }
}
