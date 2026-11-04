import SwiftUI
#if canImport(FamilyControls)
import FamilyControls
#endif

/// Start a lock: what you'll do → which apps → a keyholder → make it hard to undo →
/// confirm. Nothing is locked until the last step.
struct LockInSetupFlowView: View {
    @EnvironmentObject private var appVM: AppViewModel
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var manager = LockInManager.shared
    @ObservedObject private var companion = CompanionStateManager.shared

    private enum Step: Int, CaseIterable { case task, apps, keyholder, harden, review }

    @State private var step: Step = .task
    @State private var task = ""
    @State private var durationMinutes = LockInRules.defaultDurationMinutes
    @State private var appSelection: ScreenTimeAppSelection
    @State private var screenTimeAllowed = LockInManager.shared.isScreenTimeAuthorized
    @State private var showPicker = false
    @State private var keyholderName = ""
    @State private var keyholderEmail = ""
    @State private var isInviting = false
    @State private var errorText: String?
    @FocusState private var taskFocused: Bool
    #if canImport(FamilyControls)
    @State private var pickerSelection: FamilyActivitySelection
    #endif

    private static let suggestions = ["Finish my essay outline", "Study for the exam", "Clear my inbox", "Go for a run"]

    init(initialTask: String = "") {
        _task = State(initialValue: initialTask)
        let last = LockInManager.shared.lastApps
        _appSelection = State(initialValue: last)
        #if canImport(FamilyControls)
        _pickerSelection = State(initialValue: last.activitySelection)
        #endif
    }

    private var steps: [Step] { Step.allCases }
    private var position: Int { step.rawValue + 1 }
    private var cleanedTask: String? { LockInRules.cleanTask(task) }
    private var miloName: String { companion.miloName }

    var body: some View {
        ZStack {
            MivoColors.background.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 0) {
                header.padding(.top, 8)

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        switch step {
                        case .task: taskPage
                        case .apps: appsPage
                        case .keyholder: keyholderPage
                        case .harden: hardenPage
                        case .review: reviewPage
                        }
                    }
                    .padding(.top, 26)
                    .padding(.bottom, 20)
                }
                .scrollDismissesKeyboard(.interactively)

                actions.padding(.bottom, 20)
            }
            .padding(.horizontal, MivoMetrics.screenPadding)
        }
        .animation(MivoMotion.stepEnter, value: step)
        #if canImport(FamilyControls)
        .familyActivityPicker(isPresented: $showPicker, selection: $pickerSelection)
        .onChange(of: pickerSelection) { _, newValue in
            appSelection = ScreenTimeAppSelection(newValue)
        }
        #endif
        .interactiveDismissDisabled(!task.isEmpty)
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(MivoColors.inkMuted)
                        .frame(width: 44, height: 44, alignment: .leading)
                }
                .accessibilityLabel("Close")
                Spacer()
                MivoEyebrow(text: "Step \(position) of \(steps.count)")
            }
            MivoSegmentBar(completed: position, total: steps.count, height: 3)
        }
    }

    // MARK: Step 1 — the task

    private var taskPage: some View {
        VStack(alignment: .leading, spacing: 0) {
            LockInTitle(
                title: "What will you get done?",
                detail: "One thing, in your own words. Mivo locks your apps until you've done it and shown \(miloName)."
            )

            TextField("e.g. Finish the essay outline", text: $task, axis: .vertical)
                .lineLimit(1...3)
                .font(.system(size: 17, weight: .semibold))
                .focused($taskFocused)
                .padding(16)
                .background(MivoColors.surfaceRaised)
                .clipShape(RoundedRectangle(cornerRadius: MivoMetrics.radius))
                .overlay(
                    RoundedRectangle(cornerRadius: MivoMetrics.radius)
                        .strokeBorder(taskFocused ? MivoColors.deep.opacity(0.6) : MivoColors.hairline, lineWidth: 1)
                )
                .onChange(of: task) { _, value in
                    if value.count > LockInRules.maxTaskLength {
                        task = String(value.prefix(LockInRules.maxTaskLength))
                    }
                }
                .padding(.top, 24)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Self.suggestions, id: \.self) { suggestion in
                        Button {
                            HapticsService.selection()
                            task = suggestion
                        } label: {
                            Text(suggestion)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(MivoColors.ink)
                                .padding(.vertical, 9)
                                .padding(.horizontal, 12)
                                .overlay(
                                    RoundedRectangle(cornerRadius: MivoMetrics.radius)
                                        .strokeBorder(MivoColors.ink.opacity(0.16), lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.top, 12)

            MivoSectionTitle(text: "Check in by")
                .padding(.top, 28)
            MivoChoiceChips(
                options: LockInRules.durationChoicesMinutes.map { (value: $0, label: LockInFormat.durationChoice($0)) },
                selection: $durationMinutes
            )
            .padding(.top, 10)

            LockInFootnote("Show \(miloName) before then. If time runs out first, your apps open and the lock is recorded as not done.")
                .padding(.top, 12)
        }
    }

    // MARK: Step 2 — apps

    private var appsPage: some View {
        VStack(alignment: .leading, spacing: 0) {
            LockInTitle(
                title: "Which apps?",
                detail: "Pick the apps that pull you away. They stay locked until the lock ends."
            )

            if screenTimeAllowed {
                if !appSelection.isEmpty {
                    LockInAppsLabel(apps: appSelection)
                        .padding(.top, 24)
                }

                MivoInkButton(label: appSelection.isEmpty ? "Choose apps" : "Change apps") {
                    HapticsService.selection()
                    showPicker = true
                }
                .padding(.top, 24)

                if hasProtectedApps {
                    MivoTertiaryButton(label: "Start from my protected apps") {
                        useProtectedApps()
                    }
                    .padding(.top, 4)
                }

                LockInFootnote("Apple keeps the list of your apps private. Mivo only receives anonymous tokens for the ones you pick.")
                    .padding(.top, 14)

                if let errorText {
                    Text(errorText)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(MivoColors.timerRed)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 12)
                }
            } else {
                Text("Mivo needs Screen Time access to lock apps. It stays on your device.")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(MivoColors.inkBody)
                    .lineSpacing(5)
                    .padding(.top, 24)

                MivoInkButton(label: "Allow Screen Time access") {
                    HapticsService.selection()
                    FamilyControlsManager.shared.requestAuthorization { granted in
                        screenTimeAllowed = granted
                    }
                }
                .padding(.top, 18)
            }
        }
    }

    private var hasProtectedApps: Bool {
        #if canImport(FamilyControls)
        FamilyControlsManager.shared.hasImpulseSelection()
        #else
        false
        #endif
    }

    private func useProtectedApps() {
        #if canImport(FamilyControls)
        HapticsService.selection()
        let existing = FamilyControlsManager.shared.loadFamilyActivitySelection()
        pickerSelection = existing
        appSelection = ScreenTimeAppSelection(existing)
        #endif
    }

    // MARK: Step 3 — keyholder

    private var keyholderPage: some View {
        VStack(alignment: .leading, spacing: 0) {
            LockInTitle(
                title: "Who has the last word?",
                detail: "A keyholder is a friend who approves your unlock. Without one, \(miloName) decides. You can skip this."
            )

            if let keyholder = manager.keyholder {
                MivoCard {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(keyholder.name)
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(MivoColors.ink)
                            Spacer()
                            LockInStatusPill(
                                text: keyholder.status == .active ? "Agreed" : "Invited",
                                tone: keyholder.status == .active ? .good : .warning
                            )
                        }
                        Text(keyholder.emailMasked)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(MivoColors.inkBody)
                        if keyholder.status != .active {
                            LockInFootnote("\(keyholder.name) hasn't agreed yet. Until they do, \(miloName) decides.")
                        }
                    }
                }
                .padding(.top, 24)
            } else {
                VStack(spacing: 10) {
                    keyholderField("Their name", text: $keyholderName, content: .givenName, keyboard: .default)
                    keyholderField("Their email", text: $keyholderEmail, content: .emailAddress, keyboard: .emailAddress)
                }
                .padding(.top, 24)

                LockInFootnote("They get one email asking if they'll be your keyholder. When you ask to unlock, they see the task and a sentence from \(miloName). Never your photos or your apps.")
                    .padding(.top, 12)

                if !manager.isBackendAvailable {
                    LockInFootnote("Keyholders need Mivo's online service, which isn't set up on this build.", tone: MivoColors.timerRed)
                        .padding(.top, 8)
                }
            }

            if let errorText {
                Text(errorText)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(MivoColors.timerRed)
                    .padding(.top, 12)
            }
        }
    }

    private func keyholderField(
        _ placeholder: String,
        text: Binding<String>,
        content: UITextContentType,
        keyboard: UIKeyboardType
    ) -> some View {
        TextField(placeholder, text: text)
            .font(.system(size: 16, weight: .semibold))
            .textContentType(content)
            .keyboardType(keyboard)
            .textInputAutocapitalization(keyboard == .emailAddress ? .never : .words)
            .autocorrectionDisabled(keyboard == .emailAddress)
            .padding(16)
            .background(MivoColors.surfaceRaised)
            .clipShape(RoundedRectangle(cornerRadius: MivoMetrics.radius))
            .overlay(
                RoundedRectangle(cornerRadius: MivoMetrics.radius)
                    .strokeBorder(MivoColors.hairline, lineWidth: 1)
            )
    }

    private var keyholderFormFilled: Bool {
        !keyholderName.trimmingCharacters(in: .whitespaces).isEmpty
            && LockInManager.isPlausibleEmail(keyholderEmail.trimmingCharacters(in: .whitespaces).lowercased())
    }

    // MARK: Step 4 — make it hard to undo

    private var hardenPage: some View {
        VStack(alignment: .leading, spacing: 0) {
            LockInTitle(
                title: "Make it hard to undo",
                detail: "Mivo locks the apps. But anyone can open Settings and switch off Mivo's Screen Time access. This step closes that door."
            )
            LockInScreenTimeGuideContent()
                .padding(.top, 22)
        }
    }

    // MARK: Step 5 — review

    private var reviewPage: some View {
        VStack(alignment: .leading, spacing: 0) {
            LockInTitle(title: "Ready to lock in?")

            MivoListGroup {
                MivoListRow(icon: "checkmark.circle", title: "The task", subtitle: cleanedTask ?? "—", showsChevron: false)
                MivoListDivider()
                MivoListRow(
                    icon: "clock",
                    title: "Check in by",
                    subtitle: LockInFormat.clock(Date().addingTimeInterval(LockInRules.duration(minutes: durationMinutes))),
                    showsChevron: false
                )
                MivoListDivider()
                MivoListRow(icon: "app.badge", title: "Locked apps", subtitle: appSelection.summary, showsChevron: false)
                MivoListDivider()
                MivoListRow(
                    icon: "person.badge.key",
                    title: "Last word",
                    subtitle: lastWord,
                    showsChevron: false
                )
            }
            .padding(.top, 24)

            LockInFootnote("You can undo this for the first \(Int(LockInRules.cancelGrace / 60)) minutes. After that, the apps stay locked until you've shown \(miloName)\(manager.keyholder?.status == .active ? " and \(manager.keyholder?.name ?? "your keyholder") approves" : ""), or until the check-in time.")
                .padding(.top, 14)

            if let errorText {
                Text(errorText)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(MivoColors.timerRed)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 12)
            }
        }
    }

    private var lastWord: String {
        guard let keyholder = manager.keyholder else { return "\(miloName) decides" }
        return keyholder.status == .active
            ? "\(keyholder.name) approves the unlock"
            : "\(miloName) decides until \(keyholder.name) agrees"
    }

    // MARK: Actions

    private var actions: some View {
        VStack(spacing: 4) {
            switch step {
            case .task:
                MivoPrimaryButton(label: "Continue", disabled: cleanedTask == nil) { go(.apps) }
            case .apps:
                MivoPrimaryButton(label: "Continue", disabled: appSelection.isEmpty) { go(.keyholder) }
                MivoTertiaryButton(label: "Back") { go(.task) }
            case .keyholder:
                if manager.keyholder == nil && keyholderFormFilled {
                    MivoPrimaryButton(label: isInviting ? "Sending…" : "Send invite and continue", disabled: isInviting || !manager.isBackendAvailable) {
                        invite()
                    }
                    MivoTertiaryButton(label: "Skip — \(miloName) decides") { go(.harden) }
                } else {
                    MivoPrimaryButton(label: manager.keyholder == nil ? "Continue without a keyholder" : "Continue") { go(.harden) }
                }
                MivoTertiaryButton(label: "Back") { go(.apps) }
            case .harden:
                MivoPrimaryButton(label: "Continue") { go(.review) }
                MivoTertiaryButton(label: "Back") { go(.keyholder) }
            case .review:
                MivoPrimaryButton(label: "Lock in") { startLock() }
                MivoTertiaryButton(label: "Back") { go(.harden) }
            }
        }
    }

    private func go(_ next: Step) {
        errorText = nil
        taskFocused = false
        HapticsService.selection()
        step = next
    }

    private func invite() {
        guard !isInviting else { return }
        isInviting = true
        errorText = nil
        Task {
            let result = await manager.inviteKeyholder(name: keyholderName, email: keyholderEmail)
            isInviting = false
            switch result {
            case .success:
                HapticsService.success()
                go(.harden)
            case .failure(let error):
                HapticsService.warning()
                errorText = error.message
            }
        }
    }

    private func startLock() {
        errorText = nil
        switch manager.start(task: task, durationMinutes: durationMinutes, apps: appSelection) {
        case .started(let lock):
            appVM.syncAttentionCommitments(current: lock, history: manager.history)
            HapticsService.success()
            dismiss()
        case .blocked(let limitations):
            if limitations.contains(.screenTimeNotAuthorized) { screenTimeAllowed = false }
            errorText = limitations.map(\.message).joined(separator: " ")
            step = limitations.contains(.screenTimeNotAuthorized) || limitations.contains(.noAppsSelected) ? .apps : step
            HapticsService.warning()
        case .invalidTask:
            errorText = "Write what you'll get done first."
            step = .task
        case .alreadyLocked:
            dismiss()
        }
    }
}
