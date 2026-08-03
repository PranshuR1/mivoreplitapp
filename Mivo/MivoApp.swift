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
            title: "Open Mivo Clear BETA",
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
                try await ReferralCampaignService.registerAdminPushDevice(
                    deviceToken: token,
                    installationID: installationID
                )
                UserDefaults.standard.set(true, forKey: "mivo.adminPushRegistered")
            } catch {
                UserDefaults.standard.set(error.localizedDescription, forKey: "mivo.adminPushRegistrationError")
            }
        }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        UserDefaults.standard.set(error.localizedDescription, forKey: "mivo.adminPushRegistrationError")
    }

    // Show the banner even when Mivo is already active in the foreground.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
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
                try? await ReferralCampaignService.unregisterAdminPushDevice()
                UserDefaults.standard.set(false, forKey: "mivo.adminPushRegistered")
            }
            return
        }

        if let lastSyncAt, Date().timeIntervalSince(lastSyncAt) < 300 { return }
        lastSyncAt = Date()

        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            UIApplication.shared.registerForRemoteNotifications()
            if let token = UserDefaults.standard.string(forKey: "mivo.adminPushDeviceToken"),
               let installationID = try? DeviceBindingService.installationID() {
                do {
                    try await ReferralCampaignService.registerAdminPushDevice(
                        deviceToken: token,
                        installationID: installationID
                    )
                    UserDefaults.standard.set(true, forKey: "mivo.adminPushRegistered")
                } catch {
                    UserDefaults.standard.set(error.localizedDescription, forKey: "mivo.adminPushRegistrationError")
                }
            }
        case .notDetermined:
            let granted = (try? await UNUserNotificationCenter.current().requestAuthorization(
                options: [.alert, .badge, .sound]
            )) == true
            if granted { UIApplication.shared.registerForRemoteNotifications() }
        case .denied:
            break
        @unknown default:
            break
        }
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
            } else if ProcessInfo.processInfo.arguments.contains("-MivoPreviewPatterns") {
                NavigationStack { PatternsView() }
            } else if ProcessInfo.processInfo.arguments.contains("-MivoPreviewInterventions") {
                NavigationStack { InterventionsView() }
            } else if ProcessInfo.processInfo.arguments.contains("-MivoPreviewSettings") {
                NavigationStack { SettingsView() }
            } else if ProcessInfo.processInfo.arguments.contains("-MivoPreviewClear") {
                MivoClearAppStorePreviewView()
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
    var body: some View {
        ZStack {
            MivoColors.background.ignoresSafeArea()
            VStack(spacing: 16) {
                MivoLogo(size: 72)
                Text("Mivo")
                    .font(.system(size: 32, weight: .bold))
                    .tracking(-1)
                    .foregroundColor(MivoColors.textPrimary)
            }
        }
    }
}
