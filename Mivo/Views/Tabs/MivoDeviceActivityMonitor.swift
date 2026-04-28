import Foundation
import DeviceActivity
import FamilyControls
import ManagedSettings

// MARK: - Device Activity Monitor Extension
// This extension is called by the system when device activity events occur.
// It must be part of a separate Device Activity Monitor Extension target.

@available(iOS 16.0, *)
final class MivoDeviceActivityMonitor: DeviceActivityMonitor {
    
    // Called when the monitoring interval starts (e.g., beginning of day)
    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)
        
        let timestamp = ISO8601DateFormatter().string(from: Date())
        appendLog("[\(timestamp)] Monitoring interval started for activity: \(activity)")
        
        // Reset daily counters if needed
        resetDailyCounters()
    }
    
    // Called when the monitoring interval ends (e.g., end of day)
    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        
        let timestamp = ISO8601DateFormatter().string(from: Date())
        appendLog("[\(timestamp)] Monitoring interval ended for activity: \(activity)")
        
        // DeviceActivityMonitor cannot read raw Screen Time totals directly.
        // Numeric reports must be produced by a DeviceActivityReport extension.
        generateAndSaveDailyReport()
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
    
    private func resetDailyCounters() {
        // Reset any daily tracking data
        let appGroup = "group.com.mivo.mivoapp"
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
        let appGroup = "group.com.mivo.mivoapp"
        guard let userDefaults = UserDefaults(suiteName: appGroup) else { return }
        
        var logs = userDefaults.stringArray(forKey: "mivo.extensionLogs") ?? []
        logs.append(message)
        
        // Keep only last 50 log entries
        if logs.count > 50 {
            logs = Array(logs.suffix(50))
        }
        
        userDefaults.set(logs, forKey: "mivo.extensionLogs")
        userDefaults.synchronize()
    }
}
