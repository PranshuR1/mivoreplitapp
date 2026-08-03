import SwiftUI

private let durations: [(label: String, value: Int)] = [
    ("5 min", 5), ("10 min", 10), ("15 min", 15), ("20 min", 20), ("30 min", 30)
]

private struct ActiveSessionLaunch: Identifiable {
    let id = UUID()
    let intention: Intention
    let duration: Int
    let urgeReason: UrgeReason?
    let urgeNote: String?
}

private typealias DurationLimitState = (maxMinutes: Int, isLimited: Bool, message: String, windowTitle: String)

struct InterventionsView: View {
    @EnvironmentObject var appVM: AppViewModel
    @ObservedObject private var expansion = ProductExpansionStore.shared
    var onSessionFinished: (() -> Void)? = nil

    @State private var selectedIntention: Intention? = nil
    @State private var selectedDuration: Int? = nil
    @State private var customDurationText = ""
    @State private var durationLimitNotice: String? = nil
    @State private var showIntervention = false
    @State private var showMivoClear = false
    @State private var showOutsideWindowClearPrompt = false
    @State private var outsideWindowPromptShown = false
    @State private var activeSessionLaunch: ActiveSessionLaunch? = nil
    @State private var pendingSessionLaunch: ActiveSessionLaunch? = nil
    @State private var showAdaptivePause = false
    @State private var frictionState = InterventionFrictionState(level: 1, attemptCount: 0, waitSeconds: 5)
    @State private var frictionSecondsRemaining = 0
    @State private var frictionAttemptID: String?
    @State private var frictionAttemptResolved = false
    @State private var selectedUrge: UrgeReason? = nil
    @State private var acceptsSleepTradeoff = false
    @State private var lastScrollSelected = false
    @State private var cachedDurationLimit: DurationLimitState = (
        maxMinutes: 30,
        isLimited: false,
        message: "Checking your adaptive limit...",
        windowTitle: "Loading"
    )
    @FocusState private var customDurationFocused: Bool
    private let frictionTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var durationLimit: DurationLimitState {
        cachedDurationLimit
    }
    private var lateNightActive: Bool {
        appVM.isLateNightProtectionActive()
    }
    private var lastScrollAvailable: Bool {
        lateNightActive && !appVM.hasUsedLastScrollTonight()
    }
    private var effectiveDurationMaximum: Int {
        lastScrollSelected && lastScrollAvailable ? 10 : durationLimit.maxMinutes
    }
    var selectedDurationAllowed: Bool {
        guard let selectedDuration else { return false }
        return selectedDuration >= 1 && selectedDuration <= effectiveDurationMaximum
    }
    var canStart: Bool {
        selectedIntention != nil
            && selectedDurationAllowed
    }
    var startSelection: (intention: Intention, duration: Int)? {
        guard let intention = selectedIntention, let duration = selectedDuration, selectedDurationAllowed else { return nil }
        return (intention, duration)
    }
    var statusText: String {
        if let selection = startSelection { return "\(selection.intention.rawValue) · \(selection.duration) min" }
        if durationLimit.maxMinutes == 0 { return "No scroll window open" }
        if !durationLimit.isLimited { return "Learning mode - no cap" }
        if let selectedDuration, selectedDuration > durationLimit.maxMinutes { return "Mivo recommends \(durationLimit.maxMinutes) min or less" }
        if selectedIntention != nil { return "Choose a time limit" }
        return "Choose why you are opening it"
    }

    var body: some View {
        ZStack {
            MivoColors.background.ignoresSafeArea()
            if lateNightActive {
                Color.black.opacity(0.10)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    heroCard
                    if let experiment = appVM.activeWeeklyExperiment {
                        experimentEnforcementNotice(experiment)
                    }
                    sessionBuilderCard
                    practiceCard
                    startSessionButton
                        .padding(.top, 2)
                }
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 100)
                .mivoReadableWidth()
            }
        }
        .navigationBarHidden(true)
        .fullScreenCover(isPresented: $showIntervention) {
            InterventionView(intention: nil, duration: nil, completionTitle: "Back to Mivo")
        }
        .fullScreenCover(isPresented: $showMivoClear) {
            MivoClearHubView()
                .environmentObject(appVM)
        }
        .fullScreenCover(item: $activeSessionLaunch) { launch in
            ActiveSessionView(
                intention: launch.intention,
                plannedMinutes: launch.duration,
                urgeReason: launch.urgeReason,
                urgeNote: launch.urgeNote,
                onFinished: {
                    activeSessionLaunch = nil
                    onSessionFinished?()
                }
            )
            .environmentObject(appVM)
        }
        .sheet(isPresented: $showAdaptivePause) {
            adaptivePausePopup
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .interactiveDismissDisabled(true)
                .presentationBackground(MivoColors.background)
        }
        .sheet(isPresented: $showOutsideWindowClearPrompt) {
            outsideWindowClearPrompt
                .presentationDetents([.height(390)])
                .presentationDragIndicator(.visible)
                .presentationBackground(MivoColors.background)
        }
        .onAppear {
            refreshDurationLimit()
            clampSelectedDurationIfNeeded()
            offerMivoClearIfOutsideWindow()
        }
        .onDisappear {
            if let frictionAttemptID, !frictionAttemptResolved, appVM.mivoLaunchGateActive {
                appVM.resolveInterventionAttempt(id: frictionAttemptID, continued: false)
            }
        }
        .onChange(of: appVM.mivoLaunchGateActive) { _, active in
            if active {
                frictionAttemptID = nil
                frictionAttemptResolved = false
                acceptsSleepTradeoff = false
                lastScrollSelected = false
                refreshDurationLimit()
                outsideWindowPromptShown = false
                offerMivoClearIfOutsideWindow()
            }
        }
        .onReceive(frictionTimer) { _ in
            guard showAdaptivePause, frictionSecondsRemaining > 0 else { return }
            frictionSecondsRemaining -= 1
            if frictionSecondsRemaining == 0 {
                HapticsService.success()
                startPendingSessionIfReady()
            }
        }
        .onChange(of: appVM.sessions.count) { _, _ in
            refreshDurationLimit()
            clampSelectedDurationIfNeeded()
        }
        .onChange(of: appVM.dailyScrollSchedules.count) { _, _ in
            refreshDurationLimit()
            clampSelectedDurationIfNeeded()
        }
        .onChange(of: appVM.deviceActivityMinutesToday ?? -1) { _, _ in
            refreshDurationLimit()
            clampSelectedDurationIfNeeded()
        }
        .onChange(of: appVM.appInterventionRules.count) { _, _ in
            refreshDurationLimit()
            clampSelectedDurationIfNeeded()
        }
        .onChange(of: customDurationText) { _, value in
            applyCustomDuration(value)
        }
        .alert("Adaptive limit", isPresented: Binding(
            get: { durationLimitNotice != nil },
            set: { if !$0 { durationLimitNotice = nil } }
        )) {
            Button("Got it", role: .cancel) {}
        } message: {
            Text(durationLimitNotice ?? "")
        }
    }

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Interventions")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundColor(MivoColors.heroText)
                    Text("Add a little friction before the scroll takes over.")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(MivoColors.heroText.opacity(0.78))
                        .lineSpacing(2)
                }
                Spacer()
                ZStack {
                    Circle()
                        .fill(MivoColors.accent.opacity(0.24))
                        .frame(width: 58, height: 58)
                    Circle()
                        .fill(MivoColors.accent.opacity(0.38))
                        .frame(width: 44, height: 44)
                    Image(systemName: "pause.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(MivoColors.heroText)
                }
            }

            HStack(spacing: 10) {
                heroMetric(title: "Session", value: "Setup", icon: "slider.horizontal.3")
                heroMetric(
                    title: lastScrollSelected ? "Last scroll" : durationLimit.windowTitle,
                    value: lastScrollSelected ? "10m left" : (durationLimit.maxMinutes > 0 ? "\(durationLimit.maxMinutes)m left" : "Closed"),
                    icon: "timer"
                )
            }
        }
        .padding(20)
        .background(MivoColors.heroBg)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var adaptivePausePopup: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 22) {
                Capsule()
                    .fill(MivoColors.border.opacity(0.55))
                    .frame(width: 42, height: 5)
                    .frame(maxWidth: .infinity)

                VStack(alignment: .leading, spacing: 9) {
                    Label(frictionState.level == 3 ? "Experiment pause" : (frictionState.attemptCount >= 2 ? "Repeated opening" : "Intention set"), systemImage: "pause.circle.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(MivoColors.accent)

                    Text("Pause before the timer starts")
                        .font(.system(size: 27, weight: .bold, design: .rounded))
                        .foregroundColor(MivoColors.textPrimary)

                    Text(pauseExplanation)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(MivoColors.textSecondary)
                        .lineSpacing(4)
                }

                HStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .stroke(MivoColors.border.opacity(0.38), lineWidth: 6)
                        Circle()
                            .trim(from: 0, to: pauseProgress)
                            .stroke(MivoColors.accent, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        Text(frictionSecondsRemaining > 0 ? "\(frictionSecondsRemaining)" : "✓")
                            .font(.system(size: 23, weight: .bold, design: .rounded).monospacedDigit())
                            .foregroundColor(MivoColors.textPrimary)
                            .frame(width: 34)
                    }
                    .frame(width: 74, height: 74)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(frictionSecondsRemaining > 0 ? "Pause for a moment" : "Pause complete")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(MivoColors.textPrimary)
                        Text(pauseStatusDetail)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(MivoColors.textSecondary)
                            .lineSpacing(3)
                    }
                }
                .padding(16)
                .background(MivoColors.surface.opacity(0.62))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                if let pendingSessionLaunch {
                    HStack(spacing: 10) {
                        Image(systemName: "scope")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(MivoColors.accent)
                        Text(pendingSessionLaunch.intention.rawValue)
                        Spacer()
                        Text("\(pendingSessionLaunch.duration) min")
                    }
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(MivoColors.textPrimary)
                    .padding(14)
                    .background(MivoColors.surfaceRaised.opacity(0.58))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }

                if frictionState.level >= 2 {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("What pulled you back?")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(MivoColors.textPrimary)

                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 8)], spacing: 8) {
                            ForEach(UrgeReason.allCases) { reason in
                                Button {
                                    selectedUrge = reason
                                    HapticsService.selection()
                                    startPendingSessionIfReady()
                                } label: {
                                    Text(reason.rawValue)
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundColor(selectedUrge == reason ? MivoColors.white : MivoColors.textPrimary)
                                        .frame(maxWidth: .infinity)
                                        .frame(height: 42)
                                        .background(selectedUrge == reason ? MivoColors.accent : MivoColors.surfaceRaised)
                                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                        .overlay {
                                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                                .strokeBorder(MivoColors.border.opacity(0.30), lineWidth: 1)
                                        }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                if frictionState.level == 3, selectedUrge != nil {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Try this instead")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(MivoColors.textPrimary)

                        ForEach(replacementActions, id: \.title) { action in
                            Button {
                                chooseReplacement(action.title)
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: action.icon)
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundColor(MivoColors.blue)
                                        .frame(width: 30, height: 30)
                                        .background(MivoColors.blue.opacity(0.10))
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                    Text(action.title)
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundColor(MivoColors.textPrimary)
                                    Spacer()
                                    Image(systemName: "arrow.right")
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundColor(MivoColors.textMuted)
                                }
                                .padding(12)
                                .background(MivoColors.surfaceRaised.opacity(0.58))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if lateNightActive {
                    lateNightGatePanel
                }

                VStack(spacing: 10) {
                    Button {
                        startPendingSessionIfReady()
                    } label: {
                        HStack {
                            Text(pauseActionTitle)
                            Spacer()
                            Image(systemName: frictionSecondsRemaining > 0 ? "hourglass" : "arrow.right")
                        }
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(MivoColors.white)
                        .padding(.horizontal, 16)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(popupCanContinue ? MivoColors.blue : MivoColors.muted)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(!popupCanContinue)

                    Button {
                        chooseReplacement("Keep apps locked")
                    } label: {
                        Text("Keep apps locked")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(MivoColors.textSecondary)
                            .frame(maxWidth: .infinity, minHeight: 46)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 28)
        }
        .background(MivoColors.background)
    }

    private var popupCanContinue: Bool {
        pendingSessionLaunch != nil
            && frictionSecondsRemaining == 0
            && (frictionState.level < 2 || selectedUrge != nil)
            && (!lateNightActive || acceptsSleepTradeoff)
    }

    private var pauseActionTitle: String {
        if frictionSecondsRemaining > 0 {
            return "Starting in \(frictionSecondsRemaining)s"
        }
        if frictionState.level >= 2, selectedUrge == nil {
            return "Choose what pulled you back"
        }
        if lateNightActive, !acceptsSleepTradeoff {
            return "Answer the sleep check"
        }
        return "Start session"
    }

    private var pauseExplanation: String {
        if frictionState.waitSeconds >= 120 {
            return "This is the third opening within 30 minutes. Your approved experiment adds a two-minute cooldown before you can continue."
        }
        if frictionState.level == 3 {
            return "Your approved experiment makes repeated openings more deliberate with a longer pause, a trigger check, and another option."
        }
        if frictionState.waitSeconds == 10 {
            return "This opening came soon after another one. Your timer will stay stopped while Mivo gives you ten seconds to check the choice."
        }
        return "Your intention is saved. The session timer will stay stopped until this five-second pause is complete."
    }

    private var pauseStatusDetail: String {
        if frictionState.waitSeconds >= 120 {
            return "Your experiment detected a third opening within 30 minutes."
        }
        if frictionState.waitSeconds == 10 {
            return "Mivo noticed another opening within 30 minutes."
        }
        return "A five-second gap keeps the next step intentional."
    }

    private var pauseProgress: CGFloat {
        guard frictionState.waitSeconds > 0 else { return 1 }
        return CGFloat(frictionState.waitSeconds - frictionSecondsRemaining) / CGFloat(frictionState.waitSeconds)
    }

    private var lateNightGatePanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 9) {
                Image(systemName: "moon.stars.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(MivoColors.blue)
                    .frame(width: 30, height: 30)
                    .background(MivoColors.blue.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Late-night protection")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(MivoColors.textPrimary)
                    Text("Next wake-up: \(appVM.lateNightWakeTimeText())")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(MivoColors.textSecondary)
                }
            }

            Text("Scrolling now borrows from sleep. Are you still choosing it?")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(MivoColors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Button {
                    acceptsSleepTradeoff = true
                    lastScrollSelected = false
                    HapticsService.selection()
                    startPendingSessionIfReady()
                } label: {
                    Label(acceptsSleepTradeoff && !lastScrollSelected ? "Continuing" : "Yes, continue", systemImage: acceptsSleepTradeoff && !lastScrollSelected ? "checkmark.circle.fill" : "arrow.right.circle")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(acceptsSleepTradeoff && !lastScrollSelected ? MivoColors.heroText : MivoColors.textPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(acceptsSleepTradeoff && !lastScrollSelected ? MivoColors.accent : MivoColors.background)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)

                Button {
                    chooseReplacement("Protect my sleep")
                } label: {
                    Label("Exit now", systemImage: "lock.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(MivoColors.blue)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(MivoColors.blue.opacity(0.10))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }

            if lastScrollAvailable {
                Button {
                    acceptsSleepTradeoff = true
                    lastScrollSelected = true
                    selectedDuration = 10
                    customDurationText = ""
                    customDurationFocused = false
                    if let pendingSessionLaunch {
                        self.pendingSessionLaunch = ActiveSessionLaunch(
                            intention: pendingSessionLaunch.intention,
                            duration: 10,
                            urgeReason: selectedUrge,
                            urgeNote: pendingSessionLaunch.urgeNote
                        )
                    }
                    HapticsService.selection()
                    startPendingSessionIfReady()
                } label: {
                    HStack {
                        Image(systemName: "moon.zzz.fill")
                        Text("Make this my last scroll of the night")
                        Spacer()
                        Text("10 min")
                    }
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(lastScrollSelected ? MivoColors.heroText : MivoColors.accent)
                    .padding(11)
                    .background(lastScrollSelected ? MivoColors.accent : MivoColors.accent.opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            } else {
                Label("Your last scroll is used. Apps stay protected until \(appVM.lateNightWakeTimeText()).", systemImage: "checkmark.shield.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(MivoColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .background(Color.black.opacity(0.045))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(MivoColors.blue.opacity(0.20), lineWidth: 1))
    }

    private func heroMetric(title: String, value: String, icon: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(MivoColors.heroText)
                .frame(width: 28, height: 28)
                .background(MivoColors.accent.opacity(0.55))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(MivoColors.heroText)
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(MivoColors.heroText.opacity(0.68))
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(MivoColors.heroText.opacity(0.13))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func experimentEnforcementNotice(_ experiment: WeeklyExperiment) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: experimentNoticeIcon(experiment.type))
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(MivoColors.accent)
                .frame(width: 32, height: 32)
                .background(MivoColors.accent.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 3) {
                Text("Experiment active · Day \(experiment.dayNumber) of 7")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(MivoColors.accent)
                Text(experimentNoticeText(experiment))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(MivoColors.textPrimary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .overlay(alignment: .bottom) {
            Rectangle().fill(MivoColors.border.opacity(0.38)).frame(height: 1)
        }
    }

    private func experimentNoticeIcon(_ type: WeeklyExperimentType) -> String {
        switch type {
        case .protectedWindow: return "lock.clock.fill"
        case .reduceExtensions: return "timer"
        case .strongerFriction: return "hand.raised.fill"
        }
    }

    private func experimentNoticeText(_ experiment: WeeklyExperiment) -> String {
        switch experiment.type {
        case .protectedWindow:
            let start = experiment.rule.startHour ?? 21
            let end = experiment.rule.endHour ?? ((start + 1) % 24)
            return "Native scrolling stays protected from \(experimentHour(start)) to \(experimentHour(end)); Mivo Clear BETA remains available."
        case .reduceExtensions:
            return "The original session limit stays fixed. Add Time is unavailable while this experiment runs."
        case .strongerFriction:
            return "Repeated openings add a trigger check; a third opening within 30 minutes adds a two-minute cooldown."
        }
    }

    private func experimentHour(_ hour: Int) -> String {
        let normalized = ((hour % 24) + 24) % 24
        if normalized == 0 { return "12 AM" }
        if normalized == 12 { return "12 PM" }
        return normalized < 12 ? "\(normalized) AM" : "\(normalized - 12) PM"
    }

    private var sessionBuilderCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 11) {
                Image(systemName: "scope")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(MivoColors.heroText)
                    .frame(width: 32, height: 32)
                    .background(MivoColors.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Session builder")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(MivoColors.textPrimary)
                    Text(statusText)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(MivoColors.accent)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Why are you opening it?")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(MivoColors.accent)

                VStack(spacing: 8) {
                    ForEach(Intention.allCases, id: \.rawValue) { intention in
                        intentionRow(intention)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("How long?")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(MivoColors.accent)

                HStack(spacing: 8) {
                    Image(systemName: effectiveDurationMaximum > 0 ? "calendar.badge.clock" : "lock.fill")
                        .font(.system(size: 12, weight: .bold))
                    Text(lastScrollSelected ? "Last scroll" : durationLimit.windowTitle)
                    Spacer(minLength: 0)
                    Text(lastScrollSelected ? "10 min final" : (durationLimit.isLimited ? (durationLimit.maxMinutes > 0 ? "\(durationLimit.maxMinutes) min available" : "come back later") : "unlimited learning"))
                }
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(effectiveDurationMaximum > 0 ? MivoColors.accent : MivoColors.textMuted)
                .padding(10)
                .background(MivoColors.background)
                .clipShape(RoundedRectangle(cornerRadius: 8))

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                    ForEach(durations, id: \.value) { item in
                        durationChip(item)
                    }
                }

                customDurationField

                Label(
                    lastScrollSelected
                        ? "This one-time 10-minute session will re-lock your selected apps until \(appVM.lateNightWakeTimeText())."
                        : durationLimit.message,
                    systemImage: lastScrollSelected ? "moon.stars.fill" : (durationLimit.isLimited ? "sparkles" : "chart.line.uptrend.xyaxis")
                )
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(MivoColors.textSecondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(18)
        .background(MivoColors.surface.opacity(0.62))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(MivoColors.border.opacity(0.55), lineWidth: 1))
    }

    private func c3StepHeader(number: Int, title: String) -> some View {
        HStack(spacing: 10) {
            Text("\(number)")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundColor(MivoColors.accent)
                .frame(width: 30, height: 30)
                .background(MivoColors.accent.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            Text(title)
                .font(.system(size: 17, weight: .bold))
                .foregroundColor(MivoColors.textPrimary)
        }
    }

    private func reviewValue(icon: String, label: String, value: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(MivoColors.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(label.uppercased())
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(MivoColors.textMuted)
                Text(value)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(MivoColors.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func intentionRow(_ intention: Intention) -> some View {
        let selected = selectedIntention == intention
        return Button {
            withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
                selectedIntention = intention
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: intentionIcon(intention))
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(selected ? MivoColors.heroText : MivoColors.accent)
                    .frame(width: 32, height: 32)
                    .background(selected ? MivoColors.accent : MivoColors.background)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                Text(intention.rawValue)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(selected ? MivoColors.accent : MivoColors.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Spacer()

                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(selected ? MivoColors.accent : MivoColors.muted)
            }
            .padding(.horizontal, 12)
            .frame(height: 54)
            .background(selected ? MivoColors.accent.opacity(0.18) : MivoColors.surfaceRaised)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(selected ? MivoColors.accent.opacity(0.65) : Color.clear, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func durationChip(_ item: (label: String, value: Int)) -> some View {
        let selected = selectedDuration == item.value
        let locked = item.value > effectiveDurationMaximum
        return Button {
            guard !locked else {
                durationLimitNotice = durationLimit.maxMinutes == 0
                    ? durationLimit.message
                    : "\(durationLimit.message)\n\nChoose \(durationLimit.maxMinutes) min or less."
                HapticsService.warning()
                return
            }
            withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                lastScrollSelected = false
                selectedDuration = item.value
                customDurationText = ""
                customDurationFocused = false
            }
        } label: {
            HStack(spacing: 5) {
                if locked {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 10, weight: .bold))
                }
                Text(item.label)
                    .font(.system(size: 13, weight: .bold))
            }
                .foregroundColor(selected ? MivoColors.heroText : (locked ? MivoColors.textMuted : MivoColors.textPrimary))
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(selected ? MivoColors.accent : MivoColors.surfaceRaised)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(MivoColors.border.opacity(0.34), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var customDurationField: some View {
        HStack(spacing: 10) {
            Image(systemName: "keyboard")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(MivoColors.accent)
                .frame(width: 30, height: 30)
                .background(MivoColors.background)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            TextField(
                "",
                text: $customDurationText,
                prompt: Text("Custom minutes").foregroundColor(MivoColors.textSecondary)
            )
                .keyboardType(.numberPad)
                .focused($customDurationFocused)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(MivoColors.textPrimary)
                .disabled(durationLimit.maxMinutes == 0)

            Text("min")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(MivoColors.textSecondary)
        }
        .padding(12)
        .background(MivoColors.surfaceRaised)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(MivoColors.border.opacity(0.34), lineWidth: 1))
    }

    private var practiceCard: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(MivoColors.background)
                    .frame(width: 54, height: 54)
                Image(systemName: "hourglass")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(MivoColors.accent)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Practice the pause")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(MivoColors.textPrimary)
                Text("Preview the 5-second pause. Repeated openings use 10 seconds.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(MivoColors.textSecondary)
                    .lineSpacing(3)
            }

            Spacer()

            Button {
                showIntervention = true
            } label: {
                Image(systemName: "play.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(MivoColors.heroText)
                    .frame(width: 42, height: 42)
                    .background(MivoColors.accent)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .mivoC3Section(verticalPadding: 14)
    }

    private var startSessionButton: some View {
        let selection = startSelection
        let redirectsToClear = durationLimit.maxMinutes == 0 && !lastScrollSelected
        let buttonText = lastScrollSelected
            ? "Set intention for last scroll"
            : redirectsToClear
            ? "Use Mivo Clear BETA instead"
            : (selection.map { _ in "Set intention" } ?? "Choose intention and duration")

        return Button {
            if redirectsToClear {
                showOutsideWindowClearPrompt = true
            } else if let selection {
                beginAdaptivePause(for: selection)
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: redirectsToClear ? "sparkles" : (canStart ? "arrow.right.circle.fill" : "circle.dotted"))
                    .font(.system(size: 18, weight: .bold))
                Text(buttonText)
                    .font(.system(size: 17, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }
            .foregroundColor(MivoColors.heroText)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background((canStart || redirectsToClear) ? MivoColors.blue : MivoColors.muted)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .disabled(!canStart && !redirectsToClear)
    }

    private var outsideWindowClearPrompt: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 12) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(MivoColors.heroText)
                    .frame(width: 44, height: 44)
                    .background(MivoColors.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 3) {
                    Text("Outside your scroll window")
                        .font(.system(size: 21, weight: .bold, design: .rounded))
                        .foregroundColor(MivoColors.textPrimary)
                    Text("Your scrolling apps stay protected.")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(MivoColors.textSecondary)
                }
            }

            Text("Need to text, search, or watch a longer YouTube video? Use Mivo Clear BETA without opening the endless feed.")
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(MivoColors.textSecondary)
                .lineSpacing(4)

            Button {
                HapticsService.selection()
                showOutsideWindowClearPrompt = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                    showMivoClear = true
                }
            } label: {
                Label("Open Mivo Clear BETA", systemImage: "sparkles")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(MivoColors.heroText)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(MivoColors.blue)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)

            Button("Stay in Interventions") {
                showOutsideWindowClearPrompt = false
            }
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(MivoColors.textSecondary)
            .frame(maxWidth: .infinity)
        }
        .padding(22)
    }

    private var replacementActions: [(title: String, icon: String)] {
        switch selectedUrge {
        case .message:
            return [("Message the person directly", "message.fill"), ("Return to what you were doing", "arrow.uturn.backward")]
        case .stressed:
            return [("Take four slow breaths", "wind"), ("Walk for two minutes", "figure.walk")]
        case .specificTask:
            return [("Write down the exact task", "checklist"), ("Return to what you were doing", "arrow.uturn.backward")]
        case .bored, .habit:
            return [("Walk for two minutes", "figure.walk"), ("Message someone", "message.fill")]
        default:
            return [("Take four slow breaths", "wind"), ("Return to what you were doing", "arrow.uturn.backward")]
        }
    }

    private func registerFrictionAttemptIfNeeded() {
        guard frictionAttemptID == nil else { return }
        let standardState = InterventionFrictionTracker.registerAttempt()
        frictionState = appVM.interventionFrictionState(from: standardState)
        frictionSecondsRemaining = frictionState.waitSeconds
        frictionAttemptID = appVM.recordInterventionAttempt()
    }

    private func beginAdaptivePause(for selection: (intention: Intention, duration: Int)) {
        customDurationFocused = false
        selectedUrge = nil
        acceptsSleepTradeoff = false
        lastScrollSelected = false
        frictionAttemptID = nil
        frictionAttemptResolved = false
        registerFrictionAttemptIfNeeded()

        pendingSessionLaunch = ActiveSessionLaunch(
            intention: selection.intention,
            duration: selection.duration,
            urgeReason: nil,
            urgeNote: nil
        )

        // Keep every selected app shielded for the full pause. The active-session
        // screen is not created until the countdown has genuinely finished.
        FamilyControlsManager.shared.prepareForSessionStartPause()
        showAdaptivePause = true
    }

    private func startPendingSessionIfReady() {
        guard popupCanContinue, let pendingSessionLaunch else { return }

        let launch = ActiveSessionLaunch(
            intention: pendingSessionLaunch.intention,
            duration: pendingSessionLaunch.duration,
            urgeReason: selectedUrge,
            urgeNote: pendingSessionLaunch.urgeNote
        )
        self.pendingSessionLaunch = nil

        if lastScrollSelected {
            appVM.markLastScrollOfNightStarted()
        }
        if let frictionAttemptID {
            frictionAttemptResolved = true
            appVM.resolveInterventionAttempt(id: frictionAttemptID, continued: true)
        }

        showAdaptivePause = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
            activeSessionLaunch = launch
        }
    }

    private func chooseReplacement(_ title: String) {
        if let frictionAttemptID {
            frictionAttemptResolved = true
            appVM.resolveInterventionAttempt(id: frictionAttemptID, continued: false)
        }
        appVM.dismissMivoLaunchGate()
        pendingSessionLaunch = nil
        FamilyControlsManager.shared.cancelSessionStartPauseAndRelock()
        showAdaptivePause = false
        HapticsService.success()
        onSessionFinished?()
    }

    private func countdownLabel(_ seconds: Int) -> String {
        seconds >= 60 ? "\(seconds / 60):\(String(format: "%02d", seconds % 60))" : "\(seconds)s"
    }

    private func sectionTitle(_ title: String, subtitle: String, icon: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(MivoColors.heroText)
                .frame(width: 30, height: 30)
                .background(MivoColors.accent)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(MivoColors.textPrimary)
                Text(subtitle)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(MivoColors.textSecondary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)
            }
            Spacer()
        }
    }

    private func intentionIcon(_ intention: Intention) -> String {
        switch intention {
        case .killTime: return "clock"
        case .relax: return "leaf"
        case .bored: return "sparkles"
        case .lookingForSomethingSpecific: return "magnifyingglass"
        }
    }

    private func applyCustomDuration(_ value: String) {
        if !value.isEmpty {
            lastScrollSelected = false
        }
        let digits = value.filter(\.isNumber)
        if digits != value {
            customDurationText = digits
            return
        }

        guard let minutes = Int(digits), minutes > 0 else {
            if selectedDuration != nil && customDurationFocused {
                selectedDuration = nil
            }
            return
        }

        let capped = min(minutes, 240)
        if capped != minutes {
            customDurationText = "\(capped)"
        }

        guard capped <= durationLimit.maxMinutes else {
            selectedDuration = nil
            durationLimitNotice = durationLimit.maxMinutes == 0
                ? durationLimit.message
                : "\(durationLimit.message)\n\nChoose \(durationLimit.maxMinutes) min or less."
            return
        }

        selectedDuration = capped
    }

    private func clampSelectedDurationIfNeeded() {
        guard let selectedDuration, selectedDuration > durationLimit.maxMinutes else { return }
        self.selectedDuration = nil
    }

    private func refreshDurationLimit() {
        cachedDurationLimit = appVM.adaptiveSessionDurationLimit()
    }

    private func offerMivoClearIfOutsideWindow() {
        guard durationLimit.maxMinutes == 0,
              !lastScrollSelected,
              !outsideWindowPromptShown,
              expansion.isEnabled(.mivoClear) else { return }
        outsideWindowPromptShown = true
        DispatchQueue.main.async {
            showOutsideWindowClearPrompt = true
        }
    }

}

extension View {
    func flexibleWrapping() -> some View {
        self
    }
}
