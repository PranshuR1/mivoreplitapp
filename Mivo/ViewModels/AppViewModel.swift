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
    @Published var weeklyReports: [WeeklyReportSnapshot] = []
    @Published var appInterventionRules: [AppInterventionRule] = []
    @Published var settings: AppSettings = AppSettings(onboardingComplete: false, notificationsEnabled: false)
    @Published var onboardingProfile: OnboardingProfile = OnboardingProfile()
    @Published var isLoading: Bool = true
    @Published var adminToken: String? = nil

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
    @Published var pendingTimeTruthPrompt: TimeTruthPrompt? = nil

    private var deviceActivityObserver: NSObjectProtocol?
    private var deviceActivityPollTimer: Timer?

    init() {
        loadData()
        // Begin observing device activity updates from the Device Activity extension or Screen Time API
        startObservingDeviceActivityUpdates()

        Task { @MainActor in
            startScreenTimeMonitoringIfAuthorized()
            recoverExpiredRunningSessionIfNeeded()
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
            applyRestrictionState(for: authRecord.email)
            loadUserScopedData(for: authRecord.email)
        } else {
            adminToken = nil
            resetUserScopedState()
            FamilyControlsManager.shared.setSignedInForImpulseProtection(false)
        }
        isLoading = false
    }

    private func startScreenTimeMonitoringIfAuthorized() {
        // Keep Screen Time scheduling off the synchronous launch/loading path.
        if #available(iOS 16.0, *) {
            let collector = ScreenTimeDataCollector.shared
            if collector.authorizationStatus == .authorized {
                collector.startMonitoring()
            }
        }
    }

    private func resetUserScopedState() {
        sessions = []
        truthChecks = []
        weeklyReports = []
        appInterventionRules = defaultAppInterventionRules()
        settings = AppSettings(onboardingComplete: false, notificationsEnabled: false)
        onboardingProfile = OnboardingProfile()
        pendingSessionFeedback = nil
        pendingTimeTruthPrompt = nil
    }

    private func loadUserScopedData(for email: String) {
        sessions = StorageService.load([Session].self, forKey: .sessions, email: email) ?? []
        truthChecks = StorageService.load([TruthCheckGuess].self, forKey: .truthChecks, email: email) ?? []
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
        pendingSessionFeedback = StorageService.load(PendingSessionFeedback.self, forKey: .pendingSessionFeedback, email: email)
        clearCompletedSessionRecoveryStateIfNeeded(email: email)
    }

    private func clearCompletedSessionRecoveryStateIfNeeded(email: String) {
        if let pendingSessionFeedback,
           sessions.contains(where: { $0.id == pendingSessionFeedback.id }) {
            self.pendingSessionFeedback = nil
            StorageService.remove(forKey: .pendingSessionFeedback, email: email)
        }

        if let running = StorageService.load(RunningMivoSession.self, forKey: .runningSession, email: email),
           sessions.contains(where: { $0.id == running.id }) {
            StorageService.remove(forKey: .runningSession, email: email)
        }
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
        }

        try completeLocalLogin(email: normalizedEmail, password: password, rememberMe: rememberMe)
    }

    func socialLogin(_ credential: SocialCredential) async throws {
        guard RemoteAuthService.isConfigured else { throw AppError.socialSignInUnavailable }
        let remoteUser = try await RemoteAuthService.socialLogin(credential)
        // Social accounts have no password; cache a random one so the local keychain record stays valid.
        let placeholder = UUID().uuidString + UUID().uuidString
        try cacheRemoteUser(remoteUser, password: placeholder)
        if remoteUser.onboardingProfile == nil {
            settings.onboardingComplete = false
        }
        try completeLogin(email: remoteUser.email, persistSession: true)
    }

    private func completeOfflineLogin(email: String, password: String, rememberMe: Bool) throws {
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
        applyRestrictionState(for: record.email)
        loadUserScopedData(for: record.email)

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
        if let existingIndex = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[existingIndex] = session
        } else {
            sessions.append(session)
        }
        saveForCurrentUser(sessions, forKey: .sessions)
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
        removeForCurrentUser(.pendingSessionFeedback)
        clearRunningSession()
    }

    func saveRunningSession(_ session: RunningMivoSession) {
        saveForCurrentUser(session, forKey: .runningSession)
    }

    func clearRunningSession() {
        removeForCurrentUser(.runningSession)
    }

    func recoverExpiredRunningSessionIfNeeded(now: Date = Date()) {
        guard isLoggedIn, settings.onboardingComplete else { return }
        guard let email = user?.email,
              let running = StorageService.load(RunningMivoSession.self, forKey: .runningSession, email: email) else { return }

        if sessions.contains(where: { $0.id == running.id }) {
            if pendingSessionFeedback?.id == running.id {
                pendingSessionFeedback = nil
                removeForCurrentUser(.pendingSessionFeedback)
            }
            clearRunningSession()
            FamilyControlsManager.shared.endSessionAndRelockForIntervention()
            return
        }

        let formatter = ISO8601DateFormatter()
        guard let segmentStartedAt = formatter.date(from: running.startTime) else {
            clearRunningSession()
            return
        }

        let accumulatedElapsedSeconds = max(0, running.accumulatedElapsedSeconds ?? 0)
        let storedApprovedSeconds = max(1, running.approvedSeconds ?? running.plannedSeconds)
        let storedApprovedWasLegacyTotal = accumulatedElapsedSeconds > 0 && storedApprovedSeconds > running.plannedSeconds
        let currentSegmentApprovedSeconds = storedApprovedWasLegacyTotal
            ? max(1, min(running.plannedSeconds, storedApprovedSeconds - accumulatedElapsedSeconds))
            : storedApprovedSeconds
        let totalApprovedSeconds = storedApprovedWasLegacyTotal
            ? storedApprovedSeconds
            : accumulatedElapsedSeconds + currentSegmentApprovedSeconds
        let storedExpiresAt = running.expiresAt.flatMap { formatter.date(from: $0) }
        let fallbackSegmentSeconds: Int
        if running.expiresAt == nil,
           accumulatedElapsedSeconds > 0,
           running.approvedSeconds == nil || running.approvedSeconds == running.plannedSeconds,
           running.plannedSeconds > accumulatedElapsedSeconds {
            fallbackSegmentSeconds = running.plannedSeconds - accumulatedElapsedSeconds
        } else {
            fallbackSegmentSeconds = running.plannedSeconds
        }
        let expectedEnd = storedExpiresAt ?? segmentStartedAt.addingTimeInterval(TimeInterval(max(1, fallbackSegmentSeconds)))
        let expirationInfo = FamilyControlsManager.shared.currentSessionExpirationInfo()
        let systemExpired = expirationInfo != nil
        let isExpiredByClock = expectedEnd <= now

        if !isExpiredByClock && !systemExpired {
            let remainingSeconds = max(1, Int(expectedEnd.timeIntervalSince(now)))
            let result = FamilyControlsManager.shared.setMivoSessionActive(true, exactDurationSeconds: remainingSeconds)
            if result.success {
                return
            }
        }

        FamilyControlsManager.shared.endSessionAndRelockForIntervention()
        guard pendingSessionFeedback == nil else { return }

        let expiredAt = expirationInfo?.expiredAt ?? expectedEnd
        let cappedEnd = min(min(expiredAt, expectedEnd), now)
        let segmentElapsedSeconds = max(0, Int(cappedEnd.timeIntervalSince(segmentStartedAt)))
        let actualSeconds = max(1, min(totalApprovedSeconds, accumulatedElapsedSeconds + segmentElapsedSeconds))
        let actualMinutes = max(1, Int(ceil(Double(actualSeconds) / 60.0)))
        let finalStartTime = running.originalStartTime ?? running.startTime

        savePendingSessionFeedback(
            PendingSessionFeedback(
                id: running.id,
                intention: running.intention,
                plannedDuration: running.plannedDuration,
                actualDuration: actualMinutes,
                startTime: finalStartTime,
                endTime: formatter.string(from: cappedEnd),
                extendedOnce: running.extendedOnce,
                urgeReason: running.urgeReason,
                urgeNote: running.urgeNote,
                emergencyUnlockUsed: running.emergencyUnlockUsed,
                emergencyUnlockReason: running.emergencyUnlockReason
            )
        )
    }

    @discardableResult
    func resumePendingSession(
        from feedback: PendingSessionFeedback,
        addingMinutes addedMinutes: Int,
        emergencyReason: String? = nil
    ) -> MivoSessionActivationResult {
        let addedSeconds = max(60, addedMinutes * 60)
        let result = markMivoSessionActiveFor(seconds: addedSeconds)
        guard result.success else { return result }

        let now = Date()
        let formatter = ISO8601DateFormatter()
        let emergencyReason = emergencyReason?.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasEmergencyReason = (emergencyReason?.isEmpty == false)

        pendingSessionFeedback = nil
        removeForCurrentUser(.pendingSessionFeedback)
        saveRunningSession(
            RunningMivoSession(
                id: UUID().uuidString,
                intention: feedback.intention,
                plannedDuration: addedMinutes,
                plannedSeconds: addedSeconds,
                startTime: formatter.string(from: now),
                urgeReason: feedback.urgeReason,
                urgeNote: feedback.urgeNote,
                extendedOnce: true,
                emergencyUnlockUsed: feedback.emergencyUnlockUsed == true || hasEmergencyReason,
                emergencyUnlockReason: hasEmergencyReason ? emergencyReason : feedback.emergencyUnlockReason,
                approvedSeconds: addedSeconds,
                expiresAt: formatter.string(from: now.addingTimeInterval(TimeInterval(addedSeconds))),
                expiredAt: nil,
                expirationSource: nil,
                accumulatedElapsedSeconds: 0,
                originalStartTime: formatter.string(from: now)
            )
        )
        return result
    }

    var isAdminUser: Bool {
        user?.isAdmin == true
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
        scheduleTimeTruthNotification()
    }

    func dismissTimeTruthPrompt() {
        pendingTimeTruthPrompt = nil
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
        if let a = partial.age { onboardingProfile.age = a }
        if let ar = partial.ageRange { onboardingProfile.ageRange = ar }
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

        let summary = parts.joined(separator: " | ")
        appendAISummary(summary)
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
        pendingTimeTruthPrompt = nil
        isLoggedIn = false
        _ = FamilyControlsManager.shared.setMivoSessionActive(false)
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
        let pending = FamilyControlsManager.shared.consumePendingInterventionSetup()
        if pending {
            guard !mivoLaunchGateActive else { return false }
            mivoLaunchGateActive = true
        }
        return pending
    }

    @discardableResult
    func markMivoLaunchSessionStarted(plannedMinutes: Int = 0) -> MivoSessionActivationResult {
        let result = FamilyControlsManager.shared.setMivoSessionActive(true, plannedMinutes: plannedMinutes, exactDurationSeconds: max(1, plannedMinutes) * 60)
        guard result.success else { return result }
        mivoLaunchGateActive = false
        return result
    }

    @discardableResult
    func markMivoSessionActiveFor(seconds: Int) -> MivoSessionActivationResult {
        let result = FamilyControlsManager.shared.setMivoSessionActive(true, exactDurationSeconds: max(1, seconds))
        guard result.success else { return result }
        mivoLaunchGateActive = false
        return result
    }

    func finishMivoSession(requiresReview: Bool = false) {
        if requiresReview {
            FamilyControlsManager.shared.endSessionAndRelockForIntervention()
            return
        }
        pendingSessionFeedback = nil
        removeForCurrentUser(.pendingSessionFeedback)
        clearRunningSession()
        _ = FamilyControlsManager.shared.setMivoSessionActive(false)
    }

    func sessionExtensionDecision(
        intention: Intention,
        plannedMinutes: Int,
        elapsedSeconds: Int,
        extensionUsed: Bool,
        requestedMinutes: Int? = nil,
        now: Date = Date()
    ) -> SessionExtensionDecision {
        let plan = adaptiveScreenTimePlan()
        let ruleMode = protectedGroupRuleMode()
        let actualMinutes = max(1, Int(ceil(Double(elapsedSeconds) / 60.0)))
        let requestedAddMinutes = min(max(requestedMinutes ?? 5, 1), 60)

        if ruleMode == .looseTracking {
            return SessionExtensionDecision(
                allowed: true,
                addedMinutes: requestedAddMinutes,
                title: "\(requestedAddMinutes) more \(requestedAddMinutes == 1 ? "minute" : "minutes") approved",
                message: "This protected group is set to loose tracking, so Mivo records the choice without making the intervention stricter."
            )
        }

        guard !plan.collecting || ruleMode == .plannedWindowsOnly else {
            return SessionExtensionDecision(
                allowed: true,
                addedMinutes: requestedAddMinutes,
                title: "\(requestedAddMinutes) more \(requestedAddMinutes == 1 ? "minute" : "minutes") approved",
                message: "Mivo is still learning your real scroll pattern. You can add a little time, and this session will help the adaptive plan get smarter."
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

        guard activeWindow != nil else {
            return SessionExtensionDecision(
                allowed: false,
                addedMinutes: 0,
                title: "Come back later",
                message: nextScrollWindowMessage(for: plan, now: now, fallback: "Mivo has enough metrics now. Save this session and come back during your next planned scroll window.")
            )
        }

        let projectedToday = todaysTotalMinutes + actualMinutes
        let remainingTarget = plan.targetMinutes - projectedToday

        guard remainingTarget >= 1 else {
            return SessionExtensionDecision(
                allowed: false,
                addedMinutes: 0,
                title: "That is enough for now",
                message: nextScrollWindowMessage(for: plan, now: now, fallback: "Mivo has enough data and you are at today's adaptive target. Save this session before the scroll turns automatic.")
            )
        }

        let added = min(requestedAddMinutes, remainingTarget)
        return SessionExtensionDecision(
            allowed: true,
            addedMinutes: added,
            title: "\(added) more \(added == 1 ? "minute" : "minutes") approved",
            message: added == requestedAddMinutes
                ? "This still fits inside today's adaptive plan. Mivo will lock the app again when the added time ends."
                : "Mivo can only approve \(added) more \(added == 1 ? "minute" : "minutes") inside today's adaptive plan."
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
        guard !plan.collecting else {
            let baselineCap = min(30, max(5, plan.baselineMinutes / 4))
            return (
                maxMinutes: baselineCap,
                isLimited: baselineCap < 30,
                message: "Mivo is still learning, so this setup is capped at \(baselineCap) min instead of leaving 30 min open every time.",
                windowTitle: "Learning cap"
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
        let maxMinutes = min(30, remainingInWindow, remainingToday)
        let windowLength = max(1, activeWindow.endHour - activeWindow.startHour)
        let windowText = "\(activeWindow.title) - \(windowLength)h window"

        guard maxMinutes > 0 else {
            return (
                maxMinutes: 0,
                isLimited: true,
                message: nextScrollWindowMessage(
                    for: plan,
                    now: now,
                    fallback: "You already used this scroll window. Save the session and come back at the next planned time."
                ),
                windowTitle: windowText
            )
        }

        let message = "\(maxMinutes) min left in this \(windowLength)-hour window. Mivo is using your adaptive plan, not the old always-30-minute choice."

        return (maxMinutes: maxMinutes, isLimited: true, message: message, windowTitle: windowText)
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
        return "Mivo has enough data now. Come back at \(formatter.string(from: nextDate)) and scroll up to \(nextWindow.minutes) minutes inside that \(windowLength)-hour window."
    }

    func adaptiveScreenTimePlan() -> ScreenTimeReductionPlan {
        AIService.makeScreenTimeReductionPlan(
            sessions: sessions,
            truthChecks: truthChecks,
            todayScreenTimeMinutes: deviceActivityMinutesToday,
            profile: onboardingProfile
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

    private func timeTruthSchedule() -> (hour: Int, minute: Int) {
        let activeDates = Set(sessions.map(\.date))
        guard activeDates.count >= 3 || truthChecks.count >= 3 else {
            return (20, 0)
        }

        var buckets: [String: Int] = [
            "morning": 0,
            "afternoon": 0,
            "evening": 0,
            "night": 0
        ]

        let calendar = Calendar.current
        let formatter = ISO8601DateFormatter()

        for session in sessions {
            guard let start = formatter.date(from: session.startTime) else { continue }
            let hour = calendar.component(.hour, from: start)
            let weight = max(session.actualDuration, 1)

            if hour >= 21 || hour < 6 {
                buckets["night", default: 0] += weight
            } else if hour < 12 {
                buckets["morning", default: 0] += weight
            } else if hour < 17 {
                buckets["afternoon", default: 0] += weight
            } else {
                buckets["evening", default: 0] += weight
            }
        }

        let strongest = buckets.max(by: { $0.value < $1.value })?.key ?? "evening"
        switch strongest {
        case "morning":
            return (8, 0)
        case "afternoon":
            return (15, 0)
        case "night":
            return (22, 0)
        default:
            return (20, 0)
        }
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
    func loadDeviceActivityReport() {
        if #available(iOS 16.0, *) {
            let collector = ScreenTimeDataCollector.shared
            
            if let report = collector.latestReport {
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
            // Keep the last readable Apple report on screen while DeviceActivityReport reloads.
            // Otherwise the UI flashes to an empty/unreadable state whenever iOS rebuilds the report extension.
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
        // Idempotent: never stack a second observer or polling timer.
        guard deviceActivityObserver == nil, deviceActivityPollTimer == nil else { return }

        // Listen for updates from Screen Time collector
        deviceActivityObserver = NotificationCenter.default.addObserver(forName: Notification.Name("mivoDeviceActivityDidUpdate"), object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.loadDeviceActivityReport()
            }
        }

        // Set up a timer to poll for updates every 5 minutes
        deviceActivityPollTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
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
            } catch AppError.remoteAuthUnavailable {
                // Keep the local fallback only for offline development or cached local-only accounts.
            } catch {
                throw error
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

    private func applyRestrictionState(for email: String) {
        FamilyControlsManager.shared.setSignedInForImpulseProtection(true)
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
    case passwordResetUnavailable
    case socialSignInFailed
    case socialSignInUnavailable

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
        case .passwordResetUnavailable: return "Password reset needs verified email recovery before it can be used."
        case .socialSignInFailed: return "We couldn't verify that sign-in. Please try again."
        case .socialSignInUnavailable: return "Google and Apple sign-in need the online Mivo account server."
        }
    }
}
