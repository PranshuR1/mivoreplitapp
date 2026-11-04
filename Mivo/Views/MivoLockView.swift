import SwiftUI
#if canImport(FamilyControls)
import FamilyControls
#endif

/// Protect ▸ Lock Mivo. Sets the lock up in a calm moment, shows what it holds,
/// and runs the only way out: ask, wait, then end it. See `MivoLock`.
struct MivoLockView: View {
    @ObservedObject private var manager = MivoLockManager.shared
    @Environment(\.scenePhase) private var scenePhase

    @State private var showsPasscodeStep = false
    @State private var chosenDelay = MivoLock.defaultDelay
    @State private var code: String?
    @State private var codeUnavailable = false
    @State private var isCaptured = UIScreen.main.isCaptured
    @State private var showScreenshotWarning = false
    @State private var working = false
    @State private var errorMessage: String?
    @State private var confirmEnd = false
    @State private var confirmForget = false
    @State private var screenTimeApproved = true
    @State private var hasProtectedApps = true

    var body: some View {
        ZStack {
            MivoColors.background.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: MivoMetrics.cardSpacing) {
                    if showsPasscodeStep {
                        passcodeStep
                    } else if let lock = manager.lock {
                        TimelineView(.periodic(from: .now, by: 30)) { context in
                            lockedContent(lock, now: context.date)
                        }
                    } else {
                        setupIntro
                    }
                }
                .padding(.horizontal, MivoMetrics.tabPadding)
                .padding(.top, 12)
                .padding(.bottom, MivoMetrics.scrollBottomPadding)
            }
        }
        .navigationTitle("Lock Mivo")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: refreshStatus)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { refreshStatus() }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.userDidTakeScreenshotNotification)) { _ in
            if showsPasscodeStep, code != nil { showScreenshotWarning = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIScreen.capturedDidChangeNotification)) { _ in
            isCaptured = UIScreen.main.isCaptured
        }
        .alert("Delete that screenshot", isPresented: $showScreenshotWarning) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("A screenshot keeps the code, and the lock only holds if you don't have it. Delete it from Photos and from Recently Deleted.")
        }
        .alert("Mivo lock", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .alert("End the lock?", isPresented: $confirmEnd) {
            Button("Stay locked", role: .cancel) { manager.stayLocked() }
            Button("End the lock", role: .destructive) { endLock() }
        } message: {
            Text("Mivo's switches open again and it shows your Screen Time passcode so you can turn it off in Settings.")
        }
        .alert("Forget this passcode?", isPresented: $confirmForget) {
            Button("Cancel", role: .cancel) {}
            Button("Forget it", role: .destructive) { manager.forgetCode() }
        } message: {
            Text("Only do this after turning the Screen Time passcode off in Settings. Mivo can't show it again.")
        }
    }

    // MARK: - Setup

    private var setupIntro: some View {
        VStack(alignment: .leading, spacing: MivoMetrics.cardSpacing) {
            header(
                eyebrow: "Not locked",
                title: "Make Mivo hard to turn off",
                body: "Set this up while you feel calm. When the urge hits later, turning Mivo off means asking first, then waiting."
            )

            if let oldCode = manager.revealedCode() {
                previousCodeCard(oldCode)
            }

            heldList(usesPasscode: MivoLockManager.systemLockAvailable)

            VStack(alignment: .leading, spacing: 8) {
                MivoSectionTitle(text: "How long the wait is")
                MivoCard {
                    VStack(alignment: .leading, spacing: 12) {
                        MivoSegmentedChips(
                            options: MivoLock.delayChoices.map { (value: $0, label: MivoLock.delayLabel($0)) },
                            selection: $chosenDelay,
                            horizontalPadding: 10
                        )
                        Text("You can make it longer later, never shorter. Once the wait is over you get 30 minutes to end the lock, then it locks again.")
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundColor(MivoColors.inkBody)
                            .lineSpacing(2)
                    }
                }
            }

            if !hasProtectedApps {
                notice("Pick the apps Mivo protects first, on Protect ▸ Apps & Screen Time. A lock with no apps holds nothing.")
            } else if !screenTimeApproved {
                notice("Mivo doesn't have Screen Time access, so nothing is blocked. Turn it on in Protect ▸ Apps & Screen Time first.")
            }

            if MivoLockManager.systemLockAvailable {
                MivoPrimaryButton(label: "Next: the Screen Time passcode", disabled: !canLock) {
                    beginPasscodeStep()
                }
                MivoTertiaryButton(label: "Lock inside Mivo only") {
                    startLock(usesPasscode: false)
                }
                .disabled(!canLock)
                .opacity(canLock ? 1 : 0.5)
            } else {
                notice("This iPhone is on iOS \(UIDevice.current.systemVersion). Before iOS 26.4, anyone can turn off Mivo's Screen Time access in Settings and Mivo can't stop it. The lock below covers Mivo's own switches; update iOS to add the passcode that covers Settings too.")
                MivoPrimaryButton(label: "Lock Mivo", disabled: !canLock) {
                    startLock(usesPasscode: false)
                }
            }
        }
    }

    private var passcodeStep: some View {
        VStack(alignment: .leading, spacing: MivoMetrics.cardSpacing) {
            header(
                eyebrow: "Step 2 of 2",
                title: "Set the Screen Time passcode",
                body: "This is the part that stops turning off Mivo's Screen Time access or deleting Mivo. Mivo made the code up and keeps it."
            )

            MivoCard {
                VStack(spacing: 6) {
                    if codeUnavailable {
                        Text("Mivo couldn't store a code safely, so it won't show one. Go back and try again.")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(MivoColors.timerRed)
                    } else if isCaptured {
                        Text("Hidden while the screen is being recorded")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(MivoColors.inkBody)
                    } else if let code {
                        Text(code.map(String.init).joined(separator: " "))
                            .font(.system(size: 44, weight: .bold, design: .monospaced))
                            .foregroundColor(MivoColors.ink)
                            .accessibilityLabel("Passcode \(code.map(String.init).joined(separator: " "))")
                        Text("Your Screen Time passcode")
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundColor(MivoColors.inkBody)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }

            VStack(alignment: .leading, spacing: 8) {
                MivoSectionTitle(text: "In Settings")
                MivoCard {
                    VStack(alignment: .leading, spacing: 12) {
                        step(1, "Open Settings, then Screen Time.")
                        step(2, "Tap Lock Screen Time Settings. If you already have a Screen Time passcode, tap Change Screen Time Passcode and enter your old one first.")
                        step(3, "Enter the code above, twice.")
                        step(4, "When iPhone asks for an Apple Account for recovery, skip it. With one, \u{201C}Forgot Passcode?\u{201D} resets the code in a minute.")
                    }
                }
            }

            notice("Don't write it down or screenshot it: Mivo shows it again only after your wait. Because you skip recovery, Mivo's copy is the only one. If this iPhone loses it (a new phone, an erase), erasing the iPhone is the only way to clear the passcode, so end the lock before you switch phones.")

            MivoInkButton(label: "Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            MivoPrimaryButton(label: manager.isLocked ? "I've set it" : "I've set it, lock Mivo", disabled: code == nil || working) {
                if manager.isLocked {
                    manager.addScreenTimePasscode()
                    leavePasscodeStep()
                } else {
                    startLock(usesPasscode: true)
                }
            }
            MivoTertiaryButton(label: "Back") {
                leavePasscodeStep()
            }
        }
    }

    // MARK: - Locked

    @ViewBuilder
    private func lockedContent(_ lock: MivoLock, now: Date) -> some View {
        let phase = lock.phase(at: now)
        VStack(alignment: .leading, spacing: MivoMetrics.cardSpacing) {
            header(
                eyebrow: "Locked",
                title: "Mivo is locked",
                body: "Since \(lock.lockedAt.formatted(date: .abbreviated, time: .shortened)). Ending it takes \(MivoLock.delayLabel(lock.delay)) of waiting.",
                eyebrowColor: MivoColors.keptInk
            )

            if !screenTimeApproved {
                notice(MivoLockManager.systemLockAvailable
                    ? "Mivo's Screen Time access is off, so nothing is blocked right now. Turn it back on in Settings ▸ Screen Time."
                    : "Mivo's Screen Time access is off, so nothing is blocked right now. Turn it back on in Settings ▸ Screen Time, and update to iOS 26.4 so it can be locked there too.")
            }

            switch phase {
            case .locked:
                heldList(usesPasscode: lock.usesScreenTimePasscode)
                if !lock.usesScreenTimePasscode, MivoLockManager.systemLockAvailable {
                    MivoPrimaryButton(label: "Add the Screen Time passcode") {
                        beginPasscodeStep()
                    }
                }
                longerWaitPicker(lock)
                MivoTertiaryButton(label: "Ask to unlock", color: MivoColors.inkMuted) {
                    requestUnlock()
                }
                .disabled(working)

            case .waiting(let opensAt):
                MivoCard {
                    VStack(alignment: .leading, spacing: 6) {
                        MivoEyebrow(text: "Unlock asked")
                        Text("Opens in \(Self.remaining(from: now, to: opensAt))")
                            .font(.system(size: 26, weight: .bold))
                            .foregroundColor(MivoColors.ink)
                        Text("At \(opensAt.formatted(date: .abbreviated, time: .shortened)). If it still matters then, you'll have 30 minutes to end the lock. Until then, everything stays locked.")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(MivoColors.inkBody)
                            .lineSpacing(2)
                    }
                }
                MivoPrimaryButton(label: "Never mind, stay locked") {
                    manager.stayLocked()
                }
                heldList(usesPasscode: lock.usesScreenTimePasscode)

            case .open(let closesAt):
                MivoCard {
                    VStack(alignment: .leading, spacing: 6) {
                        MivoEyebrow(text: "Wait over")
                        Text("You can end the lock")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(MivoColors.ink)
                        Text("Until \(closesAt.formatted(date: .omitted, time: .shortened)). After that it locks again.")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(MivoColors.inkBody)
                    }
                }
                MivoPrimaryButton(label: "Stay locked") {
                    manager.stayLocked()
                }
                MivoTertiaryButton(label: "End the lock", color: MivoColors.timerRed) {
                    confirmEnd = true
                }
                .disabled(working)
            }
        }
    }

    @ViewBuilder
    private func longerWaitPicker(_ lock: MivoLock) -> some View {
        let longer = MivoLock.delayChoices.filter { $0 > lock.delay }
        if !longer.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                MivoSectionTitle(text: "Make the wait longer")
                MivoListGroup {
                    ForEach(Array(longer.enumerated()), id: \.element) { index, delay in
                        if index > 0 { MivoListDivider(inset: 16) }
                        Button {
                            manager.lengthenDelay(to: delay)
                            HapticsService.selection()
                        } label: {
                            MivoListRow(title: MivoLock.delayLabel(delay), subtitle: "Can't be shortened again")
                        }
                        .buttonStyle(MivoRowPressStyle())
                    }
                }
            }
        }
    }

    // MARK: - Pieces

    private func heldList(usesPasscode: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            MivoSectionTitle(text: "What a lock holds")
            MivoCard {
                VStack(alignment: .leading, spacing: 10) {
                    held("Protection and the apps on your list: you can add apps, not remove them")
                    held("Opening social apps inside Mivo")
                    held("Late-night protection, once it's on")
                    held("Reset all data. Signing out keeps your apps protected")
                    if usesPasscode {
                        held("Turning off Mivo's Screen Time access, and deleting Mivo (the Screen Time passcode)")
                    }
                }
            }
        }
    }

    private func previousCodeCard(_ oldCode: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            MivoSectionTitle(text: "Your Screen Time passcode")
            MivoCard {
                VStack(alignment: .leading, spacing: 10) {
                    Text(oldCode.map(String.init).joined(separator: " "))
                        .font(.system(size: 30, weight: .bold, design: .monospaced))
                        .foregroundColor(MivoColors.ink)
                    Text("To turn it off: Settings ▸ Screen Time ▸ Change Screen Time Passcode ▸ Turn Off Screen Time Passcode. Locking again uses this same code.")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundColor(MivoColors.inkBody)
                        .lineSpacing(2)
                    Button("Forget this passcode") { confirmForget = true }
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(MivoColors.deep)
                }
            }
        }
    }

    private func header(eyebrow: String, title: String, body: String, eyebrowColor: Color = MivoColors.inkBody) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            MivoEyebrow(text: eyebrow, color: eyebrowColor)
            Text(title)
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(MivoColors.ink)
                .accessibilityAddTraits(.isHeader)
            Text(body)
                .font(.system(size: 13.5, weight: .medium))
                .foregroundColor(MivoColors.inkBody)
                .lineSpacing(2)
        }
        .padding(.horizontal, 4)
    }

    private func held(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "lock.fill")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(MivoColors.deep)
                .accessibilityHidden(true)
            Text(text)
                .font(.system(size: 13.5, weight: .medium))
                .foregroundColor(MivoColors.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(number)")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(MivoColors.deep)
                .frame(width: 16, alignment: .leading)
            Text(text)
                .font(.system(size: 13.5, weight: .medium))
                .foregroundColor(MivoColors.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func notice(_ text: String) -> some View {
        MivoCard {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(MivoColors.timerRed)
                    .accessibilityHidden(true)
                Text(text)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(MivoColors.ink)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Actions

    private var canLock: Bool { hasProtectedApps && screenTimeApproved }

    private func beginPasscodeStep() {
        code = manager.codeForSetup()
        codeUnavailable = code == nil
        showsPasscodeStep = true
    }

    private func leavePasscodeStep() {
        code = nil
        codeUnavailable = false
        showsPasscodeStep = false
    }

    private func startLock(usesPasscode: Bool) {
        guard manager.startLock(delay: chosenDelay, usesScreenTimePasscode: usesPasscode) else {
            errorMessage = MivoLockManager.UnlockError.couldNotSave.errorDescription
            return
        }
        HapticsService.success()
        leavePasscodeStep()
    }

    private func requestUnlock() {
        working = true
        Task {
            do { try await manager.requestUnlock() } catch { errorMessage = error.localizedDescription }
            working = false
        }
    }

    private func endLock() {
        working = true
        Task {
            do { try await manager.endLock() } catch { errorMessage = error.localizedDescription }
            working = false
        }
    }

    private func refreshStatus() {
        #if canImport(FamilyControls)
        if #available(iOS 16.0, *) {
            screenTimeApproved = AuthorizationCenter.shared.authorizationStatus == .approved
            hasProtectedApps = FamilyControlsManager.shared.hasImpulseSelection()
        }
        #endif
    }

    static func remaining(from now: Date, to end: Date) -> String {
        let minutes = max(1, Int((end.timeIntervalSince(now) / 60).rounded(.up)))
        let days = minutes / (24 * 60)
        let hours = (minutes % (24 * 60)) / 60
        let mins = minutes % 60
        if days > 0 { return "\(days) d \(hours) h" }
        if hours > 0 { return "\(hours) h \(mins) m" }
        return "\(mins) m"
    }
}
