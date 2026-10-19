import Foundation
import SwiftUI
import UserNotifications
@preconcurrency import UserNotifications
#if canImport(WidgetKit)
import WidgetKit
#endif

private let autoFinishExpiredSessionDelay: TimeInterval = 5 * 60
private let internalDataFreshStartMarker = "mivo_internal_data_fresh_start_2026_05_29_v1"

enum LiveActivityDeepLinkAction: String {
    case finish
    case addTime
}

@MainActor
class AppViewModel: ObservableObject {
    @Published var user: UserProfile? = nil
    @Published var sessions: [Session] = []
    @Published var truthChecks: [TruthCheckGuess] = []
    @Published var recallCheckIns: [RecallCheckIn] = []
    @Published var instagramWrapperSessions: [InstagramWrapperSession] = []
    @Published var instagramRecallPrompts: [InstagramRecallPrompt] = []
    @Published var dailyScreenTimeObservations: [DailyScreenTimeObservation] = []
    @Published var dailyScrollSchedules: [DailyScrollSchedule] = []
    @Published var weeklyReports: [WeeklyReportSnapshot] = []
    @Published var appInterventionRules: [AppInterventionRule] = []
    @Published var weeklyExperiments: [WeeklyExperiment] = []
    @Published var interventionAttempts: [InterventionAttemptRecord] = []
    @Published var settings: AppSettings = AppSettings(onboardingComplete: false, notificationsEnabled: false)
    @Published var onboardingProfile: OnboardingProfile = OnboardingProfile()
    @Published var isLoading: Bool = true
    @Published var adminToken: String? = nil

    // Navigation state
    @Published var showOnboarding: Bool = false
    @Published var onboardingReplayActive: Bool = false
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
    @Published var pendingScrollGoalPrompt: ScrollGoalPrompt? = nil
    @Published var pendingGoalForecastPrompt: GoalForecastPrompt? = nil
    /// Offer to restart the plan for someone who has been away (or who wants a
    /// clean slate). Logic lives in `AppViewModel+Comeback.swift`.
    @Published var pendingComebackPrompt: ComebackPrompt? = nil
    @Published var comebackAnchor: ComebackAnchor? = nil
    @Published var comebackLapse: ComebackLapseRecord? = nil
    /// The periodic "rate us / give feedback" card. No payload needed — see
    /// `MivoRatingPromptStore` for the every-two-days, stops-when-acted-on logic.
    @Published var showRatingPrompt = false
    /// The user's pre-committed real-world substitute for opening a blocked
    /// app — see `evaluateSwapPrompt()` for how existing users are asked once.
    @Published var userSwap: UserSwap? = nil
    @Published var showSwapPrompt = false
    /// Google/Apple sign-in falls back to the email prefix as the display
    /// name when the provider doesn't return one — see `evaluateNamePrompt()`
    /// for the ask-once gating that catches it.
    @Published var showNamePrompt = false
    @Published var sessionActivationError: String? = nil
    /// Set to true when the shield "Open Mivo" button triggers a deep link
    @Published var deepLinkInterventionRequested: Bool = false
    /// Mid-session "still want to keep scrolling?" check-in — see
    /// `checkMidScrollCheckInFlag()`.
    @Published var pendingMidScrollCheckIn: Bool = false
    /// Best-effort app name for the check-in currently presenting, read
    /// alongside the flag itself in `checkMidScrollCheckInFlag()`. Nil is
    /// expected and handled — the recall prompt just asks generically.
    @Published var pendingMidScrollCheckInAppName: String? = nil
    @Published var pendingInstagramWrapper: Bool = false
    /// Set when an App Store event or universal link should open the Referral Hub.
    @Published var deepLinkReferralHubRequested: Bool = false
    @Published var pendingMivoClearRoute: MivoClearRoute? = nil
    @Published var liveActivityDeepLinkAction: LiveActivityDeepLinkAction? = nil
    private var remoteSyncTask: Task<Void, Never>? = nil

    init() {
        performInternalFreshStartIfNeeded()
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

    private func performInternalFreshStartIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: internalDataFreshStartMarker) else { return }
        StorageService.removeAllMivoData()
        SecureAuthService.deleteAllRecords()
        UserDefaults.standard.set(true, forKey: internalDataFreshStartMarker)
    }

    /// `loadUserScopedData` decodes every locally-cached array for the
    /// account — sessions, truth checks, weekly reports, intervention
    /// attempts, and more — none of which are capped in size. For an
    /// account with real history this can genuinely take a few seconds of
    /// synchronous `JSONDecoder` work, and this used to run inline inside
    /// `init()`, which SwiftUI must finish before it can render *anything*
    /// — not even `SplashView` — since the root `AppViewModel` is a
    /// `@StateObject` the whole view tree depends on. That's why the app
    /// looked frozen (nothing painted, not even a spinner) for however
    /// long the decode took, rather than showing a normal loading state.
    ///
    /// Deferring the authenticated branch into a `Task` doesn't make the
    /// decode itself faster, but it lets SwiftUI paint at least one frame
    /// — `SplashView`, gated on `isLoading` — before that work runs, so
    /// the wait reads as "loading" instead of "hung."
    func loadData() {
        guard StorageService.exists(forKey: .authSession),
              let authRecord = SecureAuthService.loadRecord() else {
            adminToken = nil
            resetUserScopedState()
            FamilyControlsManager.shared.setLearningModeUnlocked(false)
            FamilyControlsManager.shared.setSignedInForImpulseProtection(false)
            recoverExpiredRunningSessionIfNeeded()
            isLoading = false
            return
        }

        user = UserProfile(
            email: authRecord.email,
            name: authRecord.name,
            createdAt: authRecord.createdAt,
            onboardingProfile: authRecord.onboardingProfile,
            isAdmin: authRecord.isAdmin,
            accountRole: authRecord.accountRole
        )
        adminToken = authRecord.adminToken
        isLoggedIn = true
        isLoading = true

        Task { [weak self] in
            guard let self else { return }
            self.loadUserScopedData(for: authRecord.email)
            self.syncLearningModeProtectionState()
            self.applyRestrictionState(for: authRecord.email)
            self.validateActiveRemoteSessionIfNeeded(email: authRecord.email)
            self.recoverExpiredRunningSessionIfNeeded()
            self.isLoading = false
        }
    }

    private func resetUserScopedState() {
        sessions = []
        truthChecks = []
        recallCheckIns = []
        instagramWrapperSessions = []
        instagramRecallPrompts = []
        dailyScreenTimeObservations = []
        dailyScrollSchedules = []
        weeklyReports = []
        appInterventionRules = defaultAppInterventionRules()
        weeklyExperiments = []
        interventionAttempts = []
        settings = AppSettings(onboardingComplete: false, notificationsEnabled: false)
        onboardingProfile = OnboardingProfile()
        pendingSessionFeedback = nil
        pendingExpiredRunningSession = nil
        pendingTimeTruthPrompt = nil
        pendingDailyScrollSchedulePrompt = nil
        pendingComebackPrompt = nil
        comebackAnchor = nil
        comebackLapse = nil
        syncWeeklyExperimentEnforcement()

        // Every screen in this app requires being signed in — there's no
        // local-only mode the way Mac/Windows have — so this function
        // running is the one place that always corresponds to "no longer
        // signed in," whether that's an explicit logout or a background
        // session-revalidation failure. Any notification scheduled while
        // signed in (session end, check-in, Still Lock, etc.) is an
        // `UNUserNotificationCenter` request that lives entirely outside
        // this app's process — it does not know or care that the account
        // just signed out, and would otherwise still fire on schedule.
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
    }

    /// Current version of the day-key repair. Bump only if a later change makes
    /// another pass necessary.
    private static let dayKeyRepairVersion = 1

    /// Rewrites records whose day key was written under the device's own
    /// calendar rather than a Gregorian one.
    ///
    /// Runs immediately after load and before anything derives a plan, a report
    /// or a streak from these arrays, so no screen ever sees the half-repaired
    /// state. It is a no-op — and costs one integer read — for the Gregorian
    /// devices that are the vast majority.
    @discardableResult
    private func repairDayKeysIfNeeded(for email: String) -> Int {
        let completed = StorageService.load(Int.self, forKey: .dayKeyRepairVersion, email: email) ?? 0
        guard completed < Self.dayKeyRepairVersion else { return 0 }

        var repaired = 0

        let fixedSessions = sessions.map { session -> Session in
            guard let fixed = session.repairingDayKey() else { return session }
            repaired += 1
            return fixed
        }
        let fixedTruthChecks = truthChecks.map { check -> TruthCheckGuess in
            guard let fixed = check.repairingDayKey() else { return check }
            repaired += 1
            return fixed
        }
        let fixedObservations = dailyScreenTimeObservations.map { observation -> DailyScreenTimeObservation in
            guard let fixed = observation.repairingDayKey() else { return observation }
            repaired += 1
            return fixed
        }
        let fixedSchedules = dailyScrollSchedules.map { schedule -> DailyScrollSchedule in
            guard let fixed = schedule.repairingDayKey() else { return schedule }
            repaired += 1
            return fixed
        }

        if repaired > 0 {
            // Sessions are legitimately many-per-day, so they are never merged.
            sessions = fixedSessions
            // A truth check is one per day by construction, and a repaired key
            // can land on a day that already has one.
            truthChecks = dedupedByDate(
                fixedTruthChecks, date: { $0.date }, recency: { $0.checkedAt ?? "" }
            ).sorted { $0.date > $1.date }
            // A repaired key can collide with a record already written under the
            // correct key. Observations and schedules are one-per-day, so keep
            // the newest and drop the duplicate rather than showing the day twice.
            dailyScreenTimeObservations = dedupedByDate(
                fixedObservations, date: { $0.date }, recency: { $0.recordedAt }
            ).sorted { $0.date > $1.date }
            dailyScrollSchedules = dedupedByDate(
                fixedSchedules, date: { $0.date }, recency: { $0.createdAt }
            ).sorted { $0.date > $1.date }

            StorageService.save(sessions, forKey: .sessions, email: email)
            StorageService.save(truthChecks, forKey: .truthChecks, email: email)
            StorageService.save(dailyScreenTimeObservations, forKey: .dailyScreenTimeObservations, email: email)
            StorageService.save(dailyScrollSchedules, forKey: .dailyScrollSchedules, email: email)
            appendAISummary("Repaired \(repaired) record(s) whose day key was stored under a non-Gregorian calendar.")
        }

        StorageService.save(Self.dayKeyRepairVersion, forKey: .dayKeyRepairVersion, email: email)
        return repaired
    }

    /// Keeps one record per day, preferring the most recently written.
    private func dedupedByDate<T>(_ values: [T], date: (T) -> String, recency: (T) -> String) -> [T] {
        var newest: [String: T] = [:]
        for value in values {
            let key = date(value)
            if let existing = newest[key], recency(existing) >= recency(value) { continue }
            newest[key] = value
        }
        return Array(newest.values)
    }

    private func loadUserScopedData(for email: String) {
        sessions = StorageService.load([Session].self, forKey: .sessions, email: email) ?? []
        truthChecks = StorageService.load([TruthCheckGuess].self, forKey: .truthChecks, email: email) ?? []
        recallCheckIns = StorageService.load([RecallCheckIn].self, forKey: .recallCheckIns, email: email) ?? []
        instagramWrapperSessions = StorageService.load([InstagramWrapperSession].self, forKey: .instagramWrapperSessions, email: email) ?? []
        instagramRecallPrompts = StorageService.load([InstagramRecallPrompt].self, forKey: .instagramRecallPrompts, email: email) ?? []
        dailyScreenTimeObservations = StorageService.load(
            [DailyScreenTimeObservation].self,
            forKey: .dailyScreenTimeObservations,
            email: email
        ) ?? []
        dailyScrollSchedules = StorageService.load([DailyScrollSchedule].self, forKey: .dailyScrollSchedules, email: email) ?? []
        weeklyReports = StorageService.load([WeeklyReportSnapshot].self, forKey: .weeklyReports, email: email) ?? []
        weeklyExperiments = StorageService.load([WeeklyExperiment].self, forKey: .weeklyExperiments, email: email) ?? []
        interventionAttempts = StorageService.load([InterventionAttemptRecord].self, forKey: .interventionAttempts, email: email) ?? []
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
        userSwap = StorageService.load(UserSwap.self, forKey: .userSwap, email: email)
        comebackAnchor = StorageService.load(ComebackAnchor.self, forKey: .comebackAnchor, email: email)
        comebackLapse = StorageService.load(ComebackLapseRecord.self, forKey: .comebackLapse, email: email)
        repairDayKeysIfNeeded(for: email)

        let checkInMinutes = settings.checkInIntervalMinutes ?? onboardingProfile.checkInIntervalMinutes ?? 3
        settings.checkInIntervalMinutes = checkInMinutes
        FamilyControlsManager.shared.setCheckInIntervalMinutes(checkInMinutes)

        pendingSessionFeedback = StorageService.load(PendingSessionFeedback.self, forKey: .pendingSessionFeedback, email: email)
        pendingExpiredRunningSession = nil
        syncWeeklyExperimentEnforcement()
        DropPathTimeAdjustmentService.shared.prepare(for: self)
        DropPathTimeAdjustmentService.shared.applyPendingAdjustments(for: todayKey(), appVM: self)
    }

    func saveForCurrentUser<T: Encodable>(_ value: T, forKey key: StorageKey) {
        guard let email = user?.email else { return }
        StorageService.save(value, forKey: key, email: email)
        scheduleCurrentUserStateRemoteSync()
    }

    private func removeForCurrentUser(_ key: StorageKey) {
        guard let email = user?.email else { return }
        StorageService.remove(forKey: key, email: email)
        scheduleCurrentUserStateRemoteSync()
    }

    private func scheduleCurrentUserStateRemoteSync() {
        remoteSyncTask?.cancel()
        remoteSyncTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 900_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.remoteSyncTask = nil
                self?.performCurrentUserStateRemoteSync()
            }
        }
    }

    private func syncCurrentUserStateToRemote() {
        remoteSyncTask?.cancel()
        remoteSyncTask = nil
        performCurrentUserStateRemoteSync()
    }

    private func performCurrentUserStateRemoteSync() {
        guard RemoteAuthService.isConfigured,
              let currentUser = user,
              let record = SecureAuthService.loadRecord(email: currentUser.email),
              record.remoteAccessToken != nil else { return }

        let email = currentUser.email
        let snapshot = RemoteAuthService.UserStateSnapshot(
            profile: onboardingProfile,
            settings: settings,
            sessions: sessions,
            truthChecks: truthChecks,
            dailyScrollSchedules: dailyScrollSchedules,
            weeklyReports: weeklyReports,
            appInterventionRules: appInterventionRules,
            accountabilitySummary: StorageService.load(AccountabilitySummary.self, forKey: .accountabilitySummary, email: email),
            widgetSharedSummary: StorageService.load(WidgetSharedSummary.self, forKey: .widgetSharedSummary, email: email),
            aiDataset: StorageService.load([String].self, forKey: .aiDataset, email: email) ?? [],
            mivoStillSessions: MivoStillStore.shared.sessions,
            appFrictionProfiles: ProductExpansionStore.shared.appProfiles,
            userSwap: userSwap,
            interventionAttempts: interventionAttempts,
            dailyScreenTimeObservations: dailyScreenTimeObservations,
            timeLoans: TimeLoanService.shared.loans,
            intentGameHistory: IntentGameService.shared.history,
            dropPathTimeAdjustments: DropPathTimeAdjustmentService.shared.adjustments,
            recallCheckIns: recallCheckIns,
            instagramWrapperSessions: instagramWrapperSessions,
            instagramRecallPrompts: instagramRecallPrompts
        )

        Task {
            await RemoteAuthService.saveUserState(
                email: currentUser.email,
                name: currentUser.name,
                snapshot: snapshot,
                record: record
            )
        }
    }

    // MARK: - Auth

    func login(email: String, password: String, rememberMe: Bool = true) async throws {
        let normalizedEmail = email.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        if RemoteAuthService.isConfigured {
            do {
                let remoteUser = try await RemoteAuthService.login(email: normalizedEmail, password: password)
                let installationID = try DeviceBindingService.installationID()
                try await RemoteAuthService.claimDevice(installationID: installationID, user: remoteUser)
                try DeviceBindingService.bind(
                    userID: remoteUser.remoteUserId ?? normalizedEmail,
                    email: remoteUser.email,
                    replacingLocalBinding: true
                )
                try cacheRemoteUser(remoteUser, password: password)
                try completeLogin(email: remoteUser.email, persistSession: rememberMe, remoteSettings: remoteUser.settings, restoredState: remoteUser.restoredState)
                return
            } catch {
                throw error
            }
        }

        try DeviceBindingService.assertAllows(email: normalizedEmail)
        try completeLocalLogin(email: normalizedEmail, password: password, rememberMe: rememberMe)
    }

    /// Same device-binding/local-cache flow as `login(email:password:)`,
    /// entered from a Google ID token instead of an email/password pair —
    /// see `RemoteAuthService.loginWithGoogle`. A Google account has no
    /// Mivo password, so this generates a random one purely to fill the
    /// local keychain record's existing password-hash field; it's never
    /// shown to the user and never sent anywhere. Supabase's access/refresh
    /// tokens (cached in that same record) are what actually authenticate
    /// this account going forward, exactly as they are for a password
    /// account once it's signed in.
    func loginWithGoogle() async throws {
        guard RemoteAuthService.isConfigured else { throw AppError.remoteAuthUnavailable }
        let idToken = try await GoogleAuthService.signIn()
        let remoteUser = try await RemoteAuthService.loginWithGoogle(idToken: idToken)
        let installationID = try DeviceBindingService.installationID()
        do {
            try await RemoteAuthService.claimDevice(installationID: installationID, user: remoteUser)
        } catch AppError.remoteAuthUnavailable {
            throw AppError.googleSignInFailed("Google accepted your sign-in, but Mivo could not register this device with the server. Check your connection and try again.")
        } catch AppError.accountDataMissing {
            throw AppError.googleSignInFailed("Google accepted your sign-in, but the server did not return a usable account session. Try again.")
        }
        try DeviceBindingService.bind(
            userID: remoteUser.remoteUserId ?? remoteUser.email,
            email: remoteUser.email,
            replacingLocalBinding: true
        )
        try cacheRemoteUser(remoteUser, password: UUID().uuidString + UUID().uuidString)
        try completeLogin(
            email: remoteUser.email,
            persistSession: true,
            remoteSettings: remoteUser.settings,
            restoredState: remoteUser.restoredState
        )
    }

    /// Same shape as `loginWithGoogle()` above — `idToken`/`nonce` come
    /// from `LoginView`'s `SignInWithAppleButton` (see
    /// `RemoteAuthService.loginWithApple`). Apple accounts have no Mivo
    /// password either, so this generates the same kind of throwaway local
    /// password purely for the Keychain record's password-hash field.
    func loginWithApple(idToken: String, nonce: String) async throws {
        guard RemoteAuthService.isConfigured else { throw AppError.remoteAuthUnavailable }
        let remoteUser = try await RemoteAuthService.loginWithApple(idToken: idToken, nonce: nonce)
        let installationID = try DeviceBindingService.installationID()
        try await RemoteAuthService.claimDevice(installationID: installationID, user: remoteUser)
        try DeviceBindingService.bind(
            userID: remoteUser.remoteUserId ?? remoteUser.email,
            email: remoteUser.email,
            replacingLocalBinding: true
        )
        try cacheRemoteUser(remoteUser, password: UUID().uuidString + UUID().uuidString)
        try completeLogin(
            email: remoteUser.email,
            persistSession: true,
            remoteSettings: remoteUser.settings,
            restoredState: remoteUser.restoredState
        )
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

    /// `remoteSettings` is only ever non-nil right after a fresh Supabase
    /// login/refresh (see `RemoteAuthService.fetchSupabaseUserState`). It
    /// exists to cover a real gap: `AppSettings` — including
    /// `onboardingComplete` — was always pushed to the backend on every
    /// sync, but nothing ever pulled it back down on login, so a device that
    /// never locally cached it (a fresh install, most commonly after
    /// deleting and reinstalling the app) fell back to "onboarding not
    /// complete" and re-ran onboarding for an account that had already
    /// finished it. Applied the same way `record.onboardingProfile` already
    /// is a few lines below: only when this device truly has nothing cached
    /// yet, never overwriting real local state.
    func completeLogin(email: String, persistSession: Bool = true, remoteSettings: AppSettings? = nil, restoredState: RestoredUserState? = nil) throws {
        guard let record = SecureAuthService.loadRecord(email: email) else {
            throw AppError.accountDataMissing
        }
        try DeviceBindingService.assertAllows(email: record.email)
        try DeviceBindingService.bind(
            userID: record.remoteUserId ?? "local:\(record.email)",
            email: record.email
        )
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
            isAdmin: record.isAdmin,
            accountRole: record.accountRole
        )
        adminToken = record.adminToken
        isLoggedIn = true
        loadUserScopedData(for: record.email)
        syncLearningModeProtectionState()
        applyRestrictionState(for: record.email)
        syncCurrentUserStateToRemote()
        validateActiveRemoteSessionIfNeeded(email: record.email)
        Task { await refreshServerAdminRole() }

        // Restore any saved onboarding profile for this user
        if let userOnboard = record.onboardingProfile,
           !StorageService.exists(forKey: .onboardingProfile, email: record.email) {
            onboardingProfile = userOnboard
            StorageService.save(userOnboard, forKey: .onboardingProfile, email: record.email)
        }

        // Same restoration, for AppSettings (onboardingComplete above all) —
        // see the doc comment on this function for why this is needed.
        if let remoteSettings, !StorageService.exists(forKey: .settings, email: record.email) {
            settings = remoteSettings
            StorageService.save(remoteSettings, forKey: .settings, email: record.email)
        }

        // Same restoration again, for everything else `user_state` already
        // held in Supabase — `performCurrentUserStateRemoteSync()` has been
        // pushing sessions/truth checks/schedules/reports/rules/summaries on
        // every save, but until now nothing ever read them back, so a fresh
        // install + login silently lost all of it despite it already sitting
        // in the backend. Each field only fills in when this device has
        // never locally synced it, so it can't clobber a newer local edit.
        if let restoredState {
            if let remote = restoredState.sessions, !remote.isEmpty, !StorageService.exists(forKey: .sessions, email: record.email) {
                sessions = remote
                StorageService.save(remote, forKey: .sessions, email: record.email)
            }
            if let remote = restoredState.truthChecks, !remote.isEmpty, !StorageService.exists(forKey: .truthChecks, email: record.email) {
                truthChecks = remote
                StorageService.save(remote, forKey: .truthChecks, email: record.email)
            }
            if let remote = restoredState.recallCheckIns, !remote.isEmpty, !StorageService.exists(forKey: .recallCheckIns, email: record.email) {
                recallCheckIns = remote
                StorageService.save(remote, forKey: .recallCheckIns, email: record.email)
            }
            if let remote = restoredState.instagramWrapperSessions, !remote.isEmpty, !StorageService.exists(forKey: .instagramWrapperSessions, email: record.email) {
                instagramWrapperSessions = remote
                StorageService.save(remote, forKey: .instagramWrapperSessions, email: record.email)
            }
            if let remote = restoredState.instagramRecallPrompts, !remote.isEmpty, !StorageService.exists(forKey: .instagramRecallPrompts, email: record.email) {
                instagramRecallPrompts = remote
                StorageService.save(remote, forKey: .instagramRecallPrompts, email: record.email)
            }
            if let remote = restoredState.dailyScrollSchedules, !remote.isEmpty, !StorageService.exists(forKey: .dailyScrollSchedules, email: record.email) {
                dailyScrollSchedules = remote
                StorageService.save(remote, forKey: .dailyScrollSchedules, email: record.email)
            }
            if let remote = restoredState.weeklyReports, !remote.isEmpty, !StorageService.exists(forKey: .weeklyReports, email: record.email) {
                weeklyReports = remote
                StorageService.save(remote, forKey: .weeklyReports, email: record.email)
            }
            if let remote = restoredState.appInterventionRules, !remote.isEmpty, !StorageService.exists(forKey: .appInterventionRules, email: record.email) {
                appInterventionRules = remote
                StorageService.save(remote, forKey: .appInterventionRules, email: record.email)
            }
            if let remote = restoredState.accountabilitySummary, !StorageService.exists(forKey: .accountabilitySummary, email: record.email) {
                StorageService.save(remote, forKey: .accountabilitySummary, email: record.email)
            }
            if let remote = restoredState.widgetSharedSummary, !StorageService.exists(forKey: .widgetSharedSummary, email: record.email) {
                StorageService.save(remote, forKey: .widgetSharedSummary, email: record.email)
            }
            if let remote = restoredState.aiDataset, !remote.isEmpty, !StorageService.exists(forKey: .aiDataset, email: record.email) {
                StorageService.save(remote, forKey: .aiDataset, email: record.email)
            }
            if let remote = restoredState.mivoStillSessions, !remote.isEmpty, !StorageService.exists(forKey: .mivoStillSessions, email: record.email) {
                StorageService.save(remote, forKey: .mivoStillSessions, email: record.email)
            }
            if let remote = restoredState.appFrictionProfiles, !remote.isEmpty, !StorageService.exists(forKey: .appFrictionProfiles, email: record.email) {
                StorageService.save(remote, forKey: .appFrictionProfiles, email: record.email)
            }
            if let remote = restoredState.userSwap, !StorageService.exists(forKey: .userSwap, email: record.email) {
                userSwap = remote
                StorageService.save(remote, forKey: .userSwap, email: record.email)
            }
            if let remote = restoredState.interventionAttempts, !remote.isEmpty, !StorageService.exists(forKey: .interventionAttempts, email: record.email) {
                interventionAttempts = remote
                StorageService.save(remote, forKey: .interventionAttempts, email: record.email)
            }
            if let remote = restoredState.dailyScreenTimeObservations, !remote.isEmpty, !StorageService.exists(forKey: .dailyScreenTimeObservations, email: record.email) {
                dailyScreenTimeObservations = remote
                StorageService.save(remote, forKey: .dailyScreenTimeObservations, email: record.email)
            }
            if let remote = restoredState.timeLoans, !remote.isEmpty, !StorageService.exists(forKey: .timeLoans, email: record.email) {
                StorageService.save(remote, forKey: .timeLoans, email: record.email)
            }
            if let remote = restoredState.intentGameHistory, !remote.isEmpty, !StorageService.exists(forKey: .intentGameResults, email: record.email) {
                StorageService.save(remote, forKey: .intentGameResults, email: record.email)
            }
            if let remote = restoredState.dropPathTimeAdjustments, !remote.isEmpty, !StorageService.exists(forKey: .dropPathTimeAdjustments, email: record.email) {
                StorageService.save(remote, forKey: .dropPathTimeAdjustments, email: record.email)
            }
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
                let installationID = try DeviceBindingService.installationID()
                try await RemoteAuthService.claimDevice(installationID: installationID, user: remoteUser)
                try DeviceBindingService.bind(
                    userID: remoteUser.remoteUserId ?? normalizedEmail,
                    email: remoteUser.email,
                    replacingLocalBinding: true
                )
                try cacheRemoteUser(remoteUser, password: password)
            } catch AppError.emailAlreadyExists {
                throw AppError.emailAlreadyExists
            } catch {
                throw error
            }
        } else {
            try DeviceBindingService.assertAllows(email: normalizedEmail)
            try registerLocallyDirectly(email: email, password: password, displayName: displayName)
        }

        settings.onboardingComplete = false
        let updated = settings
        settings = updated
        onboardingProfile = OnboardingProfile()
        try completeLogin(email: normalizedEmail)
        saveForCurrentUser(settings, forKey: .settings)
        saveForCurrentUser(onboardingProfile, forKey: .onboardingProfile)
        Task { try? await ReferralCampaignService.requestNewAccountAlert() }
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
        if isSuperAdminUser {
            Task { try? await ReferralCampaignService.unregisterAdminPushDevice() }
        }
        if let email = user?.email, let record = SecureAuthService.loadRecord(email: email),
           let installationID = try? DeviceBindingService.installationID() {
            Task { await RemoteAuthService.unregisterPushDevice(installationID: installationID, record: record) }
        }
        // Offload storage mutation to background to avoid blocking the UI
        DispatchQueue.global(qos: .userInitiated).async {
            StorageService.remove(forKey: .authSession)
            StorageService.remove(forKey: .rememberedEmail)
            // Update published state on main actor
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                FamilyControlsManager.shared.setLearningModeUnlocked(false)
                FamilyControlsManager.shared.setSignedInForImpulseProtection(false)
                // Drops the account's companion state and clears the widget's snapshot.
                CompanionStateManager.shared.prepare(forEmail: nil)
                self.user = nil
                self.adminToken = nil
                self.isLoggedIn = false
                self.resetUserScopedState()
            }
        }
    }

    /// Permanently deletes the signed-in account: remote rows first, then every
    /// local trace, then signs out. Throws without touching local data if the
    /// remote deletion fails, so the caller can never show a false success.
    func deleteAccount(password: String) async throws {
        guard let currentUser = user else { throw AppError.noAccount }
        let email = currentUser.email.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard let record = SecureAuthService.loadRecord(email: email) else {
            throw AppError.accountDataMissing
        }
        guard SecureAuthService.verifyPassword(password, for: record) else {
            throw AppError.invalidCredentials
        }

        if RemoteAuthService.isConfigured {
            try await RemoteAuthService.deleteOwnAccount(email: email, password: password, record: record)
        }

        // Remote account is gone — clear every local trace of it.
        StorageService.removeUserScopedMivoData(email: email)
        StorageService.remove(forKey: .user)
        StorageService.remove(forKey: .credentials)
        StorageService.remove(forKey: .onboardingProfile)
        SecureAuthService.deleteRecord(email: email)
        SecureAuthService.deleteRecord()
        // Release the device binding, otherwise this device could never register
        // another Mivo account after the deletion.
        DeviceBindingService.releaseIfBound(email: email)
        ParentalConsentTicketStore.clear()

        logout()
    }

    func validateCurrentRemoteAccount() {
        guard let email = user?.email else { return }
        validateActiveRemoteSessionIfNeeded(email: email)
    }

    // MARK: - Sessions

    func addSession(_ session: Session) {
        sessions.append(session)
        persistSessionHistory()
    }

    @discardableResult
    func upsertSession(_ session: Session, refreshDerivedData: Bool = true) -> Bool {
        let inserted: Bool
        if let index = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[index] = session
            inserted = false
        } else {
            sessions.append(session)
            inserted = true
        }

        persistSessionHistory(refreshDerivedData: refreshDerivedData)
        return inserted
    }

    private func persistSessionHistory(refreshDerivedData: Bool = true) {
        saveForCurrentUser(sessions, forKey: .sessions)
        if refreshDerivedData {
            syncLearningModeProtectionState()
            refreshWeeklyReportSnapshot()
            updateWidgetSharedSummary()
            scheduleTimeTruthNotification()
            scheduleWeeklyReportNotification()
        }
        NotificationCenter.default.post(name: .mivoSessionHistoryDidUpdate, object: nil)
    }

    func recordStartedInterventionSession(
        id: String,
        intention: Intention,
        plannedDuration: Int,
        startTime: Date,
        urgeReason: UrgeReason?,
        urgeNote: String?,
        extendedOnce: Bool,
        emergencyUnlockUsed: Bool?,
        emergencyUnlockReason: String?
    ) {
        let formatter = ISO8601DateFormatter()
        let timestamp = formatter.string(from: startTime)

        let session = Session(
            id: id,
            // Sessions belong to the day they started, even when they run past
            // midnight, so a late-night scroll is not split across two days.
            date: MivoDay.key(startTime),
            startTime: timestamp,
            endTime: timestamp,
            plannedDuration: max(1, plannedDuration),
            actualDuration: 0,
            intention: intention,
            extendedOnce: extendedOnce,
            reflection: nil,
            reflectionNote: "",
            urgeReason: urgeReason,
            urgeNote: urgeNote,
            outcomeScore: nil,
            emergencyUnlockUsed: emergencyUnlockUsed,
            emergencyUnlockReason: emergencyUnlockReason
        )
        _ = upsertSession(session, refreshDerivedData: false)
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
        SessionEndedNotificationCleaner.clearPendingAndDelivered()
    }

    func saveRunningSession(_ session: RunningMivoSession) {
        guard !isRestrictionBypassUser else { return }
        saveForCurrentUser(session, forKey: .runningSession)
    }

    func clearRunningSession() {
        removeForCurrentUser(.runningSession)
        FamilyControlsManager.shared.endSessionLiveActivity()
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

        endRunningSession(running, now: now)
    }

    /// Ends `running` right now and shows the session-end review screen
    /// (`pendingExpiredRunningSession` → `SessionEndedReviewView`) — the
    /// shared tail both `recoverExpiredRunningSessionIfNeeded()` (once it
    /// finds a session whose stored `expiresAt` has already passed) and
    /// `endRunningSessionFromCheckInTimeout()` below need.
    private func endRunningSession(_ running: RunningMivoSession, now: Date = Date()) {
        FamilyControlsManager.shared.endSessionAndRelockForIntervention()
        let expired = expiredChoiceSession(from: running, now: now)
        if autoFinishExpiredRunningSessionIfForgotten(expired, now: now) {
            return
        }
        saveRunningSession(expired)
        pendingExpiredRunningSession = expired
    }

    /// Called when the mid-scroll check-in's own countdown — driven
    /// directly by `FamilyControlsManager.mivoSessionRemainingSeconds()`,
    /// not by `RunningMivoSession.expiresAt` — reaches zero. Ends the
    /// running session and shows the same review screen a normal
    /// expiration would, instead of silently dismissing back to a blank
    /// tab. Doesn't wait for `RunningMivoSession.expiresAt` to also read as
    /// past: `FamilyControlsManager`'s live countdown hitting zero is
    /// already authoritative on its own, and the two can briefly disagree.
    func endRunningSessionFromCheckInTimeout(now: Date = Date()) {
        guard let email = user?.email,
              let running = StorageService.load(RunningMivoSession.self, forKey: .runningSession, email: email) else { return }
        endRunningSession(running, now: now)
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

    func secondsUntilAutoFinishExpiredSession(_ running: RunningMivoSession, now: Date = Date()) -> TimeInterval {
        let formatter = ISO8601DateFormatter()
        let expiredAt = running.expiredAt.flatMap { formatter.date(from: $0) }
            ?? formatter.date(from: running.expiresAt)
            ?? now
        let autoFinishAt = expiredAt.addingTimeInterval(autoFinishExpiredSessionDelay)
        return max(0, autoFinishAt.timeIntervalSince(now))
    }

    private func completedSession(fromExpired running: RunningMivoSession, now: Date = Date()) -> Session {
        let formatter = ISO8601DateFormatter()
        let endTime = running.expiredAt ?? running.expiresAt
        let endDate = formatter.date(from: endTime) ?? now
        let startDate = formatter.date(from: running.startTime) ?? endDate

        return Session(
            id: running.id,
            date: MivoDay.key(startDate),
            startTime: running.startTime,
            endTime: endTime.isEmpty ? formatter.string(from: endDate) : endTime,
            plannedDuration: running.plannedDuration,
            actualDuration: cappedElapsedMinutes(for: running, now: now),
            intention: running.intention,
            extendedOnce: running.extendedOnce,
            reflection: nil,
            reflectionNote: "",
            urgeReason: running.urgeReason,
            urgeNote: running.urgeNote,
            outcomeScore: nil,
            emergencyUnlockUsed: running.emergencyUnlockUsed,
            emergencyUnlockReason: running.emergencyUnlockReason
        )
    }

    @discardableResult
    func autoFinishExpiredRunningSessionIfForgotten(_ running: RunningMivoSession, now: Date = Date(), force: Bool = false) -> Bool {
        guard force || secondsUntilAutoFinishExpiredSession(running, now: now) == 0 else { return false }

        let session = completedSession(fromExpired: running, now: now)
        if upsertSession(session) {
            appendAISummary("Session auto-finished after 5m idle: \(session.actualDuration)m actual / \(session.plannedDuration)m planned | Intention: \(session.intention.rawValue)")
        }
        pendingExpiredRunningSession = nil
        pendingSessionFeedback = nil
        pendingResumedActiveSession = nil
        removeForCurrentUser(.pendingSessionFeedback)
        clearRunningSession()
        SessionEndedNotificationCleaner.clearPendingAndDelivered()
        _ = FamilyControlsManager.shared.setMivoSessionActive(false)
        return true
    }

    func extendExpiredRunningSession(_ running: RunningMivoSession, addedMinutes: Int, emergencyReason: String? = nil) -> Bool {
        if weeklyExperimentEnforcementPolicy.blocksExtensions, emergencyReason == nil {
            sessionActivationError = "Your active experiment keeps the original session limit. Save and reflect, or use Emergency unlock for a genuine urgent need."
            return false
        }

        let addedSeconds = max(1, addedMinutes) * 60
        let now = Date()
        let formatter = ISO8601DateFormatter()
        let completedOriginalSession = completedSession(fromExpired: running, now: now)
        let updated = RunningMivoSession(
            id: UUID().uuidString,
            intention: running.intention,
            plannedDuration: max(1, addedMinutes),
            plannedSeconds: addedSeconds,
            approvedSeconds: addedSeconds,
            startTime: formatter.string(from: now),
            expiresAt: formatter.string(from: now.addingTimeInterval(TimeInterval(addedSeconds))),
            expiredAt: nil,
            expirationSource: nil,
            state: .active,
            accumulatedElapsedSeconds: 0,
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
        if upsertSession(completedOriginalSession) {
            appendAISummary("Session saved before add-time: \(completedOriginalSession.actualDuration)m actual / \(completedOriginalSession.plannedDuration)m planned | Intention: \(completedOriginalSession.intention.rawValue)")
        }
        pendingExpiredRunningSession = nil
        pendingSessionFeedback = nil
        pendingResumedActiveSession = updated
        saveRunningSession(updated)
        return true
    }

    func clearExpiredRunningSessionReview() {
        pendingExpiredRunningSession = nil
        pendingSessionFeedback = nil
        pendingResumedActiveSession = nil
        removeForCurrentUser(.pendingSessionFeedback)
        clearRunningSession()
        SessionEndedNotificationCleaner.clearPendingAndDelivered()
    }

    var accountRole: String {
        if user?.isAdmin == true { return "super_admin" }
        return user?.accountRole ?? "user"
    }

    var isSuperAdminUser: Bool { accountRole == "super_admin" }
    /// Admin capabilities are inherited by the higher Super Admin role.
    var isAdminUser: Bool { accountRole == "admin" || isSuperAdminUser }
    var canManageAnnouncements: Bool { isAdminUser }
    var canViewAdminUsers: Bool { isSuperAdminUser }
    var canAccessSuperAdminCenter: Bool { isSuperAdminUser }
    var isAmbassadorUser: Bool { accountRole == "ambassador" }

    var canReplayFounderOnboarding: Bool {
        isSuperAdminUser
            && user?.email.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
                == "pranshuraithatha0@gmail.com"
    }

    func startFounderOnboardingReplay() {
        guard canReplayFounderOnboarding else { return }
        onboardingReplayActive = true
    }

    func cancelFounderOnboardingReplay() {
        onboardingReplayActive = false
    }

    var isRestrictionBypassUser: Bool {
        false
    }

    func loadAdminUsers() async throws -> [AdminUser] {
        try await prepareAuthenticatedCampaignSession()
        let dashboard = try await ReferralCampaignService.loadAdminDashboard()
        return dashboard.users.map { item in
            AdminUser(
                email: item.email,
                name: item.name,
                createdAt: item.createdAt ?? "",
                onboardingProfile: nil,
                isAdmin: item.email.lowercased() == user?.email.lowercased(),
                role: item.email.lowercased() == user?.email.lowercased() ? "super_admin" : "user",
                lastLoginAt: nil,
                updatedAt: nil
            )
        }
    }

    func deleteAdminUser(email: String) async throws {
        try await prepareAuthenticatedCampaignSession()
        let dashboard = try await ReferralCampaignService.loadAdminDashboard()
        guard let target = dashboard.users.first(where: { $0.email.lowercased() == email.lowercased() }) else {
            throw AppError.noAccount
        }
        try await ReferralCampaignService.deleteUser(userID: target.userId, reason: "Deleted from Mivo user database")
    }

    /// Returns false when there is no trustworthy usage figure to compare the
    /// guess against, so the caller can show "Data unavailable" rather than
    /// scoring the user against a fabricated number.
    @discardableResult
    func addTruthCheck(guess: Int) -> Bool {
        let today = todayKey()
        guard let actual = timeTruthActualMinutesForToday() else { return false }
        let check = TruthCheckGuess(
            id: UUID().uuidString,
            date: today,
            guess: guess,
            actual: actual,
            checkedAt: ISO8601DateFormatter().string(from: Date()),
            perAppMinutes: currentPerAppMinutesSnapshot(for: today)
        )
        truthChecks.append(check)
        saveForCurrentUser(truthChecks, forKey: .truthChecks)
        syncLearningModeProtectionState()
        scheduleTimeTruthNotification()
        return true
    }

    func recordTimeTruthGuess(_ guess: Int, for prompt: TimeTruthPrompt) {
        guard !truthChecks.contains(where: { $0.date == prompt.date }) else { return }
        let check = TruthCheckGuess(
            id: UUID().uuidString,
            date: prompt.date,
            guess: guess,
            actual: prompt.actualMinutes,
            checkedAt: ISO8601DateFormatter().string(from: Date()),
            perAppMinutes: currentPerAppMinutesSnapshot(for: prompt.date)
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
        DropPathTimeAdjustmentService.shared.applyPendingAdjustments(for: date, appVM: self)
    }

    /// Removes time from the next unfinished window today. When today has no
    /// remaining window, an already-created tomorrow schedule is used; if that
    /// does not exist yet, the caller persists a pending adjustment for it.
    func applyTimeReductionToNextScheduledWindow(
        minutes: Int,
        sourceGame: IntentGameType = .dropPath,
        now: Date = Date()
    ) -> ScheduledTimeReductionApplication? {
        guard minutes > 0 else { return nil }
        let calendar = Calendar.current
        let minuteOfDay = calendar.component(.hour, from: now) * 60
            + calendar.component(.minute, from: now)
        let today = MivoDay.key(now)

        if let application = applyScheduledTimeReduction(
            minutes: minutes,
            on: today,
            notBeforeMinute: minuteOfDay,
            sourceGame: sourceGame
        ) {
            return application
        }

        return applyScheduledTimeReduction(
            minutes: minutes,
            on: MivoDay.key(offsetFromToday: 1, from: now),
            notBeforeMinute: nil,
            sourceGame: sourceGame
        )
    }

    /// Low-level schedule mutation shared by immediate and overnight Drop Path
    /// adjustments. It preserves the locked time window and only changes the
    /// number of minutes allowed inside it.
    func applyScheduledTimeReduction(
        minutes: Int,
        on date: String,
        notBeforeMinute: Int?,
        sourceGame: IntentGameType = .dropPath
    ) -> ScheduledTimeReductionApplication? {
        guard minutes > 0,
              let scheduleIndex = dailyScrollSchedules.firstIndex(where: { $0.date == date }) else {
            return nil
        }

        let schedule = dailyScrollSchedules[scheduleIndex]
        let windowIndex = schedule.windows.indices
            .filter { index in
                let window = schedule.windows[index]
                guard window.minutes > 0 else { return false }
                guard let notBeforeMinute else { return true }
                return window.endHour * 60 > notBeforeMinute
            }
            .sorted { schedule.windows[$0].startHour < schedule.windows[$1].startHour }
            .first
        guard let windowIndex else { return nil }

        let window = schedule.windows[windowIndex]
        let removed = min(minutes, window.minutes)
        guard removed > 0 else { return nil }
        var windows = schedule.windows
        windows[windowIndex] = ScreenScrollWindow(
            id: window.id,
            title: window.title,
            startHour: window.startHour,
            endHour: window.endHour,
            minutes: window.minutes - removed,
            reason: "\(sourceGame.title) removed \(removed) min from this session."
        )
        dailyScrollSchedules[scheduleIndex] = DailyScrollSchedule(
            id: schedule.id,
            date: schedule.date,
            windows: windows,
            createdAt: schedule.createdAt
        )
        saveForCurrentUser(dailyScrollSchedules, forKey: .dailyScrollSchedules)
        appendAISummary("\(sourceGame.title) removed \(removed)m from \(window.title) on \(date).")
        return ScheduledTimeReductionApplication(
            minutesRemoved: removed,
            targetDate: date,
            windowID: window.id,
            windowTitle: window.title
        )
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
        return "Choose today’s scroll windows. Once saved, they lock until tomorrow."
    }

    func dismissTimeTruthPrompt() {
        pendingTimeTruthPrompt = nil
    }

    func evaluateDailyScrollSchedulePrompt(now: Date = Date()) {
        guard isLoggedIn, settings.onboardingComplete else {
            pendingDailyScrollSchedulePrompt = nil
            return
        }
        // A returning user resets first; today's windows are asked right after.
        guard pendingComebackPrompt == nil else { return }

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
            content.body = "Choose today’s scroll windows. Once saved, they lock until tomorrow."
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
        guard pendingComebackPrompt == nil else { return }

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
            // Without a real Screen Time figure there is nothing to reveal, so
            // hold the prompt back rather than grading the guess against a
            // stand-in number. It fires on a later pass once the report lands.
            guard let actualMinutes = timeTruthActualMinutesForToday() else { return }
            pendingTimeTruthPrompt = TimeTruthPrompt(
                id: today,
                date: today,
                actualMinutes: actualMinutes,
                scheduledHour: schedule.hour,
                scheduledMinute: schedule.minute
            )
        }
    }

    /// Asks existing users for the daily target onboarding never managed to save.
    ///
    /// `saveOnboardingProfile` used to drop `dailyScrollGoalMinutes`, so anyone
    /// who set up before that was fixed has no goal on file and has silently
    /// been running against the 30-minute default. The value cannot be
    /// recovered — it was never written — so the only honest repair is to ask.
    func evaluateScrollGoalPrompt() {
        guard isLoggedIn, settings.onboardingComplete else {
            pendingScrollGoalPrompt = nil
            return
        }
        guard pendingComebackPrompt == nil else { return }
        guard pendingScrollGoalPrompt == nil,
              onboardingProfile.dailyScrollGoalMinutes == nil else { return }
        if let email = user?.email,
           StorageService.load(Bool.self, forKey: .scrollGoalPromptShown, email: email) == true { return }

        let plan = rawAdaptiveScreenTimePlan()
        // Their own baseline is the only useful frame for this choice, so wait
        // until observation has produced one rather than asking in a vacuum.
        guard !plan.collecting else { return }

        pendingScrollGoalPrompt = ScrollGoalPrompt(
            id: "scroll-goal-\(plan.baselineMinutes)",
            baselineMinutes: plan.baselineMinutes,
            options: [30, 45, 70, 90],
            createdAt: ISO8601DateFormatter().string(from: Date())
        )
    }

    func saveScrollGoal(_ minutes: Int) {
        var profile = onboardingProfile
        profile.dailyScrollGoalMinutes = minutes
        saveOnboardingProfile(profile)
        saveForCurrentUser(true, forKey: .scrollGoalPromptShown)
        pendingScrollGoalPrompt = nil
        HapticsService.success()
    }

    /// Dismissing leaves the default in place but stops the asking, so the
    /// prompt never becomes a nag.
    func dismissScrollGoalPrompt() {
        pendingScrollGoalPrompt = nil
        saveForCurrentUser(true, forKey: .scrollGoalPromptShown)
    }

    /// Show the one-time goal-forecast prompt the first time the user enters
    /// their personalized plan (i.e. right after observation completes).
    func evaluateGoalForecastPrompt() {
        guard isLoggedIn, settings.onboardingComplete else {
            pendingGoalForecastPrompt = nil
            return
        }
        // A fresh start has its own forecast, and this one is drawn from the
        // old ramp, so its numbers would contradict the new plan.
        guard pendingComebackPrompt == nil, comebackAnchor == nil else { return }
        // The forecast is drawn from the goal, so it must not run while the
        // goal itself is still being asked for.
        guard pendingScrollGoalPrompt == nil else { return }
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

    /// Every-two-days "rate us / give feedback" card — see
    /// `MivoRatingPromptStore` for the frequency and stop-forever rules.
    /// Never interrupts anything: it only checks in on the same minute-poll
    /// every other periodic prompt already uses, and skips entirely while a
    /// bigger prompt is already up.
    func evaluateRatingPrompt() {
        guard isLoggedIn, settings.onboardingComplete else { return }
        guard !showRatingPrompt else { return }
        guard pendingScrollGoalPrompt == nil,
              pendingGoalForecastPrompt == nil,
              pendingComebackPrompt == nil,
              pendingTimeTruthPrompt == nil,
              pendingDailyScrollSchedulePrompt == nil,
              !showNamePrompt else { return }
        guard MivoRatingPromptStore.shouldShow() else { return }
        MivoRatingPromptStore.markShown()
        showRatingPrompt = true
    }

    func saveUserSwap(_ swap: UserSwap) {
        userSwap = swap
        saveForCurrentUser(swap, forKey: .userSwap)
        saveForCurrentUser(true, forKey: .userSwapPromptShown)
        showSwapPrompt = false
    }

    /// Onboarding captures this for new users directly. Existing users never
    /// saw that step, so this asks once, the next time they open the app —
    /// mirroring the ask-once gating the other prompts above use so nothing
    /// stacks on top of anything else.
    func evaluateSwapPrompt() {
        guard isLoggedIn, settings.onboardingComplete else { return }
        guard !showSwapPrompt, userSwap == nil else { return }
        guard pendingScrollGoalPrompt == nil,
              pendingGoalForecastPrompt == nil,
              pendingComebackPrompt == nil,
              pendingTimeTruthPrompt == nil,
              pendingDailyScrollSchedulePrompt == nil,
              !showRatingPrompt, !showNamePrompt else { return }
        if let email = user?.email,
           StorageService.load(Bool.self, forKey: .userSwapPromptShown, email: email) == true { return }
        showSwapPrompt = true
    }

    func skipSwapPromptForNow() {
        showSwapPrompt = false
        saveForCurrentUser(true, forKey: .userSwapPromptShown)
    }

    /// True when the current name is exactly the email's local part — the
    /// fallback `RemoteAuthService.supabaseSignInWithGoogle`/`supabaseSignInWithApple`
    /// use when the OAuth provider doesn't return a real name. Computed
    /// live off `user` rather than cached, so it self-corrects the moment
    /// `saveDisplayName` (or a metadata change on another device) resolves it.
    private func hasFallbackDisplayName(_ user: UserProfile) -> Bool {
        let prefix = user.email.split(separator: "@").first.map(String.init) ?? ""
        return !prefix.isEmpty && user.name.caseInsensitiveCompare(prefix) == .orderedSame
    }

    /// Asks once, the next time an OAuth account with a fallback name opens
    /// the app — mirroring the ask-once gating the other prompts above use
    /// so nothing stacks on top of anything else.
    func evaluateNamePrompt() {
        guard isLoggedIn, settings.onboardingComplete else { return }
        guard !showNamePrompt, let user, hasFallbackDisplayName(user) else { return }
        guard pendingScrollGoalPrompt == nil,
              pendingGoalForecastPrompt == nil,
              pendingComebackPrompt == nil,
              pendingTimeTruthPrompt == nil,
              pendingDailyScrollSchedulePrompt == nil,
              !showRatingPrompt, !showSwapPrompt else { return }
        if StorageService.load(Bool.self, forKey: .namePromptDismissed, email: user.email) == true { return }
        showNamePrompt = true
    }

    func saveDisplayName(_ name: String) async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, var record = SecureAuthService.loadRecord(email: user?.email ?? "") else { return }

        record.name = trimmed
        try? SecureAuthService.saveRecord(record)
        user?.name = trimmed
        saveForCurrentUser(true, forKey: .namePromptDismissed)
        showNamePrompt = false

        if let accessToken = record.remoteAccessToken {
            try? await RemoteAuthService.updateDisplayName(trimmed, accessToken: accessToken)
        }
    }

    func skipNamePromptForNow() {
        showNamePrompt = false
        saveForCurrentUser(true, forKey: .namePromptDismissed)
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
        let isReplay = onboardingReplayActive
        // Observation starts when setup is actually completed. Starting it while
        // the user is still moving through onboarding can skip one or more of the
        // three measurement days before Mivo has Screen Time access.
        if !settings.onboardingComplete || onboardingProfile.observationStartedAt == nil {
            onboardingProfile.observationStartedAt = ISO8601DateFormatter().string(from: Date())
            saveForCurrentUser(onboardingProfile, forKey: .onboardingProfile)
            if var u = user {
                u.onboardingProfile = onboardingProfile
                StorageService.save(u, forKey: .user)
                user = u
            }
            if var record = SecureAuthService.loadRecord(), record.email == user?.email {
                record.onboardingProfile = onboardingProfile
                try? SecureAuthService.saveRecord(record)
            }
        }

        // Set flag
        settings.onboardingComplete = true
        if !isReplay {
            settings.tutorialComplete = false
        }
        // Reassign to force @Published notifications in case of in-place mutation
        let updated = settings
        settings = updated
        saveForCurrentUser(settings, forKey: .settings)
        syncCurrentUserStateToRemote()

        if isReplay {
            onboardingReplayActive = false
        }

        // No longer use deprecated UIApplication interaction APIs; if any global overlays were used,
        // they should be dismissed by the UI flow (we avoid calling deprecated APIs here).
    }

    func saveOnboardingProfile(_ partial: OnboardingProfile) {
        if let observationStartedAt = partial.observationStartedAt {
            onboardingProfile.observationStartedAt = observationStartedAt
        }
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
        // This merge is field-by-field, so anything not listed here is silently
        // dropped. The daily goal was missing, which meant the target the user
        // picked in onboarding never reached the plan and every ramp fell back
        // to the 30-minute default.
        if let goal = partial.dailyScrollGoalMinutes {
            onboardingProfile.dailyScrollGoalMinutes = goal
        }
        if let pauseStyle = partial.pauseStyle {
            onboardingProfile.pauseStyle = pauseStyle
        }
        if let interval = partial.checkInIntervalMinutes {
            onboardingProfile.checkInIntervalMinutes = interval
            FamilyControlsManager.shared.setCheckInIntervalMinutes(interval)
        }
        if let referralCode = partial.referralCode,
           !referralCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            onboardingProfile.referralCode = referralCode.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let source = partial.referralSource, !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            onboardingProfile.referralSource = source
            onboardingProfile.referralAmbassadorName = source == "ambassador"
                ? partial.referralAmbassadorName?.trimmingCharacters(in: .whitespacesAndNewlines)
                : nil
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

        SecureAuthService.deleteAllRecords()
        StorageService.removeAllMivoData()
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
            StorageService.remove(forKey: .recallCheckIns)
            StorageService.remove(forKey: .instagramWrapperSessions)
            StorageService.remove(forKey: .instagramRecallPrompts)
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.sessions = []
                self.truthChecks = []
                self.recallCheckIns = []
                self.instagramWrapperSessions = []
                self.instagramRecallPrompts = []
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

    func restartTutorial() {
        settings.tutorialComplete = false
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

    var appearanceMode: AppAppearanceMode {
        settings.appearanceMode ?? .system
    }

    var preferredColorScheme: ColorScheme? {
        switch appearanceMode {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    func setAppearanceMode(_ mode: AppAppearanceMode) {
        settings.appearanceMode = mode
        let updated = settings
        settings = updated
        saveForCurrentUser(updated, forKey: .settings)
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
        guard pending, !mivoLaunchGateActive else { return false }

        // This app-group value is a one-shot navigation request from the shield.
        // Consume it before changing tabs so the foreground poller cannot keep
        // selecting Interventions after the user deliberately leaves the page.
        FamilyControlsManager.shared.clearPendingInterventionSetup()
        mivoLaunchGateActive = true
        return true
    }

    // MARK: - Deep link (shield "Open Mivo" button)

    func handleDeepLink(_ url: URL) {
        if url.scheme == "mivo", url.host == "clear" {
            let platformName = url.pathComponents.first(where: { $0 != "/" })
            if let platformName, let platform = MivoClearPlatform(rawValue: platformName.lowercased()) {
                let directURL = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                    .queryItems?.first(where: { $0.name == "url" })?.value.flatMap(URL.init(string:))
                pendingMivoClearRoute = MivoClearRoute(platform: platform, directURL: directURL, entryPoint: .deepLink)
            }
            return
        }
        if url.scheme == "mivo", url.host == "referral" {
            let code = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "code" })?.value
            if let code, !code.isEmpty {
                UserDefaults.standard.set(code.uppercased(), forKey: "mivo.prefilledReferralCode")
            }
            deepLinkReferralHubRequested = true
            return
        }
        if url.host == "usemivo.app" {
            let parts = url.pathComponents.filter { $0 != "/" }
            if parts.count >= 2, parts[0] == "clear",
               let platform = MivoClearPlatform(rawValue: parts[1].lowercased()) {
                let directURL = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                    .queryItems?.first(where: { $0.name == "url" })?.value.flatMap(URL.init(string:))
                pendingMivoClearRoute = MivoClearRoute(platform: platform, directURL: directURL, entryPoint: .deepLink)
                return
            }
            if parts.count >= 2, parts[0] == "r" {
                UserDefaults.standard.set(parts[1].uppercased(), forKey: "mivo.prefilledReferralCode")
                return
            }
            if parts == ["referral"] || parts == ["events", "referral-challenge"] {
                deepLinkReferralHubRequested = true
            }
            return
        }
        guard url.scheme == "mivo" else { return }
        if url.host == "companion" {
            CompanionStateManager.shared.requestOpen()
            return
        }
        // Tapping a Mivo Still Live Activity just opens the app on the Still screen
        // it came from; it must not start the pause flow the way an unknown link does.
        if url.host == "focus" { return }
        if url.host == "session" {
            let actionName = url.pathComponents.last ?? ""
            liveActivityDeepLinkAction = LiveActivityDeepLinkAction(rawValue: actionName)
            return
        }
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

    /// Companion to `checkDeepLinkInterventionFlag()` — picks up the flag
    /// `requestMidScrollCheckIn()` in the ShieldAction extension writes when
    /// the primary shield button is tapped mid-session. Checked separately
    /// (not folded into `deepLinkInterventionRequested`) since it opens a
    /// short pause + yes/no view, not the reason/duration flow.
    func checkMidScrollCheckInFlag() {
        let defaults = UserDefaults(suiteName: FamilyControlsManager.shared.appGroup)
        guard defaults?.bool(forKey: MivoScreenTimeKeys.pendingMidScrollCheckIn) == true else { return }
        defaults?.set(false, forKey: MivoScreenTimeKeys.pendingMidScrollCheckIn)
        let appName = defaults?.string(forKey: MivoScreenTimeKeys.pendingMidScrollCheckInAppName)
        defaults?.removeObject(forKey: MivoScreenTimeKeys.pendingMidScrollCheckInAppName)
        defaults?.synchronize()
        guard FamilyControlsManager.shared.isMivoSessionActive() else { return }
        pendingMidScrollCheckInAppName = appName
        pendingMidScrollCheckIn = true
    }

    /// Companion to `checkMidScrollCheckInFlag()` — picks up the flag
    /// `requestInstagramWrapper()` in the ShieldAction extension writes when
    /// Instagram is tapped with the wrapper toggle on.
    func checkPendingInstagramWrapperFlag() {
        let defaults = UserDefaults(suiteName: FamilyControlsManager.shared.appGroup)
        guard defaults?.bool(forKey: MivoScreenTimeKeys.pendingInstagramWrapper) == true else { return }
        defaults?.set(false, forKey: MivoScreenTimeKeys.pendingInstagramWrapper)
        defaults?.synchronize()
        pendingInstagramWrapper = true
    }

    /// Real, measured data — see `InstagramWrapperSession` for why this is
    /// trustworthy in a way `RecallCheckIn.guessedCount` never can be.
    func recordInstagramWrapperSession(
        startedAt: Date,
        scrollCount: Int,
        videoPlayCount: Int = 0,
        videoWatchSeconds: Int = 0,
        tapCount: Int = 0,
        scrollDistancePoints: Int = 0,
        sectionChanges: Int = 0,
        longestPauseSeconds: Int = 0,
        firstScrollDelaySeconds: Int = 0
    ) {
        let session = InstagramWrapperSession(
            id: UUID().uuidString,
            date: todayKey(),
            startedAt: ISO8601DateFormatter().string(from: startedAt),
            endedAt: ISO8601DateFormatter().string(from: Date()),
            scrollCount: scrollCount,
            videoPlayCount: videoPlayCount,
            videoWatchSeconds: videoWatchSeconds,
            tapCount: tapCount,
            scrollDistancePoints: scrollDistancePoints,
            sectionChanges: sectionChanges,
            longestPauseSeconds: longestPauseSeconds,
            firstScrollDelaySeconds: firstScrollDelaySeconds
        )
        instagramWrapperSessions.append(session)
        saveForCurrentUser(instagramWrapperSessions, forKey: .instagramWrapperSessions)
    }

    func instagramWrapperSessions(for dateKey: String) -> [InstagramWrapperSession] {
        instagramWrapperSessions.filter { $0.date == dateKey }
    }

    /// Logged by `InstagramWrapperView` every few real scrolls — see
    /// `InstagramRecallPrompt` for why `scrollsAgo` is measured, not guessed.
    func recordInstagramRecallPrompt(scrollsAgo: Int, answer: String) {
        let prompt = InstagramRecallPrompt(
            id: UUID().uuidString,
            date: todayKey(),
            scrollsAgo: scrollsAgo,
            answer: answer.trimmingCharacters(in: .whitespacesAndNewlines),
            checkedAt: ISO8601DateFormatter().string(from: Date())
        )
        instagramRecallPrompts.append(prompt)
        saveForCurrentUser(instagramRecallPrompts, forKey: .instagramRecallPrompts)
    }

    func instagramRecallPrompts(for dateKey: String) -> [InstagramRecallPrompt] {
        instagramRecallPrompts.filter { $0.date == dateKey }
    }

    // MARK: - Recall ("Mivo Recall" / Attention Receipt)
    //
    // iOS gives no API to count what happens inside another app (no scroll
    // events, no content signal) — see the mid-scroll check-in's own
    // reasoning above. So instead of a count Mivo can't actually get, this
    // asks the person to self-report right after a check-in fires, while
    // it's still fresh, and pairs that against real numbers Mivo does have
    // (session length, `todayPerAppMinutes()`). The gap between "I think I
    // saw ~5 things" and "you were in there 41 minutes and named one" is the
    // whole point — see `AttentionReceiptView`.
    @discardableResult
    func recordRecallCheckIn(guessedCount: Int, recalledText: String) -> RecallCheckIn {
        let check = RecallCheckIn(
            id: UUID().uuidString,
            date: todayKey(),
            appName: pendingMidScrollCheckInAppName,
            guessedCount: max(0, guessedCount),
            recalledText: recalledText.trimmingCharacters(in: .whitespacesAndNewlines),
            checkedAt: ISO8601DateFormatter().string(from: Date())
        )
        recallCheckIns.append(check)
        saveForCurrentUser(recallCheckIns, forKey: .recallCheckIns)
        pendingMidScrollCheckInAppName = nil
        return check
    }

    func recallCheckIns(for dateKey: String) -> [RecallCheckIn] {
        recallCheckIns.filter { $0.date == dateKey }
    }

    /// Public wrapper around the same per-app snapshot `TruthCheckGuess`
    /// already uses internally — the Attention Receipt needs the identical
    /// real, on-device numbers (today's Screen Time report), not a second
    /// source of truth.
    func todayPerAppMinutes() -> [(name: String, minutes: Int)] {
        let snapshot = currentPerAppMinutesSnapshot(for: todayKey()) ?? [:]
        return snapshot
            .map { (name: $0.key, minutes: $0.value) }
            .sorted { $0.minutes > $1.minutes }
    }

    func checkPendingMivoClearRoute() {
        let defaults = UserDefaults(suiteName: MivoScreenTimeKeys.appGroup)
        guard let platformName = defaults?.string(forKey: MivoScreenTimeKeys.pendingMivoClearPlatform),
              let platform = MivoClearPlatform(rawValue: platformName) else { return }
        let entryPoint = defaults?.string(forKey: MivoScreenTimeKeys.pendingMivoClearEntryPoint)
            .flatMap(MivoClearEntryPoint.init(rawValue:)) ?? .shield
        defaults?.removeObject(forKey: MivoScreenTimeKeys.pendingMivoClearPlatform)
        defaults?.removeObject(forKey: MivoScreenTimeKeys.pendingMivoClearEntryPoint)
        defaults?.synchronize()
        pendingMivoClearRoute = MivoClearRoute(platform: platform, entryPoint: entryPoint)
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
        pendingResumedActiveSession = nil
        pendingExpiredRunningSession = nil
        pendingSessionFeedback = nil
        clearRunningSession()
        SessionEndedNotificationCleaner.clearPendingAndDelivered()
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

        if weeklyExperimentEnforcementPolicy.blocksExtensions {
            return SessionExtensionDecision(
                allowed: false,
                addedMinutes: 0,
                title: "Keep the original limit",
                message: "This is the experiment you approved for this week. Save the session here so Mivo can compare it fairly with last week."
            )
        }

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
                message: "Mivo is in its 3-day observation period — no cap is enforced. Your personalized plan starts on day 4 using your self-report plus the 3 observed days."
            )
        }

        if ProductExpansionStore.shared.isEnabled(.appPersonalities),
           let profile = ProductExpansionStore.shared.approvedFrictionProfile,
           !profile.extensionsAllowed {
            return SessionExtensionDecision(
                allowed: false,
                addedMinutes: 0,
                title: "Keep the original limit",
                message: "You approved the \(profile.appName) personality without extensions. Save this session here, or change that personality later under Protect."
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
        if plan.collecting {
            return (
                maxMinutes: 240,
                isLimited: false,
                message: "First 3 days: observation mode. Mivo is recording your real usage so it can start the personalized plan on day 4 from your self-report plus the 3 observed days.",
                windowTitle: "3-day observation"
            )
        }


        let hour = Calendar.current.component(.hour, from: now)
        if let locked = dailyScrollSchedule(), !locked.windows.contains(where: { scrollWindow($0, contains: hour) }) {
            return (
                maxMinutes: 0,
                isLimited: true,
                message: nextScrollWindowMessage(for: plan, now: now, fallback: "Today’s locked schedule does not include this time."),
                windowTitle: "Schedule protected"
            )
        }

        let experimentPolicy = weeklyExperimentEnforcementPolicy
        if experimentPolicy.protects(hour: hour) {
            let lockedScheduleAllowsNow = dailyScrollSchedule()?.windows.contains {
                scrollWindow($0, contains: hour)
            } == true
            if !lockedScheduleAllowsNow {
                let allowedMinutes = max(0, experimentPolicy.rule?.allowedMinutes ?? 0)
                let usedMinutes = minutesUsedToday(in: experimentPolicy)
                let remainingMinutes = max(0, allowedMinutes - usedMinutes)
                if remainingMinutes > 0 {
                    return (
                        maxMinutes: min(30, remainingMinutes),
                        isLimited: true,
                        message: "Your approved experiment allows \(remainingMinutes) more minute\(remainingMinutes == 1 ? "" : "s") during this protected hour.",
                        windowTitle: "Experiment allowance"
                    )
                }
                return (
                    maxMinutes: 0,
                    isLimited: true,
                    message: "Your approved 7-day experiment protects this hour. Today's locked schedule still takes priority when it explicitly includes this time.",
                    windowTitle: "Experiment protected"
                )
            }
        }

        if isLateNightProtectionActive(at: now), hasUsedLastScrollTonight(at: now) {
            return (
                maxMinutes: 0,
                isLimited: true,
                message: "You chose your last scroll for tonight. Mivo will keep your selected apps protected until \(lateNightWakeTimeText(at: now)).",
                windowTitle: "Night protected"
            )
        }

        if protectedGroupRuleMode() == .looseTracking {
            return (
                maxMinutes: 30,
                isLimited: false,
                message: "Loose tracking remains available outside the rule you approved for this experiment.",
                windowTitle: "Loose tracking"
            )
        }

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

    /// True when today's zero unlock minutes come from a deliberate, hard
    /// protection — a locked schedule, an approved experiment's own
    /// allowance already spent, or "last scroll of the night" already used
    /// — rather than the adaptive daily target simply running low. Mirrors
    /// the same sub-checks `adaptiveSessionDurationLimit` already makes, but
    /// answers the narrower question Intent Games' Time Loan needs: a
    /// locked schedule or a spent commitment device should never be
    /// borrowed around, while an ordinary low-on-flexible-allowance moment
    /// still should be. Kept separate rather than changing
    /// `adaptiveSessionDurationLimit`'s return shape, since that has many
    /// existing callers.
    func isHardProtectionActive(now: Date = Date()) -> Bool {
        let plan = adaptiveScreenTimePlan()
        guard !plan.collecting else { return false }

        let hour = Calendar.current.component(.hour, from: now)

        if let locked = dailyScrollSchedule(), !locked.windows.contains(where: { scrollWindow($0, contains: hour) }) {
            return true
        }

        let experimentPolicy = weeklyExperimentEnforcementPolicy
        if experimentPolicy.protects(hour: hour) {
            let lockedScheduleAllowsNow = dailyScrollSchedule()?.windows.contains {
                scrollWindow($0, contains: hour)
            } == true
            if !lockedScheduleAllowsNow {
                let allowedMinutes = max(0, experimentPolicy.rule?.allowedMinutes ?? 0)
                let usedMinutes = minutesUsedToday(in: experimentPolicy)
                if max(0, allowedMinutes - usedMinutes) <= 0 { return true }
            }
        }

        if isLateNightProtectionActive(at: now), hasUsedLastScrollTonight(at: now) {
            return true
        }

        return false
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

    private func minutesUsedToday(in policy: WeeklyExperimentEnforcementPolicy) -> Int {
        let calendar = Calendar.current
        let formatter = ISO8601DateFormatter()
        return todaysSessions.reduce(0) { total, session in
            guard let start = formatter.date(from: session.startTime) else { return total }
            let hour = calendar.component(.hour, from: start)
            return total + (policy.protects(hour: hour) ? session.actualDuration : 0)
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
                collectingSummary: "First 3 days are observation mode — no cap enforced. On day 4 your personalized plan starts from your self-report plus the 3 observed days.",
                activeSummary: comebackAnchor != nil
                    ? plan.summary
                    : "Today’s scroll windows are locked from the morning check. Mivo trims your target from your blended baseline.",
                reason: plan.collecting ? "Your times are saved for tracking. Days 1–3 have no enforced cap — Mivo just observes." : "These windows are the schedule you locked for today. You can choose again tomorrow morning."
            )
        }
        if plan.collecting {
            return planReplacingWindows(
                in: plan,
                windows: [],
                idSuffix: "needs-daily-schedule",
                collectingSummary: "First 3 days are observation mode — no cap enforced. Choose times if you want Mivo to watch those periods. Your personalized plan starts on day 4 from your self-report plus the 3 observed days.",
                activeSummary: nil,
                reason: "Mivo will not enforce a default window before you lock today’s schedule."
            )
        }
        return plan
    }

    func syncLearningModeProtectionState() {
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
            profile: onboardingProfile,
            dailyObservations: dailyScreenTimeObservations,
            comeback: comebackAnchor
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

    func todayKey() -> String { MivoDay.todayKey }

    /// Today's real usage, or the reason it cannot be shown.
    ///
    /// Deliberately does not fall back to Mivo's own session minutes: those
    /// count only time inside a Mivo session, so presenting them as "actual"
    /// tells the user they wildly overestimated when in fact Mivo just could
    /// not see their usage.
    var screenTimeToday: MivoMeasurement {
        guard FamilyControlsManager.shared.cachedAuthorizationStatus() == true else {
            return .unavailable(.screenTimeNotAuthorized)
        }
        guard let minutes = deviceActivityMinutesToday else {
            return .unavailable(.awaitingFirstReport)
        }
        if let generated = deviceActivityReportGeneratedAt,
           MivoDay.key(generated) != MivoDay.todayKey {
            return .unavailable(.reportFromAnotherDay)
        }
        return .available(minutes)
    }

    private func timeTruthActualMinutesForToday() -> Int? {
        refreshScreenTimeData()
        return screenTimeToday.minutes
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
        let count = adaptiveDailyWindowCount(for: baseline)
        let defaults = Array([(9, "Morning"), (14, "Afternoon"), (19, "Evening"), (21, "Night")].prefix(count))
        let minutes = evenDailyWindowMinutes(total: baseline, count: count)
        return defaults.enumerated().map { index, preset in
            let allowed = minutes.indices.contains(index) ? minutes[index] : max(5, baseline / max(1, count))
            let length = baseline > 180 && allowed > 60 ? 2 : 1
            return ScreenScrollWindow(
                id: "daily-session-\(index + 1)",
                title: "Session \(index + 1)",
                startHour: preset.0,
                endHour: min(24, preset.0 + length),
                minutes: allowed,
                reason: "\(preset.1) scroll window."
            )
        }
    }

    private func normalizeDailyScrollWindows(_ windows: [ScreenScrollWindow]) -> [ScreenScrollWindow] {
        windows.enumerated().map { index, window in
            let start = ((window.startHour % 24) + 24) % 24
            let originalLength = max(1, min(2, window.endHour - window.startHour))
            let end = min(24, start + originalLength)
            return ScreenScrollWindow(
                id: "daily-session-\(index + 1)",
                title: "Today’s session \(index + 1)",
                startHour: start,
                endHour: end,
                minutes: max(0, window.minutes),
                reason: "Locked for today. You can choose new times tomorrow morning."
            )
        }
    }

    private func adaptiveDailyWindowCount(for targetMinutes: Int) -> Int {
        if targetMinutes > 180 { return 4 }
        if targetMinutes > 90 { return 3 }
        return 2
    }

    private func evenDailyWindowMinutes(total: Int, count: Int) -> [Int] {
        guard count > 0 else { return [] }
        guard total > 0 else { return Array(repeating: 0, count: count) }
        let base = total / count
        let remainder = total % count
        return (0..<count).map { base + ($0 < remainder ? 1 : 0) }
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

    var lateNightProtectionEnabled: Bool {
        settings.lateNightProtectionEnabled == true
    }

    var lateNightStartHour: Int {
        min(23, max(20, settings.lateNightStartHour ?? 22))
    }

    var lateNightWakeHour: Int {
        min(10, max(5, settings.lateNightWakeHour ?? 7))
    }

    func isLateNightProtectionActive(at now: Date = Date()) -> Bool {
        guard lateNightProtectionEnabled else { return false }
        let hour = Calendar.current.component(.hour, from: now)
        return hour >= lateNightStartHour || hour < lateNightWakeHour
    }

    func lateNightWakeDate(after now: Date = Date()) -> Date {
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: now)
        let dayOffset = hour < lateNightWakeHour ? 0 : 1
        let wakeDay = calendar.date(byAdding: .day, value: dayOffset, to: now) ?? now
        return calendar.date(
            bySettingHour: lateNightWakeHour,
            minute: 0,
            second: 0,
            of: wakeDay
        ) ?? wakeDay
    }

    func lateNightWakeTimeText(at now: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: lateNightWakeDate(after: now))
    }

    func hasUsedLastScrollTonight(at now: Date = Date()) -> Bool {
        settings.lastScrollNightKey == lateNightPeriodKey(for: now)
    }

    func markLastScrollOfNightStarted(at now: Date = Date()) {
        settings.lastScrollNightKey = lateNightPeriodKey(for: now)
        let updated = settings
        settings = updated
        saveForCurrentUser(updated, forKey: .settings)
    }

    func updateLateNightProtection(enabled: Bool, startHour: Int, wakeHour: Int) {
        settings.lateNightProtectionEnabled = enabled
        settings.lateNightStartHour = min(23, max(20, startHour))
        settings.lateNightWakeHour = min(10, max(5, wakeHour))
        let updated = settings
        settings = updated
        saveForCurrentUser(updated, forKey: .settings)
    }

    private func lateNightPeriodKey(for now: Date) -> String {
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: now)
        let anchor = hour < lateNightWakeHour
            ? (calendar.date(byAdding: .day, value: -1, to: now) ?? now)
            : now
        return MivoDay.key(anchor)
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
        let total = weekSessions.reduce(0) { partial, session in
            partial + min(1_440, max(0, session.actualDuration))
        }
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

    /// The fields that actually matter for whether a widget reload is
    /// worth it — everything in `WidgetSharedSummary` except its own
    /// `updatedAt` timestamp, which would otherwise always differ and make
    /// change detection pointless.
    private var lastWidgetSummarySignature: String?

    func updateWidgetSharedSummary() {
        let plan = adaptiveScreenTimePlan()
        let nextWindow = nextWidgetWindowText(for: plan)
        let trackedScrollMinutes = todaysSessions.reduce(0) { total, session in
            total + session.actualDuration
        }
        let scrolledMinutesToday = deviceActivityMinutesToday ?? trackedScrollMinutes
        let planState = plan.collecting ? "Learning mode" : "\(plan.targetMinutes)m target"
        let streakText = "\(todaysSessions.count) session\(todaysSessions.count == 1 ? "" : "s") today"

        // `loadDeviceActivityReport()` calls this on every code path, and
        // HomeView polls that every 5 seconds for as long as the app is
        // open — this used to call `WidgetCenter.reloadAllTimelines()`
        // unconditionally on every one of those polls, regardless of
        // whether anything had changed. That's a full widget-timeline
        // reload (a real XPC round trip to the widget extension, confirmed
        // via Console showing a flood of MivoWidgets state-update messages)
        // every 5 seconds, forever — a genuine, ongoing, app-wide
        // performance cost and a very likely cause of "everything feels
        // laggy." Skip all of it, including the storage write, when
        // nothing meaningful actually changed.
        let focusedMinutesToday = MivoStillStore.shared.minutesToday
        let signature = "\(recoveredMinutes(from: todaysSessions))|\(scrolledMinutesToday)|\(nextWindow)|\(planState)|\(streakText)|\(focusedMinutesToday)"
        guard signature != lastWidgetSummarySignature else { return }
        lastWidgetSummarySignature = signature

        let summary = WidgetSharedSummary(
            recoveredMinutesToday: recoveredMinutes(from: todaysSessions),
            screenTimeMinutesToday: scrolledMinutesToday,
            nextScrollWindow: nextWindow,
            planState: planState,
            streakText: streakText,
            updatedAt: ISO8601DateFormatter().string(from: Date()),
            focusedMinutesToday: focusedMinutesToday
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
        personalizedPatternInsights().map(\.title)
    }

    func dailyTruthSummary(for check: TruthCheckGuess) -> DailyTruthSummary {
        let accuracy = truthAccuracyScore(guess: check.guess, actual: check.actual)
        let forgotten = max(0, check.actual - check.guess)
        let overestimated = max(0, check.guess - check.actual)
        let breakdown = forgottenTimeBreakdown(for: check)
        let daySessions = sessions.filter { $0.date == check.date }
        let timeLabel = truthTimeBucket(for: check)

        let insight: PersonalizedPatternInsight
        if forgotten >= 5, let top = breakdown.first {
            let appMinutes = normalizedAppMinutes(check.perAppMinutes ?? [:])[top.appName] ?? 0
            insight = PersonalizedPatternInsight(
                id: "daily-app-\(check.id)",
                title: "Most of today’s missing time likely clustered in \(top.appName).",
                detail: "\(top.appName) had \(formatInsightMinutes(appMinutes)) by the \(timeLabel) truth check.",
                evidence: "Mivo estimates about \(formatInsightMinutes(top.minutes)) of the \(formatInsightMinutes(forgotten)) gap from its share of today’s app usage.",
                tomorrowExperiment: "Tomorrow, pause before your first \(top.appName) opening and name the one thing you plan to do there.",
                icon: "sparkles"
            )
        } else if let topUrge = mostCommonUrge(in: daySessions) {
            let matching = daySessions.filter { $0.urgeReason == topUrge }
            let average = matching.isEmpty ? 0 : matching.reduce(0) { $0 + $1.actualDuration } / matching.count
            insight = PersonalizedPatternInsight(
                id: "daily-urge-\(check.id)",
                title: "\(topUrge.rawValue) was today’s strongest recorded trigger.",
                detail: "Those sessions averaged \(formatInsightMinutes(average)).",
                evidence: "Based on \(matching.count) reflected session\(matching.count == 1 ? "" : "s") today.",
                tomorrowExperiment: replacementExperiment(for: topUrge),
                icon: "brain.head.profile"
            )
        } else if accuracy >= 85 {
            insight = PersonalizedPatternInsight(
                id: "daily-accurate-\(check.id)",
                title: "Your estimate was close to the truth today.",
                detail: "Your accuracy score was \(accuracy)%.",
                evidence: "The estimate was \(formatInsightMinutes(abs(check.actual - check.guess))) from the measured total.",
                tomorrowExperiment: "Tomorrow, make the estimate at the same time and see whether the gap stays this small.",
                icon: "scope"
            )
        } else if overestimated > 0 {
            insight = PersonalizedPatternInsight(
                id: "daily-over-\(check.id)",
                title: "You expected more scrolling than Mivo measured.",
                detail: "Your estimate was \(formatInsightMinutes(overestimated)) above the actual total.",
                evidence: "Overestimates still improve awareness because they show where your internal clock is recalibrating.",
                tomorrowExperiment: "Tomorrow, estimate once without checking Screen Time first and compare the direction of the gap.",
                icon: "arrow.down.right"
            )
        } else {
            insight = PersonalizedPatternInsight(
                id: "daily-learning-\(check.id)",
                title: "Mivo is learning how your internal clock compares with real usage.",
                detail: "A few more daily checks will reveal app, trigger, and time-of-day patterns.",
                evidence: "Today’s accuracy score was \(accuracy)%.",
                tomorrowExperiment: "Make tomorrow’s estimate before opening any usage report.",
                icon: "chart.line.uptrend.xyaxis"
            )
        }

        return DailyTruthSummary(
            check: check,
            accuracyScore: accuracy,
            forgottenMinutes: forgotten,
            overestimatedMinutes: overestimated,
            forgottenBreakdown: breakdown,
            insight: insight
        )
    }

    func personalizedPatternInsights(limit: Int = 3) -> [PersonalizedPatternInsight] {
        var insights: [PersonalizedPatternInsight] = []
        let orderedChecks = truthChecks.sorted { truthSortKey($0) < truthSortKey($1) }

        if orderedChecks.count >= 4 {
            let recentCount = min(3, orderedChecks.count / 2)
            let recent = Array(orderedChecks.suffix(recentCount))
            let earlier = Array(orderedChecks.dropLast(recentCount).suffix(recentCount))
            let change = averageTruthError(earlier) - averageTruthError(recent)
            if change >= 3 {
                insights.append(PersonalizedPatternInsight(
                    id: "accuracy-improving",
                    title: "Your screen-time guesses are becoming more accurate.",
                    detail: "Recent guesses are about \(formatInsightMinutes(change)) closer to the truth.",
                    evidence: "Compared your latest \(recent.count) checks with the \(earlier.count) before them.",
                    tomorrowExperiment: "Keep guessing before the reveal. Try to stay within 10 minutes tomorrow.",
                    icon: "scope"
                ))
            }
        }

        let underestimated = orderedChecks.filter { $0.actual > $0.guess && !($0.perAppMinutes ?? [:]).isEmpty }
        if underestimated.count >= 2 {
            var appForgotten: [String: Int] = [:]
            var appBuckets: [String: [String: Int]] = [:]
            for check in underestimated {
                for slice in forgottenTimeBreakdown(for: check) {
                    appForgotten[slice.appName, default: 0] += slice.minutes
                    appBuckets[slice.appName, default: [:]][truthTimeBucket(for: check), default: 0] += slice.minutes
                }
            }
            if let top = appForgotten.max(by: { $0.value < $1.value }) {
                let bucket = appBuckets[top.key]?.max(by: { $0.value < $1.value })?.key ?? "daily"
                insights.append(PersonalizedPatternInsight(
                    id: "app-underestimate-\(top.key)",
                    title: "You underestimate \(top.key) most around your \(bucket) check.",
                    detail: "Its estimated share of forgotten time is \(formatInsightMinutes(top.value)) across recent checks.",
                    evidence: "This uses the app-level Screen Time mix saved at each reveal, not a generic guess.",
                    tomorrowExperiment: "Tomorrow, avoid \(top.key) for the first 15 minutes of your usual \(bucket) scroll period.",
                    icon: "apps.iphone"
                ))
            }
        }

        let recentSessions = Array(sessions.sorted { $0.startTime < $1.startTime }.suffix(30))
        let habit = recentSessions.filter { $0.urgeReason == .habit }
        let message = recentSessions.filter { $0.urgeReason == .message }
        if habit.count >= 2, habit.count > message.count {
            let average = habit.reduce(0) { $0 + $1.actualDuration } / habit.count
            insights.append(PersonalizedPatternInsight(
                id: "habit-trigger",
                title: "Habit is a more common recorded trigger than messages.",
                detail: "Habit openings averaged \(formatInsightMinutes(average)) and appeared \(habit.count) times.",
                evidence: "Compared the trigger selected before each recent protected-app session.",
                tomorrowExperiment: "For the first habit opening tomorrow, return to the previous activity instead of starting the session.",
                icon: "arrow.triangle.2.circlepath"
            ))
        }

        let night = recentSessions.filter { sessionHour($0).map { $0 >= 21 || $0 < 6 } == true }
        let daytime = recentSessions.filter { sessionHour($0).map { $0 >= 6 && $0 < 21 } == true }
        if night.count >= 2, !daytime.isEmpty {
            let nightAverage = night.reduce(0) { $0 + $1.actualDuration } / night.count
            let dayAverage = daytime.reduce(0) { $0 + $1.actualDuration } / daytime.count
            if nightAverage >= max(dayAverage + 5, Int(Double(dayAverage) * 1.25)) {
                insights.append(PersonalizedPatternInsight(
                    id: "night-longer",
                    title: "Sessions started at night last longer.",
                    detail: "Night sessions average \(formatInsightMinutes(nightAverage)) versus \(formatInsightMinutes(dayAverage)) during the day.",
                    evidence: "Based on \(night.count + daytime.count) recent sessions.",
                    tomorrowExperiment: "Make the final planned window your last scroll of the night and finish without extending it.",
                    icon: "moon.stars.fill"
                ))
            }
        }

        if insights.isEmpty, let latest = orderedChecks.last {
            insights.append(dailyTruthSummary(for: latest).insight)
        }
        if insights.isEmpty, sessions.count >= 2 {
            let average = sessions.reduce(0) { $0 + $1.actualDuration } / sessions.count
            insights.append(PersonalizedPatternInsight(
                id: "session-baseline",
                title: "Your current session baseline is \(formatInsightMinutes(average)).",
                detail: "Mivo needs a few truth checks to connect this with real app totals.",
                evidence: "Based on \(sessions.count) saved sessions.",
                tomorrowExperiment: "Complete one truth check tomorrow before reviewing Screen Time.",
                icon: "chart.bar.fill"
            ))
        }
        return Array(insights.prefix(max(1, limit)))
    }

    func weeklyTruthSummary(for dateKeys: [String]) -> WeeklyTruthSummary {
        let allowed = Set(dateKeys)
        let checks = truthChecks.filter { allowed.contains($0.date) }.sorted { truthSortKey($0) < truthSortKey($1) }
        let scores = checks.map { truthAccuracyScore(guess: $0.guess, actual: $0.actual) }
        let averageScore = scores.isEmpty ? 0 : scores.reduce(0, +) / scores.count
        let forgotten = checks.reduce(0) { $0 + max(0, $1.actual - $1.guess) }
        let signedGap = checks.isEmpty ? 0 : checks.reduce(0) { $0 + ($1.actual - $1.guess) } / checks.count
        var appTotals: [String: Int] = [:]
        for check in checks {
            for slice in forgottenTimeBreakdown(for: check) {
                appTotals[slice.appName, default: 0] += slice.minutes
            }
        }

        let change: Int?
        if checks.count >= 4 {
            let split = checks.count / 2
            let earlier = Array(checks.prefix(split))
            let recent = Array(checks.suffix(checks.count - split))
            let earlierScore = earlier.map { truthAccuracyScore(guess: $0.guess, actual: $0.actual) }.reduce(0, +) / max(1, earlier.count)
            let recentScore = recent.map { truthAccuracyScore(guess: $0.guess, actual: $0.actual) }.reduce(0, +) / max(1, recent.count)
            change = recentScore - earlierScore
        } else {
            change = nil
        }

        return WeeklyTruthSummary(
            checkCount: checks.count,
            averageAccuracyScore: averageScore,
            totalForgottenMinutes: forgotten,
            averageSignedGapMinutes: signedGap,
            accuracyChangePoints: change,
            topForgottenApp: appTotals.max(by: { $0.value < $1.value })?.key,
            dailyAccuracyScores: Array(zip(checks.map(\.date), scores)).map { (date: $0.0, score: $0.1) }
        )
    }

    private func currentPerAppMinutesSnapshot(for dateKey: String) -> [String: Int]? {
        if let generated = deviceActivityReportGeneratedAt {
            guard MivoDay.key(generated) == dateKey else { return nil }
        }
        let snapshot = deviceActivityPerAppSeconds.reduce(into: [String: Int]()) { result, item in
            guard item.value > 0 else { return }
            result[readableAppName(item.key)] = max(1, Int((Double(item.value) / 60.0).rounded()))
        }
        return snapshot.isEmpty ? nil : snapshot
    }

    private func forgottenTimeBreakdown(for check: TruthCheckGuess) -> [ForgottenTimeSlice] {
        let gap = max(0, check.actual - check.guess)
        let apps = normalizedAppMinutes(check.perAppMinutes ?? [:]).filter { $0.value > 0 }
        let total = apps.values.reduce(0, +)
        guard gap > 0, total > 0 else { return [] }
        return apps.sorted { $0.value > $1.value }.prefix(3).compactMap { app, minutes in
            let share = Double(minutes) / Double(total)
            let estimated = Int((Double(gap) * share).rounded())
            guard estimated > 0 else { return nil }
            return ForgottenTimeSlice(appName: app, minutes: estimated, share: share)
        }
    }

    private func normalizedAppMinutes(_ apps: [String: Int]) -> [String: Int] {
        apps.reduce(into: [String: Int]()) { result, item in
            result[readableAppName(item.key), default: 0] += max(0, item.value)
        }
    }

    private func readableAppName(_ raw: String) -> String {
        let lower = raw.lowercased()
        if lower.contains("instagram") { return "Instagram" }
        if lower.contains("tiktok") { return "TikTok" }
        if lower.contains("youtube") { return "YouTube" }
        if lower.contains("reddit") { return "Reddit" }
        if lower.contains("snapchat") { return "Snapchat" }
        if lower.contains("facebook") { return "Facebook" }
        if lower.contains("twitter") || lower.hasSuffix(".x") { return "X" }
        let last = raw.split(separator: ".").last.map(String.init) ?? raw
        return last.replacingOccurrences(of: "-", with: " ").capitalized
    }

    private func truthAccuracyScore(guess: Int, actual: Int) -> Int {
        if actual == 0 { return guess == 0 ? 100 : 0 }
        let error = Double(abs(actual - guess)) / Double(max(actual, 1))
        return max(0, min(100, Int(((1 - error) * 100).rounded())))
    }

    private func averageTruthError(_ checks: [TruthCheckGuess]) -> Int {
        guard !checks.isEmpty else { return 0 }
        return checks.reduce(0) { $0 + abs($1.actual - $1.guess) } / checks.count
    }

    private func truthSortKey(_ check: TruthCheckGuess) -> String { check.checkedAt ?? check.date }

    private func truthTimeBucket(for check: TruthCheckGuess) -> String {
        guard let text = check.checkedAt, let date = ISO8601DateFormatter().date(from: text) else { return "daily" }
        let hour = Calendar.current.component(.hour, from: date)
        if hour < 6 || hour >= 21 { return "night" }
        if hour < 12 { return "morning" }
        if hour < 17 { return "afternoon" }
        return "evening"
    }

    private func mostCommonUrge(in measured: [Session]) -> UrgeReason? {
        Dictionary(grouping: measured.compactMap(\.urgeReason), by: { $0 })
            .max(by: { $0.value.count < $1.value.count })?.key
    }

    private func sessionHour(_ session: Session) -> Int? {
        ISO8601DateFormatter().date(from: session.startTime).map { Calendar.current.component(.hour, from: $0) }
    }

    private func replacementExperiment(for urge: UrgeReason) -> String {
        switch urge {
        case .habit: return "Tomorrow, return to the previous activity on the first habit opening."
        case .bored: return "Tomorrow, take a two-minute walk before the first boredom-driven session."
        case .stressed: return "Tomorrow, take four slow breaths before deciding whether to continue."
        case .message: return "Tomorrow, open the conversation directly and leave when the reply is sent."
        case .specificTask: return "Tomorrow, write the exact task before opening and finish when it is done."
        case .other: return "Tomorrow, name the exact reason before starting the first session."
        }
    }

    private func formatInsightMinutes(_ minutes: Int) -> String {
        let safe = max(0, minutes)
        if safe >= 60 { return "\(safe / 60)h \(safe % 60)m" }
        return "\(safe)m"
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
                recordDailyScreenTimeObservation(minutes: report.totalMinutes, date: report.reportDate)
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

    private func recordDailyScreenTimeObservation(minutes: Int, date: String) {
        guard isLoggedIn, !date.isEmpty else { return }
        let safeMinutes = max(0, minutes)
        if let index = dailyScreenTimeObservations.firstIndex(where: { $0.date == date }) {
            guard safeMinutes > dailyScreenTimeObservations[index].minutes else { return }
            dailyScreenTimeObservations[index] = DailyScreenTimeObservation(
                date: date,
                minutes: safeMinutes,
                recordedAt: ISO8601DateFormatter().string(from: Date())
            )
        } else {
            dailyScreenTimeObservations.append(
                DailyScreenTimeObservation(
                    date: date,
                    minutes: safeMinutes,
                    recordedAt: ISO8601DateFormatter().string(from: Date())
                )
            )
        }
        dailyScreenTimeObservations = Array(
            dailyScreenTimeObservations.sorted { $0.date > $1.date }.prefix(45)
        )
        saveForCurrentUser(dailyScreenTimeObservations, forKey: .dailyScreenTimeObservations)
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
        return (MivoDay.key(start), MivoDay.key(end))
    }

    private func recoveredMinutes(from sessions: [Session]) -> Int {
        let planned = sessions.reduce(0) { partial, session in
            min(10_080, partial + min(1_440, max(0, session.plannedDuration)))
        }
        let actual = sessions.reduce(0) { partial, session in
            min(10_080, partial + min(1_440, max(0, session.actualDuration)))
        }
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
            let boundedMinutes = min(1_440, max(session.actualDuration, 1))
            buckets[bucket] = min(10_080, buckets[bucket, default: 0] + boundedMinutes)
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
        record.accountRole = remoteUser.isAdmin == true ? "super_admin" : (record.accountRole ?? "user")
        record.adminToken = remoteUser.adminToken
        record.remoteUserId = remoteUser.remoteUserId
        record.remoteAccessToken = remoteUser.accessToken
        record.remoteRefreshToken = remoteUser.refreshToken
        try SecureAuthService.saveRecord(record)
    }

    private func validateActiveRemoteSessionIfNeeded(email: String) {
        let normalizedEmail = email.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard RemoteAuthService.isConfigured,
              let record = SecureAuthService.loadRecord(email: normalizedEmail),
              record.remoteUserId != nil else { return }

        Task { await validateActiveRemoteSession(email: normalizedEmail) }
    }

    private func validateActiveRemoteSession(email: String) async {
        guard isLoggedIn,
              user?.email.lowercased() == email,
              var record = SecureAuthService.loadRecord(email: email) else { return }

        do {
            let remoteUser = try await RemoteAuthService.validateStoredSession(record: record)
            let installationID = try DeviceBindingService.installationID()
            try await RemoteAuthService.claimDevice(installationID: installationID, user: remoteUser)
            try DeviceBindingService.bind(
                userID: remoteUser.remoteUserId ?? email,
                email: remoteUser.email
            )
            record.name = remoteUser.name
            record.createdAt = remoteUser.createdAt
            record.onboardingProfile = remoteUser.onboardingProfile ?? record.onboardingProfile
            record.isAdmin = remoteUser.isAdmin == true
            if remoteUser.isAdmin == true { record.accountRole = "super_admin" }
            record.adminToken = remoteUser.adminToken
            record.remoteUserId = remoteUser.remoteUserId
            record.remoteAccessToken = remoteUser.accessToken ?? record.remoteAccessToken
            record.remoteRefreshToken = remoteUser.refreshToken ?? record.remoteRefreshToken
            try? SecureAuthService.saveRecord(record)
            if let currentUser = user {
                user = UserProfile(
                    email: currentUser.email,
                    name: remoteUser.name,
                    createdAt: currentUser.createdAt,
                    onboardingProfile: currentUser.onboardingProfile,
                    isAdmin: remoteUser.isAdmin == true,
                    accountRole: record.accountRole
                )
            }
        } catch AppError.invalidCredentials {
            // NOT reliable proof the account was deleted — Supabase rotates
            // refresh tokens on every use, so a concurrent or retried
            // refresh can legitimately invalidate a token that was still
            // good moments earlier. This used to call
            // handleDeletedRemoteAccount(), wiping every local session,
            // screen time record, and everything else on nothing more than
            // a background network hiccup. Sign out of the stale remote
            // session only; local data is untouched and reloads correctly
            // on the next successful login.
            signOutOfStaleRemoteSession()
        } catch AppError.noAccount {
            signOutOfStaleRemoteSession()
        } catch {
            // Keep the user in place for temporary network/server failures, but
            // never treat the local keychain as proof that the remote account exists.
        }
    }

    /// Signs out of a remote session that failed to validate or refresh,
    /// without touching anything locally stored — see the comment at the
    /// call site for why a background check can never be trusted enough to
    /// delete data. `resetUserScopedState()` only clears in-memory
    /// `@Published` state (the same thing a normal `logout()` does); the
    /// on-disk, email-scoped records are left exactly as they were, so a
    /// false positive costs nothing more than having to log back in, and a
    /// genuinely deleted account simply can't.
    private func signOutOfStaleRemoteSession() {
        StorageService.remove(forKey: .authSession)
        StorageService.remove(forKey: .rememberedEmail)
        FamilyControlsManager.shared.setLearningModeUnlocked(false)
        FamilyControlsManager.shared.setSignedInForImpulseProtection(false)
        user = nil
        adminToken = nil
        isLoggedIn = false
        resetUserScopedState()
    }

    private func applyRestrictionState(for email: String) {
        syncLearningModeProtectionState()
        FamilyControlsManager.shared.setSignedInForImpulseProtection(true)
    }

    // MARK: - Weekly experiments

    var sortedWeeklyExperiments: [WeeklyExperiment] {
        weeklyExperiments.sorted {
            let lhsUpdated = WeeklyExperiment.experimentDate(from: $0.updatedAt)
            let rhsUpdated = WeeklyExperiment.experimentDate(from: $1.updatedAt)
            if lhsUpdated != rhsUpdated { return (lhsUpdated ?? .distantPast) > (rhsUpdated ?? .distantPast) }
            let lhsCreated = WeeklyExperiment.experimentDate(from: $0.createdAt)
            let rhsCreated = WeeklyExperiment.experimentDate(from: $1.createdAt)
            return (lhsCreated ?? .distantPast) > (rhsCreated ?? .distantPast)
        }
    }

    var proposedWeeklyExperiment: WeeklyExperiment? {
        sortedWeeklyExperiments.first { $0.status == .proposed }
    }

    var activeWeeklyExperiment: WeeklyExperiment? {
        sortedWeeklyExperiments.first { $0.status == .active }
    }

    var currentWeeklyExperiment: WeeklyExperiment? {
        activeWeeklyExperiment ?? proposedWeeklyExperiment ?? completedWeeklyExperimentAwaitingDecision
    }

    var completedWeeklyExperiments: [WeeklyExperiment] {
        sortedWeeklyExperiments.filter { $0.status == .completed }
    }

    var declinedWeeklyExperiments: [WeeklyExperiment] {
        sortedWeeklyExperiments.filter { $0.status == .declined }
    }

    var canStartWeeklyExperiment: Bool {
        activeWeeklyExperiment == nil
            && proposedWeeklyExperiment == nil
            && completedWeeklyExperimentAwaitingDecision == nil
    }

    var enforcedWeeklyExperiment: WeeklyExperiment? {
        if let activeWeeklyExperiment { return activeWeeklyExperiment }
        guard let latestCompleted = completedWeeklyExperiments.first else { return nil }
        return latestCompleted.finalDecision == .keep ? latestCompleted : nil
    }

    var weeklyExperimentEnforcementPolicy: WeeklyExperimentEnforcementPolicy {
        WeeklyExperimentEnforcementPolicy(experiment: enforcedWeeklyExperiment)
    }

    var experimentBlocksExtensions: Bool {
        weeklyExperimentEnforcementPolicy.blocksExtensions
    }

    var experimentStrengthensRepeatedOpenings: Bool {
        weeklyExperimentEnforcementPolicy.strengthensRepeatedOpenings
    }

    func interventionFrictionState(
        from standardState: InterventionFrictionState,
        now: Date = Date()
    ) -> InterventionFrictionState {
        let adaptiveSeconds = AIService.adaptiveInterventionPauseSeconds(
            attemptCount: standardState.attemptCount,
            recentAttempts: interventionAttempts,
            now: now
        )
        let repeatedOpening = standardState.attemptCount >= 2 || adaptiveSeconds >= 10
        let strongerExperiment = experimentStrengthensRepeatedOpenings && repeatedOpening
        let experimentCooldown = strongerExperiment && standardState.attemptCount >= 3 ? 120 : 10
        // The pause length chosen during onboarding sets the floor. An active
        // experiment or a repeated opening can still raise it, but never lowers
        // what the user asked for.
        let chosen = onboardingProfile.pauseStyle ?? .fiveSecond
        let baseSeconds = repeatedOpening ? max(10, chosen.waitSeconds) : chosen.waitSeconds
        return InterventionFrictionState(
            level: strongerExperiment ? 3 : (adaptiveSeconds >= 10 ? 2 : 1),
            attemptCount: standardState.attemptCount,
            waitSeconds: strongerExperiment ? max(experimentCooldown, baseSeconds) : baseSeconds
        )
    }

    /// Whether the pause should ask what the user came to do, per the pause
    /// style chosen in onboarding.
    var interventionAsksReason: Bool {
        onboardingProfile.pauseStyle?.asksReason ?? false
    }

    var completedWeeklyExperimentAwaitingDecision: WeeklyExperiment? {
        sortedWeeklyExperiments.first { $0.status == .completed && $0.finalDecision == nil }
    }

    var completedWeeklyExperimentAwaitingFeedback: WeeklyExperiment? {
        sortedWeeklyExperiments.first {
            $0.status == .completed && $0.finalDecision == nil && $0.userFeedback == nil
        }
    }

    func refreshWeeklyExperiments() async {
        guard isLoggedIn else { return }
        do {
            try await prepareAuthenticatedCampaignSession()
            let remote = try await ReferralCampaignService.loadWeeklyExperiments()
            var merged = Dictionary(uniqueKeysWithValues: remote.map { ($0.id, $0) })
            let remoteActiveID = remote.first(where: { $0.status == .active })?.id
            for local in weeklyExperiments {
                let remoteVersion = merged[local.id]
                if remoteVersion == nil || preferredExperimentVersion(local, over: remoteVersion!) {
                    if local.status == .active, let remoteActiveID, remoteActiveID != local.id {
                        continue
                    }
                    do {
                        let saved = try await ReferralCampaignService.saveWeeklyExperiment(local)
                        merged[saved.id] = saved
                    } catch {
                        if remoteVersion == nil { merged[local.id] = local }
                    }
                }
            }
            weeklyExperiments = merged.values.sorted { $0.createdAt > $1.createdAt }
            saveForCurrentUser(weeklyExperiments, forKey: .weeklyExperiments)
        } catch {
            // Local state keeps the behavior available while offline.
        }
        finishWeeklyExperimentIfNeeded()
        syncWeeklyExperimentEnforcement()
        proposeWeeklyExperimentIfEligible()
    }

    /// Re-evaluates calendar-day progress whenever Mivo becomes active or crosses
    /// midnight. `dayNumber` is derived, so this explicit publication keeps an
    /// already-visible Home/Experiments screen from remaining on yesterday's day.
    func refreshWeeklyExperimentLifecycle(now: Date = Date()) {
        finishWeeklyExperimentIfNeeded(now: now)
        objectWillChange.send()
    }

    func proposeWeeklyExperimentIfEligible(now: Date = Date()) {
        guard settings.onboardingComplete,
              activeWeeklyExperiment == nil,
              proposedWeeklyExperiment == nil,
              completedWeeklyExperimentAwaitingDecision == nil,
              observationDaysElapsed(now: now) >= 3,
              sessions.count >= 3 || observationDaysElapsed(now: now) >= 7 else { return }

        if let latest = sortedWeeklyExperiments.first,
           let created = WeeklyExperiment.experimentDate(from: latest.createdAt),
           now.timeIntervalSince(created) < 7 * 86_400 { return }

        let baselineStart = Calendar.current.date(byAdding: .day, value: -7, to: now) ?? now
        let baseline = experimentMetrics(from: baselineStart, to: now)
        let recentSessions = sessionsInRange(from: baselineStart, to: now)
        let extensionRate = recentSessions.isEmpty ? 0 : Double(recentSessions.filter(\.extendedOnce).count) / Double(recentSessions.count)
        let repeatedAutomatic = recentSessions.filter { $0.urgeReason == .habit || $0.urgeReason == .bored }.count
        let type: WeeklyExperimentType = extensionRate >= 0.25
            ? .reduceExtensions
            : (repeatedAutomatic >= 2 ? .strongerFriction : .protectedWindow)
        let clusteredHour = mostCommonSessionHour(in: recentSessions) ?? 21

        let presentation: (String, String, String, WeeklyExperimentRule)
        switch type {
        case .reduceExtensions:
            presentation = (
                "Try one week without extensions",
                "Extensions appeared in \(Int((extensionRate * 100).rounded()))% of your recent sessions. This experiment keeps the original limit intact.",
                "extension_rate",
                WeeklyExperimentRule(startHour: nil, endHour: nil, allowedMinutes: nil, strongerFrictionEnabled: false)
            )
        case .strongerFriction:
            presentation = (
                "Add friction to repeated openings",
                "Several recent sessions began from boredom or habit. Repeated openings within 30 minutes will use a stronger pause.",
                "cancellation_rate",
                WeeklyExperimentRule(startHour: nil, endHour: nil, allowedMinutes: nil, strongerFrictionEnabled: true)
            )
        case .protectedWindow:
            presentation = (
                "Protect your \(experimentHourLabel(clusteredHour)) hour",
                "Your recent sessions cluster around \(experimentHourLabel(clusteredHour)). Mivo can protect that hour unless today's locked schedule explicitly allows it.",
                "outside_window_minutes",
                WeeklyExperimentRule(startHour: clusteredHour, endHour: (clusteredHour + 1) % 24, allowedMinutes: 0, strongerFrictionEnabled: false)
            )
        }

        let timestamp = experimentTimestamp(now)
        let experiment = WeeklyExperiment(
            id: UUID().uuidString.lowercased(), userId: nil, type: type, status: .proposed,
            title: presentation.0, reason: presentation.1, primaryMetric: presentation.2,
            rule: presentation.3, baselineMetrics: baseline, resultMetrics: nil,
            startsAt: nil, endsAt: nil, outcome: nil, finalDecision: nil,
            createdAt: timestamp, updatedAt: timestamp
        )
        weeklyExperiments.insert(experiment, at: 0)
        persistWeeklyExperimentsAndSync(experiment, event: "weekly_experiment_proposed")
    }

    @discardableResult
    func createWeeklyExperimentProposal(from template: ExperimentTemplate, now: Date = Date()) -> WeeklyExperiment? {
        finishWeeklyExperimentIfNeeded(now: now)
        guard canStartWeeklyExperiment else { return nil }

        let baselineStart = Calendar.current.date(byAdding: .day, value: -7, to: now) ?? now
        let metric: String
        switch template.type {
        case .protectedWindow: metric = "outside_window_minutes"
        case .reduceExtensions: metric = "extension_rate"
        case .strongerFriction: metric = "cancellation_rate"
        }

        let timestamp = experimentTimestamp(now)
        let proposal = WeeklyExperiment(
            id: UUID().uuidString.lowercased(), userId: nil, type: template.type,
            status: .proposed, title: template.title, reason: template.detail,
            primaryMetric: metric, rule: template.rule,
            baselineMetrics: experimentMetrics(from: baselineStart, to: now),
            resultMetrics: nil, startsAt: nil, endsAt: nil, outcome: nil,
            finalDecision: nil, createdAt: timestamp, updatedAt: timestamp
        )
        weeklyExperiments.insert(proposal, at: 0)
        persistWeeklyExperimentsAndSync(proposal, event: "weekly_experiment_library_proposed")
        return proposal
    }

    @discardableResult
    func approveWeeklyExperiment(id: String, rule: WeeklyExperimentRule, now: Date = Date()) -> Bool {
        finishWeeklyExperimentIfNeeded(now: now)
        guard let index = weeklyExperiments.firstIndex(where: { $0.id == id && $0.status == .proposed }),
              activeWeeklyExperiment == nil else { return false }
        weeklyExperiments[index].status = .active
        weeklyExperiments[index].rule = rule
        weeklyExperiments[index].startsAt = experimentTimestamp(now)
        let startDay = Calendar.current.startOfDay(for: now)
        let calendarEnd = Calendar.current.date(byAdding: .day, value: 7, to: startDay) ?? now.addingTimeInterval(7 * 86_400)
        weeklyExperiments[index].endsAt = experimentTimestamp(calendarEnd)
        weeklyExperiments[index].updatedAt = experimentTimestamp(now)
        syncWeeklyExperimentEnforcement()
        persistWeeklyExperimentsAndSync(weeklyExperiments[index], event: "weekly_experiment_approved")
        return true
    }

    func declineWeeklyExperiment(id: String) {
        guard let index = weeklyExperiments.firstIndex(where: { $0.id == id && $0.status == .proposed }) else { return }
        weeklyExperiments[index].status = .declined
        weeklyExperiments[index].updatedAt = experimentTimestamp(Date())
        syncWeeklyExperimentEnforcement()
        persistWeeklyExperimentsAndSync(weeklyExperiments[index], event: "weekly_experiment_declined")
    }

    func finishWeeklyExperimentIfNeeded(now: Date = Date()) {
        guard let active = activeWeeklyExperiment,
              let endText = active.endsAt,
              let end = WeeklyExperiment.experimentDate(from: endText), now >= end,
              let index = weeklyExperiments.firstIndex(where: { $0.id == active.id }) else { return }
        let start = active.startsAt.flatMap(WeeklyExperiment.experimentDate(from:)) ?? end.addingTimeInterval(-7 * 86_400)
        let result = experimentMetrics(from: start, to: end)
        weeklyExperiments[index].resultMetrics = result
        weeklyExperiments[index].outcome = experimentOutcome(for: active, result: result)
        weeklyExperiments[index].status = .completed
        weeklyExperiments[index].updatedAt = experimentTimestamp(now)
        syncWeeklyExperimentEnforcement()
        persistWeeklyExperimentsAndSync(weeklyExperiments[index], event: "weekly_experiment_completed")
    }

    func decideWeeklyExperiment(id: String, decision: WeeklyExperimentDecision) {
        finalizeWeeklyExperimentReview(id: id, decision: decision, feedback: nil, note: nil)
    }

    func completeWeeklyExperimentReview(
        id: String,
        feedback: WeeklyExperimentFeedback,
        note: String,
        decision: WeeklyExperimentDecision
    ) {
        finalizeWeeklyExperimentReview(id: id, decision: decision, feedback: feedback, note: note)
    }

    private func finalizeWeeklyExperimentReview(
        id: String,
        decision: WeeklyExperimentDecision,
        feedback: WeeklyExperimentFeedback?,
        note: String?
    ) {
        guard let index = weeklyExperiments.firstIndex(where: { $0.id == id && $0.status == .completed }) else { return }
        let now = Date()
        let trimmedNote = note?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if let feedback {
            weeklyExperiments[index].userFeedback = feedback
            weeklyExperiments[index].feedbackNote = trimmedNote.isEmpty ? nil : String(trimmedNote.prefix(500))
            weeklyExperiments[index].feedbackSubmittedAt = experimentTimestamp(now)
        }
        weeklyExperiments[index].finalDecision = decision
        weeklyExperiments[index].updatedAt = experimentTimestamp(now)
        syncWeeklyExperimentEnforcement()
        let event = feedback == nil
            ? "weekly_experiment_decision_\(decision.rawValue)"
            : "weekly_experiment_feedback_\(feedback!.rawValue)_\(decision.rawValue)"
        persistWeeklyExperimentsAndSync(weeklyExperiments[index], event: event)

        if decision == .adjust, proposedWeeklyExperiment == nil, activeWeeklyExperiment == nil {
            let prior = weeklyExperiments[index]
            let timestamp = experimentTimestamp(now)
            let adjusted = WeeklyExperiment(
                id: UUID().uuidString.lowercased(), userId: nil, type: prior.type, status: .proposed,
                title: "Adjust \(prior.title.lowercased())",
                reason: "You chose to adjust the previous rule. Review the details before another seven-day experiment begins.",
                primaryMetric: prior.primaryMetric, rule: prior.rule,
                baselineMetrics: experimentMetrics(from: Calendar.current.date(byAdding: .day, value: -7, to: now) ?? now, to: now),
                resultMetrics: nil, startsAt: nil, endsAt: nil, outcome: nil, finalDecision: nil,
                createdAt: timestamp, updatedAt: timestamp
            )
            weeklyExperiments.insert(adjusted, at: 0)
            persistWeeklyExperimentsAndSync(adjusted, event: "weekly_experiment_adjustment_proposed")
        }
    }

    func recordInterventionAttempt() -> String {
        let id = UUID().uuidString.lowercased()
        interventionAttempts.append(InterventionAttemptRecord(id: id, occurredAt: ISO8601DateFormatter().string(from: Date()), continued: nil))
        interventionAttempts = Array(interventionAttempts.suffix(200))
        saveForCurrentUser(interventionAttempts, forKey: .interventionAttempts)
        CompanionInterventionAdapter.pauseBegan()
        return id
    }

    func resolveInterventionAttempt(id: String, continued: Bool) {
        guard let index = interventionAttempts.firstIndex(where: { $0.id == id }) else { return }
        interventionAttempts[index].continued = continued
        saveForCurrentUser(interventionAttempts, forKey: .interventionAttempts)
        CompanionInterventionAdapter.pauseResolved(continued: continued)
        Task { await ReferralCampaignService.logEvent(continued ? "intervention_continued" : "intervention_cancelled") }
    }

    private func syncWeeklyExperimentEnforcement() {
        let defaults = UserDefaults(suiteName: MivoScreenTimeKeys.appGroup)
        let experiment = enforcedWeeklyExperiment
        let policy = WeeklyExperimentEnforcementPolicy(experiment: experiment)

        defaults?.set(experiment != nil, forKey: MivoScreenTimeKeys.experimentEnforced)
        defaults?.set(experiment?.type.rawValue, forKey: MivoScreenTimeKeys.experimentType)
        defaults?.set(experiment?.title, forKey: MivoScreenTimeKeys.experimentTitle)
        defaults?.set(policy.rule?.startHour, forKey: MivoScreenTimeKeys.experimentStartHour)
        defaults?.set(policy.rule?.endHour, forKey: MivoScreenTimeKeys.experimentEndHour)
        defaults?.set(policy.blocksExtensions, forKey: MivoScreenTimeKeys.experimentBlocksExtensions)
        defaults?.set(policy.strengthensRepeatedOpenings, forKey: MivoScreenTimeKeys.experimentStrongerFriction)

        if experiment?.status == .active,
           let endsAt = experiment?.endsAt,
           let end = WeeklyExperiment.experimentDate(from: endsAt) {
            defaults?.set(end.timeIntervalSince1970, forKey: MivoScreenTimeKeys.experimentEndsAt)
        } else {
            defaults?.removeObject(forKey: MivoScreenTimeKeys.experimentEndsAt)
        }
        defaults?.synchronize()

        FamilyControlsManager.shared.setShieldPauseDuration(policy.strengthensRepeatedOpenings ? 10 : 5)
    }

    private func persistWeeklyExperimentsAndSync(_ experiment: WeeklyExperiment, event: String) {
        saveForCurrentUser(weeklyExperiments, forKey: .weeklyExperiments)
        Task {
            do {
                try await prepareAuthenticatedCampaignSession()
                await ReferralCampaignService.logEvent(event)
                let saved = try await ReferralCampaignService.saveWeeklyExperiment(experiment)
                if let index = weeklyExperiments.firstIndex(where: { $0.id == saved.id }) {
                    let current = weeklyExperiments[index]
                    if preferredExperimentVersion(saved, over: current) || saved == current {
                        weeklyExperiments[index] = saved
                        saveForCurrentUser(weeklyExperiments, forKey: .weeklyExperiments)
                    }
                }
            } catch {
                // The next refresh retries from local state.
            }
        }
    }

    private func experimentTimestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    private func preferredExperimentVersion(_ candidate: WeeklyExperiment, over current: WeeklyExperiment) -> Bool {
        let candidateDate = WeeklyExperiment.experimentDate(from: candidate.updatedAt)
        let currentDate = WeeklyExperiment.experimentDate(from: current.updatedAt)
        if let candidateDate, let currentDate, candidateDate != currentDate {
            return candidateDate > currentDate
        }
        if candidate.updatedAt != current.updatedAt {
            return candidate.updatedAt > current.updatedAt
        }

        // Legacy records can share the same second-level timestamp. Never let a
        // late proposal response erase the start date of an approved experiment.
        let candidateRank = experimentStatusRank(candidate.status)
        let currentRank = experimentStatusRank(current.status)
        if candidateRank != currentRank { return candidateRank > currentRank }
        if candidate.startsAt != nil, current.startsAt == nil { return true }
        return false
    }

    private func experimentStatusRank(_ status: WeeklyExperimentStatus) -> Int {
        switch status {
        case .proposed: return 0
        case .active: return 1
        case .declined, .completed: return 2
        }
    }

    private func observationDaysElapsed(now: Date) -> Int {
        guard let text = onboardingProfile.observationStartedAt,
              let start = ISO8601DateFormatter().date(from: text) else { return 0 }
        return max(0, Calendar.current.dateComponents([.day], from: start, to: now).day ?? 0)
    }

    private func sessionsInRange(from start: Date, to end: Date) -> [Session] {
        sessions.filter { session in
            guard let date = ISO8601DateFormatter().date(from: session.startTime) else { return false }
            return date >= start && date <= end
        }
    }

    private func experimentMetrics(from start: Date, to end: Date) -> ExperimentMetrics {
        let measured = sessionsInRange(from: start, to: end)
        let outsideMinutes = measured.reduce(0) { total, session in
            guard let date = ISO8601DateFormatter().date(from: session.startTime) else { return total }
            let hour = Calendar.current.component(.hour, from: date)
            guard let schedule = dailyScrollSchedule(for: session.date) else { return total + session.actualDuration }
            let isInside = schedule.windows.contains { scrollWindow($0, contains: hour) }
            return total + (isInside ? 0 : session.actualDuration)
        }
        let extensionRate = measured.isEmpty ? 0 : Double(measured.filter(\.extendedOnce).count) / Double(measured.count)
        let worthwhile = measured.filter { $0.outcomeScore == .worthIt }.count
        let scored = measured.filter { $0.outcomeScore != nil }.count
        let attempts = interventionAttempts.filter { attempt in
            guard let date = ISO8601DateFormatter().date(from: attempt.occurredAt) else { return false }
            return date >= start && date <= end
        }
        let resolvedAttempts = attempts.compactMap(\.continued)
        let cancellationRate = resolvedAttempts.isEmpty ? 0 : Double(resolvedAttempts.filter { !$0 }.count) / Double(resolvedAttempts.count)
        let startKey = MivoDay.key(start); let endKey = MivoDay.key(end)
        let truths = truthChecks.filter { $0.date >= startKey && $0.date <= endKey }
        let truthAccuracy = truths.isEmpty ? 0 : Double(truths.reduce(0) { $0 + abs($1.actual - $1.guess) }) / Double(truths.count)
        return ExperimentMetrics(
            comparableSessions: measured.count,
            outsideWindowMinutes: outsideMinutes,
            extensionRate: extensionRate,
            cancellationRate: cancellationRate,
            truthAccuracyMinutes: truthAccuracy,
            worthwhileRate: scored == 0 ? 0 : Double(worthwhile) / Double(scored)
        )
    }

    private func experimentOutcome(for experiment: WeeklyExperiment, result: ExperimentMetrics) -> WeeklyExperimentOutcome {
        guard result.comparableSessions >= 3 else { return .inconclusive }
        let baseline = experiment.baselineMetrics
        let improvement: Double
        switch experiment.type {
        case .protectedWindow:
            improvement = relativeReduction(from: Double(baseline.outsideWindowMinutes), to: Double(result.outsideWindowMinutes))
        case .reduceExtensions:
            improvement = relativeReduction(from: baseline.extensionRate, to: result.extensionRate)
        case .strongerFriction:
            improvement = relativeIncrease(from: baseline.cancellationRate, to: result.cancellationRate)
        }
        if improvement >= 0.10 { return .helped }
        if improvement <= -0.10 { return .worsened }
        return .inconclusive
    }

    private func scrollWindow(_ window: ScreenScrollWindow, contains hour: Int) -> Bool {
        let start = ((window.startHour % 24) + 24) % 24
        let end = ((window.endHour % 24) + 24) % 24
        let current = ((hour % 24) + 24) % 24
        if start == end { return true }
        return start < end
            ? (current >= start && current < end)
            : (current >= start || current < end)
    }

    private func relativeReduction(from baseline: Double, to result: Double) -> Double {
        baseline == 0 ? (result == 0 ? 0 : -1) : (baseline - result) / baseline
    }

    private func relativeIncrease(from baseline: Double, to result: Double) -> Double {
        baseline == 0 ? (result > 0 ? 1 : 0) : (result - baseline) / baseline
    }

    private func mostCommonSessionHour(in measured: [Session]) -> Int? {
        let hours = measured.compactMap { ISO8601DateFormatter().date(from: $0.startTime) }.map { Calendar.current.component(.hour, from: $0) }
        return Dictionary(grouping: hours, by: { $0 }).max { $0.value.count < $1.value.count }?.key
    }

    private func experimentHourLabel(_ hour: Int) -> String {
        let formatter = DateFormatter(); formatter.dateFormat = "ha"
        let date = Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: Date()) ?? Date()
        return formatter.string(from: date).lowercased()
    }

    private func clearRestrictionStateForTesting() {
        mivoLaunchGateActive = false
        pendingSessionFeedback = nil
        pendingExpiredRunningSession = nil
        pendingResumedActiveSession = nil
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
    case signupEmailRateLimited
    case emailConfirmationRequired
    case adminRequired
    case accountDeletionBlockedForAdmin
    case accountDeletionFailed(reason: String?)
    case deviceBoundToAnotherAccount(hint: String?)
    /// Google sign-in failed; the associated text is already user-readable and says which step failed.
    case googleSignInFailed(String)

    var errorDescription: String? {
        switch self {
        case .noAccount: return "No account found. Please create one."
        case .invalidCredentials: return "Invalid email or password."
        case .accountDataMissing: return "Account data missing. Please register again."
        case .emailAlreadyExists: return "An account with this email already exists."
        case .weakPassword: return "Password must be at least 8 characters."
        case .secureStorageFailed: return "Could not save credentials securely."
        case .remoteAuthUnavailable: return "The online Mivo account server is not reachable yet."
        case .signupEmailRateLimited: return "Signup email limit hit. Wait a few minutes or turn off email confirmation in Supabase Auth settings."
        case .emailConfirmationRequired: return "Check your email to confirm this account, then sign in."
        case .adminRequired: return "Admin access is required. Sign in with the admin account."
        case .accountDeletionBlockedForAdmin:
            return "Admin accounts own published Mivo content and can't be deleted from the app. Contact support to have this account removed."
        case .accountDeletionFailed(let reason):
            if let reason, !reason.isEmpty {
                return "Your account could not be deleted: \(reason). Nothing was removed — please try again."
            }
            return "Your account could not be deleted. Nothing was removed — please try again."
        case .deviceBoundToAnotherAccount(let hint):
            if let hint {
                return "This device already has a Mivo account. Original email hint: \(hint). Sign in with that account."
            }
            return "This device is already linked to its previous Mivo account. Sign in with that account."
        case .googleSignInFailed(let detail):
            return detail
        }
    }
}
