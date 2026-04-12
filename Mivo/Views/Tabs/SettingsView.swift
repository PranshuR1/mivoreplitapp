import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appVM: AppViewModel
    @State private var notificationsOn = false
    @State private var showResetAlert = false
    @State private var showLogoutAlert = false
    @State private var showWeeklyReport = false
    @State private var showIntervention = false
    @State private var isExporting = false
    // Reuse a selection / impact haptic generator locally to avoid repeated allocations
    private let localSelectionGenerator = UISelectionFeedbackGenerator()
    private let localImpactGenerator = UIImpactFeedbackGenerator(style: .medium)

    var body: some View {
        ZStack {
            MivoColors.background.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Settings")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundColor(MivoColors.textPrimary)
                        .tracking(-0.8)
                        .padding(.bottom, 20)

                    // Profile card
                    HStack(spacing: 14) {
                        ZStack {
                            Circle()
                                .fill(MivoColors.accent)
                                .frame(width: 46, height: 46)
                            Text(String(appVM.user?.name.prefix(1).uppercased() ?? "?"))
                                .font(.system(size: 20, weight: .bold))
                                .foregroundColor(MivoColors.white)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(appVM.user?.name ?? "Anonymous")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(MivoColors.textPrimary)
                            Text(appVM.user?.email ?? "")
                                .font(.system(size: 13))
                                .foregroundColor(MivoColors.textSecondary)
                        }
                        Spacer()
                    }
                    .padding(16)
                    .background(MivoColors.card)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(MivoColors.border, lineWidth: 1))
                    .padding(.bottom, 16)

                    // Stats
                    HStack {
                        statCell(value: "\(appVM.sessions.count)", label: "Sessions")
                        Divider().frame(height: 40).background(MivoColors.border)
                        statCell(value: totalTimeLabel, label: "Total tracked")
                        Divider().frame(height: 40).background(MivoColors.border)
                        statCell(value: "\(appVM.truthChecks.count)", label: "Truth checks")
                    }
                    .padding(16)
                    .background(MivoColors.card)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(MivoColors.border, lineWidth: 1))
                    .padding(.bottom, 28)

                    // Preferences
                    SectionHeader(title: "Preferences")
                        .padding(.bottom, 10)
                    settingsCard {
                        HStack {
                            HStack(spacing: 12) {
                                Image(systemName: "bell")
                                    .foregroundColor(MivoColors.textSecondary)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text("Daily reminders")
                                        .font(.system(size: 15, weight: .medium))
                                        .foregroundColor(MivoColors.textPrimary)
                                    Text("Nudge to log sessions")
                                        .font(.system(size: 12))
                                        .foregroundColor(MivoColors.textMuted)
                                }
                            }
                            Spacer()
                            Toggle("", isOn: $notificationsOn)
                                .tint(MivoColors.accentLight)
                                .labelsHidden()
                        }
                        .padding(16)
                    }
                    .padding(.bottom, 24)

                    // Data
                    SectionHeader(title: "Data")
                        .padding(.bottom, 10)

                    settingsCard {
                        VStack(spacing: 0) {
                            settingsRow(icon: "arrow.down.to.line", label: "Export data") {
                                Task {
                                    await exportDataAsync()
                                }
                            }
                            rowSeparator()
                            // Inline navigation link for Weekly report
                            NavigationLink {
                                WeeklyReportView()
                            } label: {
                                HStack {
                                    Image(systemName: "calendar")
                                        .font(.system(size: 16))
                                        .foregroundColor(MivoColors.textSecondary)
                                        .frame(width: 20)
                                    Text("Weekly report")
                                        .font(.system(size: 15, weight: .medium))
                                        .foregroundColor(MivoColors.textPrimary)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 14))
                                        .foregroundColor(MivoColors.textMuted)
                                }
                                .padding(16)
                            }
                            rowSeparator()
                            NavigationLink {
                                InterventionView(intention: nil, duration: nil)
                            } label: {
                                HStack {
                                    Image(systemName: "shield")
                                        .font(.system(size: 16))
                                        .foregroundColor(MivoColors.textSecondary)
                                        .frame(width: 20)
                                    Text("Intervention preview")
                                        .font(.system(size: 15, weight: .medium))
                                        .foregroundColor(MivoColors.textPrimary)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 14))
                                        .foregroundColor(MivoColors.textMuted)
                                }
                                .padding(16)
                            }
                        }
                    }
                    .padding(.bottom, 24)

                    // Account
                    SectionHeader(title: "Account")
                        .padding(.bottom, 10)
                    settingsCard {
                        VStack(spacing: 0) {
                            settingsRow(icon: "rectangle.portrait.and.arrow.right", label: "Sign out", destructive: true) {
                                showLogoutAlert = true
                            }
                            rowSeparator()
                            settingsRow(icon: "trash", label: "Reset all data", destructive: true) {
                                showResetAlert = true
                            }
                        }
                    }
                    .padding(.bottom, 24)

                    Text("Mivo · Data stays on your device")
                        .font(.system(size: 12))
                        .foregroundColor(MivoColors.textMuted)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.bottom, 100)
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
            }
        }
        .navigationBarHidden(true)
        .alert("Sign out", isPresented: $showLogoutAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Sign out", role: .destructive) { appVM.logout() }
        } message: {
            Text("You'll need to sign in again.")
        }
        .alert("Reset data", isPresented: $showResetAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Delete all data", role: .destructive) { appVM.resetAllData() }
        } message: {
            Text("This will delete all sessions and truth checks permanently. Your account stays.")
        }
    }

    @ViewBuilder
    func statCell(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(MivoColors.textPrimary)
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(MivoColors.textMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    func settingsCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .background(MivoColors.card)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(MivoColors.border, lineWidth: 1))
            .clipped()
    }

    @ViewBuilder
    func settingsRow(icon: String, label: String, destructive: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: {
            // quick selection haptic and perform action
            localSelectionGenerator.selectionChanged()
            action()
        }) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundColor(destructive ? MivoColors.timerRed : MivoColors.textSecondary)
                    .frame(width: 20)
                Text(label)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(destructive ? MivoColors.timerRed : MivoColors.textPrimary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 14))
                    .foregroundColor(MivoColors.textMuted)
            }
            .padding(16)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    func rowSeparator() -> some View {
        Rectangle()
            .fill(MivoColors.border)
            .frame(height: 1)
            .padding(.leading, 48)
    }

    var totalTimeLabel: String {
        let total = appVM.sessions.reduce(0) { $0 + $1.actualDuration }
        let h = total / 60; let m = total % 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }

    func exportData() {
        // Keep legacy synchronous export but offload heavy work to background
        DispatchQueue.global(qos: .userInitiated).async {
            let data = appVM.exportData()
            DispatchQueue.main.async {
                let av = UIActivityViewController(activityItems: [data], applicationActivities: nil)
                if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                   let vc = scene.windows.first?.rootViewController {
                    vc.present(av, animated: true)
                }
            }
        }
    }

    // New async export that uses AppViewModel's exportDataAsync to avoid blocking UI
    func exportDataAsync() async {
        guard !isExporting else { return }
        isExporting = true
        localImpactGenerator.prepare()
        localImpactGenerator.impactOccurred()
        let data = await appVM.exportDataAsync()
        // present activity controller on main thread
        await MainActor.run {
            let av = UIActivityViewController(activityItems: [data], applicationActivities: nil)
            if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let vc = scene.windows.first?.rootViewController {
                vc.present(av, animated: true) {
                    // small release haptic
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
            }
            isExporting = false
        }
    }
}
