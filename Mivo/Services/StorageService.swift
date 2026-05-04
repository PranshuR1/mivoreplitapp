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
    case timeTruthNotificationSchedule = "mivo_time_truth_notification_schedule"
    // AI dataset storage - aggregated inputs for the AI engine
    case aiDataset = "mivo_ai_dataset"
}

struct StorageService {
    static func save<T: Encodable>(_ value: T, forKey key: StorageKey) {
        if let data = try? JSONEncoder().encode(value) {
            UserDefaults.standard.set(data, forKey: key.rawValue)
        }
    }

    static func load<T: Decodable>(_ type: T.Type, forKey key: StorageKey) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key.rawValue) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    static func remove(forKey key: StorageKey) {
        UserDefaults.standard.removeObject(forKey: key.rawValue)
    }

    static func exists(forKey key: StorageKey) -> Bool {
        UserDefaults.standard.object(forKey: key.rawValue) != nil
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
