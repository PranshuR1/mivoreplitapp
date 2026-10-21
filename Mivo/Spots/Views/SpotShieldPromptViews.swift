import Combine
import SwiftUI

/// Presented when a shielded app is tapped while a Spot is running.
struct SpotShieldPromptView: View {
    let prompt: SpotShieldPrompt

    var body: some View {
        switch prompt.kind {
        case .pause: SpotPauseView(prompt: prompt)
        case .intention: SpotIntentionView(prompt: prompt)
        }
    }
}

/// The Mivo pause, for a Spot in Pause mode: the same breathing stage and
/// length the shield pause already uses, then a real choice — not a lock.
struct SpotPauseView: View {
    let prompt: SpotShieldPrompt

    @ObservedObject private var manager = SpotManager.shared
    @Environment(\.dismiss) private var dismiss

    @State private var secondsRemaining: Int
    @State private var finished = false
    @State private var minutes = 5
    private let totalSeconds: Int
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    private static let minuteOptions: [(value: Int, label: String)] = [(5, "5 min"), (10, "10 min"), (15, "15 min")]

    init(prompt: SpotShieldPrompt) {
        self.prompt = prompt
        let seconds = max(1, FamilyControlsManager.shared.shieldPauseDuration())
        totalSeconds = seconds
        _secondsRemaining = State(initialValue: seconds)
    }

    private var cream: Color { Color(hex: "#FAF3E8") }

    var body: some View {
        ZStack {
            MivoColors.stage.ignoresSafeArea()

            if finished {
                choice
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            } else {
                VStack(spacing: 0) {
                    Spacer(minLength: 40)

                    // Renders nothing unless Companion is on.
                    CompanionPauseAccessory(compact: true, beginsPause: true, bottomPadding: 14)

                    PauseBreathingStage(secondsRemaining: secondsRemaining, totalSeconds: totalSeconds)
                        .frame(width: 210, height: 210)

                    Text("A short breath first")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundColor(cream)
                        .padding(.top, 24)

                    Text("\(prompt.spotName) is on. Mivo pauses here to give you a real choice, not to stop you.")
                        .font(.system(size: 13.5, weight: .medium))
                        .foregroundColor(cream.opacity(0.62))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 280)
                        .padding(.top, 10)

                    Spacer(minLength: 20)
                }
                .transition(.opacity)
            }
        }
        .onReceive(timer) { _ in
            guard !finished, secondsRemaining > 0 else { return }
            secondsRemaining -= 1
            if secondsRemaining == 0 {
                HapticsService.impact(style: .medium)
                withAnimation(.easeOut(duration: 0.25)) { finished = true }
            } else {
                HapticsService.impact(style: .light)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var choice: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 40)

            Text(prompt.appName.map { "Still want to open \($0)?" } ?? "Still want to open it?")
                .font(.system(size: 21, weight: .semibold))
                .foregroundColor(cream)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)

            Text("You can open it for a little while. It pauses again after.")
                .font(.system(size: 13.5, weight: .medium))
                .foregroundColor(cream.opacity(0.62))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)
                .padding(.top, 10)

            HStack(spacing: 9) {
                ForEach(Self.minuteOptions, id: \.value) { option in
                    Button {
                        HapticsService.selection()
                        minutes = option.value
                    } label: {
                        Text(option.label)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(minutes == option.value ? MivoColors.stage : cream)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .background(minutes == option.value ? cream : cream.opacity(0.10))
                            .clipShape(RoundedRectangle(cornerRadius: MivoMetrics.radius))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(minutes == option.value ? .isSelected : [])
                }
            }
            .frame(maxWidth: 280)
            .padding(.top, 28)

            Spacer(minLength: 24)

            Button {
                HapticsService.impact(style: .medium)
                manager.continuePastPause(minutes: minutes)
                dismiss()
            } label: {
                Text("Open for \(minutes) min")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(MivoColors.stage)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(RoundedRectangle(cornerRadius: MivoMetrics.radius).fill(cream))
            }
            .buttonStyle(MivoPressStyle())
            .frame(maxWidth: 280)

            Button {
                HapticsService.selection()
                manager.declinePause()
                dismiss()
            } label: {
                Text("Not now")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(cream.opacity(0.7))
                    .frame(maxWidth: 280)
                    .padding(.vertical, 14)
            }
            .padding(.bottom, 30)
        }
        .padding(.horizontal, 28)
    }
}

/// "What did you come here to do?" — asked once per Spot, for Intention Check.
struct SpotIntentionView: View {
    let prompt: SpotShieldPrompt

    @ObservedObject private var manager = SpotManager.shared
    @Environment(\.dismiss) private var dismiss

    @State private var choice: SpotIntentionChoice?
    @State private var note = ""
    @FocusState private var noteFocused: Bool

    var body: some View {
        ZStack {
            MivoColors.background.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        MivoEyebrow(text: prompt.spotName)
                            .padding(.top, 36)

                        Text("What did you come here to do?")
                            .font(.system(size: 27, weight: .bold))
                            .tracking(Font.mivoTracking(-0.025, at: 27))
                            .foregroundColor(MivoColors.ink)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 10)

                        Text(prompt.appName.map { "Before you open \($0). Mivo asks once, then gets out of the way." }
                             ?? "Mivo asks once, then gets out of the way.")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(MivoColors.inkBody)
                            .lineSpacing(5)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 12)

                        VStack(spacing: 9) {
                            ForEach(SpotIntentionChoice.allCases) { option in
                                MivoOptionRow(label: option.title, isSelected: choice == option) {
                                    HapticsService.selection()
                                    choice = option
                                }
                            }
                        }
                        .padding(.top, 22)

                        MivoTextField(
                            label: "Or say it in a few words",
                            placeholder: "Optional",
                            text: $note
                        )
                        .focused($noteFocused)
                        .padding(.top, 20)
                    }
                    .padding(.bottom, 20)
                }

                VStack(spacing: 4) {
                    MivoPrimaryButton(label: "Continue", disabled: !canContinue) {
                        noteFocused = false
                        manager.answerIntention(choice: choice, note: note)
                        HapticsService.success()
                        dismiss()
                    }
                    MivoTertiaryButton(label: "Not now") {
                        manager.declinePause()
                        dismiss()
                    }
                }
                .padding(.bottom, 20)
            }
            .padding(.horizontal, MivoMetrics.screenPadding)
        }
    }

    private var canContinue: Bool {
        choice != nil || !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
