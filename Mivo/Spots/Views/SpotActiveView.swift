import SwiftUI

/// The Spot that is running now: what it is, how long is left, and a plain way out.
struct SpotActiveView: View {
    @ObservedObject private var manager = SpotManager.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            MivoColors.background.ignoresSafeArea()

            if let session = manager.activeSession {
                content(session)
            } else {
                Color.clear.onAppear { dismiss() }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private func content(_ session: SpotSession) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 8) {
                        MivoEyebrow(text: "Active Spot")
                        Spacer()
                    }
                    .padding(.top, 30)

                    HStack(alignment: .center, spacing: 16) {
                        SpotIconView(icon: session.spotIcon, size: 64)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(session.spotName)
                                .font(.system(size: 27, weight: .bold))
                                .tracking(Font.mivoTracking(-0.025, at: 27))
                                .foregroundColor(MivoColors.ink)
                            Text(session.mode.cardLabel)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(MivoColors.inkBody)
                        }
                    }
                    .padding(.top, 14)

                    countdown(session)
                        .padding(.top, 30)

                    if let spot = manager.spot(id: session.spotID) {
                        MivoEyebrow(text: "Apps")
                            .padding(.top, 30)
                        SpotAppLabels(selection: spot.selectedApplications)
                            .padding(.top, 12)
                    }

                    if let intention = session.intention {
                        MivoEyebrow(text: "You came to")
                            .padding(.top, 26)
                        Text(intention.displayText)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(MivoColors.ink)
                            .padding(.top, 8)
                    }

                    Text(endHint(session))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(MivoColors.inkMuted)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 30)
                }
            }

            VStack(spacing: 4) {
                MivoInkButton(label: "End Spot") {
                    manager.end(reason: .endedManually)
                    dismiss()
                }
                MivoTertiaryButton(label: "Close") { dismiss() }
            }
            .padding(.bottom, 20)
        }
        .padding(.horizontal, MivoMetrics.screenPadding)
    }

    private func countdown(_ session: SpotSession) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let total = max(1, session.plannedEndDate.timeIntervalSince(session.startDate))
            let remaining = session.remainingSeconds(now: context.date)
            VStack(alignment: .leading, spacing: 12) {
                if session.isOpenEnded {
                    Text(Self.elapsedText(since: session.startDate, now: context.date))
                        .font(.system(size: 54, weight: .bold))
                        .monospacedDigit()
                        .foregroundColor(MivoColors.ink)
                    Text("so far · runs until you end it")
                        .font(.system(size: 13.5, weight: .medium))
                        .foregroundColor(MivoColors.inkBody)
                } else {
                    Text(formatSeconds(Int(remaining.rounded(.up))))
                        .font(.system(size: 54, weight: .bold))
                        .monospacedDigit()
                        .foregroundColor(MivoColors.ink)
                    MivoProgressTrack(fraction: 1 - remaining / total, fill: MivoColors.accent)
                    Text("left of \(SpotFormat.duration(minutes: Int((total / 60).rounded())))")
                        .font(.system(size: 13.5, weight: .medium))
                        .foregroundColor(MivoColors.inkBody)
                }
            }
        }
    }

    static func elapsedText(since start: Date, now: Date) -> String {
        formatSeconds(Int(max(0, now.timeIntervalSince(start))))
    }

    private func endHint(_ session: SpotSession) -> String {
        session.isOpenEnded
            ? "End it here or tap your Mivo Spot again. Mivo will end it by itself after \(SpotKeys.openEndedCapHours) hours."
            : "It ends when the timer does, when you tap your Mivo Spot again, or here — whichever comes first."
    }
}
