import Foundation

// MARK: - Why someone stopped

/// Why a lapsed user says they stopped. Optional and never required: it only
/// picks the gentlest sensible starting pace and the line Mivo answers with.
enum ComebackLapseReason: String, Codable, CaseIterable, Identifiable {
    case lostMotivation = "lost_motivation"
    case tooStrict = "too_strict"
    case forgot
    case busy
    case other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .lostMotivation: return "I lost motivation"
        case .tooStrict: return "The plan felt too strict"
        case .forgot: return "I just forgot about it"
        case .busy: return "Life got busy"
        case .other: return "Something else"
        }
    }

    /// The reply shown once a reason is picked — never about willpower.
    var acknowledgement: String {
        switch self {
        case .lostMotivation:
            return "That happens to nearly everyone. We'll start small so the first few days are easy wins."
        case .tooStrict:
            return "Fair. This time the plan starts from where you actually are, not where the old one had climbed to."
        case .forgot:
            return "Easy to do. Mivo can nudge you if things go quiet again."
        case .busy:
            return "Then the plan should be light. Start gentle and tighten it only if you want to."
        case .other:
            return "No need to explain. Let's reset from today."
        }
    }

    var suggestedPace: ComebackPace {
        switch self {
        case .lostMotivation, .tooStrict, .busy: return .easeBack
        case .forgot, .other: return .steady
        }
    }
}

// MARK: - Pace

/// How hard the fresh start leans. Every pace begins at or below what the
/// person is doing today, so day one is always achievable.
enum ComebackPace: String, Codable, CaseIterable, Identifiable {
    case easeBack = "ease_back"
    case steady
    case stretch

    var id: String { rawValue }

    var title: String {
        switch self {
        case .easeBack: return "Ease back in"
        case .steady: return "Steady"
        case .stretch: return "Stretch me"
        }
    }

    /// Share of the baseline cut from the very first day.
    var openingCut: Double {
        switch self {
        case .easeBack: return 0
        case .steady: return 0.10
        case .stretch: return 0.20
        }
    }

    /// Minutes the target drops each day after the first.
    var dailyStepMinutes: Int {
        switch self {
        case .easeBack: return 2
        case .steady: return 3
        case .stretch: return 4
        }
    }
}

// MARK: - Anchor

/// The fresh starting point that replaces the calendar-based ramp.
///
/// The normal plan counts days from when observation finished, so someone who
/// stays away for weeks returns to a target ground down far below what they
/// actually do. That mismatch is the reason people don't come back. The anchor
/// restarts the count: day one is today, at a target set from current usage.
struct ComebackAnchor: Codable, Equatable {
    /// `MivoDay` key for plan day one.
    var startDay: String
    /// What the plan treats as "usual" usage, and where that came from.
    var baselineMinutes: Int
    var baselineSource: ComebackBaseline.Source
    /// Target on day one; each later day drops by `dailyStepMinutes`.
    var startMinutes: Int
    var dailyStepMinutes: Int
    var pace: ComebackPace
    var reason: ComebackLapseReason?
    /// Days away when the user restarted. Zero for a voluntary restart.
    var lapseDays: Int
    var why: String?
    var nudgesEnabled: Bool
    var createdAt: String
}

// MARK: - Baseline

/// A usage figure together with where it came from, so the screen never
/// presents an old or self-reported number as a fresh measurement.
struct ComebackBaseline: Equatable {
    enum Source: Codable, Equatable {
        /// Average of measured days from the last two weeks.
        case recentDays(Int)
        /// Measured days, but all older than two weeks.
        case lastMeasuredDays(Int, lastDay: String)
        /// The estimate given during setup.
        case setupEstimate
        /// Typed in during the comeback itself.
        case selfReported
    }

    let minutes: Int
    let source: Source

    var caption: String {
        switch source {
        case .recentDays(let count):
            return "Average of your last \(count) measured day\(count == 1 ? "" : "s")."
        case .lastMeasuredDays(let count, let lastDay):
            return "Average of your last \(count) measured day\(count == 1 ? "" : "s"), ending \(MivoComeback.shortDate(lastDay)). Mivo has no newer data."
        case .setupEstimate:
            return "Your estimate from setup. Mivo has no measured days to use."
        case .selfReported:
            return "Your estimate for a typical day."
        }
    }
}

// MARK: - Prompt / state

/// Everything the flow screen needs, resolved once when it is presented.
struct ComebackPrompt: Identifiable, Equatable {
    let id: String
    /// Whole days since the app was last active. Zero for a manual restart.
    let lapseDays: Int
    let isManual: Bool
    let baseline: ComebackBaseline?
    /// Lowest measured day on record, if three or more days exist.
    let lowestDay: DailyScreenTimeObservation?
    /// The daily goal the plan ramps toward.
    let floorMinutes: Int
}

/// Persisted record of a detected lapse that has not yet been resolved.
struct ComebackLapseRecord: Codable, Equatable {
    enum Status: String, Codable {
        /// The prompt still has to be shown (or was interrupted).
        case pending
        /// The user said "not now"; Home keeps a quiet restart row.
        case snoozed
    }

    var lastActiveDay: String
    var detectedDay: String
    var lapseDays: Int
    var status: Status
}

// MARK: - Engine

/// Pure rules for lapse detection and the restart ramp. No storage, clocks, or
/// UI — dates come in as `MivoDay` keys so every threshold is testable.
enum MivoComeback {
    /// Days away before Mivo offers a fresh start. Short enough to catch a
    /// stalled habit, long enough that a weekend off doesn't trigger it.
    static let lapseThresholdDays = 3
    /// How long Home shows the fresh-start card.
    static let cardDays = 7
    /// How long a snoozed restart row stays on Home.
    static let snoozeVisibleDays = 14
    /// Days after the last open at which a gentle nudge is scheduled.
    static let nudgeDays = [3, 7, 14]

    static let measuredWindowDays = 14
    static let maxAveragedDays = 7

    /// Whole days between `lastActiveDay` and `today`, or nil when the key is
    /// missing or unparseable.
    static func lapseDays(lastActiveDay: String?, today: String) -> Int? {
        guard let lastActiveDay,
              let last = MivoDay.date(from: lastActiveDay),
              let now = MivoDay.date(from: today) else { return nil }
        return max(0, MivoDay.calendar.dateComponents([.day], from: last, to: now).day ?? 0)
    }

    static func isLapsed(lastActiveDay: String?, today: String) -> Bool {
        (lapseDays(lastActiveDay: lastActiveDay, today: today) ?? 0) >= lapseThresholdDays
    }

    /// The newest of the supplied day keys; keys that don't parse are ignored.
    static func latestDay(_ keys: [String]) -> String? {
        keys.filter { MivoDay.date(from: $0) != nil }.max()
    }

    /// Usual daily usage for a returning user, built only from real days.
    ///
    /// Today is excluded because it is still in progress, and zero-minute days
    /// are excluded because a zero here means a report never landed, not a day
    /// of no scrolling.
    static func baseline(
        observations: [DailyScreenTimeObservation],
        setupEstimate: Int?,
        today: String
    ) -> ComebackBaseline? {
        let measured = observations
            .filter { $0.date != today && $0.minutes > 0 && MivoDay.date(from: $0.date) != nil }
            .sorted { $0.date > $1.date }

        let windowStart = MivoDay.key(offsetFromToday: -measuredWindowDays, from: MivoDay.date(from: today) ?? Date())
        let recent = measured.filter { $0.date >= windowStart }
        if recent.count >= 2 {
            let used = Array(recent.prefix(maxAveragedDays))
            return ComebackBaseline(minutes: average(used.map(\.minutes)), source: .recentDays(used.count))
        }

        if let newest = measured.first {
            let used = Array(measured.prefix(3))
            return ComebackBaseline(
                minutes: average(used.map(\.minutes)),
                source: .lastMeasuredDays(used.count, lastDay: newest.date)
            )
        }

        if let setupEstimate, setupEstimate > 0 {
            return ComebackBaseline(minutes: setupEstimate, source: .setupEstimate)
        }
        return nil
    }

    /// The lowest measured day on record — proof the person has done it
    /// before. Needs three or more days so one odd reading can't masquerade as
    /// a personal best.
    static func lowestDay(observations: [DailyScreenTimeObservation], today: String) -> DailyScreenTimeObservation? {
        let measured = observations.filter { $0.date != today && $0.minutes > 0 }
        guard measured.count >= 3 else { return nil }
        return measured.min { $0.minutes < $1.minutes }
    }

    /// Day-one target for a pace: never above the baseline, never below the
    /// daily goal.
    static func startMinutes(baseline: Int, pace: ComebackPace, floor: Int) -> Int {
        let cut = Int((Double(baseline) * pace.openingCut).rounded())
        return max(floor, baseline - cut)
    }

    /// 1-based plan day for `anchor` on `today`; nil if the anchor starts in
    /// the future (clock changes) so the caller can ignore it.
    static func dayIndex(anchor: ComebackAnchor, today: String) -> Int? {
        guard let start = MivoDay.date(from: anchor.startDay),
              let now = MivoDay.date(from: today) else { return nil }
        guard let days = MivoDay.calendar.dateComponents([.day], from: start, to: now).day, days >= 0 else { return nil }
        return days + 1
    }

    /// Target for `dayIndex` (1-based), falling by `dailyStepMinutes` a day
    /// until it reaches `floor`.
    static func target(anchor: ComebackAnchor, dayIndex: Int, floor: Int) -> Int {
        let raw = anchor.startMinutes - anchor.dailyStepMinutes * max(0, dayIndex - 1)
        return max(floor, raw)
    }

    /// Days from day one until the target reaches `floor`; 0 when it starts
    /// there already.
    static func daysToGoal(startMinutes: Int, dailyStep: Int, floor: Int) -> Int {
        guard startMinutes > floor, dailyStep > 0 else { return 0 }
        return Int((Double(startMinutes - floor) / Double(dailyStep)).rounded(.up))
    }

    /// Plan day (1-based) on which the target first reaches `floor`.
    static func goalDayIndex(anchor: ComebackAnchor, floor: Int) -> Int {
        daysToGoal(startMinutes: anchor.startMinutes, dailyStep: anchor.dailyStepMinutes, floor: floor) + 1
    }

    /// Splits `total` minutes across windows in proportion to `weights`,
    /// always summing to exactly `total`. Equal split when no weight is
    /// positive (observation-mode windows carry zero minutes).
    static func distribute(total: Int, weights: [Int]) -> [Int] {
        guard !weights.isEmpty else { return [] }
        let total = max(0, total)
        let positive = weights.map { max(0, $0) }
        let sum = positive.reduce(0, +)
        guard sum > 0 else {
            let base = total / weights.count
            let extra = total % weights.count
            return (0..<weights.count).map { base + ($0 < extra ? 1 : 0) }
        }
        var shares = positive.map { total * $0 / sum }
        var leftover = total - shares.reduce(0, +)
        // Largest remainder first, so rounding never favours the first window.
        let order = positive.indices.sorted {
            (total * positive[$0]) % sum > (total * positive[$1]) % sum
        }
        for index in order where leftover > 0 {
            shares[index] += 1
            leftover -= 1
        }
        return shares
    }

    /// The same windows (times, titles, order) with their minutes re-split to
    /// add up to `target`, keeping each window's share of the day.
    static func fit(_ windows: [ScreenScrollWindow], toTarget target: Int) -> [ScreenScrollWindow] {
        let minutes = distribute(total: target, weights: windows.map(\.minutes))
        return zip(windows, minutes).map { window, allowed in
            ScreenScrollWindow(
                id: window.id,
                title: window.title,
                startHour: window.startHour,
                endHour: window.endHour,
                minutes: allowed,
                reason: window.reason
            )
        }
    }

    /// Short day label such as "Sep 3".
    static func shortDate(_ key: String) -> String {
        guard let date = MivoDay.date(from: key) else { return key }
        let formatter = DateFormatter()
        formatter.calendar = MivoDay.calendar
        formatter.locale = Locale.current
        formatter.setLocalizedDateFormatFromTemplate("MMMd")
        return formatter.string(from: date)
    }

    private static func average(_ values: [Int]) -> Int {
        guard !values.isEmpty else { return 0 }
        return Int((Double(values.reduce(0, +)) / Double(values.count)).rounded())
    }
}
