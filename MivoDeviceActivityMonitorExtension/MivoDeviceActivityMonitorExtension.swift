import DeviceActivity
import FamilyControls
import Foundation
import ManagedSettings
import os

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
    private let store = ManagedSettingsStore(named: ManagedSettingsStore.Name("mivo.intervention"))
    private let legacyStore = ManagedSettingsStore()

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
