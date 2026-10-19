import DeviceActivity
import FamilyControls
import Foundation
import ManagedSettings
import os
import UserNotifications

@available(iOS 16.0, *)
final class MivoSessionRelockMonitor: DeviceActivityMonitor {
    private let logger = Logger(subsystem: "com.mivo.mivoapp", category: "DeviceActivityMonitor")
    private let appGroup = "group.com.mivo.mivoapp"
    private let selectionKey = "mivo.familyActivitySelection"
    private let protectionEnabledKey = "mivo.impulseProtectionEnabled"
    private let signedInKey = "mivo.impulseProtectionSignedIn"
    private let sessionActiveKey = "mivo.sessionActive"
    private let sessionEndsAtKey = "mivo.sessionEndsAt"
    private let pendingInterventionSetupKey = "mivo.pendingInterventionSetup"
    private let pendingInterventionSetupAtKey = "mivo.pendingInterventionSetupAt"
    private let countdownUntilKey = "mivo.shieldCountdownUntil"
    private let countdownRemainingKey = "mivo.shieldCountdownRemaining"
    private let sessionExpiredAtKey = "mivo.sessionExpiredAt"
    private let sessionExpiredSourceKey = "mivo.sessionExpiredSource"
    private let lastShieldSourceKey = "mivo.lastShieldSource"
    private let sessionMonitorDidStartAtKey = "mivo.sessionMonitorDidStartAt"
    private let sessionMonitorDidEndAtKey = "mivo.sessionMonitorDidEndAt"
    private let lastSessionMonitorCallbackKey = "mivo.lastSessionMonitorCallback"
    private let sessionRelockActivityName = "mivo.session.relock"
    private let sessionEndWatcherActivityName = "mivo.session.endwatcher"
    private let leaseEnforcementActivityName = "mivo.lease.enforcement"
    private let sessionLeaseStartedAtKey = "mivo.sessionLeaseStartedAt"
    private let sessionLeaseEndsAtKey = "mivo.sessionLeaseEndsAt"
    private let sessionLeaseDurationSecondsKey = "mivo.sessionLeaseDurationSeconds"
    private let leaseMonitorDidStartAtKey = "mivo.leaseMonitorDidStartAt"
    private let leaseMonitorDidEndAtKey = "mivo.leaseMonitorDidEndAt"
    private let stillLockActivityName = "mivo.still.lock"
    private let stillLockActiveKey = "mivo.still.lock.active"
    private let stillLockEndsAtKey = "mivo.still.lock.endsAt"
    private let crossDeviceFocusActivityName = "mivo.crossDeviceFocus.clear"
    private let crossDeviceFocusActiveKey = "mivo.crossDeviceFocus.active"
    private let crossDeviceFocusEndsAtKey = "mivo.crossDeviceFocus.endsAt"
    private let crossDeviceFocusPollActivityName = "mivo.crossDeviceFocus.poll"
    private let alwaysBlockDriftActivityName = "mivo.alwaysBlockDrift.clear"
    private let alwaysBlockDriftActiveKey = "mivo.alwaysBlockDrift.active"
    private let alwaysBlockDriftArmedDateKey = "mivo.alwaysBlockDrift.armedDate"
    private let alwaysBlockDriftStore = ManagedSettingsStore(named: ManagedSettingsStore.Name("mivo.alwaysBlockDrift"))
    private let crossDeviceFocusCachedAccessTokenKey = "mivo.crossDeviceFocus.cachedAccessToken"
    private let crossDeviceFocusCachedUserIdKey = "mivo.crossDeviceFocus.cachedUserId"
    // Same literal values as Mivo/Info.plist's MIVO_SUPABASE_URL/MIVO_SUPABASE_ANON_KEY.
    // Bundle.main inside an extension resolves to the extension's own Info.plist, not
    // the host app's, so these can't be read the way RemoteAuthService reads them —
    // duplicated here the same way every other literal key in this file already is.
    private let supabaseBaseURLString = "https://pgmbqxcshgvznxdbpyre.supabase.co"
    private let supabaseAnonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InBnbWJxeGNzaGd2em54ZGJweXJlIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODAwNTM5NDMsImV4cCI6MjA5NTYyOTk0M30.-Q1t6Ao6xDyuxWkdgofn0br2l0WjVVj9YqIOeH3aLT8"
    private let store = ManagedSettingsStore(named: ManagedSettingsStore.Name("mivo.intervention"))
    private let legacyStore = ManagedSettingsStore()
    private let stillLockStore = ManagedSettingsStore(named: ManagedSettingsStore.Name("mivo.stillLock"))
    private let crossDeviceFocusStore = ManagedSettingsStore(named: ManagedSettingsStore.Name("mivo.crossDeviceFocus"))

    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)
        logger.info("intervalDidStart: activity=\(activity.rawValue)")

        // Schedules are now arranged so intervalStart = desired relock time.
        // iOS fires intervalDidStart reliably (must launch extension to begin usage counting).
        if activity.rawValue == sessionRelockActivityName {
            // Fires at session-end time — re-lock immediately.
            relockForEndedSession(source: "session-end")
            return
        }
        if activity.rawValue == leaseEnforcementActivityName {
            // Fires at lease-end time — check session state and re-lock.
            relockForActiveSessionCheckIn(source: "lease-end")
            return
        }
        if activity.rawValue == "mivo.blocker.selftest" {
            guard let defaults = UserDefaults(suiteName: appGroup) else { return }
            defaults.set(ISO8601DateFormatter().string(from: Date()), forKey: "mivo.blockerSelfTestStart")
            defaults.synchronize()
            return
        }
        if activity.rawValue == stillLockActivityName {
            // Fires at the Lock Mode end time — lift the block immediately.
            endStillLock()
            return
        }
        if activity.rawValue == crossDeviceFocusActivityName {
            // Fires at the Mac session's endsAt — lift the cross-device
            // lock even if Mivo was never reopened after the Mac ended it.
            endCrossDeviceFocus()
            return
        }
        if activity.rawValue == crossDeviceFocusPollActivityName {
            // Fires every few minutes regardless of app state — the only
            // thing that actually discovers a *new* Mac command while the
            // phone is locked/backgrounded. See the key's doc comment in
            // MivoScreenTimeKeys.swift for why this exists alongside the
            // BGAppRefreshTask fallback.
            pollCrossDeviceFocus()
            return
        }
        if activity.rawValue == alwaysBlockDriftActivityName {
            // Fires at local midnight — lifts "always block drifting apps"
            // even if Mivo was never reopened, matching Still Lock's own
            // reliable-clear pattern above.
            endAlwaysBlockDrift()
            return
        }
    }

    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        logger.info("intervalDidEnd: activity=\(activity.rawValue)")
        if activity.rawValue == leaseEnforcementActivityName {
            relockForActiveSessionCheckIn(source: "active-check-in")
            return
        }
        // Backup watcher: interval ends at session-end time — fire relock here too.
        if activity.rawValue == sessionEndWatcherActivityName {
            relockForEndedSession(source: "endwatcher-end")
            return
        }
        if activity.rawValue == "mivo.blocker.selftest" {
            guard let defaults = UserDefaults(suiteName: appGroup) else { return }
            defaults.set(ISO8601DateFormatter().string(from: Date()), forKey: "mivo.blockerSelfTestEnd")
            defaults.set(true, forKey: "mivo.blockerSelfTestPassed")
            defaults.synchronize()
            return
        }
        // Backup trigger for Lock Mode — the window closing is a second
        // chance to fire alongside intervalDidStart above.
        if activity.rawValue == stillLockActivityName {
            endStillLock()
            return
        }
        if activity.rawValue == crossDeviceFocusActivityName {
            endCrossDeviceFocus()
            return
        }
        if activity.rawValue == crossDeviceFocusPollActivityName {
            pollCrossDeviceFocus()
            return
        }
        if activity.rawValue == alwaysBlockDriftActivityName {
            endAlwaysBlockDrift()
            return
        }
        // Primary fallback for relock schedule.
        guard activity.rawValue == sessionRelockActivityName else { return }
        relockForEndedSession(source: "session-end")
    }

    override func eventDidReachThreshold(_ event: DeviceActivityEvent.Name, activity: DeviceActivityName) {
        super.eventDidReachThreshold(event, activity: activity)
        logger.info("eventDidReachThreshold: event=\(event.rawValue) activity=\(activity.rawValue)")
        // Watcher usage limit: user consumed the full session duration while interval was active.
        if activity.rawValue == sessionEndWatcherActivityName {
            relockForEndedSession(source: "endwatcher-usage")
            return
        }
        guard activity.rawValue == sessionRelockActivityName else { return }
        relockForEndedSession(source: "usage-limit")
    }

    private func relockForEndedSession(source: String) {
        logger.info("relockForEndedSession: source=\(source)")
        guard let defaults = UserDefaults(suiteName: appGroup) else { return }

        let now = Date().timeIntervalSince1970
        defaults.set(false, forKey: sessionActiveKey)
        defaults.removeObject(forKey: sessionEndsAtKey)
        defaults.set(true, forKey: pendingInterventionSetupKey)
        defaults.set(now, forKey: pendingInterventionSetupAtKey)
        defaults.set(now, forKey: sessionExpiredAtKey)
        defaults.set(source, forKey: sessionExpiredSourceKey)
        defaults.set(source, forKey: lastShieldSourceKey)
        defaults.set(now, forKey: sessionMonitorDidEndAtKey)
        defaults.set(source, forKey: lastSessionMonitorCallbackKey)
        defaults.removeObject(forKey: countdownUntilKey)
        defaults.removeObject(forKey: countdownRemainingKey)
        defaults.synchronize()

        guard defaults.bool(forKey: protectionEnabledKey),
              defaults.bool(forKey: signedInKey),
              let data = defaults.data(forKey: selectionKey),
              let selection = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data) else {
            logger.warning("relockForEndedSession: protection disabled or no selection — clearing all shields")
            clearAllShields()
            return
        }

        apply(selection: selection, to: store)
        apply(selection: selection, to: legacyStore)
        clearSessionEndNudgesAfterRelock()
        logger.info("Shield re-applied in extension: apps=\(selection.applicationTokens.count) categories=\(selection.categoryTokens.count) domains=\(selection.webDomainTokens.count)")
    }

    private func relockForActiveSessionCheckIn(source: String) {
        logger.info("relockForActiveSessionCheckIn: source=\(source)")
        guard let defaults = UserDefaults(suiteName: appGroup) else { return }

        let now = Date().timeIntervalSince1970
        defaults.removeObject(forKey: sessionLeaseStartedAtKey)
        defaults.removeObject(forKey: sessionLeaseEndsAtKey)
        defaults.removeObject(forKey: sessionLeaseDurationSecondsKey)
        defaults.set(now, forKey: leaseMonitorDidEndAtKey)
        defaults.set(source, forKey: lastShieldSourceKey)
        defaults.removeObject(forKey: countdownUntilKey)
        defaults.removeObject(forKey: countdownRemainingKey)

        let endsAt = defaults.double(forKey: sessionEndsAtKey)
        guard defaults.bool(forKey: sessionActiveKey), endsAt > now else {
            logger.info("relockForActiveSessionCheckIn: session ended — falling through to relockForEndedSession")
            defaults.synchronize()
            relockForEndedSession(source: "session-end")
            return
        }

        defaults.synchronize()
        logger.info("relockForActiveSessionCheckIn: session still active — re-applying shield for check-in")
        applySelectedAppShield(defaults: defaults)
    }

    private func applySelectedAppShield(defaults: UserDefaults) {
        guard defaults.bool(forKey: protectionEnabledKey),
              defaults.bool(forKey: signedInKey),
              let data = defaults.data(forKey: selectionKey),
              let selection = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data) else {
            clearAllShields()
            return
        }

        apply(selection: selection, to: store)
        apply(selection: selection, to: legacyStore)
    }

    private func recordCallback(key: String, source: String) {
        guard let defaults = UserDefaults(suiteName: appGroup) else { return }
        defaults.set(Date().timeIntervalSince1970, forKey: key)
        defaults.set(source, forKey: lastSessionMonitorCallbackKey)
        defaults.synchronize()
    }

    private func clearAllShields() {
        clear(store: store)
        clear(store: legacyStore)
    }

    /// Unconditional clear — unlike `relockForEndedSession`, there is no
    /// `FamilyActivitySelection` to look up: Lock Mode shields every category,
    /// so lifting it is just clearing the one dedicated store.
    private func endStillLock() {
        stillLockStore.shield.applicationCategories = nil
        guard let defaults = UserDefaults(suiteName: appGroup) else { return }
        defaults.set(false, forKey: stillLockActiveKey)
        defaults.removeObject(forKey: stillLockEndsAtKey)
        defaults.synchronize()
        logger.info("Still Lock ended from extension")
    }

    /// Unconditional clear, same shape as `endStillLock()` — "Block my
    /// iPhone too" shields every category, so there's no per-app selection
    /// to look up, just the one dedicated store.
    private func endCrossDeviceFocus() {
        crossDeviceFocusStore.shield.applicationCategories = nil
        guard let defaults = UserDefaults(suiteName: appGroup) else { return }
        defaults.set(false, forKey: crossDeviceFocusActiveKey)
        defaults.removeObject(forKey: crossDeviceFocusEndsAtKey)
        defaults.synchronize()
        logger.info("Cross-device focus lock ended from extension")
    }

    /// Checks Supabase directly for an active "Block my iPhone too" command
    /// using whatever credentials `CrossDeviceFocusService.reconcile()` last
    /// cached, applies/clears the shield accordingly, and re-arms itself for
    /// another poll a few minutes out — regardless of outcome, so a single
    /// network hiccup doesn't end the chain.
    ///
    /// Runs the network request synchronously (via a semaphore) because
    /// `DeviceActivityMonitor` override methods aren't `async` and the
    /// system may suspend this process as soon as one returns — there's no
    /// other way to guarantee the request actually completes first.
    private func pollCrossDeviceFocus() {
        defer { rearmCrossDeviceFocusPoll() }

        guard let defaults = UserDefaults(suiteName: appGroup),
              let token = defaults.string(forKey: crossDeviceFocusCachedAccessTokenKey), !token.isEmpty,
              let userId = defaults.string(forKey: crossDeviceFocusCachedUserIdKey), !userId.isEmpty,
              let encodedUserId = userId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let encodedNow = ISO8601DateFormatter().string(from: Date()).addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "\(supabaseBaseURLString)/rest/v1/cross_device_focus_sessions?select=*&user_id=eq.\(encodedUserId)&status=eq.active&block_phone=eq.true&ends_at=gt.\(encodedNow)&order=ends_at.desc&limit=1")
        else {
            logger.warning("pollCrossDeviceFocus: no cached credentials — skipping this cycle")
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 10

        var responseData: Data?
        var succeeded = false
        let semaphore = DispatchSemaphore(value: 0)
        let task = URLSession.shared.dataTask(with: request) { data, response, _ in
            if let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) {
                responseData = data
                succeeded = true
            }
            semaphore.signal()
        }
        task.resume()
        _ = semaphore.wait(timeout: .now() + 12)

        // Network/auth failure: leave whatever shield state already exists
        // alone rather than risk clearing an actually-active session on a
        // transient hiccup — the next poll cycle tries again.
        guard succeeded else {
            logger.warning("pollCrossDeviceFocus: request did not succeed this cycle")
            return
        }

        var endsAt: Date?
        if let responseData {
            let decoder = JSONDecoder()
            struct MinimalCommand: Decodable {
                let endsAt: Date
                enum CodingKeys: String, CodingKey { case endsAt = "ends_at" }
            }
            decoder.dateDecodingStrategy = .iso8601
            endsAt = (try? decoder.decode([MinimalCommand].self, from: responseData))?.first?.endsAt
        }

        if let endsAt {
            crossDeviceFocusStore.shield.applicationCategories = .all()
            defaults.set(true, forKey: crossDeviceFocusActiveKey)
            defaults.set(endsAt.timeIntervalSince1970, forKey: crossDeviceFocusEndsAtKey)
            defaults.synchronize()
            scheduleCrossDeviceFocusClearAlarm(endsAt: endsAt)
            logger.info("pollCrossDeviceFocus: applied shield until \(endsAt)")
        } else {
            // Authoritative "no active command" — safe to clear.
            crossDeviceFocusStore.shield.applicationCategories = nil
            defaults.set(false, forKey: crossDeviceFocusActiveKey)
            defaults.removeObject(forKey: crossDeviceFocusEndsAtKey)
            defaults.synchronize()
            logger.info("pollCrossDeviceFocus: no active command, shield clear")
        }
    }

    /// Mirrors `FamilyControlsManager.scheduleCrossDeviceFocusDeviceActivityClear`
    /// — needed here too since a shield this poll applies might otherwise
    /// only ever be cleared by the main app being reopened after `endsAt`.
    private func scheduleCrossDeviceFocusClearAlarm(endsAt: Date) {
        let center = DeviceActivityCenter()
        let activity = DeviceActivityName(crossDeviceFocusActivityName)
        center.stopMonitoring([activity])
        let calendar = Calendar.current
        let start = max(endsAt, Date().addingTimeInterval(30))
        let end = start.addingTimeInterval(7200)
        let schedule = DeviceActivitySchedule(
            intervalStart: calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: start),
            intervalEnd: calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: end),
            repeats: false
        )
        try? center.startMonitoring(activity, during: schedule)
    }

    private func rearmCrossDeviceFocusPoll(after interval: TimeInterval = 5 * 60) {
        let center = DeviceActivityCenter()
        let activity = DeviceActivityName(crossDeviceFocusPollActivityName)
        center.stopMonitoring([activity])
        let calendar = Calendar.current
        let start = Date().addingTimeInterval(max(30, interval))
        let end = start.addingTimeInterval(7200)
        let schedule = DeviceActivitySchedule(
            intervalStart: calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: start),
            intervalEnd: calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: end),
            repeats: false
        )
        try? center.startMonitoring(activity, during: schedule)
    }

    /// Unconditional clear, same shape as `endStillLock()`/`endCrossDeviceFocus()`
    /// — "Always block drifting apps" shields one fixed selection, so
    /// there's nothing to look up, just the one dedicated store.
    private func endAlwaysBlockDrift() {
        alwaysBlockDriftStore.shield.applications = nil
        alwaysBlockDriftStore.shield.applicationCategories = nil
        alwaysBlockDriftStore.shield.webDomains = nil
        guard let defaults = UserDefaults(suiteName: appGroup) else { return }
        defaults.set(false, forKey: alwaysBlockDriftActiveKey)
        defaults.removeObject(forKey: alwaysBlockDriftArmedDateKey)
        defaults.synchronize()
        logger.info("Always-block-drift ended from extension (midnight)")
    }

    private func clearSessionEndNudgesAfterRelock() {
        let identifiers = [
            "mivo.session.ended.nudge1",
            "mivo.session.ended.nudge2"
        ]
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
        logger.info("Session-end follow-up notifications cleared after shield re-lock")
    }

    private func apply(selection: FamilyActivitySelection, to target: ManagedSettingsStore) {
        target.shield.applications = selection.applicationTokens.isEmpty ? nil : selection.applicationTokens
        target.shield.applicationCategories = selection.categoryTokens.isEmpty ? nil : .specific(selection.categoryTokens)
        target.shield.webDomains = selection.webDomainTokens.isEmpty ? nil : selection.webDomainTokens
    }

    private func clear(store target: ManagedSettingsStore) {
        target.shield.applications = nil
        target.shield.applicationCategories = nil
        target.shield.webDomains = nil
    }
}
