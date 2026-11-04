import SwiftUI

private enum AttentionDestination: String, Identifiable {
    case plan, commitment, wins, recovery, messages, still, lock
    var id: String { rawValue }
}

/// One suggested action, with deeper tools available when they're useful.
struct AttentionHomeSection: View {
    @EnvironmentObject private var appVM: AppViewModel
    @ObservedObject private var plus = MivoPlusStore.shared
    @ObservedObject private var companion = CompanionStateManager.shared
    @State private var destination: AttentionDestination?
    @State private var paywall: PlusFeature?

    private var problem: AttentionProblem? { appVM.attentionJourney.problem }
    private var commitment: AttentionCommitment? { appVM.attentionJourney.currentCommitment }

    var body: some View {
        MivoCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    MivoEyebrow(text: "YOUR NEXT STEP")
                    Spacer()
                    Button(problem == nil ? "Choose a starting point" : "Change focus") { destination = .plan }
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(MivoColors.deep)
                }
                Text(commitment?.title ?? problem?.actionTitle ?? "What would you like your time back for?")
                    .font(.system(size: 23, weight: .bold))
                    .foregroundColor(MivoColors.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(commitment == nil
                     ? (problem?.startingPoint ?? "Choose what keeps getting in the way. Start with one useful change.")
                     : (commitment?.status == .locked ? "Your task is protected by Lock-in. Show your progress there." : "One concrete thing to do with your attention. Mark it done when you've actually finished."))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(MivoColors.inkBody)
                    .fixedSize(horizontal: false, vertical: true)
                MivoPrimaryButton(label: primaryTitle) { openRecommended() }
                if companion.isActive {
                    Text("\(companion.miloName): \(supportLine)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(MivoColors.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 20) {
                    Button("What I got done") { destination = .wins }
                    Spacer(minLength: 0)
                    Button("Make today easier") { destination = .recovery }
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(MivoColors.deep)
            }
        }
        .sheet(item: $destination) { target in
            switch target {
            case .plan: AttentionPlanView()
            case .commitment: AttentionCommitmentView()
            case .wins: AttentionWinsView()
            case .recovery: AttentionRecoveryView()
            case .messages: InterventionFlowView {}
            case .still: MivoStillFlowView(initialMinutes: 15)
            case .lock:
                NavigationStack {
                    LockInEntryView()
                        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { destination = nil } } }
                }
            }
        }
        .sheet(item: $paywall) { MivoPlusPaywallView(feature: $0) }
    }

    private var primaryTitle: String {
        if let commitment { return commitment.status == .locked ? "Open my protected task" : "Continue my commitment" }
        return problem?.actionTitle ?? "Find my starting point"
    }

    private var supportLine: String {
        if let recovery = appVM.attentionJourney.recoveries.first,
           Calendar.current.isDateInToday(recovery.chosenAt) {
            return "You chose an easier next step today. There's no catching up to do."
        }
        if let commitment {
            return commitment.status == .locked
                ? "Your task is protected. Show your progress when you're ready."
                : "You chose this task. A small start is enough."
        }
        return "What would you like to make room for today?"
    }

    private func openRecommended() {
        if let commitment {
            destination = commitment.status == .locked ? .lock : .commitment
            return
        }
        switch problem {
        case .none: destination = .plan
        case .study, .automaticScrolling: destination = .commitment
        case .bedtime: openPaid(.still, feature: .mivoStill)
        case .usefulSocial: destination = .messages
        }
    }

    private func openPaid(_ target: AttentionDestination, feature: PlusFeature) {
        if MivoPlusAccess.allows(isPlus: plus.isPlus, isAdmin: appVM.isAdminUser) {
            destination = target
        } else { paywall = feature }
    }
}

struct AttentionPlanView: View {
    @EnvironmentObject private var appVM: AppViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var selected: AttentionProblem?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("What keeps happening that you want to change?")
                        .font(.system(size: 27, weight: .bold))
                    Text("Choose one to start. You can change your focus any time.")
                        .foregroundColor(MivoColors.inkBody)
                    ForEach(AttentionProblem.allCases) { problem in
                        Button { selected = problem } label: {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: problem.icon).frame(width: 24)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(problem.title).font(.system(size: 16, weight: .semibold))
                                    if selected == problem {
                                        Text(problem.startingPoint).font(.system(size: 13))
                                    }
                                }
                                Spacer(minLength: 0)
                                Image(systemName: selected == problem ? "checkmark.circle.fill" : "circle")
                            }
                            .padding(16)
                            .foregroundColor(MivoColors.ink)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(selected == problem ? MivoColors.surfaceV2 : MivoColors.surfaceRaised)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(selected == problem ? .isSelected : [])
                    }
                    MivoPrimaryButton(label: "Use this starting point", disabled: selected == nil) {
                        guard let selected else { return }
                        appVM.chooseAttentionProblem(selected)
                        HapticsService.success()
                        dismiss()
                    }
                    Text("Choosing a focus doesn't change your existing app protections. Your starting action is on Home.")
                        .font(.system(size: 12)).foregroundColor(MivoColors.inkMuted)
                }.padding(20)
            }
            .background(MivoColors.background)
            .navigationTitle("Your starting point")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        }
        .onAppear { selected = appVM.attentionJourney.problem }
    }
}

struct AttentionCommitmentView: View {
    @EnvironmentObject private var appVM: AppViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var error: String?
    @State private var showLock = false
    @State private var showSwap = false
    @State private var resize = false
    let makeSmaller: Bool

    init(makeSmaller: Bool = false) { self.makeSmaller = makeSmaller }
    private var current: AttentionCommitment? { appVM.attentionJourney.currentCommitment }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(makeSmaller ? "Just the next small step" : "One thing you want to get done")
                        .font(.system(size: 27, weight: .bold))
                    if let current, !resize {
                        MivoCard {
                            VStack(alignment: .leading, spacing: 12) {
                                Text(current.title).font(.system(size: 22, weight: .bold))
                                if current.status == .locked {
                                    Text("This task is protected. Review evidence or unlock requests in Lock-in.")
                                    Button("Open Lock-in") { showLock = true }
                                } else {
                                    MivoPrimaryButton(label: "I finished this") {
                                        appVM.completeAttentionCommitment(current.id)
                                        HapticsService.success()
                                        dismiss()
                                    }
                                    Text("Recorded as your own check-in. Mivo hasn't verified the activity.")
                                        .font(.system(size: 12)).foregroundColor(MivoColors.inkMuted)
                                    Button("Protect this task with Lock-in") { showLock = true }
                                    Button("Make this smaller") { title = current.title; resize = true }
                                    Button("Set this aside for now") {
                                        appVM.setAsideAttentionCommitment(current.id)
                                    }
                                }
                            }
                        }
                    } else {
                        Text("Choose something specific and small enough to start today. Rest, reading, and replying to someone count too.")
                            .foregroundColor(MivoColors.inkBody)
                        TextField("e.g. Write the first paragraph", text: $title, axis: .vertical)
                            .lineLimit(2...4)
                            .padding(16).background(MivoColors.surfaceRaised)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .onChange(of: title) { _, text in
                                if text.count > 80 { title = String(text.prefix(80)) }
                            }
                        if let error { Text(error).foregroundColor(MivoColors.timerRed) }
                        MivoPrimaryButton(label: resize ? "Save the smaller step" : "Choose this commitment",
                                          disabled: AttentionJourney.cleanTitle(title) == nil) {
                            if resize, let current {
                                guard appVM.resizeAttentionCommitment(current.id, title: title) else {
                                    error = "This task may now be protected. Open Lock-in to check it."
                                    return
                                }
                                resize = false
                            } else if !appVM.addAttentionCommitment(title) {
                                error = "Finish or set aside your current commitment first."
                            }
                        }
                        Button("Use my swap: \(appVM.userSwap?.title ?? "choose one")") {
                            if let swap = appVM.userSwap { title = swap.title } else { showSwap = true }
                        }
                    }
                    Text("Your commitments stay on this device and are included in your data export.")
                        .font(.system(size: 12)).foregroundColor(MivoColors.inkMuted)
                }.padding(20)
            }
            .background(MivoColors.background)
            .navigationTitle("My commitment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
            .sheet(isPresented: $showSwap, onDismiss: {
                if let swap = appVM.userSwap { title = swap.title }
            }) { NavigationStack { SwapSettingsView() } }
        }
        .fullScreenCover(isPresented: $showLock) {
            if LockInManager.shared.current != nil {
                NavigationStack {
                    LockInEntryView().toolbar {
                        ToolbarItem(placement: .topBarTrailing) { Button("Done") { showLock = false } }
                    }
                }
            } else {
                LockInSetupFlowView(initialTask: current?.title ?? title)
            }
        }
        .onAppear {
            title = appVM.userSwap?.title ?? appVM.attentionJourney.problem?.suggestedTask ?? ""
            resize = makeSmaller && current?.status == .planned
            if resize { title = current?.title ?? title }
        }
    }
}

struct AttentionRecoveryView: View {
    @EnvironmentObject private var appVM: AppViewModel
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var plus = MivoPlusStore.shared
    @State private var choice: AttentionRecovery.Choice?
    @State private var paywall: PlusFeature?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("A difficult day can have an easier next step.")
                        .font(.system(size: 28, weight: .bold))
                    Text("You don't have to catch up. Choose what would help right now.")
                        .foregroundColor(MivoColors.inkBody)
                    ForEach(AttentionRecovery.Choice.allCases) { option in
                        MivoPrimaryButton(label: option.title) {
                            let feature: PlusFeature? = option == .quietTime ? .mivoStill : nil
                            if let feature, !MivoPlusAccess.allows(isPlus: plus.isPlus, isAdmin: appVM.isAdminUser) {
                                paywall = feature
                                return
                            }
                            appVM.chooseAttentionRecovery(option)
                            choice = option
                        }
                    }
                    Text("Your history and existing protections stay in place. Choosing a next step isn't counted as a completed task.")
                        .font(.system(size: 12)).foregroundColor(MivoColors.inkMuted)
                }.padding(20)
            }
            .background(MivoColors.background)
            .navigationTitle("Make today easier")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        }
        .fullScreenCover(item: $choice) { target in
            switch target {
            case .smallerTask: AttentionCommitmentView(makeSmaller: true)
            case .messages: InterventionFlowView {}
            case .quietTime: MivoStillFlowView(initialMinutes: 15)
            }
        }
        .sheet(item: $paywall) { MivoPlusPaywallView(feature: $0) }
    }
}

struct AttentionWinsView: View {
    @EnvironmentObject private var appVM: AppViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var weekOffset = 0

    private var start: Date {
        let today = Calendar.current.startOfDay(for: Date())
        return Calendar.current.date(byAdding: .day, value: weekOffset * 7 - 6, to: today) ?? today
    }
    private var end: Date { Calendar.current.date(byAdding: .day, value: 7, to: start) ?? Date() }
    private var wins: [AttentionCommitment] { appVM.attentionJourney.completions(from: start, to: end) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        Button { weekOffset -= 1 } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }
                            .accessibilityLabel("Previous seven days")
                        Spacer()
                        Text(weekOffset == 0 ? "Last seven days" : "\(start.formatted(date: .abbreviated, time: .omitted)) – \(end.addingTimeInterval(-1).formatted(date: .abbreviated, time: .omitted))")
                            .font(.system(size: 13, weight: .semibold))
                        Spacer()
                        Button { weekOffset += 1 } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }
                            .disabled(weekOffset == 0).accessibilityLabel("Next seven days")
                    }
                    Text("\(wins.count) commitment\(wins.count == 1 ? "" : "s") completed")
                        .font(.system(size: 28, weight: .bold))
                    Text("What you chose to do with your attention matters alongside time on your phone.")
                        .foregroundColor(MivoColors.inkBody)
                    if wins.isEmpty {
                        MivoCard {
                            Text("No completed commitments in this period yet. Choose one small task on Home and check in when it's done.")
                        }
                    }
                    ForEach(wins) { win in
                        MivoCard {
                            VStack(alignment: .leading, spacing: 6) {
                                Label(win.title, systemImage: "checkmark.circle")
                                    .font(.system(size: 17, weight: .semibold))
                                Text(win.evidence?.label ?? "No evidence recorded")
                                    .font(.system(size: 12)).foregroundColor(MivoColors.inkMuted)
                                if let date = win.completedAt {
                                    Text(date.formatted(date: .abbreviated, time: .shortened))
                                        .font(.system(size: 12)).foregroundColor(MivoColors.inkMuted)
                                }
                            }
                        }
                    }
                    Text("A timer or a restart choice alone isn't proof of task completion. Self-reported wins and reviewed evidence are labeled separately.")
                        .font(.system(size: 12)).foregroundColor(MivoColors.inkMuted)
                }.padding(20)
            }
            .background(MivoColors.background)
            .navigationTitle("What I got done")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        }
    }
}

struct AttentionExperimentCard: View {
    @EnvironmentObject private var appVM: AppViewModel
    @ObservedObject private var plus = MivoPlusStore.shared
    @State private var selected: WeeklyExperiment?
    @State private var paywall: PlusFeature?
    @State private var error: String?
    @State private var showLibrary = false

    private var experiment: WeeklyExperiment? {
        appVM.completedWeeklyExperimentAwaitingDecision ?? appVM.activeWeeklyExperiment
            ?? appVM.enforcedWeeklyExperiment ?? appVM.proposedWeeklyExperiment
    }

    var body: some View {
        MivoCard {
            VStack(alignment: .leading, spacing: 12) {
                MivoEyebrow(text: "THIS WEEK'S ONE CHANGE")
                Text(experiment?.title ?? appVM.attentionExperimentSuggestion.title)
                    .font(.system(size: 20, weight: .bold)).foregroundColor(MivoColors.ink)
                Text(detail).font(.system(size: 13)).foregroundColor(MivoColors.inkBody)
                if let experiment, experiment.status == .active {
                    MivoSegmentBar(completed: experiment.dayNumber)
                }
                Button(actionTitle) {
                    if let experiment, experiment.status != .proposed {
                        selected = experiment
                        return
                    }
                    guard MivoPlusAccess.allows(isPlus: plus.isPlus, isAdmin: appVM.isAdminUser) else {
                        paywall = .experiments
                        return
                    }
                    if let experiment { selected = experiment }
                    else if let proposal = appVM.createWeeklyExperimentProposal(from: appVM.attentionExperimentSuggestion) {
                        selected = proposal
                    } else { error = "Open your current experiment before starting another." }
                }
                .font(.system(size: 14, weight: .semibold)).foregroundColor(MivoColors.deep)
                Button("Other experiments") {
                    if MivoPlusAccess.allows(isPlus: plus.isPlus, isAdmin: appVM.isAdminUser) { showLibrary = true }
                    else { paywall = .experiments }
                }
                .font(.system(size: 12, weight: .medium)).foregroundColor(MivoColors.inkMuted)
                if let error { Text(error).font(.system(size: 12)).foregroundColor(MivoColors.timerRed) }
            }
        }
        .sheet(item: $selected) { WeeklyExperimentSheet(experiment: $0) }
        .sheet(item: $paywall) { MivoPlusPaywallView(feature: $0) }
        .sheet(isPresented: $showLibrary) {
            NavigationStack {
                ExperimentHubView().toolbar {
                    ToolbarItem(placement: .topBarTrailing) { Button("Done") { showLibrary = false } }
                }
            }
        }
    }

    private var detail: String {
        guard let experiment else { return appVM.attentionExperimentSuggestion.detail }
        switch experiment.status {
        case .active: return "Day \(experiment.dayNumber) of 7. Try the one rule you chose, then decide whether to keep, adjust, or stop it."
        case .completed:
            return experiment.finalDecision == .keep
                ? "You kept this rule. Review it or stop using it whenever it stops helping."
                : "Your week is ready to review. Compare the observations and tell Mivo how it felt."
        default: return experiment.reason
        }
    }
    private var actionTitle: String {
        switch experiment?.status {
        case .active: return "See my current rule"
        case .completed: return experiment?.finalDecision == .keep ? "Manage the rule I kept" : "Review what worked"
        default: return "Review this experiment"
        }
    }
}

struct AttentionCompletionCard: View {
    @EnvironmentObject private var appVM: AppViewModel
    let start: Date
    let end: Date
    private var wins: [AttentionCommitment] { appVM.attentionJourney.completions(from: start, to: end) }

    var body: some View {
        MivoCard {
            VStack(alignment: .leading, spacing: 10) {
                Label("What you got done", systemImage: "checkmark.circle")
                    .font(.system(size: 16, weight: .bold))
                Text("\(wins.count) commitment\(wins.count == 1 ? "" : "s") completed")
                    .font(.system(size: 21, weight: .bold))
                if wins.isEmpty {
                    Text("Choose a small commitment on Home and check in when it's done.")
                        .font(.system(size: 12)).foregroundColor(MivoColors.inkMuted)
                } else {
                    ForEach(Array(wins.prefix(3))) { win in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(win.title).font(.system(size: 14, weight: .semibold))
                            Text(win.evidence?.label ?? "No evidence recorded")
                                .font(.system(size: 11)).foregroundColor(MivoColors.inkMuted)
                        }
                    }
                    Text("\(wins.filter { $0.evidence == .selfReported }.count) self-reported · \(wins.filter { $0.evidence == .miloReviewed || $0.evidence == .keyholderApproved }.count) reviewed")
                        .font(.system(size: 12)).foregroundColor(MivoColors.inkMuted)
                }
            }
            .foregroundColor(MivoColors.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

#if DEBUG
/// Isolated launch-argument fixtures for reviewing the real screens on a QA simulator.
struct AttentionJourneyPreviewHost: View {
    @EnvironmentObject private var appVM: AppViewModel
    let mode: String
    @State private var seeded = false

    var body: some View {
        Group {
            if !seeded { ProgressView() }
            else {
                switch mode {
                case "plan": AttentionPlanView()
                case "commitment": AttentionCommitmentView()
                case "wins": AttentionWinsView()
                case "recovery": AttentionRecoveryView()
                default: NavigationStack { HomeView() }
                }
            }
        }
        .task {
            guard !seeded else { return }
            appVM.user = UserProfile(email: "attention-preview@example.test", name: "Jordan", createdAt: ISO8601DateFormatter().string(from: Date()))
            var journey = AttentionJourney(problem: .study)
            let now = Date()
            journey.addCommitment("Read two pages before bed", now: now.addingTimeInterval(-7200))
            journey.complete(journey.currentCommitment!.id, now: now.addingTimeInterval(-3600))
            journey.resolveLock(id: "preview-reviewed", task: "Finish the essay outline",
                                startedAt: now.addingTimeInterval(-1800), endedAt: now.addingTimeInterval(-600), evidence: .miloReviewed)
            journey.addCommitment("Write the introduction to my essay", now: now)
            appVM.attentionJourney = journey
            seeded = true
        }
    }
}
#endif

