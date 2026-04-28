import Foundation
import SwiftUI

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
    @Published var pendingTwoFactorChallenge: TwoFactorChallenge? = nil

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
        isLoading = false
    }

    // MARK: - Auth

    func login(email: String, password: String) throws {
        guard var record = SecureAuthService.loadRecord() else {
            throw AppError.noAccount
        }
        guard record.email == email, SecureAuthService.verifyPassword(password, for: record) else {
            throw AppError.invalidCredentials
        }
        guard record.emailVerified != false else {
            throw AppError.emailNotVerified
        }

        if record.passwordIterations == 0 {
            record = try SecureAuthService.updatePassword(password, for: record)
        }

        try completeLogin(email: email)
    }

    func completeLogin(email: String) throws {
        guard let record = SecureAuthService.loadRecord(), record.email == email else {
            throw AppError.accountDataMissing
        }
        StorageService.save("1", forKey: .authSession)
        user = UserProfile(
            email: record.email,
            name: record.name,
            createdAt: record.createdAt,
            onboardingProfile: record.onboardingProfile
        )
        isLoggedIn = true

        // Restore any saved onboarding profile for this user
        if let userOnboard = record.onboardingProfile {
            onboardingProfile = userOnboard
        } else {
            onboardingProfile = OnboardingProfile()
        }
    }

    func beginRegistration(email: String, password: String, name: String) async throws -> TwoFactorChallenge {
        if let existing = SecureAuthService.loadRecord(), existing.email == email {
            throw AppError.emailAlreadyExists
        }
        let record = try SecureAuthService.createRecord(
            email: email,
            password: password,
            name: name.isEmpty ? String(email.split(separator: "@").first ?? Substring(email)) : name
        )

        let profile = UserProfile(email: record.email, name: record.name, createdAt: record.createdAt)
        StorageService.save(profile, forKey: .user)

        // New account: ensure onboarding runs
        settings.onboardingComplete = false
        StorageService.save(settings, forKey: .settings)

        // Reset onboarding profile for fresh user
        onboardingProfile = OnboardingProfile()

        return try await sendTwoFactorChallenge(email: email, purpose: .registration)
    }

    func logout() {
        // Offload storage mutation to background to avoid blocking the UI
        DispatchQueue.global(qos: .userInitiated).async {
            StorageService.remove(forKey: .authSession)
            // Update published state on main actor
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.user = nil
                self.isLoggedIn = false
            }
        }
    }

    // MARK: - Sessions

    func addSession(_ session: Session) {
        sessions.append(session)
        StorageService.save(sessions, forKey: .sessions)
    }

    func addTruthCheck(guess: Int) {
        let today = todayKey()
        let actual = todaysSessions.reduce(0) { $0 + $1.actualDuration }
        let check = TruthCheckGuess(
            id: UUID().uuidString,
            date: today,
            guess: guess,
            actual: actual
        )
        truthChecks.append(check)
        StorageService.save(truthChecks, forKey: .truthChecks)
    }

    // MARK: - Onboarding

    func completeOnboarding() {
        // Set flag
        settings.onboardingComplete = true
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
        pendingTwoFactorChallenge = nil

        StorageService.remove(forKey: .user)
        StorageService.remove(forKey: .credentials)
        StorageService.remove(forKey: .authSession)
        StorageService.remove(forKey: .settings)
        StorageService.remove(forKey: .onboardingProfile)
        StorageService.remove(forKey: .aiDataset)

        user = nil
        settings = AppSettings(onboardingComplete: false, notificationsEnabled: false)
        onboardingProfile = OnboardingProfile()
        isLoggedIn = false

        // Offload heavier history deletion to background, update published state on main when done.
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            StorageService.remove(forKey: .sessions)
            StorageService.remove(forKey: .truthChecks)
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.sessions = []
                self.truthChecks = []
            }
        }
    }

    func completeTutorial() {
        settings.tutorialComplete = true
        let updated = settings
        settings = updated
        StorageService.save(settings, forKey: .settings)
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

    // MARK: - Helpers

    func todayKey() -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt.string(from: Date())
    }

    // Load Screen Time data from the collector or fallback sources
    func loadDeviceActivityReport() {
        if #available(iOS 16.0, *) {
            // Try to get data from Screen Time collector
            let collector = ScreenTimeDataCollector.shared
            
            if let report = collector.latestReport {
                // Use real Screen Time data
                deviceActivityMinutesToday = report.totalMinutes
                deviceActivityPerAppSeconds = report.perAppSeconds
                deviceActivityReportGeneratedAt = report.generatedAt
                
                // Store as JSON for backward compatibility
                if let encoded = try? JSONSerialization.data(withJSONObject: report.toJSON(), options: []),
                   let jsonString = String(data: encoded, encoding: .utf8) {
                    lastDeviceActivityReportJSON = jsonString
                    
                    // Also save to UserDefaults for persistence
                    if let ud = UserDefaults(suiteName: "group.com.mivo.mivoapp") {
                        ud.set(jsonString, forKey: "mivo.lastDeviceActivityReport")
                        ud.synchronize()
                    }
                }
                return
            }
        }
        
        // Fallback: Use the app group data (if extension wrote it)
        let ud = UserDefaults(suiteName: "group.com.mivo.mivoapp")
        lastDeviceActivityReportJSON = ud?.string(forKey: "mivo.lastDeviceActivityReport")

        // Parse the JSON and compute an aggregate minutes value for display
        guard let raw = lastDeviceActivityReportJSON, let data = raw.data(using: .utf8) else {
            deviceActivityMinutesToday = nil
            deviceActivityPerAppSeconds = [:]
            deviceActivityReportGeneratedAt = nil
            return
        }
        do {
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let generatedAt = json["generatedAt"] as? String {
                    deviceActivityReportGeneratedAt = ISO8601DateFormatter().date(from: generatedAt)
                } else {
                    deviceActivityReportGeneratedAt = nil
                }

                if let perApp = json["perAppSeconds"] as? [String: Any] {
                    var normalized: [String: Int] = [:]
                    for (bundleID, value) in perApp {
                        if let seconds = value as? Int {
                            normalized[bundleID] = seconds
                        } else if let seconds = value as? Double {
                            normalized[bundleID] = Int(seconds)
                        } else if let seconds = value as? String, let parsed = Int(seconds) {
                            normalized[bundleID] = parsed
                        }
                    }
                    deviceActivityPerAppSeconds = normalized
                } else {
                    deviceActivityPerAppSeconds = [:]
                }

                // Prefer explicit totalSeconds field when the extension provides it
                if let total = json["totalSeconds"] as? Int {
                    deviceActivityMinutesToday = Int((Double(total) / 60.0).rounded())
                    return
                }
                // Expecting shape: { "perAppSeconds": { "bundle.id": 123, ... } }
                if let perApp = json["perAppSeconds"] as? [String: Any] {
                    var totalSeconds = 0
                    for (_, v) in perApp {
                        if let n = v as? Int { totalSeconds += n }
                        else if let d = v as? Double { totalSeconds += Int(d) }
                        else if let s = v as? String, let iv = Int(s) { totalSeconds += iv }
                    }
                    // convert to rounded minutes
                    let minutes = Int((Double(totalSeconds) / 60.0).rounded())
                    deviceActivityMinutesToday = minutes
                    return
                }
            }
        } catch {
            // parsing failed — clear device metric but keep raw JSON visible for debugging
            deviceActivityMinutesToday = nil
            deviceActivityPerAppSeconds = [:]
            deviceActivityReportGeneratedAt = nil
            return
        }
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

    func verifyTwoFactorCode(_ code: String, for challenge: TwoFactorChallenge) throws {
        guard pendingTwoFactorChallenge?.id == challenge.id, challenge.verifies(code) else {
            throw AppError.invalidVerificationCode
        }

        switch challenge.purpose {
        case .registration:
            if var record = SecureAuthService.loadRecord(), record.email == challenge.email {
                record.emailVerified = true
                try SecureAuthService.saveRecord(record)
            }
            try completeLogin(email: challenge.email)
        case .login:
            try completeLogin(email: challenge.email)
        case .passwordReset:
            break
        }

        pendingTwoFactorChallenge = nil
    }

    func resendTwoFactorCode(for challenge: TwoFactorChallenge) async throws {
        guard challenge.purpose != .registration else {
            throw AppError.registrationCodeAlreadySent
        }
        _ = try await sendTwoFactorChallenge(email: challenge.email, purpose: challenge.purpose)
    }

    func beginPasswordReset(email: String) async throws -> TwoFactorChallenge {
        guard let record = SecureAuthService.loadRecord(), record.email == email else {
            throw AppError.noAccount
        }
        return try await sendTwoFactorChallenge(email: email, purpose: .passwordReset)
    }

    func completePasswordReset(code: String, newPassword: String, challenge: TwoFactorChallenge) throws {
        guard pendingTwoFactorChallenge?.id == challenge.id, challenge.verifies(code) else {
            throw AppError.invalidVerificationCode
        }
        guard newPassword.count >= 8 else {
            throw AppError.weakPassword
        }
        guard let record = SecureAuthService.loadRecord(), record.email == challenge.email else {
            throw AppError.noAccount
        }

        _ = try SecureAuthService.updatePassword(newPassword, for: record)
        StorageService.remove(forKey: .authSession)
        pendingTwoFactorChallenge = nil
    }

    private func sendTwoFactorChallenge(email: String, purpose: TwoFactorChallenge.Purpose) async throws -> TwoFactorChallenge {
        let result = SecureAuthService.makeChallenge(email: email, purpose: purpose)
        pendingTwoFactorChallenge = result.challenge
        try await EmailVerificationService.send(code: result.code, to: email, purpose: purpose)
        return result.challenge
    }
}

// MARK: - Errors

enum AppError: LocalizedError {
    case noAccount
    case invalidCredentials
    case accountDataMissing
    case emailAlreadyExists
    case invalidVerificationCode
    case weakPassword
    case secureStorageFailed
    case emailDeliveryUnavailable
    case emailNotVerified
    case registrationCodeAlreadySent

    var errorDescription: String? {
        switch self {
        case .noAccount: return "No account found. Please create one."
        case .invalidCredentials: return "Invalid email or password."
        case .accountDataMissing: return "Account data missing. Please register again."
        case .emailAlreadyExists: return "An account with this email already exists."
        case .invalidVerificationCode: return "That verification code is invalid or expired."
        case .weakPassword: return "Password must be at least 8 characters."
        case .secureStorageFailed: return "Could not save credentials securely."
        case .emailDeliveryUnavailable: return "Email delivery is not configured yet."
        case .emailNotVerified: return "Please verify your email from the code sent during registration."
        case .registrationCodeAlreadySent: return "Registration codes are sent once when you create the account."
        }
    }
}
