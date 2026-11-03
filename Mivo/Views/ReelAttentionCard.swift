import SwiftUI

/// Patterns card: Mivo's read of how short videos (Reels, Shorts, TikToks,
/// Spotlight) are watched inside Mivo, and the plan that follows from it.
/// See `ReelAttentionReport`.
struct ReelAttentionCard: View {
    let report: ReelAttentionReport
    let plan: ReelPlan?

    var body: some View {
        MivoCard {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("Short-video attention")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(MivoColors.inkBody)
                    Spacer(minLength: 8)
                    Text(report.sessionCount == 1 ? "1 session" : "\(report.sessionCount) sessions")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(MivoColors.inkBody)
                }

                if let band = report.band {
                    Text(band.title)
                        .font(.system(size: 32, weight: .bold))
                        .tracking(Font.mivoTracking(-0.03, at: 32))
                        .foregroundColor(MivoColors.ink)
                        .padding(.top, 10)

                    Text(band.detail)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(MivoColors.inkBody)
                        .padding(.top, 6)
                } else {
                    Text(notEnoughDataText)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(MivoColors.inkBody)
                        .padding(.top, 10)
                }

                VStack(spacing: 10) {
                    statRow("Short videos watched", value: "\(report.totalReels) · \(formatted(report.reelsPerDay)) a day")
                    if let median = report.medianSecondsPerReel {
                        statRow("Seconds per video", value: "\(formatted(median)) (middle value)")
                    }
                    if let skips = report.quickSkipShare {
                        statRow("Left in under 3 seconds", value: "\(Int((skips * 100).rounded()))%")
                    }
                    if report.pickedSessions > 0 {
                        statRow("Went past your pick", value: "\(report.wentPastPick) of \(report.pickedSessions) sessions")
                    }
                }
                .padding(.top, 16)

                if let plan, !plan.steps.isEmpty {
                    Text("Your plan")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(MivoColors.ink)
                        .accessibilityAddTraits(.isHeader)
                        .padding(.top, 18)

                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(Array(plan.steps.enumerated()), id: \.offset) { index, step in
                            PatternsNoticedRow(
                                dotColor: [MivoColors.accent, MivoColors.info, MivoColors.kept][index % 3],
                                text: AttributedString(step)
                            )
                        }
                    }
                    .padding(.top, 10)
                }
            }
        }
    }

    private var notEnoughDataText: String {
        let sessionsLeft = max(0, ReelAttentionReport.minimumSessions - report.sessionCount)
        if sessionsLeft > 0 {
            return "Mivo reads your attention after \(ReelAttentionReport.minimumSessions) sessions in Mivo. \(sessionsLeft) more to go."
        }
        let reelsLeft = max(0, ReelAttentionReport.minimumTimedReels - report.timedReels)
        return "Mivo needs about \(reelsLeft) more short videos at normal speed to read your attention."
    }

    private func statRow(_ title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .font(.system(size: 13.5, weight: .medium))
                .foregroundColor(MivoColors.inkBody)
            Spacer(minLength: 8)
            Text(value)
                .font(.system(size: 13.5, weight: .semibold))
                .monospacedDigit()
                .foregroundColor(MivoColors.ink)
        }
    }

    private func formatted(_ value: Double) -> String {
        value < 10 ? String(format: "%.1f", value) : String(Int(value.rounded()))
    }
}
