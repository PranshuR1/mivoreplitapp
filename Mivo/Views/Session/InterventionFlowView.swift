import SwiftUI

private let flowDurations: [Int] = [5, 10, 15, 30]

/// §4 Intervention flow: reason → duration → pause → active → reflect, per
/// `INTERACTIONS.md`. Active and reflect are the existing `ActiveSessionView`
/// and `ReflectionView`, which this presents unchanged — this file only owns
/// reason, duration and the pause.
///
/// The pause step also carries mechanics the design spec doesn't describe but
/// that were kept intentionally: friction escalates on repeated openings
/// (asks what pulled you back, then offers a replacement action), a late-night
/// gate asks for a deliberate yes before unlocking, and a duration cap can
/// redirect to Mivo Clear entirely when no window is open. These render as a
/// light panel under the breathing glow rather than disappearing.
struct InterventionFlowView: View {
    @EnvironmentObject var appVM: AppViewModel
    @ObservedObject private var expansion = ProductExpansionStore.shared
    @ObservedObject private var companion = CompanionStateManager.shared
    @Environment(\.dismiss) private var dismiss
    var onFinished: () -> Void

    private enum FlowStep { case reason, duration, pause }

    @State private var step: FlowStep = .reason
    @State private var selectedIntention: Intention?
    @State private var selectedDuration: Int?
    @State private var cachedDurationLimit: (maxMinutes: Int, isLimited: Bool, message: String, windowTitle: String) = (
        maxMinutes: 30, isLimited: false, message: "Checking your adaptive limit...", windowTitle: "Loading"
    )
    @State private var durationLimitNotice: String?

    @State private var showOutsideWindowClearPrompt = false
    @State private var showMivoClear = false
    @State private var showIntentGames = false
    @State private var showSwapConfirm = false

    @State private var frictionState = InterventionFrictionState(level: 1, attemptCount: 0, waitSeconds: 5)
    @State private var frictionSecondsRemaining = 0
    @State private var frictionAttemptID: String?
    @State private var frictionAttemptResolved = false
    @State private var selectedUrge: UrgeReason?
    @State private var acceptsSleepTradeoff = false
    @State private var lastScrollSelected = false
    @State private var pauseReady = false

    @State private var activeLaunch: FlowLaunch?

    private let frictionTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private struct FlowLaunch: Identifiable {
        let id = UUID()
        let intention: Intention
        let duration: Int
        let urgeReason: UrgeReason?
    }

    var body: some View {
        Group {
            switch step {
            case .reason: reasonStep
            case .duration: durationStep
            case .pause: pauseStep
            }
        }
        .fullScreenCover(item: $activeLaunch) { launch in
            ActiveSessionView(
                intention: launch.intention,
                plannedMinutes: launch.duration,
                urgeReason: launch.urgeReason,
                urgeNote: nil,
                onFinished: {
                    activeLaunch = nil
                    onFinished()
                    dismiss()
                }
            )
            .environmentObject(appVM)
        }
        .sheet(isPresented: $showOutsideWindowClearPrompt) {
            outsideWindowClearPrompt
                .presentationDetents([.height(390)])
                .presentationDragIndicator(.visible)
                .presentationBackground(MivoColors.background)
        }
        .sheet(isPresented: $showSwapConfirm) {
            swapConfirmSheet
        }
        .fullScreenCover(isPresented: $showMivoClear, onDismiss: { walkAway() }) {
            MivoClearHubView().environmentObject(appVM)
        }
        .fullScreenCover(isPresented: $showIntentGames) {
            if let selectedIntention {
                IntentGamePickerView(
                    intention: selectedIntention,
                    onSessionReady: { minutes in
                        selectedDuration = minutes
                        showIntentGames = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                            beginPause(intention: selectedIntention, duration: minutes)
                        }
                    },
                    onUseMivoClear: {
                        showIntentGames = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                            showMivoClear = true
                        }
                    }
                )
                .environmentObject(appVM)
            }
        }
        .onAppear {
            refreshDurationLimit()
            offerMivoClearIfOutsideWindow()
        }
        .onChange(of: appVM.sessions.count) { _, _ in refreshDurationLimit() }
        .onChange(of: appVM.dailyScrollSchedules.count) { _, _ in refreshDurationLimit() }
        .onChange(of: appVM.deviceActivityMinutesToday ?? -1) { _, _ in refreshDurationLimit() }
        .onChange(of: appVM.appInterventionRules.count) { _, _ in refreshDurationLimit() }
        .onReceive(frictionTimer) { _ in
            guard step == .pause, frictionSecondsRemaining > 0 else { return }
            frictionSecondsRemaining -= 1
            if frictionSecondsRemaining == 0 {
                HapticsService.impact(style: .medium)
                pauseReady = true
                startIfReady()
            } else {
                HapticsService.impact(style: .light)
            }
        }
        .onDisappear {
            if let frictionAttemptID, !frictionAttemptResolved {
                appVM.resolveInterventionAttempt(id: frictionAttemptID, continued: false)
            }
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

    // MARK: - 4.1 Reason

    private var reasonStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            flowTopBar(step: 1)

            Text("Why are you opening it?")
                .font(.system(size: 27, weight: .bold))
                .tracking(Font.mivoTracking(-0.025, at: 27))
                .foregroundColor(MivoColors.ink)
                .frame(maxWidth: 270, alignment: .leading)
                .padding(.top, 8)

            Text("No wrong answer. Naming it is the whole point.")
                .font(.system(size: 13.5, weight: .medium))
                .foregroundColor(MivoColors.inkBody)
                .padding(.top, 8)

            VStack(spacing: 9) {
                ForEach(Intention.flowOptions, id: \.rawValue) { intention in
                    MivoOptionRow(
                        label: intention.flowLabel,
                        isSelected: selectedIntention == intention,
                        fillsWhenSelected: true
                    ) {
                        HapticsService.selection()
                        selectedIntention = intention
                    }
                }
            }
            .padding(.top, 24)

            Spacer(minLength: 20)

            MivoPrimaryButton(label: "Continue", disabled: selectedIntention == nil) {
                withAnimation(MivoMotion.stepEnter) { step = .duration }
            }
            .padding(.bottom, 44)
        }
        .padding(.horizontal, MivoMetrics.screenPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(MivoColors.background.ignoresSafeArea())
        .transition(.opacity.combined(with: .move(edge: .trailing)))
    }

    // MARK: - 4.2 Duration

    private var durationStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            flowTopBar(step: 2)

            Text("How long do you need?")
                .font(.system(size: 27, weight: .bold))
                .tracking(Font.mivoTracking(-0.025, at: 27))
                .foregroundColor(MivoColors.ink)
                .padding(.top, 8)

            if let selectedIntention {
                Text(selectedIntention.flowLabel)
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundColor(MivoColors.inkBody)
                    .padding(.top, 8)
            }

            VStack(spacing: 6) {
                Text("\(effectiveSelectedMinutes)")
                    .font(.system(size: 72, weight: .bold))
                    .monospacedDigit()
                    .tracking(Font.mivoTracking(-0.045, at: 72))
                    .foregroundColor(MivoColors.ink)
                Text("minutes")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundColor(MivoColors.inkMuted)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 30)

            HStack(spacing: 9) {
                ForEach(flowDurations, id: \.self) { minutes in
                    durationChip(minutes)
                }
            }
            .padding(.top, 30)

            durationAvailabilityLine
                .padding(.top, 14)

            Text("Mivo closes the app when the window ends. You'll get a nudge at one minute left.")
                .font(.system(size: 12.5, weight: .medium))
                .foregroundColor(MivoColors.inkMuted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.top, 14)

            if appVM.userSwap != nil {
                swapRow
                    .padding(.top, 18)
            }

            // Gated on both the server flag and the local opt-in — this is a
            // trial someone chooses in Settings, not something everyone with
            // the flag on sees by default. It also stops appearing once
            // today's allowance is actually spent, rather than staying
            // available indefinitely as a way to keep pulling minutes out of
            // a day that has none left.
            if expansion.isEnabled(.intentGames), FocusBreakTrial.isOptedIn, cachedDurationLimit.maxMinutes > 0 {
                playForUnlockTimeRow
                    .padding(.top, 18)
            }

            Spacer(minLength: 20)

            MivoPrimaryButton(
                label: durationButtonLabel,
                disabled: !redirectsToClear && selectedDuration == nil
            ) {
                if redirectsToClear {
                    showOutsideWindowClearPrompt = true
                } else if let selectedIntention, let selectedDuration {
                    beginPause(intention: selectedIntention, duration: selectedDuration)
                }
            }
            .padding(.bottom, 44)
        }
        .padding(.horizontal, MivoMetrics.screenPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(MivoColors.background.ignoresSafeArea())
        .transition(.opacity.combined(with: .move(edge: .trailing)))
    }

    private func durationChip(_ minutes: Int) -> some View {
        let locked = minutes > effectiveDurationMaximum
        return Button {
            guard !locked else {
                durationLimitNotice = cachedDurationLimit.maxMinutes == 0
                    ? cachedDurationLimit.message
                    : "\(cachedDurationLimit.message)\n\nChoose \(cachedDurationLimit.maxMinutes) min or less."
                HapticsService.impact(style: .light)
                return
            }
            HapticsService.selection()
            lastScrollSelected = false
            selectedDuration = minutes
        } label: {
            HStack(spacing: 4) {
                if locked {
                    Image(systemName: "lock.fill").font(.system(size: 10, weight: .bold))
                }
                Text("\(minutes)m")
            }
            .font(.system(size: 14.5, weight: .semibold))
            .foregroundColor(selectedDuration == minutes ? MivoColors.background : (locked ? MivoColors.inkMuted : MivoColors.ink))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(selectedDuration == minutes ? MivoColors.ink : .clear)
            .clipShape(RoundedRectangle(cornerRadius: MivoMetrics.radius))
            .overlay(
                RoundedRectangle(cornerRadius: MivoMetrics.radius)
                    .strokeBorder(selectedDuration == minutes ? MivoColors.ink : MivoColors.ink.opacity(0.16), lineWidth: 1)
            )
        }
        .buttonStyle(MivoPressStyle())
    }

    @ViewBuilder
    private var durationAvailabilityLine: some View {
        if lastScrollSelected {
            Text("Last scroll of the night · re-locks after")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(MivoColors.info)
        } else if cachedDurationLimit.isLimited {
            Text(cachedDurationLimit.maxMinutes > 0 ? "\(cachedDurationLimit.windowTitle) · \(cachedDurationLimit.maxMinutes) min available" : cachedDurationLimit.windowTitle)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(MivoColors.deep)
        }
    }

    private var durationButtonLabel: String {
        if redirectsToClear { return "Use Mivo Clear instead" }
        guard let selectedDuration, let selectedIntention else { return "Choose a length" }
        return "Open \(appName(for: selectedIntention)) for \(selectedDuration) min"
    }

    /// The design copy interpolates an app name ("Open Instagram for 15 min"),
    /// but a session isn't tied to one app in this data model — see the same
    /// note on `InterventionsView.sessionMeta`. "it" keeps the sentence true.
    private func appName(for intention: Intention) -> String { "it" }

    private var effectiveSelectedMinutes: Int { selectedDuration ?? 0 }

    private var effectiveDurationMaximum: Int {
        lastScrollSelected && lastScrollAvailable ? 10 : cachedDurationLimit.maxMinutes
    }

    private var redirectsToClear: Bool {
        cachedDurationLimit.maxMinutes == 0 && !lastScrollSelected
    }

    /// Additive alternative to the duration chips above — playing a short
    /// game earns unlock minutes instead of picking a number, feeding into
    /// the exact same `beginPause` pipeline once approved. The call site
    /// already hides this once today's allowance is at 0, an opt-in trial
    /// someone has to turn on in Settings, and behind the server-side
    /// `.intentGames` flag on top of that.
    private var playForUnlockTimeRow: some View {
        Button {
            HapticsService.selection()
            showIntentGames = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.system(size: 14, weight: .semibold))
                Text("Try Focus Break")
                    .font(.system(size: 14.5, weight: .semibold))
                MivoBadge.trial()
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(MivoColors.inkMuted)
            }
            .foregroundColor(MivoColors.ink)
            .padding(.horizontal, 16)
            .padding(.vertical, 15)
            .background(MivoColors.ink.opacity(0.03))
            .clipShape(RoundedRectangle(cornerRadius: MivoMetrics.radius))
            .overlay(
                RoundedRectangle(cornerRadius: MivoMetrics.radius)
                    .strokeBorder(MivoColors.hairline, lineWidth: 1)
            )
        }
        .buttonStyle(MivoPressStyle())
    }

    /// Same cue, same routine, different reward — the pre-committed
    /// real-world alternative from `AppViewModel.userSwap`. Unlike Focus
    /// Break's mini-games this doesn't try to out-reward the app itself; it
    /// just needs to be the thing that's already decided, so there's nothing
    /// left to choose in the moment.
    private var swapRow: some View {
        Button {
            HapticsService.selection()
            showSwapConfirm = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: appVM.userSwap?.icon ?? "sparkles")
                    .font(.system(size: 14, weight: .semibold))
                Text(appVM.userSwap?.title ?? "Do your swap instead")
                    .font(.system(size: 14.5, weight: .semibold))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(MivoColors.inkMuted)
            }
            .foregroundColor(MivoColors.ink)
            .padding(.horizontal, 16)
            .padding(.vertical, 15)
            .background(MivoColors.ink.opacity(0.03))
            .clipShape(RoundedRectangle(cornerRadius: MivoMetrics.radius))
            .overlay(
                RoundedRectangle(cornerRadius: MivoMetrics.radius)
                    .strokeBorder(MivoColors.hairline, lineWidth: 1)
            )
        }
        .buttonStyle(MivoPressStyle())
    }

    private var swapConfirmSheet: some View {
        VStack(spacing: 18) {
            Image(systemName: appVM.userSwap?.icon ?? "sparkles")
                .font(.system(size: 28, weight: .semibold))
                .foregroundColor(MivoColors.ink)
                .frame(width: 64, height: 64)
                .background(MivoColors.ink.opacity(0.06))
                .clipShape(Circle())
                .padding(.top, 22)

            VStack(spacing: 8) {
                Text(appVM.userSwap?.title ?? "Your swap")
                    .font(.system(size: 19, weight: .bold))
                    .foregroundColor(MivoColors.ink)
                    .multilineTextAlignment(.center)
                Text("Go do it now, then come back and tap done.")
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundColor(MivoColors.inkBody)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 28)

            Spacer(minLength: 0)

            VStack(spacing: 10) {
                MivoPrimaryButton(label: "Done") {
                    HapticsService.success()
                    showSwapConfirm = false
                    appVM.appendAISummary("Swap used instead of opening \(selectedIntention.map { appName(for: $0) } ?? "the app"): \(appVM.userSwap?.title ?? "swap")")
                    walkAway()
                }
                Button("Never mind") {
                    HapticsService.selection()
                    showSwapConfirm = false
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(MivoColors.inkMuted)
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 28)
        }
        .presentationDetents([.height(320)])
        .presentationDragIndicator(.visible)
        .presentationBackground(MivoColors.background)
    }

    private var lateNightActive: Bool { appVM.isLateNightProtectionActive() }
    private var lastScrollAvailable: Bool { lateNightActive && !appVM.hasUsedLastScrollTonight() }

    // MARK: - 4.3 The pause

    private var pauseStep: some View {
        ZStack {
            MivoColors.stage.ignoresSafeArea()

            // The companion sits inside this existing pause; it adds no actions.
            // On a short screen that also has to fit the urge / late-night
            // panel, the layout without the character is used instead.
            if companion.isActive {
                ViewThatFits(in: .vertical) {
                    pauseColumn(showsCompanion: true)
                    pauseColumn(showsCompanion: false)
                }
            } else {
                pauseColumn(showsCompanion: false)
            }
        }
        .transition(.opacity.combined(with: .move(edge: .trailing)))
    }

    private func pauseColumn(showsCompanion: Bool) -> some View {
        VStack(spacing: 0) {
            Spacer(minLength: 40)

            PauseBreathingStage(secondsRemaining: frictionSecondsRemaining, totalSeconds: max(frictionState.waitSeconds, 1))
                .frame(width: 210, height: 210)

            Text(pauseHeadline)
                .font(.system(size: 19, weight: .semibold))
                .foregroundColor(Color(hex: "#FAF3E8"))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 250)
                .padding(.top, 24)

            if let selectedIntention {
                Text(selectedIntention.flowLabel)
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundColor(Color(hex: "#FAF3E8").opacity(0.62))
                    .padding(.top, 6)
            }

            if showsCompanion {
                CompanionPauseAccessory(compact: pausePanelVisible, topPadding: 14)
            }

            Spacer(minLength: 20)

            pausePanel
                .padding(.bottom, 16)

            Button {
                walkAway()
            } label: {
                Text("I've changed my mind")
                    .font(.system(size: 14.5, weight: .bold))
                    .foregroundColor(Color(hex: "#FAF3E8").opacity(0.72))
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .overlay(
                        RoundedRectangle(cornerRadius: MivoMetrics.radius)
                            .strokeBorder(Color(hex: "#FAF3E8").opacity(0.20), lineWidth: 1)
                    )
            }
            .buttonStyle(MivoPressStyle())
            .padding(.bottom, 20)
        }
        .padding(.horizontal, MivoMetrics.screenPadding)
    }

    private var pausePanelVisible: Bool { frictionState.level >= 2 || lateNightActive }

    /// Everything beyond the breathing glow that the pause step needs to be
    /// able to show: the urge question at friction level ≥2, the replacement
    /// suggestions once an urge is chosen, and the late-night check. Nil when
    /// none of that applies, which is the common case the design shows.
    @ViewBuilder
    private var pausePanel: some View {
        if frictionState.level >= 2 || lateNightActive {
            VStack(alignment: .leading, spacing: 16) {
                if frictionState.level >= 2, pauseReady {
                    urgeQuestion
                }
                if frictionState.level == 3, selectedUrge != nil {
                    replacementSuggestions
                }
                if lateNightActive {
                    lateNightPanel
                }
            }
            .padding(18)
            .background(MivoColors.background)
            .clipShape(RoundedRectangle(cornerRadius: MivoMetrics.radius))
        }
    }

    private var urgeQuestion: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("What pulled you back?")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(MivoColors.ink)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 8)], spacing: 8) {
                ForEach(UrgeReason.allCases) { reason in
                    Button {
                        selectedUrge = reason
                        HapticsService.selection()
                        startIfReady()
                    } label: {
                        Text(reason.rawValue)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(selectedUrge == reason ? MivoColors.background : MivoColors.ink)
                            .frame(maxWidth: .infinity)
                            .frame(height: 42)
                            .background(selectedUrge == reason ? MivoColors.ink : MivoColors.surfaceV2)
                            .clipShape(RoundedRectangle(cornerRadius: MivoMetrics.radius))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var replacementSuggestions: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Try this instead")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(MivoColors.ink)
            ForEach(replacementActions, id: \.title) { action in
                Button { chooseReplacement() } label: {
                    HStack(spacing: 10) {
                        Image(systemName: action.icon)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(MivoColors.info)
                            .frame(width: 30, height: 30)
                            .background(MivoColors.info.opacity(0.10))
                            .clipShape(RoundedRectangle(cornerRadius: MivoMetrics.radius))
                        Text(action.title)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(MivoColors.ink)
                        Spacer()
                        Image(systemName: "arrow.right")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(MivoColors.inkMuted)
                    }
                    .padding(12)
                    .background(MivoColors.surfaceV2)
                    .clipShape(RoundedRectangle(cornerRadius: MivoMetrics.radius))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var lateNightPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 9) {
                Image(systemName: "moon.stars.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(MivoColors.info)
                    .frame(width: 30, height: 30)
                    .background(MivoColors.info.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: MivoMetrics.radius))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Late-night protection")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(MivoColors.ink)
                    Text("Next wake-up: \(appVM.lateNightWakeTimeText())")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(MivoColors.inkMuted)
                }
            }

            Text("Scrolling now borrows from sleep. Are you still choosing it?")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(MivoColors.ink)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Button {
                    acceptsSleepTradeoff = true
                    lastScrollSelected = false
                    HapticsService.selection()
                    startIfReady()
                } label: {
                    Text(acceptsSleepTradeoff && !lastScrollSelected ? "Continuing" : "Yes, continue")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(acceptsSleepTradeoff && !lastScrollSelected ? .white : MivoColors.ink)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(acceptsSleepTradeoff && !lastScrollSelected ? MivoColors.accent : MivoColors.background)
                        .clipShape(RoundedRectangle(cornerRadius: MivoMetrics.radius))
                }
                .buttonStyle(.plain)

                Button { chooseReplacement() } label: {
                    Text("Exit now")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(MivoColors.info)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(MivoColors.info.opacity(0.10))
                        .clipShape(RoundedRectangle(cornerRadius: MivoMetrics.radius))
                }
                .buttonStyle(.plain)
            }

            if lastScrollAvailable {
                Button {
                    acceptsSleepTradeoff = true
                    lastScrollSelected = true
                    selectedDuration = 10
                    HapticsService.selection()
                    startIfReady()
                } label: {
                    HStack {
                        Image(systemName: "moon.zzz.fill")
                        Text("Make this my last scroll of the night")
                        Spacer()
                        Text("10 min")
                    }
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(MivoColors.accent)
                    .padding(11)
                    .background(MivoColors.accent.opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: MivoMetrics.radius))
                }
                .buttonStyle(.plain)
            }
        }
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

    private var pauseHeadline: String {
        if frictionSecondsRemaining > 0 {
            return frictionState.waitSeconds >= 60
                ? "\(frictionSecondsRemaining / 60):\(String(format: "%02d", frictionSecondsRemaining % 60)) before the door opens"
                : "\(frictionSecondsRemaining) second\(frictionSecondsRemaining == 1 ? "" : "s") before the door opens"
        }
        if frictionState.level >= 2, selectedUrge == nil { return "What pulled you back?" }
        if lateNightActive, !acceptsSleepTradeoff { return "One more check before you continue" }
        return "The door is open"
    }

    // MARK: - Top bar

    private func flowTopBar(step number: Int) -> some View {
        HStack {
            MivoEyebrow(text: "Step \(number) of 2")
            Spacer()
            Button("Not now") {
                walkAway()
            }
            .font(.system(size: 13.5, weight: .bold))
            .foregroundColor(MivoColors.deep)
        }
        .padding(.top, 56)
    }

    // MARK: - Actions

    private func beginPause(intention: Intention, duration: Int) {
        selectedUrge = nil
        acceptsSleepTradeoff = lastScrollSelected
        frictionAttemptID = nil
        frictionAttemptResolved = false
        pauseReady = false

        let standardState = InterventionFrictionTracker.registerAttempt()
        frictionState = appVM.interventionFrictionState(from: standardState)
        frictionSecondsRemaining = frictionState.waitSeconds
        frictionAttemptID = appVM.recordInterventionAttempt()

        // Keep every selected app shielded for the full pause. The active
        // session is not created until the countdown has genuinely finished.
        FamilyControlsManager.shared.prepareForSessionStartPause()
        withAnimation(MivoMotion.stepEnter) { step = .pause }
    }

    private var canStart: Bool {
        pauseReady
            && (frictionState.level < 2 || selectedUrge != nil)
            && (!lateNightActive || acceptsSleepTradeoff)
    }

    private func startIfReady() {
        guard canStart, let selectedIntention, let selectedDuration else { return }
        if lastScrollSelected {
            appVM.markLastScrollOfNightStarted()
        }
        if let frictionAttemptID {
            frictionAttemptResolved = true
            appVM.resolveInterventionAttempt(id: frictionAttemptID, continued: true)
        }
        HapticsService.success()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
            activeLaunch = FlowLaunch(intention: selectedIntention, duration: selectedDuration, urgeReason: selectedUrge)
        }
    }

    private func chooseReplacement() {
        walkAway()
    }

    /// "Not now" / "I've changed my mind" from any step, or closing without
    /// starting. Logged as a walk-away — this is the metric the Interventions
    /// tab's week stat row reads, so it has to be recorded, not discarded.
    private func walkAway() {
        if let frictionAttemptID, !frictionAttemptResolved {
            frictionAttemptResolved = true
            appVM.resolveInterventionAttempt(id: frictionAttemptID, continued: false)
        }
        appVM.dismissMivoLaunchGate()
        FamilyControlsManager.shared.cancelSessionStartPauseAndRelock()
        HapticsService.success()
        onFinished()
        dismiss()
    }

    private func refreshDurationLimit() {
        cachedDurationLimit = appVM.adaptiveSessionDurationLimit()
    }

    private func offerMivoClearIfOutsideWindow() {
        guard cachedDurationLimit.maxMinutes == 0, expansion.isEnabled(.mivoClear) else { return }
        showOutsideWindowClearPrompt = true
    }

    // MARK: - Outside-window Clear prompt

    private var outsideWindowClearPrompt: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 12) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
                    .background(MivoColors.accent)
                    .clipShape(RoundedRectangle(cornerRadius: MivoMetrics.radius))
                VStack(alignment: .leading, spacing: 3) {
                    Text("Outside your scroll window")
                        .font(.system(size: 21, weight: .bold))
                        .foregroundColor(MivoColors.ink)
                    Text("Your scrolling apps stay protected.")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(MivoColors.inkBody)
                }
            }

            Text("Need to text, search, or watch a longer YouTube video? Use Mivo Clear without opening the endless feed.")
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(MivoColors.inkBody)
                .lineSpacing(4)

            MivoPrimaryButton(label: "Open Mivo Clear") {
                HapticsService.selection()
                showOutsideWindowClearPrompt = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                    showMivoClear = true
                }
            }

            MivoTertiaryButton(label: "Stay here", color: MivoColors.inkMuted) {
                showOutsideWindowClearPrompt = false
            }
        }
        .padding(22)
    }
}

/// The 5-second pause stage: a breathing radial glow behind a countdown
/// numeral, per §4.3. `accessibilityReduceMotion` swaps the breathing loop for
/// a static ring — the countdown itself still ticks either way. Also reused
/// by `MidScrollCheckInView` for the shield's mid-session pause.
struct PauseBreathingStage: View {
    let secondsRemaining: Int
    let totalSeconds: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var breathe = false

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [MivoColors.accent.opacity(0.34), .clear],
                        center: .center, startRadius: 0, endRadius: 105
                    )
                )
                .scaleEffect(breathe ? 1.14 : 1.0)
                .opacity(breathe ? 0.9 : 0.5)

            Circle()
                .inset(by: 38)
                .strokeBorder(MivoColors.accent.opacity(0.40), lineWidth: 1)
                .opacity(breathe ? 0.7 : 0.35)

            Text("\(max(secondsRemaining, 0))")
                .font(.system(size: 84, weight: .bold))
                .monospacedDigit()
                .tracking(Font.mivoTracking(-0.04, at: 84))
                .foregroundColor(Color(hex: "#FAF3E8"))
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: true)) {
                breathe = true
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(totalSeconds) seconds remaining")
    }
}
