import SwiftUI

struct FocusTimerView: View {
    @EnvironmentObject var appVM: AppViewModel
    @Environment(\.dismiss) var dismiss

    let mode: FocusMode
    let workMinutes: Int
    let restMinutes: Int

    @State private var phase: Phase = .work
    @State private var elapsed = 0
    @State private var timer: Timer? = nil
    @State private var scale: CGFloat = 1.0

    enum Phase { case work, rest, done }

    var plannedSeconds: Int {
        phase == .work ? workMinutes * 60 : restMinutes * 60
    }
    var remaining: Int { max(0, plannedSeconds - elapsed) }
    var progress: Double { min(Double(elapsed) / Double(max(plannedSeconds, 1)), 1.0) }

    var phaseColor: Color {
        switch phase {
        case .work: return MivoColors.accent
        case .rest: return MivoColors.timerGreen
        case .done: return MivoColors.textSecondary
        }
    }

    var phaseLabel: String {
        switch phase {
        case .work: return mode == .open ? "Open Focus" : "Focus"
        case .rest: return "Break"
        case .done: return "Done"
        }
    }

    var body: some View {
        ZStack {
            MivoColors.background.ignoresSafeArea()
            VStack(spacing: 0) {
                HStack {
                    Button { endFocus() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 18))
                            .foregroundColor(MivoColors.textSecondary)
                            .frame(width: 44, height: 44)
                    }
                    Spacer()
                    Text(mode.displayName)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(MivoColors.textSecondary)
                    Spacer()
                    Color.clear.frame(width: 44, height: 44)
                }
                .padding(.bottom, 40)

                Spacer()

                VStack(spacing: 24) {
                    ZStack {
                        Circle()
                            .strokeBorder(MivoColors.border, lineWidth: 1.5)
                            .frame(width: 220, height: 220)
                        Circle()
                            .trim(from: 0, to: CGFloat(progress))
                            .stroke(phaseColor.opacity(0.3), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .frame(width: 190, height: 190)
                        VStack(spacing: 6) {
                            Text(phaseLabel)
                                .font(.system(size: 14))
                                .foregroundColor(MivoColors.textMuted)
                            Text(mode == .open ? formatSeconds(elapsed) : formatSeconds(remaining))
                                .font(.system(size: 52, weight: .bold).monospacedDigit())
                                .foregroundColor(phaseColor)
                                .tracking(-2)
                            if mode != .open {
                                Text("remaining")
                                    .font(.system(size: 12))
                                    .foregroundColor(MivoColors.textMuted)
                            }
                        }
                    }
                    .scaleEffect(scale)

                    Text(phaseMessage)
                        .font(.system(size: 14))
                        .foregroundColor(MivoColors.textSecondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                }

                Spacer()

                VStack(spacing: 12) {
                    if phase == .work && mode != .open {
                        Button {
                            phase = .rest
                            elapsed = 0
                        } label: {
                            Text("Take a break early")
                                .font(.system(size: 15))
                                .foregroundColor(MivoColors.textMuted)
                                .padding(.vertical, 14)
                        }
                    }

                    Button {
                        if phase == .rest {
                            phase = .work
                            elapsed = 0
                        } else {
                            endFocus()
                        }
                    } label: {
                        Text(phase == .rest ? "Start next focus block" : "End focus session")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(MivoColors.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(MivoColors.accent)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 40)
        }
        .navigationBarHidden(true)
        .onAppear { startTimer() }
        .onDisappear { timer?.invalidate() }
    }

    var phaseMessage: String {
        switch phase {
        case .work:
            if mode == .open { return "Running open focus. End when you're done." }
            if progress > 0.8 { return "Almost there. Keep going." }
            return "Stay focused. Distractions can wait."
        case .rest:
            return "Good work. Rest fully. Don't pick up your phone."
        case .done:
            return "Session complete. Well done."
        }
    }

    func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            elapsed += 1
            if mode != .open && elapsed >= plannedSeconds {
                timer?.invalidate()
                if phase == .work {
                    phase = .rest
                    elapsed = 0
                    startTimer()
                } else {
                    phase = .done
                }
            }
        }
    }

    func endFocus() {
        timer?.invalidate()
        dismiss()
    }
}
