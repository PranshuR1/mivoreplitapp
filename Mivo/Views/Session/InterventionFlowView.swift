import SwiftUI
import Combine

private let flowDurations: [Int] = [5, 10, 15, 30]

/// §4 Intervention flow, now starting with which app:
/// - A `SocialApp` opens inside Mivo: app → what for (`AppPurpose`) → reason →
///   how many or how long → pause → `AppWrapperView`. Messages skip straight
///   in: they're unlimited, and nothing but messages is reachable.
/// - Anything else (another app, or Snapchat chat, which the web can't do):
///   app → reason → duration → pause → active → reflect, per
///   `INTERACTIONS.md`. Active and reflect are the existing
///   `ActiveSessionView` and `ReflectionView`, presented unchanged.
///
/// Each app's last purpose and amount are remembered (`AppPickStore`), so a
/// repeat visit is mostly Continue.
///
/// The pause step also carries mechanics the design spec doesn't describe but
/// that were kept intentionally: friction escalates on repeated openings
/// (asks what pulled you back, then offers a replacement action), a late-night
/// gate asks for a deliberate yes before unlocking, and a duration cap can
/// redirect to messages in Mivo when no window is open. These render as a
/// light panel under the breathing glow rather than disappearing.
struct InterventionFlowView: View {
    @EnvironmentObject var appVM: AppViewModel
    @ObservedObject private var expansion = ProductExpansionStore.shared
    @ObservedObject private var companion = CompanionStateManager.shared
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var plus = MivoPlusStore.shared
    var onFinished: () -> Void
    /// Set when a shield on a known app opened the flow: the app step is skipped.
    private let preselectedApp: SocialApp?

    private enum FlowStep { case app, purpose, reason, duration, amount, pause }

    /// A social app opens inside Mivo; anything else opens natively for a timed window.
    private enum AppChoice: Equatable {
        case social(SocialApp)
        case other
    }

    @State private var step: FlowStep
    @State private var appChoice: AppChoice?
    @State private var selectedPurpose: AppPurpose?
    @State private var selectedAmount: Int?
    @State private var planPick: Int?
    @State private var balance = ReelBalanceStore.shared.current()
    @State private var wrapperLaunch: AppWindowConfig?
    @State private var selectedIntention: Intention?
    @State private var selectedDuration: Int?
    @State private var cachedDurationLimit: (maxMinutes: Int, isLimited: Bool, message: String, windowTitle: String) = (
        maxMinutes: 30, isLimited: false, message: "Checking your adaptive limit...", windowTitle: "Loading"
    )
    @State private var durationLimitNotice: String?

    @State private var showOutsideWindowClearPrompt = false
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

    init(preselectedApp: SocialApp? = nil, onFinished: @escaping () -> Void) {
        self.onFinished = onFinished
        self.preselectedApp = preselectedApp
        if let preselectedApp {
            _appChoice = State(initialValue: .social(preselectedApp))
            _selectedPurpose = State(initialValue: AppPickStore.lastPurpose(for: preselectedApp) ?? preselectedApp.purposes.first)
            _step = State(initialValue: .purpose)
        } else {
            _step = State(initialValue: .app)
        }
    }

    var body: some View {
        Group {
            switch step {
            case .app: appStep
            case .purpose: purposeStep
            case .reason: reasonStep
            case .duration: durationStep
            case .amount: amountStep
            case .pause: pauseStep
            }
        }
        .fullScreenCover(item: $wrapperLaunch, onDismiss: {
            onFinished()
            dismiss()
        }) { config in
            AppWrapperView(config: config)
                .environmentObject(appVM)
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
                    }
                )
                .environmentObject(appVM)
            }
        }
        .onAppear {
            refreshDurationLimit()
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

    // MARK: - Which app

    private var appStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            flowTopBar(.app)

            Text("Which app?")
                .font(.system(size: 27, weight: .bold))
                .tracking(Font.mivoTracking(-0.025, at: 27))
                .foregroundColor(MivoColors.ink)
                .padding(.top, 8)

            Text("These open inside Mivo, which keeps you to what you came for.")
                .font(.system(size: 13.5, weight: .medium))
                .foregroundColor(MivoColors.inkBody)
                .padding(.top, 8)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 9) {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 9), GridItem(.flexible(), spacing: 9)], spacing: 9) {
                        ForEach(SocialApp.allCases) { app in
                            appTile(icon: app.icon, title: app.title, isSelected: appChoice == .social(app)) {
                                choose(.social(app))
                            }
                        }
                    }
                    MivoOptionRow(
                        label: "Another app",
                        note: "Opens the app itself for a timed window",
                        isSelected: appChoice == .other,
                        fillsWhenSelected: true
                    ) {
                        choose(.other)
                    }
                }
                .padding(.top, 22)
                .padding(.bottom, 12)
            }

            MivoPrimaryButton(label: "Continue", disabled: appChoice == nil) {
                guard let appChoice else { return }
                withAnimation(MivoMotion.stepEnter) { step = appChoice == .other ? .reason : .purpose }
            }
            .padding(.top, 8)
            .padding(.bottom, 44)
        }
        .padding(.horizontal, MivoMetrics.screenPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(MivoColors.background.ignoresSafeArea())
        .transition(.opacity.combined(with: .move(edge: .trailing)))
    }

    private func appTile(icon: String, title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 20)
                Text(title)
                    .font(.system(size: 14.5, weight: .semibold))
                Spacer(minLength: 0)
            }
            .foregroundColor(isSelected ? MivoColors.background : MivoColors.ink)
            .padding(.horizontal, 14)
            .frame(height: 52)
            .background(isSelected ? MivoColors.ink : .clear)
            .clipShape(RoundedRectangle(cornerRadius: MivoMetrics.radius))
            .overlay(
                RoundedRectangle(cornerRadius: MivoMetrics.radius)
                    .strokeBorder(isSelected ? MivoColors.ink : MivoColors.ink.opacity(0.16), lineWidth: 1)
            )
        }
        .buttonStyle(MivoPressStyle())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func choose(_ choice: AppChoice) {
        HapticsService.selection()
        guard choice != appChoice else { return }
        appChoice = choice
        selectedAmount = nil
        if case .social(let app) = choice {
            selectedPurpose = AppPickStore.lastPurpose(for: app) ?? app.purposes.first
        } else {
            selectedPurpose = nil
        }
    }

    // MARK: - What for

    private var purposeStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            flowTopBar(.purpose)

            Text("What are you opening \(chosenApp?.title ?? "it") for?")
                .font(.system(size: 27, weight: .bold))
                .tracking(Font.mivoTracking(-0.025, at: 27))
                .foregroundColor(MivoColors.ink)
                .frame(maxWidth: 300, alignment: .leading)
                .padding(.top, 8)

            Text("Mivo remembers your answer for next time, and reminds you if you drift.")
                .font(.system(size: 13.5, weight: .medium))
                .foregroundColor(MivoColors.inkBody)
                .padding(.top, 8)

            VStack(spacing: 9) {
                ForEach(chosenApp?.purposes ?? []) { purpose in
                    MivoOptionRow(
                        label: purpose.title,
                        note: purposeNote(purpose),
                        isSelected: selectedPurpose?.id == purpose.id,
                        fillsWhenSelected: true
                    ) {
                        HapticsService.selection()
                        if selectedPurpose?.id != purpose.id { selectedAmount = nil }
                        selectedPurpose = purpose
                    }
                }
            }
            .padding(.top, 24)

            if let detail = selectedPurpose.map(purposeDetail), !detail.isEmpty {
                Text(detail)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundColor(MivoColors.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 14)
            }

            Spacer(minLength: 20)

            MivoPrimaryButton(label: purposeButtonLabel, disabled: selectedPurpose == nil) {
                guard let purpose = selectedPurpose, let app = chosenApp else { return }
                if purpose.kind == .messages {
                    // Unlimited and free: no reason, amount or pause.
                    HapticsService.success()
                    launchInMivo(app: app, purpose: purpose, amount: 0, reason: nil)
                } else {
                    withAnimation(MivoMotion.stepEnter) { step = .reason }
                }
            }
            .padding(.bottom, 44)
        }
        .padding(.horizontal, MivoMetrics.screenPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(MivoColors.background.ignoresSafeArea())
        .transition(.opacity.combined(with: .move(edge: .trailing)))
    }

    private func purposeNote(_ purpose: AppPurpose) -> String? {
        switch purpose.kind {
        case .count: return "Counted"
        case .minutes: return "Timed"
        case .messages: return "Unlimited"
        case .nativeApp: return "In the app"
        }
    }

    private func purposeDetail(_ purpose: AppPurpose) -> String {
        guard let app = chosenApp else { return purpose.detail }
        switch purpose.kind {
        case .count, .messages, .nativeApp:
            return purpose.detail
        case .minutes:
            return "All of \(app.title), timed. If you spend a while somewhere other than \(purpose.title.lowercased()), Mivo reminds you what you came for."
        }
    }

    private var purposeButtonLabel: String {
        guard let purpose = selectedPurpose, let app = chosenApp else { return "Continue" }
        return purpose.kind == .messages ? "Open \(app.title) messages" : "Continue"
    }

    // MARK: - How many, or how long

    private var amountStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            flowTopBar(.amount)

            Text(amountTitle)
                .font(.system(size: 27, weight: .bold))
                .tracking(Font.mivoTracking(-0.025, at: 27))
                .foregroundColor(MivoColors.ink)
                .padding(.top, 8)

            if let app = chosenApp, let purpose = selectedPurpose {
                Text("\(app.title) · \(purpose.title)")
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundColor(MivoColors.inkBody)
                    .padding(.top, 8)
            }

            VStack(spacing: 6) {
                Text("\(selectedAmount ?? 0)")
                    .font(.system(size: 72, weight: .bold))
                    .monospacedDigit()
                    .tracking(Font.mivoTracking(-0.045, at: 72))
                    .foregroundColor(MivoColors.ink)
                Text(amountUnit)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundColor(MivoColors.inkMuted)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 30)

            HStack(spacing: 7) {
                ForEach(amountOptions, id: \.self) { amount in
                    amountChip(amount)
                }
            }
            .padding(.top, 30)

            Text(amountAvailabilityText)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(startsSlowed || balance.isEmpty ? MivoColors.deep : MivoColors.inkBody)
                .padding(.top, 14)

            Text(amountExplainer)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundColor(MivoColors.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)

            if let replayText = replayStatusText {
                Text(replayText)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundColor(MivoColors.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)
            }

            Spacer(minLength: 20)

            MivoPrimaryButton(label: "Open \(chosenApp?.title ?? "it")", disabled: selectedAmount == nil) {
                guard let selectedIntention, let selectedAmount else { return }
                beginPause(intention: selectedIntention, duration: selectedAmount)
            }
            .padding(.bottom, 44)
        }
        .padding(.horizontal, MivoMetrics.screenPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(MivoColors.background.ignoresSafeArea())
        .transition(.opacity.combined(with: .move(edge: .trailing)))
    }

    private func amountChip(_ amount: Int) -> some View {
        let isSelected = selectedAmount == amount
        return Button {
            HapticsService.selection()
            selectedAmount = amount
        } label: {
            VStack(spacing: 1) {
                Text("\(amount)")
                    .font(.system(size: 14.5, weight: .semibold))
                    .monospacedDigit()
                if amount == planPick, selectedPurpose?.kind == .count {
                    Text("plan")
                        .font(.system(size: 9, weight: .bold))
                        .textCase(.uppercase)
                }
            }
            .foregroundColor(isSelected ? MivoColors.background : MivoColors.ink)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(isSelected ? MivoColors.ink : .clear)
            .clipShape(RoundedRectangle(cornerRadius: MivoMetrics.radius))
            .overlay(
                RoundedRectangle(cornerRadius: MivoMetrics.radius)
                    .strokeBorder(isSelected ? MivoColors.ink : MivoColors.ink.opacity(0.16), lineWidth: 1)
            )
        }
        .buttonStyle(MivoPressStyle())
    }

    private var amountTitle: String {
        guard let app = chosenApp, selectedPurpose?.kind == .count else { return "How long?" }
        return "How many \(app.shortVideoName.many)?"
    }

    private var amountUnit: String {
        guard let app = chosenApp, selectedPurpose?.kind == .count else { return "minutes" }
        return selectedAmount == 1 ? app.shortVideoName.one : app.shortVideoName.many
    }

    /// The fixed amounts, Mivo's plan pick for short videos, and whatever was
    /// picked last time.
    private var amountOptions: [Int] {
        let isCount = selectedPurpose?.kind == .count
        var options = isCount ? WrapperSessionLimit.reelOptions : WrapperSessionLimit.minuteOptions
        if isCount, let planPick, !options.contains(planPick) { options.append(planPick) }
        if let selectedAmount, !options.contains(selectedAmount) { options.append(selectedAmount) }
        return options.sorted()
    }

    private var startsSlowed: Bool { cachedDurationLimit.maxMinutes == 0 }

    private var amountAvailabilityText: String {
        if startsSlowed { return "Outside your scroll window: it opens slowed down." }
        if balance.isEmpty { return "That's today's time: it opens slowed down." }
        let minutes = balance.remainingMinutes
        return minutes == 1 ? "1 minute left today" : "\(minutes) minutes left today"
    }

    private var amountExplainer: String {
        guard let app = chosenApp, let purpose = selectedPurpose else { return "" }
        let amount = selectedAmount ?? 0
        switch purpose.kind {
        case .count:
            return "Only \(app.shortVideoName.many) open. After \(app.shortVideoCount(amount)), they go grey and quiet, and each one opens full screen after a short pause."
        case .minutes:
            return "After \(WrapperSessionLimit.minutes.title(amount: amount)), \(app.title) goes grey, quiet and slow. Nothing closes."
        case .messages, .nativeApp:
            return ""
        }
    }

    private var replayStatusText: String? {
        guard chosenApp == .instagram, selectedPurpose?.kind == .count else { return nil }
        guard MivoPlusAccess.allows(isPlus: plus.isPlus, isAdmin: appVM.isAdminUser) else { return "Replay mode is part of Mivo Plus." }
        guard ReplayModeSetting.isEnabled else { return "Replay mode is off. Turn it on from Home." }
        if appVM.adaptiveScreenTimePlan().collecting { return "Replay mode starts after your first 3 days, once Mivo has seen how you scroll." }
        return "Replay mode: once your Reels are used, you only see ones you've already watched."
    }

    /// Fresh balance and plan, and the amount picked last time for this app
    /// and purpose (or Mivo's plan for short videos).
    private func prepareAmount() {
        balance = ReelBalanceStore.shared.current()
        refreshDurationLimit()
        guard let app = chosenApp, let purpose = selectedPurpose else { return }
        planPick = purpose.kind == .count ? appVM.reelPlan()?.suggestedReelPick : nil
        if selectedAmount == nil {
            let fallback = purpose.kind == .count
                ? (planPick ?? WrapperSessionLimit.reelsPerSession)
                : WrapperSessionLimit.minutesPerSession
            selectedAmount = AppPickStore.lastAmount(for: app, purpose: purpose) ?? fallback
        }
    }

    // MARK: - Opening in Mivo

    private var chosenApp: SocialApp? {
        if case .social(let app) = appChoice { return app }
        return nil
    }

    /// True when the window opens inside Mivo rather than the native app.
    private var opensInMivo: Bool {
        chosenApp != nil && selectedPurpose?.runsInMivo == true
    }

    private var pauseSubtitle: String? {
        if opensInMivo, let app = chosenApp, let purpose = selectedPurpose {
            return "\(app.title) · \(purpose.title)"
        }
        return selectedIntention?.flowLabel
    }

    /// Opens the app in Mivo. The native app stays shielded: no session starts.
    private func launchInMivo(app: SocialApp, purpose: AppPurpose, amount: Int, reason: Intention?) {
        AppPickStore.save(app: app, purpose: purpose, amount: purpose.kind == .messages ? nil : amount)
        appVM.dismissMivoLaunchGate()
        wrapperLaunch = AppWindowConfig(
            app: app,
            purpose: purpose,
            amount: amount,
            reason: reason,
            startsSlowed: purpose.kind != .messages && startsSlowed
        )
    }

    /// The steps this path goes through, for "Step 2 of 4" and the back button.
    private var flowSteps: [FlowStep] {
        var steps: [FlowStep] = preselectedApp == nil ? [.app] : []
        switch appChoice {
        case .other:
            steps += [.reason, .duration]
        case .social:
            steps.append(.purpose)
            switch selectedPurpose?.kind {
            case .messages: break
            case .nativeApp: steps += [.reason, .duration]
            default: steps += [.reason, .amount]
            }
        case nil:
            steps += [.purpose, .reason, .amount]
        }
        return steps
    }

    private func goBack(from current: FlowStep) {
        let steps = flowSteps
        guard let index = steps.firstIndex(of: current), index > 0 else { return }
        HapticsService.selection()
        withAnimation(MivoMotion.stepEnter) { step = steps[index - 1] }
    }

    // MARK: - 4.1 Reason

    private var reasonStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            flowTopBar(.reason)

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
                if opensInMivo {
                    prepareAmount()
                    withAnimation(MivoMotion.stepEnter) { step = .amount }
                } else {
                    withAnimation(MivoMotion.stepEnter) { step = .duration }
                }
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
            flowTopBar(.duration)

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
        if redirectsToClear { return "Outside your scroll window" }
        guard let selectedDuration, let selectedIntention else { return "Choose a length" }
        return "Open \(appName(for: selectedIntention)) for \(selectedDuration) min"
    }

    /// The design copy interpolates an app name ("Open Snapchat for 15 min").
    /// A native session isn't tied to one app in this data model — see the
    /// same note on `InterventionsView.sessionMeta` — so "it" unless the app
    /// step named one.
    private func appName(for intention: Intention) -> String {
        if case .social(let app) = appChoice { return app.title }
        return "it"
    }

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

            if let pauseSubtitle {
                Text(pauseSubtitle)
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

            if lastScrollAvailable, !opensInMivo {
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

    private func flowTopBar(_ current: FlowStep) -> some View {
        let steps = flowSteps
        let number = (steps.firstIndex(of: current) ?? 0) + 1
        return HStack(spacing: 10) {
            if number > 1 {
                Button {
                    goBack(from: current)
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(MivoColors.deep)
                        .frame(width: 28, height: 28)
                }
                .accessibilityLabel("Back")
            }
            MivoEyebrow(text: "Step \(number) of \(steps.count)")
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
        guard canStart, let selectedIntention else { return }
        if opensInMivo {
            guard case .social(let app) = appChoice, let purpose = selectedPurpose, let amount = selectedAmount else { return }
            if let frictionAttemptID {
                frictionAttemptResolved = true
                appVM.resolveInterventionAttempt(id: frictionAttemptID, continued: true)
            }
            HapticsService.success()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
                launchInMivo(app: app, purpose: purpose, amount: amount, reason: selectedIntention)
            }
            return
        }
        guard let selectedDuration else { return }
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

            Text("Need to reply to someone? Messages open in Mivo any time, as long as you need, with nothing else reachable.")
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(MivoColors.inkBody)
                .lineSpacing(4)

            MivoPrimaryButton(label: "Open messages in Mivo") {
                HapticsService.selection()
                showOutsideWindowClearPrompt = false
                appChoice = nil
                selectedPurpose = nil
                withAnimation(MivoMotion.stepEnter) { step = .app }
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
