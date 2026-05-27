import SwiftUI

#if canImport(FamilyControls)
import FamilyControls
#endif

struct HomeView: View {
    @EnvironmentObject var appVM: AppViewModel
    @State private var protectionEnabled = false
    @State private var reflectionText = ""
    @State private var reflectionSaved = false
    @State private var adaptivePlan: ScreenTimeReductionPlan? = nil
    @State private var showMonthlyForecast = false
    #if canImport(FamilyControls)
    @State private var impulseSelection = FamilyActivitySelection()
    @State private var showImpulsePicker = false
    #endif

    var body: some View {
        ZStack {
            homeBackdrop

            ScrollView(showsIndicators: false) {
                VStack(spacing: 18) {
                    header
                    heroCard
                    metricsRow
                    adaptivePlanCard
                    protectionCard
                    insightCard
                    reflectionCard
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 118)
            }

            VStack {
                Spacer()
                focusCTA
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
            Task { await refreshAdaptivePlan() }
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
    }

    private var homeBackdrop: some View {
        ZStack {
            MivoColors.background.ignoresSafeArea()
            LinearGradient(
                colors: [
                    MivoColors.heroText,
                    MivoColors.background,
                    MivoColors.surface.opacity(0.45)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            MivoLogo(size: 42)

            VStack(alignment: .leading, spacing: 3) {
                Text("\(greeting()), \(firstName)")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(MivoColors.textPrimary)
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
                    .background(MivoColors.white.opacity(0.58))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
    }

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label(hasScreenTimeAccess ? "Live Screen Time" : "Awaiting access", systemImage: "waveform.path.ecg")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(MivoColors.heroText)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(MivoColors.heroBg)
                    .clipShape(Capsule())

                Spacer()

                Text(statusLabel)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(MivoColors.textMuted)
            }
            .padding(.horizontal, 18)
            .padding(.top, 18)
            .padding(.bottom, 14)

            if hasScreenTimeAccess, #available(iOS 16.0, *) {
                MivoReadableScreenTimeSummaryCard(compact: true)
                    .padding(.horizontal, 14)
            } else {
                connectScreenTimeBlock
                    .padding(.horizontal, 18)
                    .padding(.bottom, 4)
            }

            HStack(spacing: 10) {
                miniHeroPill(icon: "lock.open.fill", title: "\(appVM.todaysSessions.count)", subtitle: appVM.todaysSessions.count == 1 ? "unlock" : "unlocks")
                miniHeroPill(icon: trendIcon, title: trendText, subtitle: "week")
            }
            .padding(.horizontal, 18)
            .padding(.top, 14)
            .padding(.bottom, 18)
        }
        .background(MivoColors.card)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(MivoColors.border.opacity(0.5), lineWidth: 1))
        .shadow(color: Color.black.opacity(0.07), radius: 16, y: 6)
    }

    private var connectScreenTimeBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Connect Screen Time")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundColor(MivoColors.textPrimary)
                .lineLimit(2)
                .minimumScaleFactor(0.82)
            Text("Mivo will show Apple’s real Screen Time report here. No placeholder totals.")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(MivoColors.textSecondary)
                .lineSpacing(3)
        }
        .padding(.vertical, 24)
    }

    private func miniHeroPill(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(MivoColors.accent)
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(MivoColors.textPrimary)
                Text(subtitle)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(MivoColors.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(MivoColors.surface.opacity(0.7))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var metricsRow: some View {
        HStack(spacing: 12) {
            metricCard(icon: "target", value: "\(appVM.todaysSessions.count)", label: "Sessions")
            metricCard(icon: "chart.line.uptrend.xyaxis", value: trendText, label: "vs last week", tint: trendTint)
            metricCard(icon: "brain.head.profile", value: "\(appVM.truthChecks.count)", label: "Truth checks")
        }
    }

    private func metricCard(icon: String, value: String, label: String, tint: Color = MivoColors.secondary) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(tint)
            Text(value)
                .font(.system(size: 21, weight: .bold).monospacedDigit())
                .foregroundColor(MivoColors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(MivoColors.textSecondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(MivoColors.white.opacity(0.62))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(MivoColors.white.opacity(0.58), lineWidth: 1))
    }

    private var protectionCard: some View {
        HStack(spacing: 14) {
            Image(systemName: protectionEnabled ? "shield.checkered" : "shield.lefthalf.filled")
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(protectionEnabled ? MivoColors.secondary : MivoColors.textSecondary)
                .frame(width: 46, height: 46)
                .background(MivoColors.surface)
                .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(protectionEnabled ? "Selected apps are protected" : "Choose apps to protect")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(MivoColors.textPrimary)
                Text(protectionEnabled ? "iOS will show Mivo’s intervention when those apps open." : "Pick distracting apps and add friction before opening them.")
                    .font(.system(size: 13))
                    .foregroundColor(MivoColors.textSecondary)
                    .lineLimit(2)
            }

            Spacer()

            Toggle("", isOn: $protectionEnabled)
                .tint(MivoColors.accent)
                .labelsHidden()
                .onChange(of: protectionEnabled) { _, newValue in
                    setImpulseProtection(newValue)
                }
        }
        .padding(16)
        .background(MivoColors.white.opacity(0.62))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(MivoColors.white.opacity(0.58), lineWidth: 1))
    }

    private var adaptivePlanCard: some View {
        let plan = adaptivePlan ?? appVM.adaptiveScreenTimePlan()

        return Button {
            HapticsService.selection()
            showMonthlyForecast = true
        } label: {
            adaptivePlanCardBody(plan: plan)
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showMonthlyForecast) {
            MonthlyPlanForecastView(plan: plan)
        }
    }

    private func adaptivePlanCardBody(plan: ScreenTimeReductionPlan) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: plan.collecting ? "clock.badge.checkmark" : "sparkles")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(MivoColors.heroText)
                    .frame(width: 42, height: 42)
                    .background(plan.collecting ? MivoColors.blue : MivoColors.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(plan.collecting ? "5-day lenient mode" : "Personalized meter")
                        .font(.system(size: 19, weight: .bold, design: .rounded))
                        .foregroundColor(MivoColors.textPrimary)
                    Text(plan.collecting ? "Day \(min(plan.daysCollected + 1, plan.daysNeeded)) of \(plan.daysNeeded) - 2h/day cap" : "Day \(plan.dayIndex) - \(plan.strictnessPercent)% stricter")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(plan.collecting ? MivoColors.blue : MivoColors.accent)
                }

                Spacer()

                Image(systemName: "calendar")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(MivoColors.textMuted)
            }

            Text(plan.summary)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(MivoColors.textSecondary)
                .lineSpacing(4)

            HStack(spacing: 10) {
                planMetric(title: "Baseline", value: formatDuration(plan.baselineMinutes))
                planMetric(title: plan.collecting ? "Cap" : "Target", value: plan.collecting ? "2h/day" : formatDuration(plan.targetMinutes))
                planMetric(title: "Sessions", value: "\(plan.windows.count)")
            }

            if !plan.windows.isEmpty {
                VStack(spacing: 10) {
                    ForEach(plan.windows) { window in
                        scrollWindowRow(window)
                    }
                }
            }

            if plan.collecting {
                learningProgress(plan)
            }

            Text(plan.decisionReason)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(MivoColors.textMuted)
                .lineSpacing(3)

            HStack(spacing: 6) {
                Image(systemName: "hand.tap.fill")
                    .font(.system(size: 11, weight: .bold))
                Text("Tap to preview the next 30 days")
                    .font(.system(size: 12, weight: .bold))
            }
            .foregroundColor(MivoColors.accent)
        }
        .padding(18)
        .background(MivoColors.white.opacity(0.62))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(MivoColors.white.opacity(0.58), lineWidth: 1))
        .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private func planMetric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(MivoColors.textMuted)
                .textCase(.uppercase)
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundColor(MivoColors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(MivoColors.heroText.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func scrollWindowRow(_ window: ScreenScrollWindow) -> some View {
        HStack(spacing: 12) {
            VStack(spacing: 2) {
                Text(windowTimeText(window))
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(MivoColors.accent)
                Text(formatDuration(window.minutes))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(MivoColors.textSecondary)
            }
            .frame(width: 82)
            .padding(.vertical, 10)
            .background(MivoColors.heroText.opacity(0.72))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(window.title)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(MivoColors.textPrimary)
                Text(window.reason)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(MivoColors.textSecondary)
                    .lineLimit(2)
            }

            Spacer()
        }
        .padding(12)
        .background(MivoColors.surface.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func learningProgress(_ plan: ScreenTimeReductionPlan) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 6) {
                ForEach(0..<plan.daysNeeded, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(index < plan.daysCollected ? MivoColors.blue : MivoColors.border.opacity(0.35))
                        .frame(height: 8)
                }
            }

            Text("First 5 days: lenient mode with a 2-hour daily cap split across two 1-hour scroll sessions. After day 5, Mivo builds your personalized screen-time meter starting at your past-3-day average and trims 10 min/day.")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(MivoColors.textSecondary)
                .lineSpacing(3)
        }
        .padding(14)
        .background(MivoColors.surface.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var insightCard: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Label("Today’s read", systemImage: "sparkles")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(MivoColors.textPrimary)
                Spacer()
                Text(statusLabel)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(statusTint)
            }

            Text(insightText)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(MivoColors.textPrimary)
                .lineSpacing(5)

            HStack(spacing: 8) {
                ForEach(insightTags, id: \.self) { tag in
                    Text(tag)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(MivoColors.textSecondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(MivoColors.heroText)
                        .clipShape(Capsule())
                }
            }
        }
        .padding(18)
        .background(MivoColors.white.opacity(0.62))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(MivoColors.white.opacity(0.58), lineWidth: 1))
    }

    private var reflectionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Quick reflection")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundColor(MivoColors.textPrimary)
                    Text("One sentence is enough.")
                        .font(.system(size: 13))
                        .foregroundColor(MivoColors.textSecondary)
                }
                Spacer()
                if reflectionSaved {
                    Label("Saved", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(MivoColors.secondary)
                }
            }

            ZStack(alignment: .topLeading) {
                if reflectionText.isEmpty {
                    Text("What pulled your attention today?")
                        .font(.system(size: 15))
                        .foregroundColor(MivoColors.textMuted)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 17)
                }

                TextEditor(text: $reflectionText)
                    .font(.system(size: 15))
                    .foregroundColor(MivoColors.textPrimary)
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .frame(minHeight: 104)
            }
            .background(MivoColors.white.opacity(0.68))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

            Button {
                saveReflection()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "square.and.pencil")
                    Text("Save reflection")
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(MivoColors.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(reflectionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? MivoColors.textMuted.opacity(0.36) : MivoColors.blue)
                .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(reflectionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(18)
        .background(MivoColors.white.opacity(0.62))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(MivoColors.white.opacity(0.58), lineWidth: 1))
    }

    private var focusCTA: some View {
        NavigationLink {
            FocusView()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 15, weight: .semibold))
                Text("Enter Focus")
                    .font(.system(size: 17, weight: .semibold))
                Spacer()
                Image(systemName: "arrow.right")
                    .font(.system(size: 15, weight: .semibold))
            }
            .foregroundColor(MivoColors.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
            .background(MivoColors.blue)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .shadow(color: MivoColors.blue.opacity(0.24), radius: 18, y: 8)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
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

    private func saveReflection() {
        guard !reflectionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        HapticsService.success()
        reflectionSaved = true
        reflectionText = ""
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            reflectionSaved = false
        }
    }

    private func refreshAdaptivePlan() async {
        let plan = await AIService.makeScreenTimeReductionPlanOnline(
            sessions: appVM.sessions,
            truthChecks: appVM.truthChecks,
            todayScreenTimeMinutes: appVM.deviceActivityMinutesToday,
            profile: appVM.onboardingProfile
        )
        await MainActor.run {
            adaptivePlan = plan
        }
    }

    private func windowTimeText(_ window: ScreenScrollWindow) -> String {
        "\(hourLabel(window.startHour))-\(hourLabel(window.endHour))"
    }

    private func hourLabel(_ hour: Int) -> String {
        let normalized = ((hour % 24) + 24) % 24
        if normalized == 0 { return "12a" }
        if normalized < 12 { return "\(normalized)a" }
        if normalized == 12 { return "12p" }
        return "\(normalized - 12)p"
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

// MARK: - Monthly Plan Forecast

/// Shows the next 30 days of the personalized plan with each day's projected target.
/// Reachable by tapping the personalized meter card on Home.
struct MonthlyPlanForecastView: View {
    let plan: ScreenTimeReductionPlan
    @Environment(\.dismiss) private var dismiss

    private let daysToShow = 30
    private let perDayDecrement = 10
    private let floorMinutes = 30
    private let learningModeDailyMinutes = 120
    private let learningModeDuration = 5

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    summaryCard
                    timelineCard
                }
                .padding(20)
            }
            .background(MivoColors.background.ignoresSafeArea())
            .navigationTitle("Next 30 days")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Where the plan is heading")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(MivoColors.textPrimary)
            Text(summaryText)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(MivoColors.textSecondary)
                .lineSpacing(3)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MivoColors.white.opacity(0.62))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(MivoColors.white.opacity(0.58), lineWidth: 1))
    }

    private var timelineCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Daily target")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(MivoColors.textMuted)
                    .textCase(.uppercase)
                Spacer()
                Text("Minutes/day")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(MivoColors.textMuted)
                    .textCase(.uppercase)
            }

            VStack(spacing: 6) {
                ForEach(forecast, id: \.dayNumber) { entry in
                    forecastRow(entry)
                }
            }
        }
        .padding(16)
        .background(MivoColors.white.opacity(0.62))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(MivoColors.white.opacity(0.58), lineWidth: 1))
    }

    private func forecastRow(_ entry: ForecastEntry) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.dateLabel)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(MivoColors.textPrimary)
                Text(entry.phaseLabel)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(entry.isLearningMode ? MivoColors.blue : MivoColors.accent)
            }
            Spacer()
            Text(entry.formattedMinutes)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundColor(MivoColors.textPrimary)
                .monospacedDigit()
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(entry.isToday ? MivoColors.accent.opacity(0.12) : MivoColors.surface.opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var summaryText: String {
        if plan.collecting {
            let remaining = max(0, learningModeDuration - plan.daysCollected)
            if remaining > 0 {
                return "You have \(remaining) lenient day\(remaining == 1 ? "" : "s") left at a 2-hour daily cap. After that, your plan starts at your past-3-day average and trims by 10 min per day until it hits a \(floorMinutes)-min floor."
            }
            return "Personalized plan starts tomorrow. It begins at your past-3-day average of \(plan.baselineMinutes) min and trims by 10 min per day until it hits a \(floorMinutes)-min floor."
        }
        let projectedFloorDay = max(plan.dayIndex, plan.dayIndex + (plan.targetMinutes - floorMinutes) / perDayDecrement)
        return "Today's target is \(plan.targetMinutes) min. The plan keeps trimming 10 min per day from your \(plan.baselineMinutes)-min baseline until it hits the \(floorMinutes)-min floor (around plan day \(projectedFloorDay))."
    }

    private struct ForecastEntry {
        let dayNumber: Int
        let date: Date
        let minutes: Int
        let isLearningMode: Bool
        let isToday: Bool

        var dateLabel: String {
            let formatter = DateFormatter()
            formatter.dateFormat = "EEE, MMM d"
            return formatter.string(from: date)
        }

        var phaseLabel: String {
            isLearningMode ? "Lenient mode" : "Plan day \(dayNumber)"
        }

        var formattedMinutes: String {
            let hours = minutes / 60
            let mins = minutes % 60
            return hours > 0 ? "\(hours)h \(mins)m" : "\(mins)m"
        }
    }

    private var forecast: [ForecastEntry] {
        let calendar = Calendar.current
        let today = Date()
        let collectingDays = plan.collecting ? max(0, plan.daysNeeded - plan.daysCollected) : 0
        let startingDayIndex = plan.collecting ? 1 : plan.dayIndex
        let pastAverage = plan.baselineMinutes
        var entries: [ForecastEntry] = []
        for offset in 0..<daysToShow {
            guard let date = calendar.date(byAdding: .day, value: offset, to: today) else { continue }
            let isToday = offset == 0
            if offset < collectingDays {
                entries.append(ForecastEntry(
                    dayNumber: offset + 1,
                    date: date,
                    minutes: learningModeDailyMinutes,
                    isLearningMode: true,
                    isToday: isToday
                ))
                continue
            }
            let planDay = startingDayIndex + (offset - collectingDays)
            let minutes = max(floorMinutes, pastAverage - (planDay - 1) * perDayDecrement)
            entries.append(ForecastEntry(
                dayNumber: planDay,
                date: date,
                minutes: minutes,
                isLearningMode: false,
                isToday: isToday
            ))
        }
        return entries
    }
}
