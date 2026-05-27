import Foundation
import DeviceActivity
import FamilyControls
import ManagedSettings

// MARK: - Device Activity Monitor Extension
// This extension is called by the system when device activity events occur.
// It must be part of a separate Device Activity Monitor Extension target.

@available(iOS 16.0, *)
final class MivoDeviceActivityMonitor: DeviceActivityMonitor {

    private let appGroup = "group.com.mivo.mivoapp"
    private let sessionRelockActivityName = "mivo.session.relock"
    private let blockerSelfTestActivityName = "mivo.blocker.selftest"
    private let leaseEnforcementActivityName = "mivo.lease.enforcement"
    
    // Called when the monitoring interval starts (e.g., beginning of day)
    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)
        
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let activityString = activity.rawValue
        appendLog("[\(timestamp)] ⏰ Monitoring interval STARTED for activity: \(activityString)")
        
        // Handle self-test start
        if activityString == blockerSelfTestActivityName {
            appendLog("[\(timestamp)] 🧪 Self-test interval started")
        }
        
        // Reset daily counters if needed for daily monitoring
        if activityString.contains("Daily") {
            resetDailyCounters()
        }
    }
    
    // Called when the monitoring interval ends (e.g., end of day)
    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)

        let timestamp = ISO8601DateFormatter().string(from: Date())
        let activityString = activity.rawValue
        appendLog("[\(timestamp)] ⏰ Monitoring interval ENDED for activity: \(activityString)")

        // Handle session relock (full session timer ended)
        if activityString == sessionRelockActivityName {
            handleSessionRelock()
            return
        }

        // Handle lease enforcement (mid-scroll check-in interval ended).
        // This is what powers the periodic 5-second mid-scroll pause: at the end of
        // each check-in lease, we re-apply the shield so the user gets a brief pause
        // the next time they open a protected app.
        if activityString == leaseEnforcementActivityName {
            handleLeaseEnforcementEnded()
            return
        }

        // Handle self-test completion
        if activityString == blockerSelfTestActivityName {
            handleSelfTestCompletion()
            return
        }

        // Handle daily monitoring
        if activityString.contains("Daily") {
            generateAndSaveDailyReport()
        }
    }
    
    // Called when an event threshold is reached (if configured)
    override func eventDidReachThreshold(_ event: DeviceActivityEvent.Name, activity: DeviceActivityName) {
        super.eventDidReachThreshold(event, activity: activity)
        
        let timestamp = ISO8601DateFormatter().string(from: Date())
        appendLog("[\(timestamp)] Event threshold reached: \(event) for activity: \(activity)")
    }
    
    // Called when a warning threshold is reached (if configured)
    override func eventWillReachThresholdWarning(_ event: DeviceActivityEvent.Name, activity: DeviceActivityName) {
        super.eventWillReachThresholdWarning(event, activity: activity)
        
        let timestamp = ISO8601DateFormatter().string(from: Date())
        appendLog("[\(timestamp)] Event warning threshold reached: \(event) for activity: \(activity)")
    }
    
    // MARK: - Private Helpers
    
    private func handleSessionRelock() {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        appendLog("[\(timestamp)] 🔒 SESSION RELOCK - Timer ended, relocking protected apps")
        
        guard let userDefaults = UserDefaults(suiteName: appGroup) else {
            appendLog("[\(timestamp)] ❌ Failed to access app group for session relock")
            return
        }
        
        // End the session and require intervention setup
        userDefaults.set(false, forKey: "mivo.sessionActive")
        userDefaults.removeObject(forKey: "mivo.sessionEndsAt")
        userDefaults.set(true, forKey: "mivo.pendingInterventionSetup")
        userDefaults.set(Date().timeIntervalSince1970, forKey: "mivo.pendingInterventionSetupAt")
        userDefaults.synchronize()
        
        // Reapply shields via ManagedSettingsStore
        _ = ManagedSettingsStore(named: ManagedSettingsStore.Name("mivo.intervention"))
        // Shield configuration will be applied by ShieldConfigurationExtension based on flags
        // The extension reads the flags and shows appropriate shield UI
        
        appendLog("[\(timestamp)] ✅ Session ended, intervention required before next access")
    }
    
    /// Mid-scroll check-in: when the lease enforcement DeviceActivity interval ends,
    /// re-apply shields so the next protected-app open shows the 5-sec check-in pause.
    private func handleLeaseEnforcementEnded() {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        appendLog("[\(timestamp)] 🔁 LEASE END - mid-scroll check-in: reapplying shield")

        guard let userDefaults = UserDefaults(suiteName: appGroup) else {
            appendLog("[\(timestamp)] ❌ Failed to access app group for lease enforcement")
            return
        }

        // Confirm we're inside an active session and protection is on.
        guard userDefaults.bool(forKey: "mivo.sessionActive"),
              userDefaults.bool(forKey: "mivo.impulseProtectionEnabled"),
              userDefaults.bool(forKey: "mivo.impulseProtectionSignedIn") else {
            appendLog("[\(timestamp)] Lease end ignored — session inactive or protection off")
            return
        }

        // Mark lease end and source for the shield-configuration extension to read.
        userDefaults.set(Date().timeIntervalSince1970, forKey: "mivo.leaseMonitorDidEndAt")
        userDefaults.set("device-activity-lease-end", forKey: "mivo.lastShieldSource")
        userDefaults.synchronize()

        // Re-apply the saved family-activity selection to both ManagedSettings stores.
        let interventionStore = ManagedSettingsStore(named: ManagedSettingsStore.Name("mivo.intervention"))
        let legacyStore = ManagedSettingsStore()
        let selection = loadFamilyActivitySelection()
        applySelection(selection, to: interventionStore)
        applySelection(selection, to: legacyStore)

        appendLog("[\(timestamp)] ✅ Shield re-applied for mid-scroll check-in")
    }

    private func loadFamilyActivitySelection() -> FamilyActivitySelection {
        guard let defaults = UserDefaults(suiteName: appGroup),
              let data = defaults.data(forKey: "mivo.familyActivitySelection"),
              let selection = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data) else {
            return FamilyActivitySelection()
        }
        return selection
    }

    private func applySelection(_ selection: FamilyActivitySelection, to store: ManagedSettingsStore) {
        store.shield.applications = selection.applicationTokens.isEmpty ? nil : selection.applicationTokens
        store.shield.applicationCategories = selection.categoryTokens.isEmpty ? nil : .specific(selection.categoryTokens)
        store.shield.webDomains = selection.webDomainTokens.isEmpty ? nil : selection.webDomainTokens
    }

    private func handleSelfTestCompletion() {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        appendLog("[\(timestamp)] ✅ SELF-TEST COMPLETED - Extension is working correctly")
        
        guard let userDefaults = UserDefaults(suiteName: appGroup) else {
            appendLog("[\(timestamp)] ❌ Failed to access app group for self-test")
            return
        }
        
        // Mark test as completed
        userDefaults.set(timestamp, forKey: "mivo.blockerSelfTestEnd")
        userDefaults.set(true, forKey: "mivo.blockerSelfTestPassed")
        userDefaults.synchronize()
        
        appendLog("[\(timestamp)] Self-test results written to app group")
    }
    
    private func resetDailyCounters() {
        // Reset any daily tracking data
        guard let userDefaults = UserDefaults(suiteName: appGroup) else {
            appendLog("Failed to access app group for resetting counters")
            return
        }
        
        userDefaults.set(0, forKey: "mivo.dailyScreenTimeSeconds")
        userDefaults.synchronize()
        appendLog("Daily counters reset")
    }
    
    private func generateAndSaveDailyReport() {
        appendLog("Monitoring interval ended. No numeric report was written because Screen Time totals must come from a DeviceActivityReport extension.")
    }
    
    private func appendLog(_ message: String) {
        guard let userDefaults = UserDefaults(suiteName: appGroup) else { return }
        
        var logs = userDefaults.stringArray(forKey: "mivo.extensionLogs") ?? []
        logs.append(message)
        
        // Keep only last 100 log entries (increased from 50 for better debugging)
        if logs.count > 100 {
            logs = Array(logs.suffix(100))
        }
        
        userDefaults.set(logs, forKey: "mivo.extensionLogs")
        userDefaults.synchronize()
    }
}
