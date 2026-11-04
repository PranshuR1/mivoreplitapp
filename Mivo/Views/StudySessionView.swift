import AudioToolbox
import AVFoundation
import SwiftUI
#if canImport(FamilyControls)
import FamilyControls
#endif

/// The study flow: name the one thing, prop the phone up across the room and
/// let it film your hands and desk, then get a receipt, a streak and the
/// scroll time the video earned. Face optional — the back camera is used.
struct StudySessionView: View {
    @ObservedObject private var study: StudyService
    @ObservedObject private var companion = CompanionStateManager.shared
    @ObservedObject private var plus = MivoPlusStore.shared
    @EnvironmentObject private var appVM: AppViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .largeTitle) private var heroSize = 38

    @State private var paywallFeature: PlusFeature?
    @FocusState private var taskFocused: Bool
    @State private var task = ""
    /// Desk or Mac is remembered, so a person who always studies one way never picks it again.
    @AppStorage("mivo.study.lastPlace.computer") private var onComputer = false
    @State private var showingOptions = false
    @State private var plan = PhoneStudyPlan()
    @State private var websiteInput = ""
    @State private var websiteMessage: String?
    @State private var pickerMessage: String?
    @State private var showingDistractionPicker = false
    #if canImport(FamilyControls)
    @State private var distractionSelection = FamilyActivitySelection()
    #endif
    @State private var confirmingNewLink = false
    @State private var copiedLink = false
    @State private var isCharging = UIDevice.current.batteryState == .charging || UIDevice.current.batteryState == .full

    init(study: StudyService? = nil) {
        self.study = study ?? .shared
    }

    var body: some View {
        ZStack {
            MivoColors.background.ignoresSafeArea()
            if let linked = study.linkedSession {
                linkedSession(linked)
            } else {
                switch study.phase {
                case .idle: idle
                case .running(let active): running(active)
                case .finished(let receipt): finished(receipt)
                }
            }
        }
        .onAppear {
            UIDevice.current.isBatteryMonitoringEnabled = true
            updateChargingState()
            plan = study.savedPlan
            // "Done looks like" belongs to one session; the rest of the setup carries over.
            plan.outcome = ""
            #if DEBUG
            let arguments = ProcessInfo.processInfo.arguments
            if arguments.contains("-MivoPreviewStudyMaterials") || arguments.contains("-MivoPreviewStudyGoal") { showingOptions = true }
            #endif
            #if canImport(FamilyControls)
            if let data = plan.distractionSelection, let selected = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data) { distractionSelection = selected }
            #endif
            if task.isEmpty, let suggested = study.suggestedTask {
                task = String(suggested.prefix(StudyService.taskCharacterLimit))
            }
            study.suggestedTask = nil
        }
        .onDisappear { UIDevice.current.isBatteryMonitoringEnabled = false }
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.batteryStateDidChangeNotification)) { _ in
            updateChargingState()
        }
        .interactiveDismissDisabled(study.isStarting || study.phase.isRunning)
        .task { await study.refreshRoom() }
        #if canImport(FamilyControls)
        .familyActivityPicker(isPresented: $showingDistractionPicker, selection: $distractionSelection)
        .onChange(of: distractionSelection) { _, selection in
            plan.distractionSelection = try? JSONEncoder().encode(selection)
            plan.distractionCount = selection.applicationTokens.count + selection.categoryTokens.count + selection.webDomainTokens.count
        }
        #endif
        .sheet(item: $paywallFeature) { feature in
            MivoPlusPaywallView(feature: feature)
                .environmentObject(appVM)
        }
    }

    private func updateChargingState() {
        isCharging = UIDevice.current.batteryState == .charging || UIDevice.current.batteryState == .full
    }

    private var hasPlus: Bool {
        MivoPlusAccess.allows(isPlus: plus.isPlus, isAdmin: appVM.isAdminUser)
    }

    private var earnsScroll: Bool {
        StudyTrial.earnsScroll(study.trialPhase, hasPlus: hasPlus)
    }

    private var setupLocked: Bool { study.isStarting || study.linkedBusy }

    // MARK: - Before

    /// One screen: name the thing, pick a goal, start. Everything else is optional and folded away.
    private var idle: some View {
        VStack(spacing: 0) {
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.subheadline.weight(.semibold)).foregroundColor(MivoColors.inkBody)
                        .frame(width: 44, height: 44).background(MivoColors.surfaceV2, in: Circle())
                }
                .accessibilityLabel("Close study setup")
                .disabled(setupLocked)
                Spacer()
                if study.streak > 0 {
                    Label(StudyFormat.days(study.streak), systemImage: "flame")
                        .font(.footnote.weight(.semibold)).foregroundColor(MivoColors.ink)
                        .padding(.horizontal, 12).frame(height: 32)
                        .background(MivoColors.surfaceV2, in: Capsule())
                        .accessibilityLabel("\(StudyFormat.days(study.streak)) study streak")
                }
            }
            .padding(.horizontal, 24).padding(.top, 10).padding(.bottom, 4)
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    setupHeading("What are you\nworking on?", detail: onComputer
                        ? "Name it here, then your Mac counts the focused time."
                        : "Name one thing, pick a goal and start. You can finish early or keep going.")
                    if let last = quickStartEntry { quickStartCard(last) }
                    taskField
                    if !onComputer { goalPicker }
                    VStack(alignment: .leading, spacing: 12) {
                        sectionLabel(nil, "Where are you studying?")
                        if dynamicTypeSize.isAccessibilitySize { VStack(spacing: 12) { studyModes } }
                        else { HStack(spacing: 12) { studyModes } }
                    }
                    setupGuide
                    if !onComputer { optionsSection }
                    DisclosureGroup("Your room and study history") {
                        VStack(spacing: 18) { roomCard; stats; recentSessions }.padding(.top, 18)
                    }
                    .font(.subheadline.weight(.medium)).foregroundColor(MivoColors.inkBody).tint(MivoColors.inkBody)
                }
                .padding(.horizontal, 24).padding(.top, 18).padding(.bottom, 28)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { startBar }
        .animation(.easeInOut(duration: 0.18), value: showingOptions)
        .animation(.easeInOut(duration: 0.18), value: onComputer)
        .animation(.easeInOut(duration: 0.18), value: quickStartEntry?.id)
    }

    private var sortedEntries: [StudyEntry] { study.log.entries.sorted { $0.startedAt > $1.startedAt } }

    /// The last thing studied, offered as a one-tap restart while the field is empty.
    private var quickStartEntry: StudyEntry? {
        guard task.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return sortedEntries.first
    }

    /// Other recent tasks, one tap to fill the field. Never repeats the quick-start task or what is typed.
    private var recentTasks: [String] {
        var seen = Set<String>()
        if let quick = quickStartEntry { seen.insert(quick.task.lowercased()) }
        seen.insert(task.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
        return sortedEntries.map(\.task).filter { seen.insert($0.lowercased()).inserted }.prefix(4).map { $0 }
    }

    private func quickStartCard(_ entry: StudyEntry) -> some View {
        Button {
            task = entry.task
            begin(task: entry.task)
        } label: {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("PICK UP WHERE YOU LEFT OFF")
                        .font(.system(size: 10, weight: .bold)).tracking(1.2).foregroundColor(MivoColors.inkBody)
                    Text(entry.task)
                        .font(.headline).foregroundColor(MivoColors.ink)
                        .lineLimit(2).multilineTextAlignment(.leading)
                    Text(onComputer ? "On my Mac" : "\(plan.minutes) min · At my desk")
                        .font(.caption).foregroundColor(MivoColors.inkBody)
                }
                Spacer(minLength: 8)
                Image(systemName: onComputer ? "laptopcomputer" : "play.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(MivoColors.background)
                    .frame(width: 50, height: 50)
                    .background(MivoColors.ink, in: Circle())
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(MivoColors.surfaceV2, in: RoundedRectangle(cornerRadius: 22))
            .contentShape(RoundedRectangle(cornerRadius: 22))
        }
        .buttonStyle(.plain)
        .disabled(setupLocked)
        .accessibilityLabel(onComputer ? "Study \(entry.task) again on my Mac" : "Start \(entry.task) again, \(plan.minutes) minutes")
    }

    private var taskField: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField(quickStartEntry == nil ? "e.g. Finish Chapter 4 notes" : "Or something new…", text: $task, axis: .vertical)
                .font(.title3.weight(.medium)).foregroundColor(MivoColors.ink).lineLimit(1...3)
                .focused($taskFocused).submitLabel(.done).onSubmit { taskFocused = false }
                .accessibilityLabel("Study task").disabled(setupLocked)
                .onChange(of: task) { _, value in task = String(value.prefix(StudyService.taskCharacterLimit)) }
                .padding(18)
                .background(MivoColors.surfaceRaised, in: RoundedRectangle(cornerRadius: 20))
                .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(taskFocused ? MivoColors.ink : MivoColors.hairlineSoft))
            if !recentTasks.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(recentTasks, id: \.self) { recent in
                            Button {
                                task = recent
                                taskFocused = false
                                HapticsService.selection()
                            } label: {
                                Label(recent, systemImage: "arrow.uturn.backward")
                                    .font(.footnote.weight(.medium)).lineLimit(1)
                                    .frame(maxWidth: 240, alignment: .leading)
                                    .foregroundColor(MivoColors.ink)
                                    .padding(.horizontal, 14).frame(minHeight: 40)
                                    .background(MivoColors.surfaceV2, in: Capsule())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Use \(recent)")
                            .disabled(setupLocked)
                        }
                    }
                }
            }
        }
    }

    private var goalPicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel(nil, "Focus goal")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 70), spacing: 8)], spacing: 8) {
                ForEach([15, 25, 45, 60], id: \.self) { minutes in
                    Button { plan.minutes = minutes; HapticsService.selection() } label: {
                        Text("\(minutes) min").font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 48)
                            .foregroundColor(plan.minutes == minutes ? MivoColors.background : MivoColors.ink)
                            .background(plan.minutes == minutes ? MivoColors.ink : MivoColors.surfaceRaised, in: RoundedRectangle(cornerRadius: 14))
                            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(plan.minutes == minutes ? .clear : MivoColors.hairlineSoft))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(plan.minutes == minutes ? .isSelected : [])
                    .disabled(setupLocked)
                }
            }
        }
    }

    /// Done-looks-like, app pausing and materials: worth having, never in the way.
    private var optionsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                taskFocused = false
                showingOptions.toggle()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.subheadline.weight(.semibold)).foregroundColor(MivoColors.inkBody)
                        .frame(width: 20)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Session options").font(.subheadline.weight(.semibold)).foregroundColor(MivoColors.ink)
                        Text(optionsSummary).font(.caption).foregroundColor(MivoColors.inkBody)
                            .lineLimit(2).multilineTextAlignment(.leading)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.down")
                        .font(.footnote.weight(.semibold)).foregroundColor(MivoColors.inkBody)
                        .rotationEffect(.degrees(showingOptions ? 180 : 0))
                }
                .padding(16)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(showingOptions ? "Hides session options" : "Shows done looks like, app pausing and materials")
            if showingOptions {
                Rectangle().fill(MivoColors.hairlineSoft).frame(height: 1).padding(.horizontal, 16)
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 10) {
                        sectionLabel(nil, "Done looks like")
                        TextField("e.g. 2 pages of notes (optional)", text: $plan.outcome, axis: .vertical)
                            .font(.subheadline).foregroundColor(MivoColors.ink).lineLimit(1...3)
                            .padding(14).background(MivoColors.background, in: RoundedRectangle(cornerRadius: 14))
                            .onChange(of: plan.outcome) { _, value in plan.outcome = String(value.prefix(160)) }
                            .accessibilityLabel("What would done look like?")
                    }
                    distractionSetup
                    materialsSetup
                }
                .padding(16)
                .disabled(setupLocked)
            }
        }
        .background(MivoColors.surfaceRaised, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(MivoColors.hairlineSoft))
    }

    private var optionsSummary: String {
        var parts = [plan.hasDistractions ? "\(plan.distractionCount) \(plan.distractionCount == 1 ? "distraction" : "distractions") paused" : "No apps paused"]
        if plan.usesPaper { parts.append("Books & paper") }
        if !plan.websites.isEmpty { parts.append(plan.websites.count == 1 ? "1 website" : "\(plan.websites.count) websites") }
        if !plan.outcome.isEmpty { parts.append("Goal written") }
        return parts.joined(separator: " · ")
    }

    private var materialsSetup: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionLabel(nil, "Materials")
            Toggle(isOn: $plan.usesPaper) {
                Label("Books, paper or printed notes", systemImage: "book.closed")
                    .font(.subheadline.weight(.medium)).foregroundColor(MivoColors.ink)
            }.tint(MivoColors.kept)
            Text("Websites to have open on your computer or tablet. Your iPhone stays with the camera.")
                .font(.footnote).foregroundColor(MivoColors.inkBody).fixedSize(horizontal: false, vertical: true)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 10)], spacing: 10) {
                ForEach(Array(Set(["docs.google.com", "khanacademy.org", "quizlet.com", "wikipedia.org"] + plan.websites)).sorted(), id: \.self) { site in
                    Button {
                        if plan.websites.contains(site) { plan.websites.removeAll { $0 == site } }
                        else { plan.websites.append(site) }
                    } label: {
                        HStack(spacing: 6) {
                            Text(site).font(.caption.weight(.medium)).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                            Image(systemName: plan.websites.contains(site) ? "checkmark.circle.fill" : "circle").foregroundColor(plan.websites.contains(site) ? MivoColors.keptInk : MivoColors.inkBody)
                        }
                        .foregroundColor(MivoColors.ink).padding(14)
                        .background(plan.websites.contains(site) ? MivoColors.surfaceV2 : MivoColors.background, in: RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(plan.websites.contains(site) ? MivoColors.ink : MivoColors.hairline))
                    }.buttonStyle(.plain).accessibilityAddTraits(plan.websites.contains(site) ? .isSelected : [])
                }
            }
            HStack(spacing: 8) {
                TextField("Add a website", text: $websiteInput)
                    .font(.subheadline).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    .submitLabel(.done).onSubmit(addStudyWebsite)
                    .padding(14).background(MivoColors.background, in: RoundedRectangle(cornerRadius: 14))
                Button(action: addStudyWebsite) {
                    Image(systemName: "plus").font(.body.weight(.semibold)).frame(width: 48, height: 48)
                        .foregroundColor(MivoColors.ink).background(MivoColors.surfaceV2, in: RoundedRectangle(cornerRadius: 14))
                }.accessibilityLabel("Add study website").disabled(websiteInput.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if let websiteMessage { Text(websiteMessage).font(.footnote).foregroundColor(MivoColors.secondary) }
        }
    }

    private var distractionSetup: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel(nil, "Put distractions on pause")
            Text("Pause chosen apps and sites for \(plan.minutes) minutes. They come back when you finish, leave Mivo or reach your goal.")
                .font(.footnote).foregroundColor(MivoColors.inkBody).fixedSize(horizontal: false, vertical: true)
            #if canImport(FamilyControls)
            Button {
                Task { @MainActor in
                    do {
                        try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
                        pickerMessage = nil
                        showingDistractionPicker = true
                    } catch {
                        pickerMessage = "Screen Time access wasn't granted. You can still study without pausing apps."
                    }
                }
            } label: {
                HStack {
                    Label(plan.hasDistractions ? "\(plan.distractionCount) items selected" : "Choose distractions", systemImage: "app.badge")
                    Spacer()
                    Image(systemName: "chevron.right")
                }.font(.subheadline.weight(.medium)).foregroundColor(MivoColors.ink).padding(16)
                    .background(MivoColors.surfaceV2, in: RoundedRectangle(cornerRadius: 14))
            }.buttonStyle(.plain)
            if plan.hasDistractions {
                Button("Clear distraction choices") { distractionSelection = FamilyActivitySelection(); plan.distractionSelection = nil; plan.distractionCount = 0 }
                    .font(.footnote.weight(.medium)).foregroundColor(MivoColors.deep).frame(minHeight: 44)
            }
            #endif
            if let pickerMessage { Text(pickerMessage).font(.footnote).foregroundColor(MivoColors.secondary) }
        }
    }

    private func setupHeading(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.system(size: heroSize, weight: .regular, design: .serif)).tracking(-1)
                .foregroundColor(MivoColors.ink).fixedSize(horizontal: false, vertical: true)
            Text(detail).font(.subheadline).foregroundColor(MivoColors.inkBody).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func addStudyWebsite() {
        guard let host = PhoneStudyPlan.website(websiteInput) else { websiteMessage = "Enter a website such as canvas.school.edu or paste an https link."; return }
        if !plan.websites.contains(host) { plan.websites.append(host) }
        websiteInput = ""
        websiteMessage = nil
    }

    private func sectionLabel(_ number: String?, _ title: String) -> some View {
        HStack(spacing: 9) {
            if let number {
                Text(number)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(MivoColors.inkBody)
                    .frame(width: 26, height: 26)
                    .background(MivoColors.surfaceV2, in: Circle())
            }
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(MivoColors.ink)
        }
    }

    @ViewBuilder
    private var studyModes: some View {
        studyMode(computer: false, icon: "camera", title: "At my desk", detail: "Record on iPhone")
        studyMode(computer: true, icon: "laptopcomputer", title: "On my Mac", detail: "Connect with Mivo")
    }

    private func studyMode(computer: Bool, icon: String, title: String, detail: String) -> some View {
        let selected = onComputer == computer
        return Button {
            taskFocused = false
            onComputer = computer
            HapticsService.selection()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: icon).font(.system(size: 17, weight: .regular))
                Text(title).font(.subheadline.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.85)
            }
            .foregroundColor(selected ? MivoColors.background : MivoColors.ink)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(selected ? MivoColors.ink : MivoColors.surfaceRaised, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(selected ? .clear : MivoColors.hairlineSoft))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(detail)")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .disabled(setupLocked)
    }

    /// Full instructions until the first session; after that, one reminder line.
    private var setupGuide: some View {
        VStack(alignment: .leading, spacing: 14) {
            if onComputer {
                setupLine("laptopcomputer", "Open Mivo on your Mac, signed in to the same account. It joins on its own, or press Connect there.")
                if study.log.entries.isEmpty {
                    setupLine("checkmark.shield", "Focused activity counts. Distractions, away time and uncertain activity don't earn credit.")
                    setupLine("lock", "Close the phone app once connected. Window titles and websites stay on your Mac.")
                }
            } else if study.log.entries.isEmpty {
                setupLine("powerplug", "Plug in and prop your phone up across the room.")
                setupLine("camera", "Frame your hands and desk. Your face is optional.")
                setupLine("lock", "Keep Mivo open. Video stays on this phone.")
            } else {
                setupLine("camera", "Prop your phone up, plugged in, facing your desk. Keep Mivo open.")
            }
            if earnsScroll {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "hourglass")
                    Text("3 \(onComputer ? "focused" : "recorded") minutes = 1 minute of scroll. Up to \(ReelBalance.dailyEarnCapSeconds / 60) minutes a day.")
                }
                .font(.caption.weight(.medium))
                .foregroundColor(MivoColors.keptInk)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)
            }
        }
        .padding(.horizontal, 4)
    }

    private var startBar: some View {
        let valid = !task.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let label = study.linkedBusy ? "Connecting…"
            : study.isStarting ? "Starting camera…"
            : onComputer ? "Connect my Mac"
            : "Start \(plan.minutes)-minute session"
        return VStack(alignment: .leading, spacing: 10) {
            if !hasPlus { Text(trialLine).font(.caption).foregroundColor(MivoColors.inkBody).fixedSize(horizontal: false, vertical: true) }
            if let message = study.startMessage ?? study.linkedMessage { Text(message).font(.footnote).foregroundColor(MivoColors.secondary) }
            MivoPrimaryButton(label: label, disabled: setupLocked || !valid) { begin(task: task) }
            if study.trialPhase == .ended && !hasPlus {
                Button("Get Mivo Plus to earn scroll time") { paywallFeature = .studyScroll }
                    .font(.footnote.weight(.medium)).foregroundColor(MivoColors.deep).frame(maxWidth: .infinity, minHeight: 44)
            }
        }
        .padding(.horizontal, 24).padding(.top, 14).padding(.bottom, 12)
        .background(MivoColors.background)
        .overlay(alignment: .top) { Rectangle().fill(MivoColors.hairline).frame(height: 1) }
    }

    private func begin(task: String) {
        taskFocused = false
        guard !setupLocked, !task.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        HapticsService.tap()
        let chosen = plan
        Task {
            if onComputer { await study.startLinked(task: task) }
            else { await study.start(task: task, plan: chosen) }
        }
    }

    /// Where the person stands in the free week. Plus never sees it.
    @ViewBuilder
    private var trialNotice: some View {
        if !hasPlus {
            VStack(alignment: .leading, spacing: 8) {
                Text(trialLine)
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundColor(MivoColors.inkBody)
                    .fixedSize(horizontal: false, vertical: true)
                if study.trialPhase == .ended {
                    MivoPrimaryButton(label: "Get Mivo Plus") { paywallFeature = .studyScroll }
                }
            }
        }
    }

    private var trialLine: String {
        switch study.trialPhase {
        case .notStarted:
            return "Your first \(StudyTrial.days) days earn scroll time free. After that, earning it needs Mivo Plus."
        case .running(let daysLeft):
            return "Free week: \(daysLeft == 1 ? "1 day" : "\(daysLeft) days") left to earn scroll time. After that it needs Mivo Plus."
        case .ended:
            return "Your free week is over. Sessions still count for your streak, but earning scroll time needs Mivo Plus."
        }
    }

    private func setupLine(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(MivoColors.accent)
                .frame(width: 20)
            Text(text)
                .font(.subheadline)
                .foregroundColor(MivoColors.inkBody)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var stats: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 10) { statTiles }
            } else {
                HStack(spacing: 10) { statTiles }
            }
        }
    }

    @ViewBuilder
    private var statTiles: some View {
        statTile("Today", StudyFormat.scrollTime(study.studiedTodaySeconds))
        statTile("Streak", study.streak > 0 ? StudyFormat.days(study.streak) : "None yet")
        statTile("Scroll earned", StudyFormat.scrollTime(study.earnedTodaySeconds))
    }

    private func statTile(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundColor(MivoColors.inkMuted)
            Text(value)
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(MivoColors.ink)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(MivoColors.surfaceV2))
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var recentSessions: some View {
        let entries = Array(study.log.entries.sorted { $0.startedAt > $1.startedAt }.prefix(5))
        if !entries.isEmpty {
            VStack(alignment: .leading, spacing: 16) {
                Text("Recent sessions")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(MivoColors.ink)
                ForEach(entries.indices, id: \.self) { index in
                    let entry = entries[index]
                    if index > 0 { Rectangle().fill(MivoColors.hairlineSoft).frame(height: 1) }
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: entry.origin == .desktop ? "laptopcomputer" : "book.closed")
                            .font(.system(size: 16))
                            .foregroundColor(MivoColors.inkBody)
                            .frame(width: 36, height: 36)
                            .background(MivoColors.surfaceV2, in: RoundedRectangle(cornerRadius: 10))
                        VStack(alignment: .leading, spacing: 5) {
                            Text(entry.task)
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(MivoColors.ink)
                                .lineLimit(2)
                            Text("\(entry.startedAt.formatted(date: .abbreviated, time: .shortened)) · \(StudyFormat.minutes(entry.seconds))")
                                .font(.caption)
                                .foregroundColor(MivoColors.inkBody)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(18)
            .background(MivoColors.surfaceRaised, in: RoundedRectangle(cornerRadius: 20))
        }
    }

    // MARK: - Study room

    /// The room is one link. Open, friends who have it can see this person is studying and sit
    /// with them; they never see video. Hidden until the account service has rooms.
    @ViewBuilder
    private var roomCard: some View {
        if study.roomAvailable {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "person.2")
                        .font(.system(size: 20))
                        .foregroundColor(MivoColors.ink)
                        .frame(width: 44, height: 44)
                        .background(MivoColors.surfaceV2, in: RoundedRectangle(cornerRadius: 14))
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Study together")
                            .font(.system(.title3, design: .serif).weight(.semibold))
                            .foregroundColor(MivoColors.ink)
                        Text("A little company for your focus time.")
                            .font(.caption)
                            .foregroundColor(MivoColors.inkBody)
                    }
                    Spacer(minLength: 0)
                    if study.roomBusy {
                        ProgressView().tint(MivoColors.inkBody)
                            .accessibilityLabel("Updating study room")
                    } else if study.room?.hasRoom == true {
                        Menu {
                            Button("Make a new link", systemImage: "arrow.triangle.2.circlepath") { confirmingNewLink = true }
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(MivoColors.inkBody)
                                .frame(width: 44, height: 44)
                        }
                        .accessibilityLabel("Study room options")
                    }
                }

                Toggle(isOn: roomOpenBinding) {
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 7) {
                            Circle()
                                .fill(study.room?.isOpen == true ? MivoColors.kept : MivoColors.inkMuted)
                                .frame(width: 6, height: 6)
                            Text(roomStatus)
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(MivoColors.ink)
                        }
                        Text(roomSubtitle)
                            .font(.caption)
                            .foregroundColor(MivoColors.inkBody)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .tint(MivoColors.kept)
                .disabled(study.roomBusy)
                .accessibilityLabel("Open my study room")

                if let room = study.room, room.hasRoom, room.isOpen, let url = room.url {
                    Rectangle().fill(MivoColors.hairlineSoft).frame(height: 1)

                    VStack(alignment: .leading, spacing: 12) {
                        Text("YOUR INVITE LINK")
                            .font(.system(size: 10, weight: .bold))
                            .tracking(1.2)
                            .foregroundColor(MivoColors.inkBody)
                        HStack(spacing: 8) {
                            Text(url.absoluteString.replacingOccurrences(of: "https://", with: ""))
                                .font(.system(size: 12, weight: .medium, design: .monospaced))
                                .foregroundColor(MivoColors.ink)
                                .textSelection(.enabled)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Button {
                                UIPasteboard.general.string = url.absoluteString
                                copiedLink = true
                                HapticsService.selection()
                            } label: {
                                Image(systemName: copiedLink ? "checkmark" : "doc.on.doc")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(MivoColors.ink)
                                    .frame(width: 44, height: 44)
                            }
                            .accessibilityLabel(copiedLink ? "Link copied" : "Copy invite link")
                            .task(id: copiedLink) {
                                guard copiedLink else { return }
                                try? await Task.sleep(nanoseconds: 2_000_000_000)
                                guard !Task.isCancelled else { return }
                                copiedLink = false
                            }
                        }
                        .padding(.leading, 12)
                        .background(MivoColors.background, in: RoundedRectangle(cornerRadius: 12))
                        ShareLink(item: url, message: Text("\(room.displayName) is studying. Sit with them:")) {
                            Label("Invite a friend", systemImage: "square.and.arrow.up")
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(MivoColors.background)
                                .frame(maxWidth: .infinity, minHeight: 46)
                                .background(MivoColors.ink, in: RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                        Text("Friends join in a browser. No app needed.")
                            .font(.caption)
                            .foregroundColor(MivoColors.inkBody)
                    }

                    Toggle(isOn: roomShowsTaskBinding) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Share my task")
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(MivoColors.ink)
                            Text(room.showTask ? "Friends can see what you're working on." : "Only your study status and timer are visible.")
                                .font(.caption)
                                .foregroundColor(MivoColors.inkBody)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .tint(MivoColors.kept)
                    .disabled(study.roomBusy)

                    if !room.sitting.isEmpty {
                        Rectangle().fill(MivoColors.hairlineSoft).frame(height: 1)
                        VStack(alignment: .leading, spacing: 12) {
                            Text("SITTING WITH YOU · \(room.sitting.count)")
                                .font(.system(size: 10, weight: .bold))
                                .tracking(1)
                                .foregroundColor(MivoColors.inkBody)
                            ForEach(room.sitting) { visitor in
                                HStack(spacing: 10) {
                                    visitorAvatar(visitor.name)
                                    Text(visitor.name)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundColor(MivoColors.ink)
                                    Spacer()
                                    Menu {
                                        Button("Remove from room", systemImage: "person.crop.circle.badge.minus", role: .destructive) {
                                            Task { await study.removeVisitor(visitor.id) }
                                        }
                                    } label: {
                                        Image(systemName: "ellipsis")
                                            .foregroundColor(MivoColors.inkBody)
                                            .frame(width: 44, height: 44)
                                    }
                                    .accessibilityLabel("Options for \(visitor.name)")
                                    .disabled(study.roomBusy)
                                }
                            }
                        }
                    }
                }

                Label("Your camera is always private.", systemImage: "lock.shield")
                    .font(.caption)
                    .foregroundColor(MivoColors.inkBody)

                if let message = study.roomMessage {
                    Label(message, systemImage: "exclamationmark.circle")
                        .font(.footnote.weight(.medium))
                        .foregroundColor(MivoColors.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(MivoColors.surfaceRaised, in: RoundedRectangle(cornerRadius: 22))
            .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(MivoColors.hairlineSoft))
            .confirmationDialog(
                "Make a new link?",
                isPresented: $confirmingNewLink,
                titleVisibility: .visible
            ) {
                Button("Make a new link", role: .destructive) { Task { await study.rotateRoomLink() } }
                Button("Keep this link", role: .cancel) {}
            } message: {
                Text("The old link stops working and anyone sitting with you is sent away.")
            }
        }
    }

    private func visitorAvatar(_ name: String) -> some View {
        Text(String(name.prefix(1)).uppercased())
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundColor(MivoColors.ink)
            .frame(width: 34, height: 34)
            .background(MivoColors.surfaceV2, in: Circle())
            .accessibilityHidden(true)
    }

    private var roomStatus: String {
        guard let room = study.room, room.isOpen else { return "Open your room" }
        return room.studying ? "Room is live" : "Room is open"
    }

    private var roomSubtitle: String {
        guard let room = study.room, room.hasRoom, room.isOpen else {
            return "Let friends sit with you while you study."
        }
        return room.studying ? "Friends with your link can join you now." : "Your timer goes live when you start studying."
    }

    #if DEBUG
    fileprivate var roomPreview: some View { roomCard }
    #endif

    private var roomOpenBinding: Binding<Bool> {
        Binding(
            get: { study.room?.isOpen ?? false },
            set: { open in Task { await study.setRoomOpen(open) } }
        )
    }

    private var roomShowsTaskBinding: Binding<Bool> {
        Binding(
            get: { study.room?.showTask ?? true },
            set: { show in Task { await study.setRoomShowsTask(show) } }
        )
    }

    /// While a session runs: whether the room is live and who is sitting with the person.
    @ViewBuilder
    private var roomLiveLine: some View {
        if let room = study.room, room.hasRoom, room.isOpen, study.interruptedAt == nil {
            VStack(spacing: 10) {
                Label("STUDY ROOM IS LIVE", systemImage: "dot.radiowaves.left.and.right")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1)
                    .foregroundColor(MivoColors.keptInk)
                if room.sitting.isEmpty {
                    Text("A quiet space. Friends can join with your link.")
                        .font(.footnote)
                        .foregroundColor(MivoColors.inkBody)
                } else {
                    HStack(spacing: -6) {
                        ForEach(Array(room.sitting.prefix(4))) { visitor in
                            visitorAvatar(visitor.name)
                                .overlay(Circle().strokeBorder(MivoColors.background, lineWidth: 2))
                        }
                    }
                    Text("\(roomNames(room.sitting.map(\.name))) sitting with you.")
                        .font(.footnote.weight(.medium))
                        .foregroundColor(MivoColors.inkBody)
                }
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(18)
            .background(MivoColors.surfaceRaised, in: RoundedRectangle(cornerRadius: 20))
            .padding(.horizontal, 24)
            .padding(.top, 24)
        }
    }

    private func roomNames(_ names: [String]) -> String {
        switch names.count {
        case 1: return "\(names[0]) is"
        case 2: return "\(names[0]) and \(names[1]) are"
        default: return "\(names[0]), \(names[1]) and \(names.count - 2) more are"
        }
    }

    // MARK: - Computer session

    private func linkedSession(_ session: LinkedStudySession) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Label("Computer study", systemImage: "laptopcomputer")
                        .font(.system(size: 14, weight: .bold))
                    Spacer()
                    Button("Close") { dismiss() }
                }
                .foregroundColor(MivoColors.inkMuted)
                Text(session.task)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(MivoColors.ink)
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Label(study.linkedMessage == nil ? session.activityLabel(at: context.date) : "Sync unavailable · reconnect for live status",
                          systemImage: session.isConnected(at: context.date) ? "checkmark.circle" : "wifi.slash")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(MivoColors.deep)
                }
                if session.status == "waiting" {
                    Text("Open Mivo on your Mac, sign in to the same account, then choose Connect in the Computer study card on Today or Focus. Your timer starts when the Mac connects.")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(MivoColors.inkBody)
                } else {
                    Text(StudyFormat.minutes(session.focusedSeconds))
                        .font(.system(size: 42, weight: .heavy))
                        .foregroundColor(MivoColors.ink)
                    Text("Focused study activity")
                        .font(.subheadline)
                        .foregroundColor(MivoColors.inkMuted)
                    HStack(spacing: 10) {
                        statTile("Distracted", StudyFormat.minutes(session.distractedSeconds))
                        statTile("Away", StudyFormat.minutes(session.awaySeconds))
                        statTile("Uncertain", StudyFormat.minutes(session.uncertainSeconds))
                    }
                }
                if let message = study.linkedMessage {
                    Text(message).foregroundColor(MivoColors.secondary)
                    Button("Retry sync") { Task { await study.refreshLinked(hasPlus: hasPlus) } }
                }
                if session.isFinished {
                    Text(session.status == "cancelled" ? "No study time was counted." : "Saved to your account. Focused time counts toward your study streak.")
                        .foregroundColor(MivoColors.inkBody)
                    if session.status == "finished" {
                        statTile("Scroll earned on this phone", StudyFormat.scrollTime(study.linkedEarnedSeconds))
                        if !earnsScroll { trialNotice }
                    }
                    MivoPrimaryButton(label: "Done") {
                        study.dismissLinkedReceipt()
                        task = ""
                    }
                } else {
                    Text("Activity is an estimate of focus. Use the Mac card to correct an app or website that belongs to your task.")
                        .font(.footnote.weight(.medium))
                        .foregroundColor(MivoColors.inkMuted)
                    MivoPrimaryButton(label: study.linkedBusy ? "Saving…" : (session.status == "waiting" ? "Cancel connection" : "Finish study session"), disabled: study.linkedBusy) {
                        Task { await study.finishLinked(hasPlus: hasPlus) }
                    }
                    Text("Once connected, your Mac keeps monitoring when you close this screen.")
                        .font(.footnote.weight(.medium))
                        .foregroundColor(MivoColors.inkMuted)
                }
            }
            .padding(24)
        }
    }

    // MARK: - During

    private func running(_ active: StudyService.Active) -> some View {
        ScrollView {
            VStack(spacing: 0) {
                Label(study.interruptedAt == nil ? "IN YOUR FOCUS SPACE" : "SESSION PAUSED", systemImage: study.interruptedAt == nil ? "sparkle" : "pause.circle")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1.5)
                    .foregroundColor(MivoColors.inkBody)

                Text(active.task)
                    .font(.system(size: 30, weight: .regular, design: .serif))
                    .foregroundColor(MivoColors.ink)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 24)
                    .padding(.top, 16)

                VStack(spacing: 12) {
                    StudyClock(startedAt: active.startedAt, stoppedAt: study.interruptedAt)
                    Text(study.interruptedAt == nil ? "One thing at a time. You're doing it." : "Your time so far is safe to save.")
                        .font(.footnote)
                        .foregroundColor(MivoColors.inkBody)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
                .padding(.horizontal, 12)
                .background(MivoColors.surfaceV2, in: RoundedRectangle(cornerRadius: 26))
                .padding(.horizontal, 24)
                .padding(.top, 28)

                if let plan = active.plan {
                    phonePlanSummary(plan, active: active).padding(.horizontal, 24).padding(.top, 20)
                }

                StudyCaptureStatus(
                    recorder: study.recorder,
                    cameraUnavailable: study.cameraUnavailable,
                    interrupted: study.interruptedAt != nil
                )
                .padding(.top, 24)

                if study.interruptedAt != nil {
                    Text("Mivo or the camera was interrupted. Finish to save the time you studied, then start a new session.")
                        .font(.footnote.weight(.medium))
                        .foregroundColor(MivoColors.inkBody)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                        .padding(.top, 12)
                }

                roomLiveLine

                if !isCharging {
                    Label("Plug in to keep your focus going.", systemImage: "powerplug")
                        .font(.caption)
                        .foregroundColor(MivoColors.inkBody)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                        .padding(.top, 24)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 32)
        }
        .safeAreaInset(edge: .bottom) {
            MivoInkButton(label: study.isFinishing ? "Saving session…" : "Finish session", disabled: study.isFinishing) {
                Task { await study.finish(hasPlus: hasPlus) }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .background(MivoColors.background)
            .overlay(alignment: .top) { Rectangle().fill(MivoColors.hairline).frame(height: 1) }
        }
        .task(id: active.startedAt) { await chimeAtGoal(active) }
    }

    /// The phone is across the room, so reaching the goal is heard, not just shown.
    /// Only fires live: reopening a session that already passed its goal stays quiet.
    private func chimeAtGoal(_ active: StudyService.Active) async {
        let goal = Double(active.plan?.goalSeconds ?? 0)
        let remaining = goal - Date().timeIntervalSince(active.startedAt)
        guard goal > 0, remaining > 0 else { return }
        try? await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
        guard !Task.isCancelled, study.interruptedAt == nil,
              case .running(let current) = study.phase, current.startedAt == active.startedAt else { return }
        AudioServicesPlaySystemSound(1021)
        HapticsService.success()
    }

    private func phonePlanSummary(_ plan: PhoneStudyPlan, active: StudyService.Active) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let elapsed = max(0, (study.interruptedAt ?? context.date).timeIntervalSince(active.startedAt))
            VStack(alignment: .leading, spacing: 10) {
                Text("YOUR FOCUS PLAN").font(.system(size: 10, weight: .bold)).tracking(1).foregroundColor(MivoColors.inkBody)
                if !plan.outcome.isEmpty { Text(plan.outcome).font(.subheadline.weight(.medium)).foregroundColor(MivoColors.ink) }
                ProgressView(value: min(elapsed, Double(plan.goalSeconds)), total: Double(plan.goalSeconds)).tint(MivoColors.kept)
                Text(elapsed >= Double(plan.goalSeconds) ? "Focus goal reached. Finish when you're ready." : "\(Int(elapsed / 60)) of your \(plan.minutes)-minute focus goal")
                    .font(.footnote).foregroundColor(MivoColors.inkBody)
                if !plan.websites.isEmpty { Text("Materials: \(plan.websites.joined(separator: " · "))").font(.caption).foregroundColor(MivoColors.inkBody) }
                if plan.hasDistractions {
                    Text(study.interruptedAt != nil || elapsed >= Double(plan.goalSeconds) ? "Distraction pause complete." : "Selected distractions paused for this focus period.")
                        .font(.caption).foregroundColor(MivoColors.keptInk)
                }
            }
            .padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .background(MivoColors.surfaceRaised, in: RoundedRectangle(cornerRadius: 20))
        }
    }

    // MARK: - After

    private func finished(_ receipt: StudyService.Receipt) -> some View {
        let entry = receipt.entry
        let earnedMinutes = entry.scrollSecondsEarned / 60
        let lockedMinutes = receipt.lockedScrollSeconds / 60
        return ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Image(systemName: "checkmark")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundColor(MivoColors.keptInk)
                    .frame(width: 56, height: 56)
                    .background(MivoColors.kept.opacity(0.12), in: Circle())
                    .accessibilityHidden(true)
                Text("Session complete.")
                    .font(.system(size: 34, weight: .regular, design: .serif))
                    .foregroundColor(MivoColors.ink)

                VStack(alignment: .leading, spacing: 6) {
                    Text("You worked on")
                        .font(.footnote.weight(.medium))
                        .foregroundColor(MivoColors.inkMuted)
                    Text(entry.task)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(MivoColors.ink)
                    Text(StudyFormat.minutes(entry.seconds))
                        .font(.system(size: 38, weight: .medium, design: .rounded))
                        .foregroundColor(MivoColors.ink)
                        .padding(.top, 8)
                    Text(entry.startedAt.formatted(date: .complete, time: .omitted))
                        .font(.subheadline)
                        .foregroundColor(MivoColors.inkBody)
                    Text(entry.wasRecorded ? "Verified on video: \(StudyFormat.minutes(entry.recordedSeconds))" : "Not recorded, so not verified")
                        .font(.footnote.weight(.medium))
                        .foregroundColor(MivoColors.inkMuted)
                        .padding(.top, 8)
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(MivoColors.surfaceRaised))

                HStack(spacing: 12) {
                    statTile("Streak", StudyFormat.days(receipt.streak))
                    statTile("Scroll earned", entry.scrollSecondsEarned > 0 ? "+\(StudyFormat.scrollTime(entry.scrollSecondsEarned))" : (receipt.lockedScrollSeconds > 0 ? "Needs Plus" : "None"))
                }

                Text("\(companion.miloName): \(MiloStudyVoice.receipt(earnedScrollMinutes: earnedMinutes, recorded: entry.wasRecorded, capReached: receipt.capReached, streak: receipt.streak, lockedScrollMinutes: lockedMinutes))")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(MivoColors.inkBody)
                    .lineSpacing(4)

                if receipt.lockedScrollSeconds > 0 {
                    MivoPrimaryButton(label: "Unlock \(StudyFormat.scrollTime(receipt.lockedScrollSeconds)) with Mivo Plus") {
                        paywallFeature = .studyScroll
                    }
                }

                Text("A day counts once you study a total of \(StudyLog.dayThresholdSeconds / 60) minutes.")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundColor(MivoColors.inkMuted)

                if receipt.lockedScrollSeconds > 0 {
                    MivoInkButton(label: "Done") {
                        study.reset()
                        task = ""
                        dismiss()
                    }
                } else {
                    MivoPrimaryButton(label: "Done") {
                        study.reset()
                        task = ""
                        dismiss()
                    }
                }
                MivoTertiaryButton(label: "Another round on this") {
                    // Same task, same setup, straight back to the camera: no setup screen in between.
                    let again = entry.plan ?? plan
                    study.reset()
                    task = entry.task
                    plan = again
                    HapticsService.tap()
                    Task { await study.start(task: entry.task, plan: again) }
                }
                MivoTertiaryButton(label: "Start something new") {
                    study.reset()
                    task = ""
                    plan.outcome = ""
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
        }
        .task {
            // Earning scroll time is the happiest moment in the loop, so it asks
            // for a review there. iOS decides whether the system prompt shows.
            guard entry.scrollSecondsEarned > 0 else { return }
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            MivoRatingPromptAction.requestReview()
        }
    }
}

enum StudyFormat {
    /// "Under a minute", "1 minute", "25 minutes".
    static func minutes(_ seconds: Int) -> String {
        let m = max(0, seconds) / 60
        if m < 1 { return "Under a minute" }
        return m == 1 ? "1 minute" : "\(m) minutes"
    }

    static func scrollTime(_ seconds: Int) -> String {
        let seconds = max(0, seconds)
        return seconds > 0 && seconds < 60 ? "\(seconds) sec" : "\(seconds / 60) min"
    }

    static func days(_ count: Int) -> String { count == 1 ? "1 day" : "\(count) days" }

    /// "04:07" or "1:02:09".
    static func clock(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s)
    }
}

/// Only the clock invalidates every second. Setup, room controls and the camera stay stable.
private struct StudyClock: View {
    let startedAt: Date
    let stoppedAt: Date?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            Text(StudyFormat.clock((stoppedAt ?? context.date).timeIntervalSince(startedAt)))
                .font(.system(size: 64, weight: .medium, design: .rounded).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.55)
                .foregroundColor(MivoColors.ink)
                .contentTransition(.identity)
                .accessibilityLabel("Study time")
                .accessibilityValue(StudyFormat.clock((stoppedAt ?? context.date).timeIntervalSince(startedAt)))
        }
    }
}

/// Observe the recorder itself so preview/status changes do not depend on timer redraws.
private struct StudyCaptureStatus: View {
    @ObservedObject var recorder: StudyRecorder
    let cameraUnavailable: Bool
    let interrupted: Bool

    var body: some View {
        VStack(spacing: 16) {
            if cameraUnavailable {
                Text("Camera unavailable. Study time counts toward your streak, but this session won't earn scroll time.")
                    .foregroundColor(MivoColors.secondary)
                if AVCaptureDevice.authorizationStatus(for: .video) == .denied {
                    Button("Open camera settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    }
                    .foregroundColor(MivoColors.deep)
                }
            } else if interrupted || recorder.wasCutShort {
                Label("Recording stopped", systemImage: "pause.circle")
                    .foregroundColor(MivoColors.secondary)
            } else if recorder.isRecording {
                Label("Recording · saved on this phone", systemImage: "record.circle")
                    .foregroundColor(MivoColors.deep)
                CameraPreview(session: recorder.session)
                    .frame(maxWidth: .infinity)
                    .frame(height: 190)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .accessibilityLabel("Private preview of your desk camera")
            }
        }
        .font(.subheadline.weight(.semibold))
        .multilineTextAlignment(.center)
        .padding(.horizontal, 20)
    }
}

private struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}
}

// MARK: - Presentation and Home tile

struct StudyPresenter: ViewModifier {
    @EnvironmentObject private var appVM: AppViewModel
    @ObservedObject private var study = StudyService.shared
    @ObservedObject private var plus = MivoPlusStore.shared
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content
            .fullScreenCover(isPresented: $study.showRequested) {
                StudySessionView()
                    .environmentObject(appVM)
            }
            .onAppear {
                study.bind()
                study.refreshSession = { [appVM] in try await appVM.prepareAuthenticatedSession() }
            }
            .onChange(of: appVM.user?.email) { _, _ in study.bind() }
            // Saves finished sessions to the account and reads the website's in, when the app opens,
            // comes back to the front, or the account changes.
            .task(id: appVM.user?.email) { await study.syncNow() }
            .task(id: "\(appVM.user?.email ?? "")-\(scenePhase)") {
                guard scenePhase == .active, appVM.user != nil else { return }
                while !Task.isCancelled {
                    let hasPlus = MivoPlusAccess.allows(isPlus: plus.isPlus, isAdmin: appVM.isAdminUser)
                    await study.refreshLinked(hasPlus: hasPlus)
                    try? await Task.sleep(nanoseconds: 5_000_000_000)
                }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .background { study.interrupt() }
                if phase == .active { Task { await study.syncNow() } }
            }
    }
}

extension View {
    /// The study flow's presentation layer. Apply once, at the root of the signed-in UI.
    func studyPresentation() -> some View {
        modifier(StudyPresenter())
    }
}

struct StudyHomeRow: View {
    @ObservedObject private var study = StudyService.shared
    @ObservedObject private var plus = MivoPlusStore.shared
    @EnvironmentObject private var appVM: AppViewModel

    private var subtitle: String {
        if let linked = study.linkedSession { return "\(linked.task) · \(linked.activityLabel())" }
        if case .running(let active) = study.phase {
            return study.interruptedAt != nil ? "Save your interrupted session: \(active.task)" : "Studying \(active.task). Tap to return."
        }
        let earns = StudyTrial.earnsScroll(study.trialPhase, hasPlus: MivoPlusAccess.allows(isPlus: plus.isPlus, isAdmin: appVM.isAdminUser))
        if !earns {
            return study.streak > 0 ? "\(StudyFormat.days(study.streak)) streak. Earning scroll time needs Plus." : "Film it. Keep your streak. Scroll time needs Plus."
        }
        return study.streak > 0 ? "\(StudyFormat.days(study.streak)) streak. Film it, earn scroll time." : "Name one thing. Film it. Earn scroll time."
    }

    var body: some View {
        MivoToolTile(
            icon: "books.vertical",
            title: "Study",
            subtitle: subtitle
        ) {
            study.showRequested = true
        }
    }
}

#if DEBUG
/// Local-only room controls for simulator review; never touches a signed-in account.
private final class StudyRoomPreviewBackend: StudyBackend {
    private var state = StudyRoomState(
        hasRoom: true, code: "K7M2QX4RTB", displayName: "Alex", isOpen: true,
        showTask: true, studying: false,
        sitting: [.init(id: UUID(), name: "Ava"), .init(id: UUID(), name: "Leo")]
    )

    func push(_ entries: [StudyEntry]) async throws {}
    func pull(since: Date) async throws -> [RemoteStudySession] { [] }
    func room() async throws -> StudyRoomState { state }
    func ensureRoom() async throws -> StudyRoomState { state }
    func updateRoom(displayName: String?, isOpen: Bool?, showTask: Bool?) async throws -> StudyRoomState {
        if let isOpen { state.isOpen = isOpen }
        if let showTask { state.showTask = showTask }
        return state
    }
    func rotateRoomLink() async throws -> StudyRoomState {
        state.code = "PREVIEWNEW"
        state.sitting = []
        return state
    }
    func removeVisitor(_ id: UUID) async throws -> StudyRoomState {
        state.sitting.removeAll { $0.id == id }
        return state
    }
    func ping(task: String, startedAt: Date) async throws -> StudyRoomState {
        state.studying = true
        return state
    }
    func endLive() async throws -> StudyRoomState {
        state.studying = false
        return state
    }
}

struct StudyRoomPreviewHost: View {
    @StateObject private var study: StudyService

    init() {
        let defaults = UserDefaults(suiteName: "mivo.study.ui-preview")!
        defaults.removePersistentDomain(forName: "mivo.study.ui-preview")
        let account = "study-ui-preview"
        let plan = PhoneStudyPlan(outcome: "Summarize the key ideas", websites: ["docs.google.com"])
        defaults.set(try? JSONEncoder().encode(plan), forKey: AccountScopedKey.make("mivo.study.setup", account: account))
        if ProcessInfo.processInfo.arguments.contains("-MivoPreviewStudyReturning") {
            let now = Date()
            let past = [("Finish Chapter 4 notes", 1), ("Calc problem set 6", 26), ("Read Macbeth Act 2", 50)].map { task, hoursAgo in
                StudyEntry(task: task, startedAt: now.addingTimeInterval(-Double(hoursAgo) * 3600),
                           endedAt: now.addingTimeInterval(-Double(hoursAgo) * 3600 + 1500),
                           recordedSeconds: 1500, scrollSecondsEarned: 500)
            }
            defaults.set(try? JSONEncoder().encode(StudyLog(entries: past)), forKey: AccountScopedKey.make("mivo.study.log", account: account))
        }
        let balance = ReelBalanceStore(defaults: defaults, account: { account })
        let study = StudyService(defaults: defaults, balanceStore: balance, backend: StudyRoomPreviewBackend(), account: { account })
        if !ProcessInfo.processInfo.arguments.contains("-MivoPreviewStudyReturning") { study.suggestedTask = "Finish Chapter 4 notes" }
        _study = StateObject(wrappedValue: study)
    }

    var body: some View {
        Group {
            if ProcessInfo.processInfo.arguments.contains("-MivoPreviewStudyRoomCard") {
                ScrollView {
                    StudySessionView(study: study).roomPreview.padding(24)
                }
                .background(MivoColors.background.ignoresSafeArea())
                .task { await study.refreshRoom() }
            } else {
                StudySessionView(study: study)
            }
        }
        .environment(\.colorScheme, ProcessInfo.processInfo.arguments.contains("-MivoPreviewStudyDark") ? .dark : .light)
        .dynamicTypeSize(ProcessInfo.processInfo.arguments.contains("-MivoPreviewStudyLargeText") ? .accessibility2 : .large)
    }
}
#endif
