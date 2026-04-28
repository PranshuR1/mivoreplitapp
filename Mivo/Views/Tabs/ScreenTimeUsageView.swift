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

            MivoScreenTimeUsageLiveReport()
                .frame(minHeight: 360)
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .strokeBorder(MivoColors.border.opacity(0.7), lineWidth: 1)
                )
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
                Image(systemName: appVM.deviceActivityMinutesToday == nil ? "hourglass" : "checkmark.seal.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(appVM.deviceActivityMinutesToday == nil ? MivoColors.textMuted : MivoColors.accentLight)

                Text(appVM.deviceActivityMinutesToday == nil ? "Waiting for Apple's report" : "Extension report received")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(MivoColors.textPrimary)
            }

            if let generatedAt = appVM.deviceActivityReportGeneratedAt {
                Text("Last numeric report: \(generatedAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.system(size: 14))
                    .foregroundColor(MivoColors.textSecondary)
            } else {
                Text("When iOS publishes real activity through the Screen Time report extension, this page and the home total will update. Until then Mivo leaves the total empty instead of inventing a number.")
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

#if canImport(DeviceActivity) && canImport(FamilyControls) && canImport(ManagedSettings)
@available(iOS 16.0, *)
private struct MivoScreenTimeUsageLiveReport: View {
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
    }
}
#else
@available(iOS 16.0, *)
private struct MivoScreenTimeUsageLiveReport: View {
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
