import Foundation

enum StorageKey: String {
    case user = "mivo_user"
    case sessions = "mivo_sessions"
    case truthChecks = "mivo_truth_checks"
    case recallCheckIns = "mivo_recall_checkins"
    case instagramWrapperSessions = "mivo_instagram_wrapper_sessions"
    case instagramRecallPrompts = "mivo_instagram_recall_prompts"
    case dailyScreenTimeObservations = "mivo_daily_screen_time_observations"
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
    case goalForecastShown = "mivo_goal_forecast_shown"
    case weeklyReports = "mivo_weekly_reports"
    case appInterventionRules = "mivo_app_intervention_rules"
    case accountabilitySummary = "mivo_accountability_summary"
    case widgetSharedSummary = "mivo_widget_shared_summary"
    case weeklyExperiments = "mivo_weekly_experiments"
    case interventionAttempts = "mivo_intervention_attempts"
    case featureFlags = "mivo_feature_flags"
    case recoveryPlans = "mivo_recovery_plans"
    case appFrictionProfiles = "mivo_app_friction_profiles"
    case monthlyEffectReports = "mivo_monthly_effect_reports"
    case accountabilityConnections = "mivo_accountability_connections"
    case diagnosticsEnabled = "mivo_diagnostics_enabled"
    case mivoClearSessions = "mivo_clear_sessions"
    case mivoClearDisclosureSeen = "mivo_clear_disclosure_seen"
    case mivoClearTutorialVersion = "mivo_clear_tutorial_version"
    case dayKeyRepairVersion = "mivo_day_key_repair_version"
    case scrollGoalPromptShown = "mivo_scroll_goal_prompt_shown"
    case mivoStillSessions = "mivo_still_sessions"
    case mivoStillTutorialVersion = "mivo_still_tutorial_version"
    case mivoClearAgeConfirmed = "mivo_clear_age_confirmed"
    case timeLoans = "mivo_time_loans"
    case intentGameResults = "mivo_intent_game_results"
    case dropPathTimeAdjustments = "mivo_drop_path_time_adjustments"
    case userSwap = "mivo_user_swap"
    case userSwapPromptShown = "mivo_user_swap_prompt_shown"
    case namePromptDismissed = "mivo_name_prompt_dismissed"
    case companionPreferences = "mivo_companion_preferences"
    case companionRuntime = "mivo_companion_runtime"
    case companionProgress = "mivo_companion_progress"
    case comebackAnchor = "mivo_comeback_anchor"
    case comebackLapse = "mivo_comeback_lapse"
    case lastActiveDay = "mivo_last_active_day"
    case mivoSpots = "mivo_spots"
    case mivoSpotSessions = "mivo_spot_sessions"
    case mivoSpotActiveSession = "mivo_spot_active_session"
    case mivoLockIn = "mivo_lock_in"
    case mivoLockInHistory = "mivo_lock_in_history"
    case mivoLockInKeyholder = "mivo_lock_in_keyholder"
    case mivoLockInLastApps = "mivo_lock_in_last_apps"
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

    static func removeAllMivoData() {
        for key in UserDefaults.standard.dictionaryRepresentation().keys
        where key.hasPrefix("mivo_") || key.hasPrefix("mivo.") {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    static func removeUserScopedMivoData(email: String) {
        let suffix = "_user_\(simpleHash(email.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)))"
        for key in UserDefaults.standard.dictionaryRepresentation().keys where key.hasSuffix(suffix) {
            UserDefaults.standard.removeObject(forKey: key)
        }
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
