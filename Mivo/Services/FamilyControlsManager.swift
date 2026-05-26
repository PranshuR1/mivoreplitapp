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
        sessionRelockWorkItem?.cancel()
        sessionRelockWorkItem = nil

        guard durationSeconds > 0 else {
            if #available(iOS 16.0, *) {
                applyImpulseProtectionIfNeeded()
            }
            return .failure(.noTimeRemaining)
        }

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
        // Requires NSSupportsLiveActivities = YES in Info.plist and the MivoWidgets
        // extension target set up in Xcode (see Mivo/Constants/MivoLiveActivityAttributes.swift).
        let sessionEnd = Date().addingTimeInterval(TimeInterval(durationSeconds))
        startSessionLiveActivity(sessionEndsAt: sessionEnd, planMinutes: durationSeconds / 60, intentionLabel: "Session active")

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

        // Nudges: in case the user misses or dismisses the first banner, fire follow-ups
        // 30s and 90s after session end. These keep prompting until the user opens Mivo
        // (which re-locks the apps and cancels any pending notifications via cancelSessionEndNotification).
        scheduleSessionEndNudge(identifier: "mivo.session.ended.nudge1", after: max(delay, 1) + 30)
        scheduleSessionEndNudge(identifier: "mivo.session.ended.nudge2", after: max(delay, 1) + 90)
    }

    private func scheduleSessionEndNudge(identifier: String, after delay: TimeInterval) {
        let content = UNMutableNotificationContent()
        content.title = "Apps still unlocked"
        content.body = "Open Mivo to re-lock and start fresh."
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
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [
            "mivo.session.ended",
            "mivo.session.ended.nudge1",
            "mivo.session.ended.nudge2"
        ])
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
        logger.info("Shield re-applied: apps=\(selection.applicationTokens.count) categories=\(selection.categoryTokens.count) domains=\(selection.webDomainTokens.count)")
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
    #else
    func isImpulseProtectionEnabled() -> Bool { false }
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
