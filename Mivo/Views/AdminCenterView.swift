import SwiftUI
import Charts

private enum AdminCenterTab: String, CaseIterable, Identifiable {
    case overview = "Overview"
    case reliability = "Reliability"
    case releases = "Releases"
    case quality = "Data Quality"
    case analytics = "Analytics"
    case approvals = "Approvals"
    case users = "Users"
    case consent = "Consent"
    case security = "Security"

    var id: String { rawValue }
    var icon: String {
        switch self {
        case .overview: return "square.grid.2x2.fill"
        case .reliability: return "waveform.path.ecg"
        case .releases: return "shippingbox.fill"
        case .quality: return "checkmark.seal.fill"
        case .analytics: return "chart.xyaxis.line"
        case .approvals: return "tray.full.fill"
        case .users: return "person.3.fill"
        case .consent: return "person.crop.circle.badge.checkmark"
        case .security: return "lock.shield.fill"
        }
    }
}

struct MivoAdminCenterView: View {
    @EnvironmentObject var appVM: AppViewModel
    @ObservedObject private var expansion = ProductExpansionStore.shared
    @State private var selectedTab: AdminCenterTab = .overview
    @State private var searchText = ""

    var body: some View {
        ZStack {
            MivoColors.background.ignoresSafeArea()
            VStack(spacing: 0) {
                adminHeader
                tabStrip
                Divider().overlay(MivoColors.border)
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        if expansion.isRefreshingAdmin { ProgressView().frame(maxWidth: .infinity).padding() }
                        selectedContent
                    }
                    .padding(16)
                    .padding(.bottom, 36)
                }
                .refreshable { await expansion.refreshAdmin() }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await expansion.prepare(for: appVM)
            await expansion.refreshAdmin()
        }
        .alert("Admin Center", isPresented: Binding(get: { expansion.lastError != nil }, set: { if !$0 { expansion.lastError = nil } })) {
            Button("Retry") { Task { await expansion.refreshAdmin() } }
            Button("Close", role: .cancel) { expansion.lastError = nil }
        } message: { Text(expansion.lastError ?? "") }
    }

    private var adminHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Mivo Super Admin").font(.system(size: 24, weight: .bold)).foregroundColor(MivoColors.textPrimary)
                    Text("Full access · includes every Admin tool").font(.system(size: 12, weight: .semibold)).foregroundColor(MivoColors.accent)
                }
                Spacer()
                Button { Task { await expansion.refreshAdmin() } } label: {
                    Image(systemName: "arrow.clockwise").frame(width: 40, height: 40)
                        .background(MivoColors.surfaceRaised.opacity(0.75)).clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
            TextField("Search this section", text: $searchText)
                .textInputAutocapitalization(.never)
                .padding(.horizontal, 12).frame(height: 42)
                .background(MivoColors.surfaceRaised.opacity(0.75)).clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(MivoColors.border, lineWidth: 1))
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }

    private var tabStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(AdminCenterTab.allCases) { tab in
                    Button { selectedTab = tab; searchText = "" } label: {
                        Label(tab.rawValue, systemImage: tab.icon)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(selectedTab == tab ? .white : MivoColors.textSecondary)
                            .padding(.horizontal, 12).frame(height: 36)
                            .background(selectedTab == tab ? MivoColors.accent : MivoColors.white.opacity(0.7))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16).padding(.bottom, 10)
        }
    }

    @ViewBuilder private var selectedContent: some View {
        switch selectedTab {
        case .overview: overview
        case .reliability: reliability
        case .releases: releases
        case .quality: dataQuality
        case .analytics: analytics
        case .approvals: approvals
        case .users: users
        case .consent: consent
        case .security: security
        }
    }

    private var overview: some View {
        VStack(alignment: .leading, spacing: 14) {
            AdminSectionTitle("System status", icon: "bolt.heart.fill")
            HStack(spacing: 10) {
                AdminMiniStat(title: "Critical", value: "\(expansion.adminSnapshot.reliability.filter { $0.severity == .critical }.count)", color: .red)
                AdminMiniStat(title: "Open quality", value: "\(expansion.adminSnapshot.dataQualityIssues.filter { $0.status == "open" }.count)", color: MivoColors.accent)
                AdminMiniStat(title: "Approvals", value: "\(expansion.adminSnapshot.approvals.filter { $0.status == "pending" }.count)", color: MivoColors.blue)
            }
            AdminSectionTitle("Feature flags", icon: "switch.2")
            if expansion.featureFlags.isEmpty {
                AdminEmptyState(title: "Flags unavailable", detail: "Pull to refresh after applying the latest Supabase migration.")
            } else {
                ForEach(filtered(expansion.featureFlags, text: { $0.key })) { flag in
                    FeatureFlagRow(flag: flag, save: { updated in
                        Task { await expansion.updateFlag(updated) }
                    })
                }
            }
        }
    }

    private var reliability: some View {
        VStack(alignment: .leading, spacing: 12) {
            AdminSectionTitle("Reliability Center", icon: "waveform.path.ecg")
            if filtered(expansion.adminSnapshot.reliability, text: { $0.title }).isEmpty {
                AdminEmptyState(title: "No reliability events", detail: "MetricKit and operational events will appear here after devices report them.")
            }
            ForEach(filtered(expansion.adminSnapshot.reliability, text: { $0.title })) { metric in
                adminPanel {
                    HStack {
                        severityDot(metric.severity)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(metric.title).font(.system(size: 16, weight: .bold))
                            Text(metric.updatedAt).font(.system(size: 11)).foregroundColor(MivoColors.textMuted)
                        }
                        Spacer()
                        Text(format(metric.value, unit: metric.unit)).font(.system(size: 19, weight: .bold)).foregroundColor(MivoColors.textPrimary)
                    }
                }
            }
        }
    }

    private var releases: some View {
        VStack(alignment: .leading, spacing: 12) {
            AdminSectionTitle("Release health", icon: "shippingbox.fill")
            if expansion.adminSnapshot.releases.isEmpty {
                AdminEmptyState(title: "No release reports", detail: "Internal events appear immediately. Apple analytics remains Unavailable until imported and above Apple's privacy threshold.")
            }
            ForEach(filtered(expansion.adminSnapshot.releases, text: { $0.version })) { release in
                adminPanel {
                    HStack { Text("Version \(release.version)").font(.system(size: 18, weight: .bold)); Spacer(); Text(release.source).font(.caption).foregroundColor(MivoColors.textMuted) }
                    releaseMetric("Active users", value: "\(release.activeUsers)")
                    releaseMetric("Crash free", value: optionalPercent(release.crashFreeRate))
                    releaseMetric("Login success", value: optionalPercent(release.loginSuccessRate))
                    releaseMetric("Sync success", value: optionalPercent(release.syncSuccessRate))
                    releaseMetric("Session completion", value: optionalPercent(release.sessionCompletionRate))
                    releaseMetric("Retention", value: optionalPercent(release.retentionRate))
                }
            }
        }
    }

    private var dataQuality: some View {
        VStack(alignment: .leading, spacing: 12) {
            AdminSectionTitle("Data Quality", icon: "checkmark.seal.fill")
            if expansion.adminSnapshot.dataQualityIssues.isEmpty {
                AdminEmptyState(title: "No open issues", detail: "The nightly scan checks dates, duplicate sessions, durations, stale timers, observation days, and sync state.")
            }
            ForEach(filtered(expansion.adminSnapshot.dataQualityIssues, text: { $0.summary })) { issue in
                adminPanel {
                    HStack { severityDot(issue.severity); Text(issue.issueType.replacingOccurrences(of: "_", with: " ").capitalized).font(.system(size: 13, weight: .bold)); Spacer(); Text(issue.status.uppercased()).font(.caption2).foregroundColor(MivoColors.textMuted) }
                    Text(issue.summary).font(.system(size: 14, weight: .medium)).foregroundColor(MivoColors.textSecondary)
                    if issue.autoRepairable && issue.status == "open" {
                        Button("Repair deterministic issue") { Task { await expansion.repair(issue) } }
                            .font(.system(size: 13, weight: .bold)).foregroundColor(MivoColors.accent).frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }
            }
        }
    }

    private var analytics: some View {
        VStack(alignment: .leading, spacing: 12) {
            AdminSectionTitle("Outcome analytics", icon: "chart.xyaxis.line")
            adminPanel {
                HStack { Text("Apple analytics").font(.system(size: 16, weight: .bold)); Spacer(); Text(expansion.adminSnapshot.appStoreDataAvailable ? "Available" : "Unavailable").foregroundColor(expansion.adminSnapshot.appStoreDataAvailable ? .green : MivoColors.textMuted) }
                Text("Privacy-suppressed or not-yet-imported Apple values are shown as Unavailable, never as zero.")
                    .font(.system(size: 12)).foregroundColor(MivoColors.textSecondary)
            }
            NavigationLink { AdminAnalyticsView() } label: { adminNavigationLabel("Open growth and behavior analytics", icon: "chart.bar.xaxis") }
            NavigationLink { AdminFeedbackView() } label: { adminNavigationLabel("Feedback and bugs", icon: "bubble.left.and.exclamationmark.bubble.right.fill") }
        }
    }

    private var approvals: some View {
        VStack(alignment: .leading, spacing: 12) {
            AdminSectionTitle("Approval queue", icon: "tray.full.fill")
            if expansion.adminSnapshot.approvals.isEmpty { AdminEmptyState(title: "Queue is clear", detail: "Announcements, consent, and deletion reviews appear here.") }
            ForEach(filtered(expansion.adminSnapshot.approvals, text: { "\($0.title) \($0.detail)" })) { item in
                adminPanel {
                    Text(item.type.replacingOccurrences(of: "_", with: " ").uppercased()).font(.system(size: 10, weight: .bold)).foregroundColor(MivoColors.accent)
                    Text(item.title).font(.system(size: 17, weight: .bold)).foregroundColor(MivoColors.textPrimary)
                    Text(item.detail).font(.system(size: 13)).foregroundColor(MivoColors.textSecondary)
                    if item.status == "pending" {
                        HStack {
                            Button("Reject", role: .destructive) { Task { await expansion.resolve(item, action: "reject") } }
                            Spacer()
                            Button("Approve") { Task { await expansion.resolve(item, action: "approve") } }.fontWeight(.bold).foregroundColor(MivoColors.accent)
                        }
                    }
                }
            }
            NavigationLink { AnnouncementAdminView() } label: { adminNavigationLabel("Announcement drafts", icon: "bell.badge.fill") }
        }
    }

    private var users: some View {
        VStack(alignment: .leading, spacing: 12) {
            AdminSectionTitle("Users", icon: "person.3.fill")
            NavigationLink { AdminUserDatabaseView() } label: { adminNavigationLabel("Search the user database", icon: "magnifyingglass") }
            Text("Individual timelines deliberately exclude reflection notes, intention text, and selected-app identities.")
                .font(.system(size: 12, weight: .medium)).foregroundColor(MivoColors.textSecondary)
        }
    }

    private var consent: some View {
        VStack(alignment: .leading, spacing: 12) {
            AdminSectionTitle("Parent consent", icon: "person.crop.circle.badge.checkmark")
            NavigationLink { ParentalConsentReviewView() } label: { adminNavigationLabel("Review parent consent requests", icon: "checkmark.shield.fill") }
        }
    }

    private var security: some View {
        VStack(alignment: .leading, spacing: 12) {
            AdminSectionTitle("Audit and security", icon: "lock.shield.fill")
            if expansion.adminSnapshot.securityEvents.isEmpty { AdminEmptyState(title: "No recent security events", detail: "Role changes, exports, deletions, approvals, and suspicious access appear here.") }
            ForEach(filtered(expansion.adminSnapshot.securityEvents, text: { "\($0.action) \($0.actorLabel)" })) { event in
                adminPanel {
                    HStack { severityDot(event.severity); Text(event.action.replacingOccurrences(of: "_", with: " ").capitalized).font(.system(size: 15, weight: .bold)); Spacer() }
                    Text("\(event.actorLabel) · \(event.occurredAt)").font(.system(size: 12)).foregroundColor(MivoColors.textSecondary)
                    if let target = event.targetLabel { Text(target).font(.system(size: 12)).foregroundColor(MivoColors.textMuted) }
                }
            }
        }
    }

    private func filtered<T>(_ values: [T], text: (T) -> String) -> [T] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return values }
        return values.filter { text($0).lowercased().contains(query) }
    }

    private func severityDot(_ severity: AdminIssueSeverity) -> some View {
        Circle().fill(severity == .critical ? Color.red : severity == .warning ? MivoColors.accent : MivoColors.blue).frame(width: 9, height: 9)
    }

    private func format(_ value: Double, unit: String) -> String {
        if unit == "percent" { return "\(Int(value.rounded()))%" }
        return "\(value.formatted(.number.precision(.fractionLength(0...1)))) \(unit)"
    }

    private func optionalPercent(_ value: Double?) -> String { value.map { "\(Int($0.rounded()))%" } ?? "Unavailable" }
    private func releaseMetric(_ title: String, value: String) -> some View { HStack { Text(title); Spacer(); Text(value).fontWeight(.semibold) }.font(.system(size: 13)).foregroundColor(MivoColors.textSecondary) }
    private func adminNavigationLabel(_ title: String, icon: String) -> some View {
        HStack { Image(systemName: icon).foregroundColor(MivoColors.accent).frame(width: 34); Text(title).font(.system(size: 15, weight: .bold)); Spacer(); Image(systemName: "chevron.right").foregroundColor(MivoColors.textMuted) }
            .foregroundColor(MivoColors.textPrimary).padding(15).background(MivoColors.surfaceRaised.opacity(0.76)).clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct FeatureFlagRow: View {
    @State var flag: MivoFeatureFlag
    let save: (MivoFeatureFlag) -> Void

    var body: some View {
        adminPanel {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(MivoFeatureKey(rawValue: flag.key)?.title ?? flag.key).font(.system(size: 16, weight: .bold))
                    Text(flag.automaticallyPaused ? "Automatically paused" : "\(flag.rolloutPercentage)% rollout")
                        .font(.system(size: 11, weight: .medium)).foregroundColor(flag.automaticallyPaused ? .red : MivoColors.textSecondary)
                }
                Spacer()
                Toggle("", isOn: $flag.enabled).labelsHidden()
            }
            Picker("Rollout", selection: $flag.rolloutPercentage) {
                ForEach([0, 5, 25, 50, 100], id: \.self) { Text("\($0)%").tag($0) }
            }
            .pickerStyle(.segmented)
            Toggle("Founder preview", isOn: $flag.founderPreview)
            Button("Save flag") { save(flag) }.font(.system(size: 13, weight: .bold)).foregroundColor(MivoColors.accent).frame(maxWidth: .infinity, alignment: .trailing)
        }
    }
}

private struct AdminSectionTitle: View {
    let title: String; let icon: String
    init(_ title: String, icon: String) { self.title = title; self.icon = icon }
    var body: some View { Label(title, systemImage: icon).font(.system(size: 19, weight: .bold)).foregroundColor(MivoColors.textPrimary) }
}

private struct AdminMiniStat: View {
    let title: String; let value: String; let color: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 5) { Text(value).font(.system(size: 24, weight: .bold)).foregroundColor(color); Text(title).font(.system(size: 11, weight: .semibold)).foregroundColor(MivoColors.textSecondary) }
            .frame(maxWidth: .infinity, alignment: .leading).padding(13).background(MivoColors.surfaceRaised.opacity(0.75)).clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct AdminEmptyState: View {
    let title: String; let detail: String
    var body: some View {
        VStack(alignment: .leading, spacing: 5) { Text(title).font(.system(size: 16, weight: .bold)); Text(detail).font(.system(size: 13)).foregroundColor(MivoColors.textSecondary) }
            .frame(maxWidth: .infinity, alignment: .leading).padding(16).background(MivoColors.surfaceRaised.opacity(0.6)).clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private func adminPanel<Content: View>(@ViewBuilder content: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: 10) { content() }.padding(15)
        .background(MivoColors.surfaceRaised.opacity(0.76)).clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(MivoColors.border.opacity(0.7), lineWidth: 1))
}
