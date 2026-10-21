import SwiftUI

/// Shown when a Spot session finishes. Plain numbers, no scoring, and a
/// comparison only when there is enough of the person's own history to make one.
struct SpotSummaryView: View {
    let summary: SpotSessionSummary
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            MivoColors.background.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        MivoEyebrow(text: "Spot summary")
                            .padding(.top, 30)

                        HStack(spacing: 14) {
                            SpotIconView(icon: summary.spotIcon, size: 52)
                            Text(summary.spotName)
                                .font(.system(size: 27, weight: .bold))
                                .tracking(Font.mivoTracking(-0.025, at: 27))
                                .foregroundColor(MivoColors.ink)
                                .lineLimit(2)
                        }
                        .padding(.top, 14)

                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(SpotFormat.compact(minutes: summary.activeMinutes))
                                .font(.system(size: 44, weight: .bold))
                                .monospacedDigit()
                                .foregroundColor(MivoColors.ink)
                            Text("active")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(MivoColors.inkBody)
                        }
                        .padding(.top, 22)

                        Text(Self.reasonText(summary.reason))
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(MivoColors.inkMuted)
                            .padding(.top, 2)

                        usageBlock
                            .padding(.top, 26)

                        if let sentence = SpotInsights.comparisonText(summary.comparison, spotName: summary.spotName) {
                            Text(sentence)
                                .font(.system(size: 14.5, weight: .semibold))
                                .foregroundColor(comparisonColor)
                                .lineSpacing(4)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.top, 22)
                        }

                        if let intention = summary.intention {
                            MivoHairline()
                                .padding(.top, 26)
                            MivoEyebrow(text: "You came to")
                                .padding(.top, 20)
                            Text(intention.displayText)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(MivoColors.ink)
                                .padding(.top, 8)
                        }
                    }
                }

                MivoInkButton(label: "Done") { dismiss() }
                    .padding(.bottom, 20)
            }
            .padding(.horizontal, MivoMetrics.screenPadding)
        }
    }

    // MARK: Usage

    @ViewBuilder
    private var usageBlock: some View {
        if let total = summary.distractingMinutes {
            VStack(alignment: .leading, spacing: 0) {
                MivoHairline()
                MivoEyebrow(text: "In your selected apps")
                    .padding(.top, 20)
                    .padding(.bottom, 8)

                if summary.perApp.isEmpty {
                    Text(total == 0 ? "No time in them while this Spot was on." : "\(total) min in total.")
                        .font(.system(size: 14.5, weight: .semibold))
                        .foregroundColor(MivoColors.ink)
                        .padding(.vertical, 6)
                } else {
                    ForEach(summary.perApp) { app in
                        HStack {
                            SpotTokenLabel(tokenData: app.tokenData, fallbackName: app.name)
                            Spacer()
                            Text("\(app.minutes) min")
                                .font(.system(size: 14, weight: .semibold))
                                .monospacedDigit()
                                .foregroundColor(MivoColors.inkBody)
                        }
                        .padding(.vertical, 8)
                    }
                    if total > summary.perApp.map(\.minutes).reduce(0, +) {
                        HStack {
                            Text("Everything together")
                                .font(.system(size: 13.5, weight: .medium))
                                .foregroundColor(MivoColors.inkBody)
                            Spacer()
                            Text("\(total) min")
                                .font(.system(size: 13.5, weight: .semibold))
                                .monospacedDigit()
                                .foregroundColor(MivoColors.inkBody)
                        }
                        .padding(.top, 6)
                    }
                }

                Text("iOS reports app time in steps, so these are close, not exact.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(MivoColors.inkMuted)
                    .padding(.top, 10)
            }
        } else {
            VStack(alignment: .leading, spacing: 6) {
                MivoHairline()
                MivoEyebrow(text: "In your selected apps")
                    .padding(.top, 20)
                Text("App time wasn't measured this time. That needs Screen Time access to be on while the Spot runs.")
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundColor(MivoColors.inkBody)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 6)
            }
        }
    }

    private var comparisonColor: Color {
        switch summary.comparison {
        case .lessThanUsual: return MivoColors.kept
        default: return MivoColors.inkBody
        }
    }

    static func reasonText(_ reason: SpotCompletionReason) -> String {
        switch reason {
        case .timerCompleted: return "The timer finished."
        case .endedByTag: return "You ended it with a tap."
        case .endedManually: return "You ended it."
        case .replaced: return "You moved on to another Spot."
        case .expired: return "Mivo ended it after a long stretch."
        case .spotRemoved: return "The Spot was removed."
        case .signedOut: return "You signed out."
        }
    }
}
