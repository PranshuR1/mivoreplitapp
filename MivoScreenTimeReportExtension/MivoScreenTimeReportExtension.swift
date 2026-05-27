import DeviceActivity
import ExtensionKit
import Foundation
import ManagedSettings
import SwiftUI

@main
struct MivoScreenTimeReportExtension: DeviceActivityReportExtension {
    var body: some DeviceActivityReportScene {
        MivoTotalActivityReportScene()
    }
}

private struct MivoTotalActivityReportScene: DeviceActivityReportScene {
    let context = DeviceActivityReport.Context("MivoPatternsTotalActivity")
    let content: (MivoScreenTimeReportConfiguration) -> MivoScreenTimeReportView

    init() {
        content = { configuration in
            MivoScreenTimeReportView(configuration: configuration)
        }
    }

    func makeConfiguration(
        representing data: DeviceActivityResults<DeviceActivityData>
    ) async -> MivoScreenTimeReportConfiguration {
        var totalDuration: TimeInterval = 0
        var longestSession: TimeInterval = 0
        var firstPickup: Date?
        var lastUpdated: Date?
        var appDurations: [String: TimeInterval] = [:]

        for await deviceData in data {
            lastUpdated = lastUpdated.map { max($0, deviceData.lastUpdatedDate) } ?? deviceData.lastUpdatedDate

            for await segment in deviceData.activitySegments {
                totalDuration += segment.totalActivityDuration

                if let longestActivity = segment.longestActivity {
                    longestSession = max(longestSession, longestActivity.duration)
                }

                if let pickup = segment.firstPickup {
                    firstPickup = firstPickup.map { min($0, pickup) } ?? pickup
                }

                for await category in segment.categories {
                    for await app in category.applications {
                        let appName = app.application.localizedDisplayName
                            ?? app.application.bundleIdentifier
                            ?? "App"
                        appDurations[appName, default: 0] += app.totalActivityDuration
                    }
                }
            }
        }

        Self.publishCachedReport(
            totalDuration: totalDuration,
            appDurations: appDurations,
            generatedAt: lastUpdated ?? Date()
        )

        return MivoScreenTimeReportConfiguration(
            lastUpdated: lastUpdated,
            totalDuration: totalDuration,
            longestSession: longestSession,
            firstPickup: firstPickup,
            topApps: appDurations
                .map { MivoActivityItem(name: $0.key, duration: $0.value) }
                .sorted { $0.duration > $1.duration }
        )
    }

    private static func publishCachedReport(
        totalDuration: TimeInterval,
        appDurations: [String: TimeInterval],
        generatedAt: Date
    ) {
        guard let defaults = UserDefaults(suiteName: "group.com.mivo.mivoapp") else { return }

        let perAppSeconds = appDurations.reduce(into: [String: Int]()) { result, item in
            result[item.key] = max(0, Int(item.value.rounded()))
        }
        let payload: [String: Any] = [
            "generatedAt": ISO8601DateFormatter().string(from: generatedAt),
            "totalSeconds": max(0, Int(totalDuration.rounded())),
            "perAppSeconds": perAppSeconds,
            "source": "mivo-device-activity-extension"
        ]

        guard JSONSerialization.isValidJSONObject(payload),
              let data = try? JSONSerialization.data(withJSONObject: payload, options: []),
              let json = String(data: data, encoding: .utf8) else { return }

        defaults.set(json, forKey: "mivo.lastDeviceActivityReport")
        defaults.set(Date().timeIntervalSince1970, forKey: "mivo.lastReportTimestamp")
        defaults.synchronize()
    }
}

private struct MivoScreenTimeReportConfiguration: Equatable {
    let lastUpdated: Date?
    let totalDuration: TimeInterval
    let longestSession: TimeInterval
    let firstPickup: Date?
    let topApps: [MivoActivityItem]
}

private struct MivoActivityItem: Identifiable, Equatable {
    var id: String { name }
    let name: String
    let duration: TimeInterval
}

private enum MivoReportPalette {
    static let backgroundTop = Color(red: 0.98, green: 0.95, blue: 0.91)
    static let backgroundBottom = Color(red: 0.94, green: 0.89, blue: 0.80)
    static let card = Color(red: 1.0, green: 0.985, blue: 0.955)
    static let primary = Color(red: 0.09, green: 0.06, blue: 0.035)
    static let secondary = Color(red: 0.22, green: 0.14, blue: 0.075)
    static let muted = Color(red: 0.36, green: 0.24, blue: 0.14)
    static let border = Color(red: 0.70, green: 0.55, blue: 0.36).opacity(0.56)
    static let accent = Color(red: 0.83, green: 0.53, blue: 0.16)
    static let blue = Color(red: 0.29, green: 0.44, blue: 0.65)
}

private struct MivoScreenTimeReportView: View {
    let configuration: MivoScreenTimeReportConfiguration

    var body: some View {
        GeometryReader { proxy in
            VStack(alignment: .leading, spacing: proxy.size.height < 260 ? 10 : 16) {
                header

                if configuration.totalDuration > 0 {
                    if proxy.size.height >= 230 {
                        statsRow
                    }

                    if proxy.size.height >= 190 {
                        activityBars(items: Array(configuration.topApps.prefix(proxy.size.height < 260 ? 2 : 4)))
                    }
                } else {
                    emptyState
                }

                Spacer(minLength: 0)
            }
            .padding(proxy.size.height < 220 ? 14 : 18)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(reportBackground)
            .environment(\.colorScheme, .light)
            .preferredColorScheme(.light)
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(MivoReportPalette.border, lineWidth: 1)
            )
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(formattedDuration(configuration.totalDuration))
                .font(.system(size: configuration.totalDuration >= 36_000 ? 38 : 46, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundColor(MivoReportPalette.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)

            Text("real iOS Screen Time today")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(MivoReportPalette.secondary)
                .lineLimit(1)
        }
    }

    private var statsRow: some View {
        HStack(spacing: 10) {
            statPill(title: configuration.firstPickup.map(shortTime) ?? "--", subtitle: "first pickup")
            statPill(title: formattedDuration(configuration.longestSession), subtitle: "longest use")
        }
    }

    private func statPill(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundColor(MivoReportPalette.primary)
                .lineLimit(1)
            Text(subtitle)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(MivoReportPalette.muted)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .background(MivoReportPalette.card)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(MivoReportPalette.border, lineWidth: 1))
    }

    private func activityBars(items: [MivoActivityItem]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(items) { item in
                let largest = max(items.first?.duration ?? 1, 1)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(item.name)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(MivoReportPalette.primary)
                            .lineLimit(1)
                        Spacer()
                        Text(formattedDuration(item.duration))
                            .font(.system(size: 11, weight: .bold))
                            .monospacedDigit()
                            .foregroundColor(MivoReportPalette.secondary)
                    }

                    GeometryReader { barProxy in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(MivoReportPalette.border.opacity(0.72))
                            Capsule()
                                .fill(MivoReportPalette.blue)
                                .frame(width: max(8, barProxy.size.width * (item.duration / largest)))
                        }
                    }
                    .frame(height: 6)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("No activity in Apple’s report for this interval.")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(MivoReportPalette.primary)
            Text(configuration.lastUpdated.map { "Updated \(shortTime($0))" } ?? "Open Screen Time in Settings once, then return here.")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(MivoReportPalette.secondary)
                .lineLimit(2)
        }
        .padding(12)
        .background(MivoReportPalette.card)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(MivoReportPalette.border, lineWidth: 1))
    }

    private var reportBackground: some View {
        LinearGradient(
            colors: [
                MivoReportPalette.backgroundTop,
                MivoReportPalette.backgroundBottom
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private func formattedDuration(_ duration: TimeInterval) -> String {
        let totalMinutes = max(Int((duration / 60).rounded()), 0)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }

        return "\(minutes)m"
    }

    private func shortTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: date)
    }
}
