import Foundation

enum StorageKey: String {
    case user = "mivo_user"
    case sessions = "mivo_sessions"
    case truthChecks = "mivo_truth_checks"
    case settings = "mivo_settings"
    case credentials = "mivo_credentials"
    case authSession = "mivo_auth_session"
    case rememberedEmail = "mivo_remembered_email"
    case onboardingProfile = "mivo_onboarding_profile"
    case pendingSessionFeedback = "mivo_pending_session_feedback"
    case runningSession = "mivo_running_session"
    case timeTruthNotificationSchedule = "mivo_time_truth_notification_schedule"
    case dailyScrollSchedules = "mivo_daily_scroll_schedules"
    case dailyScrollScheduleNotification = "mivo_daily_scroll_schedule_notification"
    case weeklyReports = "mivo_weekly_reports"
    case appInterventionRules = "mivo_app_intervention_rules"
    case accountabilitySummary = "mivo_accountability_summary"
    case widgetSharedSummary = "mivo_widget_shared_summary"
    // AI dataset storage - aggregated inputs for the AI engine
    case aiDataset = "mivo_ai_dataset"
}

struct StorageService {
    static func scopedRawKey(for key: StorageKey, email: String) -> String {
        let normalized = email.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(key.rawValue)_user_\(simpleHash(normalized))"
    }

    static func save<T: Encodable>(_ value: T, forKey key: StorageKey) {
        if let data = try? JSONEncoder().encode(value) {
            UserDefaults.standard.set(data, forKey: key.rawValue)
        }
    }

    static func save<T: Encodable>(_ value: T, forKey key: StorageKey, email: String) {
        if let data = try? JSONEncoder().encode(value) {
            UserDefaults.standard.set(data, forKey: scopedRawKey(for: key, email: email))
        }
    }

    static func load<T: Decodable>(_ type: T.Type, forKey key: StorageKey) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key.rawValue) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    static func load<T: Decodable>(_ type: T.Type, forKey key: StorageKey, email: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: scopedRawKey(for: key, email: email)) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    static func remove(forKey key: StorageKey) {
        UserDefaults.standard.removeObject(forKey: key.rawValue)
    }

    static func remove(forKey key: StorageKey, email: String) {
        UserDefaults.standard.removeObject(forKey: scopedRawKey(for: key, email: email))
    }

    static func exists(forKey key: StorageKey) -> Bool {
        UserDefaults.standard.object(forKey: key.rawValue) != nil
    }

    static func exists(forKey key: StorageKey, email: String) -> Bool {
        UserDefaults.standard.object(forKey: scopedRawKey(for: key, email: email)) != nil
    }

    static var activeUserEmail: String? {
        guard exists(forKey: .authSession) else { return nil }
        return load(String.self, forKey: .rememberedEmail)
    }
}

// Simple hash for local auth (matches Expo implementation)
func simpleHash(_ str: String) -> String {
    var hash: Int32 = 0
    for char in str.unicodeScalars {
        let chr = Int32(bitPattern: char.value)
        hash = (hash &<< 5) &- hash &+ chr
    }
    return String(format: "%x", hash)
}
