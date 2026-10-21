import SwiftUI

/// One Spot: what it does, which apps it covers, which Mivo Spot (if any) runs
/// it, its history — and the actions to start, edit, connect or remove it.
struct SpotDetailView: View {
    let spotID: String

    @ObservedObject private var manager = SpotManager.shared
    @Environment(\.dismiss) private var dismiss

    @State private var showEdit = false
    @State private var showPair = false
    @State private var showInstant = false
    @State private var showActive = false
    @State private var confirmDelete = false
    @State private var confirmDisconnect = false
    @State private var confirmDisconnectPhysical = false
    @State private var isDisconnecting = false
    @State private var disconnectError: String?

    var body: some View {
        ZStack {
            MivoColors.background.ignoresSafeArea()

            if let spot = manager.spot(id: spotID) {
                content(spot)
            } else {
                // Deleted from underneath this screen.
                Color.clear.onAppear { dismiss() }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(isPresented: $showEdit) {
            if let spot = manager.spot(id: spotID) {
                SpotSetupFlowView(editing: spot)
            }
        }
        .sheet(isPresented: $showPair) {
            SpotPairSheet(spotID: spotID)
        }
        .sheet(isPresented: $showActive) {
            SpotActiveView()
        }
        .sheet(isPresented: $showInstant) {
            SpotInstantSheet(spotName: manager.spot(id: spotID)?.name ?? "this Spot")
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .confirmationDialog("Delete this Spot?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete Spot", role: .destructive) {
                Task {
                    await manager.deleteSpot(spotID: spotID)
                    dismiss()
                }
            }
            Button("Keep it", role: .cancel) {}
        } message: {
            Text(manager.spot(id: spotID)?.isPhysical == true
                 ? "Its history goes too. Your Mivo Spot is freed, so it can be set up again or passed on."
                 : "Its history goes too.")
        }
        .confirmationDialog("Disconnect this Mivo Spot?", isPresented: $confirmDisconnectPhysical, titleVisibility: .visible) {
            Button("Disconnect", role: .destructive) { disconnectPhysical() }
            Button("Keep it", role: .cancel) {}
        } message: {
            Text("Your Mivo Spot is freed, so it can be set up again or passed on. This Spot stays here as a Digital Spot.")
        }
        .confirmationDialog("Forget the old sticker?", isPresented: $confirmDisconnect, titleVisibility: .visible) {
            Button("Forget it", role: .destructive) { manager.disconnectTag(spotID: spotID) }
            Button("Keep it", role: .cancel) {}
        } message: {
            Text("Mivo forgets the sticker you wrote earlier. The Spot stays, and a Mivo Spot can run it instead.")
        }
    }

    private func content(_ spot: MivoSpot) -> some View {
        let isActive = manager.isActive(spot.id)
        let stats = manager.stats(for: spot.id)
        return ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                header(spot, isActive: isActive)

                testButton(spot, isActive: isActive)
                    .padding(.top, 22)

                SpotSection(title: "What happens here") {
                    VStack(alignment: .leading, spacing: 10) {
                        SpotFact(label: "Mode", value: spot.mode.title)
                        SpotFact(label: spot.mode == .focus ? "Session length" : "Stays on for", value: spot.durationLabel)
                        Text(spot.mode.detail)
                            .font(.system(size: 13.5, weight: .medium))
                            .foregroundColor(MivoColors.inkBody)
                            .lineSpacing(4)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 4)
                    }
                }

                SpotSection(title: "Apps") {
                    SpotAppLabels(selection: spot.selectedApplications)
                }

                SpotSection(title: "Mivo Spot") {
                    mivoSpotBlock(spot)
                }

                SpotSection(title: "History") {
                    historyBlock(spot, stats: stats)
                }

                SpotSection(title: "Spot") {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("This Spot is on")
                                .font(.system(size: 14.5, weight: .semibold))
                                .foregroundColor(MivoColors.ink)
                            Spacer()
                            MivoToggle(
                                isOn: Binding(
                                    get: { spot.isEnabled },
                                    set: { manager.setEnabled($0, spotID: spot.id) }
                                ),
                                label: "This Spot is on"
                            )
                        }
                        Text("Turn it off to keep the Spot without letting a tap start it.")
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundColor(MivoColors.inkMuted)
                    }

                    MivoTertiaryButton(label: "Edit Spot") { showEdit = true }
                        .padding(.top, 8)
                    MivoTertiaryButton(label: "Delete Spot", color: MivoColors.inkBody) { confirmDelete = true }
                }
            }
            .padding(.horizontal, MivoMetrics.screenPadding)
            .padding(.bottom, MivoMetrics.scrollBottomPadding)
        }
    }

    // MARK: Header and test

    private func header(_ spot: MivoSpot, isActive: Bool) -> some View {
        HStack(alignment: .center, spacing: 16) {
            SpotIconView(icon: spot.icon, size: 60)
            VStack(alignment: .leading, spacing: 5) {
                Text(spot.name)
                    .font(.system(size: 27, weight: .bold))
                    .tracking(Font.mivoTracking(-0.025, at: 27))
                    .foregroundColor(MivoColors.ink)
                    .lineLimit(2)
                HStack(spacing: 8) {
                    Text(spot.mode.cardLabel)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(MivoColors.inkBody)
                    if isActive { SpotActiveBadge() }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 14)
    }

    @ViewBuilder
    private func testButton(_ spot: MivoSpot, isActive: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if isActive {
                MivoInkButton(label: "End Spot") {
                    manager.end(reason: .endedManually)
                }
                MivoTertiaryButton(label: "Show the running Spot") { showActive = true }
            } else {
                MivoPrimaryButton(
                    label: spot.isPhysical ? "Test Spot" : "Start Spot",
                    disabled: !spot.isEnabled || spot.isSwitchedOffByMivo
                ) {
                    manager.handleScan(spotID: spot.id, trigger: spot.isPhysical ? .test : .manual)
                }
                Text(testCaption(spot))
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundColor(MivoColors.inkMuted)
            }
        }
    }

    // MARK: Mivo Spot

    private func testCaption(_ spot: MivoSpot) -> String {
        if spot.isSwitchedOffByMivo { return "Mivo has switched this Mivo Spot off." }
        if !spot.isEnabled { return "Turn this Spot on to start it." }
        return spot.isPhysical
            ? "Runs exactly what a tap on your Mivo Spot would do."
            : "Starts this Spot now. Connect a Mivo Spot to start it with a tap."
    }

    private func mivoSpotBlock(_ spot: MivoSpot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let physical = spot.physical {
                HStack(spacing: 8) {
                    Image(systemName: physical.status == .disabled ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(physical.status == .disabled ? MivoColors.inkMuted : MivoColors.kept)
                    Text(physical.status == .disabled ? "Switched off by Mivo" : "Mivo Spot connected")
                        .font(.system(size: 14.5, weight: .semibold))
                        .foregroundColor(MivoColors.ink)
                }
                Text(Self.physicalDetail(physical))
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundColor(MivoColors.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
                if let disconnectError {
                    Text(disconnectError)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundColor(MivoColors.inkBody)
                        .fixedSize(horizontal: false, vertical: true)
                }
                MivoTertiaryButton(label: "Skip the banner when you tap") { showInstant = true }
                MivoTertiaryButton(
                    label: isDisconnecting ? "Disconnecting…" : "Disconnect this Mivo Spot",
                    color: MivoColors.inkBody
                ) {
                    confirmDisconnectPhysical = true
                }
                .disabled(isDisconnecting)
            } else {
                Text("Digital Spot")
                    .font(.system(size: 14.5, weight: .semibold))
                    .foregroundColor(MivoColors.ink)
                Text("This Spot runs from its Start button or a Shortcut. Connect a Mivo Spot and a tap with your iPhone starts it — nothing to set up again.")
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundColor(MivoColors.inkBody)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
                if SpotNFCService.isAvailable {
                    MivoInkButton(label: "Connect a Mivo Spot") { showPair = true }
                        .padding(.top, 6)
                }
                if let tag = spot.tag {
                    Text("An older sticker is also connected. \(SpotDetailView.legacyDetail(tag))")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundColor(MivoColors.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 4)
                    MivoTertiaryButton(label: "Forget the old sticker", color: MivoColors.inkBody) {
                        confirmDisconnect = true
                    }
                }
            }
        }
    }

    private func disconnectPhysical() {
        isDisconnecting = true
        disconnectError = nil
        Task {
            let result = await manager.disconnectPhysicalSpot(spotID: spotID)
            isDisconnecting = false
            if case .failure(let error) = result { disconnectError = error.message }
        }
    }

    static func physicalDetail(_ physical: PhysicalSpotLink) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        var parts = ["ID \(physical.spotID)", "connected \(formatter.string(from: physical.claimedAt))"]
        if let last = physical.lastScannedAt {
            let relative = RelativeDateTimeFormatter()
            relative.unitsStyle = .short
            parts.append("last tapped \(relative.localizedString(for: last, relativeTo: Date()))")
        }
        return parts.joined(separator: " · ")
    }

    static func legacyDetail(_ tag: SpotTagBinding) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return "Connected \(formatter.string(from: tag.connectedAt))."
    }

    // MARK: History

    @ViewBuilder
    private func historyBlock(_ spot: MivoSpot, stats: SpotStats) -> some View {
        let history = manager.sessions(for: spot.id).filter { $0.endDate != nil }
        if history.isEmpty {
            Text("Nothing yet. Each session you finish here is kept so you can see how it goes.")
                .font(.system(size: 13.5, weight: .medium))
                .foregroundColor(MivoColors.inkBody)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                MivoStatColumns(items: [
                    .init(value: "\(stats.sessionCount)", label: stats.sessionCount == 1 ? "session" : "sessions"),
                    .init(value: SpotFormat.compact(minutes: stats.totalActiveMinutes), label: "in this Spot"),
                    .init(value: SpotFormat.compact(minutes: stats.averageSessionMinutes), label: "avg session")
                ])
                .padding(.top, -8)

                if stats.measuredSessionCount > 0 {
                    SpotFact(
                        label: "In selected apps",
                        value: SpotFormat.compact(minutes: stats.measuredDistractingMinutes)
                    )
                }

                VStack(spacing: 0) {
                    ForEach(Array(history.prefix(6).enumerated()), id: \.element.id) { index, session in
                        sessionRow(session)
                        if index < min(history.count, 6) - 1 { MivoHairline(soft: true) }
                    }
                }
                .padding(.top, 10)
            }
        }
    }

    private func sessionRow(_ session: SpotSession) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(Self.dayText(session.startDate))
                    .font(.system(size: 14.5, weight: .semibold))
                    .foregroundColor(MivoColors.ink)
                Spacer()
                Text(SpotFormat.compact(minutes: SpotInsights.minutes(session.activeSeconds())))
                    .font(.system(size: 13.5, weight: .semibold))
                    .monospacedDigit()
                    .foregroundColor(MivoColors.inkBody)
            }
            Text(Self.usageText(session))
                .font(.system(size: 12.5, weight: .medium))
                .foregroundColor(MivoColors.inkMuted)
        }
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }

    static func dayText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, MMM d · h:mm a"
        return formatter.string(from: date)
    }

    static func usageText(_ session: SpotSession) -> String {
        guard session.usageTracked, let usage = session.usage else { return "App time not measured" }
        if usage.totalMinutes == 0 { return "Under a minute in selected apps" }
        return "About \(usage.totalMinutes) min in selected apps"
    }
}
