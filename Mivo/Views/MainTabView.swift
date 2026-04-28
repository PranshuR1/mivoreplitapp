import SwiftUI

struct MainTabView: View {
    @EnvironmentObject var appVM: AppViewModel
    @State private var selectedTab = 0
    @State private var tutorialStep = 0
    @State private var isRequestingScreenTime = false
    @State private var tutorialMessage: String? = nil

    private let tutorialSteps = AppTutorialStep.all

    var body: some View {
        ZStack {
            TabView(selection: $selectedTab) {
                NavigationStack {
                    HomeView()
                }
                .tabItem {
                    Label("Home", systemImage: "house")
                }
                .tag(0)

                NavigationStack {
                    PatternsView()
                }
                .tabItem {
                    Label("Patterns", systemImage: "calendar")
                }
                .tag(1)

                NavigationStack {
                    InterventionsView()
                }
                .tabItem {
                    Label("Interventions", systemImage: "timer")
                }
                .tag(2)

                NavigationStack {
                    SettingsView()
                }
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
                .tag(3)
            }
            .disabled(shouldShowTutorial)

            if shouldShowTutorial {
                Color.black.opacity(0.18)
                    .ignoresSafeArea()
                    .transition(.opacity)

                VStack {
                    Spacer()
                    AppTutorialToolbar(
                        step: tutorialSteps[tutorialStep],
                        stepIndex: tutorialStep,
                        totalSteps: tutorialSteps.count,
                        isRequestingScreenTime: isRequestingScreenTime,
                        message: tutorialMessage,
                        nextAction: advanceTutorial
                    )
                    .padding(.horizontal, 16)
                    .padding(.bottom, 84)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .accentColor(MivoColors.accent)
        .onAppear {
            let appearance = UITabBarAppearance()
            appearance.configureWithOpaqueBackground()
            appearance.backgroundColor = UIColor(MivoColors.background)
            UITabBar.appearance().standardAppearance = appearance
            UITabBar.appearance().scrollEdgeAppearance = appearance

            if shouldShowTutorial {
                selectedTab = tutorialSteps[tutorialStep].tab
            }
        }
        .onChange(of: tutorialStep) { _, newValue in
            selectedTab = tutorialSteps[newValue].tab
            tutorialMessage = nil
        }
        .animation(.spring(response: 0.38, dampingFraction: 0.88), value: tutorialStep)
        .animation(.easeInOut(duration: 0.22), value: shouldShowTutorial)
    }

    private var shouldShowTutorial: Bool {
        appVM.settings.onboardingComplete && appVM.settings.tutorialComplete != true
    }

    private func advanceTutorial() {
        guard tutorialStep < tutorialSteps.count else { return }
        let step = tutorialSteps[tutorialStep]

        guard step.requiresScreenTimeAccess else {
            tutorialStep = min(tutorialStep + 1, tutorialSteps.count - 1)
            HapticsService.selection()
            return
        }

        guard !isRequestingScreenTime else { return }
        isRequestingScreenTime = true
        tutorialMessage = nil
        HapticsService.selection()

        Task {
            let granted = await appVM.requestScreenTimeAccessAndRefresh()
            await MainActor.run {
                isRequestingScreenTime = false
                if granted {
                    appVM.completeTutorial()
                    selectedTab = 0
                    tutorialMessage = nil
                    HapticsService.success()
                } else {
                    tutorialMessage = "Screen Time access was not allowed. Tap the button to try again."
                    HapticsService.warning()
                }
            }
        }
    }
}

private struct AppTutorialStep: Identifiable {
    let id: Int
    let tab: Int
    let icon: String
    let title: String
    let body: String
    let buttonTitle: String
    let requiresScreenTimeAccess: Bool

    static let all: [AppTutorialStep] = [
        AppTutorialStep(
            id: 0,
            tab: 0,
            icon: "house.fill",
            title: "Home",
            body: "This is your daily dashboard. Once Screen Time is connected, the large number shows your real device usage for today.",
            buttonTitle: "Next",
            requiresScreenTimeAccess: false
        ),
        AppTutorialStep(
            id: 1,
            tab: 1,
            icon: "calendar",
            title: "Patterns",
            body: "Use this page to see how your days are stacking up and where your scrolling habits repeat.",
            buttonTitle: "Next",
            requiresScreenTimeAccess: false
        ),
        AppTutorialStep(
            id: 2,
            tab: 2,
            icon: "timer",
            title: "Interventions",
            body: "Start a focused session, choose your intention, and add a pause before opening distracting apps.",
            buttonTitle: "Next",
            requiresScreenTimeAccess: false
        ),
        AppTutorialStep(
            id: 3,
            tab: 3,
            icon: "gearshape.fill",
            title: "Settings",
            body: "Manage permissions, account controls, and the Screen Time connection from here.",
            buttonTitle: "Next",
            requiresScreenTimeAccess: false
        ),
        AppTutorialStep(
            id: 4,
            tab: 3,
            icon: "waveform.path.ecg",
            title: "Connect Screen Time",
            body: "Allow Screen Time access so Mivo can replace the 0m placeholder with your actual usage today.",
            buttonTitle: "Allow Screen Time",
            requiresScreenTimeAccess: true
        )
    ]
}

private struct AppTutorialToolbar: View {
    let step: AppTutorialStep
    let stepIndex: Int
    let totalSteps: Int
    let isRequestingScreenTime: Bool
    let message: String?
    let nextAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: step.icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(MivoColors.heroText)
                    .frame(width: 38, height: 38)
                    .background(MivoColors.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(step.title)
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundColor(MivoColors.textPrimary)
                    Text("\(stepIndex + 1) of \(totalSteps)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(MivoColors.textSecondary)
                }

                Spacer()

                Button(action: nextAction) {
                    HStack(spacing: 8) {
                        if isRequestingScreenTime {
                            ProgressView()
                                .tint(MivoColors.heroText)
                                .scaleEffect(0.82)
                        } else {
                            Text(step.buttonTitle)
                            Image(systemName: step.requiresScreenTimeAccess ? "checkmark.shield.fill" : "arrow.right")
                        }
                    }
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(MivoColors.heroText)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(MivoColors.primary)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(isRequestingScreenTime)
            }

            Text(step.body)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(MivoColors.textPrimary)
                .lineSpacing(3)

            if let message {
                Text(message)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(MivoColors.timerRed)
            }

            ProgressView(value: Double(stepIndex + 1), total: Double(totalSteps))
                .tint(MivoColors.accent)
                .background(MivoColors.muted.opacity(0.35))
        }
        .padding(16)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(MivoColors.white.opacity(0.5), lineWidth: 1)
        )
        .shadow(color: MivoColors.primary.opacity(0.24), radius: 22, y: 10)
    }
}
