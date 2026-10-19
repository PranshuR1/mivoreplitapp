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

/// §5 Experiments sheet. Presented at a 64pt top offset by its caller (Home's
/// `.sheet` in this codebase, matching `.presentationDetents`/top-corner
/// radius from the handoff).
struct ExperimentHubView: View {
    @EnvironmentObject var appVM: AppViewModel
    @ObservedObject private var expansion = ProductExpansionStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var selectedExperiment: WeeklyExperiment?
    @State private var startError: String?
    @State private var isRefreshing = false

    var body: some View {
        ZStack {
            MivoColors.background.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    header

                    if let experiment = appVM.currentWeeklyExperiment, experiment.status == .active {
                        runningBlock(experiment)
                            .padding(.top, 22)
                    }

                    availableSection
                        .padding(.top, 26)

                    if !completedHistory.isEmpty {
                        completedSection
                            .padding(.top, 26)
                    }
                }
                .padding(.horizontal, MivoMetrics.screenPadding)
                .padding(.top, 22)
                .padding(.bottom, 40)
            }
            .refreshable { await refreshExperiments() }
        }
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

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("Experiments")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(MivoColors.ink)
                Spacer()
                Button("Done") { dismiss() }
                    .font(.system(size: 13.5, weight: .bold))
                    .foregroundColor(MivoColors.deep)
            }
            Text("One rule, seven days. Keep what works, drop what doesn't.")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(MivoColors.inkBody)
                .padding(.top, 6)

            if appVM.currentWeeklyExperiment?.status == .proposed || appVM.currentWeeklyExperiment?.status == .completed {
                proposedOrCompletedBanner
                    .padding(.top, 16)
            }
        }
    }

    @ViewBuilder
    private var proposedOrCompletedBanner: some View {
        if let experiment = appVM.currentWeeklyExperiment {
            Button {
                selectedExperiment = experiment
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(experiment.status == .proposed ? "Ready for your approval" : "Result ready")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(MivoColors.deep)
                        Text(experiment.title)
                            .font(.system(size: 14.5, weight: .semibold))
                            .foregroundColor(MivoColors.ink)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(MivoColors.inkMuted)
                }
                .padding(16)
                .background(MivoColors.surfaceV2)
                .clipShape(RoundedRectangle(cornerRadius: MivoMetrics.radius))
            }
            .buttonStyle(MivoPressStyle())
        }
    }

    /// The only filled surface on the screen, per the handoff.
    private func runningBlock(_ experiment: WeeklyExperiment) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("RUNNING · DAY \(experiment.dayNumber) OF 7")
                .font(.system(size: 10, weight: .bold))
                .tracking(Font.mivoTracking(0.10, at: 10))
                .foregroundColor(Color(hex: "#96551A"))

            Text(experiment.title)
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(MivoColors.ink)

            Text(runningSubline(experiment))
                .font(.system(size: 12.5, weight: .medium))
                .foregroundColor(MivoColors.inkBody)

            MivoSegmentBar(completed: experiment.dayNumber)
                .padding(.top, 4)

            Text("Kept \(keptDays(for: experiment)) of \(experiment.dayNumber) days so far")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(MivoColors.kept)

            Button {
                selectedExperiment = experiment
            } label: {
                HStack {
                    Text("Track experiment")
                    Spacer()
                    Image(systemName: "arrow.right")
                }
                .font(.system(size: 13.5, weight: .bold))
                .foregroundColor(MivoColors.ink)
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .padding(20)
        .background(MivoColors.surfaceV2)
        .clipShape(RoundedRectangle(cornerRadius: MivoMetrics.radius))
    }

    private var availableSection: some View {
        let templates = expansion.experimentTemplates(using: appVM)
        return VStack(alignment: .leading, spacing: 0) {
            MivoEyebrow(text: "Available")
                .padding(.bottom, 4)

            if !appVM.canStartWeeklyExperiment {
                Text("Finish reviewing the current experiment before starting another.")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundColor(MivoColors.inkMuted)
                    .padding(.vertical, 10)
            }

            VStack(spacing: 0) {
                ForEach(Array(templates.enumerated()), id: \.element.id) { index, template in
                    availableRow(template)
                    if index < templates.count - 1 {
                        MivoHairline(soft: true)
                    }
                }
            }
        }
    }

    private func availableRow(_ template: ExperimentTemplate) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(template.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(MivoColors.ink)
                Text(template.detail)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundColor(MivoColors.inkMuted)
            }
            Spacer(minLength: 8)
            Button("Start") { begin(template) }
                .font(.system(size: 12.5, weight: .bold))
                .foregroundColor(appVM.canStartWeeklyExperiment ? MivoColors.ink : MivoColors.inkMuted)
                .padding(.vertical, 8)
                .padding(.horizontal, 13)
                .overlay(
                    RoundedRectangle(cornerRadius: MivoMetrics.radius)
                        .strokeBorder(MivoColors.ink.opacity(0.20), lineWidth: 1)
                )
                .disabled(!appVM.canStartWeeklyExperiment)
        }
        .padding(.vertical, 17)
    }

    private var completedHistory: [WeeklyExperiment] {
        appVM.sortedWeeklyExperiments.filter { $0.status == .completed }
    }

    private var completedSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            MivoEyebrow(text: "Completed")
                .padding(.bottom, 4)

            VStack(spacing: 0) {
                ForEach(Array(completedHistory.enumerated()), id: \.element.id) { index, experiment in
                    Button { selectedExperiment = experiment } label: {
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(experiment.title)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(MivoColors.ink)
                                Text("\(dateText(experiment.startsAt ?? experiment.createdAt))–\(dateText(experiment.updatedAt))")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(MivoColors.inkMuted)
                            }
                            Spacer(minLength: 8)
                            MivoOutcomeBadge(outcome: experiment.outcome == .helped ? .kept : .retry)
                        }
                        .padding(.vertical, 16)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(MivoPressStyle())
                    if index < completedHistory.count - 1 {
                        MivoHairline(soft: true)
                    }
                }
            }
        }
    }

    private func runningSubline(_ experiment: WeeklyExperiment) -> String {
        switch experiment.type {
        case .protectedWindow:
            return "Windows open at \(hourText(experiment.rule.endHour ?? 22))."
        case .reduceExtensions:
            return "The original session limit stays fixed."
        case .strongerFriction:
            return "Repeated openings add a trigger check."
        }
    }

    /// Per-day "kept" for the running block. There is no stored daily kept
    /// flag, so this reads the same signal each experiment type already
    /// enforces: a protected window is kept on a day with no session inside
    /// it; reduce-extensions is kept on a day with no extension; stronger
    /// friction is kept on a day where every attempt walked away.
    private func keptDays(for experiment: WeeklyExperiment) -> Int {
        guard let startsAt = experiment.startsAt,
              let start = WeeklyExperiment.experimentDate(from: startsAt) else { return experiment.dayNumber }
        let calendar = Calendar.current
        let dayFormatter = MivoDay.formatter
        let attemptFormatter = ISO8601DateFormatter()

        var kept = 0
        for offset in 0..<experiment.dayNumber {
            guard let day = calendar.date(byAdding: .day, value: offset, to: start) else { continue }
            let sessionsThatDay = appVM.sessions.filter { dayFormatter.date(from: $0.date).map { calendar.isDate($0, inSameDayAs: day) } ?? false }

            let dayKept: Bool
            switch experiment.type {
            case .protectedWindow:
                let startHour = experiment.rule.startHour ?? 21
                let endHour = experiment.rule.endHour ?? 22
                dayKept = !sessionsThatDay.contains { session in
                    guard let started = attemptFormatter.date(from: session.startTime) else { return false }
                    let hour = calendar.component(.hour, from: started)
                    return startHour <= endHour ? (hour >= startHour && hour < endHour) : (hour >= startHour || hour < endHour)
                }
            case .reduceExtensions:
                dayKept = !sessionsThatDay.contains { $0.extendedOnce }
            case .strongerFriction:
                let attemptsThatDay = appVM.interventionAttempts.filter {
                    attemptFormatter.date(from: $0.occurredAt).map { calendar.isDate($0, inSameDayAs: day) } ?? false
                }
                dayKept = attemptsThatDay.allSatisfy { $0.continued != true } || attemptsThatDay.count <= 1
            }
            if dayKept { kept += 1 }
        }
        return kept
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
    @State private var showingDeleteAccount = false
    @State private var exportPayload: MivoDataExportPayload?
    @State private var exportError: String?

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
                    Button("Export my Mivo data") { Task { await exportData() } }
                    Button("Delete my account", role: .destructive) { showingDeleteAccount = true }
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
        .sheet(isPresented: $showingDeleteAccount) {
            MivoDeleteAccountView().environmentObject(appVM)
        }
        .sheet(item: $exportPayload) { payload in
            MivoActivitySheet(items: [payload.url])
        }
        .alert("Export failed", isPresented: Binding(get: { exportError != nil }, set: { if !$0 { exportError = nil } })) {
            Button("OK") { exportError = nil }
        } message: { Text(exportError ?? "") }
    }

    private func exportData() async {
        do {
            exportPayload = try await MivoDataExport.write(appVM: appVM)
        } catch {
            exportError = error.localizedDescription
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

// MARK: - Account data export

struct MivoDataExportPayload: Identifiable {
    let id = UUID()
    let url: URL
}

enum MivoDataExport {
    /// Serializes the signed-in user's Mivo data and writes it to a temporary
    /// JSON file that can be handed to a share sheet.
    @MainActor
    static func write(appVM: AppViewModel) async throws -> MivoDataExportPayload {
        let json = await appVM.exportDataAsync()
        let stamp = ISO8601DateFormatter.exportStamp.string(from: Date())
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Mivo-Data-Export-\(stamp).json")
        try Data(json.utf8).write(to: url, options: .atomic)
        return MivoDataExportPayload(url: url)
    }
}

private extension ISO8601DateFormatter {
    static let exportStamp: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withYear, .withMonth, .withDay]
        return formatter
    }()
}

struct MivoActivitySheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Account deletion

struct MivoDeleteAccountView: View {
    @EnvironmentObject var appVM: AppViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var password = ""
    @State private var acknowledged = false
    @State private var isDeleting = false
    @State private var errorMessage: String?

    private let confirmationPhrase = "DELETE"
    @State private var typedConfirmation = ""

    private var canDelete: Bool {
        acknowledged
            && !password.isEmpty
            && typedConfirmation.trimmingCharacters(in: .whitespaces).uppercased() == confirmationPhrase
            && !isDeleting
    }

    var body: some View {
        NavigationStack {
            ZStack {
                MivoColors.background.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        header
                        deletedList
                        keptList
                        confirmationFields
                        if let errorMessage {
                            Text(errorMessage)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.red)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        deleteButton
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Delete account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.disabled(isDeleting)
                }
            }
            .interactiveDismissDisabled(isDeleting)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            statusIcon("exclamationmark.triangle")
            Text("This permanently deletes your Mivo account.")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(MivoColors.textPrimary)
            Text("This cannot be undone. Your account and its data are removed immediately — there is no recovery period and no way to restore it later.")
                .font(.system(size: 14))
                .foregroundColor(MivoColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var deletedList: some View {
        compactPanel {
            Text("Deleted permanently")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(MivoColors.textPrimary)
            bullet("Your sign-in and \(appVM.user?.email ?? "your email address")")
            bullet("All \(appVM.sessions.count) scroll sessions and \(appVM.truthChecks.count) truth checks")
            bullet("Weekly experiments, reports, and your screen-time plan")
            bullet("Accountability partner connections and shared summaries")
            bullet("Everything Mivo stored on this device, including Screen Time selections")
        }
    }

    private var keptList: some View {
        compactPanel {
            Text("Kept")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(MivoColors.textPrimary)
            bullet("An anonymized record that a deletion happened, which Mivo is required to retain for audit purposes. It no longer identifies you.")
            Text("Want a copy first? Cancel and use “Export my Mivo data” before deleting.")
                .font(.system(size: 12))
                .foregroundColor(MivoColors.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var confirmationFields: some View {
        VStack(alignment: .leading, spacing: 14) {
            Toggle(isOn: $acknowledged) {
                Text("I understand my account and data will be permanently deleted.")
                    .font(.system(size: 13))
                    .foregroundColor(MivoColors.textSecondary)
            }
            .disabled(isDeleting)

            VStack(alignment: .leading, spacing: 6) {
                Text("Confirm your password")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(MivoColors.textPrimary)
                SecureField("Password", text: $password)
                    .textContentType(.password)
                    .autocorrectionDisabled()
                    .textFieldStyle(.roundedBorder)
                    .disabled(isDeleting)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Type \(confirmationPhrase) to confirm")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(MivoColors.textPrimary)
                TextField(confirmationPhrase, text: $typedConfirmation)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.characters)
                    .textFieldStyle(.roundedBorder)
                    .disabled(isDeleting)
            }
        }
    }

    private var deleteButton: some View {
        Button {
            Task { await performDelete() }
        } label: {
            HStack(spacing: 8) {
                if isDeleting { ProgressView().tint(.white) }
                Text(isDeleting ? "Deleting…" : "Delete my account permanently")
                    .font(.system(size: 15, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(canDelete ? Color.red : Color.red.opacity(0.35))
            .foregroundColor(.white)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .disabled(!canDelete)
    }

    private func performDelete() async {
        isDeleting = true
        errorMessage = nil
        do {
            try await appVM.deleteAccount(password: password)
            // deleteAccount() signs the user out, which returns the app to the
            // login screen behind this sheet.
            dismiss()
        } catch {
            // Never close on failure — the account still exists.
            errorMessage = error.localizedDescription
            isDeleting = false
        }
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•").foregroundColor(MivoColors.accent)
            Text(text)
                .font(.system(size: 13))
                .foregroundColor(MivoColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}
