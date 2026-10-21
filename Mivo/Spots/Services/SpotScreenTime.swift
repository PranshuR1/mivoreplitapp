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

/// Things that stopped a Spot from doing everything its mode asks for. Shown
/// plainly in the confirmation instead of failing silently.
enum SpotLimitation: Equatable {
    /// Screen Time access is off, so apps can't be paused and usage can't be watched.
    case screenTimeNotAuthorized
    case noAppsSelected
    /// iOS refused to start usage monitoring.
    case usageTrackingUnavailable
}

struct SpotScreenTimeStart: Equatable {
    var trackedApps: [SpotTrackedApp] = []
    var usageTracked = false
    var shieldApplied = false
    var limitations: [SpotLimitation] = []
}

/// What the monitor extension recorded while a Spot ran.
struct SpotUsageReading: Equatable {
    var totalMinutes: Int
    var perApp: [Int: Int]
}

enum SpotShieldRoute: String {
    case pause
    case intention
    case status
}

/// The boundary between Spots and Screen Time. Everything that touches
/// `ManagedSettings` or `DeviceActivity` for a Spot goes through here, so the
/// rules in `SpotManager` can be tested without a device.
@MainActor
protocol SpotScreenTimeControlling: AnyObject {
    var isAuthorized: Bool { get }
    func start(spot: MivoSpot, session: SpotSession) -> SpotScreenTimeStart
    /// Lets the person into the Spot's apps until `date`, then the shield returns.
    func liftShield(until date: Date)
    /// Lifts the shield for the remainder of the Spot (an answered Intention Check).
    func liftShieldForRestOfSpot()
    /// Makes the shield match what the live Spot wants right now. Idempotent.
    func reconcileShield(now: Date)
    func consumePendingRoute() -> (route: SpotShieldRoute, appName: String?)?
    func isLiveSpotRunning(now: Date) -> Bool
    /// Reads usage, then tears down every shield, monitor and alarm for the session.
    func finish(session: SpotSession) -> SpotUsageReading?
    /// Tears everything down without reading usage.
    func clearEverything()
}

/// Used where Screen Time does not exist (previews, tests, unsupported OS).
@MainActor
final class NoopSpotScreenTime: SpotScreenTimeControlling {
    var isAuthorized = false
    var pendingRoute: (route: SpotShieldRoute, appName: String?)?
    private(set) var started: [String] = []
    private(set) var finished: [String] = []
    private(set) var liftedUntil: Date?
    private(set) var liftedForRest = false
    private var running = false

    init() {}

    func start(spot: MivoSpot, session: SpotSession) -> SpotScreenTimeStart {
        started.append(session.id)
        running = true
        liftedUntil = nil
        liftedForRest = false
        return SpotScreenTimeStart(limitations: isAuthorized ? [] : [.screenTimeNotAuthorized])
    }

    func liftShield(until date: Date) { liftedUntil = date }
    func liftShieldForRestOfSpot() { liftedForRest = true }
    func reconcileShield(now: Date) {}
    func consumePendingRoute() -> (route: SpotShieldRoute, appName: String?)? {
        defer { pendingRoute = nil }
        return pendingRoute
    }
    func isLiveSpotRunning(now: Date) -> Bool { running }

    func finish(session: SpotSession) -> SpotUsageReading? {
        finished.append(session.id)
        running = false
        return nil
    }

    func clearEverything() { running = false }
}

#if canImport(FamilyControls) && canImport(ManagedSettings) && canImport(DeviceActivity)

// MARK: - Selection bridging

extension SpotAppSelection {
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

// MARK: - Real implementation

@MainActor
final class SpotScreenTime: SpotScreenTimeControlling {
    private let defaults: UserDefaults?
    private let logger = Logger(subsystem: "com.mivo.mivoapp", category: "Spots")
    private static let endNotificationID = "mivo.spot.ended"

    init(defaults: UserDefaults? = UserDefaults(suiteName: SpotKeys.appGroup)) {
        self.defaults = defaults
    }

    var isAuthorized: Bool { FamilyControlsManager.shared.liveAuthorizationStatus() }

    private var store: ManagedSettingsStore {
        ManagedSettingsStore(named: ManagedSettingsStore.Name(SpotKeys.storeName))
    }

    // MARK: Start

    func start(spot: MivoSpot, session: SpotSession) -> SpotScreenTimeStart {
        var result = SpotScreenTimeStart()
        let selection = spot.selectedApplications.activitySelection
        let hasApps = !spot.selectedApplications.isEmpty
        let authorized = isAuthorized

        if !hasApps { result.limitations.append(.noAppsSelected) }
        if !authorized { result.limitations.append(.screenTimeNotAuthorized) }

        writeLiveState(spot: spot, session: session)

        if authorized && hasApps {
            result.trackedApps = Self.trackedApps(from: selection)
            if spot.mode.usesShield {
                applyShield(selection)
                result.shieldApplied = true
            }
            result.usageTracked = startUsageMonitoring(
                selection: selection,
                trackedApps: result.trackedApps,
                endsAt: session.plannedEndDate
            )
            if !result.usageTracked { result.limitations.append(.usageTrackingUnavailable) }
        } else {
            clearShield()
        }

        scheduleEndAlarm(at: session.plannedEndDate)
        scheduleEndNotification(for: session)

        if spot.mode == .focus, ProductExpansionStore.shared.isEnabled(.liveActivities) {
            FamilyControlsManager.shared.startSessionLiveActivity(
                sessionEndsAt: session.plannedEndDate,
                planMinutes: max(1, Int((session.plannedEndDate.timeIntervalSince(session.startDate) / 60).rounded())),
                intentionLabel: spot.name,
                kind: "focus"
            )
        }
        return result
    }

    // MARK: Shield

    func liftShield(until date: Date) {
        clearShield()
        defaults?.set(date.timeIntervalSince1970, forKey: SpotKeys.liveShieldLiftedUntil)
        defaults?.synchronize()
        scheduleRelockAlarm(at: date)
    }

    func liftShieldForRestOfSpot() {
        clearShield()
        defaults?.set(true, forKey: SpotKeys.liveIntentionDone)
        defaults?.synchronize()
    }

    func reconcileShield(now: Date) {
        guard let live = SpotLiveState.read(from: defaults, now: now) else {
            clearShield()
            return
        }
        guard isAuthorized else { return }
        if live.wantsShield(at: now) {
            if let data = defaults?.data(forKey: SpotKeys.liveSelection),
               let selection = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data) {
                applyShield(selection)
                if live.liftedUntil != nil {
                    defaults?.removeObject(forKey: SpotKeys.liveShieldLiftedUntil)
                    stopActivity(SpotKeys.relockActivityName)
                }
            }
        } else {
            clearShield()
        }
    }

    func consumePendingRoute() -> (route: SpotShieldRoute, appName: String?)? {
        guard let defaults, let raw = defaults.string(forKey: SpotKeys.pendingRoute),
              let route = SpotShieldRoute(rawValue: raw) else { return nil }
        let at = defaults.double(forKey: SpotKeys.pendingAt)
        let appName = defaults.string(forKey: SpotKeys.pendingAppName)
        defaults.removeObject(forKey: SpotKeys.pendingRoute)
        defaults.removeObject(forKey: SpotKeys.pendingAppName)
        defaults.removeObject(forKey: SpotKeys.pendingAt)
        defaults.synchronize()
        // A request older than ten minutes is a stale tap, not a request.
        if at > 0, Date().timeIntervalSince1970 - at > 600 { return nil }
        return (route, appName)
    }

    func isLiveSpotRunning(now: Date) -> Bool {
        SpotLiveState.read(from: defaults, now: now) != nil
    }

    // MARK: Finish

    func finish(session: SpotSession) -> SpotUsageReading? {
        let reading = readUsage(for: session)
        clearEverything()
        if session.mode == .focus, !FamilyControlsManager.shared.isStillLockActive() {
            FamilyControlsManager.shared.endFocusLiveActivity()
        }
        return reading
    }

    func clearEverything() {
        clearShield()
        stopActivity(SpotKeys.usageActivityName)
        stopActivity(SpotKeys.endActivityName)
        stopActivity(SpotKeys.relockActivityName)
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [Self.endNotificationID])
        guard let defaults else { return }
        for key in [
            SpotKeys.liveActive, SpotKeys.liveSessionID, SpotKeys.liveSpotID, SpotKeys.liveName,
            SpotKeys.liveMode, SpotKeys.liveEndsAt, SpotKeys.liveShieldLiftedUntil,
            SpotKeys.liveIntentionDone, SpotKeys.liveSelection, SpotKeys.pendingRoute,
            SpotKeys.pendingAppName, SpotKeys.pendingAt, SpotKeys.usageLive, SpotKeys.usageSessionID
        ] {
            defaults.removeObject(forKey: key)
        }
        defaults.synchronize()
    }

    // MARK: Usage

    private func readUsage(for session: SpotSession) -> SpotUsageReading? {
        guard session.usageTracked, let defaults,
              defaults.string(forKey: SpotKeys.usageSessionID) == session.id else { return nil }
        let raw = defaults.dictionary(forKey: SpotKeys.usageLive) ?? [:]
        var tally: [String: Int] = [:]
        for (key, value) in raw { if let minutes = value as? Int { tally[key] = minutes } }

        var perApp: [Int: Int] = [:]
        for app in session.trackedApps {
            perApp[app.index] = SpotUsageLadder.minutes(for: .app(app.index), in: tally)
        }
        // The Spot total and the per-app ladders are separate events; never report
        // a total smaller than a single app's time.
        let total = max(SpotUsageLadder.minutes(for: .all, in: tally), perApp.values.max() ?? 0)
        return SpotUsageReading(totalMinutes: total, perApp: perApp)
    }

    private func startUsageMonitoring(
        selection: FamilyActivitySelection,
        trackedApps: [SpotTrackedApp],
        endsAt: Date
    ) -> Bool {
        let center = DeviceActivityCenter()
        let activity = DeviceActivityName(SpotKeys.usageActivityName)
        center.stopMonitoring([activity])

        var events: [DeviceActivityEvent.Name: DeviceActivityEvent] = [:]
        for minutes in SpotUsageLadder.allMinutes {
            events[DeviceActivityEvent.Name(SpotUsageLadder.eventName(scope: .all, minutes: minutes))] =
                DeviceActivityEvent(
                    applications: selection.applicationTokens,
                    categories: selection.categoryTokens,
                    webDomains: selection.webDomainTokens,
                    threshold: DateComponents(minute: minutes)
                )
        }
        for app in trackedApps {
            guard let token = try? JSONDecoder().decode(ApplicationToken.self, from: app.tokenData) else { continue }
            for minutes in SpotUsageLadder.appMinutes {
                events[DeviceActivityEvent.Name(SpotUsageLadder.eventName(scope: .app(app.index), minutes: minutes))] =
                    DeviceActivityEvent(
                        applications: [token],
                        categories: [],
                        webDomains: [],
                        threshold: DateComponents(minute: minutes)
                    )
            }
        }

        // A schedule must span at least 15 minutes, so a short Spot still gets a
        // longer monitoring window; the Spot's own end stops it.
        let start = Date().addingTimeInterval(2)
        let end = max(endsAt.addingTimeInterval(60), start.addingTimeInterval(16 * 60))
        let schedule = DeviceActivitySchedule(
            intervalStart: Self.components(start),
            intervalEnd: Self.components(end),
            repeats: false
        )
        do {
            try center.startMonitoring(activity, during: schedule, events: events)
            logger.info("Spot usage monitoring started: \(events.count) events")
            return true
        } catch {
            logger.warning("Spot usage monitoring failed: \(error.localizedDescription)")
            return false
        }
    }

    /// The up-to-four apps measured individually, in a fixed order so the event
    /// names the extension receives can be matched back to an app.
    static func trackedApps(from selection: FamilyActivitySelection) -> [SpotTrackedApp] {
        let encoder = JSONEncoder()
        let entries: [(data: Data, name: String?)] = selection.applicationTokens.compactMap { token in
            guard let data = try? encoder.encode(token) else { return nil }
            return (data, Application(token: token).localizedDisplayName)
        }
        let ordered = entries.sorted { $0.data.base64EncodedString() < $1.data.base64EncodedString() }
        return ordered.prefix(SpotUsageLadder.maxTrackedApps).enumerated().map { index, entry in
            SpotTrackedApp(index: index, name: entry.name, tokenData: entry.data)
        }
    }

    // MARK: Alarms

    /// Same trick the Still lock uses: the schedule *starts* at the moment the
    /// Spot should end, so iOS wakes the monitor extension then — even if Mivo
    /// was closed — and the extension lifts the shield.
    private func scheduleEndAlarm(at date: Date) {
        scheduleAlarm(named: SpotKeys.endActivityName, at: date)
    }

    private func scheduleRelockAlarm(at date: Date) {
        scheduleAlarm(named: SpotKeys.relockActivityName, at: date)
    }

    private func scheduleAlarm(named name: String, at date: Date) {
        let center = DeviceActivityCenter()
        let activity = DeviceActivityName(name)
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
            logger.warning("Spot alarm \(name) failed: \(error.localizedDescription)")
        }
    }

    private func stopActivity(_ name: String) {
        DeviceActivityCenter().stopMonitoring([DeviceActivityName(name)])
    }

    private static func components(_ date: Date) -> DateComponents {
        Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
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

    private func writeLiveState(spot: MivoSpot, session: SpotSession) {
        guard let defaults else { return }
        defaults.set(true, forKey: SpotKeys.liveActive)
        defaults.set(session.id, forKey: SpotKeys.liveSessionID)
        defaults.set(spot.id, forKey: SpotKeys.liveSpotID)
        defaults.set(spot.name, forKey: SpotKeys.liveName)
        defaults.set(spot.mode.rawValue, forKey: SpotKeys.liveMode)
        defaults.set(session.plannedEndDate.timeIntervalSince1970, forKey: SpotKeys.liveEndsAt)
        defaults.removeObject(forKey: SpotKeys.liveShieldLiftedUntil)
        defaults.set(false, forKey: SpotKeys.liveIntentionDone)
        defaults.removeObject(forKey: SpotKeys.pendingRoute)
        defaults.removeObject(forKey: SpotKeys.pendingAppName)
        defaults.removeObject(forKey: SpotKeys.pendingAt)
        if let data = spot.selectedApplications.data {
            defaults.set(data, forKey: SpotKeys.liveSelection)
        } else {
            defaults.removeObject(forKey: SpotKeys.liveSelection)
        }
        defaults.set(session.id, forKey: SpotKeys.usageSessionID)
        defaults.removeObject(forKey: SpotKeys.usageLive)
        defaults.synchronize()
    }

    // MARK: Notification

    private func scheduleEndNotification(for session: SpotSession) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [Self.endNotificationID])
        let delay = session.plannedEndDate.timeIntervalSinceNow
        guard delay > 1 else { return }

        let content = UNMutableNotificationContent()
        content.title = "\(session.spotName) wrapped up"
        content.body = "Tap to see how it went."
        content.sound = .default
        content.userInfo = ["mivoRoute": SpotKeys.notificationRoute, "spotSummary": true]
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false)
        center.add(UNNotificationRequest(identifier: Self.endNotificationID, content: content, trigger: trigger))
    }
}

#endif
