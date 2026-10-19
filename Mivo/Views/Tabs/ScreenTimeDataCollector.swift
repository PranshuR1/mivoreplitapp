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
        guard FamilyControlsManager.shared.cachedAuthorizationStatus() != nil else {
            return .notDetermined
        }
        return FamilyControlsManager.shared.liveAuthorizationStatus() ? .authorized : .denied
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
        if let report = loadCachedReport() {
            completion(.success(report))
        } else {
            completion(.failure(NSError(domain: "ScreenTimeDataCollector", 
                                       code: -1, 
                                       userInfo: [NSLocalizedDescriptionKey: "No numeric Screen Time report has been published by iOS yet. Use the live Device Activity report view for real Screen Time data."])))
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
                guard json["source"] as? String == "mivo-device-activity-extension" else {
                    clearCachedReport()
                    return nil
                }
                guard let report = ScreenTimeReport(from: json),
                      report.reportDate == Self.todayKey() else {
                    clearCachedReport()
                    return nil
                }
                return report
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

    func clearCachedReport() {
        if let userDefaults = UserDefaults(suiteName: appGroup) {
            userDefaults.removeObject(forKey: "mivo.lastDeviceActivityReport")
            userDefaults.removeObject(forKey: "mivo.lastReportTimestamp")
            userDefaults.synchronize()
        }
        UserDefaults.standard.removeObject(forKey: "mivo.lastDeviceActivityReport")
    }

    private static func todayKey(_ date: Date = Date()) -> String {
        let formatter = MivoDay.formatter
        return formatter.string(from: date)
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
    let reportDate: String
    let totalSeconds: Int
    let perAppSeconds: [String: Int]
    let topApps: [(bundleID: String, seconds: Int)]
    
    init(generatedAt: Date = Date(), reportDate: String? = nil, totalSeconds: Int = 0, perAppSeconds: [String: Int] = [:]) {
        self.generatedAt = generatedAt
        self.reportDate = reportDate ?? Self.dateKey(generatedAt)
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
        self.reportDate = (json["reportDate"] as? String) ?? Self.dateKey(generatedAt)
        
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
            "reportDate": reportDate,
            "totalSeconds": totalSeconds,
            "perAppSeconds": perAppSeconds,
            "source": "mivo-device-activity-extension"
        ]
    }
    
    var totalMinutes: Int {
        return totalSeconds / 60
    }

    private static func dateKey(_ date: Date) -> String {
        let formatter = MivoDay.formatter
        return formatter.string(from: date)
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
