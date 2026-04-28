import Foundation
import SwiftUI

#if canImport(FamilyControls)
import FamilyControls
#endif

#if canImport(DeviceActivity)
import DeviceActivity
#endif

#if canImport(ManagedSettings)
import ManagedSettings
#endif

// MARK: - Screen Time Report Model

struct ScreenTimeReport: Codable {
    var totalSeconds: Int
    var topApps: [AppUsage]
    var date: Date
    
    var totalMinutes: Int {
        totalSeconds / 60
    }
    
    var totalHours: Double {
        Double(totalSeconds) / 3600.0
    }
    
    func formattedDuration() -> String {
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else if minutes > 0 {
            return "\(minutes) min"
        } else {
            return "\(totalSeconds)s"
        }
    }
}

struct AppUsage: Codable, Identifiable {
    var id: String { bundleID }
    let bundleID: String
    let seconds: Int
    
    var minutes: Int {
        seconds / 60
    }
}

// MARK: - Screen Time Data Collector

@available(iOS 16.0, *)
class ScreenTimeDataCollector: ObservableObject {
    static let shared = ScreenTimeDataCollector()
    
    @Published var authorizationStatus: AuthorizationStatus = .notDetermined
    @Published var latestReport: ScreenTimeReport?
    @Published var isMonitoring: Bool = false
    
    private let activityCenter = DeviceActivityCenter()
    private let store = ManagedSettingsStore()
    private var authorizationCenter = AuthorizationCenter.shared
    
    // App Group for sharing data with extensions
    private let appGroupID = "group.com.mivo.mivoapp"
    private let reportKey = "mivo.screenTimeReport"
    
    // Timer for polling updates
    private var pollingTimer: Timer?
    
    private init() {
        checkAuthorizationStatus()
    }
    
    // MARK: - Authorization
    
    func checkAuthorizationStatus() {
        #if canImport(FamilyControls)
        switch authorizationCenter.authorizationStatus {
        case .notDetermined:
            authorizationStatus = .notDetermined
        case .denied:
            authorizationStatus = .denied
        case .approved:
            authorizationStatus = .authorized
        @unknown default:
            authorizationStatus = .notDetermined
        }
        #else
        authorizationStatus = .unavailable
        #endif
    }
    
    func requestAuthorization() async throws {
        #if canImport(FamilyControls)
        try await authorizationCenter.requestAuthorization(for: .individual)
        await MainActor.run {
            checkAuthorizationStatus()
            if authorizationStatus == .authorized {
                startMonitoring()
            }
        }
        #else
        throw ScreenTimeError.unavailable
        #endif
    }
    
    // MARK: - Monitoring
    
    func startMonitoring() {
        guard authorizationStatus == .authorized else { return }
        
        isMonitoring = true
        
        // Start device activity monitoring
        let schedule = DeviceActivitySchedule(
            intervalStart: DateComponents(hour: 0, minute: 0),
            intervalEnd: DateComponents(hour: 23, minute: 59),
            repeats: true
        )
        
        do {
            let activityName = DeviceActivityName("mivo.daily.tracking")
            try activityCenter.startMonitoring(activityName, during: schedule)
            
            // Start polling for updates every 5 minutes
            startPollingForUpdates()
            
            // Initial load
            Task {
                await loadTodayData()
            }
        } catch {
            print("❌ Failed to start monitoring: \(error)")
            isMonitoring = false
        }
    }
    
    func stopMonitoring() {
        let activityName = DeviceActivityName("mivo.daily.tracking")
        activityCenter.stopMonitoring([activityName])
        isMonitoring = false
        pollingTimer?.invalidate()
        pollingTimer = nil
    }
    
    private func startPollingForUpdates() {
        pollingTimer?.invalidate()
        pollingTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.loadTodayData()
            }
        }
    }
    
    // MARK: - Data Loading
    
    func requestTodayUsageData(completion: @escaping (Result<ScreenTimeReport, Error>) -> Void) {
        guard authorizationStatus == .authorized else {
            completion(.failure(ScreenTimeError.notAuthorized))
            return
        }
        
        Task {
            await loadTodayData()
            
            if let report = latestReport {
                completion(.success(report))
            } else {
                // If no data from Screen Time API, generate mock data for development
                #if DEBUG
                let mockReport = generateMockReport()
                await MainActor.run {
                    latestReport = mockReport
                }
                completion(.success(mockReport))
                #else
                completion(.failure(ScreenTimeError.noData))
                #endif
            }
        }
    }
    
    @MainActor
    private func loadTodayData() async {
        // Try to load from DeviceActivity report
        if let report = await fetchDeviceActivityReport() {
            latestReport = report
            saveToAppGroup(report)
            notifyUpdate()
            return
        }
        
        // Fallback: try loading from app group (if extension wrote it)
        if let report = loadFromAppGroup() {
            latestReport = report
            notifyUpdate()
            return
        }
        
        // Development fallback
        #if DEBUG
        latestReport = generateMockReport()
        notifyUpdate()
        #endif
    }
    
    private func fetchDeviceActivityReport() async -> ScreenTimeReport? {
        #if canImport(DeviceActivity)
        // In a real implementation, you would use DeviceActivityReport here
        // This requires a Device Activity Report Extension
        // For now, we'll return nil to indicate we need to set up the extension
        return nil
        #else
        return nil
        #endif
    }
    
    // MARK: - App Group Storage
    
    private func saveToAppGroup(_ report: ScreenTimeReport) {
        guard let defaults = UserDefaults(suiteName: appGroupID) else { return }
        
        if let encoded = try? JSONEncoder().encode(report) {
            defaults.set(encoded, forKey: reportKey)
            defaults.set(Date(), forKey: "mivo.lastUpdate")
            defaults.synchronize()
        }
    }
    
    private func loadFromAppGroup() -> ScreenTimeReport? {
        guard let defaults = UserDefaults(suiteName: appGroupID),
              let data = defaults.data(forKey: reportKey) else { return nil }
        
        return try? JSONDecoder().decode(ScreenTimeReport.self, from: data)
    }
    
    private func notifyUpdate() {
        NotificationCenter.default.post(name: Notification.Name("mivoDeviceActivityDidUpdate"), object: nil)
    }
    
    // MARK: - Mock Data (Development)
    
    private func generateMockReport() -> ScreenTimeReport {
        let now = Date()
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: now)
        
        // Generate realistic mock data based on time of day
        let baseMinutes = min(hour * 15, 180) // Up to 3 hours by end of day
        let randomVariation = Int.random(in: -30...30)
        let totalMinutes = max(0, baseMinutes + randomVariation)
        let totalSeconds = totalMinutes * 60
        
        let mockApps = [
            AppUsage(bundleID: "com.instagram.Instagram", seconds: Int(Double(totalSeconds) * 0.25)),
            AppUsage(bundleID: "com.atebits.Tweetie2", seconds: Int(Double(totalSeconds) * 0.20)),
            AppUsage(bundleID: "com.google.chrome.ios", seconds: Int(Double(totalSeconds) * 0.15)),
            AppUsage(bundleID: "com.apple.mobilesafari", seconds: Int(Double(totalSeconds) * 0.12)),
            AppUsage(bundleID: "com.burbn.TikTok", seconds: Int(Double(totalSeconds) * 0.10)),
            AppUsage(bundleID: "com.facebook.Facebook", seconds: Int(Double(totalSeconds) * 0.08)),
            AppUsage(bundleID: "com.reddit.Reddit", seconds: Int(Double(totalSeconds) * 0.06)),
            AppUsage(bundleID: "com.google.Gmail", seconds: Int(Double(totalSeconds) * 0.04))
        ].sorted { $0.seconds > $1.seconds }
        
        return ScreenTimeReport(
            totalSeconds: totalSeconds,
            topApps: mockApps,
            date: now
        )
    }
}

// MARK: - Authorization Status

enum AuthorizationStatus {
    case notDetermined
    case denied
    case authorized
    case unavailable
}

// MARK: - Errors

enum ScreenTimeError: LocalizedError {
    case notAuthorized
    case unavailable
    case noData
    case extensionNotConfigured
    
    var errorDescription: String? {
        switch self {
        case .notAuthorized:
            return "Screen Time access not authorized. Please grant permission in Settings."
        case .unavailable:
            return "Screen Time API is not available on this device or iOS version."
        case .noData:
            return "No screen time data available yet. Check back later."
        case .extensionNotConfigured:
            return "Device Activity extension needs to be configured."
        }
    }
}

// MARK: - SwiftUI Integration

@available(iOS 16.0, *)
struct ScreenTimeAuthorizationView: View {
    @StateObject private var collector = ScreenTimeDataCollector.shared
    @State private var isRequesting = false
    @State private var error: String?
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        ZStack {
            MivoColors.background.ignoresSafeArea()
            
            VStack(spacing: 24) {
                Spacer()
                
                // Icon
                ZStack {
                    Circle()
                        .fill(MivoColors.blue.opacity(0.12))
                        .frame(width: 100, height: 100)
                    
                    Image(systemName: "clock.badge.checkmark")
                        .font(.system(size: 42))
                        .foregroundColor(MivoColors.blue)
                }
                
                // Title
                VStack(spacing: 8) {
                    Text("Enable Screen Time Tracking")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundColor(MivoColors.textPrimary)
                        .multilineTextAlignment(.center)
                    
                    Text("Get accurate screen time data directly from iOS. This helps Mivo provide better insights.")
                        .font(.system(size: 15))
                        .foregroundColor(MivoColors.textSecondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                        .padding(.horizontal, 20)
                }
                
                // Features
                VStack(alignment: .leading, spacing: 14) {
                    featureRow(icon: "lock.shield.fill", text: "Your data stays private on your device")
                    featureRow(icon: "chart.bar.fill", text: "Real-time updates throughout the day")
                    featureRow(icon: "app.badge.fill", text: "Per-app usage breakdown")
                }
                .padding(.horizontal, 32)
                
                Spacer()
                
                // Error message
                if let error = error {
                    Text(error)
                        .font(.system(size: 13))
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
                
                // Buttons
                VStack(spacing: 12) {
                    Button {
                        requestPermission()
                    } label: {
                        HStack(spacing: 8) {
                            if isRequesting {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            } else {
                                Text("Enable Screen Time")
                                    .font(.system(size: 17, weight: .semibold))
                                Image(systemName: "arrow.right")
                            }
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(MivoColors.blue)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .disabled(isRequesting)
                    
                    Button {
                        dismiss()
                    } label: {
                        Text("Maybe Later")
                            .font(.system(size: 15))
                            .foregroundColor(MivoColors.textSecondary)
                    }
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 20)
            }
        }
        .onAppear {
            collector.checkAuthorizationStatus()
        }
    }
    
    private func featureRow(icon: String, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundColor(MivoColors.blue)
                .frame(width: 24)
            
            Text(text)
                .font(.system(size: 14))
                .foregroundColor(MivoColors.textSecondary)
            
            Spacer()
        }
    }
    
    private func requestPermission() {
        isRequesting = true
        error = nil
        
        Task {
            do {
                try await collector.requestAuthorization()
                await MainActor.run {
                    isRequesting = false
                    if collector.authorizationStatus == .authorized {
                        dismiss()
                    } else {
                        error = "Permission was denied. You can enable it later in Settings."
                    }
                }
            } catch {
                await MainActor.run {
                    isRequesting = false
                    self.error = error.localizedDescription
                }
            }
        }
    }
}
