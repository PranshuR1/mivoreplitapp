import Foundation
import os
import UserNotifications
#if canImport(FamilyControls)
import FamilyControls
#endif
#if canImport(ManagedSettings)
import ManagedSettings
#endif
#if canImport(DeviceActivity)
import DeviceActivity
#endif

/// Things that stopped a lock from shielding anything. Shown plainly instead of
/// starting a lock that blocks nothing.
enum LockInLimitation: Equatable {
    case screenTimeNotAuthorized
    case noAppsSelected

    var message: String {
        switch self {
        case .screenTimeNotAuthorized: return "Mivo needs Screen Time access to lock apps."
        case .noAppsSelected: return "Choose at least one app to lock."
        }
    }
}

struct LockInScreenTimeStart: Equatable {
    var limitations: [LockInLimitation] = []
    var shieldApplied: Bool { limitations.isEmpty }
}

/// The boundary between Lock-in and Screen Time. Everything that touches
/// `ManagedSettings` or `DeviceActivity` for a lock goes through here, so the rules
/// in `LockInManager` can be tested without a device.
@MainActor
protocol LockInScreenTimeControlling: AnyObject {
    var isAuthorized: Bool { get }
    /// Shields the lock's apps and arms the end alarm. Starts nothing when it
    /// reports a limitation.
    func start(lock: LockIn) -> LockInScreenTimeStart
    /// Lifts the shield and tears down every alarm. Safe to call when nothing is live.
    func end()
    /// Makes the shield match the live lock. Returns whether a lock is live.
    @discardableResult
    func reconcile(now: Date) -> Bool
    /// Whether a tap on a lock's shield asked to open Mivo since last asked.
    func consumePendingRoute() -> Bool
}

/// Used where Screen Time does not exist (previews, tests, unsupported OS).
@MainActor
final class NoopLockInScreenTime: LockInScreenTimeControlling {
    var isAuthorized = true
    var pendingRoute = false
    private(set) var started: [String] = []
    private(set) var endCount = 0
    private(set) var live = false

    init() {}

    func start(lock: LockIn) -> LockInScreenTimeStart {
        var result = LockInScreenTimeStart()
        if !isAuthorized { result.limitations.append(.screenTimeNotAuthorized) }
        if lock.apps.isEmpty { result.limitations.append(.noAppsSelected) }
        if result.limitations.isEmpty {
            started.append(lock.id)
            live = true
        }
        return result
    }

    func end() {
        endCount += 1
        live = false
    }

    func reconcile(now: Date) -> Bool { live }

    func consumePendingRoute() -> Bool {
        defer { pendingRoute = false }
        return pendingRoute
    }
}

#if canImport(FamilyControls) && canImport(ManagedSettings) && canImport(DeviceActivity)

// MARK: - Selection bridging

extension ScreenTimeAppSelection {
    /// Captures a picker selection: the persisted data, plus counts and
    /// best-effort names for showing it back.
    init(_ selection: FamilyActivitySelection) {
        let data = try? JSONEncoder().encode(selection)
        let names = selection.applicationTokens
            .compactMap { Application(token: $0).localizedDisplayName }
            .sorted()
        self.init(
            data: data,
            appNames: names,
            applicationCount: selection.applicationTokens.count,
            categoryCount: selection.categoryTokens.count,
            webDomainCount: selection.webDomainTokens.count
        )
    }

    var activitySelection: FamilyActivitySelection {
        guard let data, let selection = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data) else {
            return FamilyActivitySelection()
        }
        return selection
    }
}

@MainActor
final class LockInScreenTime: LockInScreenTimeControlling {
    private let defaults: UserDefaults?
    private let logger = Logger(subsystem: "com.mivo.mivoapp", category: "LockIn")
    private static let endNotificationID = "mivo.lockin.ended"

    init(defaults: UserDefaults? = UserDefaults(suiteName: LockInKeys.appGroup)) {
        self.defaults = defaults
    }

    var isAuthorized: Bool { FamilyControlsManager.shared.liveAuthorizationStatus() }

    private var store: ManagedSettingsStore {
        ManagedSettingsStore(named: ManagedSettingsStore.Name(LockInKeys.storeName))
    }

    // MARK: Start / end

    func start(lock: LockIn) -> LockInScreenTimeStart {
        var result = LockInScreenTimeStart()
        if !isAuthorized { result.limitations.append(.screenTimeNotAuthorized) }
        if lock.apps.isEmpty { result.limitations.append(.noAppsSelected) }
        guard result.limitations.isEmpty else { return result }

        writeLiveState(lock)
        applyShield(lock.apps.activitySelection)
        scheduleEndAlarm(at: lock.endsAt)
        scheduleEndNotification(at: lock.endsAt)
        logger.info("Lock-in started; shield applied until \(lock.endsAt)")
        return result
    }

    func end() {
        clearShield()
        stopActivity(LockInKeys.endActivityName)
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [Self.endNotificationID])
        guard let defaults else { return }
        for key in [
            LockInKeys.liveActive, LockInKeys.liveID, LockInKeys.liveTask,
            LockInKeys.liveEndsAt, LockInKeys.liveSelection,
            LockInKeys.pendingRoute, LockInKeys.pendingAt
        ] {
            defaults.removeObject(forKey: key)
        }
        defaults.synchronize()
        logger.info("Lock-in ended; shield lifted")
    }

    @discardableResult
    func reconcile(now: Date) -> Bool {
        guard LockInLiveState.read(from: defaults, now: now) != nil else {
            clearShield()
            return false
        }
        guard isAuthorized else { return true }
        if let data = defaults?.data(forKey: LockInKeys.liveSelection),
           let selection = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data) {
            applyShield(selection)
        }
        return true
    }

    func consumePendingRoute() -> Bool {
        guard let defaults, defaults.string(forKey: LockInKeys.pendingRoute) != nil else { return false }
        let at = defaults.double(forKey: LockInKeys.pendingAt)
        defaults.removeObject(forKey: LockInKeys.pendingRoute)
        defaults.removeObject(forKey: LockInKeys.pendingAt)
        defaults.synchronize()
        // A request older than ten minutes is a stale tap, not a request.
        if at > 0, Date().timeIntervalSince1970 - at > 600 { return false }
        return true
    }

    // MARK: Shield store

    private func applyShield(_ selection: FamilyActivitySelection) {
        let store = store
        store.shield.applications = selection.applicationTokens.isEmpty ? nil : selection.applicationTokens
        store.shield.applicationCategories = selection.categoryTokens.isEmpty ? nil : .specific(selection.categoryTokens)
        store.shield.webDomains = selection.webDomainTokens.isEmpty ? nil : selection.webDomainTokens
    }

    private func clearShield() {
        let store = store
        store.shield.applications = nil
        store.shield.applicationCategories = nil
        store.shield.webDomains = nil
    }

    // MARK: Live state

    private func writeLiveState(_ lock: LockIn) {
        guard let defaults else { return }
        defaults.set(true, forKey: LockInKeys.liveActive)
        defaults.set(lock.id, forKey: LockInKeys.liveID)
        defaults.set(lock.task, forKey: LockInKeys.liveTask)
        defaults.set(lock.endsAt.timeIntervalSince1970, forKey: LockInKeys.liveEndsAt)
        defaults.removeObject(forKey: LockInKeys.pendingRoute)
        defaults.removeObject(forKey: LockInKeys.pendingAt)
        if let data = lock.apps.data {
            defaults.set(data, forKey: LockInKeys.liveSelection)
        } else {
            defaults.removeObject(forKey: LockInKeys.liveSelection)
        }
        defaults.synchronize()
    }

    // MARK: Alarms

    /// Same trick the Still lock uses: the schedule *starts* at the moment
    /// the lock must end, so iOS wakes the monitor extension then — even if Mivo was
    /// closed — and the extension lifts the shield.
    private func scheduleEndAlarm(at date: Date) {
        let center = DeviceActivityCenter()
        let activity = DeviceActivityName(LockInKeys.endActivityName)
        center.stopMonitoring([activity])
        let start = max(date, Date().addingTimeInterval(30))
        let schedule = DeviceActivitySchedule(
            intervalStart: Self.components(start),
            intervalEnd: Self.components(start.addingTimeInterval(7200)),
            repeats: false
        )
        do {
            try center.startMonitoring(activity, during: schedule)
        } catch {
            logger.warning("Lock-in end alarm failed: \(error.localizedDescription)")
        }
    }

    private func stopActivity(_ name: String) {
        DeviceActivityCenter().stopMonitoring([DeviceActivityName(name)])
    }

    private static func components(_ date: Date) -> DateComponents {
        Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
    }

    private func scheduleEndNotification(at date: Date) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [Self.endNotificationID])
        let delay = date.timeIntervalSinceNow
        guard delay > 1 else { return }

        let content = UNMutableNotificationContent()
        content.title = "Your lock ran out"
        content.body = "Your apps are open again. Tap to see how it went."
        content.sound = .default
        content.userInfo = ["mivoRoute": LockInKeys.notificationRoute]
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false)
        center.add(UNNotificationRequest(identifier: Self.endNotificationID, content: content, trigger: trigger))
    }
}

#endif
