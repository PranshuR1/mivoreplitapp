import SwiftUI
import Combine

/// A standalone preview of the §4.3 pause, reachable from Settings → Help and
/// from the app tour. Both call sites pass `intention: nil, duration: nil` —
/// this never launches a real session, so it only needs the countdown itself.
struct InterventionView: View {
    @Environment(\.dismiss) var dismiss
    let intention: Intention?
    let duration: Int?
    var canCloseEarly: Bool = true
    var completionTitle: String = "Done"
    var onComplete: (() -> Void)? = nil

    @State private var secondsRemaining = 5
    @State private var ready = false
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            MivoColors.stage.ignoresSafeArea()

            VStack(spacing: 0) {
                if canCloseEarly {
                    HStack {
                        Spacer()
                        Button { dismiss() } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(Color(hex: "#FAF3E8").opacity(0.6))
                                .frame(width: 44, height: 44)
                        }
                        .accessibilityLabel("Close")
                    }
                    .padding(.top, 12)
                }

                Spacer()

                PauseBreathingPreviewStage(secondsRemaining: secondsRemaining)
                    .frame(width: 210, height: 210)

                Text("Five seconds before the door opens")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundColor(Color(hex: "#FAF3E8"))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 250)
                    .padding(.top, 24)

                Text("Mivo doesn't stop you from using your apps. It just asks you to notice before you do.")
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundColor(Color(hex: "#FAF3E8").opacity(0.62))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 280)
                    .padding(.top, 10)

                Spacer()

                Button {
                    complete()
                } label: {
                    Text(ready ? completionTitle : "Wait \(secondsRemaining)s...")
                        .font(.system(size: 15.5, weight: .bold))
                        .foregroundColor(ready ? .white : Color(hex: "#FAF3E8").opacity(0.5))
                        .frame(maxWidth: .infinity)
                        .frame(height: MivoMetrics.buttonHeight)
                        .background(ready ? MivoColors.accent : Color(hex: "#FAF3E8").opacity(0.10))
                        .clipShape(RoundedRectangle(cornerRadius: MivoMetrics.radius))
                }
                .buttonStyle(MivoPressStyle())
                .disabled(!ready)
                .padding(.bottom, canCloseEarly ? 20 : 44)
            }
            .padding(.horizontal, MivoMetrics.screenPadding)
        }
        .navigationBarHidden(true)
        .onReceive(timer) { _ in
            guard secondsRemaining > 0 else { return }
            secondsRemaining -= 1
            if secondsRemaining == 0 {
                HapticsService.impact(style: .medium)
                ready = true
            } else {
                HapticsService.impact(style: .light)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func complete() {
        if let onComplete {
            onComplete()
        } else {
            dismiss()
        }
    }
}

private struct PauseBreathingPreviewStage: View {
    let secondsRemaining: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var breathe = false

    var body: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [MivoColors.accent.opacity(0.34), .clear], center: .center, startRadius: 0, endRadius: 105))
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
        .accessibilityLabel("5 seconds remaining")
    }
}
