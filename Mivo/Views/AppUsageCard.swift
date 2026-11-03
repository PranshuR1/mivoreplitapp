import SwiftUI

/// Patterns card: each app opened in Mivo, against what was said before it
/// opened. See `AppPurposeReport`.
struct AppUsageCard: View {
    let report: AppPurposeReport

    var body: some View {
        MivoCard {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("Apps in Mivo")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(MivoColors.inkBody)
                    Spacer(minLength: 8)
                    Text(report.sessionCount == 1 ? "1 session" : "\(report.sessionCount) sessions")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(MivoColors.inkBody)
                }

                if let share = report.onPurposeShare {
                    Text("\(percent(share))%")
                        .font(.system(size: 32, weight: .bold))
                        .monospacedDigit()
                        .tracking(Font.mivoTracking(-0.03, at: 32))
                        .foregroundColor(MivoColors.ink)
                        .padding(.top, 10)
                    Text("of your time went to what you said you came for.")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(MivoColors.inkBody)
                        .padding(.top, 4)
                    MivoProgressTrack(fraction: share)
                        .padding(.top, 12)
                } else {
                    Text("Mivo compares what you say you'll do with what you do, once you've spent a couple of minutes in an app here.")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(MivoColors.inkBody)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 10)
                }

                VStack(spacing: 12) {
                    ForEach(report.rows) { row in
                        appRow(row)
                    }
                }
                .padding(.top, 18)

                if !report.findings.isEmpty {
                    Text("What Mivo noticed")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(MivoColors.ink)
                        .accessibilityAddTraits(.isHeader)
                        .padding(.top, 18)

                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(Array(report.findings.enumerated()), id: \.offset) { index, finding in
                            PatternsNoticedRow(
                                dotColor: [MivoColors.accent, MivoColors.info, MivoColors.kept][index % 3],
                                text: AttributedString(finding)
                            )
                        }
                    }
                    .padding(.top, 10)
                }
            }
        }
    }

    private func appRow(_ row: AppUsageRow) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: row.app.icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(MivoColors.ink)
                .frame(width: 30, height: 30)
                .background(MivoColors.ink.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: MivoMetrics.radius))

            VStack(alignment: .leading, spacing: 2) {
                Text(row.app.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(MivoColors.ink)
                Text(rowDetail(row))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(MivoColors.inkMuted)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            if let share = row.onPurposeShare {
                VStack(alignment: .trailing, spacing: 1) {
                    Text("\(percent(share))%")
                        .font(.system(size: 14, weight: .semibold))
                        .monospacedDigit()
                        .foregroundColor(MivoColors.ink)
                    Text("on purpose")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundColor(MivoColors.inkMuted)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func rowDetail(_ row: AppUsageRow) -> String {
        var parts = [row.sessions == 1 ? "1 session" : "\(row.sessions) sessions", "\(row.minutes) min"]
        if row.shortVideos > 0 { parts.append(row.app.shortVideoCount(row.shortVideos)) }
        if let usual = row.usualPurpose { parts.append("usually \(usual.title.lowercased())") }
        return parts.joined(separator: " · ")
    }

    private func percent(_ share: Double) -> Int { Int((share * 100).rounded()) }
}
