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
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(MivoColors.heroBg)
                .frame(minHeight: 246)

            VStack(alignment: .leading, spacing: 22) {
                HStack {
                    Label(hasScreenTimeAccess ? "Live Screen Time" : "Awaiting access", systemImage: "waveform.path.ecg")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(MivoColors.heroText.opacity(0.72))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(MivoColors.heroText.opacity(0.12))
                        .clipShape(Capsule())

                    Spacer()

                    Text(statusLabel)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(MivoColors.heroText.opacity(0.75))
                }

                if hasScreenTimeAccess, #available(iOS 16.0, *) {
                    MivoScreenTimeUsageLiveReport()
                        .frame(height: 156)
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .strokeBorder(MivoColors.heroText.opacity(0.12), lineWidth: 1)
                        )
                } else {
                    connectScreenTimeBlock
                }

                HStack(spacing: 10) {
                    miniHeroPill(icon: "lock.open.fill", title: "\(appVM.todaysSessions.count)", subtitle: appVM.todaysSessions.count == 1 ? "unlock" : "unlocks")
                    miniHeroPill(icon: trendIcon, title: trendText, subtitle: "week")
                }
            }
            .padding(22)
        }
        .shadow(color: Color.black.opacity(0.12), radius: 20, y: 10)
    }

    private var connectScreenTimeBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Connect Screen Time")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundColor(MivoColors.heroText)
                .lineLimit(2)
                .minimumScaleFactor(0.82)
            Text("Mivo will show Apple’s real Screen Time report here. No placeholder totals.")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(MivoColors.heroText.opacity(0.68))
                .lineSpacing(3)
        }
    }

    private func miniHeroPill(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(MivoColors.heroText)
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(MivoColors.heroText)
                Text(subtitle)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(MivoColors.heroText.opacity(0.56))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(MivoColors.heroText.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
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

        return VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: plan.collecting ? "waveform.path.ecg" : "sparkles")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(MivoColors.heroText)
                    .frame(width: 42, height: 42)
                    .background(plan.collecting ? MivoColors.blue : MivoColors.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(plan.collecting ? "Learning mode" : "AI screen plan")
                        .font(.system(size: 19, weight: .bold, design: .rounded))
                        .foregroundColor(MivoColors.textPrimary)
                    Text(plan.collecting ? "Day \(plan.daysCollected) of \(plan.daysNeeded)" : "Day \(plan.dayIndex) - \(plan.strictnessPercent)% stricter")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(plan.collecting ? MivoColors.blue : MivoColors.accent)
                }

                Spacer()
            }

            Text(plan.summary)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(MivoColors.textSecondary)
                .lineSpacing(4)

            HStack(spacing: 10) {
                planMetric(title: "Baseline", value: formatDuration(plan.baselineMinutes))
                planMetric(title: plan.collecting ? "Allowed" : "Target", value: plan.collecting ? "Open" : formatDuration(plan.targetMinutes))
                planMetric(title: "Windows", value: "\(plan.windows.count)")
            }

            if !plan.collecting {
                VStack(spacing: 10) {
                    ForEach(plan.windows) { window in
                        scrollWindowRow(window)
                    }
                }
            } else {
                learningProgress(plan)
            }

            Text(plan.decisionReason)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(MivoColors.textMuted)
                .lineSpacing(3)
        }
        .padding(18)
        .background(MivoColors.white.opacity(0.62))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(MivoColors.white.opacity(0.58), lineWidth: 1))
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

            Text("No reduction target yet. Mivo is letting your normal pattern show first, then it will create two daily scrolling sessions.")
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
