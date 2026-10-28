import Foundation

/// One finished study session.
struct StudyEntry: Codable, Equatable, Identifiable {
    var id = UUID()
    var task: String
    var startedAt: Date
    var endedAt: Date
    /// Seconds of the session that are on video. 0 when it was not recorded.
    var recordedSeconds: Int
    /// Wrapper seconds this session added to today's balance.
    var scrollSecondsEarned: Int

    var seconds: Int { max(0, Int(endedAt.timeIntervalSince(startedAt))) }
    var minutes: Int { seconds / 60 }
    var wasRecorded: Bool { recordedSeconds > 0 }
}

/// Every finished session, and the streak they add up to. Pure value logic —
/// no clock, no storage — so it can be unit tested.
struct StudyLog: Codable, Equatable {
    /// A day counts once it holds one block of this much study. The bar is low
    /// on purpose: the streak rewards starting, not finishing a marathon.
    static let dayThresholdSeconds = 10 * 60

    var entries: [StudyEntry] = []

    /// Study seconds per local day (`yyyy-MM-dd`). A session that crosses
    /// midnight counts toward both days.
    func secondsByDay(calendar: Calendar = .current) -> [String: Int] {
        var totals: [String: Int] = [:]
        for entry in entries {
            var cursor = entry.startedAt
            while cursor < entry.endedAt {
                let nextMidnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: cursor)) ?? entry.endedAt
                let boundary = min(entry.endedAt, nextMidnight)
                totals[ReelBalance.dayKey(for: cursor, calendar: calendar), default: 0] += Int(boundary.timeIntervalSince(cursor))
                cursor = boundary
            }
        }
        return totals
    }

    func seconds(on date: Date, calendar: Calendar = .current) -> Int {
        secondsByDay(calendar: calendar)[ReelBalance.dayKey(for: date, calendar: calendar)] ?? 0
    }

    /// Consecutive days that reached the threshold. If today has not reached it
    /// yet the count runs back from yesterday, so an unfinished day does not
    /// read as a broken streak.
    func streak(asOf now: Date, calendar: Calendar = .current) -> Int {
        let totals = secondsByDay(calendar: calendar)
        func counts(_ date: Date) -> Bool {
            (totals[ReelBalance.dayKey(for: date, calendar: calendar)] ?? 0) >= Self.dayThresholdSeconds
        }
        var day = calendar.startOfDay(for: now)
        if !counts(day) { day = calendar.date(byAdding: .day, value: -1, to: day) ?? day }
        var count = 0
        while counts(day) {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return count
    }
}

/// Milo's lines on the study receipt. Fixed: the rule for what earns scroll
/// time is the same every day, so there is nothing to argue with.
enum MiloStudyVoice {
    static func receipt(earnedScrollMinutes: Int, recorded: Bool, capReached: Bool, streak: Int) -> String {
        if !recorded {
            return "No video, so no scroll time this round. The minutes still count for your streak."
        }
        if earnedScrollMinutes == 0 {
            return capReached
                ? "Today's scroll time is already full. The studying still counts."
                : "That's a start, and starting is the hard part."
        }
        if streak >= 2 {
            return "\(streak) days in a row. You earned \(earnedScrollMinutes) minutes of scroll. Enjoy them."
        }
        return "You did the thing. \(earnedScrollMinutes) minutes of scroll are yours."
    }
}
