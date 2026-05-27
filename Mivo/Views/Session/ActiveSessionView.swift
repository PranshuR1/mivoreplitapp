import SwiftUI
import UserNotifications

struct ActiveSessionView: View {
    @EnvironmentObject var appVM: AppViewModel
    @Environment(\.dismiss) var dismiss
    @Environment(\.scenePhase) private var scenePhase

    let intention: Intention
    let plannedMinutes: Int
    let urgeReason: UrgeReason?
    let urgeNote: String?

    @State private var elapsed = 0
    @State private var extraSeconds = 0
    /// When non-nil, replaces `plannedMinutes*60 + extraSeconds` as the total time.
    /// Set when the user adds more time so the new timer equals exactly the added
    /// duration instead of stacking on the original.
    @State private var totalPlannedOverride: Int? = nil
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
    @State private var sessionEndedGateActive = false
    @State private var extensionDecisionAlert: SessionExtensionDecision? = nil
    @State private var showEmergencyUnlock = false
    @State private var emergencyUnlockReason = ""
    @State private var emergencyUnlockUsed = false
    @State private var emergencyUnlockSavedReason: String? = nil
    @State private var sessionID = UUID().uuidString

    var totalPlanned: Int { totalPlannedOverride ?? (plannedMinutes * 60 + extraSeconds) }
    var displayElapsed: Int { sessionEndedGateActive ? min(elapsed, totalPlanned) : elapsed }
    var remaining: Int { max(0, totalPlanned - elapsed) }
    var progress: Double { min(Double(displayElapsed) / Double(max(totalPlanned, 1)), 1.0) }
    var isOvertime: Bool { !sessionEndedGateActive && elapsed > totalPlanned }
    var timerColor: Color {
        if isOvertime { return MivoColors.timerRed }
        return interpolateColor(progress: progress)
    }

    var nudgeMessage: String {
        if sessionEndedGateActive { return "Time is up. Mivo has locked the selected app again until you add approved time or save this session." }
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
                    Group {
                        if sessionEndedGateActive {
                            Color.clear.frame(width: 44, height: 44)
                        } else {
                            Button { showQuitAlert = true } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 18))
                                    .foregroundColor(MivoColors.textSecondary)
                                    .frame(width: 44, height: 44)
                            }
                        }
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

                    Text("\(formatSeconds(displayElapsed)) elapsed")
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
                    if sessionEndedGateActive {
                        sessionEndedActions
                    } else {
                        Button { endSession() } label: {
                            Text("Done scrolling")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(MivoColors.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(MivoColors.accent)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                        .buttonStyle(.plain)
                    }
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
            appVM.pendingResumedActiveSession = nil
            if !showReflection, !sessionDone {
                saveRunningSessionSnapshot()
            }
            if showReflection || sessionDone {
                cancelSessionNotifications()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                updateElapsed()
            } else if phase == .background || phase == .inactive {
                updateElapsed()
                if !sessionDone {
                    saveRunningSessionSnapshot()
                }
            }
        }
        .alert("End session?", isPresented: $showQuitAlert) {
            Button("Keep going", role: .cancel) {}
            Button("End now") { endSession() }
        } message: {
            Text("Your time will be recorded as-is.")
        }
        .alert(item: $extensionDecisionAlert) { decision in
            Alert(
                title: Text(decision.title),
                message: Text(decision.message),
                dismissButton: .default(Text("Got it"))
            )
        }
        .sheet(isPresented: $showEmergencyUnlock) {
            emergencyUnlockSheet
        }
        .fullScreenCover(isPresented: $showReflection) {
            ReflectionView(
                intention: intention,
                plannedDuration: plannedMinutes,
                actualDuration: max(1, Int((Double(elapsed) / 60).rounded())),
                startTime: ISO8601DateFormatter().string(from: startTime),
                endTime: ISO8601DateFormatter().string(from: Date()),
                extendedOnce: extensionUsed,
                urgeReason: urgeReason,
                urgeNote: urgeNote,
                emergencyUnlockUsed: emergencyUnlockUsed,
                emergencyUnlockReason: emergencyUnlockSavedReason,
                onSaved: {
                    cancelSessionNotifications()
                    dismiss()
                }
            )
            .interactiveDismissDisabled()
        }
    }

    var sessionEndedActions: some View {
        VStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 13, weight: .bold))
                    Text("Session locked on Mivo")
                        .font(.system(size: 14, weight: .bold))
                }
                .foregroundColor(MivoColors.accent)

                Text("The selected app is closed again. Choose more time only if Mivo approves it, or save the session to finish.")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(MivoColors.textSecondary)
                    .lineSpacing(3)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(MivoColors.card)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(MivoColors.border, lineWidth: 1))

            Button { requestMoreTime() } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 16))
                    Text("Add more time?")
                        .font(.system(size: 15, weight: .bold))
                }
                .foregroundColor(MivoColors.accent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(MivoColors.accentMuted)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(MivoColors.accentLight, lineWidth: 1))
            }
            .buttonStyle(.plain)

            Button { showEmergencyUnlock = true } label: {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 15))
                    Text("Emergency unlock")
                        .font(.system(size: 15, weight: .bold))
                }
                .foregroundColor(MivoColors.timerOrange)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(MivoColors.timerOrange.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)

            Button { finishForReflection() } label: {
                Text("Save and finish session")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(MivoColors.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(MivoColors.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
        }
    }

    private var emergencyUnlockSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                Text("Emergency unlock")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundColor(MivoColors.textPrimary)

                Text("Mivo will give you 5 more minutes, but only after you write why this needs to happen now.")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(MivoColors.textSecondary)
                    .lineSpacing(4)

                TextEditor(text: $emergencyUnlockReason)
                    .font(.system(size: 15))
                    .foregroundColor(MivoColors.textPrimary)
                    .scrollContentBackground(.hidden)
                    .padding(10)
                    .frame(minHeight: 120)
                    .background(MivoColors.card)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(MivoColors.border, lineWidth: 1))

                Button {
                    applyEmergencyUnlock()
                } label: {
                    Text("Unlock 5 minutes")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(MivoColors.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(canUseEmergencyUnlock ? MivoColors.accent : MivoColors.accentLight)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .disabled(!canUseEmergencyUnlock)

                Spacer()
            }
            .padding(22)
            .background(MivoColors.background.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showEmergencyUnlock = false }
                }
            }
        }
    }

    private var canUseEmergencyUnlock: Bool {
        emergencyUnlockReason.trimmingCharacters(in: .whitespacesAndNewlines).count >= 3
    }

    func startTimer() {
        if !didStart {
            startTime = Date()
            didStart = true
            scheduleSessionNotifications()
            appVM.markMivoSessionActiveFor(seconds: totalPlanned)
            saveRunningSessionSnapshot()
            // Start Live Activity so the timer is visible on the lock screen / Dynamic Island.
            let sessionEnd = Date().addingTimeInterval(TimeInterval(totalPlanned))
            FamilyControlsManager.shared.startSessionLiveActivity(
                sessionEndsAt: sessionEnd,
                planMinutes: plannedMinutes,
                intentionLabel: intention.rawValue
            )
        }
        updateElapsed()
        sessionTimer?.invalidate()
        sessionTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            updateElapsed()
        }
    }

    func saveRunningSessionSnapshot() {
        guard didStart, !showReflection else { return }
        let formatter = ISO8601DateFormatter()
        let expiresAtDate = startTime.addingTimeInterval(TimeInterval(totalPlanned))
        let isExpiredChoice = sessionEndedGateActive
        let cappedElapsed = max(0, min(elapsed, totalPlanned))

        appVM.saveRunningSession(
            RunningMivoSession(
                id: sessionID,
                intention: intention,
                plannedDuration: plannedMinutes,
                plannedSeconds: totalPlanned,
                approvedSeconds: totalPlanned,
                startTime: formatter.string(from: startTime),
                expiresAt: formatter.string(from: expiresAtDate),
                expiredAt: isExpiredChoice ? formatter.string(from: expiresAtDate) : nil,
                expirationSource: isExpiredChoice ? MivoSessionExpirationSource.sessionEnd.rawValue : nil,
                state: isExpiredChoice ? .expiredAwaitingChoice : .active,
                accumulatedElapsedSeconds: cappedElapsed,
                urgeReason: urgeReason,
                urgeNote: urgeNote,
                extendedOnce: extensionUsed,
                emergencyUnlockUsed: emergencyUnlockUsed,
                emergencyUnlockReason: emergencyUnlockSavedReason
            )
        )
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
        appVM.finishMivoSession()
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
                extendedOnce: extensionUsed,
                urgeReason: urgeReason,
                urgeNote: urgeNote,
                emergencyUnlockUsed: emergencyUnlockUsed,
                emergencyUnlockReason: emergencyUnlockSavedReason
            )
        )
    }

    func completeTimeLimit() {
        guard !feedbackPresentedForTimeLimit else { return }
        elapsed = min(max(elapsed, 0), totalPlanned)
        feedbackPresentedForTimeLimit = true
        sessionDone = true
        sessionTimer?.invalidate()
        sessionEndedGateActive = true
        saveRunningSessionSnapshot()
        cancelSessionNotifications()
        appVM.finishMivoSession(requiresReview: true)
    }

    func requestMoreTime() {
        updateElapsed()
        let decision = appVM.sessionExtensionDecision(
            intention: intention,
            plannedMinutes: plannedMinutes,
            elapsedSeconds: elapsed,
            extensionUsed: extensionUsed
        )

        guard decision.allowed else {
            extensionDecisionAlert = decision
            showEmergencyUnlock = true
            HapticsService.warning()
            return
        }

        // When the user taps "Add more time" the *new* timer should equal exactly the
        // added duration — not (original + added). We override totalPlanned with the
        // added seconds, reset elapsed to 0, and rebase startTime to now.
        let addedSeconds = decision.addedMinutes * 60
        totalPlannedOverride = addedSeconds
        elapsed = 0
        startTime = Date()
        extensionUsed = true
        didPulseAtLimit = false
        feedbackPresentedForTimeLimit = false
        sessionDone = false
        sessionEndedGateActive = false
        scheduleSessionNotifications()
        appVM.markMivoSessionActiveFor(seconds: max(1, totalPlanned - elapsed))
        saveRunningSessionSnapshot()
        startTimer()
        updateElapsed()
        extensionDecisionAlert = decision
        HapticsService.success()
    }

    func applyEmergencyUnlock() {
        let reason = emergencyUnlockReason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard reason.count >= 3 else { return }
        emergencyUnlockUsed = true
        emergencyUnlockSavedReason = reason
        // Emergency unlock grants exactly 5 minutes — reset the timer so the countdown
        // shows exactly 5:00 instead of (original + 5).
        totalPlannedOverride = 5 * 60
        elapsed = 0
        startTime = Date()
        extensionUsed = true
        didPulseAtLimit = false
        feedbackPresentedForTimeLimit = false
        sessionDone = false
        sessionEndedGateActive = false
        showEmergencyUnlock = false
        scheduleSessionNotifications()
        appVM.markMivoSessionActiveFor(seconds: max(1, totalPlanned - elapsed))
        saveRunningSessionSnapshot()
        startTimer()
        updateElapsed()
        HapticsService.success()
    }

    func finishForReflection() {
        updateElapsed()
        elapsed = min(max(elapsed, 0), totalPlanned)
        sessionDone = true
        sessionEndedGateActive = false
        cancelSessionNotifications()
        sessionTimer?.invalidate()
        appVM.finishMivoSession()
        showReflection = true
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
        doneContent.title = "Session ended — re-lock your apps"
        doneContent.body = "Tap to lock apps again and save your session."
        doneContent.sound = .default
        // openIntervention flag is read by MivoAppDelegate.didReceive — applies
        // shields immediately and navigates to the intervention tab.
        doneContent.userInfo = ["mivoRoute": "sessionEnded", "openIntervention": true]
        doneContent.categoryIdentifier = "MIVO_SESSION_ENDED"
        if #available(iOS 15.0, *) {
            doneContent.interruptionLevel = .timeSensitive
        }

        let doneTrigger = UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(remainingSeconds), repeats: false)
        let doneRequest = UNNotificationRequest(
            identifier: "mivo.intervention.done",
            content: doneContent,
            trigger: doneTrigger
        )
        center.add(doneRequest)

        // The active session view owns the primary session-end notification.
        // Cancel the FamilyControlsManager backup primary so the user only sees ONE
        // banner at T=0. The nudges at +30s and +90s (mivo.session.ended.nudge1/2)
        // are intentionally kept as backup in case the user dismisses this one.
        center.removePendingNotificationRequests(withIdentifiers: ["mivo.session.ended"])
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
