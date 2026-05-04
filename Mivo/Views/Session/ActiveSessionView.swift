import SwiftUI
import UserNotifications

struct ActiveSessionView: View {
    @EnvironmentObject var appVM: AppViewModel
    @Environment(\.dismiss) var dismiss
    @Environment(\.scenePhase) private var scenePhase

    let intention: Intention
    let plannedMinutes: Int

    @State private var elapsed = 0
    @State private var extraSeconds = 0
    @State private var extensionUsed = false
    @State private var startTime = Date()
    @State private var didStart = false
    @State private var showReflection = false
    @State private var showQuitAlert = false
    @State private var sessionTimer: Timer? = nil
    @State private var scale: CGFloat = 1.0
    @State private var sessionDone = false
    @State private var didPulseAtLimit = false
    @State private var interruptionSaved = false
    @State private var feedbackPresentedForTimeLimit = false

    var totalPlanned: Int { plannedMinutes * 60 + extraSeconds }
    var remaining: Int { totalPlanned - elapsed }
    var progress: Double { min(Double(elapsed) / Double(max(totalPlanned, 1)), 1.0) }
    var isOvertime: Bool { elapsed > totalPlanned }
    var timerColor: Color {
        if isOvertime { return MivoColors.timerRed }
        return interpolateColor(progress: progress)
    }

    var nudgeMessage: String {
        if isOvertime { return "You've gone past your limit. Finish up when ready." }
        if progress > 0.9 { return "Almost done. Wrap up soon." }
        if progress > 0.7 { return "\(Int(ceil(Double(remaining) / 60))) minutes left. Start winding down." }
        return "You set \(plannedMinutes) minutes. Stay present."
    }

    var body: some View {
        ZStack {
            MivoColors.background.ignoresSafeArea()
            VStack(spacing: 0) {
                // Top bar
                HStack {
                    Button { showQuitAlert = true } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 18))
                            .foregroundColor(MivoColors.textSecondary)
                            .frame(width: 44, height: 44)
                    }
                    Spacer()
                    Text(intention.rawValue)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(MivoColors.textSecondary)
                    Spacer()
                    Color.clear.frame(width: 44, height: 44)
                }
                .padding(.bottom, 32)

                Spacer()

                // Timer ring
                VStack(spacing: 20) {
                    ZStack {
                        Circle()
                            .strokeBorder(MivoColors.border, lineWidth: 1.5)
                            .frame(width: 220, height: 220)
                        Circle()
                            .strokeBorder(timerColor.opacity(0.3), lineWidth: 2)
                            .frame(width: 180, height: 180)
                        VStack(spacing: 6) {
                            Text(isOvertime ? "+\(formatSeconds(elapsed - totalPlanned))" : formatSeconds(remaining))
                                .font(.system(size: 52, weight: .bold).monospacedDigit())
                                .foregroundColor(timerColor)
                                .tracking(-2)
                            Text(isOvertime ? "over limit" : "remaining")
                                .font(.system(size: 13))
                                .foregroundColor(MivoColors.textMuted)
                        }
                    }
                    .scaleEffect(scale)
                    .animation(.easeInOut(duration: 0.15), value: scale)

                    Text("\(formatSeconds(elapsed)) elapsed")
                        .font(.system(size: 14))
                        .foregroundColor(MivoColors.textMuted)

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(MivoColors.border)
                                .frame(height: 4)
                            RoundedRectangle(cornerRadius: 2)
                                .fill(timerColor)
                                .frame(width: geo.size.width * CGFloat(progress), height: 4)
                        }
                    }
                    .frame(width: 260, height: 4)
                }

                Spacer()

                // Nudge card
                Text(nudgeMessage)
                    .font(.system(size: 14))
                    .foregroundColor(MivoColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(6)
                    .padding(16)
                    .frame(maxWidth: .infinity)
                    .background(MivoColors.card)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(MivoColors.border, lineWidth: 1))
                    .padding(.bottom, 24)

                // Actions
                VStack(spacing: 12) {
                    if !extensionUsed && isOvertime {
                        Button { extend() } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "plus")
                                    .font(.system(size: 16))
                                Text("Add 5 more minutes (once only)")
                                    .font(.system(size: 15, weight: .medium))
                            }
                            .foregroundColor(MivoColors.accent)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(MivoColors.accentMuted)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(MivoColors.accentLight, lineWidth: 1))
                        }
                    }

                    NavigationLink {
                        ReflectionView(
                            intention: intention,
                            plannedDuration: plannedMinutes,
                            actualDuration: max(1, Int((Double(elapsed) / 60).rounded())),
                            startTime: ISO8601DateFormatter().string(from: startTime),
                            endTime: ISO8601DateFormatter().string(from: Date()),
                            extendedOnce: extensionUsed,
                            onSaved: {
                                cancelSessionNotifications()
                                dismiss()
                            }
                        )
                    } label: {
                        Text("Done scrolling")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(MivoColors.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(MivoColors.accent)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .simultaneousGesture(TapGesture().onEnded { endSession() })
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 40)
        }
        .navigationBarHidden(true)
        .onAppear { startTimer() }
        .onDisappear {
            sessionTimer?.invalidate()
            if showReflection || sessionDone {
                cancelSessionNotifications()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                updateElapsed()
            } else if phase == .background || phase == .inactive {
                updateElapsed()
            }
        }
        .alert("End session?", isPresented: $showQuitAlert) {
            Button("Keep going", role: .cancel) {}
            Button("End now") { endSession() }
        } message: {
            Text("Your time will be recorded as-is.")
        }
    }

    func startTimer() {
        if !didStart {
            startTime = Date()
            didStart = true
            scheduleSessionNotifications()
            appVM.markMivoSessionActiveFor(seconds: totalPlanned)
        }
        updateElapsed()
        sessionTimer?.invalidate()
        sessionTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            updateElapsed()
        }
    }

    func updateElapsed() {
        elapsed = max(0, Int(Date().timeIntervalSince(startTime)))
        if elapsed >= totalPlanned && !didPulseAtLimit {
            didPulseAtLimit = true
            scale = 1.06
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { scale = 1.0 }
        }
        if elapsed >= totalPlanned && !sessionDone {
            completeTimeLimit()
        }
    }

    func endSession() {
        updateElapsed()
        sessionDone = true
        cancelSessionNotifications()
        sessionTimer?.invalidate()
        showReflection = true
    }

    func persistInterruptedSessionIfNeeded() {
        guard !interruptionSaved, !showReflection, !sessionDone else { return }
        updateElapsed()
        interruptionSaved = true
        appVM.savePendingSessionFeedback(
            PendingSessionFeedback(
                id: UUID().uuidString,
                intention: intention,
                plannedDuration: plannedMinutes,
                actualDuration: max(1, Int((Double(elapsed) / 60).rounded())),
                startTime: ISO8601DateFormatter().string(from: startTime),
                endTime: ISO8601DateFormatter().string(from: Date()),
                extendedOnce: extensionUsed
            )
        )
    }

    func completeTimeLimit() {
        guard !feedbackPresentedForTimeLimit else { return }
        feedbackPresentedForTimeLimit = true
        sessionDone = true
        sessionTimer?.invalidate()
        appVM.finishMivoSession()
        saveCompletedSessionForFeedback()
        showReflection = true
    }

    func saveCompletedSessionForFeedback() {
        appVM.savePendingSessionFeedback(
            PendingSessionFeedback(
                id: UUID().uuidString,
                intention: intention,
                plannedDuration: plannedMinutes,
                actualDuration: max(1, Int((Double(elapsed) / 60).rounded())),
                startTime: ISO8601DateFormatter().string(from: startTime),
                endTime: ISO8601DateFormatter().string(from: Date()),
                extendedOnce: extensionUsed
            )
        )
    }

    func extend() {
        extraSeconds = 5 * 60
        extensionUsed = true
        didPulseAtLimit = false
        scheduleSessionNotifications()
        appVM.markMivoSessionActiveFor(seconds: max(1, totalPlanned - elapsed))
        updateElapsed()
    }

    func scheduleSessionNotifications() {
        cancelSessionNotifications()

        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .badge, .sound]) { _, _ in }
        let remainingSeconds = max(1, totalPlanned - elapsed)

        if remainingSeconds > 60 {
            let warningContent = UNMutableNotificationContent()
            warningContent.title = "1 minute left"
            warningContent.body = "Wrap up now. Mivo will lock protected apps again when the timer ends."
            warningContent.sound = .default

            let warningTrigger = UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(remainingSeconds - 60), repeats: false)
            let warningRequest = UNNotificationRequest(
                identifier: "mivo.intervention.oneMinute",
                content: warningContent,
                trigger: warningTrigger
            )
            center.add(warningRequest)
        }

        let doneContent = UNMutableNotificationContent()
        doneContent.title = "Intervention ended"
        doneContent.body = "Mivo is locking protected apps again. Open Mivo to reflect on the session."
        doneContent.sound = .default

        let doneTrigger = UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(remainingSeconds), repeats: false)
        let doneRequest = UNNotificationRequest(
            identifier: "mivo.intervention.done",
            content: doneContent,
            trigger: doneTrigger
        )
        center.add(doneRequest)
    }

    func cancelSessionNotifications() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [
            "mivo.intervention.oneMinute",
            "mivo.intervention.done"
        ])
    }

    func interpolateColor(progress: Double) -> Color {
        let calm = (r: 169.0, g: 123.0, b: 91.0)
        let orange = (r: 196.0, g: 132.0, b: 74.0)
        let red = (r: 176.0, g: 85.0, b: 64.0)

        let r, g, b: Double
        if progress < 0.7 {
            let t = progress / 0.7
            r = calm.r + (orange.r - calm.r) * t
            g = calm.g + (orange.g - calm.g) * t
            b = calm.b + (orange.b - calm.b) * t
        } else {
            let t = (progress - 0.7) / 0.3
            r = orange.r + (red.r - orange.r) * t
            g = orange.g + (red.g - orange.g) * t
            b = orange.b + (red.b - orange.b) * t
        }
        return Color(red: r / 255, green: g / 255, blue: b / 255)
    }
}
