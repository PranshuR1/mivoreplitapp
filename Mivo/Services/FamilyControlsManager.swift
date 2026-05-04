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

@available(iOS 15.0, *)
@MainActor
final class FamilyControlsManager: ObservableObject {
    static let shared = FamilyControlsManager()

    // App group used to share data with the Device Activity extension — keep in sync with extension
    // Updated app group identifier (ensure this group is registered in Apple Developer portal)
    let appGroup = "group.com.mivo.mivoapp"
    private let selectedAppsKey = "mivo.selectedApps"
    private let familyActivitySelectionKey = "mivo.familyActivitySelection"
    private let impulseProtectionEnabledKey = "mivo.impulseProtectionEnabled"
    private let impulseProtectionSignedInKey = "mivo.impulseProtectionSignedIn"
    private let mivoSessionActiveKey = "mivo.sessionActive"
    private let mivoSessionEndsAtKey = "mivo.sessionEndsAt"
    private let pendingInterventionSetupKey = "mivo.pendingInterventionSetup"
    private let lastReportKey = "mivo.lastDeviceActivityReport"
    private let authFlagKey = "mivo.familyControlsAuthorized"
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
            setMivoSessionActive(false)
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

    func setMivoSessionActive(_ active: Bool, plannedMinutes: Int = 0, exactDurationSeconds: Int? = nil) {
        sessionRelockWorkItem?.cancel()
        sessionRelockWorkItem = nil

        userDefaults?.set(active, forKey: mivoSessionActiveKey)
        if active {
            let graceSeconds = exactDurationSeconds ?? max(15 * 60, plannedMinutes * 60 + 10 * 60)
            userDefaults?.set(Date().addingTimeInterval(TimeInterval(graceSeconds)).timeIntervalSince1970, forKey: mivoSessionEndsAtKey)
            scheduleSessionRelock(after: TimeInterval(graceSeconds))
        } else {
            userDefaults?.removeObject(forKey: mivoSessionEndsAtKey)
        }
        userDefaults?.synchronize()

        if #available(iOS 16.0, *) {
            applyImpulseProtectionIfNeeded()
        }
    }

    private func scheduleSessionRelock(after delay: TimeInterval) {
        let workItem = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.userDefaults?.set(false, forKey: self.mivoSessionActiveKey)
                self.userDefaults?.removeObject(forKey: self.mivoSessionEndsAtKey)
                self.userDefaults?.synchronize()
                if #available(iOS 16.0, *) {
                    self.applyImpulseProtectionIfNeeded()
                }
            }
        }
        sessionRelockWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    func isMivoSessionActive() -> Bool {
        guard userDefaults?.bool(forKey: mivoSessionActiveKey) == true else { return false }
        let endsAt = userDefaults?.double(forKey: mivoSessionEndsAtKey) ?? 0
        if endsAt > 0 && endsAt < Date().timeIntervalSince1970 {
            userDefaults?.set(false, forKey: mivoSessionActiveKey)
            userDefaults?.removeObject(forKey: mivoSessionEndsAtKey)
            userDefaults?.synchronize()
            return false
        }
        return true
    }

    func requestInterventionSetupFromShield() {
        userDefaults?.set(true, forKey: pendingInterventionSetupKey)
        userDefaults?.synchronize()
    }

    func consumePendingInterventionSetup() -> Bool {
        guard userDefaults?.bool(forKey: pendingInterventionSetupKey) == true else { return false }
        userDefaults?.set(false, forKey: pendingInterventionSetupKey)
        userDefaults?.synchronize()
        return true
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

        guard !isMivoSessionActive() else {
            clearImpulseProtection()
            return
        }

        let selection = loadFamilyActivitySelection()
        let store = ManagedSettingsStore()
        store.shield.applications = selection.applicationTokens.isEmpty ? nil : selection.applicationTokens
        store.shield.applicationCategories = selection.categoryTokens.isEmpty ? nil : .specific(selection.categoryTokens)
        store.shield.webDomains = selection.webDomainTokens.isEmpty ? nil : selection.webDomainTokens
    }

    @available(iOS 16.0, *)
    func clearImpulseProtection() {
        let store = ManagedSettingsStore()
        store.shield.applications = nil
        store.shield.applicationCategories = nil
        store.shield.webDomains = nil
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
}

// Notification name when the extension writes new data into the app group
extension Notification.Name {
    static let mivoDeviceActivityDidUpdate = Notification.Name("mivoDeviceActivityDidUpdate")
    static let mivoSessionHistoryDidUpdate = Notification.Name("mivoSessionHistoryDidUpdate")
}
