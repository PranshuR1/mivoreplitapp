import Foundation
import DeviceActivity
import FamilyControls

#if canImport(DeviceActivity)
import DeviceActivity
#endif

// MARK: - Screen Time Data Collector
// This class helps collect and process screen time data from the system

@available(iOS 16.0, *)
@MainActor
class ScreenTimeDataCollector {
    
    static let shared = ScreenTimeDataCollector()
    
    private let appGroup = "group.com.mivo.mivoapp"
    
    private init() {}

    var authorizationStatus: MivoScreenTimeAuthorizationStatus {
        guard let cached = FamilyControlsManager.shared.cachedAuthorizationStatus() else {
            return .notDetermined
        }
        return cached ? .authorized : .denied
    }

    var isMonitoring: Bool {
        FamilyControlsManager.shared.isMonitoring()
    }

    func startMonitoring() {
        FamilyControlsManager.shared.scheduleDailyMonitoring { _ in }
    }

    var latestReport: ScreenTimeReport? {
        loadCachedReport()
    }
    
    // MARK: - Public Methods
    
    /// Request usage data for today
    func requestTodayUsageData(completion: @escaping (Result<ScreenTimeReport, Error>) -> Void) {
        #if canImport(DeviceActivity)
        // Note: DeviceActivityReport needs to be used within a SwiftUI context
        // For now, we'll check if data exists in the shared container
        if let report = loadCachedReport() {
            completion(.success(report))
        } else {
            completion(.failure(NSError(domain: "ScreenTimeDataCollector", 
                                       code: -1, 
                                       userInfo: [NSLocalizedDescriptionKey: "No cached report available. Please ensure monitoring is running."])))
        }
        #else
        completion(.failure(NSError(domain: "ScreenTimeDataCollector", 
                                   code: -2, 
                                   userInfo: [NSLocalizedDescriptionKey: "DeviceActivity framework not available"])))
        #endif
    }
    
    /// Load the most recent cached report from the app group
    func loadCachedReport() -> ScreenTimeReport? {
        guard let userDefaults = UserDefaults(suiteName: appGroup),
              let jsonString = userDefaults.string(forKey: "mivo.lastDeviceActivityReport"),
              let data = jsonString.data(using: .utf8) else {
            return nil
        }
        
        do {
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                return ScreenTimeReport(from: json)
            }
        } catch {
            print("[ScreenTimeDataCollector] Failed to parse cached report: \(error)")
        }
        
        return nil
    }
    
    /// Save a report to the app group
    func saveReport(_ report: ScreenTimeReport) {
        guard let userDefaults = UserDefaults(suiteName: appGroup) else {
            print("[ScreenTimeDataCollector] Failed to access app group")
            return
        }
        
        let json = report.toJSON()
        if let jsonData = try? JSONSerialization.data(withJSONObject: json, options: []),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            userDefaults.set(jsonString, forKey: "mivo.lastDeviceActivityReport")
            userDefaults.set(Date().timeIntervalSince1970, forKey: "mivo.lastReportTimestamp")
            userDefaults.synchronize()
            
            // Notify the app
            NotificationCenter.default.post(name: .mivoDeviceActivityDidUpdate, object: nil)
        }
    }
    
    /// Get extension logs for debugging
    func getExtensionLogs() -> [String] {
        guard let userDefaults = UserDefaults(suiteName: appGroup) else {
            return ["Failed to access app group"]
        }
        return userDefaults.stringArray(forKey: "mivo.extensionLogs") ?? []
    }
    
    /// Clear extension logs
    func clearExtensionLogs() {
        guard let userDefaults = UserDefaults(suiteName: appGroup) else { return }
        userDefaults.removeObject(forKey: "mivo.extensionLogs")
        userDefaults.synchronize()
    }
}

enum MivoScreenTimeAuthorizationStatus {
    case authorized
    case denied
    case notDetermined
    case unavailable
}

// MARK: - Screen Time Report Model

@available(iOS 16.0, *)
struct ScreenTimeReport {
    let generatedAt: Date
    let totalSeconds: Int
    let perAppSeconds: [String: Int]
    let topApps: [(bundleID: String, seconds: Int)]
    
    init(generatedAt: Date = Date(), totalSeconds: Int = 0, perAppSeconds: [String: Int] = [:]) {
        self.generatedAt = generatedAt
        self.totalSeconds = totalSeconds
        self.perAppSeconds = perAppSeconds
        
        // Calculate top apps
        let sorted = perAppSeconds.sorted { $0.value > $1.value }
        self.topApps = sorted.map { (bundleID: $0.key, seconds: $0.value) }
    }
    
    init?(from json: [String: Any]) {
        guard let generatedAtString = json["generatedAt"] as? String,
              let generatedAt = ISO8601DateFormatter().date(from: generatedAtString) else {
            return nil
        }
        
        self.generatedAt = generatedAt
        
        // Try to get total seconds
        if let total = json["totalSeconds"] as? Int {
            self.totalSeconds = total
        } else if let total = json["totalSeconds"] as? Double {
            self.totalSeconds = Int(total)
        } else {
            self.totalSeconds = 0
        }
        
        // Try to get per-app data
        if let perApp = json["perAppSeconds"] as? [String: Any] {
            var perAppSeconds: [String: Int] = [:]
            for (key, value) in perApp {
                if let intValue = value as? Int {
                    perAppSeconds[key] = intValue
                } else if let doubleValue = value as? Double {
                    perAppSeconds[key] = Int(doubleValue)
                }
            }
            self.perAppSeconds = perAppSeconds
        } else {
            self.perAppSeconds = [:]
        }
        
        // Calculate top apps
        let sorted = self.perAppSeconds.sorted { $0.value > $1.value }
        self.topApps = sorted.map { (bundleID: $0.key, seconds: $0.value) }
    }
    
    func toJSON() -> [String: Any] {
        return [
            "generatedAt": ISO8601DateFormatter().string(from: generatedAt),
            "totalSeconds": totalSeconds,
            "perAppSeconds": perAppSeconds
        ]
    }
    
    var totalMinutes: Int {
        return totalSeconds / 60
    }
    
    var totalHours: Double {
        return Double(totalSeconds) / 3600.0
    }
    
    func formattedDuration() -> String {
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
}
