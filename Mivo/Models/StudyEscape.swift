import Foundation

/// A social app opened while studying, or soon after stopping: the pattern of
/// leaving work for the feed to get away from how the work feels. Mivo names
/// it when the app opens and offers the way back when it closes.
struct StudyEscape: Equatable {
    /// How soon after a study session ends opening an app still counts.
    static let window: TimeInterval = 10 * 60

    /// What they were studying, as they typed it. Shown on this phone only;
    /// sessions store just the minutes.
    let task: String
    /// Whole minutes since the session ended; 0 while it is still running.
    let minutesAgo: Int
    /// The study session is still running underneath.
    let midSession: Bool

    /// The escape this app opening is, if any: a running study session, or the
    /// latest one ended within `window`.
    static func detect(runningTask: String?, lastEnded: (task: String, endedAt: Date)?, now: Date) -> StudyEscape? {
        if let runningTask, !runningTask.isEmpty {
            return StudyEscape(task: runningTask, minutesAgo: 0, midSession: true)
        }
        guard let lastEnded, !lastEnded.task.isEmpty else { return nil }
        let elapsed = now.timeIntervalSince(lastEnded.endedAt)
        guard elapsed >= 0, elapsed <= window else { return nil }
        return StudyEscape(task: lastEnded.task, minutesAgo: Int(elapsed / 60), midSession: false)
    }

    /// "You left Chemistry 4 minutes ago."
    var headline: String {
        if midSession { return "You're in the middle of \(task)." }
        switch minutesAgo {
        case 0: return "You left \(task) just now."
        case 1: return "You left \(task) a minute ago."
        default: return "You left \(task) \(minutesAgo) minutes ago."
        }
    }
}

extension StudyService {
    /// The escape opening an app right now would be.
    func currentEscape(now: Date = Date()) -> StudyEscape? {
        var running: String?
        if case .running(let active) = phase { running = active.task }
        let last = log.entries.max { $0.endedAt < $1.endedAt }.map { (task: $0.task, endedAt: $0.endedAt) }
        return StudyEscape.detect(runningTask: running, lastEnded: last, now: now)
    }
}

/// How a session left someone feeling, asked in one tap when they close it.
enum SessionFeeling: String, Codable, CaseIterable {
    case better
    case same
    case worse

    var title: String {
        switch self {
        case .better: return "Better"
        case .same: return "Same"
        case .worse: return "Worse"
        }
    }
}
