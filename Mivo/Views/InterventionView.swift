import SwiftUI

private let intentionPrompts = [
    "What are you hoping to find right now?",
    "Is this the best use of this moment?",
    "What will you do after you close the app?",
    "You've been here before. What's different this time?",
    "What was the last thing you scrolled past that mattered?",
]

struct InterventionView: View {
    @Environment(\.dismiss) var dismiss
    let intention: Intention?
    let duration: Int?

    @State private var countdown = 5
    @State private var canProceed = false
    @State private var prompt: String
    @State private var opacity = 0.0
    @State private var showSession = false

    var isSessionStart: Bool { intention != nil && duration != nil }

    init(intention: Intention?, duration: Int?) {
        self.intention = intention
        self.duration = duration
        _prompt = State(initialValue: intentionPrompts.randomElement()!)
    }

    var body: some View {
        ZStack {
            MivoColors.background.ignoresSafeArea()
            VStack(spacing: 0) {
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 18))
                            .foregroundColor(MivoColors.textSecondary)
                            .frame(width: 44, height: 44)
                    }
                    Spacer()
                }

                Spacer()

                VStack(spacing: 24) {
                    ZStack {
                        Circle()
                            .strokeBorder(MivoColors.accentLight, lineWidth: 1.5)
                            .frame(width: 80, height: 80)
                        Circle()
                            .fill(MivoColors.accentMuted)
                            .frame(width: 80, height: 80)
                        Image(systemName: "pause.circle")
                            .font(.system(size: 34))
                            .foregroundColor(MivoColors.accent)
                    }

                    Text("Just a moment.")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundColor(MivoColors.textPrimary)
                        .tracking(-0.8)
                        .multilineTextAlignment(.center)

                    Text(prompt)
                        .font(.system(size: 18))
                        .foregroundColor(MivoColors.textSecondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(8)
                        .padding(.horizontal, 8)

                    // Countdown
                    VStack(spacing: 4) {
                        if !canProceed {
                            Text("\(countdown)")
                                .font(.system(size: 56, weight: .bold))
                                .foregroundColor(MivoColors.accent)
                                .tracking(-2)
                                .monospacedDigit()
                            Text("seconds")
                                .font(.system(size: 14))
                                .foregroundColor(MivoColors.textMuted)
                        } else {
                            HStack(spacing: 8) {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundColor(MivoColors.timerGreen)
                                Text("Pause complete")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(MivoColors.timerGreen)
                            }
                            .frame(height: 72)
                        }
                    }
                    .frame(minHeight: 72)

                    Text("Mivo doesn't stop you from using your apps.\nIt just asks you to notice before you do.")
                        .font(.system(size: 14))
                        .foregroundColor(MivoColors.textMuted)
                        .multilineTextAlignment(.center)
                        .lineSpacing(6)
                        .padding(.horizontal, 8)
                }
                .opacity(opacity)

                Spacer()

                // Actions
                VStack(spacing: 10) {
                    if isSessionStart {
                        NavigationLink {
                            ActiveSessionView(intention: intention!, plannedMinutes: duration!)
                        } label: {
                            Text(canProceed ? "Begin session" : "Wait \(countdown)s...")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(MivoColors.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(canProceed ? MivoColors.accent : MivoColors.accentLight)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                        .disabled(!canProceed)
                    } else {
                        Button {
                            dismiss()
                        } label: {
                            Text(canProceed ? "Open the app" : "Wait \(countdown)s...")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(MivoColors.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(canProceed ? MivoColors.accent : MivoColors.accentLight)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                        .disabled(!canProceed)
                    }

                    Button { dismiss() } label: {
                        Text("Close")
                            .font(.system(size: 15))
                            .foregroundColor(MivoColors.textMuted)
                            .padding(.vertical, 14)
                    }
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 20)
        }
        .navigationBarHidden(true)
        .onAppear {
            withAnimation(.easeIn(duration: 0.6)) { opacity = 1 }
            startCountdown()
        }
    }

    func startCountdown() {
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { timer in
            if countdown <= 1 {
                timer.invalidate()
                canProceed = true
            } else {
                countdown -= 1
            }
        }
    }
}
