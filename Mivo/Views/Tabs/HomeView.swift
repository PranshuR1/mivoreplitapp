import SwiftUI

#if canImport(DeviceActivity)
import DeviceActivity
#endif

#if canImport(FamilyControls)
import FamilyControls
#endif

#if canImport(ManagedSettings)
import ManagedSettings
#endif

private enum HomePlanWindowState {
    case complete
    case next
    case later
}

struct HomeView: View {
    @EnvironmentObject var appVM: AppViewModel
    @State private var protectionEnabled = false
    @State private var adaptivePlan: ScreenTimeReductionPlan? = nil
    @State private var showMonthlyForecast = false
    @State private var showExperimentHub = false
    @State private var showMivoClear = false
    @State private var showMivoStill = false
    @State private var showAttentionReceipt = false
    @State private var showSchedule = false
    @State private var showSpots = false
    @State private var showActiveSpot = false
    @ObservedObject private var stillStore = MivoStillStore.shared
    @ObservedObject private var companion = CompanionStateManager.shared
    @ObservedObject private var expansion = ProductExpansionStore.shared
    @State private var showRecoveryMode = false
    @AppStorage(ReplayModeSetting.key) private var replayModeOn = true
    @ObservedObject private var plus = MivoPlusStore.shared
    @State private var paywallFeature: PlusFeature?
    @State private var isRequestingScreenTime = false
    private let screenTimePoller = Timer.publish(every: 5, on: .main, in: .common).autoconnect()
    #if canImport(FamilyControls)
    @State private var impulseSelection = FamilyActivitySelection()
    @State private var showImpulsePicker = false
    #endif

    var body: some View {
        ZStack {
            MivoColors.background.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                // One card per job, in the order a day goes: how much so far,
                // what is allowed, then everything optional. The optional
                // features are grouped by what they are for — Practice (the
                // experiment), Explore (modes and places) and Review (reports
                // and planning) — instead of one run of identical rows.
                VStack(alignment: .leading, spacing: MivoMetrics.cardSpacing) {
                    MivoGreetingBar(name: firstName)
                        .padding(.top, 6)

                    SpotActiveBanner { showActiveSpot = true }

                    screenTimeHero

                    ComebackHomeSection()

                    if hasScreenTimeAccess {
                        scrollingPlanSection
                    }

                    replayModeRow

                    practiceSection
                    exploreSection
                    reviewSection
                }
                .padding(.horizontal, MivoMetrics.tabPadding)
                .padding(.bottom, MivoMetrics.scrollBottomPadding)
            }
        }
        .navigationBarHidden(true)
        .sheet(item: $paywallFeature) { feature in
            MivoPlusPaywallView(feature: feature)
                .environmentObject(appVM)
        }
        .onAppear {
            MivoPlusStore.shared.start()
            protectionEnabled = FamilyControlsManager.shared.isImpulseProtectionEnabled()
            #if canImport(FamilyControls)
            if #available(iOS 16.0, *) {
                impulseSelection = FamilyControlsManager.shared.loadFamilyActivitySelection()
                FamilyControlsManager.shared.applyImpulseProtectionIfNeeded()
                Task { await CrossDeviceFocusService.shared.reconcile() }
            }
            #endif
            appVM.refreshScreenTimeData()
            // Local, synchronous, cheap — no reason to route these through
            // the Task below.
            IntentGameService.shared.prepare(for: appVM)
            TimeLoanService.shared.prepare(for: appVM)
            Task {
                // These six don't depend on each other's results (each
                // writes its own slice of state), so they run concurrently
                // instead of one after another. Sequential awaits here
                // used to mean Home's total load time was the *sum* of
                // every network call (feature flags, Mivo Clear, Mivo
                // Still, the AI-personalized plan, admin role, weekly
                // experiments) on every single appearance — including
                // every tab switch back to Home. Running them together
                // caps it at whichever one is slowest instead.
                async let expansionPrepare: Void = expansion.prepare(for: appVM)
                async let clearPrepare: Void = MivoClearStore.shared.prepare(for: appVM)
                async let stillPrepare: Void = MivoStillStore.shared.prepare(for: appVM)
                async let plan: Void = refreshAdaptivePlan()
                async let adminRole: Void = appVM.refreshServerAdminRole()
                async let weeklyExperiments: Void = appVM.refreshWeeklyExperiments()
                _ = await (expansionPrepare, clearPrepare, stillPrepare, plan, adminRole, weeklyExperiments)
            }
        }
        .onChange(of: appVM.sessions.count) { _, _ in
            Task { await refreshAdaptivePlan() }
        }
        // The plan is cached in `adaptivePlan`, so a fresh start has to push a
        // refresh or Home keeps showing the old target and windows.
        .onChange(of: appVM.comebackAnchor) { _, _ in
            Task { await refreshAdaptivePlan() }
        }
        .onChange(of: appVM.truthChecks.count) { _, _ in
            Task { await refreshAdaptivePlan() }
        }
        .onChange(of: appVM.deviceActivityMinutesToday) { _, _ in
            Task { await refreshAdaptivePlan() }
        }
        .onReceive(screenTimePoller) { _ in
            appVM.loadDeviceActivityReport()
        }
        .onReceive(NotificationCenter.default.publisher(for: .mivoDeviceActivityDidUpdate)) { _ in
            appVM.loadDeviceActivityReport()
        }
        #if canImport(FamilyControls)
        .familyActivityPicker(isPresented: $showImpulsePicker, selection: $impulseSelection)
        .onChange(of: impulseSelection) { _, newValue in
            if #available(iOS 16.0, *) {
                FamilyControlsManager.shared.saveFamilyActivitySelection(newValue)
                if FamilyControlsManager.shared.hasImpulseSelection() {
                    protectionEnabled = true
                    FamilyControlsManager.shared.setImpulseProtectionEnabled(true)
                }
            }
        }
        #endif
        .sheet(isPresented: $showExperimentHub) {
            NavigationStack {
                ExperimentHubView()
                    .environmentObject(appVM)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") { showExperimentHub = false }
                        }
                    }
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showRecoveryMode) {
            if let recovery = expansion.currentRecoveryPlan {
                RecoveryModeView(expansion: expansion, plan: recovery)
                    .presentationDetents([.large])
            }
        }
        .fullScreenCover(isPresented: $showMivoClear) {
            MivoClearHubView()
                .environmentObject(appVM)
        }
        .fullScreenCover(isPresented: $showMivoStill) {
            MivoStillFlowView()
                .environmentObject(appVM)
        }
        .fullScreenCover(isPresented: $showAttentionReceipt) {
            AttentionReceiptView()
                .environmentObject(appVM)
        }
        .sheet(isPresented: $showMonthlyForecast) {
            if let plan = displayedPlan {
                MonthlyPlanForecastView(plan: plan)
                    .environmentObject(appVM)
            }
        }
        .navigationDestination(isPresented: $showSchedule) {
            SettingsView(page: .schedule)
        }
        .navigationDestination(isPresented: $showSpots) {
            SpotsHomeView()
        }
        .sheet(isPresented: $showActiveSpot) {
            SpotActiveView()
        }
    }

    // MARK: - Screen Time hero
    //
    // The primary metric. The label is load-bearing: it has to say this is
    // total *device* Screen Time from Apple, not Mivo-tracked scrolling.

    private var screenTimeHero: some View {
        MivoCard(padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("Screen time today")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(MivoColors.inkBody)
                    Spacer(minLength: 8)
                    Text("via Apple Screen Time")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(MivoColors.inkBody)
                }
                .padding(.horizontal, MivoMetrics.cardPadding)
                .padding(.top, MivoMetrics.cardPadding)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Today's total device screen time, read from Apple Screen Time")

                if hasScreenTimeAccess {
                    // Direct and visible: a DeviceActivityReport is a UI
                    // extension that only gets real execution time while its
                    // host is genuinely on screen, so it is never hidden or
                    // faded out.
                    #if canImport(DeviceActivity) && canImport(FamilyControls) && canImport(ManagedSettings)
                    if #available(iOS 16.0, *) {
                        MivoScreenTimeUsageLiveReport()
                            .frame(height: 210)
                            .clipShape(RoundedRectangle(cornerRadius: MivoMetrics.tileRadius, style: .continuous))
                            .padding(.horizontal, 8)
                            .padding(.top, 6)
                    }
                    #endif

                    screenTimeFooter
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Not connected")
                            .font(.system(size: 27, weight: .bold))
                            .foregroundColor(MivoColors.inkBody)
                            .padding(.top, 12)

                        MivoPrimaryButton(
                            label: isRequestingScreenTime ? "Opening Screen Time…" : "Connect Apple Screen Time",
                            disabled: isRequestingScreenTime
                        ) {
                            requestScreenTimeAccess()
                        }
                        .padding(.top, 18)
                    }
                    .padding(.horizontal, MivoMetrics.cardPadding)
                    .padding(.bottom, MivoMetrics.cardPadding)
                }
            }
        }
    }

    /// Change against last week, the weekly average and the seven-day bars,
    /// each shown only when the history behind it exists.
    private var screenTimeFooter: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let comparison = screenTimeComparison {
                comparisonRow(comparison)
            }

            HStack(alignment: .center, spacing: 12) {
                if let average = weeklyAverageMinutes {
                    Text("Weekly average \(formatDuration(average))")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundColor(MivoColors.inkBody)
                }
                Spacer(minLength: 0)
                if let sparkline = screenTimeSparkline {
                    HomeSparkline(values: sparkline, height: 34)
                }
            }

            Text(screenTimeFreshnessText)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundColor(MivoColors.inkBody)
        }
        .padding(.horizontal, MivoMetrics.cardPadding)
        .padding(.top, 14)
        .padding(.bottom, MivoMetrics.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) {
            MivoHairline(soft: true)
                .padding(.horizontal, MivoMetrics.cardPadding)
                .padding(.top, 0)
        }
    }

    private func comparisonRow(_ comparison: HomeScreenTimeComparison) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: comparison.isDown ? "arrow.down" : "arrow.up")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(comparison.tint)
                .frame(width: 18, height: 18)
                .background(comparison.tint.opacity(0.16))
                .clipShape(Circle())

            (Text(comparison.magnitudeText)
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundColor(comparison.tint)
             + Text(" \(comparison.referenceText)")
                .font(.system(size: 13.5, weight: .medium))
                .foregroundColor(MivoColors.inkBody))

            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Today's scrolling plan

    @ViewBuilder
    private var scrollingPlanSection: some View {
        MivoCard {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("Today's scrolling plan")
                        .font(.system(size: 18, weight: .bold))
                        .tracking(Font.mivoTracking(-0.02, at: 18))
                        .foregroundColor(MivoColors.ink)

                    Spacer(minLength: 8)

                    if let usage = planUsageText {
                        Text(usage)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(MivoColors.deep)
                            .fixedSize()
                    }
                }

                if let plan = displayedPlan, plan.collecting {
                    observationLine(plan)
                } else if planWindows.isEmpty {
                    Text("Your plan appears once today's windows are chosen.")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(MivoColors.inkBody)
                        .padding(.top, 6)

                    MivoPrimaryButton(label: "Choose today's windows") {
                        appVM.evaluateDailyScrollSchedulePrompt()
                    }
                    .padding(.top, 20)
                } else {
                    Text(planSubline)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(MivoColors.inkBody)
                        .padding(.top, 4)

                    HomePlanTimeline(
                        windows: planWindows,
                        state: { planWindowState(at: $0, windows: planWindows) },
                        title: { $0.title.isEmpty ? windowPeriodLabel($0) : $0.title },
                        meta: { "\(fullWindowTimeText($0)) · \($0.minutes) min allowed" }
                    )
                    .padding(.top, 18)

                    // The one action on this screen. ("Open an app on purpose"
                    // used to repeat it as a second, text-only button.)
                    MivoPrimaryButton(label: primaryActionLabel) {
                        HapticsService.selection()
                        appVM.deepLinkInterventionRequested = true
                    }
                    .padding(.top, 22)
                }
            }
        }
    }

    // MARK: - Mivo Plus

    private var hasPlus: Bool {
        MivoPlusAccess.allows(isPlus: plus.isPlus, isAdmin: appVM.isAdminUser)
    }

    /// Runs `action` for Plus, otherwise opens the paywall for that feature.
    private func requirePlus(_ feature: PlusFeature, _ action: () -> Void) {
        if hasPlus {
            action()
        } else {
            HapticsService.selection()
            paywallFeature = feature
        }
    }

    // MARK: - Replay mode

    /// The on/off switch for replay mode in the Instagram view. On by default;
    /// held off during the 3-day observation so the baseline stays clean.
    private var replayModeRow: some View {
        MivoListGroup {
            HStack(spacing: 12) {
                MivoIconTile(systemName: "repeat")
                VStack(alignment: .leading, spacing: 2) {
                    Text("Replay mode")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(MivoColors.ink)
                    Text(replayModeSubtitle)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundColor(MivoColors.inkBody)
                        .multilineTextAlignment(.leading)
                        .lineLimit(3)
                }
                Spacer(minLength: 8)
                Toggle("Replay mode", isOn: Binding(
                    get: { replayModeOn && hasPlus },
                    set: { newValue in
                        if hasPlus { replayModeOn = newValue } else { requirePlus(.instagramInMivo) {} }
                    }
                ))
                    .labelsHidden()
                    .tint(MivoColors.accent)
                    .onChange(of: replayModeOn) { _, _ in HapticsService.selection() }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    private var replayModeSubtitle: String {
        guard hasPlus else { return "Part of Mivo Plus." }
        guard replayModeOn else { return "Off. Instagram's feed stays as it is." }
        if displayedPlan?.collecting == true {
            return "On. Starts after your 3 days of observing, so your baseline stays honest."
        }
        return "Once your reels or minutes are used, Instagram in Mivo only plays ones you've already watched."
    }

    /// Days 1–3 replace the timeline with a single line and a 3-segment bar
    /// rather than showing a cap that does not exist yet.
    private func observationLine(_ plan: ScreenTimeReductionPlan) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Day \(plan.daysCollected) of \(plan.daysNeeded) · observing, no cap yet")
                .font(.system(size: 13.5, weight: .medium))
                .foregroundColor(MivoColors.inkBody)

            MivoSegmentBar(
                completed: plan.daysCollected,
                total: max(1, plan.daysNeeded),
                height: 5,
                fill: MivoColors.info
            )

            Text("Your plan appears after \(plan.daysNeeded) days.")
                .font(.system(size: 13.5, weight: .medium))
                .foregroundColor(MivoColors.inkBody)
        }
        .padding(.top, 12)
    }

    // MARK: - Practice, Explore, Review

    private var practiceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            MivoSectionTitle(text: "Practice")

            Button {
                HapticsService.selection()
                requirePlus(.experiments) { showExperimentHub = true }
            } label: {
                HStack(spacing: 12) {
                    MivoIconTile(systemName: "flask")
                    VStack(alignment: .leading, spacing: 4) {
                        MivoEyebrow(text: experimentEyebrow, color: MivoColors.inkBody)
                        Text(appVM.currentWeeklyExperiment?.title ?? "Start a 7-day experiment")
                            .font(.system(size: 15.5, weight: .semibold))
                            .foregroundColor(MivoColors.ink)
                            .multilineTextAlignment(.leading)
                        if let experiment = appVM.currentWeeklyExperiment {
                            MivoSegmentBar(completed: experiment.dayNumber)
                                .frame(width: 7 * 22 + 6 * 5)
                                .padding(.top, 3)
                        }
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(MivoColors.inkMuted)
                        .accessibilityHidden(true)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .mivoCardBackground()
                .contentShape(Rectangle())
            }
            .buttonStyle(MivoPressStyle())
            .plusLockBadge(!hasPlus)
        }
    }

    /// Modes and places, two to a row. Focus Break (formerly Intent Games) is
    /// not here: it sits behind its own opt-in toggle on Protect, so it reads
    /// as an explicit trial someone chooses rather than something advertised
    /// beside Still and Clear.
    private var exploreSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            MivoSectionTitle(text: "Explore")

            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
                spacing: 10
            ) {
                if expansion.isEnabled(.mivoStill) {
                    MivoStillRow {
                        requirePlus(.mivoStill) { showMivoStill = true }
                    }
                    .plusLockBadge(!hasPlus)
                }

                if expansion.isEnabled(.mivoClear) {
                    MivoToolTile(icon: "sparkles", title: "Mivo Clear", subtitle: mivoClearMeta) {
                        requirePlus(.mivoClear) { showMivoClear = true }
                    }
                    .plusLockBadge(!hasPlus)
                }

                SpotsEntryRow {
                    showSpots = true
                }

                // Present while Companion is on; before onboarding it reads "Meet Milo".
                if companion.isActive || companion.preferences.isAwaitingIntroduction {
                    CompanionHomeRow()
                }

                LockInHomeRow()

                StudyHomeRow()
            }
        }
    }

    private var reviewSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            MivoSectionTitle(text: "Review")

            MivoListGroup {
                reviewRow(icon: "doc.text", title: "Receipt", subtitle: "What today actually cost you", locked: !hasPlus) {
                    requirePlus(.receipt) { showAttentionReceipt = true }
                }

                MivoListDivider()
                reviewRow(icon: "calendar", title: "Today's schedule", subtitle: appVM.todayScrollScheduleStatusText) {
                    showSchedule = true
                }

                if let plan = displayedPlan, !plan.collecting {
                    MivoListDivider()
                    reviewRow(icon: "chart.line.uptrend.xyaxis", title: "30-day forecast", subtitle: "Where your plan is headed, day by day", locked: !hasPlus) {
                        requirePlus(.forecast) { showMonthlyForecast = true }
                    }
                }
            }
        }
    }

    private func reviewRow(icon: String, title: String, subtitle: String, locked: Bool = false, action: @escaping () -> Void) -> some View {
        Button {
            HapticsService.selection()
            action()
        } label: {
            MivoListRow(icon: icon, title: title, subtitle: subtitle, value: locked ? "Plus" : nil)
        }
        .buttonStyle(MivoRowPressStyle())
    }

    // MARK: - Derived values

    private var displayedPlan: ScreenTimeReductionPlan? {
        adaptivePlan.map(displayPlan)
    }

    private var planWindows: [ScreenScrollWindow] {
        // After a fresh start the old plan is gone. The plan's own suggested
        // windows are not shown as if they were today's: the card waits for
        // windows the person has actually chosen.
        if appVM.isComebackCoolingDown, appVM.dailyScrollSchedule() == nil {
            return []
        }
        return (displayedPlan?.windows ?? []).sorted {
            if $0.startHour == $1.startHour { return $0.endHour < $1.endHour }
            return $0.startHour < $1.startHour
        }
    }

    private var planSubline: String {
        let count = planWindows.count
        guard count > 0 else { return "" }
        return "\(count) \(count == 1 ? "window" : "windows"), shaped around your calmest hours."
    }

    private var planUsageText: String? {
        guard !planWindows.isEmpty else { return nil }
        let allowed = planWindows.reduce(0) { $0 + $1.minutes }
        guard allowed > 0 else { return nil }
        return "\(minutesUsedTowardPlan) of \(allowed) min used"
    }

    /// Minutes already spent in today's windows. This is Mivo-tracked session
    /// time, not device Screen Time — the plan is about the windows themselves.
    private var minutesUsedTowardPlan: Int {
        appVM.todaysSessions.reduce(0) { $0 + $1.actualDuration }
    }

    private var primaryActionLabel: String {
        let index = planWindows.indices.first { planWindowState(at: $0, windows: planWindows) == .next }
        let name = index.map { planWindows[$0] }.map { $0.title.isEmpty ? windowPeriodLabel($0) : $0.title }
        let subject = (name ?? "window").lowercased()
        return appVM.pendingResumedActiveSession == nil ? "Start \(subject)" : "Resume \(subject)"
    }

    private var experimentEyebrow: String {
        guard let experiment = appVM.currentWeeklyExperiment else {
            return "7-day experiment · none running"
        }
        return "7-day experiment · day \(experiment.dayNumber) of 7"
    }

    private var mivoClearMeta: String {
        let minutes = MivoClearStore.shared.minutesToday
        return minutes > 0 ? "\(minutes)m today" : "Social without the feed"
    }

    // MARK: - Screen Time figures
    //
    // Every figure here comes from `dailyScreenTimeObservations`, which is the
    // only record of total device Screen Time per day. When there is not enough
    // history the sparkline, comparison and average are omitted rather than
    // estimated — a plausible-looking wrong total teaches the wrong thing.

    private var observationsByDay: [String: Int] {
        Dictionary(
            appVM.dailyScreenTimeObservations.map { ($0.date, $0.minutes) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    /// Today plus the six days before it, oldest first. Nil when any day in the
    /// window has no observation.
    private var screenTimeSparkline: [Int]? {
        let byDay = observationsByDay
        var values: [Int] = []
        for offset in stride(from: 6, through: 0, by: -1) {
            guard let day = MivoDay.calendar.date(byAdding: .day, value: -offset, to: Date()) else { return nil }
            let key = MivoDay.key(day)
            if offset == 0 {
                guard let today = appVM.deviceActivityMinutesToday ?? byDay[key] else { return nil }
                values.append(today)
            } else {
                guard let minutes = byDay[key] else { return nil }
                values.append(minutes)
            }
        }
        return values.contains(where: { $0 > 0 }) ? values : nil
    }

    private var weeklyAverageMinutes: Int? {
        guard let values = screenTimeSparkline, !values.isEmpty else { return nil }
        return values.reduce(0, +) / values.count
    }

    private var screenTimeComparison: HomeScreenTimeComparison? {
        guard let today = appVM.deviceActivityMinutesToday,
              let lastWeek = MivoDay.calendar.date(byAdding: .day, value: -7, to: Date()),
              let previous = observationsByDay[MivoDay.key(lastWeek)],
              previous > 0 else { return nil }
        let delta = previous - today
        guard abs(delta) >= 1 else { return nil }
        let weekday = DateFormatter()
        weekday.dateFormat = "EEEE"
        return HomeScreenTimeComparison(
            isDown: delta > 0,
            magnitudeText: "\(formatDuration(abs(delta))) \(delta > 0 ? "less" : "more")",
            referenceText: "than last \(weekday.string(from: lastWeek))"
        )
    }

    private var screenTimeFreshnessText: String {
        guard let generated = appVM.deviceActivityReportGeneratedAt else {
            return "Read live from Apple Screen Time"
        }
        let elapsed = Int(Date().timeIntervalSince(generated) / 60)
        if elapsed < 1 { return "Read live from Apple Screen Time · updated just now" }
        return "Read live from Apple Screen Time · updated \(elapsed) min ago"
    }

    private func requestScreenTimeAccess() {
        HapticsService.selection()
        #if canImport(FamilyControls)
        if #available(iOS 16.0, *) {
            // The button previously gave no feedback between the tap and
            // Apple's own system sheet appearing — with no OS-level latency
            // to compare it to, that gap read as the app itself hanging.
            // This can't make the system sheet appear faster, but it makes
            // the tap register immediately instead of feeling ignored.
            isRequestingScreenTime = true
            FamilyControlsManager.shared.requestAuthorization { _ in
                DispatchQueue.main.async {
                    isRequestingScreenTime = false
                }
            }
        }
        #endif
    }

    // MARK: - Retained helpers

    private var firstName: String {
        appVM.user?.name.split(separator: " ").first.map(String.init) ?? "there"
    }

    private var hasScreenTimeAccess: Bool {
        if #available(iOS 16.0, *) {
            return ScreenTimeDataCollector.shared.authorizationStatus == .authorized
        }
        return false
    }

    private func planWindowState(
        at index: Int,
        windows: [ScreenScrollWindow],
        now: Date = Date()
    ) -> HomePlanTimeline<ScreenScrollWindow>.WindowState {
        let calendar = Calendar.current
        let currentMinute = calendar.component(.hour, from: now) * 60 + calendar.component(.minute, from: now)
        let nextIndex = windows.firstIndex { currentMinute < normalizedEndMinute($0) }

        if currentMinute >= normalizedEndMinute(windows[index]) { return .done }
        if index == nextIndex { return .next }
        return .later
    }

    private func normalizedEndMinute(_ window: ScreenScrollWindow) -> Int {
        let start = max(0, window.startHour) * 60
        var end = max(0, window.endHour) * 60
        if end <= start { end += 24 * 60 }
        return end
    }

    private func windowPeriodLabel(_ window: ScreenScrollWindow) -> String {
        switch ((window.startHour % 24) + 24) % 24 {
        case 5..<12: return "Morning window"
        case 12..<17: return "Afternoon window"
        case 17..<22: return "Evening window"
        default: return "Late-night window"
        }
    }


    private func displayPlan(_ plan: ScreenTimeReductionPlan) -> ScreenTimeReductionPlan {
        guard let schedule = appVM.dailyScrollSchedule(), !schedule.windows.isEmpty else {
            return plan
        }

        return ScreenTimeReductionPlan(
            id: "\(plan.id)-locked-\(schedule.date)",
            collecting: plan.collecting,
            daysCollected: plan.daysCollected,
            daysNeeded: plan.daysNeeded,
            dayIndex: plan.dayIndex,
            baselineMinutes: plan.baselineMinutes,
            targetMinutes: plan.targetMinutes,
            strictnessPercent: plan.strictnessPercent,
            summary: plan.collecting
                ? "Today’s scroll windows are locked. Mivo is still observing without enforcing a cap."
                : (appVM.comebackAnchor != nil
                    ? plan.summary
                    : "Today’s scroll windows are locked from your daily check. Mivo trims your target from your blended baseline."),
            decisionReason: plan.collecting
                ? "These are the times you chose for today. Days 1-3 stay in observation mode."
                : "These windows are the schedule you locked for today. You can choose again tomorrow morning.",
            windows: schedule.windows
        )
    }

    private func refreshAdaptivePlan() async {
        let plan = await AIService.makeScreenTimeReductionPlanOnline(
            sessions: appVM.sessions,
            truthChecks: appVM.truthChecks,
            todayScreenTimeMinutes: appVM.deviceActivityMinutesToday,
            profile: appVM.onboardingProfile,
            dailyObservations: appVM.dailyScreenTimeObservations,
            comeback: appVM.comebackAnchor
        )
        await MainActor.run {
            adaptivePlan = plan
        }
    }

    private func fullWindowTimeText(_ window: ScreenScrollWindow) -> String {
        let calendar = Calendar.current
        let startHour = ((window.startHour % 24) + 24) % 24
        let endHour = ((window.endHour % 24) + 24) % 24
        let startDate = calendar.date(bySettingHour: startHour, minute: 0, second: 0, of: Date()) ?? Date()
        let endDate = calendar.date(bySettingHour: endHour, minute: 0, second: 0, of: Date()) ?? Date()
        let periodFormatter = DateFormatter()
        periodFormatter.dateFormat = "a"
        let samePeriod = periodFormatter.string(from: startDate) == periodFormatter.string(from: endDate)
        let startFormatter = DateFormatter()
        startFormatter.dateFormat = samePeriod ? "h:mm" : "h:mm a"
        let endFormatter = DateFormatter()
        endFormatter.dateFormat = "h:mm a"
        return "\(startFormatter.string(from: startDate)) – \(endFormatter.string(from: endDate))"
    }
}


struct WeeklyExperimentSheet: View {
    @EnvironmentObject private var appVM: AppViewModel
    @Environment(\.dismiss) private var dismiss
    let experiment: WeeklyExperiment
    @State private var rule: WeeklyExperimentRule
    @State private var startError: String?
    @State private var completionReviewExperiment: WeeklyExperiment?

    init(experiment: WeeklyExperiment) {
        self.experiment = experiment
        _rule = State(initialValue: experiment.rule)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                MivoColors.background.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        Label(experiment.status == .completed ? "What changed" : "One small experiment", systemImage: "flask.fill")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(MivoColors.blue)
                        Text(experiment.title)
                            .font(.system(size: 27, weight: .bold, design: .rounded))
                            .foregroundColor(MivoColors.screenTimeInk)
                        Text(experiment.reason)
                            .font(.system(size: 15))
                            .foregroundColor(MivoColors.textSecondary)
                            .lineSpacing(5)

                        if experiment.status == .proposed { proposalControls }
                        if experiment.status == .active { activeSummary }
                        if experiment.status == .completed { resultSummary }
                    }
                    .padding(20).padding(.bottom, 30)
                }
            }
            .navigationTitle("7-Day Experiment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Close") { dismiss() } } }
            .alert("Experiment not started", isPresented: Binding(
                get: { startError != nil },
                set: { if !$0 { startError = nil } }
            )) {
                Button("OK", role: .cancel) { startError = nil }
            } message: {
                Text(startError ?? "Please try again.")
            }
            .sheet(item: $completionReviewExperiment) { experiment in
                WeeklyExperimentCompletionView(
                    experiment: experiment,
                    onLater: { completionReviewExperiment = nil },
                    onCompleted: {
                        completionReviewExperiment = nil
                        dismiss()
                    }
                )
                .environmentObject(appVM)
                .interactiveDismissDisabled()
            }
        }
    }

    private var proposalControls: some View {
        VStack(alignment: .leading, spacing: 14) {
            experimentRuleCard
            VStack(alignment: .leading, spacing: 5) {
                Text("How Mivo will measure it").font(.system(size: 13, weight: .bold))
                Text("The primary metric is \(metricLabel). Mivo calls it helpful after at least three comparable sessions and a 10% improvement.")
                    .font(.system(size: 12)).foregroundColor(MivoColors.textSecondary).lineSpacing(3)
            }
            .padding(14).background(MivoColors.card).clipShape(RoundedRectangle(cornerRadius: 8))

            Button {
                if appVM.approveWeeklyExperiment(id: experiment.id, rule: rule) {
                    dismiss()
                } else {
                    startError = "Another experiment may already be active. Open the current experiment from Home and finish it before starting this one."
                }
            } label: {
                Text("Approve for 7 days").font(.system(size: 15, weight: .bold)).foregroundColor(MivoColors.white)
                    .frame(maxWidth: .infinity).padding(.vertical, 14).background(MivoColors.blue).clipShape(RoundedRectangle(cornerRadius: 8))
            }.buttonStyle(.plain)
            Button("Not this week") { appVM.declineWeeklyExperiment(id: experiment.id); dismiss() }
                .font(.system(size: 14, weight: .semibold)).foregroundColor(MivoColors.textSecondary).frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder private var experimentRuleCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Approved rule").font(.system(size: 14, weight: .bold))
            if experiment.type == .protectedWindow {
                Stepper("Starts at \(hour(rule.startHour ?? 21))", value: Binding(get: { rule.startHour ?? 21 }, set: { value in rule.startHour = value; rule.endHour = (value + 1) % 24 }), in: 0...23)
                Text("Protected apps remain locked for this hour unless today's schedule already includes it.")
                    .font(.system(size: 11)).foregroundColor(MivoColors.textSecondary)
            } else if experiment.type == .reduceExtensions {
                Label("Keep each session's original limit", systemImage: "timer")
            } else {
                Label("Use the repeated-opening friction ladder", systemImage: "hourglass")
            }
        }.padding(14).background(MivoColors.card).clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var activeSummary: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Day \(experiment.dayNumber) of 7").font(.system(size: 20, weight: .bold))
            MivoProgressSegments(completed: experiment.dayNumber, tint: MivoColors.blue)
            experimentRuleCard
            Text("You can keep using Mivo normally. The experiment only applies the rule you approved.")
                .font(.system(size: 12)).foregroundColor(MivoColors.textSecondary)
        }
    }

    private var resultSummary: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                comparisonCell("Before", value: metricValue(experiment.baselineMetrics))
                comparisonCell("During", value: metricValue(experiment.resultMetrics ?? experiment.baselineMetrics))
            }
            Text(outcomeCopy).font(.system(size: 14, weight: .semibold)).foregroundColor(MivoColors.textSecondary).lineSpacing(4)
            if let finalDecision = experiment.finalDecision {
                Label("Decision saved: \(finalDecision.rawValue.capitalized)", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(MivoColors.blue)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(MivoColors.card)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                Button {
                    completionReviewExperiment = experiment
                } label: {
                    Label("Complete experiment and share feedback", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(MivoColors.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(MivoColors.blue)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func comparisonCell(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) { Text(title).font(.system(size: 10, weight: .bold)).foregroundColor(MivoColors.textMuted); Text(value).font(.system(size: 22, weight: .bold)) }
            .frame(maxWidth: .infinity, alignment: .leading).padding(14).background(MivoColors.card).clipShape(RoundedRectangle(cornerRadius: 8))
    }
    private var metricLabel: String { experiment.primaryMetric.replacingOccurrences(of: "_", with: " ") }
    private func metricValue(_ metrics: ExperimentMetrics) -> String {
        switch experiment.type {
        case .protectedWindow: return "\(metrics.outsideWindowMinutes)m"
        case .reduceExtensions: return "\(Int((metrics.extensionRate * 100).rounded()))%"
        case .strongerFriction: return "\(Int((metrics.cancellationRate * 100).rounded()))% paused"
        }
    }
    private var outcomeCopy: String {
        switch experiment.outcome {
        case .helped: return "The primary metric improved by at least 10%. This experiment appears to have helped."
        case .worsened: return "The primary metric moved in the other direction. That does not mean failure; this rule may simply not fit your week."
        default: return "There was no clear change, or there were fewer than three comparable sessions."
        }
    }
    private func hour(_ value: Int) -> String { let f=DateFormatter(); f.dateFormat="h a"; let d=Calendar.current.date(bySettingHour:value,minute:0,second:0,of:Date()) ?? Date(); return f.string(from:d) }
}

struct WeeklyExperimentCompletionView: View {
    @EnvironmentObject private var appVM: AppViewModel

    let experiment: WeeklyExperiment
    let onLater: () -> Void
    let onCompleted: () -> Void

    @State private var feedback: WeeklyExperimentFeedback?
    @State private var decision: WeeklyExperimentDecision?
    @State private var note = ""

    var body: some View {
        NavigationStack {
            ZStack {
                MivoColors.background.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 22) {
                        completionHeader
                        resultComparison
                        feedbackSection
                        nextStepSection

                        Button(action: submit) {
                            Label("Complete experiment", systemImage: "checkmark")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(MivoColors.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 15)
                                .background(canSubmit ? MivoColors.blue : MivoColors.muted)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                        .disabled(!canSubmit)
                    }
                    .padding(20)
                    .padding(.bottom, 24)
                }
            }
            .navigationTitle("Experiment complete")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Later", action: onLater)
                }
            }
        }
    }

    private var completionHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 42, weight: .bold))
                .foregroundColor(MivoColors.blue)
            Text("Seven days complete")
                .font(.system(size: 29, weight: .bold, design: .rounded))
                .foregroundColor(MivoColors.screenTimeInk)
            Text(experiment.title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(MivoColors.textPrimary)
            Text(outcomeCopy)
                .font(.system(size: 14))
                .foregroundColor(MivoColors.textSecondary)
                .lineSpacing(4)
        }
    }

    private var resultComparison: some View {
        HStack(spacing: 10) {
            comparisonCell("Before", metrics: experiment.baselineMetrics)
            comparisonCell("During", metrics: experiment.resultMetrics ?? experiment.baselineMetrics)
        }
    }

    private var feedbackSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("How did this experiment feel?")
                .font(.system(size: 17, weight: .bold))
                .foregroundColor(MivoColors.textPrimary)
            ForEach(WeeklyExperimentFeedback.allCases) { option in
                choiceRow(
                    title: feedbackTitle(option),
                    detail: feedbackDetail(option),
                    selected: feedback == option
                ) {
                    feedback = option
                    HapticsService.selection()
                }
            }
            TextField("Anything Mivo should know? (optional)", text: $note, axis: .vertical)
                .lineLimit(2...4)
                .padding(14)
                .background(MivoColors.card)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(MivoColors.border, lineWidth: 1))
        }
    }

    private var nextStepSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("What should happen next?")
                .font(.system(size: 17, weight: .bold))
                .foregroundColor(MivoColors.textPrimary)
            choiceRow(title: "Keep it", detail: "Continue using this rule", selected: decision == .keep) { decision = .keep; HapticsService.selection() }
            choiceRow(title: "Adjust it", detail: "Create a revised experiment to review", selected: decision == .adjust) { decision = .adjust; HapticsService.selection() }
            choiceRow(title: "Stop it", detail: "Return to your regular Mivo setup", selected: decision == .stop) { decision = .stop; HapticsService.selection() }
        }
    }

    private func choiceRow(title: String, detail: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.system(size: 15, weight: .bold)).foregroundColor(MivoColors.textPrimary)
                    Text(detail).font(.system(size: 12)).foregroundColor(MivoColors.textSecondary)
                }
                Spacer()
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundColor(selected ? MivoColors.blue : MivoColors.textMuted)
            }
            .padding(14)
            .background(selected ? MivoColors.blue.opacity(0.10) : MivoColors.card)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(selected ? MivoColors.blue : MivoColors.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func comparisonCell(_ title: String, metrics: ExperimentMetrics) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(MivoColors.textMuted)
            Text(metricValue(metrics))
                .font(.system(size: 25, weight: .bold, design: .rounded))
                .foregroundColor(MivoColors.screenTimeInk)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(15)
        .background(MivoColors.card)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var canSubmit: Bool { feedback != nil && decision != nil }

    private func submit() {
        guard let feedback, let decision else { return }
        appVM.completeWeeklyExperimentReview(
            id: experiment.id,
            feedback: feedback,
            note: note,
            decision: decision
        )
        HapticsService.success()
        onCompleted()
    }

    private func metricValue(_ metrics: ExperimentMetrics) -> String {
        switch experiment.type {
        case .protectedWindow: return "\(metrics.outsideWindowMinutes)m"
        case .reduceExtensions: return "\(Int((metrics.extensionRate * 100).rounded()))%"
        case .strongerFriction: return "\(Int((metrics.cancellationRate * 100).rounded()))% paused"
        }
    }

    private var outcomeCopy: String {
        switch experiment.outcome {
        case .helped: return "The main measure improved by at least 10%. This change appears to have helped."
        case .worsened: return "The measure moved in the other direction. This rule may simply not have fit your week."
        default: return "There was no clear change yet, or Mivo did not have three comparable sessions."
        }
    }

    private func feedbackTitle(_ feedback: WeeklyExperimentFeedback) -> String {
        switch feedback {
        case .helpful: return "Helpful"
        case .neutral: return "Not sure yet"
        case .notHelpful: return "Not helpful"
        }
    }

    private func feedbackDetail(_ feedback: WeeklyExperimentFeedback) -> String {
        switch feedback {
        case .helpful: return "This change made scrolling feel more intentional"
        case .neutral: return "The week felt about the same"
        case .notHelpful: return "This rule did not fit how I use my phone"
        }
    }
}

// MARK: - Monthly Plan Forecast

/// Shows the next 30 days of the personalized plan with each day's projected target.
/// Reachable by tapping the personalized meter card on Home.
struct MonthlyPlanForecastView: View {
    let plan: ScreenTimeReductionPlan
    @Environment(\.dismiss) private var dismiss

    private let daysToShow = 30
    private let observationDuration = 3
    @EnvironmentObject private var appVM: AppViewModel
    private var floorMinutes: Int {
        max(15, appVM.onboardingProfile.dailyScrollGoalMinutes ?? 30)
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    headerStats
                    trajectoryChart
                    ForEach(weekGroups) { group in
                        weekSection(group)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 24)
            }
            .background(MivoColors.background.ignoresSafeArea())
            .navigationTitle("Your plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: - Header stats

    private var headerStats: some View {
        HStack(spacing: 10) {
            statBlock(label: "Today", value: format(currentTodayMinutes), color: MivoColors.accent)
            statBlock(label: "Goal", value: format(floorMinutes), color: MivoColors.timerGreen)
            statBlock(label: "Days to goal", value: daysToGoalDisplay, color: MivoColors.screenTimeInk)
        }
    }

    private func statBlock(label: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(MivoColors.textMuted)
                .textCase(.uppercase)
            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundColor(color)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .background(MivoColors.surfaceRaised.opacity(0.62))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(MivoColors.white.opacity(0.58), lineWidth: 1))
    }

    // MARK: - Trajectory chart

    /// Simple inline line chart with axis labels. Avoids Swift Charts so the
    /// view stays small and consistent with the rest of the app.
    private var trajectoryChart: some View {
        let entries = forecast
        let cappedMinutes = entries.map { $0.isObservation ? plan.baselineMinutes : $0.minutes }
        let maxMinutes = max(cappedMinutes.max() ?? plan.baselineMinutes, floorMinutes + 10)
        let minMinutes = max(0, floorMinutes - 5)
        let range = max(1, maxMinutes - minMinutes)

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Trajectory", systemImage: "chart.line.downtrend.xyaxis")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(MivoColors.textMuted)
                    .textCase(.uppercase)
                Spacer()
                Text("Next \(daysToShow) days")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(MivoColors.textMuted)
            }

            GeometryReader { proxy in
                let width = proxy.size.width
                let height = proxy.size.height
                let xStep = entries.count > 1 ? width / CGFloat(entries.count - 1) : width

                ZStack {
                    // Goal line
                    let goalY = height - height * CGFloat(floorMinutes - minMinutes) / CGFloat(range)
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: goalY))
                        path.addLine(to: CGPoint(x: width, y: goalY))
                    }
                    .stroke(style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .foregroundColor(MivoColors.timerGreen.opacity(0.6))

                    // Filled area
                    Path { path in
                        guard !entries.isEmpty else { return }
                        path.move(to: CGPoint(x: 0, y: height))
                        for (idx, entry) in entries.enumerated() {
                            let mins = entry.isObservation ? plan.baselineMinutes : entry.minutes
                            let y = height - height * CGFloat(mins - minMinutes) / CGFloat(range)
                            path.addLine(to: CGPoint(x: CGFloat(idx) * xStep, y: y))
                        }
                        path.addLine(to: CGPoint(x: width, y: height))
                        path.closeSubpath()
                    }
                    .fill(
                        LinearGradient(
                            colors: [MivoColors.accent.opacity(0.22), MivoColors.accent.opacity(0.02)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                    // Line
                    Path { path in
                        guard !entries.isEmpty else { return }
                        for (idx, entry) in entries.enumerated() {
                            let mins = entry.isObservation ? plan.baselineMinutes : entry.minutes
                            let y = height - height * CGFloat(mins - minMinutes) / CGFloat(range)
                            let pt = CGPoint(x: CGFloat(idx) * xStep, y: y)
                            if idx == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
                        }
                    }
                    .stroke(MivoColors.accent, style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))

                    // Today dot
                    if let firstIdx = entries.firstIndex(where: { $0.isToday }) {
                        let entry = entries[firstIdx]
                        let mins = entry.isObservation ? plan.baselineMinutes : entry.minutes
                        let y = height - height * CGFloat(mins - minMinutes) / CGFloat(range)
                        Circle()
                            .fill(MivoColors.accent)
                            .frame(width: 9, height: 9)
                            .position(x: CGFloat(firstIdx) * xStep, y: y)
                            .overlay(
                                Circle()
                                    .strokeBorder(Color.white, lineWidth: 2)
                                    .frame(width: 9, height: 9)
                                    .position(x: CGFloat(firstIdx) * xStep, y: y)
                            )
                    }
                }
            }
            .frame(height: 110)

            HStack {
                legendDot(color: MivoColors.accent, label: "Target")
                legendDot(color: MivoColors.timerGreen, label: "Goal (\(format(floorMinutes)))", dashed: true)
                Spacer()
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(MivoColors.surfaceRaised.opacity(0.62))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(MivoColors.white.opacity(0.58), lineWidth: 1))
    }

    private func legendDot(color: Color, label: String, dashed: Bool = false) -> some View {
        HStack(spacing: 5) {
            if dashed {
                Rectangle()
                    .fill(color)
                    .frame(width: 12, height: 2)
            } else {
                Circle().fill(color).frame(width: 7, height: 7)
            }
            Text(label)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(MivoColors.textSecondary)
        }
    }

    // MARK: - Week sections

    private func weekSection(_ group: WeekGroup) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(group.title)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(MivoColors.screenTimeInk)
                if let badge = group.badge {
                    Text(badge)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(MivoColors.heroText)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(group.badgeColor)
                        .clipShape(Capsule())
                }
                Spacer()
                Text(group.headlineValue)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(MivoColors.textSecondary)
                    .monospacedDigit()
            }

            VStack(spacing: 6) {
                ForEach(group.entries, id: \.id) { entry in
                    forecastRow(entry, peakMinutes: group.peakMinutes)
                }
            }
        }
        .padding(14)
        .background(MivoColors.surfaceRaised.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(MivoColors.white.opacity(0.58), lineWidth: 1))
    }

    private func forecastRow(_ entry: ForecastEntry, peakMinutes: Int) -> some View {
        let isHighlighted = entry.isToday || entry.isGoalDay
        let accent: Color = entry.isGoalDay ? MivoColors.timerGreen : MivoColors.accent
        let safePeak = max(peakMinutes, floorMinutes + 1)
        let progress: CGFloat = {
            if entry.isObservation { return 1.0 }
            let denom = max(1, safePeak - floorMinutes)
            return min(1.0, max(0.08, CGFloat(entry.minutes - floorMinutes) / CGFloat(denom)))
        }()

        return HStack(spacing: 12) {
            // Day-of-week pill
            VStack(spacing: 1) {
                Text(entry.weekdayShort)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(isHighlighted ? .white : MivoColors.textMuted)
                Text("\(entry.dayOfMonth)")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(isHighlighted ? .white : MivoColors.screenTimeInk)
                    .monospacedDigit()
            }
            .frame(width: 38, height: 40)
            .background(isHighlighted ? accent : MivoColors.surface.opacity(0.7))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            // Mini progress bar showing how far from goal
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    if entry.isToday {
                        Text("Today")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(accent)
                    } else if entry.isGoalDay {
                        Text("Goal reached")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(MivoColors.timerGreen)
                    } else if entry.isObservation {
                        Text("Observation")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(MivoColors.blue)
                    } else {
                        Text("Day \(entry.dayNumber)")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(MivoColors.textMuted)
                    }
                    Spacer(minLength: 0)
                }

                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(MivoColors.border.opacity(0.28))
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: entry.isGoalDay
                                        ? [MivoColors.timerGreen.opacity(0.8), MivoColors.timerGreen]
                                        : [MivoColors.accent.opacity(0.75), MivoColors.accent],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: max(8, proxy.size.width * progress))
                    }
                }
                .frame(height: 6)
            }

            // Minutes value
            Text(entry.formattedMinutes)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundColor(entry.isGoalDay ? MivoColors.timerGreen : MivoColors.screenTimeInk)
                .monospacedDigit()
                .frame(minWidth: 52, alignment: .trailing)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(entry.isToday ? accent.opacity(0.08) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    // MARK: - Data

    private struct ForecastEntry: Equatable {
        let id: String
        let dayNumber: Int
        let date: Date
        let minutes: Int
        let isObservation: Bool
        let isToday: Bool
        let isGoalDay: Bool

        var weekdayShort: String {
            let f = DateFormatter()
            f.dateFormat = "EEE"
            return f.string(from: date).uppercased()
        }

        var dayOfMonth: Int {
            Calendar.current.component(.day, from: date)
        }

        var formattedMinutes: String {
            if isObservation { return "—" }
            let hours = minutes / 60
            let mins = minutes % 60
            return hours > 0 ? "\(hours)h \(mins)m" : "\(mins)m"
        }
    }

    private struct WeekGroup: Identifiable {
        let id: Int
        let title: String
        let badge: String?
        let badgeColor: Color
        let headlineValue: String
        let entries: [ForecastEntry]
        let peakMinutes: Int
    }

    private var forecast: [ForecastEntry] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let remainingObservation = plan.collecting ? max(0, plan.daysNeeded - plan.daysCollected) : 0
        let startingDayIndex = plan.collecting ? 1 : plan.dayIndex
        let pastAverage = plan.baselineMinutes
        var entries: [ForecastEntry] = []
        var goalHit = false
        for offset in 0..<daysToShow {
            guard let date = calendar.date(byAdding: .day, value: offset, to: today) else { continue }
            let isToday = offset == 0
            if offset < remainingObservation {
                let observationDayNumber = plan.daysCollected + offset + 1
                entries.append(ForecastEntry(
                    id: "obs-\(offset)",
                    dayNumber: observationDayNumber,
                    date: date,
                    minutes: 0,
                    isObservation: true,
                    isToday: isToday,
                    isGoalDay: false
                ))
                continue
            }
            let planDay = startingDayIndex + (offset - remainingObservation)
            let minutes = AIService.projectedTargetMinutes(
                dayIndex: planDay,
                baseline: pastAverage,
                floor: floorMinutes,
                comeback: appVM.comebackAnchor
            )
            // First day the plan reaches the goal — flag it once.
            let isFirstGoalHit = (minutes == floorMinutes) && !goalHit
            if isFirstGoalHit { goalHit = true }
            entries.append(ForecastEntry(
                id: "plan-\(planDay)",
                dayNumber: planDay,
                date: date,
                minutes: minutes,
                isObservation: false,
                isToday: isToday,
                isGoalDay: isFirstGoalHit
            ))
        }
        return entries
    }

    private var weekGroups: [WeekGroup] {
        let entries = forecast
        let chunks = stride(from: 0, to: entries.count, by: 7).map { start -> [ForecastEntry] in
            Array(entries[start..<min(start + 7, entries.count)])
        }
        return chunks.enumerated().map { idx, chunk -> WeekGroup in
            let peak = chunk.filter { !$0.isObservation }.map(\.minutes).max() ?? plan.baselineMinutes
            let nonObs = chunk.filter { !$0.isObservation }
            let firstMins = nonObs.first?.minutes
            let lastMins = nonObs.last?.minutes
            let headline: String
            if let f = firstMins, let l = lastMins, f != l {
                headline = "\(format(f)) → \(format(l))"
            } else if let l = lastMins {
                headline = format(l)
            } else {
                headline = "Observing"
            }
            let title: String = {
                switch idx {
                case 0: return "This week"
                case 1: return "Next week"
                default: return "Week \(idx + 1)"
                }
            }()
            let (badge, badgeColor): (String?, Color) = {
                if chunk.contains(where: { $0.isObservation }) {
                    return ("Observation", MivoColors.blue)
                }
                if chunk.contains(where: { $0.isGoalDay }) {
                    return ("Goal week", MivoColors.timerGreen)
                }
                if idx == 0 {
                    return (appVM.comebackAnchor != nil ? "Fresh start" : "Lenient", MivoColors.accent)
                }
                return (nil, .clear)
            }()
            return WeekGroup(
                id: idx,
                title: title,
                badge: badge,
                badgeColor: badgeColor,
                headlineValue: headline,
                entries: chunk,
                peakMinutes: peak
            )
        }
    }

    // MARK: - Helpers

    private var currentTodayMinutes: Int {
        if plan.collecting { return plan.baselineMinutes }
        return plan.targetMinutes
    }

    private var daysToGoalDisplay: String {
        let entries = forecast
        if let goalIdx = entries.firstIndex(where: { $0.isGoalDay }) {
            let days = goalIdx + 1
            return "\(days)d"
        }
        // Goal not reached within window — extrapolate
        let total = AIService.projectedDaysUntilGoal(
            baseline: plan.baselineMinutes,
            goal: floorMinutes,
            comeback: appVM.comebackAnchor
        )
        return "\(total)d"
    }

    private func format(_ minutes: Int) -> String {
        if minutes < 60 { return "\(minutes)m" }
        let h = minutes / 60
        let m = minutes % 60
        return m == 0 ? "\(h)h" : "\(h)h \(m)m"
    }
}

private extension View {
    /// A small lock on a Plus feature while it's locked.
    func plusLockBadge(_ locked: Bool) -> some View {
        overlay(alignment: .topTrailing) {
            if locked {
                Text("Plus")
                    .font(.system(size: 10.5, weight: .bold))
                    .foregroundColor(MivoColors.deep)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(MivoColors.surfaceV2))
                    .padding(10)
                    .allowsHitTesting(false)
            }
        }
    }
}
