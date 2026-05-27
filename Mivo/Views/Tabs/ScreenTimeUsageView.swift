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

// MARK: - Screen Time Usage View
// Displays real Screen Time data through Apple's DeviceActivityReport surface.

@available(iOS 16.0, *)
struct ScreenTimeUsageView: View {
    @EnvironmentObject var appVM: AppViewModel

    var body: some View {
        ZStack {
            MivoColors.background.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    liveReportCard
                    statusCard

                    Spacer(minLength: 100)
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
            }
        }
        .refreshable {
            appVM.refreshScreenTimeData()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Live Screen Time")
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(MivoColors.textPrimary)
                .tracking(-0.8)

            Text("Mivo shows Apple's Screen Time report directly. It will not use session history or test values as a substitute.")
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(MivoColors.textSecondary)
                .lineSpacing(3)
        }
    }

    private var liveReportCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "iphone.gen3")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(MivoColors.accentLight)

                Text("Today")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(MivoColors.textPrimary)

                Spacer()
            }

            MivoReadableScreenTimeSummaryCard(compact: false)
        }
        .padding(16)
        .background(MivoColors.white.opacity(0.48))
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .overlay(
            RoundedRectangle(cornerRadius: 22)
                .strokeBorder(MivoColors.border.opacity(0.75), lineWidth: 1)
        )
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(MivoColors.accentLight)

                Text("Live Apple report")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(MivoColors.textPrimary)
            }

            if let generatedAt = appVM.deviceActivityReportGeneratedAt {
                Text("Last numeric report: \(generatedAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.system(size: 14))
                    .foregroundColor(MivoColors.textSecondary)
            } else {
                Text("The report above is the real Screen Time surface. Apple keeps detailed usage inside the report extension, so Mivo renders it directly instead of inventing or exporting totals.")
                    .font(.system(size: 14))
                    .foregroundColor(MivoColors.textSecondary)
                    .lineSpacing(3)
            }
        }
        .padding(16)
        .background(MivoColors.card)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(MivoColors.border, lineWidth: 1)
        )
    }
}

@available(iOS 16.0, *)
struct MivoReadableScreenTimeSummaryCard: View {
    @EnvironmentObject var appVM: AppViewModel
    var compact: Bool = false
    private let reportPoller = Timer.publish(every: 5, on: .main, in: .common).autoconnect()

    private var topApps: [(key: String, value: Int)] {
        Array(appVM.deviceActivityPerAppSeconds.sorted { $0.value > $1.value }.prefix(compact ? 2 : 4))
    }

    var body: some View {
        Group {
            if hasCachedReport {
                readableCachedSummary
            } else {
                liveReportSurfaceCard
            }
        }
        .frame(minHeight: compact ? 170 : 238)
        .onAppear {
            appVM.loadDeviceActivityReport()
        }
        .onReceive(reportPoller) { _ in
            appVM.loadDeviceActivityReport()
        }
    }

    private var hasCachedReport: Bool {
        appVM.deviceActivityMinutesToday != nil ||
        appVM.deviceActivityReportGeneratedAt != nil ||
        !appVM.deviceActivityPerAppSeconds.isEmpty
    }

    private var readableCachedSummary: some View {
        ZStack(alignment: .bottomTrailing) {
            VStack(alignment: .leading, spacing: compact ? 12 : 16) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(totalText)
                            .font(.system(size: compact ? 44 : 54, weight: .bold, design: .rounded))
                            .foregroundColor(MivoColors.textPrimary)
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)

                        Text(subtitleText)
                            .font(.system(size: compact ? 12 : 13, weight: .semibold))
                            .foregroundColor(MivoColors.textSecondary)
                            .lineLimit(2)
                    }

                    Spacer()

                    Image(systemName: "iphone.gen3")
                        .font(.system(size: compact ? 18 : 20, weight: .bold))
                        .foregroundColor(MivoColors.heroText)
                        .frame(width: compact ? 38 : 44, height: compact ? 38 : 44)
                        .background(MivoColors.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }

                if topApps.isEmpty {
                    readableEmptyState
                } else {
                    VStack(spacing: 9) {
                        ForEach(topApps, id: \.key) { app in
                            readableAppRow(name: prettyBundleName(app.key), seconds: app.value)
                        }
                    }
                }

                HStack(spacing: 8) {
                    Label("Apple Screen Time", systemImage: "checkmark.seal.fill")
                    Spacer(minLength: 8)
                    Text(updatedText)
                }
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(MivoColors.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
            }
            .padding(compact ? 16 : 18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                LinearGradient(
                    colors: [
                        Color(hex: "#FFF9F1"),
                        Color(hex: "#F5E9DA")
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(MivoColors.border.opacity(0.42), lineWidth: 1)
            )

            reportSyncSurface
                .frame(width: 1, height: 1)
                .opacity(0.01)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    private var liveReportSurfaceCard: some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 10) {
            HStack(spacing: 8) {
                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 12, weight: .bold))
                Text("Live Apple Screen Time")
                    .font(.system(size: 12, weight: .bold))
                Spacer()
                Text("Direct report")
                    .font(.system(size: 11, weight: .bold))
            }
            .foregroundColor(MivoColors.textSecondary)

            reportSyncSurface
                .frame(maxWidth: .infinity, minHeight: compact ? 132 : 194)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .padding(compact ? 14 : 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [
                    Color(hex: "#FFF9F1"),
                    Color(hex: "#F5E9DA")
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(MivoColors.border.opacity(0.42), lineWidth: 1)
        )
    }

    private var readableEmptyState: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Waiting for Apple’s app-level report.")
                .font(.system(size: compact ? 13 : 14, weight: .bold))
                .foregroundColor(MivoColors.textPrimary)
            Text("The live report above is still real Screen Time data; detailed app rows appear once Apple publishes the breakdown.")
                .font(.system(size: compact ? 12 : 13, weight: .medium))
                .foregroundColor(MivoColors.textSecondary)
                .lineSpacing(3)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MivoColors.white.opacity(0.58))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(MivoColors.border.opacity(0.22), lineWidth: 1))
    }

    private func readableAppRow(name: String, seconds: Int) -> some View {
        let largest = max(topApps.first?.value ?? 1, 1)
        let progress = CGFloat(max(0.04, Double(seconds) / Double(largest)))

        return VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 10) {
                Text(name)
                    .font(.system(size: compact ? 12 : 13, weight: .bold))
                    .foregroundColor(MivoColors.textPrimary)
                    .lineLimit(1)
                Spacer()
                Text(formatSeconds(seconds))
                    .font(.system(size: compact ? 12 : 13, weight: .bold))
                    .foregroundColor(MivoColors.textPrimary)
                    .monospacedDigit()
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(MivoColors.border.opacity(0.28))
                    Capsule()
                        .fill(MivoColors.blue)
                        .frame(width: max(8, proxy.size.width * progress))
                }
            }
            .frame(height: 7)
        }
        .padding(12)
        .background(MivoColors.white.opacity(0.52))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    @ViewBuilder
    private var reportSyncSurface: some View {
        #if canImport(DeviceActivity) && canImport(FamilyControls) && canImport(ManagedSettings)
        MivoScreenTimeUsageLiveReport()
        #else
        EmptyView()
        #endif
    }

    private var totalText: String {
        guard let minutes = appVM.deviceActivityMinutesToday else { return "0m" }
        return formatMinutes(minutes)
    }

    private var subtitleText: String {
        if appVM.deviceActivityMinutesToday != nil {
            return "real iOS Screen Time today"
        }
        return "real iOS Screen Time today"
    }

    private var updatedText: String {
        guard let date = appVM.deviceActivityReportGeneratedAt else { return "Live report" }
        return "Updated \(date.formatted(date: .omitted, time: .shortened))"
    }

    private func prettyBundleName(_ bundleID: String) -> String {
        let last = bundleID.split(separator: ".").last.map(String.init) ?? bundleID
        return last.replacingOccurrences(of: "-", with: " ").capitalized
    }

    private func formatSeconds(_ seconds: Int) -> String {
        formatMinutes(max(0, Int((Double(seconds) / 60.0).rounded())))
    }

    private func formatMinutes(_ minutes: Int) -> String {
        let safe = max(0, minutes)
        let hours = safe / 60
        let mins = safe % 60
        if hours > 0 {
            return "\(hours)h \(mins)m"
        }
        return "\(mins)m"
    }
}

#if canImport(DeviceActivity) && canImport(FamilyControls) && canImport(ManagedSettings)
@available(iOS 16.0, *)
struct MivoScreenTimeUsageLiveReport: View {
    private let context = DeviceActivityReport.Context("MivoPatternsTotalActivity")

    private var filter: DeviceActivityFilter {
        let interval = Calendar.current.dateInterval(of: .day, for: Date()) ?? DateInterval(start: Date(), duration: 24 * 60 * 60)
        return DeviceActivityFilter(
            segment: .daily(during: interval),
            devices: .init([.iPhone, .iPad]),
            applications: Set<ApplicationToken>(),
            categories: Set<ActivityCategoryToken>(),
            webDomains: Set<WebDomainToken>()
        )
    }

    var body: some View {
        DeviceActivityReport(context, filter: filter)
            .background(MivoColors.background.opacity(0.35))
            .environment(\.colorScheme, .light)
    }
}
#else
@available(iOS 16.0, *)
struct MivoScreenTimeUsageLiveReport: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "lock.shield")
                .font(.system(size: 28, weight: .semibold))
                .foregroundColor(MivoColors.textMuted)

            Text("Screen Time reports are not available in this build.")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(MivoColors.textPrimary)

            Text("Build on a device with Family Controls and Device Activity enabled.")
                .font(.system(size: 13))
                .foregroundColor(MivoColors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 280)
    }
}
#endif

@available(iOS 16.0, *)
struct ScreenTimeUsageView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            ScreenTimeUsageView()
                .environmentObject(AppViewModel())
        }
    }
}
