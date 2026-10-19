import Foundation

/// What the widget and the shield extension are allowed to know about the
/// companion. Written only by the app (which is where behaviour is computed),
/// read by extensions through the App Group Mivo already uses — so there is
/// nothing an extension can fail to write and nothing it has to compute.
///
/// This file is Foundation-only because it is compiled into the app, the
/// widget and the shield-configuration extension.
enum CompanionSharedKeys {
    static let appGroup = "group.com.mivo.mivoapp"
    static let snapshot = "mivo.companion.snapshot"
    static let portraitVersion = "mivo.companion.portraitVersion"
    static let portraitFileName = "mivo-companion-portrait.png"
    static let widgetKind = "MivoCompanionWidget"
}

struct CompanionSharedSnapshot: Codable, Equatable {
    var isActive: Bool
    var companionType: String
    var name: String
    var state: String
    var message: String?
    var pausesToday: Int
    var focusSessionsToday: Int
    var dayKey: String
    var focusActive: Bool
    var focusEndsAt: Date?
    var updatedAt: Date

    /// A snapshot from before today describes a different day: its counts
    /// must read as zero rather than yesterday's.
    func pausesCount(on dayKey: String) -> Int { self.dayKey == dayKey ? pausesToday : 0 }
    func focusCount(on dayKey: String) -> Int { self.dayKey == dayKey ? focusSessionsToday : 0 }

    /// Older than this and the widget shows a neutral state rather than
    /// claiming what the companion is doing now.
    func isFresh(at now: Date, maxAge: TimeInterval = 6 * 60 * 60) -> Bool {
        now.timeIntervalSince(updatedAt) <= maxAge && updatedAt.timeIntervalSince(now) < 5 * 60
    }
}

/// Read/write wrapper around the App Group defaults. If the group isn't
/// reachable (`UserDefaults(suiteName:)` returns nil), reads return nil and
/// writes report failure — callers degrade, they never crash.
struct CompanionSharedStore {
    private let defaults: UserDefaults?

    init(suiteName: String = CompanionSharedKeys.appGroup) {
        defaults = UserDefaults(suiteName: suiteName)
    }

    init(defaults: UserDefaults?) {
        self.defaults = defaults
    }

    @discardableResult
    func write(_ snapshot: CompanionSharedSnapshot) -> Bool {
        guard let defaults, let data = try? JSONEncoder().encode(snapshot) else { return false }
        defaults.set(data, forKey: CompanionSharedKeys.snapshot)
        return true
    }

    func read() -> CompanionSharedSnapshot? {
        guard let data = defaults?.data(forKey: CompanionSharedKeys.snapshot) else { return nil }
        return try? JSONDecoder().decode(CompanionSharedSnapshot.self, from: data)
    }

    func clear() {
        defaults?.removeObject(forKey: CompanionSharedKeys.snapshot)
    }
}

/// Where the app leaves a rendered portrait for the shield. A shield extension
/// can only show a bitmap, so the app renders the character once and the
/// extension reads the file.
enum CompanionPortraitFile {
    static func url(appGroup: String = CompanionSharedKeys.appGroup) -> URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
            .appendingPathComponent(CompanionSharedKeys.portraitFileName)
    }

    static func read(appGroup: String = CompanionSharedKeys.appGroup) -> Data? {
        guard let url = url(appGroup: appGroup) else { return nil }
        return try? Data(contentsOf: url)
    }
}
