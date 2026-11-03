import Foundation

/// Replay mode: once the person has used the reels or minutes they chose for
/// this session, the Instagram wrapper swaps every reel they have not seen
/// for one they already have. A feed that only repeats stops paying out
/// novelty, which is what the scrolling runs on.
///
/// Everything here is plain value logic — no clock, no web view, no storage —
/// so it can be unit tested. `SeenReelStore` persists the log and
/// `AppWrapperView` runs a `ReplaySession` against the live page.

/// Reel shortcodes are what Instagram puts in `/reel/<code>/`. They are read
/// out of a web page Mivo does not control, so nothing is trusted until it
/// matches this shape.
enum ReelCode {
    static func isValid(_ code: String) -> Bool {
        let length = code.utf8.count
        guard (8...16).contains(length) else { return false }
        return code.utf8.allSatisfy { byte in
            (byte >= 48 && byte <= 57) || (byte >= 65 && byte <= 90) || (byte >= 97 && byte <= 122) || byte == 45 || byte == 95
        }
    }

    static func url(for code: String) -> URL? {
        guard isValid(code) else { return nil }
        return URL(string: "https://www.instagram.com/reel/\(code)/")
    }
}

/// The reels watched in the wrapper, newest last. Local to this device — the
/// codes are never uploaded.
struct SeenReelLog: Codable, Equatable {
    struct Entry: Codable, Equatable {
        var code: String
        var firstSeen: Date
        var lastSeen: Date
        var timesSeen: Int
    }

    static let maxEntries = 200
    static let maxAgeDays = 30

    private(set) var entries: [Entry] = []

    init(entries: [Entry] = []) {
        self.entries = entries
    }

    var count: Int { entries.count }

    /// Codes from least to most recently seen.
    var codesByRecency: [String] {
        entries.sorted { $0.lastSeen < $1.lastSeen }.map(\.code)
    }

    func contains(_ code: String) -> Bool {
        entries.contains { $0.code == code }
    }

    mutating func record(_ code: String, at date: Date) {
        guard ReelCode.isValid(code) else { return }
        if let index = entries.firstIndex(where: { $0.code == code }) {
            entries[index].lastSeen = date
            entries[index].timesSeen += 1
        } else {
            entries.append(Entry(code: code, firstSeen: date, lastSeen: date, timesSeen: 1))
        }
        prune(now: date)
    }

    /// Drops reels older than `maxAgeDays`, then the oldest beyond `maxEntries`.
    mutating func prune(now: Date, calendar: Calendar = .current) {
        if let cutoff = calendar.date(byAdding: .day, value: -Self.maxAgeDays, to: now) {
            entries.removeAll { $0.lastSeen < cutoff }
        }
        if entries.count > Self.maxEntries {
            let keep = entries.sorted { $0.lastSeen < $1.lastSeen }.suffix(Self.maxEntries)
            let kept = Set(keep.map(\.code))
            entries = entries.filter { kept.contains($0.code) }
        }
    }
}

/// One wrapper session's replay decisions. Feed it each reel the page reports
/// playing; it says whether to let it be or swap it for a repeat.
struct ReplaySession {
    /// How many of this session's reels the replays rotate through. A small
    /// set repeats often enough to be plainly boring.
    static let replayPoolSize = 3

    enum Outcome: Equatable {
        case none
        case replace(with: String)
    }

    private(set) var log: SeenReelLog
    private(set) var lastObserved: String?
    private(set) var pendingReplay: String?
    /// True once the session's chosen reels or minutes are used up.
    private(set) var isReplaying = false
    /// Reels watched this session, oldest first. Replays come from the latest
    /// few so the loop stays tight and obvious.
    private(set) var sessionOrder: [String] = []
    private var servedCount: [String: Int] = [:]

    /// Reels that were new to the person and were watched.
    private(set) var freshReels = 0
    /// Repeats watched, whether Instagram served them or Mivo did.
    private(set) var repeatsSeen = 0
    /// New reels Mivo swapped for a repeat.
    private(set) var repeatsServed = 0

    init(log: SeenReelLog) {
        self.log = log
    }

    /// Called when the person has used what they chose for this session; from
    /// here every new reel is swapped for a repeat.
    mutating func startReplaying() {
        isReplaying = true
    }

    /// `replayActive` is false while replay is off or the 3-day baseline is
    /// being recorded: reels are still logged and counted, but never swapped.
    mutating func observe(_ code: String, replayActive: Bool, now: Date) -> Outcome {
        guard ReelCode.isValid(code), code != lastObserved else { return .none }

        if code == pendingReplay {
            pendingReplay = nil
            lastObserved = code
            watched(code, wasSeen: true, now: now)
            return .none
        }

        let wasSeen = log.contains(code)
        if replayActive, isReplaying, !wasSeen,
           let target = nextReplay(excluding: code) {
            lastObserved = code
            pendingReplay = target
            servedCount[target, default: 0] += 1
            repeatsServed += 1
            return .replace(with: target)
        }

        pendingReplay = nil
        lastObserved = code
        watched(code, wasSeen: wasSeen, now: now)
        return .none
    }

    private mutating func watched(_ code: String, wasSeen: Bool, now: Date) {
        log.record(code, at: now)
        if wasSeen { repeatsSeen += 1 } else { freshReels += 1 }
        if !sessionOrder.contains(code) { sessionOrder.append(code) }
    }

    /// The least-replayed of the latest few reels, oldest first, so a small
    /// set cycles evenly. Falls back to reels from earlier sessions when this
    /// one has watched nothing else.
    private func nextReplay(excluding current: String) -> String? {
        var pool = Array(sessionOrder.filter { $0 != current }.suffix(Self.replayPoolSize))
        if pool.isEmpty {
            pool = Array(log.codesByRecency.filter { $0 != current }.suffix(Self.replayPoolSize))
        }
        return pool.enumerated()
            .min { lhs, rhs in
                let l = servedCount[lhs.element, default: 0]
                let r = servedCount[rhs.element, default: 0]
                return l != r ? l < r : lhs.offset < rhs.offset
            }?
            .element
    }
}

/// Persists the `SeenReelLog` on this device (UserDefaults).
final class SeenReelStore {
    static let shared = SeenReelStore()
    static let defaultsKey = "mivo.wrapper.seenReels"

    private let defaults: UserDefaults
    private let now: () -> Date

    init(defaults: UserDefaults = .standard, now: @escaping () -> Date = Date.init) {
        self.defaults = defaults
        self.now = now
    }

    func load() -> SeenReelLog {
        var log = defaults.data(forKey: Self.defaultsKey)
            .flatMap { try? JSONDecoder().decode(SeenReelLog.self, from: $0) } ?? SeenReelLog()
        log.prune(now: now())
        return log
    }

    func save(_ log: SeenReelLog) {
        guard let data = try? JSONEncoder().encode(log) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }

    func clear() {
        defaults.removeObject(forKey: Self.defaultsKey)
    }
}

/// The one stored preference for replay mode: on unless turned off.
enum ReplayModeSetting {
    static let key = "mivo.wrapper.replayMode"

    static var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: key) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }

    /// Replay is held off while Mivo is still recording the 3-day baseline, so
    /// the baseline reflects how the person really scrolls.
    static func isActive(enabled: Bool, observingBaseline: Bool) -> Bool {
        enabled && !observingBaseline
    }
}
