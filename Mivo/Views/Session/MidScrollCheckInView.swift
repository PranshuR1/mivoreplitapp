import SwiftUI

/// Presented when the ShieldAction extension's `requestMidScrollCheckIn()`
/// sets the pending flag mid-session (see `AppViewModel.checkMidScrollCheckInFlag`).
///
/// The countdown itself used to run inside the shield extension via chained
/// `DispatchQueue.main.asyncAfter` calls, which iOS could suspend at any
/// point since a `ShieldActionDelegate` is a short-lived service process
/// with no UI surface of its own — the number visibly stopped moving because
/// the extension itself had stopped running. Running it here instead, in the
/// full app process, gives it a real `Timer` and real animation.
///
/// The pause starts the instant this screen appears — the user already
/// made the explicit request by tapping the shield's "Open Mivo" button (or
/// the follow-up notification, which itself says "Tap to open Mivo for your
/// short pause timer"), so gating it behind a second in-app "Begin" tap was
/// pure friction: the countdown just sat frozen at its starting number,
/// which read as "there's no countdown at all" rather than "tap to start."
/// Once the pause finishes, a short recall step asks what the person thinks
/// they just saw (see `RecallPromptStage` below) before the session resumes —
/// see `AppViewModel.recordRecallCheckIn` for why this exists: iOS has no API
/// to count scrolls or read content inside another app, so instead of a
/// number Mivo can't actually get, it asks the person directly while it's
/// still fresh, then pairs that self-report against real numbers Mivo does
/// have (session length, `todayPerAppMinutes()`) on the Attention Receipt.
struct MidScrollCheckInView: View {
    @EnvironmentObject private var appVM: AppViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var secondsRemaining: Int
    private let totalSeconds: Int
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    @State private var showingRecall = false
    @State private var guessedCount = 4
    @State private var recalledText = ""
    @FocusState private var recallFieldFocused: Bool

    init(seconds: Int = 5) {
        let clamped = max(1, seconds)
        totalSeconds = clamped
        _secondsRemaining = State(initialValue: clamped)
    }

    var body: some View {
        ZStack {
            MivoColors.stage.ignoresSafeArea()

            if showingRecall {
                RecallPromptStage(
                    appName: appVM.pendingMidScrollCheckInAppName,
                    guessedCount: $guessedCount,
                    recalledText: $recalledText,
                    fieldFocused: $recallFieldFocused,
                    onContinue: finishRecallAndResume
                )
                .transition(.opacity.combined(with: .scale(scale: 0.97)))
            } else {
                VStack(spacing: 0) {
                    Spacer(minLength: 40)

                    // Renders nothing unless Companion is on. This pause is not
                    // logged through `recordInterventionAttempt`, so the accessory
                    // reports its start itself.
                    CompanionPauseAccessory(compact: true, beginsPause: true, bottomPadding: 14)

                    PauseBreathingStage(secondsRemaining: secondsRemaining, totalSeconds: totalSeconds)
                        .frame(width: 210, height: 210)

                    Text("A short breath before you continue")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundColor(Color(hex: "#FAF3E8"))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 260)
                        .padding(.top, 24)

                    Text("Mivo pauses here to give you a real choice, not to stop you.")
                        .font(.system(size: 13.5, weight: .medium))
                        .foregroundColor(Color(hex: "#FAF3E8").opacity(0.62))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 280)
                        .padding(.top, 10)

                    Spacer(minLength: 20)
                }
                .transition(.opacity)
            }
        }
        .navigationBarHidden(true)
        .onReceive(timer) { _ in
            guard !showingRecall, secondsRemaining > 0 else { return }
            secondsRemaining -= 1
            if secondsRemaining == 0 {
                HapticsService.impact(style: .medium)
                withAnimation(.easeOut(duration: 0.25)) {
                    showingRecall = true
                }
            } else {
                HapticsService.impact(style: .light)
            }
        }
        .accessibilityElement(children: .contain)
    }

    /// The countdown already confirmed the session is still worth resuming —
    /// this only records what was typed and continues; it never blocks or
    /// re-gates on the recall answer itself.
    private func finishRecallAndResume() {
        appVM.recordRecallCheckIn(guessedCount: guessedCount, recalledText: recalledText)
        CompanionInterventionAdapter.midSessionCheckInCompleted()
        resume()
    }

    private func resume() {
        let remaining = FamilyControlsManager.shared.mivoSessionRemainingSeconds()
        guard remaining > 0 else {
            // The underlying session's timer already ran out while this
            // check-in was up — the extension-to-app handoff plus the
            // pause itself both take real time, and a check-in near the
            // end of a session can get eaten by that delay. This is the
            // session ending on schedule, not the user declining to keep
            // going, so it must not be reported as a decline — doing so
            // read as "Mivo randomly ended my session" even though nothing
            // the user did caused it. Routes through the same "end +
            // show review screen" path a normal expiration uses (instead
            // of calling `FamilyControlsManager.expireMivoSession`
            // directly and dismissing to nothing) so the user lands on
            // the actual session-end screen instead of a blank tab.
            appVM.endRunningSessionFromCheckInTimeout()
            dismiss()
            return
        }
        _ = FamilyControlsManager.shared.activateMivoSession(durationSeconds: remaining)
        dismiss()
    }
}

/// The recall step itself — two quick self-report questions, asked while the
/// last few minutes are still fresh. Deliberately not gated as a hard
/// requirement (no minimum text length, "Continue" always enabled): the
/// value is in the honest answer, and forcing one just produces junk text
/// people type past to get through.
private struct RecallPromptStage: View {
    let appName: String?
    @Binding var guessedCount: Int
    @Binding var recalledText: String
    var fieldFocused: FocusState<Bool>.Binding
    let onContinue: () -> Void

    private var promptTitle: String {
        if let appName {
            return "Before you head back to \(appName) —"
        }
        return "Before you head back —"
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 28)

            Text(promptTitle)
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(Color(hex: "#FAF3E8"))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)

            Text("How many things do you think you just scrolled past?")
                .font(.system(size: 13.5, weight: .medium))
                .foregroundColor(Color(hex: "#FAF3E8").opacity(0.62))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 260)
                .padding(.top, 10)

            HStack(spacing: 22) {
                Button {
                    HapticsService.selection()
                    guessedCount = max(0, guessedCount - 1)
                } label: {
                    Image(systemName: "minus")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(width: 40, height: 40)
                        .foregroundColor(Color(hex: "#FAF3E8"))
                        .background(Circle().fill(Color(hex: "#FAF3E8").opacity(0.12)))
                }

                Text("\(guessedCount)")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundColor(Color(hex: "#FAF3E8"))
                    .frame(minWidth: 56)
                    .contentTransition(.numericText())

                Button {
                    HapticsService.selection()
                    guessedCount = min(50, guessedCount + 1)
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(width: 40, height: 40)
                        .foregroundColor(Color(hex: "#FAF3E8"))
                        .background(Circle().fill(Color(hex: "#FAF3E8").opacity(0.12)))
                }
            }
            .padding(.top, 22)

            VStack(alignment: .leading, spacing: 8) {
                Text("Name one, in a sentence")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundColor(Color(hex: "#FAF3E8").opacity(0.5))
                    .textCase(.uppercase)
                    .tracking(0.6)

                TextField("", text: $recalledText, prompt: Text("e.g. a dog skateboarding")
                    .foregroundColor(Color(hex: "#FAF3E8").opacity(0.35)))
                    .focused(fieldFocused)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(Color(hex: "#FAF3E8"))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(hex: "#FAF3E8").opacity(0.08))
                    )
                    .submitLabel(.done)
            }
            .frame(maxWidth: 280)
            .padding(.top, 26)

            Spacer(minLength: 24)

            Button(action: {
                fieldFocused.wrappedValue = false
                HapticsService.impact(style: .medium)
                onContinue()
            }) {
                Text("Continue")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(MivoColors.stage)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color(hex: "#FAF3E8"))
                    )
            }
            .frame(maxWidth: 280)
            .padding(.bottom, 36)
        }
        .padding(.horizontal, 28)
    }
}
