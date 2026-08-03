import SwiftUI
import UserNotifications

private let defaultRescueModeThresholdSeconds = 27 * 60
private let rescueNotificationID = "mivo.session.rescue"
private let rescueReminderNotificationID = "mivo.session.rescue.reminder"
private let rescueNotificationName = Notification.Name("mivoRescueRequested")

struct ActiveSessionView: View {
    @EnvironmentObject var appVM: AppViewModel
    @ObservedObject private var expansion = ProductExpansionStore.shared
    @Environment(\.dismiss) var dismiss
    @Environment(\.scenePhase) private var scenePhase

    let intention: Intention
    let plannedMinutes: Int
    let urgeReason: UrgeReason?
    let urgeNote: String?
    var onFinished: (() -> Void)? = nil

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
    @State private var emergencyUnlockReviewMessage: String? = nil
    @State private var emergencyUnlockReviewing = false
    @State private var emergencyUnlockUsed = false
    @State private var emergencyUnlockSavedReason: String? = nil
    @State private var sessionSaved = false
    @State private var autoFinishWorkItem: DispatchWorkItem? = nil
    @State private var sessionID: String
    @State private var didRecordSessionStart = false
    @State private var showRescueMode = false
    @State private var didOfferInitialRescue = false
    @State private var rescueReminderAt: Int? = nil
    @State private var showRescueIntention = false

    init(
        intention: Intention,
        plannedMinutes: Int,
        urgeReason: UrgeReason?,
        urgeNote: String?,
        sessionID: String = UUID().uuidString,
        onFinished: (() -> Void)? = nil
    ) {
        self.intention = intention
        self.plannedMinutes = plannedMinutes
        self.urgeReason = urgeReason
        self.urgeNote = urgeNote
        self.onFinished = onFinished
        _sessionID = State(initialValue: sessionID)

    }

    var totalPlanned: Int { totalPlannedOverride ?? (plannedMinutes * 60 + extraSeconds) }
    var currentPlannedMinutes: Int { max(0, Int((Double(totalPlanned) / 60.0).rounded())) }
    var currentActualMinutes: Int {
        let seconds = max(0, elapsed)
        guard seconds > 0 else { return 0 }
        return max(1, Int((Double(seconds) / 60.0).rounded()))
    }
    var displayElapsed: Int { sessionEndedGateActive ? min(elapsed, totalPlanned) : elapsed }
    var remaining: Int { max(0, totalPlanned - elapsed) }
    var progress: Double { min(Double(displayElapsed) / Double(max(totalPlanned, 1)), 1.0) }
    private var rescueModeThresholdSeconds: Int {
        guard expansion.isEnabled(.appPersonalities),
              let profile = expansion.approvedFrictionProfile else {
            return defaultRescueModeThresholdSeconds
        }
        return min(120, max(5, profile.rescueAfterMinutes)) * 60
    }
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
            if sessionSaved {
                Color.clear
                    .onAppear {
                        DispatchQueue.main.async {
                            dismiss()
                        }
                    }
            } else {
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

                // Timer circle
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
                    .padding(.vertical, 16)
                    .frame(maxWidth: .infinity)
                    .overlay(alignment: .top) {
                        Rectangle().fill(MivoColors.border.opacity(0.34)).frame(height: 1)
                    }
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(MivoColors.border.opacity(0.34)).frame(height: 1)
                    }
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
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 40)
            }
        }
        .navigationBarHidden(true)
        .onAppear {
            guard !sessionSaved else { return }
            startTimer()
        }
        .onDisappear {
            sessionTimer?.invalidate()
            appVM.pendingResumedActiveSession = nil
            if sessionSaved || showReflection {
                cancelAutoFinishIfForgotten()
            }
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
        .sheet(isPresented: $showRescueMode) {
            rescueModeSheet
        }
        .onReceive(NotificationCenter.default.publisher(for: rescueNotificationName)) { _ in
            updateElapsed()
        }
        .fullScreenCover(isPresented: $showReflection) {
            ReflectionView(
                sessionID: sessionID,
                intention: intention,
                plannedDuration: currentPlannedMinutes,
                actualDuration: currentActualMinutes,
                startTime: ISO8601DateFormatter().string(from: startTime),
                endTime: ISO8601DateFormatter().string(from: Date()),
                extendedOnce: extensionUsed,
                urgeReason: urgeReason,
                urgeNote: urgeNote,
                emergencyUnlockUsed: emergencyUnlockUsed,
                emergencyUnlockReason: emergencyUnlockSavedReason,
                onSaved: {
                    closeFinishedSession()
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
                    Text("Session complete")
                        .font(.system(size: 14, weight: .bold))
                }
                .foregroundColor(MivoColors.accent)

                Text(appVM.experimentBlocksExtensions
                     ? "Your time is saved in Patterns. Your active experiment keeps the original limit, so save and finish this session."
                     : "Your time is saved in Patterns. Add more time if Mivo approves it, or save and finish the session.")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(MivoColors.textSecondary)
                    .lineSpacing(3)
            }
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .bottom) { Rectangle().fill(MivoColors.border.opacity(0.34)).frame(height: 1) }

            if appVM.experimentBlocksExtensions {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "flask.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(MivoColors.accent)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Original limit kept")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(MivoColors.textPrimary)
                        Text("Add Time is off during this experiment. Emergency unlock remains available for a genuine urgent need.")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(MivoColors.textSecondary)
                            .lineSpacing(3)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(MivoColors.accentMuted)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(MivoColors.accentLight, lineWidth: 1))
            } else {
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
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(MivoColors.accentLight, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }

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
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)

            Button { finishForReflection() } label: {
                Text("Save and finish session")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(MivoColors.white)
                    .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(MivoColors.accent)
                .clipShape(RoundedRectangle(cornerRadius: 8))
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

                Text("Mivo will give you 5 more minutes only if your reason is specific and time-sensitive.")
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
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(MivoColors.border, lineWidth: 1))

                if let emergencyUnlockReviewMessage {
                    Text(emergencyUnlockReviewMessage)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(MivoColors.timerOrange)
                }

                Button {
                    applyEmergencyUnlock()
                } label: {
                    Text(emergencyUnlockReviewing ? "Checking reason..." : "Unlock 5 minutes")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(MivoColors.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(canUseEmergencyUnlock ? MivoColors.accent : MivoColors.accentLight)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
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

    private var rescueModeSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                Label("A gentle check-in", systemImage: "hand.raised.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(MivoColors.accent)

                Text("You have been scrolling for \(max(1, elapsed / 60)) minutes. Still choosing this?")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundColor(MivoColors.textPrimary)

                if showRescueIntention {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("You opened Mivo to")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(MivoColors.textMuted)
                        Text(rescueIntentionText)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(MivoColors.textPrimary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .mivoSectionSurface()
                }

                VStack(spacing: 10) {
                    rescueButton("Yes, continue", icon: "arrow.right", emphasized: true) {
                        rescueReminderAt = nil
                        clearRescueNotifications()
                        showRescueMode = false
                    }
                    rescueButton("Give me 5 more minutes", icon: "timer") {
                        rescueReminderAt = elapsed + 5 * 60
                        scheduleRescueNotification(
                            after: 5 * 60,
                            identifier: rescueReminderNotificationID,
                            reminder: true
                        )
                        showRescueMode = false
                    }
                    rescueButton("Exit now", icon: "rectangle.portrait.and.arrow.right") {
                        showRescueMode = false
                        endSession()
                    }
                    rescueButton("Remind me why I opened this", icon: "quote.bubble") {
                        showRescueIntention = true
                    }
                }

                Text("You stay in control. This check-in does not change your approved session time.")
                    .font(.system(size: 12))
                    .foregroundColor(MivoColors.textMuted)
                    .lineSpacing(3)
            }
            .padding(22)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(MivoColors.background.ignoresSafeArea())
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .onAppear {
            removeDeliveredRescueNotifications()
        }
    }

    @ViewBuilder
    private func rescueButton(
        _ title: String,
        icon: String,
        emphasized: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .frame(width: 20)
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
            }
            .foregroundColor(emphasized ? MivoColors.white : MivoColors.textPrimary)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(emphasized ? MivoColors.accent : MivoColors.card)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay {
                if !emphasized {
                    RoundedRectangle(cornerRadius: 8).strokeBorder(MivoColors.border, lineWidth: 1)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var rescueIntentionText: String {
        let note = urgeNote?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !note.isEmpty { return note }
        if let urgeReason { return "\(intention.rawValue) because you felt \(urgeReason.rawValue.lowercased())." }
        return intention.rawValue
    }

    private var canUseEmergencyUnlock: Bool {
        emergencyUnlockReason.trimmingCharacters(in: .whitespacesAndNewlines).count >= 3 && !emergencyUnlockReviewing
    }

    func startTimer() {
        if !didStart {
            startTime = Date()
            didStart = true
            recordSessionStartIfNeeded()
            scheduleSessionNotifications()
            appVM.markMivoSessionActiveFor(seconds: totalPlanned)
            saveRunningSessionSnapshot()
            // Start Live Activity so the timer is visible on the lock screen / Dynamic Island.
            if expansion.isEnabled(.liveActivities) {
                let sessionEnd = Date().addingTimeInterval(TimeInterval(totalPlanned))
                FamilyControlsManager.shared.startSessionLiveActivity(
                    sessionEndsAt: sessionEnd,
                    planMinutes: plannedMinutes,
                    intentionLabel: intention.rawValue
                )
            }
        }
        updateElapsed()
        sessionTimer?.invalidate()
        sessionTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            updateElapsed()
        }
    }

    func recordSessionStartIfNeeded() {
        guard !didRecordSessionStart else { return }
        didRecordSessionStart = true
        appVM.recordStartedInterventionSession(
            id: sessionID,
            intention: intention,
            plannedDuration: currentPlannedMinutes,
            startTime: startTime,
            urgeReason: urgeReason,
            urgeNote: urgeNote,
            extendedOnce: extensionUsed,
            emergencyUnlockUsed: emergencyUnlockUsed,
            emergencyUnlockReason: emergencyUnlockSavedReason
        )
    }

    func saveCurrentSegmentBeforeAddedTime() {
        let formatter = ISO8601DateFormatter()
        let cappedSeconds = max(0, min(elapsed, totalPlanned))
        let actualMinutes = cappedSeconds == 0 ? 0 : max(1, Int((Double(cappedSeconds) / 60.0).rounded()))
        let endDate = startTime.addingTimeInterval(TimeInterval(cappedSeconds))
        let dayFormatter = MivoDay.formatter

        let session = Session(
            id: sessionID,
            date: dayFormatter.string(from: startTime),
            startTime: formatter.string(from: startTime),
            endTime: formatter.string(from: endDate),
            plannedDuration: currentPlannedMinutes,
            actualDuration: actualMinutes,
            intention: intention,
            extendedOnce: extensionUsed,
            reflection: nil,
            reflectionNote: "",
            urgeReason: urgeReason,
            urgeNote: urgeNote,
            outcomeScore: nil,
            emergencyUnlockUsed: emergencyUnlockUsed,
            emergencyUnlockReason: emergencyUnlockSavedReason
        )
        _ = appVM.upsertSession(session)
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
                plannedDuration: currentPlannedMinutes,
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
        offerRescueModeIfNeeded()
        if elapsed >= totalPlanned && !didPulseAtLimit {
            didPulseAtLimit = true
            scale = 1.06
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { scale = 1.0 }
        }
        if elapsed >= totalPlanned && !sessionDone {
            completeTimeLimit()
        }
    }

    private func offerRescueModeIfNeeded() {
        guard !sessionEndedGateActive, !sessionDone, elapsed < totalPlanned else { return }

        if !didOfferInitialRescue, elapsed >= rescueModeThresholdSeconds {
            didOfferInitialRescue = true
            clearRescueNotifications()
            showRescueMode = true
            HapticsService.warning()
            return
        }

        if let reminder = rescueReminderAt, elapsed >= reminder {
            rescueReminderAt = nil
            clearRescueNotifications()
            showRescueMode = true
            HapticsService.warning()
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
                id: sessionID,
                intention: intention,
                plannedDuration: currentPlannedMinutes,
                actualDuration: currentActualMinutes,
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
        saveCurrentSegmentBeforeAddedTime()
        saveRunningSessionSnapshot()
        cancelSessionNotifications()
        appVM.finishMivoSession(requiresReview: true)
        scheduleAutoFinishIfForgotten()
    }

    func requestMoreTime() {
        updateElapsed()
        cancelAutoFinishIfForgotten()
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
        saveCurrentSegmentBeforeAddedTime()
        sessionID = UUID().uuidString
        didRecordSessionStart = false
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
        recordSessionStartIfNeeded()
        saveRunningSessionSnapshot()
        startTimer()
        updateElapsed()
        extensionDecisionAlert = decision
        HapticsService.success()
    }

    func applyEmergencyUnlock() {
        let reason = emergencyUnlockReason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard reason.count >= 3 else { return }
        let sessions = appVM.sessions
        let profile = appVM.onboardingProfile
        emergencyUnlockReviewing = true
        emergencyUnlockReviewMessage = nil

        Task {
            let review = await AIService.verifyEmergencyUnlock(reason: reason, sessions: sessions, profile: profile)
            await MainActor.run {
                emergencyUnlockReviewing = false
                guard review.approved else {
                    emergencyUnlockReviewMessage = review.message
                    HapticsService.warning()
                    return
                }

                cancelAutoFinishIfForgotten()
                // Emergency unlock grants exactly 5 minutes — reset the timer so the countdown
                // shows exactly 5:00 instead of (original + 5).
                saveCurrentSegmentBeforeAddedTime()
                sessionID = UUID().uuidString
                didRecordSessionStart = false
                emergencyUnlockUsed = true
                emergencyUnlockSavedReason = reason
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
                recordSessionStartIfNeeded()
                saveRunningSessionSnapshot()
                startTimer()
                updateElapsed()
                HapticsService.success()
            }
        }
    }

    func finishForReflection() {
        updateElapsed()
        elapsed = min(max(elapsed, 0), totalPlanned)
        sessionDone = true
        sessionEndedGateActive = false
        cancelAutoFinishIfForgotten()
        cancelSessionNotifications()
        sessionTimer?.invalidate()
        appVM.finishMivoSession()
        showReflection = true
    }

    func closeFinishedSession() {
        cancelAutoFinishIfForgotten()
        cancelSessionNotifications()
        SessionEndedNotificationCleaner.clearPendingAndDelivered()
        sessionTimer?.invalidate()
        sessionSaved = true
        sessionDone = true
        showReflection = false
        appVM.pendingResumedActiveSession = nil
        onFinished?()
        dismiss()
    }

    func scheduleAutoFinishIfForgotten() {
        cancelAutoFinishIfForgotten()
        let workItem = DispatchWorkItem {
            autoFinishSessionIfForgotten()
        }
        autoFinishWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 5 * 60, execute: workItem)
    }

    func cancelAutoFinishIfForgotten() {
        autoFinishWorkItem?.cancel()
        autoFinishWorkItem = nil
    }

    func autoFinishSessionIfForgotten() {
        guard sessionEndedGateActive, !showReflection, !sessionSaved else { return }
        elapsed = min(max(elapsed, 0), totalPlanned)
        let formatter = ISO8601DateFormatter()
        let endDate = startTime.addingTimeInterval(TimeInterval(totalPlanned))
        let dayFormatter = MivoDay.formatter
        let plannedMinutesForRecord = max(1, Int((Double(totalPlanned) / 60.0).rounded()))
        let session = Session(
            id: sessionID,
            date: dayFormatter.string(from: startTime),
            startTime: formatter.string(from: startTime),
            endTime: formatter.string(from: endDate),
            plannedDuration: plannedMinutesForRecord,
            actualDuration: plannedMinutesForRecord,
            intention: intention,
            extendedOnce: extensionUsed,
            reflection: nil,
            reflectionNote: "",
            urgeReason: urgeReason,
            urgeNote: urgeNote,
            outcomeScore: nil,
            emergencyUnlockUsed: emergencyUnlockUsed,
            emergencyUnlockReason: emergencyUnlockSavedReason
        )

        if appVM.upsertSession(session) {
            appVM.appendAISummary("Session auto-finished after 5m idle: \(session.actualDuration)m actual / \(session.plannedDuration)m planned | Intention: \(session.intention.rawValue)")
        }
        appVM.finishMivoSession()
        closeFinishedSession()
    }

    func scheduleSessionNotifications() {
        cancelSessionNotifications()

        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .badge, .sound]) { _, _ in }
        let remainingSeconds = max(1, totalPlanned - elapsed)

        let rescueDelay = rescueModeThresholdSeconds - elapsed
        if !didOfferInitialRescue, rescueDelay > 0, rescueDelay < remainingSeconds {
            scheduleRescueNotification(
                after: rescueDelay,
                identifier: rescueNotificationID,
                reminder: false
            )
        }

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
        // banner at T=0. The nudges at +30s and +90s remain only until Screen Time
        // confirms the selected apps have been shielded again.
        center.removePendingNotificationRequests(withIdentifiers: ["mivo.session.ended"])
    }

    func cancelSessionNotifications() {
        let identifiers = [
            "mivo.intervention.oneMinute",
            "mivo.intervention.done",
            rescueNotificationID,
            rescueReminderNotificationID
        ]
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
        center.removeDeliveredNotifications(withIdentifiers: [rescueNotificationID, rescueReminderNotificationID])
    }

    private func scheduleRescueNotification(after seconds: Int, identifier: String, reminder: Bool) {
        guard seconds > 0 else { return }
        let content = UNMutableNotificationContent()
        content.title = reminder ? "Five minutes passed" : "Still choosing this?"
        content.body = reminder
            ? "Open Mivo for the check-in you asked for."
            : "You have been scrolling for 27 minutes. Open Mivo for a gentle check-in."
        content.sound = .default
        content.categoryIdentifier = "MIVO_RESCUE"
        content.userInfo = ["mivoRoute": "rescue"]

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(max(1, seconds)), repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    private func clearRescueNotifications() {
        rescueReminderAt = nil
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [rescueNotificationID, rescueReminderNotificationID])
        removeDeliveredRescueNotifications()
    }

    private func removeDeliveredRescueNotifications() {
        UNUserNotificationCenter.current().removeDeliveredNotifications(
            withIdentifiers: [rescueNotificationID, rescueReminderNotificationID]
        )
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
