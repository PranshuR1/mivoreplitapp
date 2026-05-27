import SwiftUI
import BackgroundTasks
import UserNotifications
import UIKit
#if canImport(FamilyControls)
import FamilyControls
#endif

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
        UNUserNotificationCenter.current().delegate = self
        registerSessionEndedCategory()
        return true
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
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    // Show the banner even when Mivo is already active in the foreground.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
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
        // Keep navigation bars consistent with the app's creme background even when scrolling
        let navAppearance = UINavigationBarAppearance()
        navAppearance.configureWithOpaqueBackground()
        navAppearance.backgroundColor = UIColor(red: 231.0/255.0, green: 214.0/255.0, blue: 196.0/255.0, alpha: 1.0) // #E7D6C4
        navAppearance.titleTextAttributes = [.foregroundColor: UIColor(red: 46.0/255.0, green: 46.0/255.0, blue: 46.0/255.0, alpha: 1.0)]
        navAppearance.largeTitleTextAttributes = [.foregroundColor: UIColor(red: 46.0/255.0, green: 46.0/255.0, blue: 46.0/255.0, alpha: 1.0)]

        UINavigationBar.appearance().standardAppearance = navAppearance
        UINavigationBar.appearance().scrollEdgeAppearance = navAppearance
        UINavigationBar.appearance().compactAppearance = navAppearance
        UINavigationBar.appearance().tintColor = UIColor(red: 156.0/255.0, green: 133.0/255.0, blue: 115.0/255.0, alpha: 1.0) // #9C8573

        UIToolbar.appearance().tintColor = UIColor(red: 156.0/255.0, green: 133.0/255.0, blue: 115.0/255.0, alpha: 1.0)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appVM)
                .onOpenURL { url in
                    // mivo://intervention — opened from shield "Open Mivo" button
                    if url.scheme == "mivo" {
                        // If the ObjC-runtime openURL trick worked, cancel the
                        // 0.1-second fallback notification before it fires.
                        UNUserNotificationCenter.current()
                            .removePendingNotificationRequests(withIdentifiers: ["mivo.shield.openmivo"])
                        appVM.handleDeepLink(url)
                    }
                }
        }
    }
}

struct RootView: View {
    @EnvironmentObject var appVM: AppViewModel

    var body: some View {
        Group {
            if appVM.isLoading {
                SplashView()
            } else if !appVM.isLoggedIn {
                LoginView()
            } else if !appVM.settings.onboardingComplete {
                OnboardingWelcomeView()
            } else {
                MainTabView()
            }
        }
        .animation(.easeInOut(duration: 0.3), value: appVM.isLoggedIn)
        .animation(.easeInOut(duration: 0.3), value: appVM.settings.onboardingComplete)
        .animation(.easeInOut(duration: 0.3), value: appVM.isLoading)
    }
}

struct SplashView: View {
    var body: some View {
        ZStack {
            MivoColors.background.ignoresSafeArea()
            VStack(spacing: 16) {
                MivoLogo(size: 72)
                Text("Mivo")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(MivoColors.textPrimary)
                    .tracking(-1)
            }
        }
    }
}
