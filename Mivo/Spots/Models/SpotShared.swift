import Foundation

// Foundation-only on purpose. This file is compiled into the app AND into the
// Screen Time extensions (shield configuration, shield action, device-activity
// monitor), which cannot import the app module. Anything the extensions need to
// agree with the app on — keys, mode names, the usage-event naming — lives here
// so there is exactly one spelling of each.

/// UserDefaults keys and Screen Time names used by Mivo Spots.
enum SpotKeys {
    static let appGroup = "group.com.mivo.mivoapp"

    // MARK: Live mirror (app group)
    //
    // The app is the only writer of the "live" block. Extensions read it to decide
    // what the shield says and whether a tapped app belongs to the running Spot.

    static let liveActive = "mivo.spot.live.active"
    static let liveSessionID = "mivo.spot.live.sessionID"
    static let liveSpotID = "mivo.spot.live.spotID"
    static let liveName = "mivo.spot.live.name"
    static let liveMode = "mivo.spot.live.mode"
    /// Epoch seconds. Always set — an open-ended Spot carries its safety cap here.
    static let liveEndsAt = "mivo.spot.live.endsAt"
    /// Epoch seconds until which the shield is deliberately lifted (a pause the
    /// person chose to continue past). 0 when the shield is not lifted.
    static let liveShieldLiftedUntil = "mivo.spot.live.liftedUntil"
    /// An Intention Check lifts the shield for the rest of the Spot once answered.
    static let liveIntentionDone = "mivo.spot.live.intentionDone"
    /// JSON-encoded `FamilyActivitySelection` for the running Spot.
    static let liveSelection = "mivo.spot.live.selection"

    // MARK: Shield → app hand-off

    static let pendingRoute = "mivo.spot.pendingRoute"
    static let pendingAppName = "mivo.spot.pendingAppName"
    static let pendingAt = "mivo.spot.pendingAt"

    // MARK: Usage written by the monitor extension

    static let usageLive = "mivo.spot.usage.live"
    static let usageSessionID = "mivo.spot.usage.sessionID"

    // MARK: Screen Time names

    static let storeName = "mivo.spot"
    static let usageActivityName = "mivo.spot.usage"
    static let endActivityName = "mivo.spot.end"
    static let relockActivityName = "mivo.spot.relock"

    /// `mivoRoute` value on the local notification the shield extension posts.
    static let notificationRoute = "spot"
    static let routeChangedNotification = "mivoSpotRequested"

    /// An open-ended Spot is never allowed to outlive this, so a forgotten Spot
    /// cannot keep apps shielded indefinitely.
    static let openEndedCapHours = 12
    /// How long a pause the person chose to continue past keeps the apps open.
    static let pauseGraceMinutes = 5
}

/// What a Spot does while it is active.
enum SpotMode: String, Codable, CaseIterable, Identifiable {
    case pause
    case focus
    case intention
    case awareness

    var id: String { rawValue }

    /// Name shown when choosing a behaviour.
    var title: String {
        switch self {
        case .pause: return "Mivo Pause"
        case .focus: return "Focus Session"
        case .intention: return "Intention Check"
        case .awareness: return "Awareness Only"
        }
    }

    /// Short label for a Spot card and the shield, e.g. "Focus Mode".
    var cardLabel: String {
        switch self {
        case .pause: return "Pause Mode"
        case .focus: return "Focus Mode"
        case .intention: return "Intention Check"
        case .awareness: return "Awareness Mode"
        }
    }

    var detail: String {
        switch self {
        case .pause: return "Opening one of these apps here starts the Mivo pause first."
        case .focus: return "Tap the Spot to start a timed session. These apps wait until it ends."
        case .intention: return "Mivo asks what you came to do, once, the first time you open one."
        case .awareness: return "No blocking. Mivo just notes the time you spend in these apps."
        }
    }

    var symbol: String {
        switch self {
        case .pause: return "pause.circle"
        case .focus: return "scope"
        case .intention: return "questionmark.bubble"
        case .awareness: return "eye"
        }
    }

    /// Whether the mode puts a Screen Time shield on the Spot's apps.
    var usesShield: Bool {
        switch self {
        case .pause, .focus, .intention: return true
        case .awareness: return false
        }
    }
}

/// A read-only view of the live block, shared by the app and every extension.
struct SpotLiveState: Equatable {
    let sessionID: String
    let spotID: String
    let name: String
    let mode: SpotMode
    let endsAt: Date
    let liftedUntil: Date?
    let intentionDone: Bool

    /// Returns nil when no Spot is running or its time is up, so an extension
    /// that wakes late can never act on a Spot that has already ended.
    static func read(from defaults: UserDefaults?, now: Date = Date()) -> SpotLiveState? {
        guard let defaults, defaults.bool(forKey: SpotKeys.liveActive),
              let sessionID = defaults.string(forKey: SpotKeys.liveSessionID),
              let spotID = defaults.string(forKey: SpotKeys.liveSpotID),
              let modeRaw = defaults.string(forKey: SpotKeys.liveMode),
              let mode = SpotMode(rawValue: modeRaw) else { return nil }
        let endsAt = defaults.double(forKey: SpotKeys.liveEndsAt)
        guard endsAt > now.timeIntervalSince1970 else { return nil }
        let lifted = defaults.double(forKey: SpotKeys.liveShieldLiftedUntil)
        return SpotLiveState(
            sessionID: sessionID,
            spotID: spotID,
            name: defaults.string(forKey: SpotKeys.liveName) ?? "Your Spot",
            mode: mode,
            endsAt: Date(timeIntervalSince1970: endsAt),
            liftedUntil: lifted > 0 ? Date(timeIntervalSince1970: lifted) : nil,
            intentionDone: defaults.bool(forKey: SpotKeys.liveIntentionDone)
        )
    }

    /// Whether the Spot's apps should be shielded right now.
    func wantsShield(at now: Date = Date()) -> Bool {
        guard mode.usesShield else { return false }
        if mode == .intention && intentionDone { return false }
        if let liftedUntil, liftedUntil > now { return false }
        return true
    }
}

// MARK: - Usage events

/// Which monitored set an event counts: everything the Spot covers, or one app.
enum SpotUsageScope: Equatable, Hashable {
    case all
    case app(Int)

    var key: String {
        switch self {
        case .all: return "all"
        case .app(let index): return "a\(index)"
        }
    }
}

/// iOS exposes app usage to third-party apps in exactly one live form: a
/// `DeviceActivityEvent` fires once when cumulative usage of the monitored apps
/// crosses a threshold. Mivo watches a ladder of thresholds and keeps the
/// highest one reached, so a reported time is a floor — "at least this much" —
/// never an invented number.
enum SpotUsageLadder {
    /// Per-app attribution is limited to this many apps per Spot; any further
    /// apps still count toward the Spot total.
    static let maxTrackedApps = 4

    /// Thresholds, in minutes, for the Spot as a whole.
    static let allMinutes = [1, 2, 3, 5, 7, 10, 15, 20, 25, 30, 40, 50, 60, 90, 120, 180]
    /// Thresholds, in minutes, for each individually tracked app.
    static let appMinutes = [1, 3, 5, 10, 15, 25, 40, 60, 90, 120]

    private static let prefix = "mivo.spot.u."

    static func thresholds(for scope: SpotUsageScope) -> [Int] {
        switch scope {
        case .all: return allMinutes
        case .app: return appMinutes
        }
    }

    static func eventName(scope: SpotUsageScope, minutes: Int) -> String {
        "\(prefix)\(scope.key).m\(minutes)"
    }

    static func parse(eventName: String) -> (scope: SpotUsageScope, minutes: Int)? {
        guard eventName.hasPrefix(prefix) else { return nil }
        let parts = eventName.dropFirst(prefix.count).split(separator: ".")
        guard parts.count == 2, parts[1].hasPrefix("m"),
              let minutes = Int(parts[1].dropFirst()), minutes > 0 else { return nil }
        let scopeKey = String(parts[0])
        if scopeKey == "all" { return (.all, minutes) }
        if scopeKey.hasPrefix("a"), let index = Int(scopeKey.dropFirst()), index >= 0 {
            return (.app(index), minutes)
        }
        return nil
    }

    /// Total events a Spot with this many individually tracked apps registers.
    static func eventCount(trackedApps: Int) -> Int {
        allMinutes.count + min(max(trackedApps, 0), maxTrackedApps) * appMinutes.count
    }

    /// Folds a fired event into the running tally, keeping the highest threshold.
    static func record(eventName: String, into tally: inout [String: Int]) {
        guard let parsed = parse(eventName: eventName) else { return }
        let key = parsed.scope.key
        tally[key] = max(tally[key] ?? 0, parsed.minutes)
    }

    static func minutes(for scope: SpotUsageScope, in tally: [String: Int]) -> Int {
        tally[scope.key] ?? 0
    }
}
