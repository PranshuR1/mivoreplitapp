import SwiftUI

/// Mivo Spots: the list of the person's Spots, the one that is running, and a
/// quiet summary of how they have used them.
struct SpotsHomeView: View {
    @ObservedObject private var manager = SpotManager.shared
    @ObservedObject private var nfc = SpotNFCService.shared

    @State private var showSetup = false
    @State private var showActive = false
    @State private var scanMessage: String?
    @State private var limitMessage: String?

    var body: some View {
        ZStack {
            MivoColors.background.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    introBlock

                    SpotActiveBanner(topPadding: 22) { showActive = true }

                    if manager.spots.isEmpty {
                        emptyState
                    } else {
                        spotList
                    }

                    actionButtons

                    if !manager.sessions.isEmpty {
                        insightsSection
                    }
                }
                .padding(.horizontal, MivoMetrics.screenPadding)
                .padding(.bottom, MivoMetrics.scrollBottomPadding)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(isPresented: $showSetup) {
            SpotSetupFlowView(editing: nil)
        }
        .sheet(isPresented: $showActive) {
            SpotActiveView()
        }
        .alert("Mivo Spots", isPresented: Binding(
            get: { scanMessage != nil },
            set: { if !$0 { scanMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(scanMessage ?? "")
        }
        .alert("That's all the Spots Mivo can hold", isPresented: Binding(
            get: { limitMessage != nil },
            set: { if !$0 { limitMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(limitMessage ?? "")
        }
        .onAppear { manager.ensureLoaded(); manager.reconcile() }
    }

    // MARK: Intro

    private var introBlock: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Mivo Spots")
                .font(.system(size: 27, weight: .bold))
                .tracking(Font.mivoTracking(-0.025, at: 27))
                .foregroundColor(MivoColors.ink)

            Text("Tap your Mivo Spot to start using your phone on purpose. Tap it again to end it.")
                .font(.system(size: 13.5, weight: .medium))
                .foregroundColor(MivoColors.inkBody)
                .lineSpacing(0.55 * 13.5)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 320, alignment: .leading)
                .padding(.top, 10)
        }
        .padding(.top, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: List

    private var spotList: some View {
        VStack(spacing: 0) {
            MivoEyebrow(text: "Your Spots")
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 30)
                .padding(.bottom, 4)

            ForEach(Array(manager.spots.enumerated()), id: \.element.id) { index, spot in
                NavigationLink {
                    SpotDetailView(spotID: spot.id)
                } label: {
                    SpotCardRow(spot: spot, isActive: manager.isActive(spot.id))
                }
                .buttonStyle(.plain)

                if index < manager.spots.count - 1 {
                    MivoHairline(soft: true)
                }
            }
            MivoHairline()
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 14) {
            MivoEyebrow(text: "How it works")
                .padding(.top, 30)

            ForEach(Array(Self.steps.enumerated()), id: \.offset) { _, step in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: step.symbol)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(MivoColors.deep)
                        .frame(width: 24)
                        .accessibilityHidden(true)
                    Text(step.text)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(MivoColors.inkBody)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.bottom, 8)

            MivoHairline()
        }
    }

    private static let steps: [(symbol: String, text: String)] = [
        ("mappin.and.ellipse", "Put your Mivo Spot where you want it — your desk, your bedside, the car."),
        ("wave.3.right", "Tap it with your iPhone. The first time, you set up what it does."),
        ("hand.raised", "Each Spot decides what happens: a pause, a focus session, a question, or just awareness. Change it any time.")
    ]

    // MARK: Actions

    /// The Mivo Spot is the main way in: scanning one starts setup (or the Spot, if
    /// it is already set up). A Digital Spot — no hardware — stays available for
    /// anyone without one yet, and on devices that can't read NFC.
    @ViewBuilder
    private var actionButtons: some View {
        if SpotNFCService.isAvailable {
            MivoPrimaryButton(
                label: nfc.isWorking ? "Waiting for your Mivo Spot…" : manager.spots.isEmpty ? "Set up your Mivo Spot" : "Scan a Mivo Spot",
                disabled: nfc.isWorking
            ) {
                scan()
            }
            .padding(.top, 24)

            MivoTertiaryButton(label: "Create a Digital Spot") { createDigitalSpot() }
                .padding(.top, 4)
        } else {
            MivoPrimaryButton(label: "Create a Digital Spot") { createDigitalSpot() }
                .padding(.top, 24)

            Text("This device can't read NFC. Tap your Mivo Spot with an iPhone, and your Spots appear here.")
                .font(.system(size: 12.5, weight: .medium))
                .foregroundColor(MivoColors.inkMuted)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)
        }
    }

    private func createDigitalSpot() {
        HapticsService.selection()
        if manager.spots.count >= SpotManager.maxSpots {
            limitMessage = "Remove one before adding another."
        } else {
            showSetup = true
        }
    }

    private func scan() {
        Task {
            do {
                let target = try await SpotNFCService.shared.scanSpot()
                manager.handle(target: target, trigger: .inAppScan)
            } catch let error as SpotNFCError {
                if error != .cancelled { scanMessage = error.message }
            } catch {
                scanMessage = error.localizedDescription
            }
        }
    }

    // MARK: Insights

    private var insightsSection: some View {
        let overall = manager.overallStats
        let totals = overall.totals
        return VStack(alignment: .leading, spacing: 0) {
            MivoEyebrow(text: "Across your Spots")
                .padding(.top, 30)

            if totals.sessionCount == 0 {
                Text("Your first full session will show up here.")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(MivoColors.inkMuted)
                    .padding(.top, 12)
            } else {
                MivoStatColumns(items: [
                    .init(value: "\(totals.sessionCount)", label: totals.sessionCount == 1 ? "session" : "sessions"),
                    .init(value: SpotFormat.compact(minutes: totals.totalActiveMinutes), label: "in Spots"),
                    .init(value: SpotFormat.compact(minutes: totals.averageSessionMinutes), label: "avg session")
                ])
                .padding(.top, 10)

                VStack(spacing: 0) {
                    if let name = overall.mostUsedSpotName {
                        SpotFact(label: "Most used", value: "\(name) · \(overall.mostUsedSessionCount)×")
                    }
                    if totals.measuredSessionCount > 0 {
                        SpotFact(
                            label: "In selected apps",
                            value: "\(SpotFormat.compact(minutes: totals.measuredDistractingMinutes)) over \(totals.measuredSessionCount) \(totals.measuredSessionCount == 1 ? "session" : "sessions")"
                        )
                    }
                }
                .padding(.top, 4)
            }
        }
    }
}

/// One Spot in the list.
struct SpotCardRow: View {
    let spot: MivoSpot
    let isActive: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            SpotIconView(icon: spot.icon, size: 46)

            VStack(alignment: .leading, spacing: 4) {
                Text(spot.name)
                    .font(.system(size: 15.5, weight: .semibold))
                    .foregroundColor(MivoColors.ink)
                    .lineLimit(1)
                Text("\(spot.kindLabel) · \(spot.mode.cardLabel)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(MivoColors.inkBody)
                Text(spot.selectedApplications.summary)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundColor(MivoColors.inkMuted)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 6) {
                status
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(MivoColors.inkMuted)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, 18)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var status: some View {
        if isActive {
            SpotActiveBadge()
        } else {
            Text(spot.isSwitchedOffByMivo || !spot.isEnabled ? "Off" : "Ready")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(MivoColors.inkMuted)
        }
    }
}
