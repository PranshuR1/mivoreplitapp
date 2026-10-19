import Foundation
import SwiftUI
import BackgroundTasks
import UserNotifications
import os
#if canImport(UIKit)
import UIKit
#endif

#if canImport(FamilyControls)
import FamilyControls
#endif

#if canImport(DeviceActivity)
import DeviceActivity
#endif

#if canImport(ManagedSettings)
import ManagedSettings
#endif

import ActivityKit

enum InterventionFrictionTracker {
    private static let lastAttemptKey = "mivo.friction.lastAttempt"
    private static let attemptCountKey = "mivo.friction.attemptCount"
    private static let resetInterval: TimeInterval = 30 * 60

    static func registerAttempt(now: Date = Date()) -> InterventionFrictionState {
        let defaults = UserDefaults(suiteName: MivoScreenTimeKeys.appGroup) ?? .standard
        let previous = defaults.double(forKey: lastAttemptKey)
        let continuesSequence = previous > 0 && now.timeIntervalSince1970 - previous <= resetInterval
        let count = continuesSequence ? defaults.integer(forKey: attemptCountKey) + 1 : 1
        defaults.set(now.timeIntervalSince1970, forKey: lastAttemptKey)
        defaults.set(count, forKey: attemptCountKey)
        defaults.synchronize()
        let level = count >= 2 ? 2 : 1
        return InterventionFrictionState(level: level, attemptCount: count, waitSeconds: count >= 2 ? 10 : 5)
    }

    static func currentState(now: Date = Date()) -> InterventionFrictionState {
        let defaults = UserDefaults(suiteName: MivoScreenTimeKeys.appGroup) ?? .standard
        let previous = defaults.double(forKey: lastAttemptKey)
        guard previous > 0, now.timeIntervalSince1970 - previous <= resetInterval else {
            return InterventionFrictionState(level: 1, attemptCount: 0, waitSeconds: 5)
        }
        let count = max(1, defaults.integer(forKey: attemptCountKey))
        let level = count >= 2 ? 2 : 1
        return InterventionFrictionState(level: level, attemptCount: count, waitSeconds: count >= 2 ? 10 : 5)
    }
}

@available(iOS 15.0, *)
@MainActor
final class FamilyControlsManager: ObservableObject {
    static let shared = FamilyControlsManager()
    private let logger = Logger(subsystem: "com.mivo.mivoapp", category: "FamilyControls")

    // App group used to share data with the Device Activity extension — keep in sync with extension
    // Updated app group identifier (ensure this group is registered in Apple Developer portal)
    let appGroup = MivoScreenTimeKeys.appGroup
    private let selectedAppsKey = "mivo.selectedApps"
    private let familyActivitySelectionKey = MivoScreenTimeKeys.familyActivitySelection
    private let impulseProtectionEnabledKey = MivoScreenTimeKeys.impulseProtectionEnabled
    private let impulseProtectionSignedInKey = MivoScreenTimeKeys.impulseProtectionSignedIn
    private let learningModeUnlockedKey = MivoScreenTimeKeys.learningModeUnlocked
    private let mivoSessionActiveKey = MivoScreenTimeKeys.sessionActive
    private let mivoSessionEndsAtKey = MivoScreenTimeKeys.sessionEndsAt
    private let pendingInterventionSetupKey = MivoScreenTimeKeys.pendingInterventionSetup
    private let pendingInterventionSetupAtKey = MivoScreenTimeKeys.pendingInterventionSetupAt
    private let sessionRelockActivityName = MivoScreenTimeKeys.sessionRelockActivityName
    private let sessionEndWatcherActivityName = MivoScreenTimeKeys.sessionEndWatcherActivityName
    private let leaseEnforcementActivityName = MivoScreenTimeKeys.leaseEnforcementActivityName
    private let blockerSelfTestActivityName = MivoScreenTimeKeys.blockerSelfTestActivityName
    private let checkInIntervalMinutesKey = MivoScreenTimeKeys.checkInIntervalMinutes
    private let lastReportKey = "mivo.lastDeviceActivityReport"
    private let authFlagKey = "mivo.familyControlsAuthorized"
    private let blockerSelfTestStartKey = "mivo.blockerSelfTestStart"
    private let blockerSelfTestEndKey = "mivo.blockerSelfTestEnd"
    private let blockerSelfTestPassedKey = "mivo.blockerSelfTestPassed"
    private var sessionRelockWorkItem: DispatchWorkItem?

    private init() {}

    var userDefaults: UserDefaults? {
        // Try the app group first; if it's not available (provisioning not configured), fall back to standard defaults.
        if let ud = UserDefaults(suiteName: appGroup) {
            return ud
        } else {
            // Log to console to help debugging provisioning issues
            print("[FamilyControlsManager] App Group \(appGroup) not available; falling back to UserDefaults.standard")
            return UserDefaults.standard
        }
    }

    // Persist selected bundle identifiers
    func saveSelectedBundleIdentifiers(_ bundles: [String]) {
        userDefaults?.set(bundles, forKey: selectedAppsKey)
        userDefaults?.synchronize()
    }

    func loadSelectedBundleIdentifiers() -> [String] {
        return userDefaults?.stringArray(forKey: selectedAppsKey) ?? []
    }

    #if canImport(FamilyControls) && canImport(ManagedSettings)
    @available(iOS 16.0, *)
    func saveFamilyActivitySelection(_ selection: FamilyActivitySelection) {
        guard let data = try? JSONEncoder().encode(selection) else { return }
        userDefaults?.set(data, forKey: familyActivitySelectionKey)
        userDefaults?.synchronize()
        applyImpulseProtectionIfNeeded()
    }

    @available(iOS 16.0, *)
    func loadFamilyActivitySelection() -> FamilyActivitySelection {
        guard let data = userDefaults?.data(forKey: familyActivitySelectionKey),
              let selection = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data) else {
            return FamilyActivitySelection()
        }
        return selection
    }

    @available(iOS 16.0, *)
    func saveMivoClearMapping(_ selection: FamilyActivitySelection, for platform: MivoClearPlatform) throws {
        guard selection.applicationTokens.count == 1,
              selection.categoryTokens.isEmpty,
              selection.webDomainTokens.isEmpty,
              let token = selection.applicationTokens.first else {
            throw MivoClearMappingError.selectOneApp
        }

        for otherPlatform in MivoClearPlatform.supportedCases where otherPlatform != platform {
            if loadMivoClearToken(for: otherPlatform) == token {
                throw MivoClearMappingError.alreadyMapped(otherPlatform)
            }
        }

        guard let tokenData = try? JSONEncoder().encode(token) else {
            throw MivoClearMappingError.selectOneApp
        }
        userDefaults?.set(tokenData, forKey: mivoClearMappingKey(for: platform))

        var protectedSelection = loadFamilyActivitySelection()
        protectedSelection.applicationTokens.insert(token)
        saveFamilyActivitySelection(protectedSelection)
        userDefaults?.synchronize()
    }

    @available(iOS 16.0, *)
    func loadMivoClearToken(for platform: MivoClearPlatform) -> ApplicationToken? {
        guard let data = userDefaults?.data(forKey: mivoClearMappingKey(for: platform)) else { return nil }
        return try? JSONDecoder().decode(ApplicationToken.self, from: data)
    }

    @available(iOS 16.0, *)
    func hasMivoClearMapping(for platform: MivoClearPlatform) -> Bool {
        loadMivoClearToken(for: platform) != nil
    }

    @available(iOS 16.0, *)
    func clearMivoClearMapping(for platform: MivoClearPlatform) {
        userDefaults?.removeObject(forKey: mivoClearMappingKey(for: platform))
        userDefaults?.synchronize()
    }

    private func mivoClearMappingKey(for platform: MivoClearPlatform) -> String {
        MivoScreenTimeKeys.mivoClearMappingPrefix + platform.rawValue
    }

    @available(iOS 16.0, *)
    func hasImpulseSelection() -> Bool {
        let selection = loadFamilyActivitySelection()
        return !selection.applicationTokens.isEmpty
            || !selection.categoryTokens.isEmpty
            || !selection.webDomainTokens.isEmpty
    }

    func isImpulseProtectionEnabled() -> Bool {
        userDefaults?.bool(forKey: impulseProtectionEnabledKey) ?? false
    }

    func setSignedInForImpulseProtection(_ signedIn: Bool) {
        userDefaults?.set(signedIn, forKey: impulseProtectionSignedInKey)
        userDefaults?.synchronize()

        if !signedIn {
            _ = setMivoSessionActive(false)
            if #available(iOS 16.0, *) {
                clearImpulseProtection()
            }
        } else if #available(iOS 16.0, *) {
            applyImpulseProtectionIfNeeded()
        }
    }

    func isSignedInForImpulseProtection() -> Bool {
        userDefaults?.bool(forKey: impulseProtectionSignedInKey) ?? false
    }

    func isLearningModeUnlocked() -> Bool {
        userDefaults?.bool(forKey: learningModeUnlockedKey) ?? false
    }

    func setLearningModeUnlocked(_ enabled: Bool) {
        // This flag is for adaptive limits only. Screen Time permission or learning mode must never
        // clear/apply app shields by itself; blocking is controlled by the intervention toggle.
        userDefaults?.set(enabled, forKey: learningModeUnlockedKey)
        userDefaults?.synchronize()
    }

    func checkInIntervalMinutes() -> Int {
        let stored = userDefaults?.integer(forKey: checkInIntervalMinutesKey) ?? 0
        guard stored > 0 else { return MivoScreenTimeKeys.defaultCheckInIntervalMinutes }
        return min(max(stored, 1), 10)
    }

    func setCheckInIntervalMinutes(_ minutes: Int) {
        let clamped = min(max(minutes, 1), 10)
        userDefaults?.set(clamped, forKey: checkInIntervalMinutesKey)
        userDefaults?.synchronize()
    }

    func shieldPauseDuration() -> Int {
        let stored = userDefaults?.integer(forKey: MivoScreenTimeKeys.shieldPauseDuration) ?? 0
        guard stored > 0 else { return 5 }
        return min(max(stored, 3), 30)
    }

    func setShieldPauseDuration(_ seconds: Int) {
        userDefaults?.set(min(max(seconds, 3), 30), forKey: MivoScreenTimeKeys.shieldPauseDuration)
        userDefaults?.synchronize()
    }

    func activateMivoSession(durationSeconds: Int) -> Result<Void, SessionStartError> {
        guard durationSeconds > 0 else {
            sessionRelockWorkItem?.cancel()
            sessionRelockWorkItem = nil
            if #available(iOS 16.0, *) {
                applyImpulseProtectionIfNeeded()
            }
            return .failure(.noTimeRemaining)
        }

        // Re-affirming an already-active session — as opposed to genuinely
        // starting or extending one — must be a no-op. Every app foreground
        // calls this indirectly via `recoverExpiredRunningSessionIfNeeded()`
        // (passing back whatever `mivoSessionRemainingSeconds()` currently
        // reads), and a successful mid-scroll check-in does the same thing
        // from `MidScrollCheckInView.resume()`. Both are asking to "keep this
        // session going," not "start a new one" — but everything below this
        // point tears down and reschedules every DeviceActivity monitor,
        // notification, BG task, and Live Activity from scratch, which
        // otherwise fought the very belt-and-suspenders reliability those
        // exist for (rapid stop/restart cycles, flickering Live Activity) and
        // silently reset the mid-scroll check-in cadence's schedule anchor —
        // read as the *session itself* getting cancelled/restarted. A caller
        // asking to keep going computes an end time within a second or two of
        // the one already stored; a real extension (e.g. "add 10 minutes"
        // from the session-end screen) lands well outside that tolerance and
        // still goes through the full path below.
        let requestedEndsAt = Date().addingTimeInterval(TimeInterval(durationSeconds))
        if isMivoSessionActive() {
            let existingEndsAt = userDefaults?.double(forKey: mivoSessionEndsAtKey) ?? 0
            // Also require the actual DeviceActivity relock monitor to
            // still be registered, not just the stored timestamp to match —
            // otherwise a session whose *original* scheduling silently
            // failed (network hiccup, DeviceActivity quota, etc.) would
            // never get a second chance: every later re-affirming call
            // would keep taking this early-return and the session would
            // simply never re-lock at the end. Checking reality here, not
            // just the stored end time, means a genuinely broken schedule
            // self-heals on the next foreground instead of silently
            // skipping forever.
            if existingEndsAt > 0,
               abs(existingEndsAt - requestedEndsAt.timeIntervalSince1970) < 5,
               isMonitoring(activityName: sessionRelockActivityName) {
                logger.info("Intervention start: skipping re-activation, session already running with the same end time")
                return .success(())
            }
        }

        sessionRelockWorkItem?.cancel()
        sessionRelockWorkItem = nil

        logger.info("Intervention start: durationSeconds=\(durationSeconds)")
        clearPendingInterventionSetup()
        userDefaults?.set(true, forKey: mivoSessionActiveKey)
        userDefaults?.set(Date().addingTimeInterval(TimeInterval(durationSeconds)).timeIntervalSince1970, forKey: mivoSessionEndsAtKey)
        userDefaults?.removeObject(forKey: MivoScreenTimeKeys.sessionExpiredAt)
        userDefaults?.removeObject(forKey: MivoScreenTimeKeys.sessionExpiredSource)
        userDefaults?.removeObject(forKey: MivoScreenTimeKeys.sessionLeaseStartedAt)
        userDefaults?.removeObject(forKey: MivoScreenTimeKeys.sessionLeaseEndsAt)
        userDefaults?.removeObject(forKey: MivoScreenTimeKeys.sessionLeaseDurationSeconds)
        userDefaults?.removeObject(forKey: MivoScreenTimeKeys.shieldCountdownUntil)
        userDefaults?.removeObject(forKey: MivoScreenTimeKeys.shieldCountdownRemaining)
        userDefaults?.synchronize()

        if #available(iOS 16.0, *) {
            logger.info("Shield removal: clearing impulse protection for \(durationSeconds)s session")
            clearImpulseProtection()
            let leaseDuration = nextActiveSessionLeaseDuration(for: durationSeconds)
            scheduleActiveSessionLeaseRelock(after: leaseDuration)
            scheduleSystemLeaseRelock(after: leaseDuration)
            // Belt-and-suspenders: schedule a local notification for each check-in interval.
            // This fires even when the DispatchWorkItem and DeviceActivity can't run, so the
            // user is always alerted and the shield is visible when they open the blocked app.
            scheduleCheckInNotification(after: leaseDuration, sessionDurationSeconds: durationSeconds)
        }

        let monitorScheduled = scheduleSystemSessionRelock(after: TimeInterval(durationSeconds))
        if monitorScheduled {
            logger.info("DeviceActivity schedule start: session relock monitor scheduled for \(durationSeconds)s")
        } else {
            let detail = userDefaults?.string(forKey: MivoScreenTimeKeys.lastScheduleError) ?? "Device Activity relock was not scheduled."
            logger.warning("DeviceActivity schedule start: relock monitor NOT scheduled — \(detail)")
        }
        // Second trigger: intervalEnd-based watcher (starts now, ends at session end).
        // Complements the intervalDidStart approach — gives iOS two independent reasons to wake the extension.
        let watcherScheduled = scheduleSessionEndWatcher(after: TimeInterval(durationSeconds))
        logger.info("DeviceActivity schedule start: session end watcher \(watcherScheduled ? "scheduled" : "NOT scheduled") for \(durationSeconds)s")

        // Belt-and-suspenders: schedule a BGAppRefreshTask and a local notification at session end.
        // These fire even when DeviceActivityMonitor and the in-process DispatchWorkItem can't run.
        scheduleBGSessionRelock(after: TimeInterval(durationSeconds))
        scheduleSessionEndNotification(after: TimeInterval(durationSeconds))

        // Live Activity: shows a live countdown on the lock screen and Dynamic Island.
        if ProductExpansionStore.shared.isEnabled(.liveActivities) {
            let sessionEnd = Date().addingTimeInterval(TimeInterval(durationSeconds))
            startSessionLiveActivity(sessionEndsAt: sessionEnd, planMinutes: durationSeconds / 60, intentionLabel: "Session active")
        } else {
            endSessionLiveActivity()
        }

        return .success(())
    }

    // Compatibility wrapper for existing callers. Activation unlocks immediately and schedules relock best-effort.
    func setMivoSessionActive(_ active: Bool, plannedMinutes: Int = 0, exactDurationSeconds: Int? = nil) -> Bool {
        if active {
            let seconds = exactDurationSeconds ?? max(15 * 60, plannedMinutes * 60 + 10 * 60)
            return activateMivoSession(durationSeconds: seconds).isSuccess
        }

        finishMivoSessionState()
        return true
    }

    /// Re-locks the selected apps while Mivo runs the post-intention pause.
    /// A new active session is created only after that pause has completed.
    func prepareForSessionStartPause() {
        _ = setMivoSessionActive(false)

        if #available(iOS 16.0, *), hasImpulseSelection() {
            // Choosing to start a protected session should repair an accidentally
            // disabled protection toggle instead of leaving the apps exposed.
            userDefaults?.set(true, forKey: impulseProtectionSignedInKey)
            userDefaults?.set(true, forKey: impulseProtectionEnabledKey)
            userDefaults?.synchronize()
            applyImpulseProtectionIfNeeded()
        }
    }

    func cancelSessionStartPauseAndRelock() {
        _ = setMivoSessionActive(false)
        if #available(iOS 16.0, *) {
            applyImpulseProtectionIfNeeded()
        }
    }

    func endSessionAndRelockForIntervention() {
        expireMivoSession(source: MivoSessionExpirationSource.appRecovery.rawValue)
    }

    func expireMivoSession(source: String) {
        sessionRelockWorkItem?.cancel()
        sessionRelockWorkItem = nil
        stopSystemSessionRelock()
        stopSessionEndWatcher()
        stopLeaseRelock()
        cancelBGSessionRelock()
        cancelSessionEndNotification()
        cancelCheckInNotification()

        userDefaults?.set(false, forKey: mivoSessionActiveKey)
        userDefaults?.removeObject(forKey: mivoSessionEndsAtKey)
        userDefaults?.removeObject(forKey: MivoScreenTimeKeys.sessionLeaseStartedAt)
        userDefaults?.removeObject(forKey: MivoScreenTimeKeys.sessionLeaseEndsAt)
        userDefaults?.removeObject(forKey: MivoScreenTimeKeys.sessionLeaseDurationSeconds)
        userDefaults?.set(Date().timeIntervalSince1970, forKey: MivoScreenTimeKeys.sessionExpiredAt)
        userDefaults?.set(source, forKey: MivoScreenTimeKeys.sessionExpiredSource)
        userDefaults?.set(source, forKey: MivoScreenTimeKeys.lastShieldSource)
        userDefaults?.set(true, forKey: pendingInterventionSetupKey)
        userDefaults?.set(Date().timeIntervalSince1970, forKey: pendingInterventionSetupAtKey)
        userDefaults?.removeObject(forKey: MivoScreenTimeKeys.shieldCountdownUntil)
        userDefaults?.removeObject(forKey: MivoScreenTimeKeys.shieldCountdownRemaining)
        userDefaults?.synchronize()

        if #available(iOS 16.0, *) {
            applyImpulseProtectionIfNeeded()
        }
        endSessionLiveActivity()
    }

    func finishMivoSessionState() {
        sessionRelockWorkItem?.cancel()
        sessionRelockWorkItem = nil
        stopSystemSessionRelock()
        stopSessionEndWatcher()
        stopLeaseRelock()
        cancelBGSessionRelock()
        cancelSessionEndNotification()
        cancelCheckInNotification()

        userDefaults?.set(false, forKey: mivoSessionActiveKey)
        userDefaults?.removeObject(forKey: mivoSessionEndsAtKey)
        userDefaults?.removeObject(forKey: MivoScreenTimeKeys.sessionLeaseStartedAt)
        userDefaults?.removeObject(forKey: MivoScreenTimeKeys.sessionLeaseEndsAt)
        userDefaults?.removeObject(forKey: MivoScreenTimeKeys.sessionLeaseDurationSeconds)
        userDefaults?.removeObject(forKey: MivoScreenTimeKeys.sessionExpiredAt)
        userDefaults?.removeObject(forKey: MivoScreenTimeKeys.sessionExpiredSource)
        userDefaults?.removeObject(forKey: MivoScreenTimeKeys.shieldCountdownUntil)
        userDefaults?.removeObject(forKey: MivoScreenTimeKeys.shieldCountdownRemaining)
        userDefaults?.set(false, forKey: pendingInterventionSetupKey)
        userDefaults?.removeObject(forKey: pendingInterventionSetupAtKey)
        userDefaults?.set(MivoSessionExpirationSource.manualFinish.rawValue, forKey: MivoScreenTimeKeys.lastShieldSource)
        userDefaults?.synchronize()

        if #available(iOS 16.0, *) {
            applyImpulseProtectionIfNeeded()
        }
        endSessionLiveActivity()
    }

    // MARK: - Mivo Still Lock Mode

    /// Separate from the normal intervention shield store — Lock Mode blocks
    /// every app on the device via `.applicationCategories = .all()`,
    /// independent of whatever the user has (or hasn't) chosen as
    /// "protected." Kept as its own store so the two never interfere: normal
    /// relock/unlock logic elsewhere only ever touches `makeInterventionStore()`
    /// and the legacy default store.
    @available(iOS 16.0, *)
    private var stillLockStore: ManagedSettingsStore {
        ManagedSettingsStore(named: ManagedSettingsStore.Name("mivo.stillLock"))
    }
    private var stillLockUnlockWorkItem: DispatchWorkItem?

    @available(iOS 16.0, *)
    func activateStillLock(durationSeconds: Int = 15 * 60) {
        // Nothing should be sitting unlocked underneath the new block.
        _ = setMivoSessionActive(false)

        stillLockStore.shield.applicationCategories = .all()

        let endsAt = Date().addingTimeInterval(TimeInterval(durationSeconds))
        userDefaults?.set(true, forKey: MivoScreenTimeKeys.stillLockActive)
        userDefaults?.set(endsAt.timeIntervalSince1970, forKey: MivoScreenTimeKeys.stillLockEndsAt)
        userDefaults?.set(
            max(1, Int((Double(durationSeconds) / 60).rounded())),
            forKey: MivoScreenTimeKeys.stillLockPlannedMinutes
        )
        userDefaults?.synchronize()

        // Four independent triggers to reliably lift the block, mirroring the
        // same belt-and-suspenders relock pattern this class already uses in
        // reverse (apply now, clear later, instead of clear now, apply later).
        scheduleStillLockDeviceActivityUnlock(after: TimeInterval(durationSeconds))
        scheduleStillLockBGTask(after: TimeInterval(durationSeconds))
        scheduleStillLockNotification(after: TimeInterval(durationSeconds))
        scheduleStillLockForegroundUnlock(after: TimeInterval(durationSeconds))

        logger.info("Still Lock activated for \(durationSeconds)s")
    }

    /// Self-expiring, same shape as `isMivoSessionActive()` — past
    /// `stillLockEndsAt`, it clears the flag and returns false.
    @available(iOS 16.0, *)
    func isStillLockActive(now: Date = Date()) -> Bool {
        guard userDefaults?.bool(forKey: MivoScreenTimeKeys.stillLockActive) == true else { return false }
        let endsAt = userDefaults?.double(forKey: MivoScreenTimeKeys.stillLockEndsAt) ?? 0
        if endsAt > 0 && endsAt < now.timeIntervalSince1970 {
            endStillLock()
            return false
        }
        return true
    }

    @available(iOS 16.0, *)
    func stillLockRemainingMinutes(now: Date = Date()) -> Int {
        guard isStillLockActive(now: now) else { return 0 }
        let endsAt = userDefaults?.double(forKey: MivoScreenTimeKeys.stillLockEndsAt) ?? 0
        return max(0, Int(ceil((endsAt - now.timeIntervalSince1970) / 60)))
    }

    /// Seconds-precision remaining, so a Lock Mode countdown that is restored
    /// after the app was closed picks up where the clock actually is instead
    /// of rounding up to the next whole minute.
    @available(iOS 16.0, *)
    func stillLockRemainingSeconds(now: Date = Date()) -> Double {
        guard isStillLockActive(now: now) else { return 0 }
        let endsAt = userDefaults?.double(forKey: MivoScreenTimeKeys.stillLockEndsAt) ?? 0
        return max(0, endsAt - now.timeIntervalSince1970)
    }

    /// The full length the active Lock Mode run was started with, used to
    /// label a restored session correctly.
    @available(iOS 16.0, *)
    func stillLockPlannedMinutes() -> Int {
        max(1, userDefaults?.integer(forKey: MivoScreenTimeKeys.stillLockPlannedMinutes) ?? 0)
    }

    @available(iOS 16.0, *)
    func endStillLock() {
        stillLockUnlockWorkItem?.cancel()
        stillLockUnlockWorkItem = nil
        stillLockStore.shield.applicationCategories = nil

        userDefaults?.set(false, forKey: MivoScreenTimeKeys.stillLockActive)
        userDefaults?.removeObject(forKey: MivoScreenTimeKeys.stillLockEndsAt)
        userDefaults?.removeObject(forKey: MivoScreenTimeKeys.stillLockPlannedMinutes)
        userDefaults?.synchronize()

        stopStillLockDeviceActivity()
        cancelStillLockBGTask()
        cancelStillLockNotification()
        logger.info("Still Lock ended")
    }

    /// Safe to call unconditionally — a no-op unless a lock is active and its
    /// end time has already passed. Used by the BGAppRefreshTask fallback.
    func endStillLockIfExpired() {
        if #available(iOS 16.0, *) {
            _ = isStillLockActive()
        }
    }

    /// Re-arms the in-process unlock timer for a lock that outlived the
    /// process that started it.
    ///
    /// `scheduleStillLockForegroundUnlock` is a `DispatchWorkItem`, so it dies
    /// with the app. After a relaunch mid-lock, the only remaining triggers
    /// were the DeviceActivity extension and a BGTask — precisely the two the
    /// system is free to delay, which is how a lock ends up outstaying its
    /// timer. Call this on launch and on foreground so the reliable trigger
    /// exists again.
    @available(iOS 16.0, *)
    func rearmStillLockUnlockIfNeeded(now: Date = Date()) {
        guard isStillLockActive(now: now) else { return }
        let remaining = stillLockRemainingSeconds(now: now)
        guard remaining > 0 else {
            endStillLock()
            return
        }
        scheduleStillLockForegroundUnlock(after: remaining)
    }

    @available(iOS 16.0, *)
    private func scheduleStillLockDeviceActivityUnlock(after delay: TimeInterval) {
        #if canImport(DeviceActivity)
        let center = DeviceActivityCenter()
        let activity = DeviceActivityName(MivoScreenTimeKeys.stillLockActivityName)
        center.stopMonitoring([activity])

        let calendar = Calendar.current
        let now = Date()
        // intervalStart = the exact unlock time — iOS reliably fires
        // intervalDidStart, waking the extension even if Mivo isn't running.
        let start = now.addingTimeInterval(max(30, delay))
        let end = start.addingTimeInterval(7200)

        let schedule = DeviceActivitySchedule(
            intervalStart: calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: start),
            intervalEnd: calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: end),
            repeats: false
        )

        do {
            try center.startMonitoring(activity, during: schedule)
            logger.info("Still Lock unlock scheduled via DeviceActivity for \(start)")
        } catch {
            logger.warning("Still Lock DeviceActivity scheduling failed: \(error.localizedDescription)")
        }
        #endif
    }

    private func stopStillLockDeviceActivity() {
        #if canImport(DeviceActivity)
        guard #available(iOS 16.0, *) else { return }
        DeviceActivityCenter().stopMonitoring([DeviceActivityName(MivoScreenTimeKeys.stillLockActivityName)])
        #endif
    }

    private func scheduleStillLockBGTask(after delay: TimeInterval) {
        let request = BGAppRefreshTaskRequest(identifier: MivoScreenTimeKeys.stillLockBGTaskIdentifier)
        request.earliestBeginDate = Date().addingTimeInterval(max(delay, 30))
        try? BGTaskScheduler.shared.submit(request)
    }

    private func cancelStillLockBGTask() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: MivoScreenTimeKeys.stillLockBGTaskIdentifier)
    }

    private func scheduleStillLockNotification(after delay: TimeInterval) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["mivo.still.lock.ended"])

        let content = UNMutableNotificationContent()
        content.title = "Mivo Still lock ended"
        content.body = "Your apps are unlocked again."
        content.sound = .default
        if #available(iOS 15.0, *) {
            content.interruptionLevel = .timeSensitive
        }
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(delay, 1), repeats: false)
        let request = UNNotificationRequest(identifier: "mivo.still.lock.ended", content: content, trigger: trigger)
        center.add(request, withCompletionHandler: nil)
    }

    private func cancelStillLockNotification() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["mivo.still.lock.ended"])
    }

    @available(iOS 16.0, *)
    private func scheduleStillLockForegroundUnlock(after delay: TimeInterval) {
        stillLockUnlockWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.endStillLock()
        }
        stillLockUnlockWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    // MARK: - Always block drifting apps (Home screen commitment toggle)

    /// Shields the user's own protected-apps selection — not every category
    /// like Still Lock — because this is framed as "stop the apps that
    /// pull me off track," not a full lockdown. Kept in its own store so
    /// arming/clearing it can never step on Still Lock, cross-device focus,
    /// or normal intervention shielding.
    @available(iOS 16.0, *)
    private var alwaysBlockDriftStore: ManagedSettingsStore {
        ManagedSettingsStore(named: ManagedSettingsStore.Name("mivo.alwaysBlockDrift"))
    }

    private static func todayDateString(_ date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .current
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: date)
    }

    /// Self-expiring by calendar date, not a timer — arming it at 11:58pm
    /// should still clear at midnight, not run for a nearly-full 24 hours.
    /// Checking "is the armed date still today?" on every call (rather than
    /// scheduling a duration from the moment it was armed) is what makes
    /// that true regardless of when in the day the user turned it on.
    @available(iOS 16.0, *)
    func isAlwaysBlockDriftActive(now: Date = Date()) -> Bool {
        guard userDefaults?.bool(forKey: MivoScreenTimeKeys.alwaysBlockDriftActive) == true else { return false }
        guard userDefaults?.string(forKey: MivoScreenTimeKeys.alwaysBlockDriftArmedDate) == Self.todayDateString(now) else {
            endAlwaysBlockDrift()
            return false
        }
        return true
    }

    /// No corresponding "disable" entry point is exposed to the UI on
    /// purpose — the only way this clears before the day rolls over is
    /// `isAlwaysBlockDriftActive` noticing the date changed, or the
    /// midnight DeviceActivity alarm below.
    @available(iOS 16.0, *)
    func enableAlwaysBlockDriftForRestOfToday() {
        apply(selection: loadFamilyActivitySelection(), to: alwaysBlockDriftStore)
        userDefaults?.set(true, forKey: MivoScreenTimeKeys.alwaysBlockDriftActive)
        userDefaults?.set(Self.todayDateString(), forKey: MivoScreenTimeKeys.alwaysBlockDriftArmedDate)
        userDefaults?.synchronize()
        scheduleAlwaysBlockDriftMidnightClear()
        logger.info("Always-block-drift armed for the rest of today")
    }

    @available(iOS 16.0, *)
    private func endAlwaysBlockDrift() {
        clearShieldStore(alwaysBlockDriftStore)
        userDefaults?.set(false, forKey: MivoScreenTimeKeys.alwaysBlockDriftActive)
        userDefaults?.removeObject(forKey: MivoScreenTimeKeys.alwaysBlockDriftArmedDate)
        userDefaults?.synchronize()
        stopAlwaysBlockDriftDeviceActivity()
        logger.info("Always-block-drift ended (day rolled over)")
    }

    /// Same trick as `scheduleStillLockDeviceActivityUnlock`: intervalStart
    /// = the clear moment, so iOS reliably wakes the monitor extension even
    /// with Mivo fully killed overnight.
    @available(iOS 16.0, *)
    private func scheduleAlwaysBlockDriftMidnightClear() {
        #if canImport(DeviceActivity)
        let center = DeviceActivityCenter()
        let activity = DeviceActivityName(MivoScreenTimeKeys.alwaysBlockDriftActivityName)
        center.stopMonitoring([activity])

        let calendar = Calendar.current
        guard let midnight = calendar.nextDate(
            after: Date(),
            matching: DateComponents(hour: 0, minute: 0, second: 0),
            matchingPolicy: .nextTime
        ) else { return }
        let end = midnight.addingTimeInterval(7200)

        let schedule = DeviceActivitySchedule(
            intervalStart: calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: midnight),
            intervalEnd: calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: end),
            repeats: false
        )
        do {
            try center.startMonitoring(activity, during: schedule)
            logger.info("Always-block-drift midnight clear scheduled for \(midnight)")
        } catch {
            logger.warning("Always-block-drift DeviceActivity scheduling failed: \(error.localizedDescription)")
        }
        #endif
    }

    private func stopAlwaysBlockDriftDeviceActivity() {
        #if canImport(DeviceActivity)
        guard #available(iOS 16.0, *) else { return }
        DeviceActivityCenter().stopMonitoring([DeviceActivityName(MivoScreenTimeKeys.alwaysBlockDriftActivityName)])
        #endif
    }

    // MARK: - Live Activity management

    /// Starts a Live Activity showing a countdown timer on the lock screen / Dynamic Island.
    /// Requires NSSupportsLiveActivities = YES and the MivoWidgets extension target to be
    /// wired up in Xcode (see Mivo/Constants/MivoLiveActivityAttributes.swift).
    func startSessionLiveActivity(sessionEndsAt: Date, planMinutes: Int, intentionLabel: String) {
        // End any stale activity from a previous session first.
        endSessionLiveActivity()
        let attrs = MivoSessionLiveAttributes(
            sessionStartedAt: Date(),
            intentionLabel: intentionLabel
        )
        let state = MivoSessionLiveAttributes.ContentState(
            sessionEndsAt: sessionEndsAt,
            planMinutes: planMinutes
        )
        do {
            let content = ActivityContent(state: state, staleDate: sessionEndsAt.addingTimeInterval(60))
            _ = try Activity.request(attributes: attrs, content: content)
            logger.info("LiveActivity: started — ends at \(sessionEndsAt)")
        } catch {
            logger.warning("LiveActivity: failed to start — \(error.localizedDescription)")
        }
    }

    /// Ends all running Mivo session Live Activities.
    func endSessionLiveActivity() {
        Task {
            for activity in Activity<MivoSessionLiveAttributes>.activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
    }

    private func nextActiveSessionLeaseDuration(for durationSeconds: Int) -> TimeInterval {
        let configuredSeconds = TimeInterval(checkInIntervalMinutes() * 60)
        return max(1, min(TimeInterval(durationSeconds), configuredSeconds))
    }

@available(iOS 16.0, *)
private func scheduleActiveSessionLeaseRelock(after delay: TimeInterval) {
    sessionRelockWorkItem?.cancel()

    let leaseDuration = max(1, delay)
    let now = Date()
    userDefaults?.set(now.timeIntervalSince1970, forKey: MivoScreenTimeKeys.sessionLeaseStartedAt)
    userDefaults?.set(now.addingTimeInterval(leaseDuration).timeIntervalSince1970, forKey: MivoScreenTimeKeys.sessionLeaseEndsAt)
    userDefaults?.set(Int(leaseDuration), forKey: MivoScreenTimeKeys.sessionLeaseDurationSeconds)
    userDefaults?.set(now.timeIntervalSince1970, forKey: MivoScreenTimeKeys.leaseMonitorScheduledAt)
    userDefaults?.synchronize()

    #if canImport(UIKit)
    var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Mivo active lease relock") {
        if backgroundTask != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTask)
            backgroundTask = .invalid
        }
    }
    #endif

    let workItem = DispatchWorkItem { [weak self] in
        Task { @MainActor in
            guard let self else { return }
            self.reapplyShieldForActiveSessionLeaseEnd(source: MivoSessionExpirationSource.leaseEnd.rawValue)
            #if canImport(UIKit)
            if backgroundTask != .invalid {
                UIApplication.shared.endBackgroundTask(backgroundTask)
                backgroundTask = .invalid
            }
            #endif
        }
    }
    sessionRelockWorkItem = workItem
    DispatchQueue.main.asyncAfter(deadline: .now() + leaseDuration, execute: workItem)
}

/// Called from AppDelegate when the user taps the check-in notification.
/// Re-applies shields immediately so the blocked app shows the "Active session
/// check-in" shield as soon as the user navigates to it.
func applyCheckInShieldIfSessionActive() {
    guard #available(iOS 16.0, *) else { return }
    reapplyShieldForActiveSessionLeaseEnd(source: "check-in-notification-tap")
}

@available(iOS 16.0, *)
private func reapplyShieldForActiveSessionLeaseEnd(source: String) {
    guard isImpulseProtectionEnabled(), isSignedInForImpulseProtection() else {
        clearImpulseProtection()
        return
    }

    guard isMivoSessionActive() else {
        expireMivoSession(source: MivoSessionExpirationSource.sessionEnd.rawValue)
        return
    }

    let selection = loadFamilyActivitySelection()
    apply(selection: selection, to: makeInterventionStore())
    apply(selection: selection, to: ManagedSettingsStore())
    userDefaults?.set(Date().timeIntervalSince1970, forKey: MivoScreenTimeKeys.leaseMonitorDidEndAt)
    userDefaults?.set(source, forKey: MivoScreenTimeKeys.lastShieldSource)
    userDefaults?.synchronize()
}

    private func scheduleSystemSessionRelock(after delay: TimeInterval) -> Bool {
        #if canImport(DeviceActivity)
        guard #available(iOS 16.0, *) else { return false }

        let center = DeviceActivityCenter()
        let activity = DeviceActivityName(sessionRelockActivityName)
        center.stopMonitoring([activity])

        let calendar = Calendar.current
        let now = Date()

        // intervalStart = exact session-end time (second precision, no minute-rounding).
        // Previously we rounded UP to the next minute which caused up to 60 s of delay.
        // iOS calls intervalDidStart reliably — it must launch the extension to begin usage counting.
        let start = now.addingTimeInterval(max(30, delay))
        // Keep the window open for 2 hours so intervalDidEnd fires as a final fallback.
        let end = start.addingTimeInterval(7200)

        // Include year/month/day so the schedule is unambiguous and fires today only.
        // Include second so the match is precise to the second, not the minute.
        let startComponents = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: start)
        let endComponents   = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: end)
        let schedule = DeviceActivitySchedule(
            intervalStart: startComponents,
            intervalEnd: endComponents,
            repeats: false
        )
        // 1-second threshold: fires the moment user opens a blocked app after session ends.
        // This is a second line of defence behind intervalDidStart.
        let events = makeSessionUsageLimitEvents(seconds: 1)

        do {
            try center.startMonitoring(activity, during: schedule, events: events)
            userDefaults?.set(Date().timeIntervalSince1970, forKey: MivoScreenTimeKeys.sessionMonitorScheduledAt)
            userDefaults?.removeObject(forKey: MivoScreenTimeKeys.lastScheduleError)
            userDefaults?.synchronize()
            print("[FamilyControlsManager] ✅ Session relock scheduled: intervalDidStart fires at \(start)")
            return true
        } catch {
            print("[FamilyControlsManager] ❌ Failed to schedule session relock: \(error.localizedDescription)")
            userDefaults?.set(error.localizedDescription, forKey: MivoScreenTimeKeys.lastScheduleError)
            userDefaults?.synchronize()
            return false
        }
        #else
        return false
        #endif
    }

    @available(iOS 16.0, *)
    private func makeSessionUsageLimitEvents(seconds: Int) -> [DeviceActivityEvent.Name: DeviceActivityEvent] {
        let selection = loadFamilyActivitySelection()
        guard !selection.applicationTokens.isEmpty || !selection.categoryTokens.isEmpty || !selection.webDomainTokens.isEmpty else {
            return [:]
        }

        let event = DeviceActivityEvent(
            applications: selection.applicationTokens,
            categories: selection.categoryTokens,
            webDomains: selection.webDomainTokens,
            threshold: DateComponents(second: max(1, seconds))
        )
        return [DeviceActivityEvent.Name(MivoScreenTimeKeys.sessionUsageLimitEventName): event]
    }

    // MARK: - BGAppRefreshTask fallback relock

    private func scheduleBGSessionRelock(after delay: TimeInterval) {
        let request = BGAppRefreshTaskRequest(identifier: "com.mivo.mivoapp.sessionrelock")
        // Earliest possible start = session end. iOS may fire a few minutes later — still acceptable.
        request.earliestBeginDate = Date().addingTimeInterval(max(delay, 30))
        try? BGTaskScheduler.shared.submit(request)
        logger.info("BGAppRefreshTask scheduled for session relock in \(Int(delay))s")
    }

    private func cancelBGSessionRelock() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: "com.mivo.mivoapp.sessionrelock")
    }

    // MARK: - Session-end notification fallback

    private func scheduleSessionEndNotification(after delay: TimeInterval) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [
            "mivo.session.ended",
            "mivo.session.ended.nudge1",
            "mivo.session.ended.nudge2"
        ])

        // Primary: time-sensitive notification at session-end. Tap → opens Mivo →
        // `recoverExpiredRunningSessionIfNeeded()` runs on .active → shields applied.
        // Time-sensitive interruption level pierces Focus modes and shows even while
        // the user is inside a blocked app.
        let content = UNMutableNotificationContent()
        content.title = "Session ended — re-lock your apps"
        content.body = "Tap Open Mivo to lock the apps and reset your intention."
        content.sound = .default
        content.categoryIdentifier = "MIVO_SESSION_ENDED"
        content.userInfo = ["openIntervention": true]
        if #available(iOS 15.0, *) {
            content.interruptionLevel = .timeSensitive
        }

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(delay, 1), repeats: false)
        let request = UNNotificationRequest(identifier: "mivo.session.ended", content: content, trigger: trigger)
        center.add(request) { [weak self] error in
            if let error { self?.logger.warning("Session-end notification scheduling failed: \(error.localizedDescription)") }
        }

        // Nudges are fallbacks only while the selected apps remain unlocked. The app
        // and Device Activity extension cancel them as soon as shields are re-applied.
        scheduleSessionEndNudge(identifier: "mivo.session.ended.nudge1", after: max(delay, 1) + 30)
        scheduleSessionEndNudge(identifier: "mivo.session.ended.nudge2", after: max(delay, 1) + 90)
    }

    private func scheduleSessionEndNudge(identifier: String, after delay: TimeInterval) {
        let content = UNMutableNotificationContent()
        content.title = "Open Mivo"
        content.body = "Finish the session and re-lock your apps."
        content.sound = .default
        content.categoryIdentifier = "MIVO_SESSION_ENDED"
        content.userInfo = ["openIntervention": true]
        if #available(iOS 15.0, *) {
            content.interruptionLevel = .timeSensitive
        }
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(delay, 1), repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }

    private func cancelSessionEndNotification() {
        SessionEndedNotificationCleaner.clearPendingAndDelivered()
    }

    // MARK: - Check-in interval notification

    /// Schedules a local notification at the next check-in interval.
    /// This is a reliable fallback for when the DispatchWorkItem and DeviceActivity
    /// extension can't fire (app backgrounded, system limits, etc.).
    /// The notification reminds the user that their check-in is due; the shield is
    /// (also) applied by the DeviceActivity extension to block the app.
    func scheduleCheckInNotification(after delay: TimeInterval, sessionDurationSeconds: Int) {
        cancelCheckInNotification()
        // Only schedule if the check-in fires before the session ends.
        let interval = min(delay, TimeInterval(sessionDurationSeconds))
        guard interval >= 30 && interval < TimeInterval(sessionDurationSeconds) else { return }

        let content = UNMutableNotificationContent()
        content.title = "Mivo check-in"
        content.body = "Your \(Int(interval / 60))-minute check-in is here. Open the blocked app to continue with a short pause."
        content.sound = .default
        content.categoryIdentifier = "MIVO_SESSION_ENDED"
        content.userInfo = ["mivoRoute": "checkIn"]
        if #available(iOS 15.0, *) {
            content.interruptionLevel = .timeSensitive
        }

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(interval, 1), repeats: false)
        let request = UNNotificationRequest(identifier: "mivo.session.checkIn", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request) { [weak self] error in
            if let error {
                self?.logger.warning("Check-in notification scheduling failed: \(error.localizedDescription)")
            }
        }
        logger.info("Check-in notification scheduled in \(Int(interval))s")
    }

    func cancelCheckInNotification() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["mivo.session.checkIn"])
    }

    private func stopSystemSessionRelock() {
        #if canImport(DeviceActivity)
        guard #available(iOS 16.0, *) else { return }
        DeviceActivityCenter().stopMonitoring([DeviceActivityName(sessionRelockActivityName)])
        #endif
    }

    // MARK: - Session end watcher (backup relock trigger)

    /// Schedules a DeviceActivity whose interval ENDS at session-end time.
    /// iOS fires `intervalDidEnd` when the window closes — a second chance to wake the extension
    /// alongside the `intervalDidStart`-at-session-end approach used by `mivo.session.relock`.
    @discardableResult
    private func scheduleSessionEndWatcher(after delay: TimeInterval) -> Bool {
        #if canImport(DeviceActivity)
        guard #available(iOS 16.0, *) else { return false }

        let center = DeviceActivityCenter()
        let activity = DeviceActivityName(sessionEndWatcherActivityName)
        center.stopMonitoring([activity])

        let calendar = Calendar.current
        let now = Date()

        // Start: 2 seconds from now so the interval is always in the future when submitted.
        let startDate = now.addingTimeInterval(2)

        // End: exact session-end time (second precision, no minute-rounding).
        let endDate = now.addingTimeInterval(max(30, delay))

        guard endDate > startDate else {
            logger.warning("scheduleSessionEndWatcher: end <= start — skipping")
            return false
        }

        let startComponents = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: startDate)
        let endComponents   = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: endDate)
        let schedule = DeviceActivitySchedule(
            intervalStart: startComponents,
            intervalEnd: endComponents,
            repeats: false
        )

        // Usage threshold = full session duration. Fires the moment cumulative usage equals
        // the allowed session time (catches the case where the user is actively in the app when time runs out).
        let events = makeSessionEndWatcherEvents(seconds: Int(max(30, delay)))

        do {
            try center.startMonitoring(activity, during: schedule, events: events)
            print("[FamilyControlsManager] ✅ SessionEndWatcher scheduled: intervalDidEnd fires at \(endDate)")
            return true
        } catch {
            print("[FamilyControlsManager] ❌ Failed to schedule sessionEndWatcher: \(error.localizedDescription)")
            return false
        }
        #else
        return false
        #endif
    }

    private func stopSessionEndWatcher() {
        #if canImport(DeviceActivity)
        guard #available(iOS 16.0, *) else { return }
        DeviceActivityCenter().stopMonitoring([DeviceActivityName(sessionEndWatcherActivityName)])
        #endif
    }

    @available(iOS 16.0, *)
    private func makeSessionEndWatcherEvents(seconds: Int) -> [DeviceActivityEvent.Name: DeviceActivityEvent] {
        let selection = loadFamilyActivitySelection()
        guard !selection.applicationTokens.isEmpty || !selection.categoryTokens.isEmpty || !selection.webDomainTokens.isEmpty else {
            return [:]
        }
        let event = DeviceActivityEvent(
            applications: selection.applicationTokens,
            categories: selection.categoryTokens,
            webDomains: selection.webDomainTokens,
            threshold: DateComponents(second: max(1, seconds))
        )
        return [DeviceActivityEvent.Name(MivoScreenTimeKeys.sessionEndWatcherUsageLimitEventName): event]
    }

    private func stopLeaseRelock() {
        #if canImport(DeviceActivity)
        guard #available(iOS 16.0, *) else { return }
        DeviceActivityCenter().stopMonitoring([DeviceActivityName(leaseEnforcementActivityName)])
        #endif
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
        // Same strategy as session relock: schedule START = lease end time.
        // intervalDidStart fires reliably; extension calls relockForActiveSessionCheckIn there.
        // Use second precision — previously rounded up to minute causing up to 60 s of delay.
        let start = now.addingTimeInterval(max(30, delay))
        let end = start.addingTimeInterval(7200)

        let schedule = DeviceActivitySchedule(
            intervalStart: calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: start),
            intervalEnd: calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: end),
            repeats: false
        )

        do {
            try center.startMonitoring(activity, during: schedule)
            userDefaults?.set(now.timeIntervalSince1970, forKey: MivoScreenTimeKeys.leaseMonitorScheduledAt)
            userDefaults?.removeObject(forKey: MivoScreenTimeKeys.lastScheduleError)
            userDefaults?.synchronize()
            return true
        } catch {
            userDefaults?.set(error.localizedDescription, forKey: MivoScreenTimeKeys.lastScheduleError)
            userDefaults?.synchronize()
            return false
        }
        #else
        return false
        #endif
    }

    /// Seconds left in the current Mivo session, 0 if none is active. Used to
    /// resume the same session (not restart a fresh one) after a mid-scroll
    /// check-in confirms the user still wants to keep going.
    func mivoSessionRemainingSeconds(now: Date = Date()) -> Int {
        guard isMivoSessionActive() else { return 0 }
        let endsAt = userDefaults?.double(forKey: mivoSessionEndsAtKey) ?? 0
        return max(0, Int(endsAt - now.timeIntervalSince1970))
    }

    func isMivoSessionActive() -> Bool {
        guard userDefaults?.bool(forKey: mivoSessionActiveKey) == true else { return false }
        let endsAt = userDefaults?.double(forKey: mivoSessionEndsAtKey) ?? 0
        if endsAt > 0 && endsAt < Date().timeIntervalSince1970 {
            userDefaults?.set(false, forKey: mivoSessionActiveKey)
            userDefaults?.removeObject(forKey: mivoSessionEndsAtKey)
            userDefaults?.set(true, forKey: pendingInterventionSetupKey)
            userDefaults?.set(Date().timeIntervalSince1970, forKey: pendingInterventionSetupAtKey)
            userDefaults?.synchronize()
            return false
        }
        return true
    }

    func requestInterventionSetupFromShield() {
        userDefaults?.set(true, forKey: pendingInterventionSetupKey)
        userDefaults?.set(Date().timeIntervalSince1970, forKey: pendingInterventionSetupAtKey)
        userDefaults?.synchronize()
    }

    func consumePendingInterventionSetup() -> Bool {
        userDefaults?.bool(forKey: pendingInterventionSetupKey) == true
    }

    func clearPendingInterventionSetup() {
        userDefaults?.set(false, forKey: pendingInterventionSetupKey)
        userDefaults?.removeObject(forKey: pendingInterventionSetupAtKey)
        userDefaults?.synchronize()
    }

    /// Whether tapping the real Instagram app should redirect into Mivo's own
    /// wrapper instead of the normal intervention flow. Read by both the app
    /// (Settings toggle) and the ShieldAction extension (which can't import
    /// this class, so it reads the same app-group key directly).
    func isInstagramWrapperEnabled() -> Bool {
        userDefaults?.bool(forKey: MivoScreenTimeKeys.instagramWrapperEnabled) ?? false
    }

    func setInstagramWrapperEnabled(_ enabled: Bool) {
        userDefaults?.set(enabled, forKey: MivoScreenTimeKeys.instagramWrapperEnabled)
        userDefaults?.synchronize()
    }

    @available(iOS 16.0, *)
    func setImpulseProtectionEnabled(_ enabled: Bool) {
        userDefaults?.set(enabled, forKey: impulseProtectionEnabledKey)
        userDefaults?.synchronize()

        if enabled {
            applyImpulseProtectionIfNeeded()
        } else {
            clearImpulseProtection()
        }
    }

    @available(iOS 16.0, *)
    func applyImpulseProtectionIfNeeded() {
        guard isImpulseProtectionEnabled(), isSignedInForImpulseProtection() else {
            clearImpulseProtection()
            return
        }

        if isMivoSessionActive() {
            clearImpulseProtection()
            return
        }

        let selection = loadFamilyActivitySelection()
        apply(selection: selection, to: makeInterventionStore())
        apply(selection: selection, to: ManagedSettingsStore())
        cancelSessionEndNudgesAfterRelock()
        logger.info("Shield re-applied: apps=\(selection.applicationTokens.count) categories=\(selection.categoryTokens.count) domains=\(selection.webDomainTokens.count)")
    }

    private func cancelSessionEndNudgesAfterRelock() {
        let identifiers = [
            "mivo.session.ended.nudge1",
            "mivo.session.ended.nudge2"
        ]
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
    }

    @available(iOS 16.0, *)
    func clearImpulseProtection() {
        logger.info("Shield removal: clearing all managed-settings shields")
        clearShieldStore(makeInterventionStore())
        clearShieldStore(ManagedSettingsStore())
    }

    @available(iOS 16.0, *)
    private func clearLegacyImpulseProtection() {
        clearShieldStore(ManagedSettingsStore())
    }

    @available(iOS 16.0, *)
    private func clearShieldStore(_ store: ManagedSettingsStore) {
        store.shield.applications = nil
        store.shield.applicationCategories = nil
        store.shield.webDomains = nil
    }

    @available(iOS 16.0, *)
    private func apply(selection: FamilyActivitySelection, to store: ManagedSettingsStore) {
        store.shield.applications = selection.applicationTokens.isEmpty ? nil : selection.applicationTokens
        store.shield.applicationCategories = selection.categoryTokens.isEmpty ? nil : .specific(selection.categoryTokens)
        store.shield.webDomains = selection.webDomainTokens.isEmpty ? nil : selection.webDomainTokens
    }

    @available(iOS 16.0, *)
    private func makeInterventionStore() -> ManagedSettingsStore {
        ManagedSettingsStore(named: ManagedSettingsStore.Name(MivoScreenTimeKeys.shieldStoreName))
    }

    /// Dedicated store for shields applied by a "Block my iPhone too"
    /// command from the Mac companion app (see `CrossDeviceFocusService`).
    /// Kept separate from `makeInterventionStore()`/the legacy default
    /// store/Still Lock's store so ending a cross-device command can never
    /// clear an unrelated shield, and vice versa.
    @available(iOS 16.0, *)
    private func crossDeviceFocusStore() -> ManagedSettingsStore {
        ManagedSettingsStore(named: ManagedSettingsStore.Name("mivo.crossDeviceFocus"))
    }

    /// "Block my iPhone too" is a full lockdown, same as Mivo Still
    /// (`activateStillLock` — `.applicationCategories = .all()`), not a
    /// shield limited to the user's own tracked-apps selection. The Mac
    /// side already frames it as "lock down like Focus Lock does," so the
    /// iPhone side should match that expectation rather than silently
    /// shielding a narrower set.
    ///
    /// `endsAt` is recorded alongside the shield (same pattern as
    /// `activateStillLock`'s `stillLockEndsAtKey`) so
    /// `MivoShieldConfigurationExtension` can show "Focus mode on your Mac"
    /// with a real countdown instead of falling through to its generic
    /// default copy, which told the user to "Open Mivo" — misleading here,
    /// since only ending the session on Mac clears this shield.
    @available(iOS 16.0, *)
    func applyCrossDeviceFocusShield(endsAt: Date) {
        crossDeviceFocusStore().shield.applicationCategories = .all()
        userDefaults?.set(true, forKey: MivoScreenTimeKeys.crossDeviceFocusActive)
        userDefaults?.set(endsAt.timeIntervalSince1970, forKey: MivoScreenTimeKeys.crossDeviceFocusEndsAt)
        userDefaults?.synchronize()
        // Guarantees the clear even if Mivo never reopens again before the
        // Mac session ends — otherwise this shield could only ever be
        // lifted by a reconcile() call, and one relies entirely on the app
        // being foregrounded at some point after endsAt.
        scheduleCrossDeviceFocusDeviceActivityClear(endsAt: endsAt)
    }

    @available(iOS 16.0, *)
    func clearCrossDeviceFocusShield() {
        clearShieldStore(crossDeviceFocusStore())
        userDefaults?.set(false, forKey: MivoScreenTimeKeys.crossDeviceFocusActive)
        userDefaults?.removeObject(forKey: MivoScreenTimeKeys.crossDeviceFocusEndsAt)
        userDefaults?.synchronize()
        stopCrossDeviceFocusDeviceActivity()
    }

    /// Reliable clear trigger, same trick as `scheduleStillLockDeviceActivityUnlock`:
    /// intervalStart = the exact end time, so iOS fires `intervalDidStart` in
    /// `MivoDeviceActivityMonitorExtension` and clears the shield even with
    /// Mivo fully killed. intervalEnd is a 2-hour window purely because
    /// `DeviceActivitySchedule` requires one; `intervalDidEnd` is a backup
    /// trigger for the same clear.
    @available(iOS 16.0, *)
    private func scheduleCrossDeviceFocusDeviceActivityClear(endsAt: Date) {
        #if canImport(DeviceActivity)
        let center = DeviceActivityCenter()
        let activity = DeviceActivityName(MivoScreenTimeKeys.crossDeviceFocusActivityName)
        center.stopMonitoring([activity])

        let calendar = Calendar.current
        let start = max(endsAt, Date().addingTimeInterval(30))
        let end = start.addingTimeInterval(7200)

        let schedule = DeviceActivitySchedule(
            intervalStart: calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: start),
            intervalEnd: calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: end),
            repeats: false
        )

        do {
            try center.startMonitoring(activity, during: schedule)
            logger.info("Cross-device focus clear scheduled via DeviceActivity for \(start)")
        } catch {
            logger.warning("Cross-device focus DeviceActivity scheduling failed: \(error.localizedDescription)")
        }
        #endif
    }

    @available(iOS 16.0, *)
    private func stopCrossDeviceFocusDeviceActivity() {
        #if canImport(DeviceActivity)
        DeviceActivityCenter().stopMonitoring([DeviceActivityName(MivoScreenTimeKeys.crossDeviceFocusActivityName)])
        #endif
    }

    // MARK: - Cross-device focus background discovery
    //
    // There is no push channel yet for "the Mac just started a session," so
    // this is the only way the phone can find a new command while the app
    // isn't foregrounded. iOS schedules BGAppRefreshTask opportunistically —
    // this is best-effort, not a guarantee — but it's the same mechanism
    // already used for session relock and Still Lock's unlock fallback, and
    // it re-arms itself every time it runs.
    @available(iOS 16.0, *)
    func scheduleCrossDeviceFocusBackgroundCheck() {
        let request = BGAppRefreshTaskRequest(identifier: MivoScreenTimeKeys.crossDeviceFocusBGTaskIdentifier)
        request.earliestBeginDate = Date().addingTimeInterval(15 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    /// Starts (or re-arms) the DeviceActivity-based poll chain that
    /// `MivoDeviceActivityMonitorExtension` uses to actually discover a new
    /// Mac command while backgrounded/locked — see the doc comment on
    /// `MivoScreenTimeKeys.crossDeviceFocusPollActivityName`. Idempotent:
    /// `startMonitoring` on an activity that's already scheduled just
    /// replaces it, so calling this from every `reconcile()` is harmless
    /// and keeps the chain alive as long as the app is opened at all.
    /// If the extension's own re-arming (after it fires) is working, this
    /// call is mostly a safety net for the very first poll and for the
    /// case where the chain died for some reason.
    @available(iOS 16.0, *)
    func scheduleCrossDeviceFocusPoll(after interval: TimeInterval = 5 * 60) {
        #if canImport(DeviceActivity)
        let center = DeviceActivityCenter()
        let activity = DeviceActivityName(MivoScreenTimeKeys.crossDeviceFocusPollActivityName)
        guard !center.activities.contains(activity) else { return }

        let calendar = Calendar.current
        let start = Date().addingTimeInterval(max(30, interval))
        let end = start.addingTimeInterval(7200)
        let schedule = DeviceActivitySchedule(
            intervalStart: calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: start),
            intervalEnd: calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: end),
            repeats: false
        )
        try? center.startMonitoring(activity, during: schedule)
        #endif
    }
    #else
    func isImpulseProtectionEnabled() -> Bool { false }
    func applyCrossDeviceFocusShield(endsAt: Date) {}
    func clearCrossDeviceFocusShield() {}
    #endif

    // Save a raw JSON summary from the extension (the extension should write the report JSON into the same app group)
    func saveReportJSON(_ json: String) {
        // Save into the app group when available; otherwise standard defaults for development/testing
        userDefaults?.set(json, forKey: lastReportKey)
        userDefaults?.synchronize()
        // Post a notification that new data is available
        NotificationCenter.default.post(name: .mivoDeviceActivityDidUpdate, object: nil)
    }

    func loadLastReportJSON() -> String? {
        return userDefaults?.string(forKey: lastReportKey)
    }

    // Request family controls authorization
    func requestAuthorization(completion: @escaping (Bool) -> Void) {
        #if canImport(FamilyControls)
        guard #available(iOS 16.0, *) else {
            completion(false); return
        }
        Task {
            do {
                try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
                // Mark cached authorization as true
                self.userDefaults?.set(true, forKey: self.authFlagKey)
                self.userDefaults?.synchronize()
                print("[FamilyControlsManager] Authorization success")
                completion(true)
            } catch {
                // Mark cached authorization as false
                self.userDefaults?.set(false, forKey: self.authFlagKey)
                self.userDefaults?.synchronize()
                print("[FamilyControlsManager] Authorization failed: \(error.localizedDescription)")
                // If the error includes an OSStatus or code, print debug description
                print("[FamilyControlsManager] Authorization failure debug: \(error)")
                completion(false)
            }
        }
        #else
        completion(false)
        #endif
    }

    // Persist a cached authorization flag so the UI can show a status quickly
    func saveAuthorizationFlag(_ granted: Bool) {
        userDefaults?.set(granted, forKey: authFlagKey)
        userDefaults?.synchronize()
    }

    // Returns cached authorization if present; nil means unknown (never requested on this install)
    func cachedAuthorizationStatus() -> Bool? {
        guard let ud = userDefaults else { return nil }
        if ud.object(forKey: authFlagKey) == nil { return nil }
        return ud.bool(forKey: authFlagKey)
    }

    /// The cached flag above is written once, at the moment the system prompt
    /// is answered, and never revisited — but Family Controls authorization
    /// can silently change afterward (user revokes it in Settings, or a
    /// fresh dev install/entitlement change resets it at the OS level). When
    /// that happens the cached flag keeps reporting `true` while Apple's own
    /// `AuthorizationCenter` has actually reverted to `.notDetermined`, so
    /// `DeviceActivityReport` silently renders nothing (no error — it just
    /// never calls the report extension), which is what left Home's screen
    /// time total stuck on "—" indefinitely even after the extension-hosting
    /// fixes. This reads Apple's live status and self-heals the cache so
    /// every caller of `cachedAuthorizationStatus()` sees the truth again.
    func liveAuthorizationStatus() -> Bool {
        #if canImport(FamilyControls)
        guard #available(iOS 16.0, *) else { return cachedAuthorizationStatus() ?? false }
        let approved = AuthorizationCenter.shared.authorizationStatus == .approved
        if cachedAuthorizationStatus() != approved {
            saveAuthorizationFlag(approved)
        }
        return approved
        #else
        return cachedAuthorizationStatus() ?? false
        #endif
    }

    // Clear the cached authorization flag (useful to force a fresh request attempt)
    func clearCachedAuthorizationFlag() {
        userDefaults?.removeObject(forKey: authFlagKey)
        userDefaults?.synchronize()
        print("[FamilyControlsManager] Cleared cached authorization flag")
    }

    // Schedule a simple daily DeviceActivity. The actual work is performed by the Device Activity extension.
    func scheduleDailyMonitoring(activityName: String = "mivoDaily", completion: @escaping (Result<Void, Error>) -> Void) {
        #if canImport(DeviceActivity)
        guard #available(iOS 16.0, *) else {
            completion(.failure(NSError(domain: "FamilyControlsManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "iOS 16.0+ required"])))
            return
        }
        
        let center = DeviceActivityCenter()
        let schedule = DeviceActivitySchedule(
            intervalStart: DateComponents(hour: 0, minute: 0),
            intervalEnd: DateComponents(hour: 23, minute: 59),
            repeats: true
        )
        
        // Create an activity name
        let activity = DeviceActivityName(activityName)
        
        do {
            // Start monitoring all device activity for the entire day
            try center.startMonitoring(activity, during: schedule)
            print("[FamilyControlsManager] Successfully scheduled daily monitoring for activity: \(activityName)")
            completion(.success(()))
        } catch {
            print("[FamilyControlsManager] Failed to schedule monitoring: \(error.localizedDescription)")
            completion(.failure(error))
        }
        #else
        // DeviceActivity framework not available in this build — no-op
        completion(.failure(NSError(domain: "FamilyControlsManager", code: -2, userInfo: [NSLocalizedDescriptionKey: "DeviceActivity framework not available"])))
        #endif
    }
    
    // Stop monitoring
    func stopMonitoring(activityName: String = "mivoDaily") {
        #if canImport(DeviceActivity)
        guard #available(iOS 16.0, *) else { return }
        let center = DeviceActivityCenter()
        let activity = DeviceActivityName(activityName)
        center.stopMonitoring([activity])
        print("[FamilyControlsManager] Stopped monitoring for activity: \(activityName)")
        #endif
    }
    
    // Check if monitoring is active
    func isMonitoring(activityName: String = "mivoDaily") -> Bool {
        #if canImport(DeviceActivity)
        guard #available(iOS 16.0, *) else { return false }
        let center = DeviceActivityCenter()
        let activity = DeviceActivityName(activityName)
        return center.activities.contains(activity)
        #else
        return false
        #endif
    }
    
    // MARK: - Blocker Self-Test
    
    /// Run a self-test of the Device Activity monitor extension.
    /// This schedules a 15-second activity that should trigger intervalDidEnd callback.
    /// Returns true if scheduling succeeded, false otherwise.
    func runBlockerSelfTest() -> Bool {
        #if canImport(DeviceActivity)
        guard #available(iOS 16.0, *) else { return false }
        
        // Clear previous test results
        userDefaults?.removeObject(forKey: blockerSelfTestStartKey)
        userDefaults?.removeObject(forKey: blockerSelfTestEndKey)
        userDefaults?.set(false, forKey: blockerSelfTestPassedKey)
        userDefaults?.synchronize()
        
        let center = DeviceActivityCenter()
        let activity = DeviceActivityName(blockerSelfTestActivityName)
        center.stopMonitoring([activity])
        
        let calendar = Calendar.current
        let now = Date()
        let start = now.addingTimeInterval(1)
        let end = now.addingTimeInterval(16) // 15 second test after a future start
        let startComponents = calendar.dateComponents([.hour, .minute, .second], from: start)
        let endComponents = calendar.dateComponents([.hour, .minute, .second], from: end)
        let schedule = DeviceActivitySchedule(
            intervalStart: startComponents,
            intervalEnd: endComponents,
            repeats: false
        )
        
        // Record test start
        userDefaults?.set(ISO8601DateFormatter().string(from: now), forKey: blockerSelfTestStartKey)
        userDefaults?.synchronize()
        
        do {
            try center.startMonitoring(activity, during: schedule)
            
            // Verify it's active
            let isActive = center.activities.contains(activity)
            if isActive {
                print("[FamilyControlsManager] ✅ Blocker self-test scheduled (15s)")
                return true
            } else {
                print("[FamilyControlsManager] ⚠️ Blocker self-test scheduling did not confirm active")
                return false
            }
        } catch {
            print("[FamilyControlsManager] ❌ Blocker self-test failed to schedule: \(error.localizedDescription)")
            return false
        }
        #else
        return false
        #endif
    }
    
    /// Mark that the self-test callback was received (called from extension via app group)
    func markBlockerSelfTestCompleted() {
        userDefaults?.set(ISO8601DateFormatter().string(from: Date()), forKey: blockerSelfTestEndKey)
        userDefaults?.set(true, forKey: blockerSelfTestPassedKey)
        userDefaults?.synchronize()
        print("[FamilyControlsManager] ✅ Blocker self-test callback received")
    }
    
    /// Check if the blocker self-test has passed recently (within 24 hours)
    func hasRecentBlockerSelfTestPass() -> Bool {
        guard let passed = userDefaults?.bool(forKey: blockerSelfTestPassedKey), passed else {
            return false
        }
        
        guard let endDateString = userDefaults?.string(forKey: blockerSelfTestEndKey),
              let endDate = ISO8601DateFormatter().date(from: endDateString) else {
            return false
        }
        
        let ageHours = Date().timeIntervalSince(endDate) / 3600
        return ageHours < 24
    }
    
    /// Get self-test diagnostic info
    func getBlockerSelfTestDiagnostics() -> String {
        var info = "Blocker Self-Test Diagnostics\n"
        info += "==============================\n\n"
        
        if let startString = userDefaults?.string(forKey: blockerSelfTestStartKey) {
            info += "Test started: \(startString)\n"
        } else {
            info += "Test started: Never\n"
        }
        
        if let endString = userDefaults?.string(forKey: blockerSelfTestEndKey) {
            info += "Test completed: \(endString)\n"
        } else {
            info += "Test completed: Never\n"
        }
        
        let passed = userDefaults?.bool(forKey: blockerSelfTestPassedKey) ?? false
        info += "Test passed: \(passed ? "YES" : "NO")\n"
        
        let hasRecent = hasRecentBlockerSelfTestPass()
        info += "Recent pass (< 24h): \(hasRecent ? "YES" : "NO")\n\n"
        
        if hasRecent {
            info += "✅ Blocker is healthy - timed sessions can proceed\n"
        } else {
            info += "⚠️ Blocker not verified - sessions may not relock properly\n"
            info += "Run the test, leave Mivo, stop Xcode, wait 15+ seconds, reopen Mivo\n"
        }
        
        return info
    }
}

// Notification name when the extension writes new data into the app group
extension Notification.Name {
    static let mivoDeviceActivityDidUpdate = Notification.Name("mivoDeviceActivityDidUpdate")
    static let mivoSessionHistoryDidUpdate = Notification.Name("mivoSessionHistoryDidUpdate")
}
