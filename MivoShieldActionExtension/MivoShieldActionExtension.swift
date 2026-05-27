import FamilyControls
import Foundation
import ManagedSettings
import os
import UserNotifications
#if canImport(DeviceActivity)
import DeviceActivity
#endif

final class MivoShieldActionExtension: ShieldActionDelegate {
    private let logger = Logger(subsystem: "com.mivo.mivoapp", category: "ShieldAction")
    private let appGroup = "group.com.mivo.mivoapp"
    private let selectionKey = "mivo.familyActivitySelection"
    private let protectionEnabledKey = "mivo.impulseProtectionEnabled"
    private let signedInKey = "mivo.impulseProtectionSignedIn"
    private let sessionActiveKey = "mivo.sessionActive"
    private let sessionEndsAtKey = "mivo.sessionEndsAt"
    private let pendingInterventionSetupKey = "mivo.pendingInterventionSetup"
    private let pendingInterventionSetupAtKey = "mivo.pendingInterventionSetupAt"
    private let sessionExpiredAtKey = "mivo.sessionExpiredAt"
    private let sessionExpiredSourceKey = "mivo.sessionExpiredSource"
    private let countdownUntilKey = "mivo.shieldCountdownUntil"
    private let countdownRemainingKey = "mivo.shieldCountdownRemaining"
    private let checkInIntervalMinutesKey = "mivo.checkInIntervalMinutes"
    private let sessionLeaseStartedAtKey = "mivo.sessionLeaseStartedAt"
    private let sessionLeaseEndsAtKey = "mivo.sessionLeaseEndsAt"
    private let sessionLeaseDurationSecondsKey = "mivo.sessionLeaseDurationSeconds"
    private let leaseEnforcementActivityName = "mivo.lease.enforcement"
    private let leaseMonitorScheduledAtKey = "mivo.leaseMonitorScheduledAt"
    private let leaseMonitorDidEndAtKey = "mivo.leaseMonitorDidEndAt"
    private let lastScheduleErrorKey = "mivo.lastScheduleError"
    private let lastShieldSourceKey = "mivo.lastShieldSource"
    private let shieldPauseDurationKey = "mivo.shieldPauseDuration"

    /// Pause duration in seconds, reading the value the user set in Mivo settings.
    private var countdownDuration: TimeInterval {
        let stored = UserDefaults(suiteName: appGroup)?.integer(forKey: shieldPauseDurationKey) ?? 0
        guard stored > 0 else { return 5 }
        return TimeInterval(min(max(stored, 3), 30))
    }
    private let interventionRelockDelay: TimeInterval = 2
    private let defaultCheckInIntervalMinutes = 3
    private let pendingSetupFreshnessWindow: TimeInterval = 10 * 60
    private let store = ManagedSettingsStore(named: ManagedSettingsStore.Name("mivo.intervention"))
    private let legacyStore = ManagedSettingsStore()

    override func handle(
        action: ShieldAction,
        for application: ApplicationToken,
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        handleShieldAction(action: action, completionHandler: completionHandler)
    }

    override func handle(
        action: ShieldAction,
        for category: ActivityCategoryToken,
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        handleShieldAction(action: action, completionHandler: completionHandler)
    }

    override func handle(
        action: ShieldAction,
        for webDomain: WebDomainToken,
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        handleShieldAction(action: action, completionHandler: completionHandler)
    }

    // MARK: - Shared action handler

    private func handleShieldAction(
        action: ShieldAction,
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        switch action {

        case .primaryButtonPressed:
            if isCountingDownActive() {
                // Ignore taps while the hold is running
                logger.info("ShieldAction primary: countdown in progress → .defer")
                completionHandler(.defer)

            } else if isPendingSetupWithoutSession() {
                // "Open Mivo" state — user needs to go to Mivo to set their intention
                logger.info("ShieldAction primary: pending setup → opening Mivo")
                openMivoForIntervention()
                completionHandler(.defer)

            } else if isSessionActive() {
                // Active session check-in: primary now starts the 5-sec mid-scroll
                // pause and then unlocks the lease automatically — no second button.
                logger.info("ShieldAction primary: active session → mid-scroll 5s pause + unlock")
                beginCountdownForActiveSession(completionHandler: completionHandler)
                // DO NOT call completionHandler here — the countdown does it.

            } else {
                // Default "Start" — begin user-configured pause, then glimpse + re-lock.
                // We pass the completionHandler in and call it only after the countdown
                // finishes. This keeps the extension process alive for the full duration
                // so every asyncAfter tick fires reliably.
                logger.info("ShieldAction primary: no session → starting intervention countdown (\(self.countdownDuration)s)")
                beginCountdownForNewIntervention(completionHandler: completionHandler)
                // DO NOT call completionHandler here — it will be called from inside the countdown
            }

        case .secondaryButtonPressed:
            // The active-session check-in shield no longer offers a "Not now" option.
            // Treat any secondary press as a dismissal.
            logger.info("ShieldAction secondary: dismiss → .close")
            completionHandler(.close)

        @unknown default:
            completionHandler(.close)
        }
    }

    // MARK: - Countdown helpers

    /// Session-active countdown (used by "Continue session" secondary button).
    /// The completion handler is intentionally called only after the countdown finishes;
    /// returning early lets iOS suspend the extension before the one-second ticks run.
    private func beginCountdownForActiveSession(completionHandler: @escaping (ShieldActionResponse) -> Void) {
        let endTime = Date().addingTimeInterval(countdownDuration).timeIntervalSince1970
        updateCountdownDisplay(remaining: Int(countdownDuration), endTime: endTime)
        applyFullShieldDuringActiveSession(markSource: "active-check-in-countdown")

        // Tick twice per second so iOS has more opportunities to redraw the
        // shield and the user sees the pause progressing instead of looking
        // hung. The displayed remaining-seconds value still steps by 1.
        let totalSec = Int(countdownDuration)
        let ticksPerSecond = 2
        let totalTicks = totalSec * ticksPerSecond
        for tick in 1..<totalTicks {
            let delay = TimeInterval(tick) / TimeInterval(ticksPerSecond)
            let remaining = max(1, totalSec - tick / ticksPerSecond)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                self.updateCountdownDisplay(remaining: remaining, endTime: endTime)
                self.applyFullShieldDuringActiveSession(markSource: "active-check-in-countdown")
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + countdownDuration) {
            self.unlockActiveSessionShield()
            completionHandler(.defer)
        }
    }

    /// New-intervention countdown (used by "Start" primary button, no active session).
    /// Flow: N-second hold → immediately transition to "Open Mivo" shield that
    /// persists until the user taps it.  No app glimpse — going from pause to
    /// "Open Mivo" directly avoids leaking even a moment of access to the
    /// blocked app.
    ///
    /// `completionHandler` is called only AFTER the re-lock retries.  This keeps
    /// the extension process alive so every `asyncAfter` tick fires reliably.
    /// Calling the handler signals iOS the action is handled; `.defer` keeps the
    /// shield visible.
    private func beginCountdownForNewIntervention(completionHandler: @escaping (ShieldActionResponse) -> Void) {
        let duration = countdownDuration
        let endTime = Date().addingTimeInterval(duration).timeIntervalSince1970
        updateCountdownDisplay(remaining: Int(duration), endTime: endTime)

        // Tick twice per second so iOS has more chances to repaint the shield.
        // The shown remaining-seconds value still steps once per real second.
        let totalSec = Int(duration)
        let ticksPerSecond = 2
        let totalTicks = totalSec * ticksPerSecond
        for tick in 1..<totalTicks {
            let delay = TimeInterval(tick) / TimeInterval(ticksPerSecond)
            let remaining = max(1, totalSec - tick / ticksPerSecond)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                self.updateCountdownDisplay(remaining: remaining, endTime: endTime)
                self.apply(selection: self.loadSelection())
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            // Clear countdown keys, then flip directly to the "Open Mivo" state.
            // No glimpse: we re-apply the shield in the same tick so the user
            // never sees the blocked app between the pause and the Open Mivo screen.
            let defaults = UserDefaults(suiteName: self.appGroup)
            defaults?.removeObject(forKey: self.countdownUntilKey)
            defaults?.removeObject(forKey: self.countdownRemainingKey)
            defaults?.synchronize()

            self.requestInterventionSetup()
            self.apply(selection: self.loadSelection())

            // Belt-and-suspenders re-lock retries: 0.2 / 0.6 / 1.2 / 2.0 / 3.5
            // seconds after the countdown ends.  Each pass re-marks
            // pendingInterventionSetup and re-applies the shield in case the
            // prior call was suppressed.
            let retryOffsets: [TimeInterval] = [0.2, 0.6, 1.2, 2.0, 3.5]
            for offset in retryOffsets {
                DispatchQueue.main.asyncAfter(deadline: .now() + offset) {
                    self.requestInterventionSetup()
                    self.apply(selection: self.loadSelection())
                }
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
                completionHandler(.defer)
            }
        }
    }

    // MARK: - Open Mivo

    // NOTE ON iOS EXTENSION SANDBOX:
    // `ShieldActionDelegate` runs as `com.apple.ManagedSettings.shield-action-service`,
    // which is a pure SERVICE extension — it has its own sandboxed process with NO
    // UIApplication instance.  `NSClassFromString("UIApplication")` finds the class
    // (UIKit is linked) but `sharedApplication` returns nil, so the ObjC runtime trick
    // silently exits every time.
    //
    // The ONLY reliable mechanism for a service extension to open the host app is a
    // local notification.  We fire one with a 0.1-second delay so it appears as an
    // instant banner while the shield is still on screen.  Tapping the "Open Mivo"
    // action (or the banner body) launches Mivo; MivoAppDelegate.didReceive applies
    // shields and routes to the Interventions tab.
    //
    // We also attempt the UIApplication tricks in case a future iOS version loosens the
    // restriction — if they work, the main app cancels the pending notification in
    // onOpenURL before it fires.
    private func openMivoForIntervention() {
        let defaults = UserDefaults(suiteName: appGroup)
        defaults?.set(true, forKey: "mivo.openInterventionOnLaunch")
        defaults?.synchronize()

        guard let url = URL(string: "mivo://intervention") else { return }

        // ── Best-effort: UIApplication ObjC tricks ────────────────────────────────
        // These succeed only when UIApplication.shared exists in this process (it
        // doesn't in a service extension on current iOS, but we try anyway).

        if let appClass = NSClassFromString("UIApplication") as? NSObject.Type,
           let sharedApp = appClass.perform(NSSelectorFromString("sharedApplication"))?.takeUnretainedValue() as? NSObject {

            // Prefer the modern non-deprecated selector first.
            let modernSel = NSSelectorFromString("openURL:options:completionHandler:")
            if sharedApp.responds(to: modernSel),
               let imp = class_getMethodImplementation(object_getClass(sharedApp), modernSel) {
                // Signature: void(*)(id, SEL, NSURL*, NSDictionary*, void(^)(BOOL))
                typealias OpenImpl = @convention(c) (AnyObject, Selector, NSURL, NSDictionary, AnyObject?) -> Void
                let fn = unsafeBitCast(imp, to: OpenImpl.self)
                fn(sharedApp, modernSel, url as NSURL, [:] as NSDictionary, nil)
                logger.info("openMivoForIntervention: called openURL:options:completionHandler: ✓")
                // Don't return — schedule the notification fallback anyway; main app cancels it.
            } else {
                // Deprecated openURL: as last-resort ObjC attempt.
                let legacySel = NSSelectorFromString("openURL:")
                if sharedApp.responds(to: legacySel) {
                    sharedApp.perform(legacySel, with: url)
                    logger.info("openMivoForIntervention: called openURL: (deprecated)")
                }
            }
        } else {
            logger.warning("openMivoForIntervention: UIApplication.shared not available in this extension process (expected for service extensions)")
        }

        // ── Reliable fallback: immediate local notification ───────────────────────
        // Fires in 0.1 s — appears as a time-sensitive banner while the shield is
        // still visible.  Tapping "Open Mivo" action or the body launches the main
        // app; MivoAppDelegate applies shields and routes to the Interventions tab.
        // If the ObjC trick above actually worked, the main app cancels this
        // notification in its onOpenURL handler before it fires.
        fireOpenMivoNotification()
    }

    private func fireOpenMivoNotification() {
        let center = UNUserNotificationCenter.current()

        let content = UNMutableNotificationContent()
        content.title = "Open Mivo to set your intention"
        content.body = "Tap this notification to open Mivo and choose your session."
        content.sound = .default
        content.categoryIdentifier = "MIVO_SESSION_ENDED"
        content.userInfo = ["openIntervention": true]
        if #available(iOS 15.0, *) {
            content.interruptionLevel = .timeSensitive
        }

        // 0.1 s — fires almost instantly; feels like a direct response to the button tap.
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
        let request = UNNotificationRequest(
            identifier: "mivo.shield.openmivo",
            content: content,
            trigger: trigger
        )
        center.add(request) { [weak self] error in
            if let error {
                self?.logger.warning("fireOpenMivoNotification: failed to schedule — \(error.localizedDescription)")
            }
        }
        logger.info("openMivoForIntervention: immediate notification scheduled (0.1 s)")
    }

    // MARK: - State checks

    private func isCountingDownActive() -> Bool {
        guard let d = UserDefaults(suiteName: appGroup) else { return false }
        let endTime = d.double(forKey: countdownUntilKey)
        if endTime > 0 && endTime > Date().timeIntervalSince1970 { return true }
        return d.integer(forKey: countdownRemainingKey) > 0
    }

    private func isPendingSetupWithoutSession() -> Bool {
        guard let d = UserDefaults(suiteName: appGroup),
              d.bool(forKey: pendingInterventionSetupKey) else { return false }
        let createdAt = d.double(forKey: pendingInterventionSetupAtKey)
        if createdAt > 0 && Date().timeIntervalSince1970 - createdAt > pendingSetupFreshnessWindow {
            return false
        }
        return !isSessionActive()
    }

    private func updateCountdownDisplay(remaining: Int, endTime: TimeInterval) {
        let defaults = UserDefaults(suiteName: appGroup)
        defaults?.set(endTime, forKey: countdownUntilKey)
        defaults?.set(remaining, forKey: countdownRemainingKey)
        defaults?.synchronize()
    }

    private func unlock(application: ApplicationToken, relockDelay: TimeInterval, requestSetupOnRelock: Bool) {
        var selection = loadSelection()
        selection.applicationTokens.remove(application)
        if requestSetupOnRelock {
            requestInterventionSetup()
        }
        apply(selection: selection)
        scheduleRelock(after: relockDelay, requestSetupOnRelock: requestSetupOnRelock)
    }

    private func unlock(category: ActivityCategoryToken, relockDelay: TimeInterval, requestSetupOnRelock: Bool) {
        var selection = loadSelection()
        selection.categoryTokens.remove(category)
        if requestSetupOnRelock {
            requestInterventionSetup()
        }
        apply(selection: selection)
        scheduleRelock(after: relockDelay, requestSetupOnRelock: requestSetupOnRelock)
    }

    private func unlock(webDomain: WebDomainToken, relockDelay: TimeInterval, requestSetupOnRelock: Bool) {
        var selection = loadSelection()
        selection.webDomainTokens.remove(webDomain)
        if requestSetupOnRelock {
            requestInterventionSetup()
        }
        apply(selection: selection)
        scheduleRelock(after: relockDelay, requestSetupOnRelock: requestSetupOnRelock)
    }

    private func loadSelection() -> FamilyActivitySelection {
        guard let defaults = UserDefaults(suiteName: appGroup),
              let data = defaults.data(forKey: selectionKey),
              let selection = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data) else {
            return FamilyActivitySelection()
        }

        return selection
    }

    private func apply(selection: FamilyActivitySelection) {
        let defaults = UserDefaults(suiteName: appGroup)
        guard defaults?.bool(forKey: protectionEnabledKey) == true,
              defaults?.bool(forKey: signedInKey) == true else {
            clearAllShields()
            return
        }

        apply(selection: selection, to: store)
        apply(selection: selection, to: legacyStore)
    }

    private func scheduleRelock(after delay: TimeInterval, requestSetupOnRelock: Bool) {
        let defaults = UserDefaults(suiteName: appGroup)
        defaults?.removeObject(forKey: countdownUntilKey)
        defaults?.removeObject(forKey: countdownRemainingKey)
        defaults?.synchronize()

        let relockOffsets: [TimeInterval] = [delay, delay + 0.25, delay + 0.75, delay + 1.5, delay + 3.0]
        for offset in relockOffsets {
            DispatchQueue.main.asyncAfter(deadline: .now() + offset) {
                if requestSetupOnRelock {
                    self.requestInterventionSetup()
                }
                self.apply(selection: self.loadSelection())
            }
        }
    }


    private func clearAllShields() {
        clear(store: store)
        clear(store: legacyStore)
    }

    private func clearLegacyShield() {
        clear(store: legacyStore)
    }

    private func clear(store target: ManagedSettingsStore) {
        target.shield.applications = nil
        target.shield.applicationCategories = nil
        target.shield.webDomains = nil
    }

    private func unlockActiveSessionShield() {
        clearPendingInterventionSetup()
        let defaults = UserDefaults(suiteName: appGroup)
        defaults?.removeObject(forKey: countdownUntilKey)
        defaults?.removeObject(forKey: countdownRemainingKey)
        defaults?.synchronize()

        clearAllShields()
        scheduleActiveSessionLeaseRelock()
    }

    private func scheduleActiveSessionLeaseRelock() {
        let defaults = UserDefaults(suiteName: appGroup)
        let leaseDuration = activeSessionLeaseDuration()
        let now = Date()
        defaults?.set(now.timeIntervalSince1970, forKey: sessionLeaseStartedAtKey)
        defaults?.set(now.addingTimeInterval(leaseDuration).timeIntervalSince1970, forKey: sessionLeaseEndsAtKey)
        defaults?.set(Int(leaseDuration), forKey: sessionLeaseDurationSecondsKey)
        defaults?.set(now.timeIntervalSince1970, forKey: leaseMonitorScheduledAtKey)
        defaults?.synchronize()
        scheduleSystemLeaseRelock(after: leaseDuration)
        // Belt-and-suspenders: local notification fallback for the next check-in.
        // Fires even when the extension process dies before the DispatchQueue delays run.
        scheduleCheckInNotification(after: leaseDuration)

        let relockOffsets: [TimeInterval] = [leaseDuration, leaseDuration + 0.25, leaseDuration + 0.75, leaseDuration + 1.5, leaseDuration + 3.0]
        for offset in relockOffsets {
            DispatchQueue.main.asyncAfter(deadline: .now() + offset) {
                if self.isSessionActive() {
                    self.applyFullShieldDuringActiveSession(markSource: "active-lease-end")
                } else {
                    self.apply(selection: self.loadSelection())
                }
            }
        }
    }

    /// Schedules a local UNNotification for the next check-in time so the user is
    /// alerted even if the DispatchQueue delays above are killed with the extension process.
    private func scheduleCheckInNotification(after delay: TimeInterval) {
        guard delay >= 30 else { return }
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["mivo.session.checkIn"])

        let content = UNMutableNotificationContent()
        content.title = "Mivo check-in"
        content.body = "Your \(Int(delay / 60))-minute check-in is here. Open the blocked app to continue with a short pause."
        content.sound = .default
        content.categoryIdentifier = "MIVO_SESSION_ENDED"
        content.userInfo = ["mivoRoute": "checkIn"]
        if #available(iOS 15.0, *) {
            content.interruptionLevel = .timeSensitive
        }
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false)
        let request = UNNotificationRequest(identifier: "mivo.session.checkIn", content: content, trigger: trigger)
        center.add(request, withCompletionHandler: nil)
    }

    private func activeSessionLeaseDuration() -> TimeInterval {
        let defaults = UserDefaults(suiteName: appGroup)
        let storedMinutes = defaults?.integer(forKey: checkInIntervalMinutesKey) ?? 0
        let minutes = storedMinutes > 0 ? min(max(storedMinutes, 1), 10) : defaultCheckInIntervalMinutes
        let configuredDuration = TimeInterval(minutes * 60)

        guard let defaults,
              defaults.bool(forKey: sessionActiveKey) else {
            return configuredDuration
        }

        let endsAt = defaults.double(forKey: sessionEndsAtKey)
        guard endsAt > 0 else { return configuredDuration }
        let remaining = endsAt - Date().timeIntervalSince1970
        return max(1, min(configuredDuration, remaining))
    }

    @discardableResult
    private func scheduleSystemLeaseRelock(after delay: TimeInterval) -> Bool {
        #if canImport(DeviceActivity)
        guard #available(iOS 16.0, *) else { return false }

        let center = DeviceActivityCenter()
        let activity = DeviceActivityName(leaseEnforcementActivityName)
        center.stopMonitoring([activity])

        let calendar = Calendar.current
        let now = Date()
        // Schedule START = exact lease end time (second precision — no minute-rounding).
        let start = now.addingTimeInterval(max(30, delay))
        let end = start.addingTimeInterval(7200)

        let schedule = DeviceActivitySchedule(
            intervalStart: calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: start),
            intervalEnd: calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: end),
            repeats: false
        )

        do {
            try center.startMonitoring(activity, during: schedule)
            let defaults = UserDefaults(suiteName: appGroup)
            defaults?.set(now.timeIntervalSince1970, forKey: leaseMonitorScheduledAtKey)
            defaults?.removeObject(forKey: lastScheduleErrorKey)
            defaults?.synchronize()
            return true
        } catch {
            let defaults = UserDefaults(suiteName: appGroup)
            defaults?.set(error.localizedDescription, forKey: lastScheduleErrorKey)
            defaults?.synchronize()
            return false
        }
        #else
        return false
        #endif
    }

    private func applyFullShieldDuringActiveSession(markSource source: String = "active-lease-end") {
        let defaults = UserDefaults(suiteName: appGroup)
        guard defaults?.bool(forKey: protectionEnabledKey) == true,
              defaults?.bool(forKey: signedInKey) == true else {
            clearAllShields()
            return
        }

        let selection = loadSelection()
        apply(selection: selection, to: store)
        apply(selection: selection, to: legacyStore)
        defaults?.set(Date().timeIntervalSince1970, forKey: leaseMonitorDidEndAtKey)
        defaults?.set(source, forKey: lastShieldSourceKey)
        defaults?.synchronize()
    }

    private func apply(selection: FamilyActivitySelection, to target: ManagedSettingsStore) {
        target.shield.applications = selection.applicationTokens.isEmpty ? nil : selection.applicationTokens
        target.shield.applicationCategories = selection.categoryTokens.isEmpty ? nil : .specific(selection.categoryTokens)
        target.shield.webDomains = selection.webDomainTokens.isEmpty ? nil : selection.webDomainTokens
    }

    private func clearPendingInterventionSetup() {
        let defaults = UserDefaults(suiteName: appGroup)
        defaults?.set(false, forKey: pendingInterventionSetupKey)
        defaults?.removeObject(forKey: pendingInterventionSetupAtKey)
        defaults?.synchronize()
    }

    private func requestInterventionSetup() {
        let defaults = UserDefaults(suiteName: appGroup)
        defaults?.set(true, forKey: pendingInterventionSetupKey)
        defaults?.set(Date().timeIntervalSince1970, forKey: pendingInterventionSetupAtKey)
        defaults?.removeObject(forKey: sessionExpiredAtKey)
        defaults?.removeObject(forKey: sessionExpiredSourceKey)
        defaults?.removeObject(forKey: countdownUntilKey)
        defaults?.removeObject(forKey: countdownRemainingKey)
        defaults?.synchronize()
    }

    private func isInterventionSetupPending() -> Bool {
        guard let defaults = UserDefaults(suiteName: appGroup),
              defaults.bool(forKey: pendingInterventionSetupKey) else {
            return false
        }
        
        let createdAt = defaults.double(forKey: pendingInterventionSetupAtKey)
        guard createdAt > 0 else {
            clearStalePendingInterventionSetup(defaults)
            return false
        }
        
        if Date().timeIntervalSince1970 - createdAt > pendingSetupFreshnessWindow {
            clearStalePendingInterventionSetup(defaults)
            return false
        }
        
        return true
    }
    
    private func clearStalePendingInterventionSetup(_ defaults: UserDefaults) {
        defaults.set(false, forKey: pendingInterventionSetupKey)
        defaults.removeObject(forKey: pendingInterventionSetupAtKey)
        defaults.removeObject(forKey: countdownUntilKey)
        defaults.removeObject(forKey: countdownRemainingKey)
        defaults.synchronize()
    }

    private func isSessionActive() -> Bool {
        guard let defaults = UserDefaults(suiteName: appGroup),
              defaults.bool(forKey: sessionActiveKey) else {
            return false
        }

        let endsAt = defaults.double(forKey: sessionEndsAtKey)
        if endsAt > 0 && endsAt < Date().timeIntervalSince1970 {
            defaults.set(false, forKey: sessionActiveKey)
            defaults.removeObject(forKey: sessionEndsAtKey)
            defaults.set(true, forKey: pendingInterventionSetupKey)
            defaults.set(Date().timeIntervalSince1970, forKey: pendingInterventionSetupAtKey)
            defaults.removeObject(forKey: countdownUntilKey)
            defaults.removeObject(forKey: countdownRemainingKey)
            defaults.synchronize()
            return false
        }

        return true
    }
}
