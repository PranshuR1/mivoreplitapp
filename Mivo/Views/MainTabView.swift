import SwiftUI

struct MainTabView: View {
    @EnvironmentObject var appVM: AppViewModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedTab = 0
    @State private var tutorialStep = 0
    @State private var isRequestingScreenTime = false
    @State private var tutorialMessage: String? = nil

    private let tutorialSteps = AppTutorialStep.all
    private let pendingInterventionPoller = Timer.publish(every: 0.75, on: .main, in: .common).autoconnect()

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
            appVM.scheduleTimeTruthNotification()
            appVM.evaluateTimeTruthPrompt()
            appVM.recoverExpiredRunningSessionIfNeeded()

            if shouldShowTutorial {
                selectedTab = tutorialSteps[tutorialStep].tab
            } else {
                routeForForegroundOpen()
            }
        }
        .onChange(of: scenePhase) { phase in
            guard phase == .active, !shouldShowTutorial else { return }
            appVM.recoverExpiredRunningSessionIfNeeded()
            routeForForegroundOpen()
            appVM.scheduleTimeTruthNotification()
            appVM.evaluateTimeTruthPrompt()
        }
        .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { _ in
            guard !shouldShowTutorial else { return }
            appVM.evaluateTimeTruthPrompt()
        }
        .onReceive(pendingInterventionPoller) { _ in
            guard scenePhase == .active, !shouldShowTutorial else { return }
            routeToPendingInterventionIfNeeded()
        }
        .onChange(of: tutorialStep) { newValue in
            selectedTab = tutorialSteps[newValue].tab
            tutorialMessage = nil
        }
        .fullScreenCover(item: $appVM.pendingSessionFeedback) { feedback in
            ReflectionView(
                intention: feedback.intention,
                plannedDuration: feedback.plannedDuration,
                actualDuration: feedback.actualDuration,
                startTime: feedback.startTime,
                endTime: feedback.endTime,
                extendedOnce: feedback.extendedOnce,
                urgeReason: feedback.urgeReason,
                urgeNote: feedback.urgeNote,
                emergencyUnlockUsed: feedback.emergencyUnlockUsed == true,
                emergencyUnlockReason: feedback.emergencyUnlockReason,
                onSaved: {
                    appVM.clearPendingSessionFeedback()
                }
            )
            .interactiveDismissDisabled()
        }
        .fullScreenCover(item: $appVM.pendingTimeTruthPrompt) { prompt in
            TimeTruthCheckView(prompt: prompt)
                .environmentObject(appVM)
        }
        .animation(.spring(response: 0.38, dampingFraction: 0.88), value: tutorialStep)
        .animation(.easeInOut(duration: 0.22), value: shouldShowTutorial)
    }

    private var shouldShowTutorial: Bool {
        appVM.settings.onboardingComplete && appVM.settings.tutorialComplete != true
    }
    
    private func routeForForegroundOpen() {
        if !routeToPendingInterventionIfNeeded() {
            selectedTab = 0
        }
    }

    @discardableResult
    private func routeToPendingInterventionIfNeeded() -> Bool {
        guard appVM.consumePendingInterventionSetup() else { return false }
        selectedTab = 2
        HapticsService.selection()
        return true
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

private struct TimeTruthCheckView: View {
    @EnvironmentObject var appVM: AppViewModel
    let prompt: TimeTruthPrompt

    @State private var guessText = ""
    @State private var revealedGuess: Int? = nil
    @State private var saved = false
    @FocusState private var guessFocused: Bool

    private var guessMinutes: Int? {
        Int(guessText.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private var scheduledText: String {
        let date = Calendar.current.date(
            bySettingHour: prompt.scheduledHour,
            minute: prompt.scheduledMinute,
            second: 0,
            of: Date()
        ) ?? Date()
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }

    var body: some View {
        ZStack {
            MivoColors.background.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer(minLength: 24)

                VStack(spacing: 22) {
                    iconMark

                    VStack(spacing: 9) {
                        Text("Time Truth")
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .foregroundColor(MivoColors.textPrimary)

                        Text(revealedGuess == nil ? "Before Mivo reveals today, make a quick guess." : "Here is the real total Mivo has for today.")
                            .font(.system(size: 16, weight: .semibold))
                            .multilineTextAlignment(.center)
                            .foregroundColor(MivoColors.textSecondary)
                            .lineSpacing(3)
                            .padding(.horizontal, 14)
                    }

                    if let revealedGuess {
                        revealedContent(guess: revealedGuess)
                    } else {
                        guessContent
                    }
                }
                .padding(.horizontal, 20)

                Spacer(minLength: 24)
            }
        }
        .onAppear {
            guessFocused = true
        }
    }

    private var iconMark: some View {
        ZStack {
            Circle()
                .fill(MivoColors.surface)
                .frame(width: 102, height: 102)
                .overlay(Circle().strokeBorder(MivoColors.border.opacity(0.7), lineWidth: 1))

            Image(systemName: "hourglass")
                .font(.system(size: 42, weight: .bold))
                .foregroundColor(MivoColors.accent)
                .symbolEffect(.pulse, options: .repeating.speed(0.42))
        }
    }

    private var guessContent: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Your guess")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(MivoColors.textMuted)
                    .textCase(.uppercase)

                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    TextField("0", text: $guessText)
                        .keyboardType(.numberPad)
                        .focused($guessFocused)
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .foregroundColor(MivoColors.textPrimary)
                        .multilineTextAlignment(.center)
                        .padding(.vertical, 8)

                    Text("min")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(MivoColors.textSecondary)
                }
                .padding(.horizontal, 18)
                .background(MivoColors.white.opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(MivoColors.border.opacity(0.75), lineWidth: 1)
                )
            }

            HStack(spacing: 10) {
                quickGuessButton(30)
                quickGuessButton(60)
                quickGuessButton(120)
            }

            MivoButton(
                label: "Reveal truth",
                action: reveal,
                disabled: guessMinutes == nil,
                icon: "eye.fill"
            )

            Text("Daily check time: \(scheduledText). After a few days, Mivo moves this to your heaviest scroll window.")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(MivoColors.textMuted)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
        }
        .padding(18)
        .background(MivoColors.card)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .strokeBorder(MivoColors.border.opacity(0.75), lineWidth: 1)
        )
        .shadow(color: MivoColors.primary.opacity(0.08), radius: 20, y: 10)
    }

    private func revealedContent(guess: Int) -> some View {
        let delta = guess - prompt.actualMinutes
        return VStack(spacing: 18) {
            HStack(spacing: 12) {
                truthStat(title: "You guessed", value: formatDuration(guess), tint: MivoColors.secondary)
                truthStat(title: "Actual", value: formatDuration(prompt.actualMinutes), tint: MivoColors.accent)
            }

            VStack(spacing: 6) {
                Text(deltaText(delta))
                    .font(.system(size: 21, weight: .bold, design: .rounded))
                    .foregroundColor(MivoColors.textPrimary)
                    .multilineTextAlignment(.center)

                Text("This is saved to your Truth Checks so the statistics page can learn from your guesses.")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(MivoColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }

            MivoButton(label: "Done", action: appVM.dismissTimeTruthPrompt, icon: "checkmark")
        }
        .padding(18)
        .background(MivoColors.card)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .strokeBorder(MivoColors.border.opacity(0.75), lineWidth: 1)
        )
        .shadow(color: MivoColors.primary.opacity(0.08), radius: 20, y: 10)
    }

    private func quickGuessButton(_ minutes: Int) -> some View {
        Button {
            guessText = "\(minutes)"
            HapticsService.selection()
        } label: {
            Text(formatDuration(minutes))
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(guessText == "\(minutes)" ? MivoColors.white : MivoColors.textPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(guessText == "\(minutes)" ? MivoColors.accent : MivoColors.white.opacity(0.42))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    private func truthStat(title: String, value: String, tint: Color) -> some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(MivoColors.textMuted)
                .textCase(.uppercase)
            Text(value)
                .font(.system(size: 25, weight: .bold, design: .rounded))
                .foregroundColor(tint)
                .minimumScaleFactor(0.75)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .background(MivoColors.white.opacity(0.42))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func reveal() {
        guard let guess = guessMinutes, !saved else { return }
        saved = true
        appVM.recordTimeTruthGuess(guess, for: prompt)
        withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) {
            revealedGuess = guess
        }
        HapticsService.success()
    }

    private func deltaText(_ delta: Int) -> String {
        if delta == 0 {
            return "Exactly right."
        }
        if delta > 0 {
            return "You guessed \(formatDuration(delta)) higher than the real total."
        }
        return "You guessed \(formatDuration(abs(delta))) lower than the real total."
    }
}

private struct MivoLaunchGateOverlay: View {
    var body: some View {
        VStack {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(MivoColors.heroText)
                    .frame(width: 38, height: 38)
                    .background(MivoColors.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text("Start with intention")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundColor(MivoColors.textPrimary)
                    Text("Mivo is locked until you start a session. Choose why you opened the app and how long you need.")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(MivoColors.textSecondary)
                        .lineSpacing(3)
                }

                Spacer()
            }
            .padding(16)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(MivoColors.white.opacity(0.5), lineWidth: 1)
            )
            .shadow(color: MivoColors.primary.opacity(0.18), radius: 18, y: 8)
            .padding(.horizontal, 16)
            .padding(.top, 14)

            Spacer()
        }
        .allowsHitTesting(false)
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
            body: "Allow Screen Time access so Mivo can show your real iOS usage today.",
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
