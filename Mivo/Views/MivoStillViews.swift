import SwiftUI

/// Home's entry point for Still — a `MivoNavigationRow` matching the
/// experiment and Mivo Clear rows.
struct MivoStillRow: View {
    @ObservedObject private var store = MivoStillStore.shared
    let action: () -> Void

    var body: some View {
        MivoNavigationRow(action: action) {
            Text("Mivo Still")
                .font(.system(size: 15.5, weight: .semibold))
                .foregroundColor(MivoColors.ink)
            Text(meta)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundColor(MivoColors.inkMuted)
        }
    }

    private var meta: String {
        let streak = store.currentStreakDays
        if store.minutesToday > 0 {
            let streakSuffix = streak > 1 ? " · \(streak)-day streak" : ""
            return "\(store.minutesToday)m still today\(streakSuffix)"
        }
        return "Put your phone face-down and focus"
    }
}

/// The full session flow: pick a duration, place the phone, hold still, and a
/// result. One view switching on `monitor.phase` rather than separate covers,
/// so there is a single continuous animation rather than a fresh sheet
/// transition between phases.
struct MivoStillFlowView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appVM: AppViewModel
    @ObservedObject private var store = MivoStillStore.shared
    @StateObject private var monitor = MivoStillMotionMonitor()

    @State private var selectedMinutes = 25
    @State private var started = false
    @State private var recorded = false
    @State private var breathing = false
    @State private var lockModeEnabled = false
    @State private var showLockStillActiveNotice = false
    @State private var showTutorial = false
    @State private var lockModeMinutesText = "15"
    /// Snapshotted at the moment Lock Mode actually starts, so later screens
    /// (result, stats) stay correct even though the text field itself is
    /// gone by then.
    @State private var activeLockMinutes = 15

    private static let durationOptions: [(value: Int, label: String)] = [
        (15, "15 min"), (25, "25 min"), (45, "45 min"), (60, "60 min")
    ]
    private static let lockModeMinMinutes = 1
    private static let lockModeMaxMinutes = 180

    var body: some View {
        ZStack {
            MivoColors.background.ignoresSafeArea()

            if !started {
                setupScreen
            } else if !monitor.isAvailable {
                unavailableScreen
            } else {
                switch monitor.phase {
                case .waitingToSettle(let elapsed):
                    settlingScreen(elapsed: elapsed)
                case .active(let remaining, let pickups):
                    activeScreen(remaining: remaining, pickups: pickups, disturbed: false)
                case .disturbed(let remaining, let pickups, _, _):
                    activeScreen(remaining: remaining, pickups: pickups, disturbed: true)
                case .completed:
                    resultScreen()
                }
            }
        }
        .animation(MivoMotion.standard(0.28), value: phaseIdentity)
        // While a Lock Mode run is counting down there is no way off this
        // screen — no swipe, no button. The timer is the only exit.
        .interactiveDismissDisabled(isLockRunInProgress)
        .onAppear {
            breathing = true
            restoreLockModeRunIfNeeded()
            Task {
                await store.prepare(for: appVM)
                guard !started, !store.hasCompletedTutorial() else { return }
                showTutorial = true
            }
        }
        .onDisappear {
            if started {
                monitor.stop()
                CompanionInterventionAdapter.focusEnded(completed: false)
                endFocusLiveActivityUnlessLocked()
            }
        }
        .onChange(of: monitor.phase) { _, newPhase in
            if newPhase.isTerminal { recordIfNeeded(newPhase) }
        }
        .alert("Your apps are still locked", isPresented: $showLockStillActiveNotice) {
            Button("OK") { dismiss() }
        } message: {
            Text("Mivo Still's Lock Mode isn't tied to this screen — \(FamilyControlsManager.shared.stillLockRemainingMinutes())m left before your apps unlock.")
        }
        .fullScreenCover(isPresented: $showTutorial) {
            MivoStillTutorialView {
                store.completeTutorial()
                showTutorial = false
            }
            .interactiveDismissDisabled()
        }
    }

    /// A coarse key for the animation trigger — the exact countdown value
    /// changing every 200ms should not itself cross-fade the screen.
    private var phaseIdentity: String {
        guard started else { return "setup" }
        switch monitor.phase {
        case .waitingToSettle: return "settling"
        case .active: return "active"
        case .disturbed: return "disturbed"
        case .completed: return "completed"
        }
    }

    // MARK: Setup

    private var setupScreen: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(MivoColors.inkMuted)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Close")
                Spacer()
            }
            .padding(.top, 8)

            MivoEyebrow(text: "MIVO STILL")
                .padding(.top, 18)

            Text("Put your phone down and focus")
                .font(.system(size: 27, weight: .bold))
                .tracking(Font.mivoTracking(-0.025, at: 27))
                .foregroundColor(MivoColors.ink)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)

            Text("Choose how long. The countdown only moves while it's face-down and still — pick it up and it pauses, never ends. It also only runs while you're in Mivo.")
                .font(.system(size: 13.5, weight: .medium))
                .foregroundColor(MivoColors.inkBody)
                .lineSpacing(13.5 * 0.55)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)

            if lockModeEnabled {
                lockModeDurationField
                    .padding(.top, 26)
            } else {
                MivoChoiceChips(options: Self.durationOptions, selection: $selectedMinutes)
                    .padding(.top, 26)
            }

            lockModeSection
                .padding(.top, 18)

            if store.minutesToday > 0 {
                HStack(spacing: 6) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(MivoColors.deep)
                    Text("\(store.minutesToday) min still today\(store.currentStreakDays > 1 ? " · \(store.currentStreakDays)-day streak" : "")")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundColor(MivoColors.inkBody)
                }
                .padding(.top, 16)
            }

            Spacer(minLength: 20)

            MivoPrimaryButton(label: "Start Still session", disabled: lockModeEnabled && !lockModeMinutesValid) {
                HapticsService.impact(style: .medium)
                started = true
                if lockModeEnabled {
                    activeLockMinutes = lockModeMinutesValue
                    _ = FamilyControlsManager.shared.activateStillLock(durationSeconds: activeLockMinutes * 60)
                    monitor.start(plannedSeconds: Double(activeLockMinutes * 60))
                    CompanionInterventionAdapter.focusBegan(endsAt: Date().addingTimeInterval(Double(activeLockMinutes * 60)))
                    startFocusLiveActivity(minutes: activeLockMinutes)
                } else {
                    monitor.start(plannedSeconds: Double(selectedMinutes * 60))
                    CompanionInterventionAdapter.focusBegan(endsAt: Date().addingTimeInterval(Double(selectedMinutes * 60)))
                    startFocusLiveActivity(minutes: selectedMinutes)
                }
            }
            .padding(.bottom, 24)
        }
        .padding(.horizontal, MivoMetrics.screenPadding)
    }

    private var lockModeMinutesValue: Int { Int(lockModeMinutesText) ?? 0 }
    private var lockModeMinutesValid: Bool {
        (Self.lockModeMinMinutes...Self.lockModeMaxMinutes).contains(lockModeMinutesValue)
    }

    private var lockModeDurationField: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text("Lock for exactly")
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundColor(MivoColors.inkBody)

                TextField("15", text: $lockModeMinutesText)
                    .keyboardType(.numberPad)
                    .font(.system(size: 18, weight: .bold))
                    .monospacedDigit()
                    .foregroundColor(MivoColors.ink)
                    .multilineTextAlignment(.center)
                    .frame(width: 56)
                    .padding(.vertical, 8)
                    .background(MivoColors.ink.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(lockModeMinutesValid ? MivoColors.ink.opacity(0.16) : MivoColors.deep, lineWidth: 1)
                    )
                    .onChange(of: lockModeMinutesText) { _, newValue in
                        let digitsOnly = String(newValue.filter(\.isNumber).prefix(3))
                        if digitsOnly != newValue { lockModeMinutesText = digitsOnly }
                    }

                Text("minutes")
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundColor(MivoColors.inkBody)

                Spacer()
            }

            if !lockModeMinutesValid {
                Text("Choose \(Self.lockModeMinMinutes)–\(Self.lockModeMaxMinutes) minutes.")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundColor(MivoColors.deep)
            }
        }
    }

    @ViewBuilder
    private var lockModeSection: some View {
        let authorized = FamilyControlsManager.shared.cachedAuthorizationStatus() == true
        Toggle(isOn: Binding(
            get: { lockModeEnabled },
            set: { newValue in
                guard authorized else { return }
                lockModeEnabled = newValue
            }
        )) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Lock Mode")
                    .font(.system(size: 14.5, weight: .semibold))
                    .foregroundColor(MivoColors.ink)
                Text(authorized
                     ? "Every app locks for exactly the time you set below. No early exit — the timer is the only way back in."
                     : "Needs Screen Time access. Grant it in Settings to use Lock Mode.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(MivoColors.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .tint(MivoColors.accent)
        .disabled(!authorized)
    }

    private var unavailableScreen: some View {
        resultLayout(
            icon: "exclamationmark.triangle.fill",
            iconColor: MivoColors.accent,
            title: "Not available on this device",
            detail: "Mivo Still needs motion sensors this device or simulator doesn't report.",
            statLine: nil,
            primaryLabel: "Done",
            primaryAction: { dismiss() },
            secondaryLabel: nil,
            secondaryAction: nil
        )
    }

    // MARK: Settling

    private func settlingScreen(elapsed: TimeInterval) -> some View {
        VStack(spacing: 18) {
            Spacer()

            ZStack {
                Circle()
                    .stroke(MivoColors.ink.opacity(0.10), lineWidth: 4)
                    .frame(width: 116, height: 116)
                Circle()
                    .trim(from: 0, to: min(1, elapsed / MivoStillEngine.settleDuration))
                    .stroke(MivoColors.accent, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .frame(width: 116, height: 116)
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.15), value: elapsed)
                Image(systemName: "arrow.down.to.line.compact")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundColor(MivoColors.ink)
            }

            Text("Place your phone face-down")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(MivoColors.ink)
                .multilineTextAlignment(.center)

            Text("Somewhere you can't easily reach it. The timer starts once it's still.")
                .font(.system(size: 13.5, weight: .medium))
                .foregroundColor(MivoColors.inkBody)
                .multilineTextAlignment(.center)
                .lineSpacing(13.5 * 0.55)
                .frame(maxWidth: 280)

            Spacer()

            // Cancelling is still allowed before the timer starts — Lock Mode
            // has not begun counting yet at this point. Once it does, the
            // active screen offers no way out.
            MivoTertiaryButton(label: "Cancel") {
                endSessionTapped()
            }
            .padding(.bottom, 16)
        }
        .padding(.horizontal, MivoMetrics.screenPadding)
    }

    // MARK: Active / disturbed

    private func activeScreen(remaining: TimeInterval, pickups: Int, disturbed: Bool) -> some View {
        VStack(spacing: 22) {
            Spacer()

            ZStack {
                Circle()
                    .fill(MivoColors.accent.opacity(0.12))
                    .frame(width: 210, height: 210)
                    .scaleEffect(breathing ? 1.06 : 0.94)
                    .opacity(breathing ? 1 : 0.7)
                    .animation(.easeInOut(duration: 2).repeatForever(autoreverses: true), value: breathing)

                VStack(spacing: 6) {
                    Text(countdownText(remaining))
                        .font(.system(size: 52, weight: .bold))
                        .monospacedDigit()
                        .tracking(Font.mivoTracking(-0.04, at: 52))
                        .foregroundColor(MivoColors.ink)
                    Text("Locked in")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(MivoColors.deep)
                }
            }

            Text(activeSubline(disturbed: disturbed))
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundColor(disturbed ? MivoColors.deep : MivoColors.inkBody)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 260)
                .animation(.easeInOut(duration: 0.2), value: disturbed)

            Spacer()

            if pickups > 0 {
                Text("\(pickups) pickup\(pickups == 1 ? "" : "s") so far")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundColor(MivoColors.inkMuted)
            }

            // Lock Mode is a commitment: the run has to finish. Without an
            // exit button here the timer is the only way out, which is the
            // whole point of turning it on.
            if !lockModeEnabled {
                MivoTertiaryButton(label: "End session") {
                    endSessionTapped()
                }
                .padding(.bottom, 16)
            }
        }
        .padding(.horizontal, MivoMetrics.screenPadding)
    }

    private func activeSubline(disturbed: Bool) -> String {
        if disturbed {
            // The countdown is frozen right now, not still running — see
            // MivoStillEngine.advance. Lock Mode's own device-wide block is
            // the one thing that keeps going regardless, which is worth
            // saying explicitly so picking it up doesn't look consequence-free.
            return lockModeEnabled
                ? "Timer's paused. Your apps stay locked either way."
                : "Timer's paused — put it back down to keep it moving."
        }
        return "Keep your phone face-down until this reaches zero."
    }

    // MARK: Result

    /// Only ever reached by the countdown hitting zero — a session has no
    /// other ending.
    private func resultScreen() -> some View {
        let plannedMinutes = lockModeEnabled ? activeLockMinutes : selectedMinutes
        let streak = store.currentStreakDays
        return resultLayout(
            icon: "checkmark.seal.fill",
            iconColor: MivoColors.kept,
            title: "Session complete",
            // Going over a window elsewhere in Mivo is never framed as a
            // failure, and finishing here gets the same plain treatment —
            // a fact, not a reward speech.
            detail: streak > 1 ? "\(streak)-day streak." : "Nicely done.",
            statLine: "\(plannedMinutes) min complete",
            primaryLabel: "Done",
            primaryAction: { dismiss() },
            secondaryLabel: "Start another",
            secondaryAction: { resetToSetup() }
        )
    }

    private func resultLayout(
        icon: String,
        iconColor: Color,
        title: String,
        detail: String,
        statLine: String?,
        primaryLabel: String,
        primaryAction: @escaping () -> Void,
        secondaryLabel: String?,
        secondaryAction: (() -> Void)?
    ) -> some View {
        // Ending the Still session (this screen) is separate from Lock Mode's
        // device-wide block, which keeps running on its own timer regardless.
        let lockMinutesRemaining = lockModeEnabled ? FamilyControlsManager.shared.stillLockRemainingMinutes() : 0

        return VStack(spacing: 16) {
            Spacer()

            ZStack {
                Circle().fill(iconColor.opacity(0.14)).frame(width: 96, height: 96)
                Image(systemName: icon)
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundColor(iconColor)
            }

            Text(title)
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(MivoColors.ink)

            Text(detail)
                .font(.system(size: 13.5, weight: .medium))
                .foregroundColor(MivoColors.inkBody)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 270)

            if let statLine {
                Text(statLine)
                    .font(.system(size: 14.5, weight: .bold))
                    .monospacedDigit()
                    .foregroundColor(MivoColors.deep)
                    .padding(.top, 6)
            }

            if lockMinutesRemaining > 0 {
                Text("Your apps are still locked for \(lockMinutesRemaining)m more.")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundColor(MivoColors.deep)
                    .multilineTextAlignment(.center)
                    .padding(.top, 4)
            }

            Spacer()

            MivoPrimaryButton(label: primaryLabel, action: primaryAction)

            if let secondaryLabel, let secondaryAction {
                MivoTertiaryButton(label: secondaryLabel, action: secondaryAction)
            }
        }
        .padding(.horizontal, MivoMetrics.screenPadding)
        .padding(.bottom, 24)
    }

    // MARK: Helpers

    private func countdownText(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    /// True from the moment a Lock Mode countdown starts until it reaches
    /// zero. Everything that could cut the run short is gated on this.
    private var isLockRunInProgress: Bool {
        started && lockModeEnabled && !monitor.phase.isTerminal
    }

    /// A Lock Mode run outlives this screen: the block itself is enforced by
    /// `FamilyControlsManager` against a stored end time, so if Mivo was
    /// closed and reopened mid-run the timer has to come back rather than
    /// dropping the user on the setup screen while their apps are still
    /// locked.
    private func restoreLockModeRunIfNeeded() {
        guard !started,
              FamilyControlsManager.shared.isStillLockActive() else { return }
        let remaining = FamilyControlsManager.shared.stillLockRemainingSeconds()
        guard remaining > 0 else { return }
        lockModeEnabled = true
        activeLockMinutes = FamilyControlsManager.shared.stillLockPlannedMinutes()
        lockModeMinutesText = String(activeLockMinutes)
        recorded = false
        started = true
        monitor.start(plannedSeconds: remaining)
        CompanionInterventionAdapter.focusBegan(endsAt: Date().addingTimeInterval(remaining))
        startFocusLiveActivity(minutes: max(1, Int((remaining / 60).rounded(.up))), endsAt: Date().addingTimeInterval(remaining))
    }

    /// Lock Mode keeps blocking apps after the screen closes, so its countdown
    /// stays up until `endStillLock()` ends it.
    private func endFocusLiveActivityUnlessLocked() {
        if !FamilyControlsManager.shared.isStillLockActive() {
            FamilyControlsManager.shared.endFocusLiveActivity()
        }
    }

    /// Shows the countdown (and the companion, if on) on the Lock Screen and
    /// Dynamic Island for the length of the Still run. Same opt-in rollout flag
    /// as Mivo's session Live Activity — this reuses that activity, it doesn't add another.
    private func startFocusLiveActivity(minutes: Int, endsAt: Date? = nil) {
        guard ProductExpansionStore.shared.isEnabled(.liveActivities) else { return }
        FamilyControlsManager.shared.startSessionLiveActivity(
            sessionEndsAt: endsAt ?? Date().addingTimeInterval(Double(minutes * 60)),
            planMinutes: minutes,
            intentionLabel: "Mivo Still",
            kind: "focus"
        )
    }

    private func resetToSetup() {
        recorded = false
        started = false
        // Lock Mode is a deliberate, heavy commitment — require it to be
        // switched on again explicitly rather than carrying over silently.
        lockModeEnabled = false
    }

    /// Ending the Still session UI is separate from Lock Mode's device-wide
    /// block, which is enforced independently and keeps running on its own
    /// timer. This just makes that explicit before dismissing.
    private func endSessionTapped() {
        monitor.stop()
        // A completed session was already reported by `recordIfNeeded`; this
        // closes any that is leaving early. Ending early is never held against anyone.
        CompanionInterventionAdapter.focusEnded(completed: false)
        endFocusLiveActivityUnlessLocked()
        if lockModeEnabled, FamilyControlsManager.shared.isStillLockActive() {
            showLockStillActiveNotice = true
        } else {
            dismiss()
        }
    }

    private func recordIfNeeded(_ phase: MivoStillPhase) {
        guard !recorded else { return }
        recorded = true

        // `.completed` is the only phase that terminates a session, so
        // reaching here at all means the countdown ran out.
        guard case .completed = phase else { return }
        let outcome: MivoStillOutcome = .completed

        // Lock Mode's device-wide shield also lifts on its own schedule (see
        // `FamilyControlsManager.activateStillLock`), but that relies on the
        // OS waking a background extension or task, which can lag by seconds
        // to minutes. The app is right here watching the countdown hit zero,
        // so unlock immediately instead of making the user wait on that.
        if lockModeEnabled {
            FamilyControlsManager.shared.endStillLock()
        }

        let now = Date()
        let startedAt = now.addingTimeInterval(-monitor.elapsedActiveSeconds)
        let plannedMinutes = lockModeEnabled ? activeLockMinutes : selectedMinutes
        let session = MivoStillSession(
            id: UUID().uuidString.lowercased(),
            date: MivoDay.key(startedAt),
            startedAt: ISO8601DateFormatter().string(from: startedAt),
            endedAt: ISO8601DateFormatter().string(from: now),
            plannedSeconds: plannedMinutes * 60,
            actualSeconds: Int(monitor.elapsedActiveSeconds.rounded()),
            pickupCount: monitor.pickupCount,
            outcome: outcome,
            lockModeUsed: lockModeEnabled
        )
        store.record(session)
        CompanionInterventionAdapter.focusEnded(completed: true)
        FamilyControlsManager.shared.endFocusLiveActivity()
        HapticsService.impact(style: .medium)
        if outcome == .completed {
            HapticsService.success()
        }
    }
}

private struct MivoStillTutorialView: View {
    private struct Page: Identifiable {
        let id: Int
        let eyebrow: String
        let title: String
        let detail: String
        let systemImage: String
    }

    private let pages = [
        Page(
            id: 0,
            eyebrow: "PLACE",
            title: "Put your phone face-down",
            detail: "Mivo Still starts only when the phone is face-down and resting somewhere you cannot casually grab it.",
            systemImage: "arrow.down.to.line.compact"
        ),
        Page(
            id: 1,
            eyebrow: "COUNT",
            title: "Time moves only while it stays still",
            detail: "Pick it up and the countdown pauses. Put it back down and the timer continues from where you left off.",
            systemImage: "pause.circle.fill"
        ),
        Page(
            id: 2,
            eyebrow: "LOCK",
            title: "Lock Mode is stricter",
            detail: "With Screen Time access, Lock Mode blocks apps for the exact time you choose. No early exit from inside Mivo.",
            systemImage: "lock.fill"
        ),
        Page(
            id: 3,
            eyebrow: "FINISH",
            title: "Finish the timer to complete the session",
            detail: "Mivo records the focused minutes and pickups so your quiet time shows up in your progress.",
            systemImage: "checkmark.seal.fill"
        )
    ]

    let finish: () -> Void

    @State private var page = 0
    @State private var isAnimating = false

    var body: some View {
        ZStack {
            MivoColors.background.ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    Label("Mivo Still", systemImage: "arrow.down.to.line.compact")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(MivoColors.ink)
                    Spacer()
                    if page < pages.count - 1 {
                        Button("Skip") { completeTutorial() }
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(MivoColors.inkMuted)
                    }
                }
                .padding(.horizontal, 22)
                .padding(.top, 14)

                TabView(selection: $page) {
                    ForEach(pages) { item in
                        tutorialPage(item)
                            .tag(item.id)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                HStack(spacing: 7) {
                    ForEach(pages) { item in
                        Capsule()
                            .fill(item.id == page ? MivoColors.accent : MivoColors.border.opacity(0.45))
                            .frame(width: item.id == page ? 26 : 7, height: 7)
                            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: page)
                    }
                }
                .padding(.bottom, 20)

                Button(action: advance) {
                    HStack(spacing: 10) {
                        Text(page == pages.count - 1 ? "Start Mivo Still" : "Next")
                        Image(systemName: "arrow.right")
                    }
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(MivoColors.heroText)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(MivoColors.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 22)
                .padding(.bottom, 16)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.65, dampingFraction: 0.72)) {
                isAnimating = true
            }
        }
        .onChange(of: page) { _, _ in
            HapticsService.selection()
        }
    }

    private func tutorialPage(_ item: Page) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 22)

            tutorialVisual(systemImage: item.systemImage)
                .frame(maxWidth: .infinity)
                .scaleEffect(isAnimating ? 1 : 0.92)
                .opacity(isAnimating ? 1 : 0)

            Spacer(minLength: 28)

            Text(item.eyebrow)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(MivoColors.accent)
            Text(item.title)
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundColor(MivoColors.ink)
                .padding(.top, 8)
                .fixedSize(horizontal: false, vertical: true)
            Text(item.detail)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(MivoColors.inkBody)
                .lineSpacing(4)
                .padding(.top, 12)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 20)
        }
        .padding(.horizontal, 24)
    }

    private func tutorialVisual(systemImage: String) -> some View {
        ZStack {
            Circle()
                .fill(MivoColors.accent.opacity(0.10))
                .frame(width: 226, height: 226)
            Circle()
                .stroke(MivoColors.accent.opacity(0.24), lineWidth: 2)
                .frame(width: 174, height: 174)
            Circle()
                .trim(from: 0.10, to: 0.86)
                .stroke(MivoColors.accent, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .frame(width: 158, height: 158)
                .rotationEffect(.degrees(-90))
            Image(systemName: systemImage)
                .font(.system(size: 44, weight: .semibold))
                .foregroundColor(MivoColors.ink)
        }
        .frame(height: 250)
        .accessibilityHidden(true)
    }

    private func advance() {
        HapticsService.impact(style: .medium)
        guard page < pages.count - 1 else {
            completeTutorial()
            return
        }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
            page += 1
        }
    }

    private func completeTutorial() {
        HapticsService.success()
        finish()
    }
}

#if DEBUG
/// Deterministic capture states for App Store artwork. The real Still flow is
/// driven by Core Motion, which the simulator cannot reproduce reliably. This
/// view deliberately uses the same tokens, components and copy as the shipped
/// flow while replacing only the sensor-driven state with launch arguments.
struct MivoStillAppStorePreviewView: View {
    private enum Phase: String {
        case setup, faceDown, active, paused, lockMode, complete
    }

    private let phase: Phase

    init() {
        let arguments = ProcessInfo.processInfo.arguments
        if let flag = arguments.firstIndex(of: "-MivoPreviewStillPhase"),
           arguments.indices.contains(flag + 1),
           let requested = Phase(rawValue: arguments[flag + 1]) {
            phase = requested
        } else {
            phase = .setup
        }
    }

    var body: some View {
        ZStack {
            MivoColors.background.ignoresSafeArea()
            switch phase {
            case .setup:
                setupScreen(lockMode: false)
            case .faceDown:
                faceDownScreen
            case .active:
                countdownScreen(paused: false)
            case .paused:
                countdownScreen(paused: true)
            case .lockMode:
                setupScreen(lockMode: true)
            case .complete:
                completionScreen
            }
        }
    }

    private func setupScreen(lockMode: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(MivoColors.inkMuted)
                    .frame(width: 44, height: 44)
                Spacer()
            }
            .padding(.top, 8)

            MivoEyebrow(text: "MIVO STILL")
                .padding(.top, 18)

            Text("Put your phone down and focus")
                .font(.system(size: 27, weight: .bold))
                .tracking(Font.mivoTracking(-0.025, at: 27))
                .foregroundColor(MivoColors.ink)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)

            Text("Choose how long. The countdown only moves while it's face-down and still — pick it up and it pauses, never ends.")
                .font(.system(size: 13.5, weight: .medium))
                .foregroundColor(MivoColors.inkBody)
                .lineSpacing(7)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)

            if lockMode {
                HStack(spacing: 10) {
                    Text("Lock for exactly")
                        .font(.system(size: 13.5, weight: .medium))
                        .foregroundColor(MivoColors.inkBody)
                    Text("30")
                        .font(.system(size: 18, weight: .bold))
                        .monospacedDigit()
                        .foregroundColor(MivoColors.ink)
                        .frame(width: 56)
                        .padding(.vertical, 8)
                        .background(MivoColors.ink.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(MivoColors.ink.opacity(0.16)))
                    Text("minutes")
                        .font(.system(size: 13.5, weight: .medium))
                        .foregroundColor(MivoColors.inkBody)
                    Spacer()
                }
                .padding(.top, 26)
            } else {
                MivoChoiceChips(
                    options: [(15, "15 min"), (25, "25 min"), (45, "45 min"), (60, "60 min")],
                    selection: .constant(25)
                )
                .padding(.top, 26)
            }

            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Lock Mode")
                        .font(.system(size: 14.5, weight: .semibold))
                        .foregroundColor(MivoColors.ink)
                    Text(lockMode
                         ? "Every app locks for exactly the time you set. No early exit — the timer is the only way back in."
                         : "Optionally lock every app for the full session, with no early exit.")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(MivoColors.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 16)
                ZStack(alignment: lockMode ? .trailing : .leading) {
                    Capsule().fill(lockMode ? MivoColors.accent : MivoColors.ink.opacity(0.14))
                        .frame(width: 51, height: 31)
                    Circle().fill(Color.white)
                        .frame(width: 27, height: 27)
                        .padding(2)
                        .shadow(color: .black.opacity(0.12), radius: 1, y: 1)
                }
            }
            .padding(.top, 20)

            HStack(spacing: 6) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(MivoColors.deep)
                Text("50 min still today · 4-day streak")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundColor(MivoColors.inkBody)
            }
            .padding(.top, 18)

            Spacer(minLength: 20)

            MivoPrimaryButton(label: lockMode ? "Start 30-minute Lock Mode" : "Start Still session") {}
                .padding(.bottom, 24)
        }
        .padding(.horizontal, MivoMetrics.screenPadding)
    }

    private var faceDownScreen: some View {
        VStack(spacing: 18) {
            Spacer()
            ZStack {
                Circle()
                    .stroke(MivoColors.ink.opacity(0.10), lineWidth: 4)
                    .frame(width: 116, height: 116)
                Circle()
                    .trim(from: 0, to: 0.72)
                    .stroke(MivoColors.accent, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .frame(width: 116, height: 116)
                    .rotationEffect(.degrees(-90))
                Image(systemName: "arrow.down.to.line.compact")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundColor(MivoColors.ink)
            }
            Text("Place your phone face-down")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(MivoColors.ink)
            Text("Somewhere you can't easily reach it. The timer starts once it's still.")
                .font(.system(size: 13.5, weight: .medium))
                .foregroundColor(MivoColors.inkBody)
                .multilineTextAlignment(.center)
                .lineSpacing(7)
                .frame(maxWidth: 280)
            Spacer()
            MivoTertiaryButton(label: "Cancel") {}
                .padding(.bottom, 16)
        }
        .padding(.horizontal, MivoMetrics.screenPadding)
    }

    private func countdownScreen(paused: Bool) -> some View {
        VStack(spacing: 22) {
            Spacer()
            ZStack {
                Circle()
                    .fill((paused ? MivoColors.deep : MivoColors.accent).opacity(0.12))
                    .frame(width: 210, height: 210)
                Circle()
                    .stroke((paused ? MivoColors.deep : MivoColors.accent).opacity(0.34), lineWidth: 2)
                    .frame(width: 186, height: 186)
                VStack(spacing: 6) {
                    Text(paused ? "18:42" : "24:18")
                        .font(.system(size: 52, weight: .bold))
                        .monospacedDigit()
                        .tracking(Font.mivoTracking(-0.04, at: 52))
                        .foregroundColor(MivoColors.ink)
                    Text(paused ? "Timer paused" : "Locked in")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(MivoColors.deep)
                }
            }
            Text(paused
                 ? "Put it back down to keep the countdown moving."
                 : "Keep your phone face-down until this reaches zero.")
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundColor(paused ? MivoColors.deep : MivoColors.inkBody)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 270)
            if paused {
                HStack(spacing: 7) {
                    Image(systemName: "hand.raised.fill")
                    Text("1 pickup so far")
                }
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundColor(MivoColors.inkMuted)
            }
            Spacer()
            if !paused {
                Text("Notifications are quiet while you stay focused")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundColor(MivoColors.inkMuted)
                    .padding(.bottom, 26)
            }
        }
        .padding(.horizontal, MivoMetrics.screenPadding)
    }

    private var completionScreen: some View {
        VStack(spacing: 16) {
            Spacer()
            ZStack {
                Circle().fill(MivoColors.kept.opacity(0.14)).frame(width: 96, height: 96)
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundColor(MivoColors.kept)
            }
            Text("Session complete")
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(MivoColors.ink)
            Text("4-day streak.")
                .font(.system(size: 13.5, weight: .medium))
                .foregroundColor(MivoColors.inkBody)
            Text("25 min complete")
                .font(.system(size: 14.5, weight: .bold))
                .monospacedDigit()
                .foregroundColor(MivoColors.deep)
                .padding(.top, 6)
            HStack(spacing: 16) {
                previewStat(value: "100m", label: "this week")
                Rectangle().fill(MivoColors.hairline).frame(width: 1, height: 38)
                previewStat(value: "4", label: "day streak")
                Rectangle().fill(MivoColors.hairline).frame(width: 1, height: 38)
                previewStat(value: "1", label: "pickup")
            }
            .padding(.top, 22)
            Spacer()
            MivoPrimaryButton(label: "Done") {}
            MivoTertiaryButton(label: "Start another") {}
        }
        .padding(.horizontal, MivoMetrics.screenPadding)
        .padding(.bottom, 24)
    }

    private func previewStat(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 18, weight: .bold))
                .monospacedDigit()
                .foregroundColor(MivoColors.ink)
            Text(label)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundColor(MivoColors.inkMuted)
        }
        .frame(maxWidth: .infinity)
    }
}
#endif
