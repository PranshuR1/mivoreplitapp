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
            appVM.scheduleDailyScrollScheduleNotification()
            appVM.evaluateDailyScrollSchedulePrompt()
            appVM.evaluateTimeTruthPrompt()
            appVM.evaluateGoalForecastPrompt()
            appVM.recoverExpiredRunningSessionIfNeeded()

            if shouldShowTutorial {
                selectedTab = tutorialSteps[tutorialStep].tab
            } else {
                routeForForegroundOpen()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active, !shouldShowTutorial else { return }
            // Defense in depth: every time Mivo becomes active, re-check whether
            // the session has expired in the background and apply shields immediately.
            // This catches the case where iOS didn't wake the DeviceActivityMonitor
            // extension at session end (common in release/App Store builds when the
            // app isn't being debugged from Xcode).
            if #available(iOS 16.0, *) {
                FamilyControlsManager.shared.applyImpulseProtectionIfNeeded()
            }
            appVM.recoverExpiredRunningSessionIfNeeded()
            appVM.checkDeepLinkInterventionFlag()   // pick up flag written by shield extension
            routeForForegroundOpen()
            appVM.scheduleTimeTruthNotification()
            appVM.scheduleDailyScrollScheduleNotification()
            appVM.evaluateDailyScrollSchedulePrompt()
            appVM.evaluateTimeTruthPrompt()
            appVM.evaluateGoalForecastPrompt()
        }
        .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { _ in
            guard !shouldShowTutorial else { return }
            appVM.evaluateDailyScrollSchedulePrompt()
            appVM.evaluateTimeTruthPrompt()
            appVM.evaluateGoalForecastPrompt()
        }
        .onReceive(pendingInterventionPoller) { _ in
            guard scenePhase == .active, !shouldShowTutorial else { return }
            routeToPendingInterventionIfNeeded()
        }
        .onChange(of: appVM.deepLinkInterventionRequested) { _, requested in
            guard requested, !shouldShowTutorial else { return }
            appVM.deepLinkInterventionRequested = false
            selectedTab = 2   // Interventions tab
            HapticsService.selection()
        }
        .onChange(of: tutorialStep) { _, newValue in
            selectedTab = tutorialSteps[newValue].tab
            tutorialMessage = nil
        }
        .fullScreenCover(item: $appVM.pendingExpiredRunningSession) { running in
            SessionEndedReviewView(running: running)
                .environmentObject(appVM)
                .interactiveDismissDisabled()
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
        .fullScreenCover(item: $appVM.pendingDailyScrollSchedulePrompt) { prompt in
            DailyScrollScheduleCheckView(prompt: prompt)
                .environmentObject(appVM)
                .interactiveDismissDisabled()
        }
        .fullScreenCover(item: $appVM.pendingGoalForecastPrompt) { prompt in
            GoalForecastPromptView(prompt: prompt)
                .environmentObject(appVM)
                .interactiveDismissDisabled()
        }
        .fullScreenCover(item: $appVM.pendingResumedActiveSession) { session in
            NavigationStack {
                ActiveSessionView(
                    intention: session.intention,
                    plannedMinutes: session.plannedDuration,
                    urgeReason: session.urgeReason,
                    urgeNote: session.urgeNote
                )
                .environmentObject(appVM)
            }
        }
        .animation(.spring(response: 0.38, dampingFraction: 0.88), value: tutorialStep)
        .animation(.easeInOut(duration: 0.22), value: shouldShowTutorial)
    }

    private var shouldShowTutorial: Bool {
        appVM.settings.onboardingComplete && appVM.settings.tutorialComplete != true
    }
    
    private func routeForForegroundOpen() {
        routeToPendingInterventionIfNeeded()
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

private struct SessionEndedReviewView: View {
    @EnvironmentObject var appVM: AppViewModel
    @Environment(\.dismiss) private var dismiss

    let running: RunningMivoSession

    @State private var showAddTimeSheet = false
    @State private var selectedExtraMinutes: Int = 10
    @State private var customMinutesText = ""
    @FocusState private var customFieldFocused: Bool
    @State private var showEmergencyUnlock = false
    @State private var emergencyUnlockReason = ""
    @State private var showReflection = false
    @State private var activationError: String? = nil

    private var actualMinutes: Int { appVM.cappedElapsedMinutes(for: running) }
    private var actualSeconds: Int { appVM.cappedElapsedSeconds(for: running) }

    private var extensionDecision: SessionExtensionDecision {
        appVM.sessionExtensionDecision(
            intention: running.intention,
            plannedMinutes: running.plannedDuration,
            elapsedSeconds: actualSeconds,
            extensionUsed: running.extendedOnce
        )
    }

    private var allowedTimeOptions: [Int] {
        let maxAllowed = extensionDecision.allowed ? max(extensionDecision.addedMinutes, 5) : 0
        return [5, 10, 15, 20, 30].filter { $0 <= maxAllowed }
    }

    private var maxAllowedMinutes: Int {
        extensionDecision.allowed ? max(extensionDecision.addedMinutes, 5) : 0
    }

    private var customMinutes: Int? {
        Int(customMinutesText.trimmingCharacters(in: .whitespaces))
    }

    private var effectiveMinutes: Int {
        if let c = customMinutes, c > 0 { return c }
        return selectedExtraMinutes
    }

    private var isCustomValid: Bool {
        guard let c = customMinutes else { return true }
        return c > 0 && c <= maxAllowedMinutes
    }

    var body: some View {
        ZStack {
            MivoColors.background.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    // Header
                    VStack(spacing: 14) {
                        ZStack {
                            Circle()
                                .fill(MivoColors.accent.opacity(0.1))
                                .frame(width: 88, height: 88)
                            Image(systemName: "lock.fill")
                                .font(.system(size: 36, weight: .bold))
                                .foregroundColor(MivoColors.accent)
                        }
                        VStack(spacing: 5) {
                            Text("Time's up")
                                .font(.system(size: 34, weight: .bold, design: .rounded))
                                .foregroundColor(MivoColors.textPrimary)
                            Text("The selected app is locked again.")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundColor(MivoColors.textSecondary)
                        }
                    }
                    .padding(.top, 52)
                    .padding(.bottom, 28)

                    // Stats card
                    VStack(spacing: 0) {
                        statRow(label: "Time used", value: formatDuration(actualMinutes), icon: "clock.fill", color: MivoColors.accent)
                        Divider().padding(.leading, 58)
                        statRow(label: "Planned", value: formatDuration(running.plannedDuration), icon: "timer", color: MivoColors.blue)
                        Divider().padding(.leading, 58)
                        statRow(label: "Reason", value: running.intention.rawValue, icon: "tag.fill", color: MivoColors.secondary)
                        if running.extendedOnce {
                            Divider().padding(.leading, 58)
                            statRow(label: "Extended", value: "Once", icon: "arrow.triangle.2.circlepath", color: MivoColors.timerOrange)
                        }
                    }
                    .background(MivoColors.card)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(MivoColors.border.opacity(0.7), lineWidth: 1))
                    .shadow(color: MivoColors.primary.opacity(0.05), radius: 10, y: 4)
                    .padding(.horizontal, 22)

                    if let err = activationError {
                        Text(err)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(MivoColors.timerRed)
                            .lineSpacing(3)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(MivoColors.timerRed.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .padding(.horizontal, 22)
                            .padding(.top, 12)
                    }

                    // Actions
                    VStack(spacing: 10) {
                        if extensionDecision.allowed {
                            Button { showAddTimeSheet = true } label: {
                                HStack {
                                    Image(systemName: "plus.circle.fill")
                                        .font(.system(size: 17))
                                    Text("Add more time")
                                        .font(.system(size: 16, weight: .semibold))
                                }
                                .foregroundColor(MivoColors.accent)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(MivoColors.accentMuted)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(MivoColors.accentLight, lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                        }

                        Button { showEmergencyUnlock = true } label: {
                            HStack {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 14))
                                Text("Emergency unlock")
                                    .font(.system(size: 15, weight: .semibold))
                            }
                            .foregroundColor(MivoColors.timerOrange)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(MivoColors.timerOrange.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                        }
                        .buttonStyle(.plain)

                        Button { showReflection = true } label: {
                            Text("Save and finish session")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(MivoColors.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(MivoColors.accent)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 22)
                    .padding(.top, 28)
                    .padding(.bottom, 50)
                }
            }
        }
        .sheet(isPresented: $showAddTimeSheet) { addTimeSheet }
        .sheet(isPresented: $showEmergencyUnlock) { emergencyUnlockSheet }
        .fullScreenCover(isPresented: $showReflection) {
            ReflectionView(
                intention: running.intention,
                plannedDuration: running.plannedDuration,
                actualDuration: actualMinutes,
                startTime: running.startTime,
                endTime: running.expiredAt ?? ISO8601DateFormatter().string(from: Date()),
                extendedOnce: running.extendedOnce,
                urgeReason: running.urgeReason,
                urgeNote: running.urgeNote,
                emergencyUnlockUsed: running.emergencyUnlockUsed == true,
                emergencyUnlockReason: running.emergencyUnlockReason,
                onSaved: {
                    appVM.clearExpiredRunningSessionReview()
                    dismiss()
                }
            )
            .interactiveDismissDisabled()
        }
        .onAppear {
            let opts = allowedTimeOptions
            if !opts.isEmpty { selectedExtraMinutes = opts.first! }
        }
    }

    private func statRow(label: String, value: String, icon: String, color: Color) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(color)
                .frame(width: 32, height: 32)
                .background(color.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            Text(label)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(MivoColors.textSecondary)
            Spacer()
            Text(value)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(MivoColors.textPrimary)
                .lineLimit(1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private var addTimeSheet: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    if extensionDecision.allowed {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Add more time")
                                .font(.system(size: 26, weight: .bold, design: .rounded))
                                .foregroundColor(MivoColors.textPrimary)
                            Text(extensionDecision.message)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(MivoColors.textSecondary)
                                .lineSpacing(3)
                        }

                        // Preset quick-pick options
                        if !allowedTimeOptions.isEmpty {
                            VStack(spacing: 8) {
                                ForEach(allowedTimeOptions, id: \.self) { mins in
                                    Button {
                                        selectedExtraMinutes = mins
                                        customMinutesText = ""
                                        customFieldFocused = false
                                        HapticsService.selection()
                                    } label: {
                                        HStack {
                                            Text("\(mins) minutes")
                                                .font(.system(size: 16, weight: .semibold))
                                                .foregroundColor(isPresetSelected(mins) ? MivoColors.white : MivoColors.textPrimary)
                                            Spacer()
                                            if isPresetSelected(mins) {
                                                Image(systemName: "checkmark")
                                                    .font(.system(size: 13, weight: .bold))
                                                    .foregroundColor(.white)
                                            }
                                        }
                                        .padding(.horizontal, 18)
                                        .padding(.vertical, 15)
                                        .background(isPresetSelected(mins) ? MivoColors.accent : MivoColors.card)
                                        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                                        .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous)
                                            .strokeBorder(isPresetSelected(mins) ? MivoColors.accent : MivoColors.border, lineWidth: 1))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }

                        // Custom minutes input
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Or type a custom amount")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(MivoColors.textMuted)

                            HStack(spacing: 10) {
                                TextField("e.g. 7", text: $customMinutesText)
                                    .keyboardType(.numberPad)
                                    .focused($customFieldFocused)
                                    .font(.system(size: 17, weight: .semibold))
                                    .foregroundColor(MivoColors.textPrimary)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 13)
                                    .background(MivoColors.card)
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .strokeBorder(customFieldFocused ? MivoColors.accent : MivoColors.border, lineWidth: 1))
                                    .onChange(of: customMinutesText) { _, _ in
                                        // deselect preset when typing
                                        if !customMinutesText.isEmpty {
                                            selectedExtraMinutes = 0
                                        }
                                    }

                                Text("min")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(MivoColors.textSecondary)
                            }

                            if let c = customMinutes, c > 0, !isCustomValid {
                                Text("Max allowed is \(maxAllowedMinutes) min based on your plan.")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(MivoColors.timerRed)
                            }
                        }

                        Spacer(minLength: 24)

                        Button { applyAddTime() } label: {
                            Text(effectiveMinutes > 0 ? "Add \(effectiveMinutes) minutes" : "Pick a duration")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(MivoColors.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(canApplyAddTime ? MivoColors.accent : MivoColors.muted)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .disabled(!canApplyAddTime)
                    } else {
                        VStack(alignment: .leading, spacing: 14) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 46))
                                .foregroundColor(MivoColors.timerRed)
                            Text(extensionDecision.title)
                                .font(.system(size: 22, weight: .bold, design: .rounded))
                                .foregroundColor(MivoColors.textPrimary)
                            Text(extensionDecision.message)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundColor(MivoColors.textSecondary)
                                .lineSpacing(4)
                        }
                    }
                }
                .padding(22)
            }
            .background(MivoColors.background.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showAddTimeSheet = false }
                }
            }
        }
    }

    private func isPresetSelected(_ mins: Int) -> Bool {
        customMinutesText.isEmpty && selectedExtraMinutes == mins
    }

    private var canApplyAddTime: Bool {
        effectiveMinutes > 0 && isCustomValid
    }

    private func applyAddTime() {
        guard canApplyAddTime else { return }
        if appVM.extendExpiredRunningSession(running, addedMinutes: effectiveMinutes) {
            showAddTimeSheet = false
            HapticsService.success()
            // pendingResumedActiveSession is now set → MainTabView will present ActiveSessionView
            dismiss()
        } else {
            activationError = appVM.sessionActivationError ?? "Mivo could not safely add more time."
            showAddTimeSheet = false
            HapticsService.warning()
        }
    }

    private var emergencyUnlockSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                Text("Emergency unlock")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundColor(MivoColors.textPrimary)
                Text("Write why this needs to happen now. Mivo will record it and allow 5 more minutes if the blocker can be scheduled.")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(MivoColors.textSecondary)
                    .lineSpacing(4)
                TextEditor(text: $emergencyUnlockReason)
                    .font(.system(size: 15))
                    .foregroundColor(MivoColors.textPrimary)
                    .scrollContentBackground(.hidden)
                    .padding(10)
                    .frame(minHeight: 120)
                    .background(MivoColors.card)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(MivoColors.border, lineWidth: 1))
                Button { applyEmergencyUnlock() } label: {
                    Text("Unlock 5 minutes")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(MivoColors.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(canUseEmergencyUnlock ? MivoColors.accent : MivoColors.accentLight)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .disabled(!canUseEmergencyUnlock)
                Spacer()
            }
            .padding(22)
            .background(MivoColors.background.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showEmergencyUnlock = false }
                }
            }
        }
    }

    private var canUseEmergencyUnlock: Bool {
        emergencyUnlockReason.trimmingCharacters(in: .whitespacesAndNewlines).count >= 3
    }

    private func applyEmergencyUnlock() {
        let reason = emergencyUnlockReason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard reason.count >= 3 else { return }
        if appVM.extendExpiredRunningSession(running, addedMinutes: 5, emergencyReason: reason) {
            showEmergencyUnlock = false
            HapticsService.success()
            dismiss()
        } else {
            activationError = appVM.sessionActivationError ?? "Mivo could not safely start the emergency unlock."
            HapticsService.warning()
        }
    }
}

private struct DailyScrollScheduleCheckView: View {
    @EnvironmentObject var appVM: AppViewModel
    let prompt: DailyScrollSchedulePrompt

    @State private var firstHour: Int
    @State private var secondHour: Int

    init(prompt: DailyScrollSchedulePrompt) {
        self.prompt = prompt
        let first = prompt.recommendedWindows.first?.startHour ?? 14
        let second = prompt.recommendedWindows.dropFirst().first?.startHour ?? 20
        _firstHour = State(initialValue: first)
        _secondHour = State(initialValue: second)
    }

    var body: some View {
        ZStack {
            MivoColors.background.ignoresSafeArea()
            VStack(spacing: 0) {
                Spacer(minLength: 24)
                VStack(spacing: 22) {
                    ZStack {
                        Circle()
                            .fill(MivoColors.surface)
                            .frame(width: 102, height: 102)
                            .overlay(Circle().strokeBorder(MivoColors.border.opacity(0.7), lineWidth: 1))
                        Image(systemName: prompt.isRecommendationReady ? "sparkles" : "clock.badge.checkmark")
                            .font(.system(size: 42, weight: .bold))
                            .foregroundColor(MivoColors.accent)
                            .symbolEffect(.pulse, options: .repeating.speed(0.48))
                    }

                    VStack(spacing: 9) {
                        Text("Set today’s scroll times")
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .foregroundColor(MivoColors.textPrimary)
                            .multilineTextAlignment(.center)
                        Text(prompt.isRecommendationReady ? "Mivo recommends these two windows from your last 3 days. You can adjust now, then today is locked." : "Choose your two scroll windows for today. Once saved, you can’t keep moving them around for extra time.")
                            .font(.system(size: 16, weight: .semibold))
                            .multilineTextAlignment(.center)
                            .foregroundColor(MivoColors.textSecondary)
                            .lineSpacing(3)
                            .padding(.horizontal, 14)
                    }

                    VStack(spacing: 12) {
                        scheduleStepper(title: "Session 1", hour: $firstHour)
                        scheduleStepper(title: "Session 2", hour: $secondHour)

                        MivoButton(label: "Lock today’s schedule", action: save, icon: "lock.fill")

                        Text("Daily schedule check: 8:00 AM. You can choose again tomorrow morning.")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(MivoColors.textMuted)
                            .multilineTextAlignment(.center)
                            .lineSpacing(2)
                    }
                    .padding(18)
                    .background(MivoColors.card)
                    .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(MivoColors.border.opacity(0.75), lineWidth: 1))
                    .shadow(color: MivoColors.primary.opacity(0.08), radius: 20, y: 10)
                }
                .padding(.horizontal, 20)
                Spacer(minLength: 24)
            }
        }
    }

    private func scheduleStepper(title: String, hour: Binding<Int>) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(MivoColors.textPrimary)
                Text("\(hourLabel(hour.wrappedValue))-\(hourLabel((hour.wrappedValue + 1) % 24))")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(MivoColors.textMuted)
            }
            Spacer()
            Button { adjust(hour, by: -1) } label: {
                Image(systemName: "minus")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(MivoColors.textPrimary)
                    .frame(width: 38, height: 38)
                    .background(MivoColors.background)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            Text(hourLabel(hour.wrappedValue))
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundColor(MivoColors.textPrimary)
                .frame(width: 64)
            Button { adjust(hour, by: 1) } label: {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(MivoColors.textPrimary)
                    .frame(width: 38, height: 38)
                    .background(MivoColors.background)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(MivoColors.surface.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func adjust(_ hour: Binding<Int>, by delta: Int) {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
            hour.wrappedValue = ((hour.wrappedValue + delta) % 24 + 24) % 24
        }
        HapticsService.selection()
    }

    private func save() {
        appVM.saveDailyScrollScheduleForToday([
            ScreenScrollWindow(id: "daily-prompt-1", title: "Today’s session 1", startHour: firstHour, endHour: min(24, firstHour + 1), minutes: 15, reason: "Locked for today."),
            ScreenScrollWindow(id: "daily-prompt-2", title: "Today’s session 2", startHour: secondHour, endHour: min(24, secondHour + 1), minutes: 15, reason: "Locked for today.")
        ])
        HapticsService.success()
    }

    private func hourLabel(_ hour: Int) -> String {
        let normalized = ((hour % 24) + 24) % 24
        if normalized == 0 { return "12a" }
        if normalized < 12 { return "\(normalized)a" }
        if normalized == 12 { return "12p" }
        return "\(normalized - 12)p"
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

// MARK: - Goal forecast prompt
//
// One-time post-observation prompt that tells the user how their personalized
// plan will get them from their 3-day observation average to their daily
// scroll goal. Similar styling to TimeTruthCheckView.

private struct GoalForecastPromptView: View {
    @EnvironmentObject var appVM: AppViewModel
    let prompt: GoalForecastPrompt

    var body: some View {
        ZStack {
            MivoColors.background.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 22) {
                    iconMark

                    VStack(spacing: 9) {
                        Text("Your plan is ready")
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                            .foregroundColor(MivoColors.textPrimary)
                            .multilineTextAlignment(.center)

                        Text("Based on your 3 days of real usage, here is how Mivo will get you to your goal.")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(MivoColors.textSecondary)
                            .multilineTextAlignment(.center)
                            .lineSpacing(3)
                            .padding(.horizontal, 14)
                    }

                    summaryCard
                    timelineCard

                    Button {
                        appVM.dismissGoalForecastPrompt()
                        HapticsService.success()
                    } label: {
                        Text("Start my plan")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(MivoColors.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 17)
                            .background(MivoColors.textPrimary)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .shadow(color: MivoColors.textPrimary.opacity(0.22), radius: 14, y: 8)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 30)
            }
        }
    }

    private var iconMark: some View {
        ZStack {
            Circle()
                .fill(MivoColors.surface)
                .frame(width: 102, height: 102)
                .overlay(Circle().strokeBorder(MivoColors.border.opacity(0.7), lineWidth: 1))
            Image(systemName: "target")
                .font(.system(size: 42, weight: .bold))
                .foregroundColor(MivoColors.accent)
        }
    }

    private var summaryCard: some View {
        VStack(spacing: 12) {
            HStack {
                bigStat(label: "Observation avg", value: format(prompt.observationAverageMinutes))
                bigStat(label: "Your goal", value: format(prompt.goalMinutes), accent: true)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("\(prompt.daysToReachGoal) days to reach \(format(prompt.goalMinutes))")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(MivoColors.textPrimary)
                Text("Mivo will trim a few minutes off each day — small in week 1, then a bit more each week. Once you reach the goal, the plan holds steady.")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(MivoColors.textSecondary)
                    .lineSpacing(3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .background(MivoColors.white.opacity(0.62))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(MivoColors.white.opacity(0.58), lineWidth: 1))
    }

    private var timelineCard: some View {
        VStack(spacing: 10) {
            timelineRow(day: "Day 1", value: format(prompt.firstPlanDayTarget), color: MivoColors.accent)
            timelineRow(day: "Day 8", value: format(prompt.oneWeekTarget), color: MivoColors.accent)
            timelineRow(day: "Day 15", value: format(prompt.twoWeekTarget), color: MivoColors.accent)
            timelineRow(day: "Day \(prompt.daysToReachGoal)", value: format(prompt.goalMinutes), color: MivoColors.timerGreen, highlight: true)
        }
        .padding(16)
        .background(MivoColors.white.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(MivoColors.white.opacity(0.58), lineWidth: 1))
    }

    private func timelineRow(day: String, value: String, color: Color, highlight: Bool = false) -> some View {
        HStack {
            Circle()
                .fill(color)
                .frame(width: 9, height: 9)
            Text(day)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(MivoColors.textPrimary)
            Spacer()
            Text(value)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundColor(highlight ? MivoColors.timerGreen : MivoColors.textPrimary)
                .monospacedDigit()
            if highlight {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(MivoColors.timerGreen)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(highlight ? MivoColors.timerGreen.opacity(0.14) : MivoColors.surface.opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func bigStat(label: String, value: String, accent: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(MivoColors.textMuted)
                .textCase(.uppercase)
            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundColor(accent ? MivoColors.accent : MivoColors.textPrimary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(MivoColors.heroText.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func format(_ minutes: Int) -> String {
        if minutes < 60 { return "\(minutes)m" }
        let h = minutes / 60
        let m = minutes % 60
        return m == 0 ? "\(h)h" : "\(h)h \(m)m"
    }
}
