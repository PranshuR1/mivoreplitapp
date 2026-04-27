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
        
        // Generate and save the daily report
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
        // Access device activity data and generate a report
        // Note: Actual screen time data requires using the DeviceActivityReport API
        // For now, we'll create a placeholder report structure
        
        let appGroup = "group.com.mivo.mivoapp"
        guard let userDefaults = UserDefaults(suiteName: appGroup) else {
            appendLog("Failed to access app group for saving report")
            return
        }
        
        // Create a report structure
        // In a real implementation, you would use DeviceActivityReport or other APIs
        // to get actual usage data
        let report: [String: Any] = [
            "generatedAt": ISO8601DateFormatter().string(from: Date()),
            "totalSeconds": 0,  // Would be populated with actual data
            "perAppSeconds": [:],  // Would be populated with actual data
            "note": "This is a placeholder. Implement actual data collection using DeviceActivityReport or other APIs."
        ]
        
        // Serialize and save
        if let jsonData = try? JSONSerialization.data(withJSONObject: report, options: []),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            userDefaults.set(jsonString, forKey: "mivo.lastDeviceActivityReport")
            userDefaults.synchronize()
            appendLog("Daily report saved to app group")
            
            // Post notification to main app
            // Note: This may not work from an extension context, but we'll try
            notifyMainApp()
        } else {
            appendLog("Failed to serialize report")
        }
    }
    
    private func notifyMainApp() {
        // Try to notify the main app that new data is available
        // Extensions have limited ability to communicate with the main app
        // The main app should periodically check the shared UserDefaults
        
        let appGroup = "group.com.mivo.mivoapp"
        guard let userDefaults = UserDefaults(suiteName: appGroup) else { return }
        
        userDefaults.set(Date().timeIntervalSince1970, forKey: "mivo.lastReportTimestamp")
        userDefaults.synchronize()
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
