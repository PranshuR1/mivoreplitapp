import SwiftUI
import UserNotifications

struct TodayGuideHomeCard: View {
    let guide: TodayGuide
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: guide.icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(MivoColors.accent)
                    .frame(width: 42, height: 42)
                    .background(MivoColors.accent.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(guide.eyebrow)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(MivoColors.accent)
                    Text(guide.title)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(MivoColors.textPrimary)
                }
                Spacer()
            }
            Text(guide.detail)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(MivoColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if let progress = guide.progress {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(MivoColors.border.opacity(0.55))
                        Capsule().fill(MivoColors.accent).frame(width: proxy.size.width * max(0, min(1, progress)))
                    }
                }
                .frame(height: 7)
            }
            Button(action: action) {
                HStack {
                    Text(guide.actionTitle)
                    Spacer()
                    Image(systemName: "arrow.right")
                }
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(MivoColors.accent)
            }
            .buttonStyle(.plain)
        }
        .mivoSectionSurface()
    }
}

struct RecoveryModeView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var expansion: ProductExpansionStore
    let plan: RecoveryPlan

    var body: some View {
        NavigationStack {
            ZStack {
                MivoColors.background.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        statusIcon("arrow.counterclockwise.circle.fill")
                        Text("Yesterday was information, not a verdict.")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundColor(MivoColors.textPrimary)
                        Text(plan.reason)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(MivoColors.textSecondary)
                        compactPanel {
                            recoveryRow("Outside planned windows", value: "\(plan.outsideWindowMinutes) min")
                            Divider().overlay(MivoColors.border)
                            recoveryRow("Extended sessions not worth it", value: "\(plan.notWorthwhileExtensionCount)")
                        }
                        compactPanel {
                            Label("A simpler day", systemImage: "sparkles")
                                .font(.system(size: 17, weight: .bold))
                                .foregroundColor(MivoColors.textPrimary)
                            Text("Mivo keeps your locked schedule and protections. It quiets extra prompts and gives you one clear next action at a time.")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(MivoColors.textSecondary)
                        }
                        MivoButton(label: "Use a simpler day", action: {
                            expansion.acceptRecovery(plan); dismiss()
                        }, icon: "checkmark")
                        Button("Keep my normal plan") {
                            expansion.declineRecovery(plan); dismiss()
                        }
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(MivoColors.textSecondary)
                        .frame(maxWidth: .infinity)
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Recovery")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Close") { dismiss() } } }
        }
    }

    private func recoveryRow(_ title: String, value: String) -> some View {
        HStack { Text(title); Spacer(); Text(value).fontWeight(.bold) }
            .font(.system(size: 14)).foregroundColor(MivoColors.textPrimary)
    }
}

struct MonthlyEffectReportView: View {
    @EnvironmentObject var appVM: AppViewModel
    @ObservedObject private var expansion = ProductExpansionStore.shared

    var body: some View {
        ZStack {
            MivoColors.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let report = expansion.monthlyReports.first {
                        effectHeader(report)
                        if report.hasEnoughData {
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                                metric("Daily average", "\(report.averageDailyMinutes)m", "clock")
                                metric("On schedule", percent(report.scheduleAdherence), "calendar.badge.checkmark")
                                metric("Extensions", percent(report.extensionRate), "plus.circle")
                                metric("Truth gap", "\(Int(report.averageTruthError.rounded()))m", "eye")
                                metric("Worthwhile", percent(report.worthwhileRate), "hand.thumbsup")
                                metric("Experiments", "\(report.completedExperiments)", "flask")
                            }
                            compactPanel {
                                Text("Estimated change")
                                    .font(.system(size: 12, weight: .bold)).foregroundColor(MivoColors.accent)
                                Text(report.estimatedReducedMinutes > 0
                                     ? "About \(report.estimatedReducedMinutes) fewer unplanned minutes than the comparison period."
                                     : "No clear reduction yet. Mivo will keep comparing complete periods.")
                                    .font(.system(size: 18, weight: .bold)).foregroundColor(MivoColors.textPrimary)
                                Text("This is an estimate based on recorded sessions and planned windows, not a guarantee of time saved.")
                                    .font(.system(size: 12, weight: .medium)).foregroundColor(MivoColors.textMuted)
                            }
                        } else {
                            ContentUnavailableView("More pattern needed", systemImage: "chart.line.uptrend.xyaxis",
                                                   description: Text("Mivo needs seven active days and three completed sessions for this report."))
                        }
                    } else {
                        ContentUnavailableView("Report preparing", systemImage: "calendar", description: Text("Open Mivo after your next completed session."))
                    }
                }
                .padding(20)
            }
        }
        .navigationTitle("Mivo Effect")
        .task { await expansion.prepare(for: appVM) }
    }

    private func effectHeader(_ report: MonthlyEffectReport) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("MONTHLY EFFECT").font(.system(size: 12, weight: .bold)).foregroundColor(MivoColors.accent)
            Text("What changed this month")
                .font(.system(size: 27, weight: .bold)).foregroundColor(MivoColors.textPrimary)
            Text("Based on \(report.validDays) active days and \(report.sessionCount) completed sessions.")
                .font(.system(size: 14, weight: .medium)).foregroundColor(MivoColors.textSecondary)
        }
    }

    private func metric(_ title: String, _ value: String, _ icon: String) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Image(systemName: icon).foregroundColor(MivoColors.accent)
            Text(value).font(.system(size: 23, weight: .bold)).foregroundColor(MivoColors.textPrimary)
            Text(title).font(.system(size: 12, weight: .semibold)).foregroundColor(MivoColors.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(15)
        .background(MivoColors.surfaceRaised.opacity(0.72)).clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func percent(_ value: Double) -> String { "\(Int((value * 100).rounded()))%" }
}

struct ExperimentHubView: View {
    @EnvironmentObject var appVM: AppViewModel
    @ObservedObject private var expansion = ProductExpansionStore.shared
    @State private var selectedExperiment: WeeklyExperiment?
    @State private var startError: String?
    @State private var isRefreshing = false

    var body: some View {
        ZStack {
            MivoColors.background.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 16) {
                    hubHeader
                    summaryRow
                    currentSection
                    availableSection
                    historySection
                }
                .padding(.horizontal, 18)
                .padding(.top, 12)
                .padding(.bottom, 28)
            }
            .refreshable { await refreshExperiments() }
        }
        .navigationTitle("Experiments")
        .navigationBarTitleDisplayMode(.inline)
        .task { await refreshExperiments() }
        .sheet(item: $selectedExperiment) { experiment in
            WeeklyExperimentSheet(experiment: experiment)
                .environmentObject(appVM)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .alert("Experiment unavailable", isPresented: Binding(
            get: { startError != nil },
            set: { if !$0 { startError = nil } }
        )) {
            Button("OK", role: .cancel) { startError = nil }
        } message: {
            Text(startError ?? "Please try again.")
        }
    }

    private var hubHeader: some View {
        VStack(alignment: .leading, spacing: 7) {
            Label("ONE CHANGE AT A TIME", systemImage: "flask.fill")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(MivoColors.blue)
            Text("Run a seven-day experiment")
                .font(.system(size: 25, weight: .bold, design: .rounded))
                .foregroundColor(MivoColors.textPrimary)
            Text("Choose the rule yourself. Mivo tracks the week against your recent pattern, then shows what changed.")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(MivoColors.textSecondary)
                .lineSpacing(4)
        }
    }

    private var summaryRow: some View {
        HStack(spacing: 8) {
            summaryCell("Current", currentStatus, "calendar.badge.clock")
            summaryCell("Completed", "\(appVM.completedWeeklyExperiments.count)", "checkmark.circle.fill")
            summaryCell("Helped", "\(helpedCount)", "chart.line.uptrend.xyaxis")
        }
    }

    @ViewBuilder private var currentSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Current experiment", icon: "scope")
            if let experiment = appVM.currentWeeklyExperiment {
                compactPanel {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: experimentIcon(experiment.type))
                            .font(.system(size: 17, weight: .bold))
                            .foregroundColor(MivoColors.white)
                            .frame(width: 40, height: 40)
                            .background(MivoColors.blue)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        VStack(alignment: .leading, spacing: 4) {
                            Text(statusText(experiment))
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(MivoColors.blue)
                            Text(experiment.title)
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(MivoColors.textPrimary)
                        }
                        Spacer()
                    }

                    if experiment.status == .active {
                        MivoProgressSegments(completed: experiment.dayNumber, tint: MivoColors.blue)
                        HStack {
                            Text("DAY \(experiment.dayNumber)")
                            Spacer()
                            Text("\(Int((experiment.progress() * 100).rounded()))% COMPLETE")
                        }
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(MivoColors.blue)
                        HStack(spacing: 8) {
                            trackingCell("Rule", ruleSummary(experiment), "checkmark.shield")
                            trackingCell("Tracking", metricName(experiment), "chart.bar.xaxis")
                        }
                        Label("Baseline: \(metricValue(experiment.baselineMetrics, for: experiment)) from \(experiment.baselineMetrics.comparableSessions) comparable sessions", systemImage: "flag.checkered")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(MivoColors.textSecondary)
                        if let endsAt = experiment.endsAt {
                            Label("Result available \(dateText(endsAt))", systemImage: "calendar")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(MivoColors.textSecondary)
                        }
                    } else {
                        Text(currentDetail(experiment))
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(MivoColors.textSecondary)
                            .lineSpacing(3)
                    }

                    Button {
                        selectedExperiment = experiment
                    } label: {
                        HStack {
                            Text(currentAction(experiment))
                            Spacer()
                            Image(systemName: "arrow.right")
                        }
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(MivoColors.white)
                        .padding(.horizontal, 14)
                        .frame(height: 44)
                        .background(MivoColors.blue)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
            } else {
                statusBanner("No experiment is running. Pick one below when you are ready to test a small change.", icon: "plus.circle")
            }
        }
    }

    private var availableSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Choose an experiment", icon: "square.grid.2x2")
            if !appVM.canStartWeeklyExperiment {
                Text("Finish reviewing the current experiment before starting another.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(MivoColors.textMuted)
            }
            ForEach(expansion.experimentTemplates(using: appVM)) { template in
                experimentTemplateCard(template)
            }
        }
    }

    @ViewBuilder private var historySection: some View {
        let history = appVM.sortedWeeklyExperiments.filter {
            $0.status == .completed || $0.status == .declined
        }
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("History", icon: "clock.arrow.circlepath")
            if history.isEmpty {
                Text("Completed and declined experiments will appear here.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(MivoColors.textMuted)
                    .padding(.vertical, 8)
            } else {
                ForEach(history) { experiment in
                    compactPanel {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: historyIcon(experiment))
                                .foregroundColor(historyColor(experiment))
                                .frame(width: 34, height: 34)
                                .background(historyColor(experiment).opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            VStack(alignment: .leading, spacing: 4) {
                                Text(experiment.title)
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundColor(MivoColors.textPrimary)
                                Text(historyDetail(experiment))
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(MivoColors.textSecondary)
                            }
                            Spacer()
                        }
                        if experiment.status == .completed {
                            HStack(spacing: 8) {
                                Button("View result") { selectedExperiment = experiment }
                                    .font(.system(size: 12, weight: .bold))
                                    .buttonStyle(.bordered)
                                    .tint(MivoColors.blue)
                                Button("Run again") { begin(repeatTemplate(for: experiment)) }
                                    .font(.system(size: 12, weight: .bold))
                                    .buttonStyle(.borderedProminent)
                                    .tint(MivoColors.accent)
                                    .disabled(!appVM.canStartWeeklyExperiment)
                            }
                        }
                    }
                }
            }
        }
    }

    private func experimentTemplateCard(_ template: ExperimentTemplate) -> some View {
        compactPanel {
            HStack(alignment: .top, spacing: 13) {
                Image(systemName: experimentIcon(template.type))
                    .foregroundColor(MivoColors.accent)
                    .frame(width: 36, height: 36)
                    .background(MivoColors.accent.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 5) {
                    Text(template.title)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(MivoColors.textPrimary)
                    Text(template.detail)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(MivoColors.textSecondary)
                        .lineSpacing(3)
                }
            }
            Button {
                begin(template)
            } label: {
                HStack {
                    Text(appVM.canStartWeeklyExperiment ? "Review and start" : "Current experiment first")
                    Spacer()
                    Image(systemName: appVM.canStartWeeklyExperiment ? "arrow.right" : "lock.fill")
                }
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(appVM.canStartWeeklyExperiment ? MivoColors.accent : MivoColors.textMuted)
            }
            .buttonStyle(.plain)
            .disabled(!appVM.canStartWeeklyExperiment)
        }
    }

    private func summaryCell(_ label: String, _ value: String, _ icon: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon).font(.system(size: 12, weight: .bold)).foregroundColor(MivoColors.accent)
            Text(value).font(.system(size: 16, weight: .bold)).foregroundColor(MivoColors.textPrimary).lineLimit(1).minimumScaleFactor(0.72)
            Text(label).font(.system(size: 10, weight: .semibold)).foregroundColor(MivoColors.textMuted)
        }
        .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
        .padding(12)
        .background(MivoColors.surfaceRaised.opacity(0.88))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(MivoColors.border.opacity(0.4), lineWidth: 1))
    }

    private func trackingCell(_ label: String, _ value: String, _ icon: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(label, systemImage: icon)
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(MivoColors.textMuted)
            Text(value)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(MivoColors.textPrimary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
        .padding(10)
        .background(MivoColors.background.opacity(0.75))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func sectionHeader(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.system(size: 14, weight: .bold))
            .foregroundColor(MivoColors.textPrimary)
    }

    private func begin(_ template: ExperimentTemplate) {
        guard let proposal = expansion.startExperiment(template, using: appVM) else {
            startError = expansion.lastError ?? "Mivo could not prepare this experiment."
            return
        }
        selectedExperiment = proposal
    }

    @MainActor private func refreshExperiments() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        await expansion.prepare(for: appVM)
        await appVM.refreshWeeklyExperiments()
        isRefreshing = false
    }

    private func repeatTemplate(for experiment: WeeklyExperiment) -> ExperimentTemplate {
        ExperimentTemplate(
            id: "repeat-\(experiment.id)", type: experiment.type,
            title: experiment.title,
            detail: "Repeat the rule you previously approved for another seven days.",
            rule: experiment.rule, sourceExperimentID: experiment.id
        )
    }

    private func experimentIcon(_ type: WeeklyExperimentType) -> String {
        switch type { case .protectedWindow: return "clock.badge.exclamationmark"; case .reduceExtensions: return "minus.circle"; case .strongerFriction: return "hand.raised.fill" }
    }

    private var helpedCount: Int {
        appVM.completedWeeklyExperiments.filter { $0.outcome == .helped }.count
    }

    private var currentStatus: String {
        guard let experiment = appVM.currentWeeklyExperiment else { return "Ready" }
        switch experiment.status {
        case .active: return "Day \(experiment.dayNumber)"
        case .proposed: return "Review"
        case .completed: return "Result"
        case .declined: return "Ready"
        }
    }

    private func statusText(_ experiment: WeeklyExperiment) -> String {
        switch experiment.status {
        case .active: return "DAY \(experiment.dayNumber) OF 7"
        case .proposed: return "READY FOR YOUR APPROVAL"
        case .completed: return "RESULT READY"
        case .declined: return "DECLINED"
        }
    }

    private func currentAction(_ experiment: WeeklyExperiment) -> String {
        switch experiment.status {
        case .active: return "Track experiment"
        case .proposed: return "Review experiment"
        case .completed: return "Review result"
        case .declined: return "View experiment"
        }
    }

    private func currentDetail(_ experiment: WeeklyExperiment) -> String {
        if experiment.status == .proposed { return experiment.reason }
        switch experiment.outcome {
        case .helped: return "This experiment appears to have helped. Review the comparison and choose whether to keep it."
        case .worsened: return "This rule may not have fit this week. Review the result before choosing what comes next."
        default: return "Mivo did not find a clear change yet. Review the available data and choose what comes next."
        }
    }

    private func ruleSummary(_ experiment: WeeklyExperiment) -> String {
        switch experiment.type {
        case .protectedWindow:
            return "Protect \(hourText(experiment.rule.startHour ?? 21))-\(hourText(experiment.rule.endHour ?? 22))"
        case .reduceExtensions: return "No extensions"
        case .strongerFriction: return "Stronger repeat pause"
        }
    }

    private func metricName(_ experiment: WeeklyExperiment) -> String {
        switch experiment.type {
        case .protectedWindow: return "Outside-window minutes"
        case .reduceExtensions: return "Extension rate"
        case .strongerFriction: return "Stops after a pause"
        }
    }

    private func metricValue(_ metrics: ExperimentMetrics, for experiment: WeeklyExperiment) -> String {
        switch experiment.type {
        case .protectedWindow: return "\(metrics.outsideWindowMinutes) minutes outside windows"
        case .reduceExtensions: return "\(Int((metrics.extensionRate * 100).rounded()))% extension rate"
        case .strongerFriction: return "\(Int((metrics.cancellationRate * 100).rounded()))% stopped after pausing"
        }
    }

    private func historyIcon(_ experiment: WeeklyExperiment) -> String {
        if experiment.status == .declined { return "minus.circle" }
        return experiment.outcome == .helped ? "checkmark.circle.fill" : "chart.bar.fill"
    }

    private func historyColor(_ experiment: WeeklyExperiment) -> Color {
        experiment.outcome == .helped ? MivoColors.timerGreen : MivoColors.accent
    }

    private func historyDetail(_ experiment: WeeklyExperiment) -> String {
        if experiment.status == .declined { return "Declined \(dateText(experiment.updatedAt))" }
        let result: String
        switch experiment.outcome {
        case .helped: result = "Helped"
        case .worsened: result = "Made things worse"
        default: result = "No clear change"
        }
        let decision = experiment.finalDecision.map { " - \($0.rawValue.capitalized)" } ?? " - Decision needed"
        return "\(result)\(decision) - \(dateText(experiment.updatedAt))"
    }

    private func dateText(_ value: String) -> String {
        guard let date = WeeklyExperiment.experimentDate(from: value) else { return "after day 7" }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }

    private func hourText(_ hour: Int) -> String {
        let normalized = ((hour % 24) + 24) % 24
        if normalized == 0 { return "12a" }
        if normalized < 12 { return "\(normalized)a" }
        if normalized == 12 { return "12p" }
        return "\(normalized - 12)p"
    }
}

struct ExperimentLibraryView: View {
    var body: some View {
        ExperimentHubView()
    }
}

struct AppPersonalitiesView: View {
    @EnvironmentObject var appVM: AppViewModel
    @ObservedObject private var expansion = ProductExpansionStore.shared

    var body: some View {
        ZStack {
            MivoColors.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    statusBanner("Each profile stays on this device. Mivo never sends selected-app identities to the server.", icon: "lock.shield")
                    ForEach(expansion.appProfiles) { profile in
                        AppPersonalityEditor(profile: profile) { expansion.updateAppProfile($0) }
                    }
                    if expansion.appProfiles.isEmpty {
                        ContentUnavailableView("No app rules yet", systemImage: "apps.iphone", description: Text("Choose protected apps first, then return here."))
                    }
                }
                .padding(20)
            }
        }
        .navigationTitle("App Personalities")
        .task { await expansion.prepare(for: appVM) }
    }
}

private struct AppPersonalityEditor: View {
    @State var profile: AppFrictionProfile
    let save: (AppFrictionProfile) -> Void

    var body: some View {
        compactPanel {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(profile.appName).font(.system(size: 18, weight: .bold)).foregroundColor(MivoColors.textPrimary)
                    Text(profile.userApproved ? "Approved on this device" : "Review before applying")
                        .font(.system(size: 12, weight: .medium)).foregroundColor(MivoColors.textSecondary)
                }
                Spacer()
                Image(systemName: profile.userApproved ? "checkmark.seal.fill" : "circle.dashed")
                    .foregroundColor(MivoColors.accent)
            }
            Picker("Strength", selection: $profile.strength) {
                ForEach(AppFrictionStrength.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            Stepper("Pause: \(profile.pauseSeconds) seconds", value: $profile.pauseSeconds, in: 5...120, step: 5)
            Stepper("Rescue after: \(profile.rescueAfterMinutes) minutes", value: $profile.rescueAfterMinutes, in: 10...60, step: 5)
            Toggle("Ask for intention every time", isOn: $profile.intentionEveryOpening)
            Toggle("Allow session extensions", isOn: $profile.extensionsAllowed)
            Toggle("Stronger after bedtime", isOn: $profile.strongerLateNight)
            Button(profile.userApproved ? "Save changes" : "Approve profile") {
                profile.userApproved = true; save(profile)
            }
            .font(.system(size: 14, weight: .bold)).foregroundColor(MivoColors.accent)
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }
}

struct AccountabilityPartnersView: View {
    @EnvironmentObject var appVM: AppViewModel
    @ObservedObject private var expansion = ProductExpansionStore.shared
    @State private var email = ""
    @State private var sending = false

    var body: some View {
        ZStack {
            MivoColors.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 15) {
                    statusBanner("Partners receive only weekly totals and encouragement. App names, exact times, triggers, and notes stay private.", icon: "person.2.badge.gearshape")
                    compactPanel {
                        Text("Weekly preview").font(.system(size: 18, weight: .bold)).foregroundColor(MivoColors.textPrimary)
                        let summary = expansion.weeklySummary(using: appVM)
                        summaryRow("Planned time", "\(summary.plannedMinutes) min")
                        summaryRow("Reflected days", "\(summary.reflectedDays)")
                        summaryRow("Truth trend", summary.truthAccuracyTrend)
                        summaryRow("Experiment", summary.experimentStatus)
                    }
                    compactPanel {
                        Text("Invite someone you trust").font(.system(size: 18, weight: .bold)).foregroundColor(MivoColors.textPrimary)
                        TextField("Partner email", text: $email)
                            .textInputAutocapitalization(.never).keyboardType(.emailAddress)
                            .padding(12).background(MivoColors.surface).clipShape(RoundedRectangle(cornerRadius: 8))
                        Button {
                            sending = true
                            Task { await expansion.invitePartner(email: email, using: appVM); sending = false; email = "" }
                        } label: {
                            Label(sending ? "Sending..." : "Send secure invitation", systemImage: "paperplane.fill")
                                .font(.system(size: 15, weight: .bold)).frame(maxWidth: .infinity).padding(.vertical, 12)
                                .background(MivoColors.accent).foregroundColor(.white).clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .disabled(email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || sending)
                    }
                    ForEach(expansion.accountabilityConnections) { connection in
                        compactPanel {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(connection.partnerEmailMasked).font(.system(size: 16, weight: .bold)).foregroundColor(MivoColors.textPrimary)
                                    Text(connection.status.rawValue.capitalized).font(.system(size: 12, weight: .medium)).foregroundColor(MivoColors.textSecondary)
                                }
                                Spacer()
                                if connection.status == .active {
                                    Toggle("", isOn: Binding(get: { connection.automaticSharingEnabled }, set: { value in
                                        Task { await expansion.setAutomaticSharing(value, connection: connection) }
                                    })).labelsHidden()
                                }
                            }
                            if connection.status != .revoked {
                                Button("Revoke access", role: .destructive) { Task { await expansion.revoke(connection) } }
                            }
                        }
                    }
                }
                .padding(20)
            }
        }
        .navigationTitle("Accountability")
        .task { await expansion.prepare(for: appVM) }
        .alert("Accountability", isPresented: Binding(get: { expansion.lastError != nil }, set: { if !$0 { expansion.lastError = nil } })) {
            Button("OK") { expansion.lastError = nil }
        } message: { Text(expansion.lastError ?? "") }
    }

    private func summaryRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .top) { Text(title); Spacer(); Text(value).multilineTextAlignment(.trailing).fontWeight(.semibold) }
            .font(.system(size: 13)).foregroundColor(MivoColors.textSecondary)
    }
}

struct MivoPrivacyCenterView: View {
    @EnvironmentObject var appVM: AppViewModel
    @ObservedObject private var expansion = ProductExpansionStore.shared
    @State private var notificationsAuthorized = false
    @State private var diagnosticsEnabled = false

    var body: some View {
        ZStack {
            MivoColors.background.ignoresSafeArea()
            List {
                Section("Stored on this device") {
                    privacyRow("Selected-app identities", "Never uploaded", "iphone.gen3")
                    privacyRow("Screen Time tokens", "Device only", "lock.shield")
                    privacyRow("App personalities", "Device only", "slider.horizontal.3")
                }
                Section("Synced to your account") {
                    privacyRow("Sessions", "\(appVM.sessions.count) records", "clock.arrow.circlepath")
                    privacyRow("Truth checks", "\(appVM.truthChecks.count) records", "eye")
                    privacyRow("Experiments", "\(appVM.weeklyExperiments.count) records", "flask")
                    privacyRow("Partner summaries", "High-level totals only", "person.2")
                }
                Section("Permissions") {
                    privacyRow("Notifications", notificationsAuthorized ? "Allowed" : "Not allowed", "bell")
                    privacyRow("Screen Time", FamilyControlsManager.shared.cachedAuthorizationStatus() == true ? "Allowed" : "Not allowed", "hourglass")
                    Toggle("Share anonymous diagnostics", isOn: $diagnosticsEnabled)
                        .disabled(!expansion.isEnabled(.diagnostics))
                        .onChange(of: diagnosticsEnabled) { _, value in
                            if let email = appVM.user?.email { StorageService.save(value, forKey: .diagnosticsEnabled, email: email) }
                            MivoDiagnosticsService.shared.setEnabled(value && expansion.isEnabled(.diagnostics))
                        }
                    if !expansion.isEnabled(.diagnostics) {
                        Text("Diagnostics are currently paused by Mivo.")
                            .font(.caption).foregroundColor(MivoColors.textMuted)
                    }
                }
                Section("Account controls") {
                    NavigationLink("Accountability connections") { AccountabilityPartnersView().environmentObject(appVM) }
                    Button("Export my Mivo data") { Task { _ = await appVM.exportDataAsync() } }
                    Button("Request account deletion", role: .destructive) {
                        Task { try? await ProductExpansionService.ingestPrivacyRequest(type: "delete") }
                    }
                }
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Privacy Center")
        .task {
            await expansion.prepare(for: appVM)
            if let email = appVM.user?.email {
                diagnosticsEnabled = StorageService.load(Bool.self, forKey: .diagnosticsEnabled, email: email) ?? false
                if !expansion.isEnabled(.diagnostics) { diagnosticsEnabled = false }
            }
            notificationsAuthorized = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus == .authorized
        }
    }

    private func privacyRow(_ title: String, _ value: String, _ icon: String) -> some View {
        Label { HStack { Text(title); Spacer(); Text(value).foregroundColor(MivoColors.textSecondary) } } icon: {
            Image(systemName: icon).foregroundColor(MivoColors.accent)
        }
    }
}

private func compactPanel<Content: View>(@ViewBuilder content: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: 12) { content() }
        .padding(16).background(MivoColors.surfaceRaised.opacity(0.9))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(MivoColors.border.opacity(0.4), lineWidth: 1))
}

private func statusBanner(_ text: String, icon: String) -> some View {
    HStack(alignment: .top, spacing: 12) {
        Image(systemName: icon).foregroundColor(MivoColors.accent)
        Text(text).font(.system(size: 13, weight: .medium)).foregroundColor(MivoColors.textSecondary)
    }
    .padding(14).background(MivoColors.accent.opacity(0.08)).clipShape(RoundedRectangle(cornerRadius: 8))
}

private func statusIcon(_ icon: String) -> some View {
    Image(systemName: icon).font(.system(size: 32, weight: .semibold)).foregroundColor(MivoColors.accent)
        .frame(width: 64, height: 64).background(MivoColors.accent.opacity(0.1)).clipShape(RoundedRectangle(cornerRadius: 8))
}
