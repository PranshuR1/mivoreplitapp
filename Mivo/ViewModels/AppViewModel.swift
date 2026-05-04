import Foundation
import SwiftUI
@preconcurrency import UserNotifications

@MainActor
class AppViewModel: ObservableObject {
    @Published var user: UserProfile? = nil
    @Published var sessions: [Session] = []
    @Published var truthChecks: [TruthCheckGuess] = []
    @Published var settings: AppSettings = AppSettings(onboardingComplete: false, notificationsEnabled: false)
    @Published var onboardingProfile: OnboardingProfile = OnboardingProfile()
    @Published var isLoading: Bool = true

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
                onboardingProfile: authRecord.onboardingProfile
            )
            isLoggedIn = true
            FamilyControlsManager.shared.setSignedInForImpulseProtection(true)
        } else {
            FamilyControlsManager.shared.setSignedInForImpulseProtection(false)
        }
        if let savedSessions = StorageService.load([Session].self, forKey: .sessions) {
            sessions = savedSessions
        }
        if let savedTruth = StorageService.load([TruthCheckGuess].self, forKey: .truthChecks) {
            truthChecks = savedTruth
        }
        if let savedSettings = StorageService.load(AppSettings.self, forKey: .settings) {
            settings = savedSettings
        }
        if let savedProfile = StorageService.load(OnboardingProfile.self, forKey: .onboardingProfile) {
            onboardingProfile = savedProfile
        }
        pendingSessionFeedback = StorageService.load(PendingSessionFeedback.self, forKey: .pendingSessionFeedback)
        isLoading = false
    }

    // MARK: - Auth

    func login(email: String, password: String, rememberMe: Bool = true) async throws {
        if RemoteAuthService.isConfigured {
            let remoteUser = try await RemoteAuthService.login(email: email, password: password)
            try cacheRemoteUser(remoteUser, password: password)
            try completeLogin(email: remoteUser.email, persistSession: rememberMe)
            return
        }

        guard var record = SecureAuthService.loadRecord() else {
            throw AppError.noAccount
        }
        guard record.email == email, SecureAuthService.verifyPassword(password, for: record) else {
            throw AppError.invalidCredentials
        }

        if record.passwordIterations == 0 {
            record = try SecureAuthService.updatePassword(password, for: record)
        }

        try completeLogin(email: email, persistSession: rememberMe)
    }

    func completeLogin(email: String, persistSession: Bool = true) throws {
        guard let record = SecureAuthService.loadRecord(), record.email == email else {
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
            onboardingProfile: record.onboardingProfile
        )
        isLoggedIn = true
        FamilyControlsManager.shared.setSignedInForImpulseProtection(true)

        // Restore any saved onboarding profile for this user
        if let userOnboard = record.onboardingProfile {
            onboardingProfile = userOnboard
        } else {
            onboardingProfile = OnboardingProfile()
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
        StorageService.save(settings, forKey: .settings)
        onboardingProfile = OnboardingProfile()
        try completeLogin(email: normalizedEmail)
    }

    private func registerLocallyDirectly(email: String, password: String, displayName: String) throws {
        if let existing = SecureAuthService.loadRecord(), existing.email == email {
            throw AppError.emailAlreadyExists
        }
        let record = try SecureAuthService.createRecord(email: email, password: password, name: displayName)
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
                self.isLoggedIn = false
            }
        }
    }

    // MARK: - Sessions

    func addSession(_ session: Session) {
        sessions.append(session)
        StorageService.save(sessions, forKey: .sessions)
        scheduleTimeTruthNotification()
        NotificationCenter.default.post(name: .mivoSessionHistoryDidUpdate, object: nil)
    }

    func savePendingSessionFeedback(_ feedback: PendingSessionFeedback) {
        pendingSessionFeedback = feedback
        StorageService.save(feedback, forKey: .pendingSessionFeedback)
    }

    func clearPendingSessionFeedback() {
        pendingSessionFeedback = nil
        StorageService.remove(forKey: .pendingSessionFeedback)
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
        StorageService.save(truthChecks, forKey: .truthChecks)
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
        StorageService.save(truthChecks, forKey: .truthChecks)
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
        if StorageService.load(String.self, forKey: .timeTruthNotificationSchedule) == scheduleKey {
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
                    StorageService.save(scheduleKey, forKey: .timeTruthNotificationSchedule)
                    self?.settings.notificationsEnabled = true
                    if let updated = self?.settings {
                        StorageService.save(updated, forKey: .settings)
                    }
                }
            }
        }
    }

    // MARK: - Onboarding

    func completeOnboarding() {
        // Set flag
        settings.onboardingComplete = true
        settings.tutorialComplete = false
        // Reassign to force @Published notifications in case of in-place mutation
        let updated = settings
        settings = updated
        StorageService.save(settings, forKey: .settings)

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
        StorageService.save(onboardingProfile, forKey: .onboardingProfile)

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
        var entries = StorageService.load([String].self, forKey: .aiDataset) ?? []
        entries.insert(summary, at: 0)
        if entries.count > 50 { entries = Array(entries.prefix(50)) }
        StorageService.save(entries, forKey: .aiDataset)
    }

    func resetAllData() {
        SecureAuthService.deleteRecord()
        mivoLaunchGateActive = false

        StorageService.remove(forKey: .user)
        StorageService.remove(forKey: .credentials)
        StorageService.remove(forKey: .authSession)
        StorageService.remove(forKey: .rememberedEmail)
        StorageService.remove(forKey: .settings)
        StorageService.remove(forKey: .onboardingProfile)
        StorageService.remove(forKey: .pendingSessionFeedback)
        StorageService.remove(forKey: .timeTruthNotificationSchedule)
        StorageService.remove(forKey: .aiDataset)

        user = nil
        settings = AppSettings(onboardingComplete: false, notificationsEnabled: false)
        onboardingProfile = OnboardingProfile()
        pendingSessionFeedback = nil
        pendingTimeTruthPrompt = nil
        isLoggedIn = false
        FamilyControlsManager.shared.setMivoSessionActive(false)
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
        StorageService.save(settings, forKey: .settings)
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
            mivoLaunchGateActive = true
        }
        return pending
    }

    func markMivoLaunchSessionStarted(plannedMinutes: Int = 0) {
        FamilyControlsManager.shared.setMivoSessionActive(true, plannedMinutes: plannedMinutes, exactDurationSeconds: max(1, plannedMinutes) * 60)
        mivoLaunchGateActive = false
    }

    func markMivoSessionActiveFor(seconds: Int) {
        FamilyControlsManager.shared.setMivoSessionActive(true, exactDurationSeconds: max(1, seconds))
        mivoLaunchGateActive = false
    }

    func finishMivoSession() {
        FamilyControlsManager.shared.setMivoSessionActive(false)
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
                return
            }
        }

        lastDeviceActivityReportJSON = nil
        deviceActivityMinutesToday = nil
        deviceActivityPerAppSeconds = [:]
        deviceActivityReportGeneratedAt = nil
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

    // MARK: - Secure Auth

    func resetPasswordWithoutVerification(email: String, newPassword: String) async throws {
        let normalizedEmail = email.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard newPassword.count >= 8 else {
            throw AppError.weakPassword
        }

        if RemoteAuthService.isConfigured {
            do {
                try await RemoteAuthService.resetPassword(email: normalizedEmail, newPassword: newPassword)
                if var record = SecureAuthService.loadRecord(), record.email == normalizedEmail {
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

        guard var record = SecureAuthService.loadRecord(), record.email == normalizedEmail else {
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
        try SecureAuthService.saveRecord(record)
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

    var errorDescription: String? {
        switch self {
        case .noAccount: return "No account found. Please create one."
        case .invalidCredentials: return "Invalid email or password."
        case .accountDataMissing: return "Account data missing. Please register again."
        case .emailAlreadyExists: return "An account with this email already exists."
        case .weakPassword: return "Password must be at least 8 characters."
        case .secureStorageFailed: return "Could not save credentials securely."
        case .remoteAuthUnavailable: return "The online Mivo account server is not reachable yet."
        }
    }
}
