import SwiftUI

/// "Connect your Mac" — advertises Mivo for Mac and shows whether this
/// account is already active there. There's no separate pairing code:
/// both apps already share one Supabase account (see
/// `RemoteAuthService`/MivoMac's own `MivoAuthService`), so signing into
/// the same email and password on a Mac *is* the pairing step. This
/// screen's only job is to make that discoverable and show whether it
/// already happened, using `fetchHasMacActivity` — the same signal
/// Mivo for Mac uses in reverse for its own "iPhone today" card.
struct MacPairingSettingsView: View {
    @EnvironmentObject var appVM: AppViewModel

    private enum ConnectionState: Equatable { case checking, connected, notConnected }
    @State private var state: ConnectionState = .checking
    @State private var macSummary: MacActivitySummary?

    var body: some View {
        ZStack {
            MivoColors.background.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    header

                    switch state {
                    case .checking:
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                        .frame(height: 90)
                    case .connected:
                        connectedCard
                        if let macSummary {
                            macActivitySection(macSummary)
                        }
                    case .notConnected:
                        notConnectedCard
                    }
                }
                .padding(20)
            }
        }
        .navigationTitle("Mivo for Mac")
        .navigationBarTitleDisplayMode(.inline)
        .task { await refresh() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: "laptopcomputer")
                .font(.system(size: 26, weight: .semibold))
                .foregroundColor(MivoColors.ink)
            Text("Desktop focus tracking, sessions, and blocking — same account, same history.")
                .font(.system(size: 13.5, weight: .medium))
                .foregroundColor(MivoColors.inkBody)
        }
    }

    private var connectedCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(MivoColors.deep)
            VStack(alignment: .leading, spacing: 3) {
                Text("Connected")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(MivoColors.ink)
                Text("This account is already active on your Mac.")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundColor(MivoColors.inkBody)
            }
            Spacer()
        }
        .padding(16)
        .background(MivoColors.deep.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: MivoMetrics.radius, style: .continuous))
    }

    private var notConnectedCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Not connected yet")
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(MivoColors.ink)
            Text("On your Mac, open Mivo for Mac and sign in with the same email\(appVM.user.map { " (\($0.email))" } ?? "") and password you use here. No pairing code — signing in with the same account connects it automatically.")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(MivoColors.inkBody)
        }
        .padding(16)
        .background(MivoColors.ink.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: MivoMetrics.radius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: MivoMetrics.radius, style: .continuous)
                .strokeBorder(MivoColors.hairline, lineWidth: 1)
        )
    }

    private func macActivitySection(_ summary: MacActivitySummary) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("On your Mac today")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(MivoColors.inkBody)

            HStack(spacing: 24) {
                statColumn(value: "\(summary.totalMinutes)m", label: "TIME OBSERVED")
                statColumn(value: "\(summary.focusMinutes)m", label: "FOCUSED")
                statColumn(value: "\(summary.driftMinutes)m", label: "DRIFT")
                statColumn(value: "\(summary.focusSessionsToday)", label: "SESSIONS")
            }

            if !summary.topApps.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(summary.topApps) { app in
                        HStack {
                            Text(app.name)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(MivoColors.ink)
                            Spacer()
                            Text("\(app.minutes)m")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(MivoColors.inkBody)
                        }
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding(16)
        .background(MivoColors.ink.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: MivoMetrics.radius, style: .continuous))
    }

    private func statColumn(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 17, weight: .bold))
                .foregroundColor(MivoColors.ink)
            Text(label)
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundColor(MivoColors.inkBody.opacity(0.7))
        }
    }

    private func refresh() async {
        guard let email = appVM.user?.email, let record = SecureAuthService.loadRecord(email: email) else {
            state = .notConnected
            return
        }
        let connected = await RemoteAuthService.fetchHasMacActivity(record: record)
        state = connected ? .connected : .notConnected
        if connected {
            macSummary = await RemoteAuthService.fetchMacActivitySummary(record: record)
        }
    }
}
