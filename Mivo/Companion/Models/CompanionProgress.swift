import Foundation

/// Lightweight, non-punishing progression. It rewards *intentional* behaviour
/// (pausing, stepping away, focusing) — never low screen time — and nothing is
/// ever taken back: milestones stay unlocked and a broken streak just restarts.
enum CompanionMilestone: String, Codable, CaseIterable, Identifiable {
    case firstPause
    case threePauses
    case tenPauses
    case firstFocus
    case threeDays
    case sevenDays

    var id: String { rawValue }

    var title: String {
        switch self {
        case .firstPause: return "First pause"
        case .threePauses: return "Three pauses"
        case .tenPauses: return "Ten pauses"
        case .firstFocus: return "First focus session"
        case .threeDays: return "Three mindful days"
        case .sevenDays: return "A mindful week"
        }
    }

    var detail: String {
        switch self {
        case .firstPause: return "You took a deliberate pause before an app."
        case .threePauses: return "Unlocks a stretch the companion does while relaxing."
        case .tenPauses: return "Ten moments of choosing instead of drifting."
        case .firstFocus: return "You finished a Mivo Still session."
        case .threeDays: return "Three days in a row with an intentional pause or focus session."
        case .sevenDays: return "Seven days in a row. Quietly impressive."
        }
    }
}

struct CompanionDayRecord: Codable, Equatable {
    var dayKey: String
    /// Pauses the person went through (continued or walked away).
    var pauses: Int = 0
    /// Of those, the ones that ended with walking away.
    var exits: Int = 0
    var focusSessions: Int = 0

    var isMindful: Bool { pauses > 0 || focusSessions > 0 }
}

/// Aggregated daily counters only. No app names, no durations, no timestamps
/// beyond the day — the raw usage history stays where Mivo already keeps it.
struct CompanionProgress: Codable, Equatable {
    static let retainedDays = 90

    var days: [CompanionDayRecord] = []
    var totalPauses: Int = 0
    var totalExits: Int = 0
    var totalFocusSessions: Int = 0
    var bestStreak: Int = 0
    var unlocked: [CompanionMilestone] = []

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        days = c.value(.days, default: [])
        totalPauses = c.value(.totalPauses, default: 0)
        totalExits = c.value(.totalExits, default: 0)
        totalFocusSessions = c.value(.totalFocusSessions, default: 0)
        bestStreak = c.value(.bestStreak, default: 0)
        unlocked = c.value(.unlocked, default: [])
    }

    func record(for dayKey: String) -> CompanionDayRecord {
        days.first(where: { $0.dayKey == dayKey }) ?? CompanionDayRecord(dayKey: dayKey)
    }

    func isUnlocked(_ milestone: CompanionMilestone) -> Bool { unlocked.contains(milestone) }

    /// The ambient stretch only plays once it's been earned.
    func isUnlocked(_ animation: CompanionAnimation) -> Bool {
        animation == .stretching ? isUnlocked(.threePauses) : true
    }

    /// Consecutive mindful days ending today, or yesterday if today hasn't had
    /// one yet — so an unfinished day never reads as a lost streak.
    func currentStreak(today: Date, calendar: Calendar) -> Int {
        let mindful = Set(days.filter(\.isMindful).map(\.dayKey))
        var offset = 0
        if !mindful.contains(CompanionDay.key(offset: 0, from: today, calendar: calendar)) { offset = -1 }
        var streak = 0
        while mindful.contains(CompanionDay.key(offset: offset, from: today, calendar: calendar)) {
            streak += 1
            offset -= 1
        }
        return streak
    }

    @discardableResult
    mutating func recordPause(exited: Bool, dayKey: String, today: Date, calendar: Calendar) -> [CompanionMilestone] {
        mutateDay(dayKey) { day in
            day.pauses += 1
            if exited { day.exits += 1 }
        }
        totalPauses += 1
        if exited { totalExits += 1 }
        return refreshMilestones(today: today, calendar: calendar)
    }

    @discardableResult
    mutating func recordFocusSession(dayKey: String, today: Date, calendar: Calendar) -> [CompanionMilestone] {
        mutateDay(dayKey) { $0.focusSessions += 1 }
        totalFocusSessions += 1
        return refreshMilestones(today: today, calendar: calendar)
    }

    private mutating func mutateDay(_ dayKey: String, _ change: (inout CompanionDayRecord) -> Void) {
        if let index = days.firstIndex(where: { $0.dayKey == dayKey }) {
            change(&days[index])
        } else {
            var day = CompanionDayRecord(dayKey: dayKey)
            change(&day)
            days.append(day)
            days.sort { $0.dayKey < $1.dayKey }
            if days.count > Self.retainedDays { days.removeFirst(days.count - Self.retainedDays) }
        }
    }

    private mutating func refreshMilestones(today: Date, calendar: Calendar) -> [CompanionMilestone] {
        let streak = currentStreak(today: today, calendar: calendar)
        bestStreak = max(bestStreak, streak)
        var earned: [CompanionMilestone] = []
        func unlock(_ milestone: CompanionMilestone, when condition: Bool) {
            guard condition, !unlocked.contains(milestone) else { return }
            unlocked.append(milestone)
            earned.append(milestone)
        }
        unlock(.firstPause, when: totalPauses >= 1)
        unlock(.threePauses, when: totalPauses >= 3)
        unlock(.tenPauses, when: totalPauses >= 10)
        unlock(.firstFocus, when: totalFocusSessions >= 1)
        unlock(.threeDays, when: bestStreak >= 3)
        unlock(.sevenDays, when: bestStreak >= 7)
        return earned
    }
}
