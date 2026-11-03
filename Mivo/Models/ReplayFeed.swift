import Foundation

/// Replay mode, "the feed runs out": once the person has used the short videos
/// they chose for this session, Mivo swaps every video they have not seen for
/// one they already have. A feed that only repeats stops paying out novelty,
/// which is what the scrolling runs on. Instagram Reels, YouTube Shorts,
/// Facebook Reels and Snapchat Spotlight; TikTok's web feed doesn't put each
/// video in the page address, so it has nothing to swap by.
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

/// Short-video IDs for every app replay mode works in. Like `ReelCode` they
/// are read from pages Mivo does not control, so each app's shape is checked
/// before an ID is stored or put into an address.
enum ShortVideoID {
    static func supportsReplay(_ app: SocialApp) -> Bool {
        switch app {
        case .instagram, .youtube, .facebook, .snapchat: return true
        case .tiktok, .x, .reddit, .threads: return false
        }
    }

    /// The common floor for anything stored: URL-safe characters, sensible length.
    static func isSafe(_ id: String) -> Bool {
        let length = id.utf8.count
        guard (6...96).contains(length) else { return false }
        return id.utf8.allSatisfy { byte in
            (byte >= 48 && byte <= 57) || (byte >= 65 && byte <= 90) || (byte >= 97 && byte <= 122) || byte == 45 || byte == 95
        }
    }

    static func isValid(_ id: String, for app: SocialApp) -> Bool {
        guard isSafe(id) else { return false }
        switch app {
        case .instagram: return ReelCode.isValid(id)
        case .youtube: return id.utf8.count == 11
        case .facebook: return id.utf8.count <= 25 && id.allSatisfy(\.isNumber)
        case .snapchat: return id.utf8.count >= 10
        case .tiktok, .x, .reddit, .threads: return false
        }
    }

    /// The video a page address points at, when it points at one.
    static func id(in url: URL, app: SocialApp) -> String? {
        guard supportsReplay(app), app.owns(host: url.host) else { return nil }
        let parts = url.path.split(separator: "/").map(String.init)
        guard parts.count >= 2 else { return nil }
        let marker = parts[0].lowercased()
        let candidate = parts[1]
        let matches: Bool
        switch app {
        case .instagram: matches = marker == "reel" || marker == "reels"
        case .youtube: matches = marker == "shorts"
        case .facebook: matches = marker == "reel" || marker == "reels"
        case .snapchat: matches = marker == "spotlight"
        case .tiktok, .x, .reddit, .threads: matches = false
        }
        return matches && isValid(candidate, for: app) ? candidate : nil
    }

    static func url(for id: String, app: SocialApp) -> URL? {
        guard isValid(id, for: app) else { return nil }
        switch app {
        case .instagram: return ReelCode.url(for: id)
        case .youtube: return URL(string: "https://m.youtube.com/shorts/\(id)")
        case .facebook: return URL(string: "https://m.facebook.com/reel/\(id)")
        case .snapchat: return URL(string: "https://www.snapchat.com/spotlight/\(id)")
        case .tiktok, .x, .reddit, .threads: return nil
        }
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
        guard ShortVideoID.isSafe(code) else { return }
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
        guard ShortVideoID.isSafe(code), code != lastObserved else { return .none }

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

/// Persists the `SeenReelLog` on this device (UserDefaults), one log per app.
final class SeenReelStore {
    static let shared = SeenReelStore()
    static let defaultsKey = "mivo.wrapper.seenReels"

    private let defaults: UserDefaults
    private let now: () -> Date
    private let key: String

    init(defaults: UserDefaults = .standard, now: @escaping () -> Date = Date.init, key: String = SeenReelStore.defaultsKey) {
        self.defaults = defaults
        self.now = now
        self.key = key
    }

    /// Instagram keeps the original key, so reels seen before every app
    /// opened in Mivo still count as seen.
    static func forApp(_ app: SocialApp) -> SeenReelStore {
        app == .instagram ? shared : SeenReelStore(key: "\(defaultsKey).\(app.rawValue)")
    }

    func load() -> SeenReelLog {
        var log = defaults.data(forKey: key)
            .flatMap { try? JSONDecoder().decode(SeenReelLog.self, from: $0) } ?? SeenReelLog()
        log.prune(now: now())
        return log
    }

    func save(_ log: SeenReelLog) {
        guard let data = try? JSONEncoder().encode(log) else { return }
        defaults.set(data, forKey: key)
    }

    func clear() {
        defaults.removeObject(forKey: key)
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
