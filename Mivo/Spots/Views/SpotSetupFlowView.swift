import SwiftUI
#if canImport(FamilyControls)
import FamilyControls
#endif

/// Create a Spot, or edit one: name → apps → what happens here.
///
/// With a `claim`, this is the first-scan experience for an official Mivo Spot:
/// "Meet your new Mivo Spot" → (connect to an existing setup, if there is one) →
/// the same three steps → done. Nothing is saved or claimed until the last step
/// is confirmed, so leaving early leaves the Mivo Spot unclaimed.
struct SpotSetupFlowView: View {
    let editing: MivoSpot?
    let claim: PhysicalSpotClaimRequest?

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var manager = SpotManager.shared

    private enum Step: Hashable { case welcome, choose, name, apps, behavior, done }

    private enum Choice: Hashable {
        case existing(String)
        case new
    }

    @State private var step: Step
    @State private var choice: Choice?
    @State private var isSaving = false
    @State private var templateID: String?
    @State private var name: String
    @State private var icon: String
    @State private var emojiText = ""
    @State private var appSelection: SpotAppSelection
    @State private var mode: SpotMode
    @State private var durationChoice: Int
    @State private var customMinutes: Int
    @State private var savedSpotID: String?
    @State private var saveError: String?
    @State private var screenTimeAllowed = FamilyControlsManager.shared.liveAuthorizationStatus()
    @State private var showPicker = false
    #if canImport(FamilyControls)
    @State private var pickerSelection: FamilyActivitySelection
    #endif

    // Duration choices are plain integers so one chip row can serve both lists.
    private static let customChoice = -1
    private static let openChoice = 0
    private static let focusChoices: [(value: Int, label: String)] = [(25, "25 min"), (60, "60 min"), (customChoice, "Custom")]
    private static let sustainedChoices: [(value: Int, label: String)] = [(60, "1 hr"), (120, "2 hr"), (240, "4 hr"), (openChoice, "Open")]

    init(editing: MivoSpot?, claim: PhysicalSpotClaimRequest? = nil) {
        self.editing = editing
        self.claim = claim
        _step = State(initialValue: claim == nil ? .name : .welcome)
        let spot = editing
        _name = State(initialValue: spot?.name ?? "")
        _icon = State(initialValue: spot?.icon ?? SpotIcon.defaultIcon)
        _appSelection = State(initialValue: spot?.selectedApplications ?? .empty)
        _mode = State(initialValue: spot?.mode ?? .pause)
        _savedSpotID = State(initialValue: spot?.id)
        #if canImport(FamilyControls)
        _pickerSelection = State(initialValue: spot?.selectedApplications.activitySelection ?? FamilyActivitySelection())
        #endif

        let initialMode = spot?.mode ?? .pause
        let minutes = spot?.defaultDurationMinutes
        let isFocus = initialMode == .focus
        let allowed = (isFocus ? Self.focusChoices : Self.sustainedChoices).map(\.value)
        if spot == nil {
            _durationChoice = State(initialValue: 60)
            _customMinutes = State(initialValue: 45)
        } else if let minutes, allowed.contains(minutes) {
            _durationChoice = State(initialValue: minutes)
            _customMinutes = State(initialValue: minutes)
        } else if let minutes {
            _durationChoice = State(initialValue: isFocus ? Self.customChoice : 60)
            _customMinutes = State(initialValue: min(max(minutes, 5), 240))
        } else {
            _durationChoice = State(initialValue: isFocus ? 60 : Self.openChoice)
            _customMinutes = State(initialValue: 45)
        }
    }

    var body: some View {
        ZStack {
            MivoColors.background.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                header
                    .padding(.top, 8)

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        switch step {
                        case .welcome: welcomePage
                        case .choose: choosePage
                        case .name: namePage
                        case .apps: appsPage
                        case .behavior: behaviorPage
                        case .done: donePage
                        }
                    }
                    .padding(.top, 26)
                    .padding(.bottom, 20)
                }

                actions
                    .padding(.bottom, 20)
            }
            .padding(.horizontal, MivoMetrics.screenPadding)
        }
        .animation(MivoMotion.stepEnter, value: step)
        #if canImport(FamilyControls)
        .familyActivityPicker(isPresented: $showPicker, selection: $pickerSelection)
        .onChange(of: pickerSelection) { _, newValue in
            appSelection = SpotAppSelection(newValue)
        }
        #endif
        .interactiveDismissDisabled(isSaving || (step != .done && hasUnsavedInput))
    }

    private var hasUnsavedInput: Bool {
        editing == nil && !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    // MARK: Steps

    /// Existing setups a new Mivo Spot could take over: Digital Spots only, since a
    /// Spot already tied to a Mivo Spot keeps it.
    private var candidates: [MivoSpot] {
        let digital = manager.spots.filter { !$0.isPhysical }
        if let pairID = claim?.pairWithSpotID { return digital.filter { $0.id == pairID } }
        return digital
    }

    private var steps: [Step] {
        guard claim != nil else { return [.name, .apps, .behavior] }
        return [.welcome] + (candidates.isEmpty ? [] : [.choose]) + [.name, .apps, .behavior, .done]
    }

    private var stepPosition: Int { (steps.firstIndex(of: step) ?? 0) + 1 }

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
                MivoEyebrow(text: "Step \(stepPosition) of \(steps.count)")
            }
            MivoSegmentBar(completed: stepPosition, total: steps.count, height: 3)
        }
    }

    // MARK: Welcome (a Mivo Spot was just scanned)

    private var welcomePage: some View {
        VStack(alignment: .leading, spacing: 0) {
            Image(systemName: "wave.3.right")
                .font(.system(size: 26, weight: .semibold))
                .foregroundColor(MivoColors.deep)
                .frame(width: 64, height: 64)
                .background(MivoColors.surfaceV2)
                .clipShape(RoundedRectangle(cornerRadius: MivoMetrics.radius))
                .accessibilityHidden(true)

            Text("Meet your new Mivo Spot")
                .font(.system(size: 27, weight: .bold))
                .tracking(Font.mivoTracking(-0.025, at: 27))
                .foregroundColor(MivoColors.ink)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 22)

            Text(claim?.alreadyYours == true
                 ? "This Mivo Spot is already yours. Set up what it does on this iPhone."
                 : "Tap it with your iPhone to start a Spot, and tap it again to end it. Set it up once here.")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(MivoColors.inkBody)
                .lineSpacing(5)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 12)

            Text("Your Mivo Spot only holds its own ID. What it does lives in Mivo, so you can change it any time — even turn a Study Spot into a Sleep Spot — without touching the Mivo Spot.")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(MivoColors.inkMuted)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 14)
        }
    }

    // MARK: Connect to an existing setup

    private var choosePage: some View {
        let isPairing = claim?.pairWithSpotID != nil
        return VStack(alignment: .leading, spacing: 0) {
            Text(isPairing ? "Connect this Mivo Spot?" : "Connect this Mivo Spot to an existing setup?")
                .font(.system(size: 27, weight: .bold))
                .tracking(Font.mivoTracking(-0.025, at: 27))
                .foregroundColor(MivoColors.ink)
                .fixedSize(horizontal: false, vertical: true)

            Text("It keeps that Spot's apps, behavior and history. Tapping the Mivo Spot will start it.")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(MivoColors.inkBody)
                .lineSpacing(5)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 12)

            VStack(spacing: 9) {
                ForEach(candidates) { spot in
                    MivoOptionRow(
                        label: spot.name,
                        note: "\(spot.mode.cardLabel) · \(spot.selectedApplications.summary)",
                        isSelected: choice == .existing(spot.id)
                    ) {
                        HapticsService.selection()
                        choice = .existing(spot.id)
                    }
                }
                if !isPairing {
                    MivoOptionRow(label: "Create new", isSelected: choice == .new) {
                        HapticsService.selection()
                        choice = .new
                    }
                }
            }
            .padding(.top, 22)

            errorText
        }
        .onAppear {
            if choice == nil, let pairID = claim?.pairWithSpotID { choice = .existing(pairID) }
        }
    }

    // MARK: Done

    private var donePage: some View {
        let spot = savedSpotID.flatMap { manager.spot(id: $0) }
        return VStack(alignment: .leading, spacing: 0) {
            if let spot {
                SpotIconView(icon: spot.icon, size: 64)
            }

            Text(spot.map { "\($0.name) is ready" } ?? "Your Mivo Spot is ready")
                .font(.system(size: 27, weight: .bold))
                .tracking(Font.mivoTracking(-0.025, at: 27))
                .foregroundColor(MivoColors.ink)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, spot == nil ? 0 : 22)

            Text("Tap your Mivo Spot with your iPhone any time to start it, and tap it again to end it. You can change what it does in Mivo Spots whenever you like.")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(MivoColors.inkBody)
                .lineSpacing(5)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 12)
        }
    }

    @ViewBuilder
    private var errorText: some View {
        if let saveError {
            Text(saveError)
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundColor(MivoColors.inkBody)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 14)
        }
    }

    // MARK: Step 1 — name

    private var namePage: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(editing != nil ? "Edit your Spot" : claim == nil ? "Name your Spot" : "Name your Mivo Spot")
                .font(.system(size: 27, weight: .bold))
                .tracking(Font.mivoTracking(-0.025, at: 27))
                .foregroundColor(MivoColors.ink)
                .fixedSize(horizontal: false, vertical: true)

            Text(claim == nil
                 ? "A Spot is a place where you want to use your phone more intentionally."
                 : "Pick what this Mivo Spot is for — Study, Sleep, Work, anything. You can change it later.")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(MivoColors.inkBody)
                .lineSpacing(5)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 12)

            if editing == nil {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 9), GridItem(.flexible(), spacing: 9)], spacing: 9) {
                    ForEach(SpotTemplate.all) { template in
                        MivoOptionRow(label: template.displayName, isSelected: templateID == template.id) {
                            apply(template)
                        }
                    }
                }
                .padding(.top, 22)
            }

            MivoTextField(label: "Name", placeholder: "e.g. Study Desk", text: $name)
                .padding(.top, 22)

            MivoEyebrow(text: "Icon")
                .padding(.top, 26)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 9) {
                    ForEach(SpotIconChoices.symbols, id: \.self) { symbol in
                        iconTile(SpotIcon.symbol(symbol))
                    }
                }
                .padding(.vertical, 2)
            }
            .padding(.top, 12)

            MivoTextField(
                label: "Or use an emoji",
                placeholder: "🙂",
                text: $emojiText
            )
            .padding(.top, 16)
            .onChange(of: emojiText) { _, newValue in
                let trimmed = newValue.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty else { return }
                icon = SpotIcon.emoji(from: trimmed)
                // Keep the field to the one character that was taken.
                if trimmed.count > 1 { emojiText = icon }
            }
        }
    }

    private func iconTile(_ value: String) -> some View {
        Button {
            HapticsService.selection()
            icon = value
            emojiText = ""
        } label: {
            SpotIconView(icon: value, size: 48)
                .overlay(
                    RoundedRectangle(cornerRadius: MivoMetrics.radius)
                        .strokeBorder(icon == value ? MivoColors.deep.opacity(0.6) : .clear, lineWidth: 1.5)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Icon option")
        .accessibilityAddTraits(icon == value ? .isSelected : [])
    }

    private func apply(_ template: SpotTemplate) {
        HapticsService.selection()
        templateID = template.id
        if template.isCustom {
            name = ""
        } else {
            name = template.name
            icon = template.icon
            emojiText = ""
            if editing == nil { setMode(template.suggestedMode) }
        }
    }

    // MARK: Step 2 — apps

    private var appsPage: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Choose apps")
                .font(.system(size: 27, weight: .bold))
                .tracking(Font.mivoTracking(-0.025, at: 27))
                .foregroundColor(MivoColors.ink)

            Text("Pick the distracting apps this Spot should look after. You can change them any time.")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(MivoColors.inkBody)
                .lineSpacing(5)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 12)

            if screenTimeAllowed {
                if !appSelection.isEmpty {
                    SpotAppLabels(selection: appSelection)
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

                Text("Apple keeps the list of your apps private. Mivo only receives anonymous tokens for the ones you pick.")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundColor(MivoColors.inkMuted)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 14)
            } else {
                Text("Mivo needs Screen Time access to see and pause the apps you choose. It stays on your device.")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(MivoColors.inkBody)
                    .lineSpacing(5)
                    .fixedSize(horizontal: false, vertical: true)
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
        appSelection = SpotAppSelection(existing)
        #endif
    }

    // MARK: Step 3 — behaviour

    private var behaviorPage: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("What happens here?")
                .font(.system(size: 27, weight: .bold))
                .tracking(Font.mivoTracking(-0.025, at: 27))
                .foregroundColor(MivoColors.ink)

            Text("Pick how this Spot should nudge you. Mivo adds friction and awareness — it never locks you out.")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(MivoColors.inkBody)
                .lineSpacing(5)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 12)

            VStack(spacing: 9) {
                ForEach(SpotMode.allCases) { option in
                    MivoOptionRow(label: option.title, isSelected: mode == option) {
                        HapticsService.selection()
                        setMode(option)
                    }
                }
            }
            .padding(.top, 22)

            Text(mode.detail)
                .font(.system(size: 13.5, weight: .medium))
                .foregroundColor(MivoColors.inkBody)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 14)
                .id(mode)
                .transition(.opacity)

            MivoEyebrow(text: mode == .focus ? "Session length" : "Stay on for")
                .padding(.top, 28)

            MivoChoiceChips(options: durationOptions, selection: $durationChoice)
                .padding(.top, 12)

            if durationChoice == Self.customChoice {
                minutesStepper
                    .padding(.top, 16)
            }

            errorText
        }
        .animation(MivoMotion.standard(0.18), value: mode)
        .animation(MivoMotion.standard(0.18), value: durationChoice)
    }

    private var durationOptions: [(value: Int, label: String)] {
        mode == .focus ? Self.focusChoices : Self.sustainedChoices
    }

    private func setMode(_ newMode: SpotMode) {
        let wasFocus = mode == .focus
        mode = newMode
        let isFocus = newMode == .focus
        guard wasFocus != isFocus else { return }
        // The two modes offer different lengths; 60 minutes is on both lists.
        durationChoice = 60
    }

    private var minutesStepper: some View {
        HStack(spacing: 22) {
            stepperButton("minus") { customMinutes = max(5, customMinutes - 5) }
            Text(SpotFormat.duration(minutes: customMinutes))
                .font(.system(size: 20, weight: .bold))
                .monospacedDigit()
                .foregroundColor(MivoColors.ink)
                .frame(minWidth: 110)
                .contentTransition(.numericText())
            stepperButton("plus") { customMinutes = min(240, customMinutes + 5) }
        }
        .frame(maxWidth: .infinity)
    }

    private func stepperButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button {
            HapticsService.selection()
            action()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(MivoColors.ink)
                .frame(width: 44, height: 44)
                .background(MivoColors.surfaceV2)
                .clipShape(RoundedRectangle(cornerRadius: MivoMetrics.radius))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(symbol == "plus" ? "More time" : "Less time")
    }

    // MARK: Actions

    @ViewBuilder
    private var actions: some View {
        VStack(spacing: 4) {
            switch step {
            case .welcome:
                MivoPrimaryButton(label: "Set it up") {
                    go(candidates.isEmpty ? .name : .choose)
                }
            case .choose:
                MivoPrimaryButton(
                    label: isSaving ? "Connecting…" : choice == .new ? "Continue" : "Connect",
                    disabled: choice == nil || isSaving
                ) {
                    continueFromChoice()
                }
                MivoTertiaryButton(label: "Back") { go(.welcome) }
                    .disabled(isSaving)
            case .name:
                MivoPrimaryButton(label: "Continue", disabled: trimmedName.isEmpty) { go(.apps) }
                if let back = backFromName {
                    MivoTertiaryButton(label: "Back") { go(back) }
                }
            case .apps:
                MivoPrimaryButton(label: "Continue", disabled: appSelection.isEmpty) { go(.behavior) }
                MivoTertiaryButton(label: "Back") { go(.name) }
            case .behavior:
                MivoPrimaryButton(
                    label: isSaving ? "Saving…" : claim == nil ? "Save" : "Finish",
                    disabled: isSaving
                ) {
                    saveTapped()
                }
                MivoTertiaryButton(label: "Back") { go(.apps) }
                    .disabled(isSaving)
            case .done:
                MivoPrimaryButton(label: "Done") { dismiss() }
                if let savedSpotID {
                    MivoTertiaryButton(label: "Start it now") {
                        manager.handleScan(spotID: savedSpotID, trigger: .manual)
                        dismiss()
                    }
                }
            }
        }
    }

    private var backFromName: Step? {
        guard claim != nil else { return nil }
        return candidates.isEmpty ? .welcome : .choose
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var resolvedDurationMinutes: Int? {
        switch durationChoice {
        case Self.openChoice: return nil
        case Self.customChoice: return customMinutes
        default: return durationChoice
        }
    }

    private func go(_ next: Step) {
        HapticsService.selection()
        withAnimation(MivoMotion.stepEnter) { step = next }
    }

    private func continueFromChoice() {
        saveError = nil
        switch choice {
        case .new:
            go(.name)
        case .existing(let id):
            guard let claim, let spot = manager.spot(id: id) else { return }
            claimPhysicalSpot(claim, configuring: spot)
        case nil:
            break
        }
    }

    private func saveTapped() {
        var spot = editing.flatMap { manager.spot(id: $0.id) } ?? MivoSpot(name: trimmedName)
        spot.name = trimmedName
        spot.icon = icon
        spot.selectedApplications = appSelection
        spot.mode = mode
        spot.defaultDurationMinutes = resolvedDurationMinutes

        if let claim {
            claimPhysicalSpot(claim, configuring: spot)
            return
        }
        switch manager.save(spot) {
        case .success:
            saveError = nil
            HapticsService.success()
            dismiss()
        case .failure(.emptyName):
            saveError = PhysicalSpotError.emptyName.message
        case .failure(.tooManySpots):
            saveError = PhysicalSpotError.tooManySpots.message
        }
    }

    /// Claims the Mivo Spot and saves the setup together. Nothing is kept if the
    /// claim fails (someone else got there first, no internet, …).
    private func claimPhysicalSpot(_ claim: PhysicalSpotClaimRequest, configuring spot: MivoSpot) {
        guard !isSaving else { return }
        isSaving = true
        saveError = nil
        Task {
            let result = await manager.claimPhysicalSpot(physicalID: claim.physicalID, configuring: spot)
            isSaving = false
            switch result {
            case .success(let saved):
                savedSpotID = saved.id
                HapticsService.success()
                go(.done)
            case .failure(let error):
                HapticsService.warning()
                saveError = error.message
            }
        }
    }
}
