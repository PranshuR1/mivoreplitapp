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
    @State private var referralSummary: ReferralSummary?
    @State private var referralLoading = false
    @State private var showReferralHub = false
    @State private var showExperimentHub = false
    @State private var showMivoClear = false
    @ObservedObject private var expansion = ProductExpansionStore.shared
    @State private var showRecoveryMode = false
    private let screenTimePoller = Timer.publish(every: 5, on: .main, in: .common).autoconnect()
    #if canImport(FamilyControls)
    @State private var impulseSelection = FamilyActivitySelection()
    @State private var showImpulsePicker = false
    #endif

    var body: some View {
        ZStack {
            homeBackdrop

            ScrollView(showsIndicators: false) {
                VStack(spacing: 26) {
                    header
                    heroCard
                    metricsRow
                    adaptivePlanCard
                    ExperimentsHomeCard(
                        experiment: appVM.currentWeeklyExperiment,
                        completedCount: appVM.completedWeeklyExperiments.count,
                        open: { showExperimentHub = true }
                    )
                    if expansion.isEnabled(.mivoClear) {
                        MivoClearHomeCard { showMivoClear = true }
                    }
                    if referralSummary?.campaign != nil {
                        ReferralHomeCard(
                            summary: referralSummary,
                            isLoading: referralLoading,
                            openHub: { showReferralHub = true }
                        )
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 12)
                .padding(.bottom, 40)
                .mivoReadableWidth()
            }
        }
        .navigationBarHidden(true)
        .onAppear {
            protectionEnabled = FamilyControlsManager.shared.isImpulseProtectionEnabled()
            #if canImport(FamilyControls)
            if #available(iOS 16.0, *) {
                impulseSelection = FamilyControlsManager.shared.loadFamilyActivitySelection()
                FamilyControlsManager.shared.applyImpulseProtectionIfNeeded()
            }
            #endif
            appVM.refreshScreenTimeData()
            Task {
                await expansion.prepare(for: appVM)
                await MivoClearStore.shared.prepare(for: appVM)
                async let plan: Void = refreshAdaptivePlan()
                async let referral: Void = refreshReferralSummary()
                await appVM.refreshServerAdminRole()
                _ = await (plan, referral)
                await appVM.refreshWeeklyExperiments()
            }
        }
        .onChange(of: appVM.sessions.count) { _, _ in
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
        .sheet(isPresented: $showReferralHub, onDismiss: {
            Task { await refreshReferralSummary() }
        }) {
            ReferralHubView()
                .environmentObject(appVM)
        }
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
    }

    private func handleTodayGuideAction() {
        let guide = expansion.todayGuide(using: appVM)
        switch guide.kind {
        case .rescue:
            showRecoveryMode = true
        case .experiment:
            showExperimentHub = true
        case .nextWindow:
            appVM.deepLinkInterventionRequested = true
        case .dailySchedule:
            appVM.evaluateDailyScrollSchedulePrompt()
        case .truthCheck:
            appVM.evaluateTimeTruthPrompt()
        case .expiredSession, .complete:
            break
        }
    }

    @MainActor
    private func refreshReferralSummary() async {
        referralLoading = true
        referralSummary = try? await appVM.loadReferralSummary()
        referralLoading = false
    }

    private var homeBackdrop: some View {
        MivoColors.background.ignoresSafeArea()
    }

    private var header: some View {
        HStack(spacing: 12) {
            MivoLogo(size: 42)

            VStack(alignment: .leading, spacing: 3) {
                Text("\(greeting()), \(firstName)")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(MivoColors.screenTimeInk)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                Text(dateLabel)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(MivoColors.textSecondary)
            }

            Spacer()

            Button {
                setImpulseProtection(!protectionEnabled)
            } label: {
                Image(systemName: protectionEnabled ? "shield.fill" : "shield")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(protectionEnabled ? MivoColors.accent : MivoColors.textSecondary)
                    .frame(width: 42, height: 42)
                    .background(MivoColors.card)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
    }

    private var heroCard: some View {
        NavigationLink {
            if #available(iOS 16.0, *) {
                ScreenTimeUsageView()
            }
        } label: {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Label(hasScreenTimeAccess ? "Live Screen Time" : "Awaiting access", systemImage: "waveform.path.ecg")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(MivoColors.heroText)
                        .padding(.horizontal, 12)
                        .frame(height: 32)
                        .background(MivoColors.heroBg)
                        .clipShape(Capsule())

                    Spacer()

                    Text(statusLabel)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(MivoColors.textMuted)
                }

                if hasScreenTimeAccess {
                    screenTimeReportSyncSurface
                        .frame(maxWidth: .infinity)
                        .frame(height: 190)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                } else {
                    connectScreenTimeBlock
                        .frame(minHeight: 132, alignment: .topLeading)
                }

                HStack(spacing: 10) {
                    miniHeroStat(
                        icon: "lock.open.fill",
                        value: "\(appVM.todaysSessions.count)",
                        label: appVM.todaysSessions.count == 1 ? "unlock" : "unlocks"
                    )
                    miniHeroStat(icon: trendIcon, value: trendText, label: "week")
                }
            }
            .padding(18)
            .background(MivoColors.surface)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(MivoColors.border.opacity(0.55), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    private var connectScreenTimeBlock: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("Connect Screen Time")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundColor(MivoColors.screenTimeInk)
                .lineLimit(2)
                .minimumScaleFactor(0.82)
            Text("Mivo will show Apple’s real Screen Time report here. No placeholder totals.")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(MivoColors.textSecondary)
                .lineSpacing(3)
        }
    }

    private func miniHeroStat(icon: String, value: String, label: String) -> some View {
        HStack(spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(MivoColors.accent)
            VStack(alignment: .leading, spacing: 0) {
                Text(value)
                    .font(.system(size: 15, weight: .bold).monospacedDigit())
                    .foregroundColor(MivoColors.screenTimeInk)
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(MivoColors.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(11)
        .background(MivoColors.background.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var metricsRow: some View {
        HStack(spacing: 10) {
            metricCard(icon: "target", value: "\(appVM.todaysSessions.count)", label: "Sessions")
            metricCard(icon: "chart.line.uptrend.xyaxis", value: trendText, label: "vs last week", tint: trendTint)
            metricCard(icon: "brain.head.profile", value: "\(appVM.truthChecks.count)", label: "Truth checks")
        }
    }

    private func metricCard(
        icon: String,
        value: String,
        label: String,
        tint: Color = MivoColors.secondary
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(tint)
            Text(value)
                .font(.system(size: 20, weight: .bold).monospacedDigit())
                .foregroundColor(MivoColors.screenTimeInk)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(MivoColors.textSecondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, minHeight: 82, alignment: .leading)
        .padding(13)
        .background(MivoColors.card)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(MivoColors.border.opacity(0.35), lineWidth: 1)
        }
    }

    @ViewBuilder
    private var screenTimeReportSyncSurface: some View {
        #if canImport(DeviceActivity) && canImport(FamilyControls) && canImport(ManagedSettings)
        if #available(iOS 16.0, *) {
            MivoScreenTimeUsageLiveReport()
        }
        #else
        EmptyView()
        #endif
    }

    private var adaptivePlanCard: some View {
        let plan = displayPlan(adaptivePlan ?? appVM.adaptiveScreenTimePlan())

        return Group {
            if plan.collecting {
                observationProgressSection(plan)
            } else {
                personalizedPlanTimeline(plan)
            }
        }
        .sheet(isPresented: $showMonthlyForecast) {
            MonthlyPlanForecastView(plan: plan).environmentObject(appVM)
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
                : "Today’s scroll windows are locked from your daily check. Mivo trims your target from your blended baseline.",
            decisionReason: plan.collecting
                ? "These are the times you chose for today. Days 1-3 stay in observation mode."
                : "These windows are the schedule you locked for today. You can choose again tomorrow morning.",
            windows: schedule.windows
        )
    }

    private func observationProgressSection(_ plan: ScreenTimeReductionPlan) -> some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack(spacing: 10) {
                Image(systemName: "clock.badge.checkmark")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(MivoColors.blue)
                Text("3-day observation · Day \(min(plan.daysCollected + 1, plan.daysNeeded))")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundColor(MivoColors.screenTimeInk)
                Spacer()
                Text("No cap")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(MivoColors.blue)
            }

            HStack(spacing: 7) {
                ForEach(0..<plan.daysNeeded, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(index < plan.daysCollected ? MivoColors.blue : MivoColors.surface)
                        .frame(height: 8)
                }
            }

            Text("Mivo is observing your real Screen Time first. Your personalized plan appears only after all three observation days are complete.")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(MivoColors.textSecondary)
                .lineSpacing(3)
        }
        .padding(.vertical, 18)
        .overlay(alignment: .top) {
            Rectangle().fill(MivoColors.border.opacity(0.34)).frame(height: 1)
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(MivoColors.border.opacity(0.34)).frame(height: 1)
        }
    }

    private func personalizedPlanTimeline(_ plan: ScreenTimeReductionPlan) -> some View {
        let windows = plan.windows.sorted {
            if $0.startHour == $1.startHour { return $0.endHour < $1.endHour }
            return $0.startHour < $1.startHour
        }

        return VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(MivoColors.white)
                    .frame(width: 42, height: 42)
                    .background(MivoColors.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text("Personalized meter")
                        .font(.system(size: 19, weight: .bold, design: .rounded))
                        .foregroundColor(MivoColors.screenTimeInk)
                    Text("Day \(plan.dayIndex) · \(plan.strictnessPercent)% stricter")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(MivoColors.accent)
                }

                Spacer(minLength: 8)

                Button {
                    HapticsService.selection()
                    showMonthlyForecast = true
                } label: {
                    Image(systemName: "calendar")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(MivoColors.accent)
                        .frame(width: 38, height: 38)
                        .background(MivoColors.background)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("View full personalized plan")
            }

            Text(plan.summary)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(MivoColors.textSecondary)
                .lineSpacing(3)

            HStack(spacing: 0) {
                personalizedPlanMetric("BASELINE", value: formatDuration(plan.baselineMinutes))
                Rectangle()
                    .fill(MivoColors.border.opacity(0.28))
                    .frame(width: 1, height: 42)
                personalizedPlanMetric("TARGET", value: formatDuration(plan.targetMinutes))
                Rectangle()
                    .fill(MivoColors.border.opacity(0.28))
                    .frame(width: 1, height: 42)
                personalizedPlanMetric("SESSIONS", value: "\(windows.count)")
            }
            .padding(.vertical, 12)
            .background(MivoColors.background.opacity(0.72))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            Rectangle()
                .fill(MivoColors.border.opacity(0.28))
                .frame(height: 1)

            if windows.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "calendar.badge.plus")
                        .foregroundColor(MivoColors.accent)
                    Text("Choose today’s scroll windows to place them on your plan.")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(MivoColors.textSecondary)
                }
                .padding(.vertical, 22)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(windows.enumerated()), id: \.element.id) { index, window in
                        planWindowRow(
                            window,
                            state: planWindowState(at: index, windows: windows),
                            isLast: index == windows.count - 1
                        )
                    }
                }
            }

            Text(plan.decisionReason)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(MivoColors.textMuted)
                .lineSpacing(3)

            Button {
                HapticsService.selection()
                showMonthlyForecast = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "hand.tap.fill")
                    Text("View your full personalized plan")
                    Spacer()
                    Image(systemName: "chevron.right")
                }
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(MivoColors.accent)
            }
            .buttonStyle(.plain)
        }
        .padding(18)
        .background(MivoColors.surfaceRaised.opacity(0.68))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(MivoColors.border.opacity(0.34), lineWidth: 1)
        }
    }

    private func personalizedPlanMetric(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(MivoColors.textMuted)
            Text(value)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundColor(MivoColors.screenTimeInk)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
    }

    private func planWindowRow(
        _ window: ScreenScrollWindow,
        state: HomePlanWindowState,
        isLast: Bool
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack(alignment: .top) {
                if !isLast {
                    Rectangle()
                        .fill(state == .complete ? MivoColors.accent : MivoColors.border.opacity(0.55))
                        .frame(width: 1)
                        .padding(.top, 23)
                }
                planWindowMarker(state)
            }
            .frame(width: 24)
            .frame(maxHeight: .infinity, alignment: .top)

            VStack(alignment: .leading, spacing: 5) {
                Text(fullWindowTimeText(window))
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(MivoColors.screenTimeInk)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Text(windowPeriodLabel(window))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(MivoColors.accent)

                Text("\(window.minutes) min available")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(MivoColors.textMuted)
            }

            Spacer(minLength: 8)
            planWindowStatusChip(state)
        }
        .padding(.vertical, 15)
        .frame(minHeight: 104, alignment: .top)
        .overlay(alignment: .bottomTrailing) {
            if !isLast {
                Rectangle()
                    .fill(MivoColors.border.opacity(0.25))
                    .frame(height: 1)
                    .padding(.leading, 36)
            }
        }
    }

    @ViewBuilder
    private func planWindowMarker(_ state: HomePlanWindowState) -> some View {
        switch state {
        case .complete:
            Image(systemName: "checkmark")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(MivoColors.white)
                .frame(width: 24, height: 24)
                .background(MivoColors.accent)
                .clipShape(Circle())
        case .next:
            Circle()
                .fill(MivoColors.background)
                .frame(width: 22, height: 22)
                .overlay(Circle().strokeBorder(MivoColors.accent, lineWidth: 2))
        case .later:
            Circle()
                .fill(MivoColors.background)
                .frame(width: 22, height: 22)
                .overlay(Circle().strokeBorder(MivoColors.border.opacity(0.75), lineWidth: 2))
        }
    }

    private func planWindowStatusChip(_ state: HomePlanWindowState) -> some View {
        let title: String
        let icon: String
        let foreground: Color
        let background: Color

        switch state {
        case .complete:
            title = "Complete"
            icon = "checkmark.circle.fill"
            foreground = Color(hex: "#37682F")
            background = Color(hex: "#E8F0E2")
        case .next:
            title = "Next"
            icon = "circle"
            foreground = MivoColors.accent
            background = MivoColors.accent.opacity(0.09)
        case .later:
            title = "Later"
            icon = "circle"
            foreground = MivoColors.textSecondary
            background = MivoColors.surface.opacity(0.62)
        }

        return HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .bold))
            Text(title)
                .font(.system(size: 11, weight: .bold))
        }
        .foregroundColor(foreground)
        .padding(.horizontal, 10)
        .frame(height: 34)
        .background(background)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func planWindowState(
        at index: Int,
        windows: [ScreenScrollWindow],
        now: Date = Date()
    ) -> HomePlanWindowState {
        let calendar = Calendar.current
        let currentMinute = calendar.component(.hour, from: now) * 60 + calendar.component(.minute, from: now)
        let nextIndex = windows.firstIndex { currentMinute < normalizedEndMinute($0) }

        if currentMinute >= normalizedEndMinute(windows[index]) {
            return .complete
        }
        if index == nextIndex {
            return .next
        }
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

    private var insightCard: some View {
        let personalized = appVM.personalizedPatternInsights(limit: 1).first
        let hasHistory = appVM.sessions.count >= 2 || appVM.truthChecks.count >= 3

        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: personalized?.icon ?? "lightbulb.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(MivoColors.accent)
                    .frame(width: 24, height: 24)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Mivo noticed")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(MivoColors.screenTimeInk)
                    Text(hasHistory ? (personalized?.title ?? insightText) : "Mivo is still learning your pattern.")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(MivoColors.screenTimeInk)
                        .lineSpacing(3)
                    Text(personalized?.detail ?? "Complete a few sessions and truth checks to unlock a supported insight.")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(MivoColors.textSecondary)
                        .lineSpacing(3)
                }
            }

            if let personalized {
                Rectangle().fill(MivoColors.border.opacity(0.30)).frame(height: 1)
                HStack(alignment: .center, spacing: 10) {
                    Image(systemName: "target")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(MivoColors.accent)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("TRY THIS NEXT")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(MivoColors.accent)
                        Text(personalized.tomorrowExperiment)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(MivoColors.screenTimeInk)
                            .lineLimit(3)
                    }
                    Spacer(minLength: 6)
                    Button { showExperimentHub = true } label: {
                        Image(systemName: "arrow.right")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(MivoColors.blue)
                            .frame(width: 36, height: 36)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Open experiments")
                }
            }
        }
        .padding(.vertical, 18)
        .overlay(alignment: .top) {
            Rectangle().fill(MivoColors.border.opacity(0.30)).frame(height: 1)
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(MivoColors.border.opacity(0.30)).frame(height: 1)
        }
    }

    private var firstName: String {
        appVM.user?.name.split(separator: " ").first.map(String.init) ?? "there"
    }

    private var dateLabel: String {
        let fmt = DateFormatter()
        fmt.dateStyle = .full
        return fmt.string(from: Date())
    }

    private var trendText: String {
        "\(appVM.patternPercent >= 0 ? "+" : "")\(appVM.patternPercent)%"
    }

    private var trendIcon: String {
        appVM.patternPercent <= 0 ? "arrow.down.right" : "arrow.up.right"
    }

    private var trendTint: Color {
        appVM.patternPercent <= 0 ? MivoColors.secondary : MivoColors.timerRed
    }

    private var statusLabel: String {
        if hasScreenTimeAccess {
            return "Live"
        }
        return "Connect"
    }

    private var statusTint: Color {
        switch statusLabel {
        case "Quiet start", "On track": return MivoColors.secondary
        case "Watchful": return MivoColors.accent
        default: return MivoColors.timerRed
        }
    }

    private var insightText: String {
        if hasScreenTimeAccess {
            return "The Screen Time card above is Apple’s live Device Activity report. Mivo is not filling it with session history or estimates."
        }
        if appVM.patternPercent > 20 {
            return "Your usage is trending higher than last week. A short focus session now can keep the day from drifting."
        }
        if appVM.patternPercent < -10 {
            return "You’re trending lower than last week. Keep the same friction in place and let the quiet compound."
        }
        return "Your day is still shapeable. Use a pause before opening the apps you selected during onboarding."
    }

    private var insightTags: [String] {
        [
            protectionEnabled ? "Protected" : "Ready",
            hasScreenTimeAccess ? "Live Screen Time" : "No device report yet",
            appVM.todaysSessions.isEmpty ? "No sessions" : "\(appVM.todaysSessions.count) sessions"
        ]
    }

    private var hasScreenTimeAccess: Bool {
        if #available(iOS 16.0, *) {
            return ScreenTimeDataCollector.shared.authorizationStatus == .authorized
        }
        return false
    }

    private func setImpulseProtection(_ enabled: Bool) {
        HapticsService.selection()
        #if canImport(FamilyControls)
        guard #available(iOS 16.0, *) else {
            protectionEnabled = false
            return
        }

        if enabled {
            guard FamilyControlsManager.shared.hasImpulseSelection() else {
                protectionEnabled = false
                FamilyControlsManager.shared.setImpulseProtectionEnabled(false)
                showImpulsePicker = true
                return
            }

            protectionEnabled = true
            FamilyControlsManager.shared.setImpulseProtectionEnabled(true)
        } else {
            protectionEnabled = false
            FamilyControlsManager.shared.setImpulseProtectionEnabled(false)
        }
        #else
        protectionEnabled = false
        #endif
    }

    private func refreshAdaptivePlan() async {
        let plan = await AIService.makeScreenTimeReductionPlanOnline(
            sessions: appVM.sessions,
            truthChecks: appVM.truthChecks,
            todayScreenTimeMinutes: appVM.deviceActivityMinutesToday,
            profile: appVM.onboardingProfile,
            dailyObservations: appVM.dailyScreenTimeObservations
        )
        await MainActor.run {
            adaptivePlan = plan
        }
    }

    private func greeting() -> String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 0..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        default: return "Good evening"
        }
    }
    
    private func formatDuration(_ minutes: Int) -> String {
        let hours = minutes / 60
        let mins = minutes % 60

        if hours > 0 {
            return "\(hours)h \(mins)m"
        } else {
            return "\(mins)m"
        }
    }
}

private struct ExperimentsHomeCard: View {
    let experiment: WeeklyExperiment?
    let completedCount: Int
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: 11) {
                HStack(spacing: 13) {
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(MivoColors.blue)
                        .frame(width: 38, height: 38)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Experiments")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(MivoColors.screenTimeInk)
                            .multilineTextAlignment(.leading)
                        Text(experiment == nil ? "Try one small change for seven days" : title)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(MivoColors.textSecondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 8)

                    HStack(spacing: 7) {
                        Text(statusLabel)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(MivoColors.blue)
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(MivoColors.textMuted)
                    }
                    .fixedSize(horizontal: true, vertical: false)
                }

                if let experiment, experiment.status == .active {
                    MivoProgressSegments(completed: experiment.dayNumber, tint: MivoColors.blue)
                }
            }
            .padding(.vertical, 15)
            .overlay(alignment: .top) {
                Rectangle().fill(MivoColors.border.opacity(0.30)).frame(height: 1)
            }
            .overlay(alignment: .bottom) {
                Rectangle().fill(MivoColors.border.opacity(0.30)).frame(height: 1)
            }
        }
        .buttonStyle(MivoPressStyle())
    }

    private var statusLabel: String {
        guard let experiment else {
            return completedCount == 1 ? "1 COMPLETE" : "\(completedCount) COMPLETE"
        }
        switch experiment.status {
        case .proposed: return "READY FOR REVIEW"
        case .active: return "DAY \(experiment.dayNumber) OF 7"
        case .completed: return "RESULT READY"
        case .declined: return "EXPERIMENTS"
        }
    }
    private var title: String {
        experiment?.title ?? "Try one change for seven days"
    }
    private var detail: String {
        guard let experiment else {
            return "Choose an experiment, approve its exact rule, and let Mivo track what changes."
        }
        if experiment.status == .proposed { return experiment.reason }
        switch experiment.outcome {
        case .helped: return "Your result is ready. This change appears to have helped."
        case .worsened: return "Your result is ready. This rule may not have fit this week."
        default: return "Your result is ready to review before choosing what comes next."
        }
    }
    private var icon: String { experiment?.status == .completed ? "chart.bar.fill" : "flask.fill" }
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
            let minutes = AIService.personalizedTargetMinutes(
                dayIndex: planDay,
                baseline: pastAverage,
                floor: floorMinutes
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
                    return ("Lenient", MivoColors.accent)
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
        let total = AIService.daysUntilGoalReached(baseline: plan.baselineMinutes, goal: floorMinutes)
        return "\(total)d"
    }

    private func format(_ minutes: Int) -> String {
        if minutes < 60 { return "\(minutes)m" }
        let h = minutes / 60
        let m = minutes % 60
        return m == 0 ? "\(h)h" : "\(h)h \(m)m"
    }
}
