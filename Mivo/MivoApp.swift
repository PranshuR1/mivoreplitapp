import SwiftUI
import BackgroundTasks
import UserNotifications
import UIKit
#if canImport(FamilyControls)
import FamilyControls
#endif
#if canImport(GoogleSignIn)
import GoogleSignIn
#endif

enum SessionEndedNotificationCleaner {
    static let identifiers = [
        "mivo.intervention.done",
        "mivo.session.ended",
        "mivo.session.ended.nudge1",
        "mivo.session.ended.nudge2"
    ]
    static let identifierPrefixes = [
        "mivo.shield.openmivo"
    ]

    static func clearDelivered(center: UNUserNotificationCenter = .current()) {
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
        center.getDeliveredNotifications { notifications in
            let prefixed = notifications
                .map(\.request.identifier)
                .filter(matchesKnownPrefix)
            guard !prefixed.isEmpty else { return }
            center.removeDeliveredNotifications(withIdentifiers: prefixed)
        }
    }

    static func clearPendingAndDelivered(center: UNUserNotificationCenter = .current()) {
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
        center.getPendingNotificationRequests { requests in
            let prefixed = requests
                .map(\.identifier)
                .filter(matchesKnownPrefix)
            guard !prefixed.isEmpty else { return }
            center.removePendingNotificationRequests(withIdentifiers: prefixed)
        }
        center.getDeliveredNotifications { notifications in
            let prefixed = notifications
                .map(\.request.identifier)
                .filter(matchesKnownPrefix)
            guard !prefixed.isEmpty else { return }
            center.removeDeliveredNotifications(withIdentifiers: prefixed)
        }
    }

    private static func matchesKnownPrefix(_ identifier: String) -> Bool {
        identifierPrefixes.contains { identifier.hasPrefix($0) }
    }
}

// MARK: - App delegate
// SwiftUI doesn't expose a UNUserNotificationCenterDelegate out of the box.
// We adopt it here so we can:
//   1. Show the "Session ended" banner even when Mivo is in the foreground.
//   2. React to notification taps — set the deep-link flag and apply shields
//      immediately (before scenePhase machinery runs) so the apps re-lock the
//      instant the user taps "Open Mivo".
final class MivoAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        configureAppAppearance()
        // Notification suppression is owned by a running Still session, and no
        // session can be running across a cold launch. Without this reset, an
        // app that was force-quit or crashed mid-session would leave the flag
        // set and silently swallow every Mivo notification from then on, with
        // nothing in the UI to reveal or undo it. A Lock Mode run that resumes
        // re-arms suppression itself when its monitor restarts.
        MivoStillNotificationSuppression.isActive = false
        // A Lock Mode run can outlive the process that started it. Give it a
        // live in-process unlock timer again rather than leaving the apps
        // locked until the system gets around to a background trigger.
        if #available(iOS 16.0, *) {
            FamilyControlsManager.shared.rearmStillLockUnlockIfNeeded()
        }
        UNUserNotificationCenter.current().delegate = self
        registerSessionEndedCategory()
        SessionEndedNotificationCleaner.clearDelivered()
        return true
    }

    private func configureAppAppearance() {
        let tabAppearance = UITabBarAppearance()
        tabAppearance.configureWithOpaqueBackground()
        tabAppearance.backgroundColor = UIColor(MivoColors.background)
        tabAppearance.shadowColor = UIColor(MivoColors.border.opacity(0.32))
        tabAppearance.stackedLayoutAppearance.normal.iconColor = UIColor(MivoColors.textMuted)
        tabAppearance.stackedLayoutAppearance.normal.titleTextAttributes = [
            .foregroundColor: UIColor(MivoColors.textMuted),
            .font: UIFont.systemFont(ofSize: 10, weight: .medium)
        ]
        tabAppearance.stackedLayoutAppearance.selected.iconColor = UIColor(MivoColors.accent)
        tabAppearance.stackedLayoutAppearance.selected.titleTextAttributes = [
            .foregroundColor: UIColor(MivoColors.accent),
            .font: UIFont.systemFont(ofSize: 10, weight: .semibold)
        ]
        UITabBar.appearance().standardAppearance = tabAppearance
        UITabBar.appearance().scrollEdgeAppearance = tabAppearance

        let navAppearance = UINavigationBarAppearance()
        navAppearance.configureWithOpaqueBackground()
        navAppearance.backgroundColor = UIColor(MivoColors.background)
        navAppearance.shadowColor = .clear
        UINavigationBar.appearance().standardAppearance = navAppearance
        UINavigationBar.appearance().scrollEdgeAppearance = navAppearance
    }

    private func registerSessionEndedCategory() {
        let openAction = UNNotificationAction(
            identifier: "OPEN_MIVO",
            title: "Open Mivo",
            options: [.foreground]
        )
        let category = UNNotificationCategory(
            identifier: "MIVO_SESSION_ENDED",
            actions: [openAction],
            intentIdentifiers: [],
            options: []
        )
        let rescueAction = UNNotificationAction(
            identifier: "OPEN_RESCUE",
            title: "Open Rescue Mode",
            options: [.foreground]
        )
        let rescueCategory = UNNotificationCategory(
            identifier: "MIVO_RESCUE",
            actions: [rescueAction],
            intentIdentifiers: [],
            options: []
        )
        let adminAccountCategory = UNNotificationCategory(
            identifier: "MIVO_ADMIN_ACCOUNT",
            actions: [],
            intentIdentifiers: [],
            options: []
        )
        let clearAction = UNNotificationAction(
            identifier: "OPEN_MIVO_CLEAR",
            title: "Open Mivo Clear",
            options: [.foreground]
        )
        let clearCategory = UNNotificationCategory(
            identifier: "MIVO_CLEAR",
            actions: [clearAction],
            intentIdentifiers: [],
            options: []
        )
        UNUserNotificationCenter.current().setNotificationCategories([category, rescueCategory, adminAccountCategory, clearCategory])
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        UserDefaults.standard.set(token, forKey: "mivo.adminPushDeviceToken")
        Task {
            guard let installationID = try? DeviceBindingService.installationID() else { return }
            do {
                try await MivoBackendService.registerAdminPushDevice(
                    deviceToken: token,
                    installationID: installationID
                )
                UserDefaults.standard.set(true, forKey: "mivo.adminPushRegistered")
            } catch {
                UserDefaults.standard.set(error.localizedDescription, forKey: "mivo.adminPushRegistrationError")
            }
            await Self.registerGeneralPushDeviceIfSignedIn(deviceToken: token, installationID: installationID)
        }
    }

    /// Registers this device in `user_push_devices` for whichever account
    /// is currently signed in, alongside (not instead of) the admin-only
    /// registration above — that one only ever reaches admin accounts,
    /// but cross-device focus commands (`CrossDeviceFocusService`) need
    /// every signed-in user's device. No-op when signed out.
    static func registerGeneralPushDeviceIfSignedIn(deviceToken: String, installationID: String) async {
        guard let email = StorageService.load(String.self, forKey: .rememberedEmail),
              let record = SecureAuthService.loadRecord(email: email) else { return }
        #if DEBUG
        let environment = "sandbox"
        #else
        let environment = "production"
        #endif
        await RemoteAuthService.registerPushDevice(
            deviceToken: deviceToken,
            environment: environment,
            installationID: installationID,
            record: record
        )
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        UserDefaults.standard.set(error.localizedDescription, forKey: "mivo.adminPushRegistrationError")
    }

    /// The silent-push counterpart to `scheduleCrossDeviceFocusBackgroundCheck()`
    /// — `cross-device-focus-push` (the Edge Function the Mac calls right
    /// after writing a command) sends a `content-available` push with no
    /// alert, whose only job is to land here and give `reconcile()` a
    /// chance to run immediately instead of waiting on the next foreground
    /// or the next opportunistic BGAppRefreshTask. iOS delivers this even
    /// while the phone is locked, as long as `UIBackgroundModes` includes
    /// `remote-notification` (see Info.plist) — that's the whole reason
    /// this exists over relying on the background task alone.
    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        guard #available(iOS 16.0, *) else {
            completionHandler(.noData)
            return
        }
        Task {
            await CrossDeviceFocusService.shared.reconcile()
            completionHandler(.newData)
        }
    }

    // Show the banner even when Mivo is already active in the foreground.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        // A Still session is a deliberate no-phone period — don't let Mivo's
        // own notifications buzz or light up the screen and tempt a pickup.
        // This only reaches notifications Mivo itself scheduled; there is no
        // way for a third-party app to hold back notifications from other
        // apps or the system.
        if MivoStillNotificationSuppression.isActive {
            completionHandler([])
            return
        }
        if (notification.request.content.userInfo["mivoRoute"] as? String) == SpotKeys.notificationRoute {
            // A Mivo Spot finished, or a Spot's shield asked to open Mivo — and Mivo
            // is already open, so there is nothing to banner; just act on it.
            center.removeDeliveredNotifications(withIdentifiers: [notification.request.identifier])
            NotificationCenter.default.post(name: Notification.Name(SpotKeys.routeChangedNotification), object: nil)
            completionHandler([])
            return
        }
        if (notification.request.content.userInfo["mivoRoute"] as? String) == "mivoClear" {
            persistMivoClearRoute(from: notification.request.content.userInfo)
            center.removeDeliveredNotifications(withIdentifiers: [notification.request.identifier])
            NotificationCenter.default.post(name: Notification.Name("mivoClearRequested"), object: nil)
            completionHandler([])
            return
        }
        if (notification.request.content.userInfo["mivoRoute"] as? String) == "rescue" {
            NotificationCenter.default.post(name: Notification.Name("mivoRescueRequested"), object: nil)
            completionHandler([])
            return
        }
        if #available(iOS 14.0, *) {
            completionHandler([.banner, .sound, .list])
        } else {
            completionHandler([.alert, .sound])
        }
    }

    // Fired when the user taps the notification body OR the "Open Mivo" action.
    // The default behaviour of a `.foreground` action is to launch Mivo, so we just
    // need to mark the deep-link flag and kick off the relock immediately.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let userInfo = response.notification.request.content.userInfo

        if (userInfo["mivoRoute"] as? String) == SpotKeys.notificationRoute {
            center.removeDeliveredNotifications(withIdentifiers: [response.notification.request.identifier])
            NotificationCenter.default.post(name: Notification.Name(SpotKeys.routeChangedNotification), object: nil)
            completionHandler()
            return
        }

        if (userInfo["mivoRoute"] as? String) == "mivoClear" {
            persistMivoClearRoute(from: userInfo)
            center.removeDeliveredNotifications(withIdentifiers: [response.notification.request.identifier])
            NotificationCenter.default.post(name: Notification.Name("mivoClearRequested"), object: nil)
            completionHandler()
            return
        }

        if (userInfo["mivoRoute"] as? String) == "rescue" {
            center.removeDeliveredNotifications(withIdentifiers: [
                "mivo.session.rescue",
                "mivo.session.rescue.reminder"
            ])
            NotificationCenter.default.post(name: Notification.Name("mivoRescueRequested"), object: nil)
            completionHandler()
            return
        }

        if (userInfo["mivoRoute"] as? String) == "adminUser",
           let userID = userInfo["userID"] as? String {
            UserDefaults.standard.set(userID, forKey: "mivo.pendingAdminUserID")
            NotificationCenter.default.post(
                name: Notification.Name("mivoAdminUserRequested"),
                object: userID
            )
            completionHandler()
            return
        }

        // ── Check-in notification: re-apply shields so the blocked app shows the
        //    "Active session check-in" shield when the user navigates to it. ──
        if (userInfo["mivoRoute"] as? String) == "checkIn" {
            Task { @MainActor in
                FamilyControlsManager.shared.applyCheckInShieldIfSessionActive()
            }
            completionHandler()
            return
        }

        if userInfo["openIntervention"] as? Bool == true {
            SessionEndedNotificationCleaner.clearPendingAndDelivered(center: center)

            // Mark the deep-link flag — MainTabView picks this up on .active and
            // navigates to the Interventions tab.
            let defaults = UserDefaults(suiteName: "group.com.mivo.mivoapp")
            defaults?.set(true, forKey: "mivo.openInterventionOnLaunch")
            defaults?.synchronize()

            // Apply shields ASAP. `applyImpulseProtectionIfNeeded` self-corrects
            // sessionActive/sessionEndsAt when the session has expired.
            Task { @MainActor in
                FamilyControlsManager.shared.applyImpulseProtectionIfNeeded()
                await CrossDeviceFocusService.shared.reconcile()
            }
        }
        completionHandler()
    }

    private func persistMivoClearRoute(from userInfo: [AnyHashable: Any]) {
        guard let platform = userInfo["platform"] as? String else { return }
        let defaults = UserDefaults(suiteName: MivoScreenTimeKeys.appGroup)
        defaults?.set(platform, forKey: MivoScreenTimeKeys.pendingMivoClearPlatform)
        defaults?.set(MivoClearEntryPoint.shield.rawValue, forKey: MivoScreenTimeKeys.pendingMivoClearEntryPoint)
        defaults?.synchronize()
    }
}

@MainActor
enum AdminPushNotificationManager {
    private static var lastSyncAt: Date?

    static func sync(for access: AccountAccess) async {
        guard access.isSuperAdmin else {
            if UserDefaults.standard.bool(forKey: "mivo.adminPushRegistered") {
                try? await MivoBackendService.unregisterAdminPushDevice()
                UserDefaults.standard.set(false, forKey: "mivo.adminPushRegistered")
            }
            // Not an admin, so the RPC registration below doesn't apply —
            // but registerForRemoteNotifications() previously only ever
            // ran for admins, meaning didRegisterForRemoteNotificationsWithDeviceToken
            // (and therefore registerGeneralPushDeviceIfSignedIn, which
            // cross-device focus commands depend on) never fired for
            // ordinary users at all. Every signed-in user needs this.
            await ensureRemoteNotificationRegistration()
            return
        }

        if let lastSyncAt, Date().timeIntervalSince(lastSyncAt) < 300 { return }
        lastSyncAt = Date()

        let registered = await ensureRemoteNotificationRegistration()
        guard registered else { return }
        if let token = UserDefaults.standard.string(forKey: "mivo.adminPushDeviceToken"),
           let installationID = try? DeviceBindingService.installationID() {
            do {
                try await MivoBackendService.registerAdminPushDevice(
                    deviceToken: token,
                    installationID: installationID
                )
                UserDefaults.standard.set(true, forKey: "mivo.adminPushRegistered")
            } catch {
                UserDefaults.standard.set(error.localizedDescription, forKey: "mivo.adminPushRegistrationError")
            }
        }
    }

    /// Requests notification authorization if undetermined, and calls
    /// `registerForRemoteNotifications()` whenever the app is allowed to
    /// receive push at all. Returns whether the app is registered (or
    /// about to be) so callers can skip work that depends on it.
    /// A silent (`content-available`) push — which is all
    /// `cross-device-focus-push` ever sends — needs a device token, not
    /// alert/badge/sound authorization; Apple delivers those to a
    /// `.denied` app the same as an `.authorized` one; only a *visible*
    /// notification needs the user's permission. Gating
    /// `registerForRemoteNotifications()` on that authorization status
    /// meant anyone who declined the alert prompt — plausible for an app
    /// about reducing distraction — never got a device token at all, so
    /// cross-device focus silently fell back to the much slower
    /// BGAppRefreshTask-only path with no way to tell. Registering
    /// unconditionally here still requests alert/badge/sound when
    /// undetermined (for the *visible* notifications elsewhere in this
    /// app), but no longer blocks the token itself on the outcome.
    @discardableResult
    private static func ensureRemoteNotificationRegistration() async -> Bool {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            _ = try? await UNUserNotificationCenter.current().requestAuthorization(
                options: [.alert, .badge, .sound]
            )
        }
        UIApplication.shared.registerForRemoteNotifications()
        return true
    }
}

@main
struct MivoApp: App {
    @UIApplicationDelegateAdaptor(MivoAppDelegate.self) private var appDelegate
    @StateObject private var appVM = AppViewModel()

    init() {
        // Register background session-relock task. Must happen before app finishes launching.
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: "com.mivo.mivoapp.sessionrelock",
            using: nil
        ) { task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            // Re-apply shields if session has expired. Safe to call on any background thread.
            if #available(iOS 16.0, *) {
                FamilyControlsManager.shared.applyImpulseProtectionIfNeeded()
            }
            refreshTask.setTaskCompleted(success: true)
        }
        // Register the Mivo Still Lock Mode unlock fallback — mirrors the
        // relock registration above, in reverse (lifts a block instead of
        // reapplying one).
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: MivoScreenTimeKeys.stillLockBGTaskIdentifier,
            using: nil
        ) { task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            FamilyControlsManager.shared.endStillLockIfExpired()
            refreshTask.setTaskCompleted(success: true)
        }
        // Best-effort background discovery for "Block my iPhone too" — see
        // the doc comment on scheduleCrossDeviceFocusBackgroundCheck().
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: MivoScreenTimeKeys.crossDeviceFocusBGTaskIdentifier,
            using: nil
        ) { task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            let work = Task {
                if #available(iOS 16.0, *) {
                    await CrossDeviceFocusService.shared.reconcile()
                }
                refreshTask.setTaskCompleted(success: true)
            }
            refreshTask.expirationHandler = { work.cancel() }
        }
        // Keep navigation bars consistent with the selected Mivo appearance.
        let navAppearance = UINavigationBarAppearance()
        navAppearance.configureWithOpaqueBackground()
        navAppearance.backgroundColor = UIColor(MivoColors.background)
        navAppearance.titleTextAttributes = [.foregroundColor: UIColor(MivoColors.textPrimary)]
        navAppearance.largeTitleTextAttributes = [.foregroundColor: UIColor(MivoColors.textPrimary)]

        UINavigationBar.appearance().standardAppearance = navAppearance
        UINavigationBar.appearance().scrollEdgeAppearance = navAppearance
        UINavigationBar.appearance().compactAppearance = navAppearance
        UINavigationBar.appearance().tintColor = UIColor(MivoColors.textSecondary)

        UIToolbar.appearance().tintColor = UIColor(MivoColors.textSecondary)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appVM)
                .preferredColorScheme(appVM.preferredColorScheme)
                .onOpenURL { url in
                    #if canImport(GoogleSignIn)
                    if GIDSignIn.sharedInstance.handle(url) { return }
                    #endif
                    if url.scheme == "mivo" || url.host == "usemivo.app" {
                        // If the ObjC-runtime openURL trick worked, cancel/clear any
                        // fallback notification the shield action extension requested.
                        SessionEndedNotificationCleaner.clearPendingAndDelivered()
                        appVM.handleDeepLink(url)
                    }
                }
                // Background tag reading hands a tapped Mivo Spot to the app as a
                // universal-link user activity. `onOpenURL` normally sees it too;
                // this makes sure it is never missed. A repeat delivery is ignored
                // by `SpotManager`, so it can't turn a Spot straight back off.
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                    guard let url = activity.webpageURL, SpotLink.target(from: url) != nil else { return }
                    appVM.handleDeepLink(url)
                }
        }
    }
}

struct RootView: View {
    @EnvironmentObject var appVM: AppViewModel
    @AppStorage("mivo.firstLaunchStoryComplete") private var firstLaunchStoryComplete = false

    var body: some View {
        Group {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-MivoPreviewOnboarding") {
                OnboardingWelcomeView()
            } else if ProcessInfo.processInfo.arguments.contains("-MivoPreviewFirstLaunch") {
                MivoFirstLaunchIntroView(onComplete: {})
            } else if ProcessInfo.processInfo.arguments.contains("-MivoPreviewOnboardingApps") {
                NavigationStack { OnboardingAppsView() }
            } else if ProcessInfo.processInfo.arguments.contains("-MivoPreviewOnboardingCalibration") {
                NavigationStack { OnboardingCalibrationView() }
            } else if ProcessInfo.processInfo.arguments.contains("-MivoPreviewOnboardingTime") {
                NavigationStack { OnboardingTimePreviewView() }
            } else if ProcessInfo.processInfo.arguments.contains("-MivoPreviewOnboardingRecovery") {
                NavigationStack { ResultOnboardingView_Internal(providedAge: 21, providedAgeRange: "18-24") }
            } else if ProcessInfo.processInfo.arguments.contains("-MivoPreviewWeeklyReportChart") {
                NavigationStack { WeeklyReportView(initialPage: 2) }
            } else if ProcessInfo.processInfo.arguments.contains("-MivoPreviewWeeklyReportImpact") {
                NavigationStack { WeeklyReportView(initialPage: 4) }
            } else if ProcessInfo.processInfo.arguments.contains("-MivoPreviewWeeklyReportRecap") {
                NavigationStack { WeeklyReportView(initialPage: 5) }
            } else if ProcessInfo.processInfo.arguments.contains("-MivoPreviewWeeklyReport") {
                NavigationStack { WeeklyReportView() }
            } else if ProcessInfo.processInfo.arguments.contains("-MivoPreviewHome") {
                NavigationStack { HomeView() }
            } else if let raw = UserDefaults.standard.string(forKey: "MivoPreviewTabs"), let tab = Int(raw) {
                // Whole tab shell with the bar, opened on the given tab (0-3).
                MainTabView(initialTab: tab)
            } else if let raw = UserDefaults.standard.string(forKey: "MivoPreviewSettingsPage"),
                      let page = SettingsPage(rawValue: raw) {
                NavigationStack { SettingsView(page: page) }
            } else if ProcessInfo.processInfo.arguments.contains("-MivoPreviewPatterns") {
                NavigationStack { PatternsView() }
            } else if ProcessInfo.processInfo.arguments.contains("-MivoPreviewInterventions") {
                NavigationStack { InterventionsView() }
            } else if ProcessInfo.processInfo.arguments.contains("-MivoPreviewSettings") {
                NavigationStack { SettingsView() }
            } else if ProcessInfo.processInfo.arguments.contains("-MivoPreviewClear") {
                MivoClearAppStorePreviewView()
            } else if ProcessInfo.processInfo.arguments.contains("-MivoPreviewStill") {
                MivoStillAppStorePreviewView()
            } else if ProcessInfo.processInfo.arguments.contains("-MivoPreviewInstagramWrapper") {
                InstagramWrapperView()
            } else if ProcessInfo.processInfo.arguments.contains("-MivoPreviewComeback") {
                ComebackFlowView(prompt: ComebackPreviewFixtures.prompt)
            } else if ProcessInfo.processInfo.arguments.contains("-MivoPreviewComebackHome") {
                ComebackHomePreview()
            } else if let spotScreen = SpotPreviewHost.screen(from: ProcessInfo.processInfo.arguments) {
                SpotPreviewHost(screen: spotScreen)
            } else if let companionMode = UserDefaults.standard.string(forKey: "MivoPreviewCompanion") {
                CompanionPreviewHost(mode: companionMode)
            } else {
                defaultRoot
            }
            #else
            defaultRoot
            #endif
        }
        .animation(.easeInOut(duration: 0.3), value: appVM.isLoggedIn)
        .animation(.easeInOut(duration: 0.3), value: appVM.settings.onboardingComplete)
        .animation(.easeInOut(duration: 0.3), value: appVM.isLoading)
    }

    @ViewBuilder
    private var defaultRoot: some View {
        if appVM.isLoading {
            SplashView()
        } else if !appVM.isLoggedIn && !firstLaunchStoryComplete {
            MivoFirstLaunchIntroView {
                withAnimation(.easeInOut(duration: 0.36)) {
                    firstLaunchStoryComplete = true
                }
            }
        } else if !appVM.isLoggedIn {
            LoginView()
        } else if !appVM.settings.onboardingComplete {
            OnboardingWelcomeView()
        } else {
            MainTabView()
        }
    }
}

#if DEBUG && MIVO_AI_WALKTHROUGH_CAPTURE
private struct AIWalkthroughSeededView<Content: View>: View {
    @EnvironmentObject private var appVM: AppViewModel
    @State private var isReady = false
    private let content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View {
        Group {
            if isReady {
                content()
            } else {
                MivoColors.background.ignoresSafeArea()
            }
        }
        .onAppear {
            appVM.loadAIWalkthroughDemoState()
            DispatchQueue.main.async {
                isReady = true
            }
        }
    }
}

private struct AIWalkthroughAutoScrollDriver: UIViewRepresentable {
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isUserInteractionEnabled = false

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            guard !context.coordinator.didStart,
                  let window = view.window else { return }

            context.coordinator.didStart = true
            let scrollView = window.aiWalkthroughScrollViews
                .filter { $0.contentSize.height > $0.bounds.height + 120 }
                .max {
                    ($0.contentSize.height - $0.bounds.height)
                        < ($1.contentSize.height - $1.bounds.height)
                }

            guard let scrollView else { return }
            let bottomY = max(
                -scrollView.adjustedContentInset.top,
                scrollView.contentSize.height
                    - scrollView.bounds.height
                    + scrollView.adjustedContentInset.bottom
            )

            UIView.animate(
                withDuration: 11,
                delay: 0,
                options: [.curveEaseInOut, .allowUserInteraction]
            ) {
                scrollView.contentOffset = CGPoint(x: scrollView.contentOffset.x, y: bottomY)
            }
        }

        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}

    final class Coordinator {
        var didStart = false
    }
}

private extension UIView {
    var aiWalkthroughScrollViews: [UIScrollView] {
        var matches = self as? UIScrollView == nil ? [] : [self as! UIScrollView]
        for subview in subviews {
            matches.append(contentsOf: subview.aiWalkthroughScrollViews)
        }
        return matches
    }
}

extension AppViewModel {
    func loadAIWalkthroughDemoState(now: Date = Date()) {
        let calendar = Calendar.current
        let iso = ISO8601DateFormatter()
        let dayFormatter = MivoDay.formatter

        func day(_ offset: Int) -> Date {
            calendar.date(byAdding: .day, value: offset, to: now) ?? now
        }

        func dateKey(_ offset: Int) -> String {
            dayFormatter.string(from: day(offset))
        }

        func session(
            offset: Int,
            hour: Int,
            planned: Int,
            actual: Int,
            intention: Intention,
            urge: UrgeReason,
            extended: Bool,
            outcome: SessionOutcomeScore,
            reflection: ReflectionChoice = .yes
        ) -> Session {
            let start = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day(offset)) ?? day(offset)
            let end = start.addingTimeInterval(TimeInterval(actual * 60))
            return Session(
                id: "ai-demo-\(offset)-\(hour)",
                date: dateKey(offset),
                startTime: iso.string(from: start),
                endTime: iso.string(from: end),
                plannedDuration: planned,
                actualDuration: actual,
                intention: intention,
                extendedOnce: extended,
                reflection: reflection,
                reflectionNote: outcome == .notWorthIt ? "I opened automatically during a study break." : "I found what I needed.",
                urgeReason: urge,
                urgeNote: nil,
                outcomeScore: outcome,
                emergencyUnlockUsed: false,
                emergencyUnlockReason: nil
            )
        }

        var profile = OnboardingProfile(
            primaryIntention: .bored,
            scrollEstimateMinutes: 120,
            preferredApps: ["Instagram", "TikTok", "YouTube"],
            preferredScrollWindows: [
                ScreenScrollWindow(
                    id: "demo-morning",
                    title: "Morning window",
                    startHour: 9,
                    endHour: 10,
                    minutes: 30,
                    reason: "Your selected morning anchor."
                ),
                ScreenScrollWindow(
                    id: "demo-afternoon",
                    title: "Afternoon window",
                    startHour: 14,
                    endHour: 15,
                    minutes: 30,
                    reason: "Your selected afternoon anchor."
                ),
                ScreenScrollWindow(
                    id: "demo-evening",
                    title: "Evening window",
                    startHour: 20,
                    endHour: 21,
                    minutes: 20,
                    reason: "A smaller evening window based on recent sessions."
                )
            ]
        )
        profile.observationStartedAt = iso.string(from: day(-14))
        profile.intentions = [.bored, .killTime, .relax]
        profile.age = 21
        profile.ageRange = "18-24"
        profile.checkInIntervalMinutes = 3
        profile.dailyScrollGoalMinutes = 75
        onboardingProfile = profile

        settings = AppSettings(
            onboardingComplete: true,
            notificationsEnabled: true,
            tutorialComplete: true,
            notificationsChoiceMade: true,
            accountabilityEnabled: false,
            checkInIntervalMinutes: 3,
            lateNightProtectionEnabled: true,
            lateNightStartHour: 22,
            lateNightWakeHour: 7,
            lastScrollNightKey: nil,
            appearanceMode: .light
        )

        sessions = [
            session(offset: -7, hour: 20, planned: 20, actual: 42, intention: .bored, urge: .habit, extended: true, outcome: .notWorthIt, reflection: .no),
            session(offset: -6, hour: 9, planned: 25, actual: 28, intention: .lookingForSomethingSpecific, urge: .specificTask, extended: false, outcome: .worthIt),
            session(offset: -5, hour: 14, planned: 25, actual: 37, intention: .relax, urge: .stressed, extended: true, outcome: .mixed, reflection: .kindOf),
            session(offset: -4, hour: 20, planned: 20, actual: 35, intention: .bored, urge: .habit, extended: true, outcome: .notWorthIt, reflection: .no),
            session(offset: -3, hour: 9, planned: 25, actual: 24, intention: .lookingForSomethingSpecific, urge: .message, extended: false, outcome: .worthIt),
            session(offset: -2, hour: 14, planned: 25, actual: 29, intention: .relax, urge: .stressed, extended: false, outcome: .mixed, reflection: .kindOf),
            session(offset: -1, hour: 20, planned: 20, actual: 31, intention: .bored, urge: .habit, extended: true, outcome: .notWorthIt, reflection: .no),
            session(offset: 0, hour: 9, planned: 25, actual: 22, intention: .lookingForSomethingSpecific, urge: .specificTask, extended: false, outcome: .worthIt)
        ]

        truthChecks = (-6...0).map { offset in
            let actual = [164, 151, 146, 137, 128, 119, 112][offset + 6]
            let guess = [95, 100, 102, 104, 106, 108, 109][offset + 6]
            return TruthCheckGuess(
                id: "truth-\(offset)",
                date: dateKey(offset),
                guess: guess,
                actual: actual,
                checkedAt: iso.string(from: day(offset)),
                perAppMinutes: ["Instagram": max(18, actual / 2), "TikTok": max(12, actual / 3), "YouTube": max(8, actual / 6)]
            )
        }

        dailyScreenTimeObservations = [
            DailyScreenTimeObservation(date: dateKey(-3), minutes: 178, recordedAt: iso.string(from: day(-3))),
            DailyScreenTimeObservation(date: dateKey(-2), minutes: 156, recordedAt: iso.string(from: day(-2))),
            DailyScreenTimeObservation(date: dateKey(-1), minutes: 139, recordedAt: iso.string(from: day(-1)))
        ]

        let todayWindows = profile.preferredScrollWindows ?? []
        dailyScrollSchedules = [
            DailyScrollSchedule(
                id: "demo-schedule-\(dateKey(0))",
                date: dateKey(0),
                windows: todayWindows,
                createdAt: iso.string(from: now)
            )
        ]

        let baseline = ExperimentMetrics(
            comparableSessions: 6,
            outsideWindowMinutes: 74,
            extensionRate: 0.67,
            cancellationRate: 0.16,
            truthAccuracyMinutes: 47,
            worthwhileRate: 0.42
        )
        let result = ExperimentMetrics(
            comparableSessions: 7,
            outsideWindowMinutes: 48,
            extensionRate: 0.43,
            cancellationRate: 0.29,
            truthAccuracyMinutes: 29,
            worthwhileRate: 0.64
        )
        weeklyExperiments = [
            WeeklyExperiment(
                id: "demo-active-experiment",
                userId: "demo-user",
                type: .strongerFriction,
                status: .active,
                title: "Pause repeated openings",
                reason: "Repeated evening openings often became sessions you marked Not worth it.",
                primaryMetric: "cancellation_rate",
                rule: WeeklyExperimentRule(startHour: nil, endHour: nil, allowedMinutes: nil, strongerFrictionEnabled: true),
                baselineMetrics: baseline,
                resultMetrics: nil,
                startsAt: iso.string(from: day(-3)),
                endsAt: iso.string(from: day(3)),
                outcome: nil,
                finalDecision: nil,
                createdAt: iso.string(from: day(-3)),
                updatedAt: iso.string(from: now)
            ),
            WeeklyExperiment(
                id: "demo-completed-experiment",
                userId: "demo-user",
                type: .reduceExtensions,
                status: .completed,
                title: "Keep original session limits",
                reason: "Extensions were most common in evening sessions.",
                primaryMetric: "extension_rate",
                rule: WeeklyExperimentRule(startHour: nil, endHour: nil, allowedMinutes: 20, strongerFrictionEnabled: false),
                baselineMetrics: baseline,
                resultMetrics: result,
                startsAt: iso.string(from: day(-14)),
                endsAt: iso.string(from: day(-8)),
                outcome: .helped,
                finalDecision: .keep,
                userFeedback: .helpful,
                feedbackNote: "The fixed limit made the choice clearer.",
                feedbackSubmittedAt: iso.string(from: day(-8)),
                createdAt: iso.string(from: day(-14)),
                updatedAt: iso.string(from: day(-8))
            )
        ]

        interventionAttempts = [
            InterventionAttemptRecord(id: "attempt-1", occurredAt: iso.string(from: now.addingTimeInterval(-18 * 60)), continued: true),
            InterventionAttemptRecord(id: "attempt-2", occurredAt: iso.string(from: now.addingTimeInterval(-9 * 60)), continued: true)
        ]
        deviceActivityMinutesToday = 236
        deviceActivityPerAppSeconds = [
            "Instagram": 68 * 60,
            "TikTok": 49 * 60,
            "YouTube": 37 * 60
        ]
        deviceActivityReportGeneratedAt = now
    }
}
#endif

struct SplashView: View {
    @State private var appear = false

    var body: some View {
        ZStack {
            MivoColors.background.ignoresSafeArea()
            VStack(spacing: 16) {
                MivoLogo(size: 72)
                Text("Mivo")
                    .font(.system(size: 32, weight: .bold))
                    .tracking(-1)
                    .foregroundColor(MivoColors.textPrimary)
                Text("Scroll on purpose.")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(MivoColors.textSecondary)
            }
            .opacity(appear ? 1 : 0)
            .scaleEffect(appear ? 1 : 0.94)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.5)) { appear = true }
        }
    }
}
