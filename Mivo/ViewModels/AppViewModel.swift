import Foundation
import SwiftUI
@preconcurrency import UserNotifications
#if canImport(WidgetKit)
import WidgetKit
#endif

@MainActor
class AppViewModel: ObservableObject {
    @Published var user: UserProfile? = nil
    @Published var sessions: [Session] = []
    @Published var truthChecks: [TruthCheckGuess] = []
    @Published var dailyScrollSchedules: [DailyScrollSchedule] = []
    @Published var weeklyReports: [WeeklyReportSnapshot] = []
    @Published var appInterventionRules: [AppInterventionRule] = []
    @Published var settings: AppSettings = AppSettings(onboardingComplete: false, notificationsEnabled: false)
    @Published var onboardingProfile: OnboardingProfile = OnboardingProfile()
    @Published var isLoading: Bool = true
    @Published var adminToken: String? = nil
    private let builtInAdminEmail = "useparkez@gmail.com"
    private let builtInTestingEmail = "pranshuraithatha@gmail.com"
    private let builtInTestingPassword = "Pranshu@123"

    // Navigation state
    @Published var showOnboarding: Bool = false
    @Published var isLoggedIn: Bool = false

    // Last Device Activity report JSON (from extension via app group)
    @Published var lastDeviceActivityReportJSON: String? = nil
    @Published var deviceActivityMinutesToday: Int? = nil
    @Published var deviceActivityPerAppSeconds: [String: Int] = [:]
    @Published var deviceActivityReportGeneratedAt: Date? = nil
    @Published var mivoLaunchGateActive: Bool = false
    @Published var pendingSessionFeedback: PendingSessionFeedback? = nil
    @Published var pendingExpiredRunningSession: RunningMivoSession? = nil
    @Published var pendingResumedActiveSession: RunningMivoSession? = nil
    @Published var pendingTimeTruthPrompt: TimeTruthPrompt? = nil
    @Published var pendingDailyScrollSchedulePrompt: DailyScrollSchedulePrompt? = nil
    /// One-time post-observation prompt that tells the user how many days until
    /// their personalized plan reaches the goal they set in onboarding.
    @Published var pendingGoalForecastPrompt: GoalForecastPrompt? = nil
    @Published var sessionActivationError: String? = nil
    /// Set to true when the shield "Open Mivo" button triggers a deep link
    @Published var deepLinkInterventionRequested: Bool = false

    init() {
        loadData()
        // Begin observing device activity updates from the Device Activity extension or Screen Time API
        startObservingDeviceActivityUpdates()
        
        // Start Screen Time monitoring if authorized (iOS 16+)
        if #available(iOS 16.0, *) {
            let collector = ScreenTimeDataCollector.shared
            if collector.authorizationStatus == .authorized {
                collector.startMonitoring()
            }
        }
    }

    func loadData() {
        if StorageService.exists(forKey: .authSession),
           let authRecord = SecureAuthService.loadRecord() {
            user = UserProfile(
                email: authRecord.email,
                name: authRecord.name,
                createdAt: authRecord.createdAt,
                onboardingProfile: authRecord.onboardingProfile,
                isAdmin: authRecord.isAdmin
            )
            adminToken = authRecord.adminToken
            isLoggedIn = true
            loadUserScopedData(for: authRecord.email)
            syncLearningModeProtectionState()
            applyRestrictionState(for: authRecord.email)
        } else {
            adminToken = nil
            resetUserScopedState()
            FamilyControlsManager.shared.setLearningModeUnlocked(false)
            FamilyControlsManager.shared.setSignedInForImpulseProtection(false)
        }
        recoverExpiredRunningSessionIfNeeded()
        isLoading = false
    }

    private func resetUserScopedState() {
        sessions = []
        truthChecks = []
        dailyScrollSchedules = []
        weeklyReports = []
        appInterventionRules = defaultAppInterventionRules()
        settings = AppSettings(onboardingComplete: false, notificationsEnabled: false)
        onboardingProfile = OnboardingProfile()
        pendingSessionFeedback = nil
        pendingExpiredRunningSession = nil
        pendingTimeTruthPrompt = nil
        pendingDailyScrollSchedulePrompt = nil
        FamilyControlsManager.shared.setCheckInIntervalMinutes(3)
    }

    private func loadUserScopedData(for email: String) {
        sessions = StorageService.load([Session].self, forKey: .sessions, email: email) ?? []
        truthChecks = StorageService.load([TruthCheckGuess].self, forKey: .truthChecks, email: email) ?? []
        dailyScrollSchedules = StorageService.load([DailyScrollSchedule].self, forKey: .dailyScrollSchedules, email: email) ?? []
        weeklyReports = StorageService.load([WeeklyReportSnapshot].self, forKey: .weeklyReports, email: email) ?? []
        if let rules = StorageService.load([AppInterventionRule].self, forKey: .appInterventionRules, email: email) {
            appInterventionRules = rules
        } else {
            appInterventionRules = defaultAppInterventionRules()
            StorageService.save(appInterventionRules, forKey: .appInterventionRules, email: email)
        }
        settings = StorageService.load(AppSettings.self, forKey: .settings, email: email)
            ?? AppSettings(onboardingComplete: false, notificationsEnabled: false)
        if let savedProfile = StorageService.load(OnboardingProfile.self, forKey: .onboardingProfile, email: email) {
            onboardingProfile = savedProfile
        } else if let record = SecureAuthService.loadRecord(), record.email == email, let userProfile = record.onboardingProfile {
            onboardingProfile = userProfile
            StorageService.save(userProfile, forKey: .onboardingProfile, email: email)
        } else {
            onboardingProfile = OnboardingProfile()
        }
        let checkInMinutes = settings.checkInIntervalMinutes ?? onboardingProfile.checkInIntervalMinutes ?? 3
        settings.checkInIntervalMinutes = checkInMinutes
        FamilyControlsManager.shared.setCheckInIntervalMinutes(checkInMinutes)

        pendingSessionFeedback = StorageService.load(PendingSessionFeedback.self, forKey: .pendingSessionFeedback, email: email)
        pendingExpiredRunningSession = nil
    }

    private func saveForCurrentUser<T: Encodable>(_ value: T, forKey key: StorageKey) {
        guard let email = user?.email else { return }
        StorageService.save(value, forKey: key, email: email)
    }

    private func removeForCurrentUser(_ key: StorageKey) {
        guard let email = user?.email else { return }
        StorageService.remove(forKey: key, email: email)
    }

    // MARK: - Auth

    func login(email: String, password: String, rememberMe: Bool = true) async throws {
        let normalizedEmail = email.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        if isBuiltInTestingEmail(normalizedEmail) {
            guard isBuiltInTestingCredentials(email: normalizedEmail, password: password) else {
                throw AppError.invalidCredentials
            }
            try createOrUpdateLocalTestingRecord(email: normalizedEmail, password: password)
            try completeLogin(email: normalizedEmail, persistSession: rememberMe)
            return
        }

        if RemoteAuthService.isConfigured {
            do {
                let remoteUser = try await RemoteAuthService.login(email: normalizedEmail, password: password)
                try cacheRemoteUser(remoteUser, password: password)
                try completeLogin(email: remoteUser.email, persistSession: rememberMe)
                return
            } catch AppError.remoteAuthUnavailable {
                try completeOfflineLogin(email: normalizedEmail, password: password, rememberMe: rememberMe)
                return
            }
        } else if isBuiltInAdminCredentials(email: normalizedEmail, password: password) {
            try createOrUpdateLocalAdminRecord(email: normalizedEmail, password: password)
            try completeLogin(email: normalizedEmail, persistSession: rememberMe)
            return
        }

        try completeLocalLogin(email: normalizedEmail, password: password, rememberMe: rememberMe)
    }

    private func completeOfflineLogin(email: String, password: String, rememberMe: Bool) throws {
        if isBuiltInAdminCredentials(email: email, password: password) {
            try createOrUpdateLocalAdminRecord(email: email, password: password)
            try completeLogin(email: email, persistSession: rememberMe)
            return
        }

        if isBuiltInTestingCredentials(email: email, password: password) {
            try createOrUpdateLocalTestingRecord(email: email, password: password)
            try completeLogin(email: email, persistSession: rememberMe)
            return
        }

        try completeLocalLogin(email: email, password: password, rememberMe: rememberMe)
    }

    private func completeLocalLogin(email: String, password: String, rememberMe: Bool) throws {
        guard var record = SecureAuthService.loadRecord(email: email) else {
            throw AppError.noAccount
        }
        guard SecureAuthService.verifyPassword(password, for: record) else {
            throw AppError.invalidCredentials
        }

        if record.passwordIterations == 0 {
            record = try SecureAuthService.updatePassword(password, for: record)
        }

        try completeLogin(email: email, persistSession: rememberMe)
    }

    func completeLogin(email: String, persistSession: Bool = true) throws {
        guard let record = SecureAuthService.loadRecord(email: email) else {
            throw AppError.accountDataMissing
        }
        if persistSession {
            StorageService.save("1", forKey: .authSession)
            StorageService.save(email, forKey: .rememberedEmail)
        } else {
            StorageService.remove(forKey: .authSession)
            StorageService.remove(forKey: .rememberedEmail)
        }
        user = UserProfile(
            email: record.email,
            name: record.name,
            createdAt: record.createdAt,
            onboardingProfile: record.onboardingProfile,
            isAdmin: record.isAdmin
        )
        adminToken = record.adminToken
        isLoggedIn = true
        loadUserScopedData(for: record.email)
        syncLearningModeProtectionState()
        applyRestrictionState(for: record.email)

        // Restore any saved onboarding profile for this user
        if let userOnboard = record.onboardingProfile,
           !StorageService.exists(forKey: .onboardingProfile, email: record.email) {
            onboardingProfile = userOnboard
            StorageService.save(userOnboard, forKey: .onboardingProfile, email: record.email)
        }
    }

    func registerDirectly(email: String, password: String, name: String) async throws {
        let normalizedEmail = email.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let displayName = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? String(normalizedEmail.split(separator: "@").first ?? Substring(normalizedEmail))
            : name.trimmingCharacters(in: .whitespacesAndNewlines)

        if isBuiltInTestingEmail(normalizedEmail) {
            guard isBuiltInTestingCredentials(email: normalizedEmail, password: password) else {
                throw AppError.invalidCredentials
            }
            try createOrUpdateLocalTestingRecord(email: normalizedEmail, password: password)
            try completeLogin(email: normalizedEmail)
            settings.onboardingComplete = true
            settings.tutorialComplete = true
            saveForCurrentUser(settings, forKey: .settings)
            return
        }

        if RemoteAuthService.isConfigured {
            do {
                let remoteUser = try await RemoteAuthService.register(
                    email: normalizedEmail,
                    password: password,
                    name: displayName,
                    onboardingProfile: nil
                )
                try cacheRemoteUser(remoteUser, password: password)
            } catch AppError.emailAlreadyExists {
                throw AppError.emailAlreadyExists
            } catch {
                try registerLocallyDirectly(email: email, password: password, displayName: displayName)
            }
        } else {
            try registerLocallyDirectly(email: email, password: password, displayName: displayName)
        }

        settings.onboardingComplete = false
        let updated = settings
        settings = updated
        onboardingProfile = OnboardingProfile()
        try completeLogin(email: normalizedEmail)
        saveForCurrentUser(settings, forKey: .settings)
        saveForCurrentUser(onboardingProfile, forKey: .onboardingProfile)
    }

    private func registerLocallyDirectly(email: String, password: String, displayName: String) throws {
        let normalizedEmail = email.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if SecureAuthService.loadRecord(email: normalizedEmail) != nil {
            throw AppError.emailAlreadyExists
        }
        let record = try SecureAuthService.createRecord(email: normalizedEmail, password: password, name: displayName)
        let profile = UserProfile(email: record.email, name: record.name, createdAt: record.createdAt)
        StorageService.save(profile, forKey: .user)
    }

    func logout() {
        // Offload storage mutation to background to avoid blocking the UI
        DispatchQueue.global(qos: .userInitiated).async {
            StorageService.remove(forKey: .authSession)
            StorageService.remove(forKey: .rememberedEmail)
            // Update published state on main actor
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                FamilyControlsManager.shared.setLearningModeUnlocked(false)
                FamilyControlsManager.shared.setSignedInForImpulseProtection(false)
                self.user = nil
                self.adminToken = nil
                self.isLoggedIn = false
                self.resetUserScopedState()
            }
        }
    }

    // MARK: - Sessions

    func addSession(_ session: Session) {
        sessions.append(session)
        saveForCurrentUser(sessions, forKey: .sessions)
        syncLearningModeProtectionState()
        refreshWeeklyReportSnapshot()
        updateWidgetSharedSummary()
        scheduleTimeTruthNotification()
        scheduleWeeklyReportNotification()
        NotificationCenter.default.post(name: .mivoSessionHistoryDidUpdate, object: nil)
    }

    func savePendingSessionFeedback(_ feedback: PendingSessionFeedback) {
        pendingSessionFeedback = feedback
        saveForCurrentUser(feedback, forKey: .pendingSessionFeedback)
    }

    func clearPendingSessionFeedback() {
        pendingSessionFeedback = nil
        pendingExpiredRunningSession = nil
        removeForCurrentUser(.pendingSessionFeedback)
        clearRunningSession()
    }

    func saveRunningSession(_ session: RunningMivoSession) {
        guard !isRestrictionBypassUser else { return }
        saveForCurrentUser(session, forKey: .runningSession)
    }

    func clearRunningSession() {
        removeForCurrentUser(.runningSession)
    }

    func recoverExpiredRunningSessionIfNeeded(now: Date = Date()) {
        guard isLoggedIn, settings.onboardingComplete, !isRestrictionBypassUser else { return }
        guard let email = user?.email,
              let running = StorageService.load(RunningMivoSession.self, forKey: .runningSession, email: email) else { return }

        guard let startedAt = ISO8601DateFormatter().date(from: running.startTime) else {
            clearRunningSession()
            return
        }

        let formatter = ISO8601DateFormatter()
        let expiresAt = formatter.date(from: running.expiresAt)
            ?? startedAt.addingTimeInterval(TimeInterval(running.approvedSeconds))

        if running.state == .active, expiresAt > now {
            let remainingSeconds = max(1, Int(expiresAt.timeIntervalSince(now).rounded(.up)))
            let success = FamilyControlsManager.shared.setMivoSessionActive(true, exactDurationSeconds: remainingSeconds)
            if !success {
                print("[AppViewModel] ⚠️ Session recovery failed: Device Activity blocker not confirmed")
            }
            return
        }

        FamilyControlsManager.shared.endSessionAndRelockForIntervention()
        let expired = expiredChoiceSession(from: running, now: now)
        saveRunningSession(expired)
        pendingExpiredRunningSession = expired
    }

    private func expiredChoiceSession(from running: RunningMivoSession, now: Date = Date()) -> RunningMivoSession {
        let formatter = ISO8601DateFormatter()
        let expiredAt = running.expiredAt ?? running.expiresAt
        let elapsedSeconds = cappedElapsedSeconds(for: running, now: now)

        return RunningMivoSession(
            id: running.id,
            intention: running.intention,
            plannedDuration: running.plannedDuration,
            plannedSeconds: running.plannedSeconds,
            approvedSeconds: running.approvedSeconds,
            startTime: running.startTime,
            expiresAt: running.expiresAt,
            expiredAt: expiredAt.isEmpty ? formatter.string(from: now) : expiredAt,
            expirationSource: running.expirationSource ?? MivoSessionExpirationSource.sessionEnd.rawValue,
            state: .expiredAwaitingChoice,
            accumulatedElapsedSeconds: elapsedSeconds,
            urgeReason: running.urgeReason,
            urgeNote: running.urgeNote,
            extendedOnce: running.extendedOnce,
            emergencyUnlockUsed: running.emergencyUnlockUsed,
            emergencyUnlockReason: running.emergencyUnlockReason
        )
    }

    func cappedElapsedSeconds(for running: RunningMivoSession, now: Date = Date()) -> Int {
        let formatter = ISO8601DateFormatter()
        let approved = max(1, running.approvedSeconds)
        var candidate = running.accumulatedElapsedSeconds

        if let start = formatter.date(from: running.startTime) {
            if let expiredAt = running.expiredAt.flatMap({ formatter.date(from: $0) }) {
                candidate = max(candidate, Int(expiredAt.timeIntervalSince(start)))
            } else if let expiresAt = formatter.date(from: running.expiresAt), expiresAt <= now {
                candidate = max(candidate, Int(expiresAt.timeIntervalSince(start)))
            } else {
                candidate = max(candidate, Int(now.timeIntervalSince(start)))
            }
        }

        return max(1, min(candidate, approved))
    }

    func cappedElapsedMinutes(for running: RunningMivoSession, now: Date = Date()) -> Int {
        max(1, Int((Double(cappedElapsedSeconds(for: running, now: now)) / 60.0).rounded()))
    }

    func extendExpiredRunningSession(_ running: RunningMivoSession, addedMinutes: Int, emergencyReason: String? = nil) -> Bool {
        let addedSeconds = max(1, addedMinutes) * 60
        let now = Date()
        let formatter = ISO8601DateFormatter()
        let elapsedSeconds = cappedElapsedSeconds(for: running, now: now)
        let updated = RunningMivoSession(
            id: running.id,
            intention: running.intention,
            plannedDuration: running.plannedDuration + addedMinutes,
            plannedSeconds: running.plannedSeconds + addedSeconds,
            approvedSeconds: running.approvedSeconds + addedSeconds,
            startTime: running.startTime,
            expiresAt: formatter.string(from: now.addingTimeInterval(TimeInterval(addedSeconds))),
            expiredAt: nil,
            expirationSource: nil,
            state: .active,
            accumulatedElapsedSeconds: elapsedSeconds,
            urgeReason: running.urgeReason,
            urgeNote: running.urgeNote,
            extendedOnce: true,
            emergencyUnlockUsed: (running.emergencyUnlockUsed == true) || emergencyReason != nil,
            emergencyUnlockReason: emergencyReason ?? running.emergencyUnlockReason
        )

        let success = FamilyControlsManager.shared.setMivoSessionActive(true, exactDurationSeconds: addedSeconds)
        guard success else {
            sessionActivationError = "Failed to add time: Device Activity blocker could not be scheduled. Protected apps will remain locked."
            return false
        }

        sessionActivationError = nil
        pendingExpiredRunningSession = nil
        pendingSessionFeedback = nil
        pendingResumedActiveSession = updated
        saveRunningSession(updated)
        return true
    }

    func clearExpiredRunningSessionReview() {
        pendingExpiredRunningSession = nil
        pendingSessionFeedback = nil
        removeForCurrentUser(.pendingSessionFeedback)
        clearRunningSession()
    }

    var isAdminUser: Bool {
        user?.isAdmin == true || user?.email.lowercased() == builtInAdminEmail
    }

    var isRestrictionBypassUser: Bool {
        guard let email = user?.email.lowercased() else { return false }
        return isBuiltInTestingEmail(email)
    }

    func loadAdminUsers() async throws -> [AdminUser] {
        guard let adminToken, !adminToken.isEmpty else {
            throw AppError.remoteAuthUnavailable
        }
        return try await RemoteAuthService.adminUsers(adminToken: adminToken)
    }

    func deleteAdminUser(email: String) async throws {
        guard let adminToken, !adminToken.isEmpty else {
            throw AppError.remoteAuthUnavailable
        }
        try await RemoteAuthService.adminDeleteUser(adminToken: adminToken, email: email)
    }

    func addTruthCheck(guess: Int) {
        let today = todayKey()
        let actual = timeTruthActualMinutesForToday()
        let check = TruthCheckGuess(
            id: UUID().uuidString,
            date: today,
            guess: guess,
            actual: actual
        )
        truthChecks.append(check)
        saveForCurrentUser(truthChecks, forKey: .truthChecks)
        syncLearningModeProtectionState()
        scheduleTimeTruthNotification()
    }

    func recordTimeTruthGuess(_ guess: Int, for prompt: TimeTruthPrompt) {
        guard !truthChecks.contains(where: { $0.date == prompt.date }) else { return }
        let check = TruthCheckGuess(
            id: UUID().uuidString,
            date: prompt.date,
            guess: guess,
            actual: prompt.actualMinutes
        )
        truthChecks.append(check)
        saveForCurrentUser(truthChecks, forKey: .truthChecks)
        syncLearningModeProtectionState()
        scheduleTimeTruthNotification()
    }

    func saveDailyScrollScheduleForToday(_ windows: [ScreenScrollWindow]) {
        saveDailyScrollSchedule(windows, for: todayKey())
    }

    func saveDailyScrollSchedule(_ windows: [ScreenScrollWindow], for date: String) {
        guard !windows.isEmpty else { return }
        if dailyScrollSchedule(for: date) != nil { return }

        let normalized = normalizeDailyScrollWindows(windows)
        let schedule = DailyScrollSchedule(
            id: date,
            date: date,
            windows: normalized,
            createdAt: ISO8601DateFormatter().string(from: Date())
        )
        dailyScrollSchedules.removeAll { $0.date == date }
        dailyScrollSchedules.insert(schedule, at: 0)
        dailyScrollSchedules = Array(dailyScrollSchedules.prefix(45))
        saveForCurrentUser(dailyScrollSchedules, forKey: .dailyScrollSchedules)
        persistPreferredScrollWindows(normalized)
        pendingDailyScrollSchedulePrompt = nil
        appendAISummary("Daily scroll schedule locked for \(date): \(normalized.map { "\($0.title) \($0.startHour)-\($0.endHour)" }.joined(separator: ", "))")
    }

    func dailyScrollSchedule(for date: String? = nil) -> DailyScrollSchedule? {
        let key = date ?? todayKey()
        return dailyScrollSchedules.first { $0.date == key }
    }

    var isTodayScrollScheduleLocked: Bool {
        dailyScrollSchedule() != nil
    }

    var todayScrollScheduleStatusText: String {
        if let schedule = dailyScrollSchedule() {
            let times = schedule.windows.map { "\(hourLabel($0.startHour))-\(hourLabel($0.endHour))" }.joined(separator: " and ")
            return "Locked today: \(times). You can choose again tomorrow morning."
        }
        return "Choose today’s two scroll windows. Once saved, they lock until tomorrow."
    }

    func dismissTimeTruthPrompt() {
        pendingTimeTruthPrompt = nil
    }

    func evaluateDailyScrollSchedulePrompt(now: Date = Date()) {
        guard isLoggedIn, settings.onboardingComplete else {
            pendingDailyScrollSchedulePrompt = nil
            return
        }

        let today = todayKey()
        guard dailyScrollSchedule(for: today) == nil else {
            if pendingDailyScrollSchedulePrompt?.date == today {
                pendingDailyScrollSchedulePrompt = nil
            }
            return
        }

        let schedule = dailyScrollSchedulePromptTime()
        let calendar = Calendar.current
        let isBrandNewSchedule = dailyScrollSchedules.isEmpty
        let dueAt = calendar.date(
            bySettingHour: schedule.hour,
            minute: schedule.minute,
            second: 0,
            of: now
        ) ?? now
        guard isBrandNewSchedule || now >= dueAt else { return }

        if pendingDailyScrollSchedulePrompt?.date != today {
            let recommendationReady = !rawAdaptiveScreenTimePlan().collecting
            pendingDailyScrollSchedulePrompt = DailyScrollSchedulePrompt(
                id: today,
                date: today,
                recommendedWindows: suggestedDailyScrollWindows(recommendationReady: recommendationReady),
                isRecommendationReady: recommendationReady,
                scheduledHour: schedule.hour,
                scheduledMinute: schedule.minute
            )
        }
    }

    func scheduleDailyScrollScheduleNotification() {
        guard isLoggedIn, settings.onboardingComplete else { return }

        let schedule = dailyScrollSchedulePromptTime()
        let scheduleKey = String(format: "%02d:%02d", schedule.hour, schedule.minute)
        if let email = user?.email,
           StorageService.load(String.self, forKey: .dailyScrollScheduleNotification, email: email) == scheduleKey {
            return
        }

        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["mivo.scrollSchedule.daily"])
        center.requestAuthorization(options: [.alert, .badge, .sound]) { [weak self] granted, _ in
            guard granted else { return }

            let content = UNMutableNotificationContent()
            content.title = "Set today’s scroll times"
            content.body = "Choose your two scroll windows for today. Once saved, they lock until tomorrow."
            content.sound = .default

            var date = DateComponents()
            date.hour = schedule.hour
            date.minute = schedule.minute
            let trigger = UNCalendarNotificationTrigger(dateMatching: date, repeats: true)
            let request = UNNotificationRequest(identifier: "mivo.scrollSchedule.daily", content: content, trigger: trigger)

            center.add(request) { error in
                guard error == nil else { return }
                DispatchQueue.main.async {
                    self?.saveForCurrentUser(scheduleKey, forKey: .dailyScrollScheduleNotification)
                    self?.settings.notificationsEnabled = true
                    if let updated = self?.settings {
                        self?.saveForCurrentUser(updated, forKey: .settings)
                    }
                }
            }
        }
    }

    func evaluateTimeTruthPrompt(now: Date = Date()) {
        guard isLoggedIn, settings.onboardingComplete else {
            pendingTimeTruthPrompt = nil
            return
        }

        let today = todayKey()
        guard !truthChecks.contains(where: { $0.date == today }) else {
            if pendingTimeTruthPrompt?.date == today {
                pendingTimeTruthPrompt = nil
            }
            return
        }

        let schedule = timeTruthSchedule()
        let calendar = Calendar.current
        guard let dueAt = calendar.date(
            bySettingHour: schedule.hour,
            minute: schedule.minute,
            second: 0,
            of: now
        ), now >= dueAt else { return }

        if pendingTimeTruthPrompt?.date != today {
            refreshScreenTimeData()
            pendingTimeTruthPrompt = TimeTruthPrompt(
                id: today,
                date: today,
                actualMinutes: timeTruthActualMinutesForToday(),
                scheduledHour: schedule.hour,
                scheduledMinute: schedule.minute
            )
        }
    }

    /// Show the one-time goal-forecast prompt the first time the user enters
    /// their personalized plan (i.e. right after observation completes).
    func evaluateGoalForecastPrompt() {
        guard isLoggedIn, settings.onboardingComplete else {
            pendingGoalForecastPrompt = nil
            return
        }
        guard pendingGoalForecastPrompt == nil else { return }
        // Don't re-show after the user has dismissed it once.
        if let email = user?.email,
           StorageService.load(Bool.self, forKey: .goalForecastShown, email: email) == true { return }

        let plan = rawAdaptiveScreenTimePlan()
        // Wait until the plan exits observation mode.
        guard !plan.collecting else { return }

        let observationAverage = plan.baselineMinutes
        let goal = max(15, onboardingProfile.dailyScrollGoalMinutes ?? 30)
        // Goal already reached on day 1: no forecast needed.
        guard observationAverage > goal else { return }

        let daysToReachGoal = AIService.daysUntilGoalReached(baseline: observationAverage, goal: goal)
        let firstDay = AIService.personalizedTargetMinutes(dayIndex: 1, baseline: observationAverage, floor: goal)
        let oneWeek = AIService.personalizedTargetMinutes(dayIndex: 8, baseline: observationAverage, floor: goal)
        let twoWeek = AIService.personalizedTargetMinutes(dayIndex: 15, baseline: observationAverage, floor: goal)
        pendingGoalForecastPrompt = GoalForecastPrompt(
            id: "goal-forecast-\(observationAverage)-\(goal)",
            observationAverageMinutes: observationAverage,
            goalMinutes: goal,
            daysToReachGoal: daysToReachGoal,
            firstPlanDayTarget: firstDay,
            oneWeekTarget: oneWeek,
            twoWeekTarget: twoWeek,
            createdAt: ISO8601DateFormatter().string(from: Date())
        )
    }

    func dismissGoalForecastPrompt() {
        pendingGoalForecastPrompt = nil
        saveForCurrentUser(true, forKey: .goalForecastShown)
    }

    func scheduleTimeTruthNotification() {
        guard isLoggedIn, settings.onboardingComplete else { return }

        let schedule = timeTruthSchedule()
        let scheduleKey = String(format: "%02d:%02d", schedule.hour, schedule.minute)
        if let email = user?.email,
           StorageService.load(String.self, forKey: .timeTruthNotificationSchedule, email: email) == scheduleKey {
            return
        }

        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["mivo.timeTruth.daily"])
        center.requestAuthorization(options: [.alert, .badge, .sound]) { [weak self] granted, _ in
            guard granted else { return }

            let content = UNMutableNotificationContent()
            content.title = "Time Truth"
            content.body = "How much did you scroll today? Make a guess, then reveal the real number."
            content.sound = .default
            content.categoryIdentifier = "MIVO_TIME_TRUTH"

            var date = DateComponents()
            date.hour = schedule.hour
            date.minute = schedule.minute
            let trigger = UNCalendarNotificationTrigger(dateMatching: date, repeats: true)
            let request = UNNotificationRequest(identifier: "mivo.timeTruth.daily", content: content, trigger: trigger)

            center.add(request) { error in
                guard error == nil else { return }
                DispatchQueue.main.async {
                    self?.saveForCurrentUser(scheduleKey, forKey: .timeTruthNotificationSchedule)
                    self?.settings.notificationsEnabled = true
                    if let updated = self?.settings {
                        self?.saveForCurrentUser(updated, forKey: .settings)
                    }
                }
            }
        }
    }

    func scheduleWeeklyReportNotification() {
        guard isLoggedIn, settings.onboardingComplete, settings.notificationsEnabled else { return }

        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["mivo.weeklyReport.sunday"])

        let content = UNMutableNotificationContent()
        content.title = "Your Mivo week is ready"
        content.body = "Review your scroll time, recovered time, hardest trigger, and next week’s plan."
        content.sound = .default

        var date = DateComponents()
        date.weekday = 1
        date.hour = 18
        date.minute = 0
        let trigger = UNCalendarNotificationTrigger(dateMatching: date, repeats: true)
        let request = UNNotificationRequest(identifier: "mivo.weeklyReport.sunday", content: content, trigger: trigger)
        center.add(request)
    }

    // MARK: - Onboarding

    func completeOnboarding() {
        // Set flag
        settings.onboardingComplete = true
        settings.tutorialComplete = false
        // Reassign to force @Published notifications in case of in-place mutation
        let updated = settings
        settings = updated
        saveForCurrentUser(settings, forKey: .settings)

        // No longer use deprecated UIApplication interaction APIs; if any global overlays were used,
        // they should be dismissed by the UI flow (we avoid calling deprecated APIs here).
    }

    func saveOnboardingProfile(_ partial: OnboardingProfile) {
        if let intention = partial.primaryIntention {
            onboardingProfile.primaryIntention = intention
        }
        // Merge multiple intentions if provided
        if !partial.intentions.isEmpty {
            // Keep unique and preserve previous selections
            let existing = onboardingProfile.intentions
            let combined = existing + partial.intentions
            onboardingProfile.intentions = Array(NSOrderedSet(array: combined)) as? [Intention] ?? Array(Set(combined))
            // Keep first intention as primary if not set
            if onboardingProfile.primaryIntention == nil {
                onboardingProfile.primaryIntention = onboardingProfile.intentions.first
            }
        }
        if let estimate = partial.scrollEstimateMinutes {
            onboardingProfile.scrollEstimateMinutes = estimate
        }
        if !partial.preferredApps.isEmpty || partial.preferredApps != onboardingProfile.preferredApps {
            onboardingProfile.preferredApps = partial.preferredApps
        }
        if let windows = partial.preferredScrollWindows, !windows.isEmpty {
            onboardingProfile.preferredScrollWindows = windows
        }
        if let a = partial.age { onboardingProfile.age = a }
        if let ar = partial.ageRange { onboardingProfile.ageRange = ar }
        if let interval = partial.checkInIntervalMinutes {
            onboardingProfile.checkInIntervalMinutes = interval
            FamilyControlsManager.shared.setCheckInIntervalMinutes(interval)
        }
        // Persist the onboarding profile separately
        saveForCurrentUser(onboardingProfile, forKey: .onboardingProfile)

        // If we have a logged-in user, attach the onboarding profile to the user and save
        if var u = user {
            u.onboardingProfile = onboardingProfile
            StorageService.save(u, forKey: .user)
            user = u

            if var record = SecureAuthService.loadRecord(), record.email == u.email {
                record.onboardingProfile = onboardingProfile
                try? SecureAuthService.saveRecord(record)
            }

            if RemoteAuthService.isConfigured {
                Task {
                    await RemoteAuthService.saveProfile(email: u.email, onboardingProfile: onboardingProfile)
                }
            }
        }

        // Create a small summary string for AI and append to AI dataset (stored as simple string array)
        var parts: [String] = []
        if !onboardingProfile.intentions.isEmpty {
            let names = onboardingProfile.intentions.map { $0.rawValue }
            parts.append("Intentions: \(names.joined(separator: ", "))")
        } else if let i = onboardingProfile.primaryIntention {
            parts.append("Intention: \(i.rawValue)")
        }
        if let minutes = onboardingProfile.scrollEstimateMinutes {
            parts.append("Daily scroll minutes: \(minutes)")
        }
        if !onboardingProfile.preferredApps.isEmpty {
            parts.append("Preferred apps: \(onboardingProfile.preferredApps.joined(separator: ", "))")
        }
        if let a = onboardingProfile.age { parts.append("Age: \(a)") }
        if let ar = onboardingProfile.ageRange { parts.append("Age range: \(ar)") }
        if let interval = onboardingProfile.checkInIntervalMinutes { parts.append("Check-in interval: \(interval) min") }

        if let windows = onboardingProfile.preferredScrollWindows, !windows.isEmpty {
            let schedule = windows.map { "\($0.title): \($0.startHour)-\($0.endHour)" }.joined(separator: ", ")
            parts.append("User scroll windows: \(schedule)")
        }

        let summary = parts.joined(separator: " | ")
        appendAISummary(summary)
    }

    func updatePreferredScrollWindows(_ windows: [ScreenScrollWindow]) {
        guard !isTodayScrollScheduleLocked else { return }
        saveDailyScrollScheduleForToday(windows)
    }

    private func persistPreferredScrollWindows(_ windows: [ScreenScrollWindow]) {
        onboardingProfile.preferredScrollWindows = windows
        saveForCurrentUser(onboardingProfile, forKey: .onboardingProfile)
        if var u = user {
            u.onboardingProfile = onboardingProfile
            StorageService.save(u, forKey: .user)
            user = u
        }
        if var record = SecureAuthService.loadRecord() {
            record.onboardingProfile = onboardingProfile
            try? SecureAuthService.saveRecord(record)
        }
        updateWidgetSharedSummary()
    }

    // Append a short summary string into the aiDataset storage slot (simple string array)
    func appendAISummary(_ summary: String) {
        let email = user?.email
        var entries = email.flatMap { StorageService.load([String].self, forKey: .aiDataset, email: $0) } ?? []
        entries.insert(summary, at: 0)
        if entries.count > 50 { entries = Array(entries.prefix(50)) }
        if let email {
            StorageService.save(entries, forKey: .aiDataset, email: email)
        }
    }

    func resetAllData() {
        let resetEmail = user?.email ?? StorageService.activeUserEmail
        mivoLaunchGateActive = false

        StorageService.remove(forKey: .user)
        StorageService.remove(forKey: .credentials)
        StorageService.remove(forKey: .authSession)
        StorageService.remove(forKey: .rememberedEmail)
        StorageService.remove(forKey: .settings)
        StorageService.remove(forKey: .onboardingProfile)
        StorageService.remove(forKey: .pendingSessionFeedback)
        StorageService.remove(forKey: .timeTruthNotificationSchedule)
        StorageService.remove(forKey: .dailyScrollSchedules)
        StorageService.remove(forKey: .dailyScrollScheduleNotification)
        StorageService.remove(forKey: .weeklyReports)
        StorageService.remove(forKey: .appInterventionRules)
        StorageService.remove(forKey: .accountabilitySummary)
        StorageService.remove(forKey: .widgetSharedSummary)
        StorageService.remove(forKey: .aiDataset)
        if let resetEmail {
            StorageService.remove(forKey: .settings, email: resetEmail)
            StorageService.remove(forKey: .onboardingProfile, email: resetEmail)
            StorageService.remove(forKey: .pendingSessionFeedback, email: resetEmail)
            StorageService.remove(forKey: .runningSession, email: resetEmail)
            StorageService.remove(forKey: .timeTruthNotificationSchedule, email: resetEmail)
            StorageService.remove(forKey: .dailyScrollSchedules, email: resetEmail)
            StorageService.remove(forKey: .dailyScrollScheduleNotification, email: resetEmail)
            StorageService.remove(forKey: .weeklyReports, email: resetEmail)
            StorageService.remove(forKey: .appInterventionRules, email: resetEmail)
            StorageService.remove(forKey: .accountabilitySummary, email: resetEmail)
            StorageService.remove(forKey: .widgetSharedSummary, email: resetEmail)
            StorageService.remove(forKey: .aiDataset, email: resetEmail)
            StorageService.remove(forKey: .sessions, email: resetEmail)
            StorageService.remove(forKey: .truthChecks, email: resetEmail)
        }

        user = nil
        adminToken = nil
        settings = AppSettings(onboardingComplete: false, notificationsEnabled: false)
        onboardingProfile = OnboardingProfile()
        weeklyReports = []
        appInterventionRules = defaultAppInterventionRules()
        pendingSessionFeedback = nil
        pendingExpiredRunningSession = nil
        pendingTimeTruthPrompt = nil
        isLoggedIn = false
        _ = FamilyControlsManager.shared.setMivoSessionActive(false)
        FamilyControlsManager.shared.setLearningModeUnlocked(false)
        FamilyControlsManager.shared.setSignedInForImpulseProtection(false)

        // Offload heavier history deletion to background, update published state on main when done.
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            StorageService.remove(forKey: .sessions)
            StorageService.remove(forKey: .truthChecks)
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.sessions = []
                self.truthChecks = []
                NotificationCenter.default.post(name: .mivoSessionHistoryDidUpdate, object: nil)
            }
        }
    }

    func completeTutorial() {
        settings.tutorialComplete = true
        let updated = settings
        settings = updated
        saveForCurrentUser(settings, forKey: .settings)
    }

    func persistCurrentSettings() {
        if let interval = settings.checkInIntervalMinutes {
            FamilyControlsManager.shared.setCheckInIntervalMinutes(interval)
        }
        saveForCurrentUser(settings, forKey: .settings)
    }

    func requireMivoSessionOnLaunch() {
        mivoLaunchGateActive = false
    }

    func dismissMivoLaunchGate() {
        mivoLaunchGateActive = false
    }

    func consumePendingInterventionSetup() -> Bool {
        guard isLoggedIn, settings.onboardingComplete else { return false }
        guard !isRestrictionBypassUser else {
            clearRestrictionStateForTesting()
            return false
        }
        let pending = FamilyControlsManager.shared.consumePendingInterventionSetup()
        if pending {
            guard !mivoLaunchGateActive else { return false }
            mivoLaunchGateActive = true
        }
        return pending
    }

    // MARK: - Deep link (shield "Open Mivo" button)

    func handleDeepLink(_ url: URL) {
        guard url.scheme == "mivo" else { return }
        // Any mivo:// URL from the shield means "go to the intervention tab"
        deepLinkInterventionRequested = true
    }

    /// Called on app foreground to pick up the flag written by the ShieldAction extension
    func checkDeepLinkInterventionFlag() {
        let defaults = UserDefaults(suiteName: FamilyControlsManager.shared.appGroup)
        if defaults?.bool(forKey: "mivo.openInterventionOnLaunch") == true {
            defaults?.set(false, forKey: "mivo.openInterventionOnLaunch")
            defaults?.synchronize()
            deepLinkInterventionRequested = true
        }
    }

    func markMivoLaunchSessionStarted(plannedMinutes: Int = 0) {
        guard !isRestrictionBypassUser else {
            clearRestrictionStateForTesting()
            return
        }
        
        let success = FamilyControlsManager.shared.setMivoSessionActive(true, plannedMinutes: plannedMinutes, exactDurationSeconds: max(1, plannedMinutes) * 60)
        
        if success {
            sessionActivationError = nil
            mivoLaunchGateActive = false
            print("[AppViewModel] ✅ Session started successfully")
        } else {
            sessionActivationError = "Failed to start session: Device Activity blocker could not be scheduled. Protected apps will remain locked."
            print("[AppViewModel] ❌ Session activation failed")
        }
    }

    func markMivoSessionActiveFor(seconds: Int) {
        guard !isRestrictionBypassUser else {
            clearRestrictionStateForTesting()
            return
        }
        
        let success = FamilyControlsManager.shared.setMivoSessionActive(true, exactDurationSeconds: max(1, seconds))
        
        if success {
            sessionActivationError = nil
            mivoLaunchGateActive = false
            print("[AppViewModel] ✅ Session started successfully")
        } else {
            sessionActivationError = "Failed to start session: Device Activity blocker could not be scheduled. Protected apps will remain locked."
            print("[AppViewModel] ❌ Session activation failed")
        }
    }

    func finishMivoSession(requiresReview: Bool = false) {
        guard !isRestrictionBypassUser else {
            clearRestrictionStateForTesting()
            return
        }
        if requiresReview {
            FamilyControlsManager.shared.endSessionAndRelockForIntervention()
            return
        }
        clearRunningSession()
        _ = FamilyControlsManager.shared.setMivoSessionActive(false)
    }

    func sessionExtensionDecision(
        intention: Intention,
        plannedMinutes: Int,
        elapsedSeconds: Int,
        extensionUsed: Bool,
        now: Date = Date()
    ) -> SessionExtensionDecision {
        let plan = adaptiveScreenTimePlan()
        let ruleMode = protectedGroupRuleMode()
        let actualMinutes = max(1, Int(ceil(Double(elapsedSeconds) / 60.0)))

        if ruleMode == .looseTracking {
            return SessionExtensionDecision(
                allowed: true,
                addedMinutes: 5,
                title: "5 more minutes approved",
                message: "This protected group is set to loose tracking, so Mivo records the choice without making the intervention stricter."
            )
        }

        if plan.collecting {
            return SessionExtensionDecision(
                allowed: true,
                addedMinutes: 30,
                title: "Observation mode",
                message: "Mivo is in its 3-day observation period — no cap is enforced. Your personalized plan starts on day 4 at the average of these 3 days."
            )
        }

        if extensionUsed {
            return SessionExtensionDecision(
                allowed: false,
                addedMinutes: 0,
                title: "Pause here",
                message: nextScrollWindowMessage(for: plan, now: now, fallback: "Mivo has enough data for today. Save this session, then come back during your next planned scroll window.")
            )
        }

        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: now)
        let activeWindow = plan.windows.first { window in
            hour >= window.startHour && hour < window.endHour
        }

        guard let activeWindow else {
            return SessionExtensionDecision(
                allowed: false,
                addedMinutes: 0,
                title: "Come back later",
                message: nextScrollWindowMessage(for: plan, now: now, fallback: "Mivo has enough metrics now. Save this session and come back during your next planned scroll window.")
            )
        }

        let projectedToday = todaysTotalMinutes + actualMinutes
        let remainingTarget = plan.targetMinutes - projectedToday

        guard remainingTarget >= 3 else {
            let added = min(5, max(1, activeWindow.minutes))
            return SessionExtensionDecision(
                allowed: true,
                addedMinutes: added,
                title: "Short check-in approved",
                message: "You are inside your planned scroll window, so Mivo is allowing a short session even though today's recorded usage is already at the adaptive target."
            )
        }

        let added = min(5, max(3, remainingTarget))
        return SessionExtensionDecision(
            allowed: true,
            addedMinutes: added,
            title: "\(added) more minutes approved",
            message: "This still fits inside today's adaptive plan. Mivo will lock the app again when the added time ends."
        )
    }

    func adaptiveSessionDurationLimit(now: Date = Date()) -> (maxMinutes: Int, isLimited: Bool, message: String, windowTitle: String) {
        let plan = adaptiveScreenTimePlan()
        if protectedGroupRuleMode() == .looseTracking {
            return (
                maxMinutes: 30,
                isLimited: false,
                message: "Loose tracking is on for the protected group, so Mivo will record sessions without lowering choices.",
                windowTitle: "Loose tracking"
            )
        }
        if plan.collecting {
            return (
                maxMinutes: 240,
                isLimited: false,
                message: "First 3 days: observation mode. Mivo is recording your real usage so it can start the personalized plan on day 4 at the average of these 3 days.",
                windowTitle: "3-day observation"
            )
        }

        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: now)
        let activeWindow = plan.windows.first { window in
            hour >= window.startHour && hour < window.endHour
        }

        guard let activeWindow else {
            return (
                maxMinutes: 0,
                isLimited: true,
                message: nextScrollWindowMessage(
                    for: plan,
                    now: now,
                    fallback: "No scroll window is open right now. Come back during the next planned window."
                ),
                windowTitle: "No window open"
            )
        }

        let usedInWindow = minutesUsedToday(in: activeWindow)
        let remainingInWindow = max(0, activeWindow.minutes - usedInWindow)
        let remainingToday = max(0, plan.targetMinutes - todaysTotalMinutes)
        let computedMaxMinutes = min(30, remainingInWindow, remainingToday)
        let windowLength = max(1, activeWindow.endHour - activeWindow.startHour)
        let windowText = "\(activeWindow.title) - \(windowLength)h window"

        if computedMaxMinutes <= 0 {
            let activeWindowMinimum = min(5, max(1, activeWindow.minutes))
            let message = "This scroll window is open now. Mivo is allowing a short \(activeWindowMinimum)-minute session even though recorded usage already hit the planned cap."
            return (maxMinutes: activeWindowMinimum, isLimited: true, message: message, windowTitle: windowText)
        }

        let message = "\(computedMaxMinutes) min left in this \(windowLength)-hour window. Mivo is using your adaptive plan, not the old always-30-minute choice."

        return (maxMinutes: computedMaxMinutes, isLimited: true, message: message, windowTitle: windowText)
    }

    private func minutesUsedToday(in window: ScreenScrollWindow) -> Int {
        let calendar = Calendar.current
        let formatter = ISO8601DateFormatter()
        return todaysSessions.reduce(0) { total, session in
            guard let start = formatter.date(from: session.startTime) else { return total }
            let hour = calendar.component(.hour, from: start)
            guard hour >= window.startHour && hour < window.endHour else { return total }
            return total + session.actualDuration
        }
    }

    private func nextScrollWindowMessage(for plan: ScreenTimeReductionPlan, now: Date, fallback: String) -> String {
        guard !plan.windows.isEmpty else { return fallback }

        let calendar = Calendar.current
        let currentHour = calendar.component(.hour, from: now)
        let sortedWindows = plan.windows.sorted { lhs, rhs in
            if lhs.startHour == rhs.startHour { return lhs.endHour < rhs.endHour }
            return lhs.startHour < rhs.startHour
        }
        let nextWindow = sortedWindows.first { $0.startHour > currentHour } ?? sortedWindows[0]
        let nextDate = calendar.date(
            bySettingHour: nextWindow.startHour,
            minute: 0,
            second: 0,
            of: nextWindow.startHour > currentHour ? now : calendar.date(byAdding: .day, value: 1, to: now) ?? now
        ) ?? now

        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        let windowLength = max(1, nextWindow.endHour - nextWindow.startHour)
        if plan.collecting {
            return "Your chosen scroll schedule is active. Come back at \(formatter.string(from: nextDate)) and scroll up to \(nextWindow.minutes) minutes inside that \(windowLength)-hour window."
        }
        return "Mivo has enough data now. Come back at \(formatter.string(from: nextDate)) and scroll up to \(nextWindow.minutes) minutes inside that \(windowLength)-hour window."
    }

    func adaptiveScreenTimePlan() -> ScreenTimeReductionPlan {
        let plan = rawAdaptiveScreenTimePlan()
        if let todaySchedule = dailyScrollSchedule() {
            return planReplacingWindows(
                in: plan,
                windows: todaySchedule.windows,
                idSuffix: "today-\(todaySchedule.date)",
                collectingSummary: "First 3 days are observation mode — no cap enforced. On day 4 your personalized plan starts at the average of these 3 days and trims 10 min per day from there.",
                activeSummary: "Today’s scroll windows are locked from the morning check. Mivo trims your target by 10 min per day from your 3-day observation average.",
                reason: plan.collecting ? "Your times are saved for tracking. Days 1–3 have no enforced cap — Mivo just observes." : "These windows are the schedule you locked for today. You can choose again tomorrow morning."
            )
        }
        if plan.collecting {
            return planReplacingWindows(
                in: plan,
                windows: [],
                idSuffix: "needs-daily-schedule",
                collectingSummary: "First 3 days are observation mode — no cap enforced. Choose times if you want Mivo to watch those periods. Your personalized plan starts on day 4 at the average of these 3 days.",
                activeSummary: nil,
                reason: "Mivo will not enforce a default window before you lock today’s schedule."
            )
        }
        return plan
    }

    private func syncLearningModeProtectionState() {
        guard isLoggedIn, !isRestrictionBypassUser else {
            FamilyControlsManager.shared.setLearningModeUnlocked(false)
            return
        }

        FamilyControlsManager.shared.setLearningModeUnlocked(rawAdaptiveScreenTimePlan().collecting)
    }

    private func rawAdaptiveScreenTimePlan() -> ScreenTimeReductionPlan {
        AIService.makeScreenTimeReductionPlan(
            sessions: sessions,
            truthChecks: truthChecks,
            todayScreenTimeMinutes: deviceActivityMinutesToday,
            profile: onboardingProfile
        )
    }

    private func planReplacingWindows(
        in plan: ScreenTimeReductionPlan,
        windows: [ScreenScrollWindow],
        idSuffix: String,
        collectingSummary: String,
        activeSummary: String?,
        reason: String
    ) -> ScreenTimeReductionPlan {
        ScreenTimeReductionPlan(
            id: "\(plan.id)-\(idSuffix)",
            collecting: plan.collecting,
            daysCollected: plan.daysCollected,
            daysNeeded: plan.daysNeeded,
            dayIndex: plan.dayIndex,
            baselineMinutes: plan.baselineMinutes,
            targetMinutes: plan.targetMinutes,
            strictnessPercent: plan.strictnessPercent,
            summary: plan.collecting ? collectingSummary : (activeSummary ?? plan.summary),
            decisionReason: reason,
            windows: windows
        )
    }

    // MARK: - Helpers

    func todayKey() -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt.string(from: Date())
    }

    private func timeTruthActualMinutesForToday() -> Int {
        refreshScreenTimeData()
        return deviceActivityMinutesToday ?? todaysTotalMinutes
    }

    private func dailyScrollSchedulePromptTime() -> (hour: Int, minute: Int) {
        (8, 0)
    }

    private func suggestedDailyScrollWindows(recommendationReady: Bool) -> [ScreenScrollWindow] {
        let plan = adaptiveScreenTimePlan()
        if recommendationReady, !plan.windows.isEmpty {
            return plan.windows
        }
        if let windows = onboardingProfile.preferredScrollWindows, !windows.isEmpty {
            return windows
        }
        let baseline = onboardingProfile.scrollEstimateMinutes ?? 60
        let perWindow = max(5, min(20, baseline / 4))
        return [
            ScreenScrollWindow(id: "daily-session-1", title: "Session 1", startHour: 14, endHour: 15, minutes: perWindow, reason: "Your first daily scroll window."),
            ScreenScrollWindow(id: "daily-session-2", title: "Session 2", startHour: 20, endHour: 21, minutes: perWindow, reason: "Your second daily scroll window.")
        ]
    }

    private func normalizeDailyScrollWindows(_ windows: [ScreenScrollWindow]) -> [ScreenScrollWindow] {
        let baseline = onboardingProfile.scrollEstimateMinutes ?? 60
        let firstMinutes = max(5, min(30, Int(Double(baseline) * 0.55)))
        let secondMinutes = max(5, min(30, baseline - firstMinutes))
        return Array(windows.prefix(2).enumerated()).map { index, window in
            let start = ((window.startHour % 24) + 24) % 24
            let end = (start + 1) % 24
            return ScreenScrollWindow(
                id: "daily-session-\(index + 1)",
                title: index == 0 ? "Today’s session 1" : "Today’s session 2",
                startHour: start,
                endHour: end == 0 ? 24 : end,
                minutes: index == 0 ? firstMinutes : secondMinutes,
                reason: "Locked for today. You can choose new times tomorrow morning."
            )
        }
    }

    private func adaptiveLearningDaysCollected() -> Int {
        Set(Array(sessions.map(\.date)) + truthChecks.map(\.date)).count
    }

    private func hourLabel(_ hour: Int) -> String {
        let normalized = ((hour % 24) + 24) % 24
        if normalized == 0 { return "12a" }
        if normalized < 12 { return "\(normalized)a" }
        if normalized == 12 { return "12p" }
        return "\(normalized - 12)p"
    }

    private func timeTruthSchedule() -> (hour: Int, minute: Int) {
        // Daily Truth always fires at 9:00 PM local time — a consistent end-of-day
        // moment so users build a steady reflection habit instead of guessing when
        // the prompt will appear.
        return (21, 0)
    }

    func requestScreenTimeAccessAndRefresh() async -> Bool {
        let granted = await withCheckedContinuation { continuation in
            FamilyControlsManager.shared.requestAuthorization { granted in
                continuation.resume(returning: granted)
            }
        }

        FamilyControlsManager.shared.saveAuthorizationFlag(granted)

        guard granted else {
            loadDeviceActivityReport()
            return false
        }

        await withCheckedContinuation { continuation in
            FamilyControlsManager.shared.scheduleDailyMonitoring { _ in
                continuation.resume()
            }
        }

        loadDeviceActivityReport()
        return true
    }

    func refreshScreenTimeData() {
        loadDeviceActivityReport()
        updateWidgetSharedSummary()
    }

    func updateAccountabilityEnabled(_ enabled: Bool) {
        settings.accountabilityEnabled = enabled
        let updated = settings
        settings = updated
        saveForCurrentUser(updated, forKey: .settings)
        updateAccountabilitySummary()
    }

    func updateAppInterventionRule(_ rule: AppInterventionRule) {
        if let index = appInterventionRules.firstIndex(where: { $0.id == rule.id }) {
            appInterventionRules[index] = rule
        } else {
            appInterventionRules.append(rule)
        }
        saveForCurrentUser(appInterventionRules, forKey: .appInterventionRules)
        updateWidgetSharedSummary()
    }

    func refreshWeeklyReportSnapshot() {
        let snapshot = makeCurrentWeeklyReportSnapshot()
        weeklyReports.removeAll { $0.id == snapshot.id }
        weeklyReports.insert(snapshot, at: 0)
        weeklyReports = Array(weeklyReports.prefix(12))
        saveForCurrentUser(weeklyReports, forKey: .weeklyReports)
        updateAccountabilitySummary()
    }

    func makeCurrentWeeklyReportSnapshot(now: Date = Date()) -> WeeklyReportSnapshot {
        let week = weekBounds(containing: now)
        let weekSessions = sessions.filter { $0.date >= week.startKey && $0.date <= week.endKey }
        let total = weekSessions.reduce(0) { $0 + $1.actualDuration }
        let recovered = recoveredMinutes(from: weekSessions)
        let topUrge = Dictionary(grouping: weekSessions.compactMap(\.urgeReason), by: { $0 })
            .max(by: { $0.value.count < $1.value.count })?.key
        let hardest = hardestWindow(from: weekSessions)
        let extended = weekSessions.filter(\.extendedOnce).count
        let emergencies = weekSessions.filter { $0.emergencyUnlockUsed == true }.count
        let recommendation = weeklyRecommendation(
            sessions: weekSessions,
            topUrge: topUrge,
            hardestWindow: hardest,
            emergencyUnlockCount: emergencies
        )
        return WeeklyReportSnapshot(
            id: week.startKey,
            weekStart: week.startKey,
            weekEnd: week.endKey,
            totalMinutes: total,
            recoveredMinutes: recovered,
            sessionCount: weekSessions.count,
            topUrgeReason: topUrge,
            hardestWindow: hardest,
            extendedCount: extended,
            emergencyUnlockCount: emergencies,
            recommendation: recommendation
        )
    }

    func accountabilityShareText() -> String {
        let snapshot = makeCurrentWeeklyReportSnapshot()
        let plan = adaptiveScreenTimePlan()
        let weekSessions = sessions.filter { $0.date >= snapshot.weekStart && $0.date <= snapshot.weekEnd }
        let days = Set(weekSessions.map(\.date))
        let withinPlanDays = min(days.count, max(0, 7 - snapshot.emergencyUnlockCount))
        let hours = Double(snapshot.recoveredMinutes) / 60.0
        return "This week I stayed within plan \(withinPlanDays)/7 days, used \(snapshot.emergencyUnlockCount) emergency unlock\(snapshot.emergencyUnlockCount == 1 ? "" : "s"), and recovered \(String(format: "%.1f", hours)) hours. Current Mivo target: \(plan.targetMinutes)m/day."
    }

    func updateAccountabilitySummary() {
        guard settings.accountabilityEnabled == true else {
            removeForCurrentUser(.accountabilitySummary)
            return
        }
        let snapshot = makeCurrentWeeklyReportSnapshot()
        let summary = AccountabilitySummary(
            weekStart: snapshot.weekStart,
            weekEnd: snapshot.weekEnd,
            shareText: accountabilityShareText()
        )
        saveForCurrentUser(summary, forKey: .accountabilitySummary)
    }

    func updateWidgetSharedSummary() {
        let plan = adaptiveScreenTimePlan()
        let nextWindow = nextWidgetWindowText(for: plan)
        let trackedScrollMinutes = todaysSessions.reduce(0) { total, session in
            total + session.actualDuration
        }
        let scrolledMinutesToday = deviceActivityMinutesToday ?? trackedScrollMinutes
        let summary = WidgetSharedSummary(
            recoveredMinutesToday: recoveredMinutes(from: todaysSessions),
            screenTimeMinutesToday: scrolledMinutesToday,
            nextScrollWindow: nextWindow,
            planState: plan.collecting ? "Learning mode" : "\(plan.targetMinutes)m target",
            streakText: "\(todaysSessions.count) session\(todaysSessions.count == 1 ? "" : "s") today",
            updatedAt: ISO8601DateFormatter().string(from: Date())
        )
        saveForCurrentUser(summary, forKey: .widgetSharedSummary)
        if let groupDefaults = UserDefaults(suiteName: FamilyControlsManager.shared.appGroup),
           let data = try? JSONEncoder().encode(summary) {
            groupDefaults.set(data, forKey: StorageKey.widgetSharedSummary.rawValue)
            groupDefaults.synchronize()
        }
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }

    func exportData() -> String {
        let data: [String: Any] = [
            "sessions": (try? JSONEncoder().encode(sessions)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]",
            "truthChecks": (try? JSONEncoder().encode(truthChecks)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        ]
        if let jsonData = try? JSONSerialization.data(withJSONObject: data, options: .prettyPrinted),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            return jsonString
        }
        return "{}"
    }

    // Async export that snapshots session/trace data and serializes off the main thread
    func exportDataAsync() async -> String {
        // Snapshot current arrays on main actor
        let sessionsSnapshot = sessions
        let truthSnapshot = truthChecks

        return await Task.detached(priority: .userInitiated) {
            let data: [String: Any] = [
                "sessions": (try? JSONEncoder().encode(sessionsSnapshot)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]",
                "truthChecks": (try? JSONEncoder().encode(truthSnapshot)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
            ]
            if let jsonData = try? JSONSerialization.data(withJSONObject: data, options: .prettyPrinted),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                return jsonString
            }
            return "{}"
        }.value
    }

    // MARK: - Computed

    var todaysSessions: [Session] {
        let today = todayKey()
        return sessions.filter { $0.date == today }
    }

    var todaysTotalMinutes: Int {
        todaysSessions.reduce(0) { $0 + $1.actualDuration }
    }

    var patternPercent: Int {
        let cal = Calendar.current
        let now = Date()
        let oneWeekAgo = cal.date(byAdding: .day, value: -7, to: now)!
        let twoWeeksAgo = cal.date(byAdding: .day, value: -14, to: now)!
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withFullDate]

        let thisWeek = sessions.filter {
            if let d = fmt.date(from: $0.date) { return d >= oneWeekAgo }
            return false
        }.reduce(0) { $0 + $1.actualDuration }

        let lastWeek = sessions.filter {
            if let d = fmt.date(from: $0.date) { return d >= twoWeeksAgo && d < oneWeekAgo }
            return false
        }.reduce(0) { $0 + $1.actualDuration }

        if lastWeek == 0 { return 0 }
        return Int(Double(thisWeek - lastWeek) / Double(lastWeek) * 100)
    }

    func patternInsights() -> [String] {
        guard sessions.count >= 2 else { return [] }
        var insights: [String] = []

        var intentionCounts: [Intention: Int] = [:]
        sessions.forEach { intentionCounts[$0.intention, default: 0] += 1 }
        if let top = intentionCounts.max(by: { $0.value < $1.value }) {
            insights.append("You most often scroll to \(top.key.rawValue.lowercased()).")
        }

        let avg = sessions.reduce(0) { $0 + $1.actualDuration } / sessions.count
        insights.append("Your average session lasts \(avg) minutes.")

        let cal = Calendar.current
        let nightSessions = sessions.filter {
            guard let date = ISO8601DateFormatter().date(from: $0.startTime) else { return false }
            let hour = cal.component(.hour, from: date)
            return hour >= 21 || hour < 6
        }
        if nightSessions.count > sessions.count * 2 / 5 {
            insights.append("You scroll most at night.")
        }

        let overSessions = sessions.filter { $0.actualDuration > $0.plannedDuration }
        if overSessions.count > sessions.count / 2 {
            insights.append("You often go over your planned time.")
        }

        let extended = sessions.filter { $0.extendedOnce }
        if extended.count * 10 > sessions.count * 3 {
            insights.append("Extensions are common for you.")
        }

        let boredSessions = sessions.filter { $0.intention == .bored }
        if !boredSessions.isEmpty {
            let boredAvg = boredSessions.reduce(0) { $0 + $1.actualDuration } / boredSessions.count
            if boredAvg > avg {
                insights.append("Your longest sessions start when you say you're bored.")
            }
        }

        return insights
    }

    // Load Screen Time data from the real Device Activity extension report.
    //
    // The Screen Time data is "sticky": once we have a non-zero total for today
    // we hold on to it even if the next refresh returns an empty report.  iOS's
    // DeviceActivityReportExtension occasionally hands back empty results when
    // the report surface isn't fully ready, which used to cause the live total
    // to flicker between a real value and 0.  Hiding good data behind a bad
    // refresh is worse than showing slightly stale data, so we only adopt a new
    // value when it has signal.
    func loadDeviceActivityReport() {
        if #available(iOS 16.0, *) {
            let collector = ScreenTimeDataCollector.shared

            if let report = collector.latestReport {
                let isEmpty = report.totalSeconds == 0 && report.perAppSeconds.isEmpty
                if isEmpty,
                   let existing = deviceActivityMinutesToday, existing > 0,
                   let existingGenerated = deviceActivityReportGeneratedAt,
                   Calendar.current.isDate(existingGenerated, inSameDayAs: Date()) {
                    // Keep the previously shown total; don't flicker to 0.
                    updateWidgetSharedSummary()
                    return
                }

                deviceActivityMinutesToday = report.totalMinutes
                deviceActivityPerAppSeconds = report.perAppSeconds
                deviceActivityReportGeneratedAt = report.generatedAt
                if let encoded = try? JSONSerialization.data(withJSONObject: report.toJSON(), options: []),
                   let jsonString = String(data: encoded, encoding: .utf8) {
                    lastDeviceActivityReportJSON = jsonString
                }
                updateWidgetSharedSummary()
                return
            }
        }

        if #available(iOS 16.0, *),
           ScreenTimeDataCollector.shared.authorizationStatus == .authorized,
           deviceActivityReportGeneratedAt != nil || deviceActivityMinutesToday != nil || !deviceActivityPerAppSeconds.isEmpty {
            updateWidgetSharedSummary()
            return
        }

        lastDeviceActivityReportJSON = nil
        deviceActivityMinutesToday = nil
        deviceActivityPerAppSeconds = [:]
        deviceActivityReportGeneratedAt = nil
        updateWidgetSharedSummary()
    }

    func startObservingDeviceActivityUpdates() {
        // Listen for updates from Screen Time collector
        NotificationCenter.default.addObserver(forName: Notification.Name("mivoDeviceActivityDidUpdate"), object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.loadDeviceActivityReport()
            }
        }
        
        // Set up a timer to poll for updates every 5 minutes
        Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.loadDeviceActivityReport()
            }
        }
        
        // Initial load
        Task { @MainActor in loadDeviceActivityReport() }
    }

    private func defaultAppInterventionRules() -> [AppInterventionRule] {
        let appNames = onboardingProfile.preferredApps.isEmpty
            ? ["Protected apps"]
            : onboardingProfile.preferredApps
        return appNames.map {
            AppInterventionRule(id: $0.lowercased(), appName: $0, mode: .standardPause)
        }
    }

    private func protectedGroupRuleMode() -> AppRuleMode {
        if let group = appInterventionRules.first(where: { $0.id == "protected apps" }) {
            return group.mode
        }
        return appInterventionRules.first?.mode ?? .standardPause
    }

    private func weekBounds(containing date: Date) -> (startKey: String, endKey: String) {
        let calendar = Calendar.current
        let interval = calendar.dateInterval(of: .weekOfYear, for: date)
        let start = interval?.start ?? date
        let end = calendar.date(byAdding: .day, value: 6, to: start) ?? date
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return (formatter.string(from: start), formatter.string(from: end))
    }

    private func recoveredMinutes(from sessions: [Session]) -> Int {
        let planned = sessions.reduce(0) { $0 + $1.plannedDuration }
        let actual = sessions.reduce(0) { $0 + $1.actualDuration }
        let baseline = max(onboardingProfile.scrollEstimateMinutes ?? 60, planned)
        return max(0, baseline - actual)
    }

    private func hardestWindow(from sessions: [Session]) -> String {
        guard !sessions.isEmpty else { return "No pattern yet" }
        var buckets: [String: Int] = ["Morning": 0, "Afternoon": 0, "Evening": 0, "Night": 0]
        let calendar = Calendar.current
        let formatter = ISO8601DateFormatter()
        for session in sessions {
            guard let date = formatter.date(from: session.startTime) else { continue }
            let hour = calendar.component(.hour, from: date)
            let bucket: String
            if hour >= 21 || hour < 6 {
                bucket = "Night"
            } else if hour < 12 {
                bucket = "Morning"
            } else if hour < 17 {
                bucket = "Afternoon"
            } else {
                bucket = "Evening"
            }
            buckets[bucket, default: 0] += max(session.actualDuration, 1)
        }
        return buckets.max(by: { $0.value < $1.value })?.key ?? "No pattern yet"
    }

    private func weeklyRecommendation(
        sessions: [Session],
        topUrge: UrgeReason?,
        hardestWindow: String,
        emergencyUnlockCount: Int
    ) -> String {
        if sessions.isEmpty {
            return "Complete one protected-app session so Mivo can build next week’s plan."
        }
        if emergencyUnlockCount > 0 {
            return "Keep emergency unlocks rare next week. Start with shorter sessions during \(hardestWindow.lowercased()) and save the reason before adding time."
        }
        if let topUrge {
            return "Your strongest urge was \(topUrge.rawValue.lowercased()). Add one offline replacement before opening protected apps."
        }
        return "Your session control is forming. Keep the 5-second pause and choose a clear reason before scrolling."
    }

    private func nextWidgetWindowText(for plan: ScreenTimeReductionPlan) -> String {
        guard let window = plan.windows.first else {
            return plan.collecting ? "Learning your rhythm" : "Open Mivo"
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "ha"
        let calendar = Calendar.current
        let start = calendar.date(bySettingHour: window.startHour, minute: 0, second: 0, of: Date()) ?? Date()
        return "\(formatter.string(from: start)) · \(window.minutes)m"
    }

    // MARK: - Secure Auth

    func resetPasswordWithoutVerification(email: String, newPassword: String) async throws {
        let normalizedEmail = email.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard newPassword.count >= 8 else {
            throw AppError.weakPassword
        }

        if RemoteAuthService.isConfigured {
            do {
                try await RemoteAuthService.resetPassword(email: normalizedEmail, newPassword: newPassword)
                if var record = SecureAuthService.loadRecord(email: normalizedEmail) {
                    record = try SecureAuthService.updatePassword(newPassword, for: record)
                    try SecureAuthService.saveRecord(record)
                }
                return
            } catch AppError.noAccount {
                throw AppError.noAccount
            } catch {
                // Let local-only test accounts reset even when the backend is offline.
            }
        }

        guard var record = SecureAuthService.loadRecord(email: normalizedEmail) else {
            throw AppError.noAccount
        }
        record = try SecureAuthService.updatePassword(newPassword, for: record)
        try SecureAuthService.saveRecord(record)
    }

    private func cacheRemoteUser(_ remoteUser: RemoteAuthUser, password: String) throws {
        var record = try SecureAuthService.createRecord(
            email: remoteUser.email,
            password: password,
            name: remoteUser.name
        )
        record.createdAt = remoteUser.createdAt
        record.onboardingProfile = remoteUser.onboardingProfile
        record.isAdmin = remoteUser.isAdmin == true
        record.adminToken = remoteUser.adminToken
        try SecureAuthService.saveRecord(record)
    }

    private func isBuiltInAdminCredentials(email: String, password: String) -> Bool {
        email == builtInAdminEmail && password == "Pranshu@123"
    }

    private func isBuiltInTestingEmail(_ email: String) -> Bool {
        email == builtInTestingEmail
    }

    private func isBuiltInTestingCredentials(email: String, password: String) -> Bool {
        isBuiltInTestingEmail(email) && password == builtInTestingPassword
    }

    private func createOrUpdateLocalAdminRecord(email: String, password: String) throws {
        var record: SecureAuthRecord
        if let existing = SecureAuthService.loadRecord(email: email) {
            record = try SecureAuthService.updatePassword(password, for: existing)
        } else {
            record = try SecureAuthService.createRecord(email: email, password: password, name: "Mivo Admin")
        }

        record.isAdmin = true
        record.adminToken = nil
        try SecureAuthService.saveRecord(record)
    }

    private func createOrUpdateLocalTestingRecord(email: String, password: String) throws {
        var record: SecureAuthRecord
        if let existing = SecureAuthService.loadRecord(email: email) {
            record = try SecureAuthService.updatePassword(password, for: existing)
        } else {
            record = try SecureAuthService.createRecord(email: email, password: password, name: "Mivo Testing")
        }

        record.isAdmin = false
        record.adminToken = nil
        try SecureAuthService.saveRecord(record)
    }

    private func applyRestrictionState(for email: String) {
        if isBuiltInTestingEmail(email.lowercased()) {
            clearRestrictionStateForTesting()
        } else {
            syncLearningModeProtectionState()
            FamilyControlsManager.shared.setSignedInForImpulseProtection(true)
        }
    }

    private func clearRestrictionStateForTesting() {
        mivoLaunchGateActive = false
        pendingSessionFeedback = nil
        pendingExpiredRunningSession = nil
        removeForCurrentUser(.pendingSessionFeedback)
        clearRunningSession()
        _ = FamilyControlsManager.shared.setMivoSessionActive(false)
        FamilyControlsManager.shared.setLearningModeUnlocked(false)
        FamilyControlsManager.shared.clearPendingInterventionSetup()
        FamilyControlsManager.shared.setSignedInForImpulseProtection(false)
    }

}

// MARK: - Errors

enum AppError: LocalizedError {
    case noAccount
    case invalidCredentials
    case accountDataMissing
    case emailAlreadyExists
    case weakPassword
    case secureStorageFailed
    case remoteAuthUnavailable
    case adminRequired

    var errorDescription: String? {
        switch self {
        case .noAccount: return "No account found. Please create one."
        case .invalidCredentials: return "Invalid email or password."
        case .accountDataMissing: return "Account data missing. Please register again."
        case .emailAlreadyExists: return "An account with this email already exists."
        case .weakPassword: return "Password must be at least 8 characters."
        case .secureStorageFailed: return "Could not save credentials securely."
        case .remoteAuthUnavailable: return "The online Mivo account server is not reachable yet."
        case .adminRequired: return "Admin access is required. Sign in with the admin account."
        }
    }
}
