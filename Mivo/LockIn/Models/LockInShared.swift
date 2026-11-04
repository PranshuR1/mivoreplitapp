import Foundation

// Foundation-only on purpose. This file is compiled into the app AND into the
// Screen Time extensions (shield configuration, shield action, device-activity
// monitor), which cannot import the app module. Anything the extensions need to
// agree with the app on — keys, names, the safety cap — lives here so there is
// exactly one spelling of each.

/// UserDefaults keys and Screen Time names used by Lock-in.
enum LockInKeys {
    static let appGroup = "group.com.mivo.mivoapp"

    // MARK: Live mirror (app group)
    //
    // The app is the only writer of the "live" block. Extensions read it to decide
    // what the shield says and whether a tapped app belongs to the running lock.

    static let liveActive = "mivo.lockin.live.active"
    static let liveID = "mivo.lockin.live.id"
    static let liveTask = "mivo.lockin.live.task"
    /// Epoch seconds. Always set — a lock never outlives its safety cap.
    static let liveEndsAt = "mivo.lockin.live.endsAt"
    /// JSON-encoded `FamilyActivitySelection` for the running lock.
    static let liveSelection = "mivo.lockin.live.selection"

    // MARK: Shield → app hand-off

    static let pendingRoute = "mivo.lockin.pendingRoute"
    static let pendingAt = "mivo.lockin.pendingAt"

    // MARK: Screen Time names

    static let storeName = "mivo.lockIn"
    static let endActivityName = "mivo.lockin.end"

    /// `mivoRoute` value on the local notification the shield extension posts.
    static let notificationRoute = "lockin"
    static let routeChangedNotification = "mivoLockInRequested"

    /// A lock is never allowed to outlive this, so a forgotten lock cannot keep
    /// apps shielded indefinitely.
    static let hardCapHours = 12
}

/// A read-only view of the live lock, shared by the app and every extension.
struct LockInLiveState: Equatable {
    let id: String
    let task: String
    let endsAt: Date

    /// Returns nil when no lock is running or its time is up, so an extension that
    /// wakes late can never act on a lock that has already ended.
    static func read(from defaults: UserDefaults?, now: Date = Date()) -> LockInLiveState? {
        guard let defaults, defaults.bool(forKey: LockInKeys.liveActive),
              let id = defaults.string(forKey: LockInKeys.liveID) else { return nil }
        let endsAt = defaults.double(forKey: LockInKeys.liveEndsAt)
        guard endsAt > now.timeIntervalSince1970 else { return nil }
        return LockInLiveState(
            id: id,
            task: defaults.string(forKey: LockInKeys.liveTask) ?? "",
            endsAt: Date(timeIntervalSince1970: endsAt)
        )
    }

    /// Whole minutes left, never below 1 while the lock is live.
    func minutesLeft(now: Date = Date()) -> Int {
        // Whole seconds first: a stored end time can come back a hair late and read as an extra minute.
        max(1, Int(ceil(endsAt.timeIntervalSince(now).rounded() / 60)))
    }
}
