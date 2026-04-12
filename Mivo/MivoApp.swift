import SwiftUI

@main
struct MivoApp: App {
    @StateObject private var appVM = AppViewModel()

    init() {
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
