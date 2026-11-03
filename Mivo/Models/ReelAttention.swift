import Foundation

/// Instagram's last pick from before every app opened in Mivo. `AppPickStore`
/// keeps picks per app now and reads this once, as Instagram's fallback.
enum WrapperPickStore {
    static let kindKey = "mivo.wrapper.lastPickKind"
    static let amountKey = "mivo.wrapper.lastPickAmount"

    static func load(defaults: UserDefaults = .standard) -> (kind: WrapperSessionLimit, amount: Int) {
        let kind = defaults.string(forKey: kindKey).flatMap(WrapperSessionLimit.init(rawValue:)) ?? .reels
        let amount = defaults.integer(forKey: amountKey)
        return (kind, amount > 0 ? amount : kind.defaultAmount)
    }

    static func save(_ kind: WrapperSessionLimit, amount: Int, defaults: UserDefaults = .standard) {
        defaults.set(kind.rawValue, forKey: kindKey)
        defaults.set(amount, forKey: amountKey)
    }
}

/// How short videos (Reels, Shorts, TikToks, Spotlight) are being watched,
/// named from the median seconds one stays on screen at normal speed. The
/// cut-offs are Mivo's own, not a clinical scale: most run 15 to 60 seconds,
/// so a few seconds each means scanning.
enum AttentionBand: String, Equatable {
    case skimming
    case restless
    case steady
    case settled

    init(medianSeconds: Double) {
        switch medianSeconds {
        case ..<4: self = .skimming
        case ..<8: self = .restless
        case ..<15: self = .steady
        default: self = .settled
        }
    }

    var title: String {
        switch self {
        case .skimming: return "Skimming"
        case .restless: return "Restless"
        case .steady: return "Steady"
        case .settled: return "Settled"
        }
    }

    var detail: String {
        switch self {
        case .skimming: return "Most videos get a few seconds before the next swipe. That's scanning for the next one, not watching."
        case .restless: return "Videos get some seconds each, then a swipe. Attention moves on before most of them land."
        case .steady: return "Most videos get watched for a while before the swipe."
        case .settled: return "Videos mostly get watched through. Your attention holds."
        }
    }
}

/// Mivo's read of how someone watches short videos, from the sessions in Mivo
/// in one period (every app; messages-only sessions left out). Pure: sessions
/// in, numbers out, so it can be tested.
struct ReelAttentionReport: Equatable {
    static let minimumSessions = 3
    static let minimumTimedReels = 20
    /// A Reel left sooner than this was skipped, not watched.
    static let quickSkipSeconds = 3.0

    let days: Int
    let sessionCount: Int
    let totalReels: Int
    /// Reels with a measured time on screen (normal speed only).
    let timedReels: Int
    let medianSecondsPerReel: Double?
    /// Share of timed Reels left in under `quickSkipSeconds`.
    let quickSkipShare: Double?
    /// Sessions with a recorded pick.
    let pickedSessions: Int
    /// Of those, sessions that kept watching after the pick ran out.
    let wentPastPick: Int
    /// Average Reels started after the pick ran out, over `wentPastPick` sessions.
    let averageReelsPastPick: Double?
    /// Median Reels pick, over sessions counted in Reels.
    let typicalReelPick: Int?
    /// Median Reels watched at normal speed per session.
    let typicalReelsPerSession: Int?
    /// Sessions counted in minutes rather than Reels.
    let minutePickSessions: Int

    init(sessions: [InstagramWrapperSession], days: Int) {
        self.days = max(days, 1)
        sessionCount = sessions.count
        totalReels = sessions.reduce(0) { $0 + $1.reelCount }

        let seconds = sessions.flatMap(\.reelSeconds).filter { $0 >= 0 }
        timedReels = seconds.count
        medianSecondsPerReel = Self.median(seconds)
        quickSkipShare = seconds.isEmpty ? nil : Double(seconds.filter { $0 < Self.quickSkipSeconds }.count) / Double(seconds.count)

        let picked = sessions.filter { $0.limitKind != nil }
        pickedSessions = picked.count
        let past = picked.filter { $0.slowDownCause == "pick" && $0.reelsAfterSlowdown > 0 }
        wentPastPick = past.count
        averageReelsPastPick = past.isEmpty ? nil : Double(past.reduce(0) { $0 + $1.reelsAfterSlowdown }) / Double(past.count)

        let reelPicks = picked.filter { $0.limitKind == WrapperSessionLimit.reels.rawValue }.compactMap(\.limitAmount)
        typicalReelPick = Self.median(reelPicks.map(Double.init)).map { Int($0.rounded()) }
        minutePickSessions = picked.filter { $0.limitKind == WrapperSessionLimit.minutes.rawValue }.count

        let normalSpeedReels = sessions.map { Double(max(0, $0.reelCount - $0.reelsAfterSlowdown)) }
        typicalReelsPerSession = Self.median(normalSpeedReels).map { Int($0.rounded()) }
    }

    var hasEnoughData: Bool {
        sessionCount >= Self.minimumSessions && timedReels >= Self.minimumTimedReels
    }

    var band: AttentionBand? {
        guard hasEnoughData, let medianSecondsPerReel else { return nil }
        return AttentionBand(medianSeconds: medianSecondsPerReel)
    }

    var reelsPerDay: Double { Double(totalReels) / Double(days) }

    /// Share of picked sessions that stopped at the pick (or before it).
    var keptPickShare: Double? {
        pickedSessions == 0 ? nil : Double(pickedSessions - wentPastPick) / Double(pickedSessions)
    }

    static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }
}

/// What Mivo suggests next, from a report. It lowers the pick only once the
/// current one is mostly kept, because a smaller pick that keeps getting
/// blown past changes nothing.
struct ReelPlan: Equatable {
    static let smallestPick = 5
    static let largestPick = 30
    /// Lower the pick when at least this share of sessions stopped at it.
    static let keptShareToStepDown = 0.7
    static let stepDown = 0.8

    let suggestedReelPick: Int
    let steps: [String]

    init?(report: ReelAttentionReport) {
        guard report.hasEnoughData else { return nil }
        let base = min(Self.largestPick, max(Self.smallestPick,
            report.typicalReelPick ?? report.typicalReelsPerSession ?? WrapperSessionLimit.reelsPerSession))

        var steps: [String] = []
        let kept = report.keptPickShare ?? 1
        if kept >= Self.keptShareToStepDown {
            suggestedReelPick = max(Self.smallestPick, Int((Double(base) * Self.stepDown).rounded()))
            if report.pickedSessions > 0 {
                steps.append("You stopped at your pick in \(report.pickedSessions - report.wentPastPick) of \(report.pickedSessions) sessions. Next: \(suggestedReelPick) short videos a session.")
            } else {
                steps.append("Next: \(suggestedReelPick) short videos a session.")
            }
        } else {
            suggestedReelPick = base
            let extra = report.averageReelsPastPick.map { String(format: "%.0f", $0) } ?? "a few"
            steps.append("You went past your pick in \(report.wentPastPick) of \(report.pickedSessions) sessions, by \(extra) videos on average. Keep \(base) until you stop there most times; then Mivo lowers it.")
        }

        if let skips = report.quickSkipShare, skips >= 0.5 {
            steps.append("\(Int((skips * 100).rounded()))% of your short videos got under 3 seconds. Fewer, each watched to the end, beat many skipped ones.")
        } else if let band = report.band, band == .steady || band == .settled {
            steps.append("You give short videos real attention. The aim now is fewer of them.")
        }

        let sessionsPerDay = max(1, Int((Double(report.sessionCount) / Double(report.days)).rounded()))
        let dailyTarget = suggestedReelPick * sessionsPerDay
        if report.reelsPerDay > Double(dailyTarget) {
            steps.append("Aim for \(dailyTarget) short videos a day this week, down from \(Int(report.reelsPerDay.rounded())).")
        }

        if report.minutePickSessions * 2 > report.pickedSessions, report.pickedSessions > 0 {
            steps.append("Minutes let the feed set the pace. Counting videos makes the count yours.")
        }
        self.steps = steps
    }
}

extension AppViewModel {
    /// Mivo's read of the sessions in Mivo in the last `days` days, today
    /// included. Messages-only sessions have no videos to read.
    func reelAttentionReport(days: Int = 7, now: Date = Date()) -> ReelAttentionReport {
        let calendar = MivoDay.calendar
        let start = calendar.date(byAdding: .day, value: -(max(days, 1) - 1), to: calendar.startOfDay(for: now)) ?? now
        let startKey = MivoDay.key(start)
        // Day keys are yyyy-MM-dd, so they compare in date order as strings.
        return ReelAttentionReport(
            sessions: instagramWrapperSessions.filter { $0.date >= startKey && $0.purpose != "messages" },
            days: days
        )
    }

    /// The plan from the last week, if there's enough to go on.
    func reelPlan(now: Date = Date()) -> ReelPlan? {
        ReelPlan(report: reelAttentionReport(days: 7, now: now))
    }
}
