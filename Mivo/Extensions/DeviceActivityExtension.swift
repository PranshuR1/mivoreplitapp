import DeviceActivity
import FamilyControls
import ManagedSettings
import os

// Minimal DeviceActivityMonitor subclass. Place this file inside a Device Activity extension target (not the main app target).
// This implementation writes a compact JSON summary into the shared App Group so the main app can read it.

@available(iOS 16.0, *)
public class DeviceActivityMonitorHandler: DeviceActivityMonitor {
    let logger = Logger(subsystem: "app.mivo.com", category: "DeviceActivityMonitor")
    let appGroup = "group.com.mivo.mivoapp" // must match FamilyControlsManager.appGroup

    public override func intervalDidStart(context: DeviceActivityContext) {
        logger.log("intervalDidStart: \(context)")
    }

    public override func activityDidEnd(_ activity: DeviceActivityName) {
        logger.log("activityDidEnd: \(activity) reached")
    }

    public override func eventualDidUpdate(context: DeviceActivityContext) {
        // Called when the system has new aggregated data available
        logger.log("eventualDidUpdate: \(context)")

        // Simple extraction of usage by bundle id for the monitored apps
        var summary: [String: Any] = [:]
        var totalSeconds = 0
        if let events = context.eventsByApplication {
            var perApp: [String: Int] = [:]
            for (app, eventsForApp) in events {
                // sum foreground time in seconds (approximate)
                let total = eventsForApp.reduce(0) { $0 + ($1.interval.duration ?? 0) }
                let secs = Int(total)
                totalSeconds += secs
                perApp[app.bundleIdentifier ?? "unknown"] = secs
            }
            summary["perAppSeconds"] = perApp
        }

        // Add generated timestamp and an explicit totalSeconds field to make parsing straightforward
        let iso = ISO8601DateFormatter().string(from: Date())
        summary["generatedAt"] = iso
        summary["totalSeconds"] = totalSeconds

        // Save into shared UserDefaults (app group)
        if let data = try? JSONSerialization.data(withJSONObject: summary, options: []) {
            if let str = String(data: data, encoding: .utf8) {
                if let ud = UserDefaults(suiteName: appGroup) {
                    ud.set(str, forKey: "mivo.lastDeviceActivityReport")
                    ud.synchronize()
                }
            }
        }
    }
}
