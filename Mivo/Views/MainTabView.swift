import SwiftUI

struct MainTabView: View {
    @EnvironmentObject var appVM: AppViewModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedTab = 0
    @State private var tutorialStep = 0
    @State private var isRequestingScreenTime = false
    @State private var tutorialMessage: String? = nil
    @State private var completedTutorialDemos: Set<Int> = []
    @State private var activeAnnouncement: MivoAnnouncement?
    @State private var requestedAdminUser: AdminUserRoute?
    @State private var openExpiredAddTimeImmediately = false
    @State private var showDeepLinkedReferralHub = false
    @State private var completedExperimentForReview: WeeklyExperiment?
    @State private var deferredExperimentReviewID: String?

    private let currentTutorialVersion = 3
    private let pendingInterventionPoller = Timer.publish(every: 0.75, on: .main, in: .common).autoconnect()

    private var tutorialSteps: [AppTutorialStep] {
        AppTutorialStep.steps(for: appVM.accountRole)
    }

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
                    InterventionsView {
                        selectedTab = 0
                    }
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
                AppTutorialOverlay(
                    step: currentTutorialStep,
                    stepIndex: tutorialStep,
                    totalSteps: tutorialSteps.count,
                    isRequestingScreenTime: isRequestingScreenTime,
                    message: tutorialMessage,
                    demoCompleted: completedTutorialDemos.contains(currentTutorialStep.id),
                    demoAction: performTutorialDemo,
                    backAction: tutorialStep == 0 ? nil : retreatTutorial,
                    skipAction: skipTutorial,
                    nextAction: advanceTutorial
                )
                .transition(.opacity)
            }

        }
        .accentColor(MivoColors.accent)
        .onChange(of: selectedTab) { oldValue, newValue in
            guard oldValue != newValue else { return }
            HapticsService.selection()
        }
        .onAppear {
            MivoDiagnosticsService.shared.startForActiveUser()
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
            appVM.refreshWeeklyExperimentLifecycle()
            presentCompletedExperimentReviewIfNeeded()
            appVM.recoverExpiredRunningSessionIfNeeded()
            cleanupSessionEndedNotificationsIfNeeded()
            appVM.validateCurrentRemoteAccount()
            Task {
                await ProductExpansionStore.shared.prepare(for: appVM)
                await appVM.refreshServerAdminRole()
                await ReferralCampaignService.logEvent("app_open")
                await loadAnnouncement()
            }
            routePendingAdminNotification()
            appVM.checkPendingMivoClearRoute()

            if shouldShowTutorial {
                selectedTab = currentTutorialStep.tab
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
            cleanupSessionEndedNotificationsIfNeeded()
            appVM.validateCurrentRemoteAccount()
            appVM.checkDeepLinkInterventionFlag()   // pick up flag written by shield extension
            appVM.checkPendingMivoClearRoute()
            routeForForegroundOpen()
            appVM.scheduleTimeTruthNotification()
            appVM.scheduleDailyScrollScheduleNotification()
            appVM.evaluateDailyScrollSchedulePrompt()
            appVM.evaluateTimeTruthPrompt()
            appVM.evaluateGoalForecastPrompt()
            appVM.refreshWeeklyExperimentLifecycle()
            presentCompletedExperimentReviewIfNeeded()
            Task {
                await ProductExpansionStore.shared.prepare(for: appVM)
                await appVM.refreshServerAdminRole()
                await ReferralCampaignService.logEvent("app_open")
                await loadAnnouncement()
            }
            routePendingAdminNotification()
        }
        .onReceive(Timer.publish(every: 5, on: .main, in: .common).autoconnect()) { _ in
            guard scenePhase == .active, !shouldShowTutorial else { return }
            Task { await appVM.refreshServerAdminRole() }
        }
        .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { _ in
            guard !shouldShowTutorial else { return }
            appVM.evaluateDailyScrollSchedulePrompt()
            appVM.evaluateTimeTruthPrompt()
            appVM.evaluateGoalForecastPrompt()
            appVM.refreshWeeklyExperimentLifecycle()
            presentCompletedExperimentReviewIfNeeded()
            Task {
                await ProductExpansionStore.shared.prepare(for: appVM)
                await MivoClearStore.shared.prepare(for: appVM)
            }
        }
        .onReceive(pendingInterventionPoller) { _ in
            guard scenePhase == .active, !shouldShowTutorial else { return }
            routeToPendingInterventionIfNeeded()
        }
        .onChange(of: appVM.deepLinkInterventionRequested) { _, requested in
            guard requested, !shouldShowTutorial else { return }
            routeToDeepLinkedInterventionIfNeeded()
        }
        .onChange(of: appVM.liveActivityDeepLinkAction) { _, action in
            guard action != nil, !shouldShowTutorial else { return }
            routeToLiveActivityActionIfNeeded()
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("mivoClearRequested"))) { _ in
            guard !shouldShowTutorial else { return }
            appVM.checkPendingMivoClearRoute()
        }
        .onChange(of: tutorialStep) { _, newValue in
            let safeIndex = min(max(0, newValue), tutorialSteps.count - 1)
            selectedTab = tutorialSteps[safeIndex].tab
            tutorialMessage = nil
        }
        .onChange(of: appVM.accountRole) { _, _ in
            if tutorialStep >= tutorialSteps.count {
                tutorialStep = max(0, tutorialSteps.count - 1)
            }
        }
        .onChange(of: appVM.completedWeeklyExperimentAwaitingFeedback?.id) { _, _ in
            presentCompletedExperimentReviewIfNeeded()
        }
        .onChange(of: appVM.settings.tutorialComplete) { _, complete in
            guard complete == false else { return }
            tutorialStep = 0
            completedTutorialDemos.removeAll()
            tutorialMessage = nil
            selectedTab = tutorialSteps[0].tab
        }
        .fullScreenCover(item: $appVM.pendingExpiredRunningSession) { running in
            SessionEndedReviewView(
                running: running,
                startWithAddTime: openExpiredAddTimeImmediately,
                onFinished: {
                    openExpiredAddTimeImmediately = false
                    selectedTab = 0
                }
            )
                .environmentObject(appVM)
                .interactiveDismissDisabled()
        }
        .fullScreenCover(item: $appVM.pendingMivoClearRoute) { route in
            MivoClearHubView(initialRoute: route)
                .environmentObject(appVM)
        }
        .fullScreenCover(item: $appVM.pendingSessionFeedback) { feedback in
            ReflectionView(
                sessionID: feedback.id,
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
                    selectedTab = 0
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
                    urgeNote: session.urgeNote,
                    sessionID: session.id,
                    onFinished: {
                        appVM.pendingResumedActiveSession = nil
                        selectedTab = 0
                    }
                )
                .environmentObject(appVM)
            }
        }
        .sheet(item: $activeAnnouncement) { announcement in
            AnnouncementPresentationView(announcement: announcement) {
                Task {
                    try? await ReferralCampaignService.markAnnouncementSeen(id: announcement.id, dismissed: true)
                    activeAnnouncement = nil
                }
            }
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $requestedAdminUser) { route in
            NavigationStack {
                AdminPushUserDestinationView(userID: route.id)
                    .environmentObject(appVM)
            }
        }
        .sheet(isPresented: $showDeepLinkedReferralHub) {
            ReferralHubView()
                .environmentObject(appVM)
        }
        .sheet(item: $completedExperimentForReview) { experiment in
            WeeklyExperimentCompletionView(
                experiment: experiment,
                onLater: {
                    deferredExperimentReviewID = experiment.id
                    completedExperimentForReview = nil
                },
                onCompleted: {
                    deferredExperimentReviewID = nil
                    completedExperimentForReview = nil
                }
            )
            .environmentObject(appVM)
            .interactiveDismissDisabled()
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("mivoAdminUserRequested"))) { note in
            guard let userID = note.object as? String else { return }
            selectedTab = 3
            requestedAdminUser = AdminUserRoute(id: userID)
        }
        .onChange(of: appVM.deepLinkReferralHubRequested) { _, requested in
            guard requested, !shouldShowTutorial else { return }
            routeToDeepLinkedReferralHubIfNeeded()
        }
        .animation(.spring(response: 0.38, dampingFraction: 0.88), value: tutorialStep)
        .animation(.easeInOut(duration: 0.22), value: shouldShowTutorial)
    }

    private var shouldShowTutorial: Bool {
        appVM.settings.onboardingComplete
            && (appVM.settings.tutorialComplete != true
                || UserDefaults.standard.integer(forKey: tutorialVersionKey) < currentTutorialVersion)
    }

    private var tutorialVersionKey: String {
        let account = appVM.user?.email.lowercased() ?? "local"
        return "mivo.tutorial.version.\(account)"
    }

    private var completedExperimentReviewHistoryKey: String {
        let account = appVM.user?.email.lowercased() ?? "local"
        return "mivo.experiment.completed-review-history.\(account)"
    }

    private var currentTutorialStep: AppTutorialStep {
        tutorialSteps[min(max(0, tutorialStep), tutorialSteps.count - 1)]
    }

    private func presentCompletedExperimentReviewIfNeeded() {
        guard !shouldShowTutorial,
              completedExperimentForReview == nil,
              appVM.pendingExpiredRunningSession == nil,
              appVM.pendingSessionFeedback == nil,
              appVM.pendingTimeTruthPrompt == nil,
              appVM.pendingDailyScrollSchedulePrompt == nil,
              appVM.pendingGoalForecastPrompt == nil,
              let experiment = appVM.completedWeeklyExperimentAwaitingFeedback,
              deferredExperimentReviewID != experiment.id,
              !hasPresentedCompletedExperimentReview(experiment.id) else { return }
        markCompletedExperimentReviewPresented(experiment.id)
        completedExperimentForReview = experiment
        HapticsService.success()
    }

    private func hasPresentedCompletedExperimentReview(_ experimentID: String) -> Bool {
        let presentedIDs = UserDefaults.standard.stringArray(
            forKey: completedExperimentReviewHistoryKey
        ) ?? []
        return presentedIDs.contains(experimentID)
    }

    private func markCompletedExperimentReviewPresented(_ experimentID: String) {
        var presentedIDs = UserDefaults.standard.stringArray(
            forKey: completedExperimentReviewHistoryKey
        ) ?? []
        guard !presentedIDs.contains(experimentID) else { return }
        presentedIDs.append(experimentID)
        UserDefaults.standard.set(
            Array(presentedIDs.suffix(20)),
            forKey: completedExperimentReviewHistoryKey
        )
    }

    private func loadAnnouncement() async {
        guard !shouldShowTutorial, activeAnnouncement == nil else { return }
        do {
            try await appVM.prepareAuthenticatedCampaignSession()
            guard let announcement = try await ReferralCampaignService.unseenAnnouncements().first else { return }
            activeAnnouncement = announcement
            try? await ReferralCampaignService.markAnnouncementSeen(id: announcement.id, dismissed: false)
        } catch {
            // Announcements should never interrupt the rest of Mivo when offline.
        }
    }
    
    private func routeForForegroundOpen() {
        appVM.checkDeepLinkInterventionFlag()
        if routeToDeepLinkedReferralHubIfNeeded() {
            return
        }
        if routeToLiveActivityActionIfNeeded() {
            return
        }
        if routeToDeepLinkedInterventionIfNeeded() {
            return
        }
        routeToPendingInterventionIfNeeded()
    }

    @discardableResult
    private func routeToDeepLinkedReferralHubIfNeeded() -> Bool {
        guard appVM.deepLinkReferralHubRequested else { return false }
        appVM.deepLinkReferralHubRequested = false
        selectedTab = 0
        showDeepLinkedReferralHub = true
        HapticsService.selection()
        return true
    }

    @discardableResult
    private func routeToLiveActivityActionIfNeeded() -> Bool {
        guard let action = appVM.liveActivityDeepLinkAction else { return false }
        appVM.liveActivityDeepLinkAction = nil
        appVM.recoverExpiredRunningSessionIfNeeded()

        if appVM.pendingExpiredRunningSession != nil {
            openExpiredAddTimeImmediately = action == .addTime
            HapticsService.selection()
            return true
        }

        guard let email = appVM.user?.email,
              let running = StorageService.load(
                RunningMivoSession.self,
                forKey: .runningSession,
                email: email
              ) else {
            selectedTab = 2
            return true
        }

        appVM.pendingResumedActiveSession = running
        HapticsService.selection()
        return true
    }

    private func cleanupSessionEndedNotificationsIfNeeded() {
        if appVM.pendingExpiredRunningSession != nil || appVM.pendingSessionFeedback != nil {
            SessionEndedNotificationCleaner.clearPendingAndDelivered()
        } else {
            SessionEndedNotificationCleaner.clearDelivered()
        }
    }

    @discardableResult
    private func routeToPendingInterventionIfNeeded() -> Bool {
        guard appVM.consumePendingInterventionSetup() else { return false }
        selectedTab = 2
        HapticsService.selection()
        return true
    }

    @discardableResult
    private func routeToDeepLinkedInterventionIfNeeded() -> Bool {
        guard appVM.deepLinkInterventionRequested else { return false }
        appVM.deepLinkInterventionRequested = false
        selectedTab = 2
        HapticsService.selection()
        return true
    }

    private func advanceTutorial() {
        guard tutorialStep < tutorialSteps.count else { return }
        let step = currentTutorialStep

        if step.requiresDemo, !completedTutorialDemos.contains(step.id) {
            performTutorialDemo()
            return
        }

        guard step.requiresScreenTimeAccess else {
            if tutorialStep >= tutorialSteps.count - 1 {
                finishTutorial()
                selectedTab = 0
            } else {
                tutorialStep += 1
            }
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
                    finishTutorial()
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

    private func retreatTutorial() {
        guard tutorialStep > 0 else { return }
        tutorialStep -= 1
        HapticsService.selection()
    }

    private func skipTutorial() {
        finishTutorial()
        selectedTab = 0
        tutorialMessage = nil
        HapticsService.selection()
    }

    private func performTutorialDemo() {
        let step = currentTutorialStep
        guard step.requiresDemo, !completedTutorialDemos.contains(step.id) else { return }
        withAnimation(.spring(response: 0.36, dampingFraction: 0.82)) {
            completedTutorialDemos.insert(step.id)
            tutorialMessage = step.demoCompletion
        }
        HapticsService.success()
    }

    private func finishTutorial() {
        UserDefaults.standard.set(currentTutorialVersion, forKey: tutorialVersionKey)
        appVM.completeTutorial()
    }

    private func routePendingAdminNotification() {
        guard let userID = UserDefaults.standard.string(forKey: "mivo.pendingAdminUserID") else { return }
        UserDefaults.standard.removeObject(forKey: "mivo.pendingAdminUserID")
        selectedTab = 3
        requestedAdminUser = AdminUserRoute(id: userID)
    }
}

private struct AdminUserRoute: Identifiable {
    let id: String
}

private struct AnnouncementPresentationView: View {
    let announcement: MivoAnnouncement
    let dismissAction: () -> Void

    var body: some View {
        ZStack {
            MivoColors.background.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Image(systemName: "megaphone.fill")
                        .font(.system(size: 19, weight: .bold))
                        .foregroundColor(MivoColors.white)
                        .frame(width: 44, height: 44)
                        .background(MivoColors.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Mivo announcement")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(MivoColors.accent)
                        Text(announcement.title)
                            .font(.system(size: 21, weight: .bold, design: .rounded))
                            .foregroundColor(MivoColors.textPrimary)
                    }
                }
                Text(announcement.body)
                    .font(.system(size: 15))
                    .foregroundColor(MivoColors.textSecondary)
                    .lineSpacing(5)
                Spacer()
                Button(action: dismissAction) {
                    Text("Got it")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(MivoColors.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(MivoColors.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }
            .padding(22)
        }
    }
}

private struct SessionEndedReviewView: View {
    @EnvironmentObject var appVM: AppViewModel
    @Environment(\.dismiss) private var dismiss

    let running: RunningMivoSession
    var startWithAddTime = false
    var onFinished: (() -> Void)? = nil

    @State private var showAddTimeSheet = false
    @State private var selectedExtraMinutes: Int = 10
    @State private var customMinutesText = ""
    @FocusState private var customFieldFocused: Bool
    @State private var showEmergencyUnlock = false
    @State private var emergencyUnlockReason = ""
    @State private var emergencyUnlockReviewMessage: String? = nil
    @State private var emergencyUnlockReviewing = false
    @State private var showReflection = false
    @State private var activationError: String? = nil
    @State private var autoFinishWorkItem: DispatchWorkItem? = nil

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
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(MivoColors.border.opacity(0.7), lineWidth: 1))
                    .padding(.horizontal, 22)

                    if let err = activationError {
                        Text(err)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(MivoColors.timerRed)
                            .lineSpacing(3)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(MivoColors.timerRed.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
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
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(MivoColors.accentLight, lineWidth: 1))
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
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                        .buttonStyle(.plain)

                        Button {
                            cancelAutoFinishIfForgotten()
                            showReflection = true
                        } label: {
                            Text("Save and finish session")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(MivoColors.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(MivoColors.accent)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
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
                sessionID: running.id,
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
                    cancelAutoFinishIfForgotten()
                    appVM.clearExpiredRunningSessionReview()
                    onFinished?()
                    dismiss()
                }
            )
            .interactiveDismissDisabled()
        }
        .onAppear {
            let opts = allowedTimeOptions
            if !opts.isEmpty { selectedExtraMinutes = opts.first! }
            if startWithAddTime, extensionDecision.allowed {
                showAddTimeSheet = true
            }
            scheduleAutoFinishIfForgotten()
        }
        .onDisappear {
            cancelAutoFinishIfForgotten()
        }
    }

    private func statRow(label: String, value: String, icon: String, color: Color) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(color)
                .frame(width: 32, height: 32)
                .background(color.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
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
                                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
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
                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
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
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
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
        cancelAutoFinishIfForgotten()
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
                Text("Write why this needs to happen now. Mivo will allow 5 more minutes only if the reason is specific and time-sensitive.")
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
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(MivoColors.border, lineWidth: 1))

                if let emergencyUnlockReviewMessage {
                    Text(emergencyUnlockReviewMessage)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(MivoColors.timerOrange)
                }

                Button { applyEmergencyUnlock() } label: {
                    Text(emergencyUnlockReviewing ? "Checking reason..." : "Unlock 5 minutes")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(MivoColors.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(canUseEmergencyUnlock ? MivoColors.accent : MivoColors.accentLight)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
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
        emergencyUnlockReason.trimmingCharacters(in: .whitespacesAndNewlines).count >= 3 && !emergencyUnlockReviewing
    }

    private func applyEmergencyUnlock() {
        let reason = emergencyUnlockReason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard reason.count >= 3 else { return }
        let sessions = appVM.sessions
        let profile = appVM.onboardingProfile
        emergencyUnlockReviewing = true
        emergencyUnlockReviewMessage = nil

        Task {
            let review = await AIService.verifyEmergencyUnlock(reason: reason, sessions: sessions, profile: profile)
            await MainActor.run {
                emergencyUnlockReviewing = false
                guard review.approved else {
                    emergencyUnlockReviewMessage = review.message
                    HapticsService.warning()
                    return
                }

                cancelAutoFinishIfForgotten()
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
    }

    private func scheduleAutoFinishIfForgotten() {
        cancelAutoFinishIfForgotten()
        let delay = appVM.secondsUntilAutoFinishExpiredSession(running)
        let workItem = DispatchWorkItem {
            if appVM.autoFinishExpiredRunningSessionIfForgotten(running, force: true) {
                onFinished?()
                dismiss()
            }
        }
        autoFinishWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func cancelAutoFinishIfForgotten() {
        autoFinishWorkItem?.cancel()
        autoFinishWorkItem = nil
    }
}

private struct DailyScrollScheduleCheckView: View {
    @EnvironmentObject var appVM: AppViewModel
    let prompt: DailyScrollSchedulePrompt

    @State private var windows: [ScreenScrollWindow]

    init(prompt: DailyScrollSchedulePrompt) {
        self.prompt = prompt
        let fallback = [
            ScreenScrollWindow(id: "daily-prompt-1", title: "Session 1", startHour: 14, endHour: 15, minutes: 15, reason: "Locked for today."),
            ScreenScrollWindow(id: "daily-prompt-2", title: "Session 2", startHour: 20, endHour: 21, minutes: 15, reason: "Locked for today.")
        ]
        _windows = State(initialValue: prompt.recommendedWindows.isEmpty ? fallback : prompt.recommendedWindows)
    }

    var body: some View {
        ZStack {
            MivoColors.background.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
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
                        Text(prompt.isRecommendationReady ? "Mivo recommends these windows from your last 3 days. Pick any start time, then today is locked." : "Choose any start time across the full day. Mivo sets the length and minutes; you choose when each window begins.")
                            .font(.system(size: 16, weight: .semibold))
                            .multilineTextAlignment(.center)
                            .foregroundColor(MivoColors.textSecondary)
                            .lineSpacing(3)
                            .padding(.horizontal, 14)
                    }

                    VStack(spacing: 12) {
                        ForEach(windows.indices, id: \.self) { index in
                            scheduleStepper(index: index)
                        }

                        MivoButton(label: "Lock today’s schedule", action: save, icon: "lock.fill")

                        Text("Choose any start time. You can set new times again tomorrow.")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(MivoColors.textMuted)
                            .multilineTextAlignment(.center)
                            .lineSpacing(2)
                    }
                    .padding(18)
                    .background(MivoColors.card)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(MivoColors.border.opacity(0.75), lineWidth: 1))
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 24)
            }
        }
    }

    private func scheduleStepper(index: Int) -> some View {
        let window = windows[index]
        let duration = max(1, window.endHour - window.startHour)
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Session \(index + 1)")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(MivoColors.textPrimary)
                Text("\(hourLabel(window.startHour))-\(hourLabel(window.endHour)) · \(window.minutes)m allowed · \(duration)h window")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(MivoColors.textMuted)
            }
            Spacer()
            Menu {
                ForEach(0...max(0, 24 - duration), id: \.self) { candidate in
                    Button {
                        setWindowStart(at: index, to: candidate)
                    } label: {
                        if candidate == window.startHour {
                            Label(hourLabel(candidate), systemImage: "checkmark")
                        } else {
                            Text(hourLabel(candidate))
                        }
                    }
                }
            } label: {
                HStack(spacing: 7) {
                    Text(hourLabel(window.startHour))
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 10, weight: .bold))
                }
                .foregroundColor(MivoColors.textPrimary)
                .padding(.horizontal, 12)
                .frame(height: 40)
                .background(MivoColors.background)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(MivoColors.surface.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func setWindowStart(at index: Int, to requestedStart: Int) {
        guard windows.indices.contains(index) else { return }
        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
            let window = windows[index]
            let duration = max(1, window.endHour - window.startHour)
            let maxStart = max(0, 24 - duration)
            let start = min(max(0, requestedStart), maxStart)
            windows[index] = ScreenScrollWindow(
                id: window.id,
                title: window.title,
                startHour: start,
                endHour: min(24, start + duration),
                minutes: window.minutes,
                reason: window.reason
            )
        }
        HapticsService.selection()
    }

    private func save() {
        appVM.saveDailyScrollScheduleForToday(windows)
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
            ScrollView(showsIndicators: false) {
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
                .padding(.top, 28)
                .padding(.bottom, 36)
            }
            .scrollDismissesKeyboard(.interactively)
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
                .background(MivoColors.surfaceRaised.opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
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
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(MivoColors.border.opacity(0.75), lineWidth: 1)
        )
    }

    private func revealedContent(guess: Int) -> some View {
        let check = appVM.truthChecks.last(where: { $0.date == prompt.date })
            ?? TruthCheckGuess(id: prompt.id, date: prompt.date, guess: guess, actual: prompt.actualMinutes)
        let summary = appVM.dailyTruthSummary(for: check)
        return VStack(spacing: 18) {
            HStack(spacing: 8) {
                truthStat(title: "You guessed", value: formatDuration(guess), tint: MivoColors.secondary)
                truthStat(title: "Actual", value: formatDuration(prompt.actualMinutes), tint: MivoColors.accent)
                truthStat(title: "Accuracy", value: "\(summary.accuracyScore)%", tint: MivoColors.blue)
            }

            forgottenTimeSection(summary)
            personalizedInsightSection(summary.insight)
            tomorrowExperimentSection(summary.insight.tomorrowExperiment)

            MivoButton(label: "Done", action: appVM.dismissTimeTruthPrompt, icon: "checkmark")
        }
    }

    private func forgottenTimeSection(_ summary: DailyTruthSummary) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Forgotten-time analysis", systemImage: "clock.arrow.circlepath")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(MivoColors.textPrimary)
                Spacer()
                Text(summary.forgottenMinutes > 0 ? formatDuration(summary.forgottenMinutes) : "No gap")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(MivoColors.accent)
            }

            if summary.forgottenMinutes > 0, !summary.forgottenBreakdown.isEmpty {
                Text("Estimated from each app’s share of the Screen Time total at reveal.")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(MivoColors.textMuted)
                ForEach(summary.forgottenBreakdown) { slice in
                    VStack(spacing: 5) {
                        HStack {
                            Text(slice.appName)
                            Spacer()
                            Text("~\(formatDuration(slice.minutes))")
                        }
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(MivoColors.textSecondary)
                        GeometryReader { proxy in
                            Capsule()
                                .fill(MivoColors.border.opacity(0.35))
                                .overlay(alignment: .leading) {
                                    Capsule()
                                        .fill(MivoColors.blue)
                                        .frame(width: max(8, proxy.size.width * CGFloat(slice.share)))
                                }
                        }
                        .frame(height: 6)
                    }
                }
            } else if summary.overestimatedMinutes > 0 {
                Text("You estimated \(formatDuration(summary.overestimatedMinutes)) more than Mivo measured. That still helps calibrate your internal clock.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(MivoColors.textSecondary)
                    .lineSpacing(3)
            } else {
                Text("Your estimate matched the measured total, so there is no missing-time gap to explain today.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(MivoColors.textSecondary)
                    .lineSpacing(3)
            }
        }
        .padding(16)
        .background(MivoColors.card)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(MivoColors.border.opacity(0.75), lineWidth: 1))
    }

    private func personalizedInsightSection(_ insight: PersonalizedPatternInsight) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Label("Personalized insight", systemImage: insight.icon)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(MivoColors.accent)
                .textCase(.uppercase)
            Text(insight.title)
                .font(.system(size: 19, weight: .bold, design: .rounded))
                .foregroundColor(MivoColors.textPrimary)
            Text(insight.detail)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(MivoColors.textSecondary)
                .lineSpacing(3)
            Text(insight.evidence)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(MivoColors.textMuted)
                .lineSpacing(3)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MivoColors.card)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(MivoColors.border.opacity(0.75), lineWidth: 1))
    }

    private func tomorrowExperimentSection(_ experiment: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "sunrise.fill")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(MivoColors.heroText)
                .frame(width: 36, height: 36)
                .background(MivoColors.accent)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 4) {
                Text("ONE SMALL EXPERIMENT FOR TOMORROW")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(MivoColors.accent)
                Text(experiment)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(MivoColors.textPrimary)
                    .lineSpacing(3)
            }
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
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
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    private func truthStat(title: String, value: String, tint: Color) -> some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(MivoColors.textMuted)
                .textCase(.uppercase)
                .lineLimit(2)
                .multilineTextAlignment(.center)
            Text(value)
                .font(.system(size: 21, weight: .bold, design: .rounded))
                .foregroundColor(tint)
                .minimumScaleFactor(0.75)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, minHeight: 88)
        .padding(.vertical, 15)
        .background(MivoColors.surfaceRaised.opacity(0.42))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
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
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

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
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(MivoColors.white.opacity(0.5), lineWidth: 1)
            )
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
    let eyebrow: String
    let title: String
    let body: String
    let shortBody: String
    let bullets: [String]
    let hint: String
    let targetLabel: String
    let focus: AppTutorialFocus
    let buttonTitle: String
    let requiresDemo: Bool
    let demoCompletion: String?
    let requiresScreenTimeAccess: Bool

    static let all: [AppTutorialStep] = [
        AppTutorialStep(
            id: 0, tab: 0, icon: "sparkles", eyebrow: "Home", title: "Today’s Guide",
            body: "Mivo now chooses one useful next action instead of asking you to scan the whole app.",
            shortBody: "Handle the one thing that matters now: a truth check, schedule, session, experiment, or recovery prompt.",
            bullets: ["One prioritized action", "Live progress", "Next scroll window"],
            hint: "This card changes as your day changes.", targetLabel: "Today’s next step", focus: .top,
            buttonTitle: "Continue", requiresDemo: false, demoCompletion: nil, requiresScreenTimeAccess: false
        ),
        AppTutorialStep(
            id: 1, tab: 1, icon: "eye.fill", eyebrow: "Truth Check", title: "Guess, reveal, understand",
            body: "Estimate first. Mivo then reveals actual usage, your accuracy, forgotten time, and one personal insight.",
            shortBody: "Try a sample reveal to see how Mivo turns a guess into a useful pattern.",
            bullets: ["Guess vs actual", "Forgotten-time analysis", "Personalized daily insight"],
            hint: "Tap the highlighted demo or use Try demo.", targetLabel: "Daily truth reveal", focus: .middle,
            buttonTitle: "Continue", requiresDemo: true, demoCompletion: "Your sample guess was revealed. Mivo would now explain the missing time and suggest one small action.", requiresScreenTimeAccess: false
        ),
        AppTutorialStep(
            id: 2, tab: 0, icon: "calendar.badge.clock", eyebrow: "Your Plan", title: "Adaptive scroll windows",
            body: "After three observation days, Mivo blends your estimate with all three daily totals and builds today’s schedule.",
            shortBody: "Your plan can use 2–4 windows and one- or two-hour periods based on your real pattern.",
            bullets: ["No plan before observation", "Adaptive window count", "Same limits everywhere"],
            hint: "You choose start times; Mivo calculates the structure.", targetLabel: "Personalized windows", focus: .upper,
            buttonTitle: "Continue", requiresDemo: false, demoCompletion: nil, requiresScreenTimeAccess: false
        ),
        AppTutorialStep(
            id: 3, tab: 2, icon: "hand.raised.fill", eyebrow: "Interventions", title: "Pause before opening",
            body: "Choose why you opened the app and how long you need. Repeated attempts receive gradually stronger friction.",
            shortBody: "Try selecting a reason. Mivo uses it to start intentionally and improve future insights.",
            bullets: ["5-second first pause", "10 seconds for repeated openings", "Reason check when a pattern repeats"],
            hint: "Tap the reason in the highlighted demo.", targetLabel: "Choose your reason", focus: .middle,
            buttonTitle: "Continue", requiresDemo: true, demoCompletion: "Reason selected. In the real flow, you would choose minutes and Mivo would unlock only for that session.", requiresScreenTimeAccess: false
        ),
        AppTutorialStep(
            id: 4, tab: 2, icon: "lifepreserver.fill", eyebrow: "Active Session", title: "Rescue without losing control",
            body: "During a long session, Rescue Mode lets you continue, add five minutes, exit, or remember why you opened the app.",
            shortBody: "Try the rescue moment. Timers also appear through Live Activities, and added time records only the extra minutes.",
            bullets: ["Gentle long-session interrupt", "Lock Screen Live Activity", "Accurate add-time tracking"],
            hint: "Tap the highlighted rescue choice.", targetLabel: "Rescue Mode", focus: .middle,
            buttonTitle: "Continue", requiresDemo: true, demoCompletion: "Exit chosen. Mivo would finish the elapsed time, relock selected apps, and return you Home.", requiresScreenTimeAccess: false
        ),
        AppTutorialStep(
            id: 5, tab: 2, icon: "moon.stars.fill", eyebrow: "Night", title: "Protect tomorrow’s sleep",
            body: "Late-night protection adds a longer pause, shows tomorrow’s wake time, and offers one final short scroll.",
            shortBody: "Nighttime prompts stay calm while making the sleep tradeoff clear.",
            bullets: ["Longer nighttime pause", "Wake-time reminder", "One last-scroll option"],
            hint: "Set your night and wake hours in Settings.", targetLabel: "Late-night protection", focus: .upper,
            buttonTitle: "Continue", requiresDemo: false, demoCompletion: nil, requiresScreenTimeAccess: false
        ),
        AppTutorialStep(
            id: 6, tab: 1, icon: "chart.xyaxis.line", eyebrow: "Patterns", title: "See what keeps repeating",
            body: "Patterns combines charts, the calendar, session reflections, truth accuracy, experiments, and reports.",
            shortBody: "Weekly Truth and monthly Mivo Effect reports show change only after enough real data exists.",
            bullets: ["Personalized pattern insights", "Weekly and monthly reports", "Experiment before-and-after charts"],
            hint: "Tap a calendar day to inspect the sessions behind it.", targetLabel: "Pattern dashboard", focus: .upper,
            buttonTitle: "Continue", requiresDemo: false, demoCompletion: nil, requiresScreenTimeAccess: false
        ),
        AppTutorialStep(
            id: 7, tab: 0, icon: "flask.fill", eyebrow: "Experiment", title: "Try one change for seven days",
            body: "Mivo proposes one measurable rule. Nothing changes until you review and approve it.",
            shortBody: "Try approving the sample to see how an experiment begins and tracks Day 1 through Day 7.",
            bullets: ["You approve every rule", "One experiment at a time", "Keep, Adjust, or Stop"],
            hint: "Tap the highlighted approval button.", targetLabel: "7-day experiment", focus: .middle,
            buttonTitle: "Continue", requiresDemo: true, demoCompletion: "Sample experiment approved. Home would now show Day 1 of 7 and measure the agreed rule without changing it.", requiresScreenTimeAccess: false
        ),
        AppTutorialStep(
            id: 8, tab: 0, icon: "person.2.fill", eyebrow: "Referral", title: "Invite and track privately",
            body: "Your Referral Hub holds your code, link, milestones, private rank, campaign rules, and qualified referrals.",
            shortBody: "Copy or share your code and see first-name-only progress when a campaign is active.",
            bullets: ["Unique code and link", "Qualified and pending counts", "Rules and milestones"],
            hint: "Campaign controls stay hidden until the founder publishes them.", targetLabel: "Referral Hub", focus: .lower,
            buttonTitle: "Continue", requiresDemo: false, demoCompletion: nil, requiresScreenTimeAccess: false
        ),
        AppTutorialStep(
            id: 9, tab: 3, icon: "slider.horizontal.3", eyebrow: "Personalize", title: "Recovery and app personalities",
            body: "Recovery Mode simplifies a difficult day, while app personalities adjust pauses, rescue timing, and extensions per app.",
            shortBody: "Your locked schedule remains the strongest rule; these tools tune the support around it.",
            bullets: ["Gentler recovery days", "Different friction per app", "Experiment Library"],
            hint: "Find these controls under Mivo Tools.", targetLabel: "Personal controls", focus: .upper,
            buttonTitle: "Continue", requiresDemo: false, demoCompletion: nil, requiresScreenTimeAccess: false
        ),
        AppTutorialStep(
            id: 10, tab: 3, icon: "hand.raised.square.fill", eyebrow: "Privacy", title: "You control what leaves Mivo",
            body: "Privacy Center explains synced and device-only data. Accountability summaries are previewed before sharing and can be revoked.",
            shortBody: "Manage permissions, diagnostics, exports, deletion, and trusted weekly summaries in one place.",
            bullets: ["Private summary preview", "14-day revocable links", "Export and deletion controls"],
            hint: "Accountability never shares app names, triggers, notes, or exact times.", targetLabel: "Privacy and sharing", focus: .lower,
            buttonTitle: "Continue", requiresDemo: false, demoCompletion: nil, requiresScreenTimeAccess: false
        ),
        AppTutorialStep(
            id: 15, tab: 0, icon: "sparkles.rectangle.stack.fill", eyebrow: "Mivo Clear BETA", title: "Use social tools without the feed",
            body: "Map Instagram, TikTok, or YouTube once. The native app stays protected while Mivo Clear BETA keeps useful actions available.",
            shortBody: "Try the sample mapping, then choose a focused shortcut instead of opening an endless short-form feed.",
            bullets: ["Messages, profile, and posting", "A shared reel returns you to the chat", "Device-only app mappings"],
            hint: "Tap the demo to map Instagram and open Messages.", targetLabel: "Mivo Clear BETA setup", focus: .middle,
            buttonTitle: "Continue", requiresDemo: true, demoCompletion: "Instagram mapped. The shield would now offer Mivo Clear BETA, and Messages would open as the focused destination.", requiresScreenTimeAccess: false
        ),
        AppTutorialStep(
            id: 11, tab: 3, icon: "waveform.path.ecg", eyebrow: "Final Step", title: "Connect Screen Time",
            body: "Screen Time access lets Mivo measure real usage, run the observation, protect selected apps, and enforce your schedule.",
            shortBody: "Allow access once so the core Mivo experience can work accurately.",
            bullets: ["Real usage", "App shields", "Accurate plans and insights"],
            hint: "Apple keeps app selection private to this device.", targetLabel: "Screen Time access", focus: .middle,
            buttonTitle: "Allow Screen Time", requiresDemo: false, demoCompletion: nil, requiresScreenTimeAccess: true
        )
    ]

    static func steps(for role: String) -> [AppTutorialStep] {
        guard let permissionStep = all.last else { return all }
        var result = Array(all.dropLast())
        switch role {
        case "super_admin":
            result.append(roleStep(
                id: 12, icon: "rectangle.3.group.fill", eyebrow: "Founder",
                title: "Run Mivo from your iPhone",
                shortBody: "Admin Center brings reliability, releases, data quality, analytics, approvals, users, referrals, and security together.",
                bullets: ["Feature flags and kill switches", "User and campaign tools", "Audited approvals"]
            ))
        case "admin":
            result.append(roleStep(
                id: 13, icon: "bell.badge.fill", eyebrow: "Admin",
                title: "Prepare announcement drafts",
                shortBody: "Create and edit your own announcement drafts. The founder reviews and publishes them before users see anything.",
                bullets: ["Draft only", "Founder approval", "No user-data access"]
            ))
        case "ambassador":
            result.append(roleStep(
                id: 14, icon: "person.2.badge.gearshape.fill", eyebrow: "Ambassador",
                title: "Your ambassador dashboard",
                shortBody: "See only people who entered one of your assigned ambassador names, with limited onboarding and referral status.",
                bullets: ["Attributed users only", "No emails", "No behavior history"]
            ))
        default:
            break
        }
        result.append(permissionStep)
        return result
    }

    private static func roleStep(
        id: Int,
        icon: String,
        eyebrow: String,
        title: String,
        shortBody: String,
        bullets: [String]
    ) -> AppTutorialStep {
        AppTutorialStep(
            id: id, tab: 3, icon: icon, eyebrow: eyebrow, title: title,
            body: shortBody, shortBody: shortBody, bullets: bullets,
            hint: "This section appears only when your account has this role.",
            targetLabel: "Role tools", focus: .upper, buttonTitle: "Continue",
            requiresDemo: false, demoCompletion: nil, requiresScreenTimeAccess: false
        )
    }
}

private enum AppTutorialFocus: Equatable {
    case top
    case upper
    case middle
    case lower
    case action
    case tabBar

    func targetFrame(in size: CGSize) -> CGRect {
        let inset: CGFloat = 22
        let width = max(230, min(size.width - inset * 2, preferredWidth))
        let x = (size.width - width) / 2
        let height = targetHeight

        switch self {
        case .top:
            return CGRect(x: x, y: 104, width: width, height: height)
        case .upper:
            return CGRect(x: x, y: 176, width: width, height: height)
        case .middle:
            return CGRect(x: x, y: max(218, size.height * 0.38), width: width, height: height)
        case .lower:
            return CGRect(x: x, y: max(330, size.height * 0.56), width: width, height: height)
        case .action:
            return CGRect(x: x, y: max(390, size.height * 0.66), width: width, height: height)
        case .tabBar:
            return CGRect(x: max(16, x), y: max(90, size.height - 98), width: min(width, size.width - 32), height: height)
        }
    }

    func coachmarkCenter(in size: CGSize) -> CGPoint {
        let target = targetFrame(in: size)
        let estimatedHeight: CGFloat = 214
        let gap: CGFloat = 18
        let y: CGFloat

        if target.midY < size.height * 0.46 {
            y = min(size.height - estimatedHeight / 2 - 24, target.maxY + estimatedHeight / 2 + gap)
        } else {
            y = max(estimatedHeight / 2 + 26, target.minY - estimatedHeight / 2 - gap)
        }

        return CGPoint(x: size.width / 2, y: y)
    }

    private var preferredWidth: CGFloat {
        switch self {
        case .action:
            return 330
        case .tabBar:
            return 360
        default:
            return 340
        }
    }

    private var targetHeight: CGFloat {
        switch self {
        case .top:
            return 92
        case .upper, .middle, .lower:
            return 144
        case .action:
            return 78
        case .tabBar:
            return 58
        }
    }
}

private struct AppTutorialOverlay: View {
    let step: AppTutorialStep
    let stepIndex: Int
    let totalSteps: Int
    let isRequestingScreenTime: Bool
    let message: String?
    let demoCompleted: Bool
    let demoAction: () -> Void
    let backAction: (() -> Void)?
    let skipAction: () -> Void
    let nextAction: () -> Void

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let targetFrame = step.focus.targetFrame(in: size)
            let coachmarkCenter = step.focus.coachmarkCenter(in: size)
            let coachmarkWidth = min(max(size.width - 32, 240), 342)

            ZStack {
                MivoColors.primary.opacity(0.14)
                    .ignoresSafeArea()

                AppTutorialTarget(step: step, demoCompleted: demoCompleted)
                    .frame(width: targetFrame.width, height: targetFrame.height)
                    .position(x: targetFrame.midX, y: targetFrame.midY)
                    .contentShape(Rectangle())
                    .onTapGesture { demoAction() }
                    .accessibilityAddTraits(step.requiresDemo ? .isButton : [])
                    .accessibilityHint(step.requiresDemo ? "Runs the sample interaction" : "")

                AppTutorialCoachmark(
                    step: step,
                    stepIndex: stepIndex,
                    totalSteps: totalSteps,
                    isRequestingScreenTime: isRequestingScreenTime,
                    message: message,
                    demoCompleted: demoCompleted,
                    backAction: backAction,
                    skipAction: skipAction,
                    nextAction: nextAction
                )
                .frame(width: coachmarkWidth)
                .position(coachmarkCenter)
            }
            .animation(.spring(response: 0.42, dampingFraction: 0.84), value: step.id)
        }
        .ignoresSafeArea()
    }
}

private struct AppTutorialTarget: View {
    let step: AppTutorialStep
    let demoCompleted: Bool

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.85)) { context in
            let beat = Int(context.date.timeIntervalSinceReferenceDate / 0.85) % 2 == 0
            ZStack(alignment: .leading) {
                // A slow breathing halo keeps the eye on the highlighted card
                // while the viewer reads the coachmark.
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(MivoColors.accent.opacity(beat ? 0 : 0.5), lineWidth: 3)
                    .scaleEffect(beat ? 1.06 : 1)

                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(MivoColors.card.opacity(0.92))
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(MivoColors.accent.opacity(0.62), style: StrokeStyle(lineWidth: 1.5, dash: [7, 6]))
                    )

                if step.focus == .tabBar {
                    tabBarPreview
                } else {
                    demoPreview
                }
            }
            .padding(2)
            .overlay(alignment: .topTrailing) {
                if step.requiresDemo {
                    Image(systemName: demoCompleted ? "checkmark.circle.fill" : "hand.tap.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(demoCompleted ? MivoColors.blue : MivoColors.accent)
                        .scaleEffect(!demoCompleted && beat ? 1.18 : 1)
                        .padding(10)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.85), value: beat)
        }
    }

    @ViewBuilder
    private var demoPreview: some View {
        switch step.id {
        case 0:
            todayPreview
        case 1:
            truthCheckPreview
        case 2:
            planWindowPreview
        case 3:
            reasonPickerPreview
        case 4:
            rescueModePreview
        case 5:
            lateNightPreview
        case 6:
            patternDashboardPreview
        case 7:
            experimentPreview
        case 8:
            referralPreview
        case 9:
            personalControlsPreview
        case 10:
            privacySharingPreview
        case 15:
            mivoClearPreview
        case 11:
            screenTimePreview
        case 12, 13, 14:
            roleToolsPreview
        default:
            cardPreview
        }
    }

    private var cardPreview: some View {
        HStack(spacing: 12) {
            iconBadge

            VStack(alignment: .leading, spacing: 6) {
                Text(step.targetLabel)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(MivoColors.textPrimary)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    ForEach(0..<3, id: \.self) { index in
                        Capsule()
                            .fill(index == 0 ? MivoColors.accent.opacity(0.42) : MivoColors.background.opacity(0.9))
                            .frame(width: index == 0 ? 48 : 34, height: 7)
                    }
                }

                Text("Look here")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(MivoColors.textMuted)
                    .textCase(.uppercase)
            }

            Spacer()

            Image(systemName: "scope")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(MivoColors.accent.opacity(0.75))
        }
        .padding(.horizontal, 16)
    }

    private var todayPreview: some View {
        demoStack {
            demoHeader("Today’s Guide", subtitle: "One useful next action")
            demoRow("Truth check", value: "Ready", selected: true)
            miniProgress(title: "Today’s plan is ready", progress: 0.52)
        }
    }

    private var mivoClearPreview: some View {
        demoStack {
            demoHeader("Mivo Clear BETA", subtitle: demoCompleted ? "Instagram mapped" : "Choose one native app")
            demoRow("Instagram", value: demoCompleted ? "Mapped" : "Map", selected: true)
            HStack(spacing: 7) {
                miniPill("Messages", selected: demoCompleted)
                miniPill("Following", selected: false)
                miniPill("Post", selected: false)
            }
        }
    }

    private var sessionReviewPreview: some View {
        demoStack {
            demoHeader("Time's up", subtitle: "Finish the session")
            HStack(spacing: 8) {
                miniPill("Used 12m", selected: false)
                miniPill("Save", selected: true)
                tapCue("tap")
            }
        }
    }

    private var planWindowPreview: some View {
        demoStack {
            demoHeader("Plan ready after observation", subtitle: "2 scroll windows")
            HStack(spacing: 8) {
                miniWindow("12 PM", "15m")
                miniWindow("7 PM", "20m")
            }
        }
    }

    private var patternCalendarPreview: some View {
        demoStack {
            demoHeader("This week", subtitle: "Sessions saved by day")
            HStack(spacing: 7) {
                ForEach(Array(["M", "T", "W", "T", "F"].enumerated()), id: \.offset) { _, day in
                    VStack(spacing: 5) {
                        Text(day)
                            .font(.system(size: 9, weight: .black))
                            .foregroundColor(MivoColors.textMuted)
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(day == "W" ? MivoColors.accent.opacity(0.42) : MivoColors.background.opacity(0.9))
                            .frame(height: day == "W" ? 44 : 28)
                    }
                    .frame(maxWidth: .infinity, alignment: .bottom)
                }
            }
        }
    }

    private var weeklyReportPreview: some View {
        demoStack {
            demoHeader("Weekly report", subtitle: "What changed")
            HStack(spacing: 8) {
                miniStat("Recovered", "1h 10m")
                miniStat("Trigger", "Bored")
            }
        }
    }

    private var truthCheckPreview: some View {
        demoStack {
            demoHeader("Truth check", subtitle: demoCompleted ? "Here is what the gap means" : "Guess, then reveal")
            HStack(spacing: 8) {
                miniStat("You guessed", "45m")
                miniStat(demoCompleted ? "Actual" : "Tap reveal", demoCompleted ? "1h 18m" : "?", selected: true)
            }
            if demoCompleted {
                demoRow("Forgotten time", value: "33m", selected: true)
            } else {
                tapCue("Reveal truth")
            }
        }
    }

    private var startSessionPreview: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                miniPill("Break", selected: true)
                miniPill("10m", selected: true)
                Spacer()
                tapCue("press")
            }
            HStack(spacing: 10) {
                iconBadge
                Text("Start 10 min session")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(MivoColors.heroText)
                    .lineLimit(1)
                Spacer()
                Image(systemName: "arrow.right")
                    .font(.system(size: 15, weight: .black))
                    .foregroundColor(MivoColors.heroText)
            }
            .padding(.horizontal, 14)
            .frame(height: 44)
            .background(MivoColors.accent)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .padding(10)
    }

    private var reasonPickerPreview: some View {
        demoStack {
            demoHeader("Why are you opening it?", subtitle: demoCompleted ? "Reason saved" : "Pick before unlock")
            HStack(spacing: 8) {
                miniPill("Bored", selected: demoCompleted)
                miniPill("Message", selected: false)
                miniPill("Relax", selected: false)
            }
            if demoCompleted { miniProgress(title: "Next: choose minutes", progress: 0.5) }
            else { tapCue("choose") }
        }
    }

    private var rescueModePreview: some View {
        demoStack {
            demoHeader("27 minutes", subtitle: demoCompleted ? "Session ended and apps relocked" : "Still choosing this?")
            HStack(spacing: 7) {
                miniPill("Continue", selected: false)
                miniPill("+5m", selected: false)
                miniPill("Exit now", selected: demoCompleted)
            }
            if demoCompleted { demoRow("Saved", value: "27m", selected: true) }
            else { tapCue("Exit now") }
        }
    }

    private var lateNightPreview: some View {
        demoStack {
            demoHeader("Late-night protection", subtitle: "Wake-up tomorrow at 7:00 AM")
            Text("Scrolling now borrows from sleep. Are you still choosing it?")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(MivoColors.textSecondary)
                .lineLimit(2)
            HStack(spacing: 8) {
                miniPill("Last 10m", selected: true)
                miniPill("Exit", selected: false)
            }
        }
    }

    private var patternDashboardPreview: some View {
        demoStack {
            demoHeader("Patterns", subtitle: "Truth, sessions, and experiments")
            HStack(spacing: 7) {
                miniStat("Accuracy", "82%", selected: true)
                miniStat("Worth it", "67%")
                miniStat("Extensions", "2")
            }
            miniProgress(title: "Monthly estimated improvement", progress: 0.64)
        }
    }

    private var experimentPreview: some View {
        demoStack {
            demoHeader(demoCompleted ? "Day 1 of 7" : "Protect one difficult hour", subtitle: demoCompleted ? "Experiment active" : "Review before anything changes")
            demoRow("Rule", value: "9–10 PM", selected: true)
            if demoCompleted { miniProgress(title: "Seven-day progress", progress: 1.0 / 7.0) }
            else { tapCue("Approve for 7 days") }
        }
    }

    private var referralPreview: some View {
        demoStack {
            demoHeader("Your referral code", subtitle: "MIVO-7K2Q")
            HStack(spacing: 7) {
                miniStat("Qualified", "3", selected: true)
                miniStat("Pending", "1")
                miniStat("Rank", "#4")
            }
            HStack(spacing: 8) {
                miniPill("Copy", selected: false)
                miniPill("Share", selected: true)
                miniPill("Rules", selected: false)
            }
        }
    }

    private var personalControlsPreview: some View {
        demoStack {
            demoHeader("Mivo Tools", subtitle: "Tune support without weakening locks")
            demoRow("Recovery Mode", value: "Available", selected: true)
            demoRow("App personalities", value: "Balanced", selected: false)
            demoRow("Experiment Library", value: "3 ideas", selected: false)
        }
    }

    private var privacySharingPreview: some View {
        demoStack {
            demoHeader("Privacy Center", subtitle: "See and control your data")
            demoRow("Accountability preview", value: "Private", selected: true)
            demoRow("Diagnostics", value: "Manage", selected: false)
            HStack(spacing: 8) {
                miniPill("Export", selected: false)
                miniPill("Revoke link", selected: true)
            }
        }
    }

    @ViewBuilder
    private var roleToolsPreview: some View {
        demoStack {
            if step.id == 12 {
                demoHeader("Admin Center", subtitle: "Founder-only controls")
                demoRow("Reliability", value: "Healthy", selected: true)
                demoRow("Approvals", value: "3 waiting", selected: false)
                demoRow("Feature flags", value: "Manage", selected: false)
            } else if step.id == 13 {
                demoHeader("Announcement drafts", subtitle: "Founder approval required")
                demoRow("New draft", value: "Edit", selected: true)
                demoRow("Publishing", value: "Founder only", selected: false)
            } else {
                demoHeader("Ambassador", subtitle: "Assigned names only")
                HStack(spacing: 8) {
                    miniStat("Attributed", "8", selected: true)
                    miniStat("Complete", "6")
                    miniStat("Pending", "2")
                }
            }
        }
    }

    private var appRulesPreview: some View {
        demoStack {
            demoHeader("App rules", subtitle: "Different apps, different limits")
            demoRow("Instagram", value: "Pause + limit", selected: true)
            demoRow("TikTok", value: "Planned windows", selected: false)
        }
    }

    private var addTimePreview: some View {
        demoStack {
            demoHeader("Add more time", subtitle: "Only starts the extra minutes")
            HStack(spacing: 8) {
                miniPill("+5", selected: false)
                miniPill("+10", selected: true)
                miniPill("+15", selected: false)
                tapCue("tap")
            }
            miniProgress(title: "New timer: 10m", progress: 0.12)
        }
    }

    private var emergencyUnlockPreview: some View {
        demoStack {
            demoHeader("Emergency unlock", subtitle: "Reason gets checked")
            HStack(spacing: 7) {
                Image(systemName: "quote.opening")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(MivoColors.textMuted)
                Text("Need code from text now")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(MivoColors.textPrimary)
                    .lineLimit(1)
                Spacer()
            }
            HStack(spacing: 7) {
                miniPill("AI checking", selected: true)
                miniPill("5m unlock", selected: false)
            }
        }
    }

    private var settingsListPreview: some View {
        demoStack {
            demoHeader("Settings", subtitle: "Account and app controls")
            demoRow("Screen Time", value: "Connected", selected: true)
            demoRow("Reset data", value: "Manage", selected: false)
        }
    }

    private var notificationsPreview: some View {
        demoStack {
            demoHeader("Notifications", subtitle: "Session ended reminders")
            demoRow("Open Mivo", value: "On", selected: true)
            demoRow("Weekly report", value: "On", selected: false)
        }
    }

    private var dataControlsPreview: some View {
        demoStack {
            demoHeader("Data sync", subtitle: "Saved to your Mivo account")
            HStack(spacing: 8) {
                miniPill("Sessions", selected: true)
                miniPill("Plans", selected: false)
                miniPill("Reports", selected: false)
            }
        }
    }

    private var screenTimePreview: some View {
        demoStack {
            demoHeader("Screen Time access", subtitle: "Required for blocking")
            HStack(spacing: 8) {
                miniPill("Usage", selected: true)
                miniPill("Shields", selected: true)
                tapCue("Allow")
            }
        }
    }

    private var actionPreview: some View {
        HStack(spacing: 10) {
            iconBadge

            Text(step.targetLabel)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundColor(MivoColors.heroText)
                .lineLimit(1)

            Spacer()

            Image(systemName: "arrow.right")
                .font(.system(size: 16, weight: .black))
                .foregroundColor(MivoColors.heroText)
        }
        .padding(.horizontal, 17)
        .background(MivoColors.accent)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius - 2, style: .continuous))
        .padding(7)
    }

    private var tabBarPreview: some View {
        HStack(spacing: 8) {
            ForEach(["Home", "Patterns", "Interventions", "Settings"], id: \.self) { title in
                VStack(spacing: 4) {
                    Image(systemName: iconName(for: title))
                        .font(.system(size: 14, weight: .bold))
                    Text(title)
                        .font(.system(size: 9, weight: .bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .foregroundColor(title == step.eyebrow ? MivoColors.accent : MivoColors.textSecondary)
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 12)
    }

    private var iconBadge: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(MivoColors.accent.opacity(0.1))
            Image(systemName: step.icon)
                .font(.system(size: 17, weight: .bold))
                .foregroundColor(MivoColors.accent.opacity(0.9))
        }
        .frame(width: 42, height: 42)
    }

    private var cornerRadius: CGFloat {
        switch step.focus {
        case .action:
            return 20
        case .tabBar:
            return 28
        default:
            return 24
        }
    }

    private func demoStack<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            content()
        }
        .padding(13)
    }

    private func demoHeader(_ title: String, subtitle: String) -> some View {
        HStack(spacing: 10) {
            iconBadge
                .frame(width: 34, height: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(MivoColors.textPrimary)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(MivoColors.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }

    private func miniPill(_ text: String, selected: Bool) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .black))
            .foregroundColor(selected ? MivoColors.heroText : MivoColors.textSecondary)
            .padding(.horizontal, 9)
            .frame(height: 26)
            .background(selected ? MivoColors.accent.opacity(0.86) : MivoColors.background.opacity(0.86))
            .clipShape(Capsule())
    }

    private func tapCue(_ text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "hand.tap.fill")
                .font(.system(size: 10, weight: .bold))
            Text(text)
                .font(.system(size: 10, weight: .black))
        }
        .foregroundColor(MivoColors.accent)
        .padding(.horizontal, 8)
        .frame(height: 24)
        .background(MivoColors.accent.opacity(0.1))
        .clipShape(Capsule())
    }

    private func miniWindow(_ time: String, _ minutes: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(time)
                .font(.system(size: 10, weight: .black))
                .foregroundColor(MivoColors.textPrimary)
            Text(minutes)
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(MivoColors.textSecondary)
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MivoColors.background.opacity(0.82))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func miniStat(_ title: String, _ value: String, selected: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 9, weight: .black))
                .foregroundColor(selected ? MivoColors.accent : MivoColors.textMuted)
            Text(value)
                .font(.system(size: 13, weight: .black, design: .rounded))
                .foregroundColor(MivoColors.textPrimary)
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(selected ? MivoColors.accent.opacity(0.1) : MivoColors.background.opacity(0.82))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func demoRow(_ title: String, value: String, selected: Bool) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(selected ? MivoColors.accent.opacity(0.75) : MivoColors.muted.opacity(0.42))
                .frame(width: 8, height: 8)
            Text(title)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(MivoColors.textPrimary)
                .lineLimit(1)
            Spacer()
            Text(value)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(MivoColors.textSecondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(MivoColors.background.opacity(0.74))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func miniProgress(title: String, progress: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(MivoColors.textSecondary)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(MivoColors.background.opacity(0.9))
                    Capsule()
                        .fill(MivoColors.accent.opacity(0.46))
                        .frame(width: max(8, proxy.size.width * progress))
                }
            }
            .frame(height: 7)
        }
    }

    private func iconName(for title: String) -> String {
        switch title {
        case "Home":
            return "house.fill"
        case "Patterns":
            return "calendar"
        case "Interventions":
            return "timer"
        default:
            return "gearshape.fill"
        }
    }
}

private struct AppTutorialCoachmark: View {
    let step: AppTutorialStep
    let stepIndex: Int
    let totalSteps: Int
    let isRequestingScreenTime: Bool
    let message: String?
    let demoCompleted: Bool
    let backAction: (() -> Void)?
    let skipAction: () -> Void
    let nextAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 8) {
                Text(step.eyebrow.uppercased())
                    .font(.system(size: 10, weight: .black))
                    .foregroundColor(MivoColors.accent.opacity(0.86))

                Text("\(stepIndex + 1)/\(totalSteps)")
                    .font(.system(size: 11, weight: .bold).monospacedDigit())
                    .foregroundColor(MivoColors.textSecondary)

                Spacer()

                Button("Skip", action: skipAction)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(MivoColors.textSecondary)
                    .buttonStyle(.plain)
            }

            HStack(alignment: .top, spacing: 10) {
                Image(systemName: step.icon)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(MivoColors.heroText)
                    .frame(width: 34, height: 34)
                    .background(MivoColors.accent.opacity(0.9))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .symbolEffect(.bounce, value: step.id)

                VStack(alignment: .leading, spacing: 4) {
                    Text(step.title)
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundColor(MivoColors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(step.shortBody)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(MivoColors.textSecondary)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .id(step.id)
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .opacity
                ))
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.82), value: step.id)

            HStack(spacing: 7) {
                Image(systemName: "scope")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(MivoColors.accent.opacity(0.82))

                Text(step.hint)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(MivoColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(MivoColors.background.opacity(0.72))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            if let message {
                Text(message)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(demoCompleted ? MivoColors.blue : MivoColors.timerRed)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 5) {
                ForEach(0..<totalSteps, id: \.self) { index in
                    Capsule()
                        .fill(index <= stepIndex ? MivoColors.accent : MivoColors.muted.opacity(0.38))
                        .frame(width: index == stepIndex ? 18 : 5, height: 5)
                }
            }
            .frame(maxWidth: .infinity)

            HStack(spacing: 10) {
                Button {
                    backAction?()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 13, weight: .black))
                        .foregroundColor(MivoColors.textPrimary)
                        .frame(width: 38, height: 38)
                        .background(MivoColors.background.opacity(backAction == nil ? 0.28 : 0.78))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(backAction == nil || isRequestingScreenTime)
                .opacity(backAction == nil ? 0.45 : 1)

                Spacer()

                Button(action: nextAction) {
                    HStack(spacing: 7) {
                        if isRequestingScreenTime {
                            ProgressView()
                                .tint(MivoColors.heroText)
                                .scaleEffect(0.76)
                        } else {
                            Text(step.requiresDemo && !demoCompleted ? "Try demo" : step.buttonTitle)
                            Image(systemName: step.requiresDemo && !demoCompleted
                                  ? "hand.tap.fill"
                                  : (step.requiresScreenTimeAccess ? "checkmark.shield.fill" : "arrow.right"))
                        }
                    }
                    .font(.system(size: 13, weight: .black))
                    .foregroundColor(MivoColors.heroText)
                    .padding(.horizontal, 15)
                    .frame(height: 38)
                    .background(MivoColors.primary)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(isRequestingScreenTime)
            }
        }
        .padding(14)
        .background(MivoColors.card.opacity(0.96))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(MivoColors.white.opacity(0.62), lineWidth: 1)
        )
    }
}

private struct AppTutorialToolbar: View {
    let step: AppTutorialStep
    let stepIndex: Int
    let totalSteps: Int
    let isRequestingScreenTime: Bool
    let message: String?
    let backAction: (() -> Void)?
    let skipAction: () -> Void
    let nextAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Text(step.eyebrow.uppercased())
                    .font(.system(size: 11, weight: .black))
                    .foregroundColor(MivoColors.accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(MivoColors.accent.opacity(0.12))
                    .clipShape(Capsule())

                Text("\(stepIndex + 1) / \(totalSteps)")
                    .font(.system(size: 12, weight: .bold).monospacedDigit())
                    .foregroundColor(MivoColors.textSecondary)

                Spacer()

                Button("Skip") {
                    skipAction()
                }
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(MivoColors.textSecondary)
                .buttonStyle(.plain)
            }

            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [MivoColors.accent, MivoColors.primary],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    Image(systemName: step.icon)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(MivoColors.heroText)
                }
                .frame(width: 48, height: 48)

                VStack(alignment: .leading, spacing: 6) {
                    Text(step.title)
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundColor(MivoColors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(step.body)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(MivoColors.textPrimary)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            VStack(alignment: .leading, spacing: 9) {
                ForEach(step.bullets, id: \.self) { item in
                    HStack(alignment: .top, spacing: 9) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(MivoColors.accent)
                            .padding(.top, 2)
                        Text(item)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(MivoColors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(13)
            .background(MivoColors.surfaceRaised.opacity(0.46))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            HStack(alignment: .top, spacing: 9) {
                Image(systemName: "scope")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(MivoColors.accent)
                    .padding(.top, 2)
                Text(step.hint)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(MivoColors.textSecondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let message {
                Text(message)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(MivoColors.timerRed)
            }

            HStack(spacing: 8) {
                ForEach(0..<totalSteps, id: \.self) { index in
                    Capsule()
                        .fill(index <= stepIndex ? MivoColors.accent : MivoColors.muted.opacity(0.38))
                        .frame(width: index == stepIndex ? 22 : 7, height: 7)
                        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: stepIndex)
                }
            }
            .frame(maxWidth: .infinity)

            HStack(spacing: 12) {
                Button {
                    backAction?()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(MivoColors.textPrimary)
                        .frame(width: 44, height: 44)
                        .background(MivoColors.surfaceRaised.opacity(backAction == nil ? 0.22 : 0.64))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(backAction == nil || isRequestingScreenTime)
                .opacity(backAction == nil ? 0.45 : 1)

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
                    .padding(.horizontal, 18)
                    .frame(height: 44)
                    .background(MivoColors.primary)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(isRequestingScreenTime)
            }
        }
        .padding(18)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(MivoColors.white.opacity(0.5), lineWidth: 1)
        )
    }
}

// MARK: - Goal forecast prompt
//
// One-time post-observation prompt that tells the user how their personalized
// plan will get them from their blended baseline to their daily
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

                        Text("Based on your self-report and 3 days of real usage, here is how Mivo will get you to your goal.")
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
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
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
                bigStat(label: "Baseline", value: format(prompt.observationAverageMinutes))
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
        .background(MivoColors.surfaceRaised.opacity(0.62))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(MivoColors.white.opacity(0.58), lineWidth: 1))
    }

    private var timelineCard: some View {
        VStack(spacing: 10) {
            timelineRow(day: "Day 1", value: format(prompt.firstPlanDayTarget), color: MivoColors.accent)
            timelineRow(day: "Day 8", value: format(prompt.oneWeekTarget), color: MivoColors.accent)
            timelineRow(day: "Day 15", value: format(prompt.twoWeekTarget), color: MivoColors.accent)
            timelineRow(day: "Day \(prompt.daysToReachGoal)", value: format(prompt.goalMinutes), color: MivoColors.timerGreen, highlight: true)
        }
        .padding(16)
        .background(MivoColors.surfaceRaised.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(MivoColors.white.opacity(0.58), lineWidth: 1))
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
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
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
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func format(_ minutes: Int) -> String {
        if minutes < 60 { return "\(minutes)m" }
        let h = minutes / 60
        let m = minutes % 60
        return m == 0 ? "\(h)h" : "\(h)h \(m)m"
    }
}
