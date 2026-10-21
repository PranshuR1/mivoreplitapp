import Foundation

/// Totals for one Spot, or for all of them.
struct SpotStats: Equatable {
    var sessionCount: Int
    var totalActiveMinutes: Int
    /// Sum over sessions where usage was actually measured.
    var measuredDistractingMinutes: Int
    var measuredSessionCount: Int
    var averageSessionMinutes: Int

    static let empty = SpotStats(
        sessionCount: 0, totalActiveMinutes: 0, measuredDistractingMinutes: 0,
        measuredSessionCount: 0, averageSessionMinutes: 0
    )
}

struct SpotOverallStats: Equatable {
    var totals: SpotStats
    var mostUsedSpotID: String?
    var mostUsedSpotName: String?
    var mostUsedSessionCount: Int
}

/// How a session compares with the person's own history in the same Spot.
enum SpotComparison: Equatable {
    /// Not enough comparable sessions, or this one has no measured usage.
    case notEnoughData
    case lessThanUsual(minutes: Int)
    case similarToUsual
    case moreThanUsual(minutes: Int)
}

struct SpotSessionSummary: Identifiable, Equatable {
    var id: String { sessionID }
    let sessionID: String
    let spotName: String
    let spotIcon: String
    let activeMinutes: Int
    /// nil when usage was not measured — shown as "not measured", never as 0.
    let distractingMinutes: Int?
    let perApp: [SpotAppUsage]
    let comparison: SpotComparison
    let reason: SpotCompletionReason
    let intention: SpotIntentionAnswer?
}

/// Pure analytics over session history. Deliberately small: totals, an average,
/// a most-used Spot, and one honest comparison.
enum SpotInsights {
    /// Sessions shorter than this are accidental taps and are left out of stats.
    static let minimumCountedSeconds: TimeInterval = 60
    /// Prior sessions needed before any comparison is offered.
    static let minimumSessionsForComparison = 3
    /// A prior session must run at least this long to inform the comparison.
    static let minimumComparableMinutes = 10
    /// Differences smaller than this (and than 15% of expected) read as "similar".
    static let similarityFloorMinutes = 5

    static func minutes(_ seconds: TimeInterval) -> Int {
        Int((max(0, seconds) / 60).rounded())
    }

    static func counted(_ sessions: [SpotSession]) -> [SpotSession] {
        sessions.filter { $0.endDate != nil && $0.activeSeconds() >= minimumCountedSeconds }
    }

    static func stats(for sessions: [SpotSession], spotID: String? = nil) -> SpotStats {
        let relevant = counted(sessions).filter { spotID == nil || $0.spotID == spotID }
        guard !relevant.isEmpty else { return .empty }
        let active = relevant.map { minutes($0.activeSeconds()) }
        let measured = relevant.filter { $0.usageTracked && $0.usage != nil }
        let totalActive = active.reduce(0, +)
        return SpotStats(
            sessionCount: relevant.count,
            totalActiveMinutes: totalActive,
            measuredDistractingMinutes: measured.compactMap { $0.usage?.totalMinutes }.reduce(0, +),
            measuredSessionCount: measured.count,
            averageSessionMinutes: Int((Double(totalActive) / Double(relevant.count)).rounded())
        )
    }

    static func overall(for sessions: [SpotSession]) -> SpotOverallStats {
        let relevant = counted(sessions)
        var counts: [String: (count: Int, minutes: Int, name: String)] = [:]
        for session in relevant {
            var entry = counts[session.spotID] ?? (0, 0, session.spotName)
            entry.count += 1
            entry.minutes += minutes(session.activeSeconds())
            entry.name = session.spotName
            counts[session.spotID] = entry
        }
        // Ties go to the Spot with more time, then the earlier ID, so the answer
        // never flickers between two equally used Spots.
        let top = counts.max { lhs, rhs in
            if lhs.value.count != rhs.value.count { return lhs.value.count < rhs.value.count }
            if lhs.value.minutes != rhs.value.minutes { return lhs.value.minutes < rhs.value.minutes }
            return lhs.key > rhs.key
        }
        return SpotOverallStats(
            totals: stats(for: relevant),
            mostUsedSpotID: top?.key,
            mostUsedSpotName: top?.value.name,
            mostUsedSessionCount: top?.value.count ?? 0
        )
    }

    /// Compares time in distracting apps against the person's own rate in the
    /// same Spot. Returns `.notEnoughData` rather than guessing.
    static func comparison(for session: SpotSession, history: [SpotSession]) -> SpotComparison {
        guard session.usageTracked, let usage = session.usage else { return .notEnoughData }
        let thisMinutes = minutes(session.activeSeconds())
        guard thisMinutes >= minimumComparableMinutes else { return .notEnoughData }

        let prior = counted(history).filter {
            $0.id != session.id && $0.spotID == session.spotID
                && $0.usageTracked && $0.usage != nil
                && minutes($0.activeSeconds()) >= minimumComparableMinutes
        }
        guard prior.count >= minimumSessionsForComparison else { return .notEnoughData }

        let priorActive = prior.map { minutes($0.activeSeconds()) }.reduce(0, +)
        let priorDistracting = prior.compactMap { $0.usage?.totalMinutes }.reduce(0, +)
        guard priorActive > 0 else { return .notEnoughData }

        // Compare rates, not totals, so a longer session isn't "worse" just by being longer.
        let expected = Double(priorDistracting) / Double(priorActive) * Double(thisMinutes)
        let difference = Int((expected - Double(usage.totalMinutes)).rounded())
        let threshold = max(similarityFloorMinutes, Int((expected * 0.15).rounded()))
        if abs(difference) < threshold { return .similarToUsual }
        return difference > 0 ? .lessThanUsual(minutes: difference) : .moreThanUsual(minutes: -difference)
    }

    static func summary(for session: SpotSession, history: [SpotSession]) -> SpotSessionSummary {
        SpotSessionSummary(
            sessionID: session.id,
            spotName: session.spotName,
            spotIcon: session.spotIcon,
            activeMinutes: minutes(session.activeSeconds()),
            distractingMinutes: session.usageTracked ? session.usage?.totalMinutes : nil,
            perApp: (session.usage?.perApp ?? []).filter { $0.minutes > 0 }.sorted { $0.minutes > $1.minutes },
            comparison: comparison(for: session, history: history),
            reason: session.completionReason ?? .endedManually,
            intention: session.intention
        )
    }

    /// The sentence shown under a summary, or nil when there is nothing true to say.
    static func comparisonText(_ comparison: SpotComparison, spotName: String) -> String? {
        switch comparison {
        case .notEnoughData:
            return nil
        case .lessThanUsual(let minutes):
            return "\(minutes) min less distracting screen time than your usual \(spotName) sessions."
        case .similarToUsual:
            return "About the same as your usual \(spotName) sessions."
        case .moreThanUsual(let minutes):
            return "About \(minutes) min more than your usual \(spotName) sessions. Noticing is the point."
        }
    }
}
