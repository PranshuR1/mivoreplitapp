import SwiftUI

#if canImport(FamilyControls)
import FamilyControls
#endif

struct SettingsView: View {
    @EnvironmentObject var appVM: AppViewModel
    @State private var notificationsOn = false
    @State private var showResetAlert = false
    @State private var showLogoutAlert = false
    @State private var showWeeklyReport = false
    @State private var showIntervention = false
    @State private var isExporting = false
    @State private var familyControlsMessage: String? = nil
    @State private var showFamilyControlsAlert: Bool = false
    @State private var showFamilyControlsSettingsAlert: Bool = false
    @State private var showMonitoringAlert: Bool = false
    @State private var monitoringMessage: String? = nil
    @State private var lastActionLog: String? = nil
    @State private var showScreenTimeGuide: Bool = false
    @State private var provisioningDiagnostics: String? = nil
    @State private var showProvisioningDiagnosticsSheet: Bool = false
    @State private var impulseProtectionEnabled = FamilyControlsManager.shared.isImpulseProtectionEnabled()
    @State private var aiProtectedAppRecommendation: ProtectedAppRecommendation?
    @State private var aiProtectedAppLoading = false
    @State private var interventionSelectionSummaryText = "Checking selected apps..."
    @State private var monitoringActiveState = false
    @State private var cachedScreenTimeAuthorization = FamilyControlsManager.shared.cachedAuthorizationStatus()
    @State private var accountabilityEnabled = false
    @State private var accountabilityShareText = ""
    @State private var firstScrollStartHour = 14
    @State private var secondScrollStartHour = 20
    @State private var adminUsers: [AdminUser] = []
    @State private var adminLoading = false
    @State private var adminMessage: String? = nil
    @State private var adminDeleteCandidate: AdminUser? = nil
    @State private var blockerSelfTestRunning = false
    @State private var blockerSelfTestMessage: String? = nil
    @State private var showBlockerSelfTestAlert = false
    @State private var showBlockerDiagnosticsSheet = false
    #if DEBUG
    @State private var extensionLogs: [String] = []
    #endif
    #if canImport(FamilyControls)
    @State private var impulseSelection = FamilyActivitySelection()
    @State private var showImpulsePicker = false
    #endif
    // Reuse a selection / impact haptic generator locally to avoid repeated allocations
    private let localSelectionGenerator = UISelectionFeedbackGenerator()
    private let localImpactGenerator = UIImpactFeedbackGenerator(style: .medium)

    var body: some View {
        ZStack {
            MivoColors.background.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    settingsHeader

                    settingsSection("Account") {
                        accountSummaryRow
                    }

                    if appVM.isAdminUser {
                        settingsSection("Admin") {
                            adminPanel
                        }
                    }

                    settingsSection("Preferences") {
                        dailyReminderRow
                        rowSeparator()
                        interventionRows
                    }

                    settingsSection("Accountability & Rules") {
                        accountabilityRow
                        rowSeparator()
                        scrollScheduleRows
                        rowSeparator()
                        appRulesRows
                    }

                    settingsSection("Screen Time") {
                        screenTimeAccessRow
                        rowSeparator()
                        monitoringRow
                        rowSeparator()
                        blockerSelfTestRow
                    }

                    settingsSection("Reports") {
                        settingsNavigationRow(icon: "calendar", title: "Weekly report", subtitle: "Review your weekly pattern") {
                            WeeklyReportView()
                        }
                        rowSeparator()
                        settingsNavigationRow(icon: "shield", title: "Intervention preview", subtitle: "Practice the 5-second pause") {
                            InterventionView(intention: nil, duration: nil)
                        }
                        rowSeparator()
                        settingsActionRow(icon: "arrow.down.to.line", title: "Export data", subtitle: "Prepare your local Mivo data") {
                            Task { await exportDataAsync() }
                        }
                    }

                    settingsSection("Advanced") {
                        deviceReportRow
                        #if DEBUG
                        rowSeparator()
                        extensionLogsRow
                        #endif
                        rowSeparator()
                        diagnosticsRow
                    }

                    settingsSection("Danger Zone") {
                        settingsActionRow(icon: "rectangle.portrait.and.arrow.right", title: "Sign out", subtitle: "Return to the login screen", destructive: true) {
                            showLogoutAlert = true
                        }
                        rowSeparator()
                        settingsActionRow(icon: "trash", title: "Reset all data", subtitle: "Delete local account, sessions, and settings", destructive: true) {
                            showResetAlert = true
                        }
                    }

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
        .onAppear {
            refreshSettingsSnapshot()
            applyImpulseProtectionAfterRender()
            refreshProtectedAppRecommendation()
            if appVM.isAdminUser {
                Task { await refreshAdminUsers() }
            }
        }
        #if canImport(FamilyControls)
        .familyActivityPicker(isPresented: $showImpulsePicker, selection: $impulseSelection)
        .onChange(of: impulseSelection) { _, newValue in
            if #available(iOS 16.0, *) {
                FamilyControlsManager.shared.saveFamilyActivitySelection(newValue)
                if FamilyControlsManager.shared.hasImpulseSelection() {
                    impulseProtectionEnabled = true
                    FamilyControlsManager.shared.setImpulseProtectionEnabled(true)
                }
                refreshSettingsSnapshot()
            }
        }
        #endif
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
            Text("This will delete your account, credentials, onboarding, sessions, and local app data permanently.")
        }
        .alert(item: $adminDeleteCandidate) { user in
            Alert(
                title: Text("Delete user?"),
                message: Text("Delete \(user.email) from the online Mivo database? This cannot be undone."),
                primaryButton: .destructive(Text("Delete")) {
                    Task { await deleteAdminUser(user) }
                },
                secondaryButton: .cancel()
            )
        }
        // Simple status alert for informational messages
        .alert("Family Controls", isPresented: $showFamilyControlsAlert, actions: {
            Button("OK", role: .cancel) {}
        }, message: {
            Text(familyControlsMessage ?? "")
        })
        // If denied or needs Settings, offer to open the app Settings page
        .alert("Family Controls", isPresented: $showFamilyControlsSettingsAlert) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    DispatchQueue.main.async {
                        UIApplication.shared.open(url)
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(familyControlsMessage ?? "To enable Screen Time permissions, open Settings → Screen Time or the app settings and grant Family Controls access.")
        }
        // Show result of monitoring scheduling
        .alert("Monitoring", isPresented: $showMonitoringAlert, actions: {
            Button("OK", role: .cancel) {}
        }, message: {
            Text(monitoringMessage ?? "")
        })
        // Blocker self-test alert
        .alert("Blocker Self-Test", isPresented: $showBlockerSelfTestAlert, actions: {
            Button("OK", role: .cancel) {}
        }, message: {
            Text(blockerSelfTestMessage ?? "")
        })
        // Blocker diagnostics sheet
        .sheet(isPresented: $showBlockerDiagnosticsSheet) {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(FamilyControlsManager.shared.getBlockerSelfTestDiagnostics())
                            .font(.system(size: 14, design: .monospaced))
                            .foregroundColor(MivoColors.textPrimary)
                            .padding()
                        
                        Text("How to Test:")
                            .font(.system(size: 16, weight: .bold))
                            .padding(.horizontal)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("1. Tap 'Test' button in Settings")
                            Text("2. Leave Mivo app (home screen)")
                            Text("3. Stop/kill Xcode if running")
                            Text("4. Wait 15+ seconds")
                            Text("5. Reopen Mivo and check this screen")
                        }
                        .font(.system(size: 14))
                        .foregroundColor(MivoColors.textSecondary)
                        .padding(.horizontal)
                        
                        Spacer()
                    }
                }
                .navigationTitle("Blocker Diagnostics")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            showBlockerDiagnosticsSheet = false
                        }
                    }
                }
            }
        }
        // Screen Time guide sheet
        .sheet(isPresented: $showScreenTimeGuide) {
            VStack(spacing: 16) {
                Text("Enable Screen Time / Family Controls")
                    .font(.system(size: 20, weight: .bold))
                    .padding(.top, 20)
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("If you don't see Screen Time on the app's page in iOS Settings, follow these steps:")
                            .font(.system(size: 16, weight: .semibold))
                        Text("1. Make sure you're running the app on a real iPhone (not Simulator).\n2. In Xcode, confirm the main app target has the 'Family Controls' capability and the same App Group ('group.com.mivo.mivoapp') as any Device Activity extension.\n3. If you changed capabilities, reinstall the app from Xcode so entitlements are applied.\n4. Open this app and tap 'Re-check / Request' to trigger the system permission dialog.\n5. If the dialog was denied, tap 'Open App Settings' below and enable permissions or reinstall after fixing provisioning.")
                            .font(.system(size: 14))
                        Text("Notes:")
                            .font(.system(size: 15, weight: .semibold))
                        Text("• The Screen Time / Family Controls permission is surfaced by a system prompt — it won't always appear in the per-app toggles like Camera/Microphone.\n• The app must be signed with the Family Controls entitlement and the App Group for the system to allow the prompt.")
                            .font(.system(size: 14))
                    }
                    .padding()
                }
                HStack(spacing: 12) {
                    Button("Open App Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    #if DEBUG
                    Button("Open Screen Time settings (Debug)") {
                        // This URL scheme is for debugging only. It may not be App Store-safe but helps when testing locally.
                        if let url = URL(string: "App-Prefs:root=SCREEN_TIME") {
                            if UIApplication.shared.canOpenURL(url) {
                                UIApplication.shared.open(url)
                            } else if let alt = URL(string: "App-Prefs:root=Privacy&path=SCREEN_TIME") {
                                UIApplication.shared.open(alt)
                            }
                        }
                    }
                    .buttonStyle(.bordered)
                    #endif
                    Button("Close", role: .cancel) {
                        showScreenTimeGuide = false
                    }
                }
                .padding(.bottom, 24)
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showProvisioningDiagnosticsSheet) {
            VStack(spacing: 16) {
                Text("Provisioning Diagnostics")
                    .font(.system(size: 20, weight: .bold))
                    .padding(.top, 20)
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(provisioningDiagnostics ?? "No diagnostics available.")
                            .font(.system(size: 14, weight: .regular))
                            .foregroundColor(MivoColors.textPrimary)
                            .padding()
                            .background(MivoColors.card)
                            .cornerRadius(12)
                            .padding(.horizontal, 16)
                    }
                }
                .padding(.bottom, 20)
                Button(action: {
                    copyProvisioningDiagnosticsToClipboard()
                }) {
                    Text("Copy to Clipboard")
                        .font(.system(size: 16, weight: .semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(MivoColors.accentLight)
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .padding(.bottom, 16)
                Button("Close", role: .cancel) {
                    showProvisioningDiagnosticsSheet = false
                }
            }
            .presentationDetents([.medium, .large])
        }
    }

    // MARK: - Helpers

    private var settingsHeader: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Settings")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundColor(MivoColors.textPrimary)
                .tracking(-0.5)
            Text("Account, protection, and Screen Time settings.")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(MivoColors.textSecondary)
        }
        .padding(.top, 4)
        .padding(.bottom, 4)
    }

    private var accountSummaryRow: some View {
        HStack(spacing: 13) {
            ZStack {
                Circle()
                    .fill(MivoColors.accent)
                    .frame(width: 44, height: 44)
                Text(String(appVM.user?.name.prefix(1).uppercased() ?? "?"))
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(MivoColors.heroText)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(appVM.user?.name ?? "Anonymous")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(MivoColors.textPrimary)
                HStack(spacing: 6) {
                    Text(appVM.user?.email ?? "No email")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(MivoColors.textSecondary)
                        .lineLimit(1)
                    if appVM.isAdminUser {
                        Text("ADMIN")
                            .font(.system(size: 9, weight: .black))
                            .foregroundColor(MivoColors.heroText)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(MivoColors.accent)
                            .clipShape(Capsule())
                    }
                }
            }

            Spacer()
        }
        .padding(15)
    }

    private var adminPanel: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                settingsIcon("person.3.sequence.fill", color: MivoColors.accent)
                rowText(
                    title: "User database",
                    subtitle: adminLoading ? "Loading online users..." : "\(adminUsers.count) online users loaded"
                )
                Spacer()
                Button {
                    Task { await refreshAdminUsers() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(MivoColors.accent)
                        .frame(width: 34, height: 34)
                        .background(MivoColors.background)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(adminLoading)
            }
            .padding(15)

            if let adminMessage {
                rowSeparator()
                Text(adminMessage)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(MivoColors.textSecondary)
                    .lineSpacing(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(15)
            }

            if !adminUsers.isEmpty {
                rowSeparator()
                VStack(spacing: 0) {
                    ForEach(adminUsers) { user in
                        adminUserRow(user)
                        if user.id != adminUsers.last?.id {
                            rowSeparator()
                        }
                    }
                }
            }
        }
    }

    private func adminUserRow(_ user: AdminUser) -> some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                Circle()
                    .fill(user.isAdmin == true ? MivoColors.accent : MivoColors.background)
                    .frame(width: 38, height: 38)
                Text(String(user.name.prefix(1).uppercased()))
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(user.isAdmin == true ? MivoColors.heroText : MivoColors.textPrimary)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(user.name)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(MivoColors.textPrimary)
                        .lineLimit(1)
                    if user.isAdmin == true {
                        Text("ADMIN")
                            .font(.system(size: 9, weight: .black))
                            .foregroundColor(MivoColors.accent)
                    }
                }
                Text(user.email)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(MivoColors.textSecondary)
                    .lineLimit(1)
                Text(adminUserMeta(user))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(MivoColors.textMuted)
                    .lineLimit(1)
            }

            Spacer()

            if user.isAdmin == true {
                Image(systemName: "lock.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(MivoColors.textMuted)
            } else {
                Button {
                    adminDeleteCandidate = user
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.red)
                        .frame(width: 34, height: 34)
                        .background(Color.red.opacity(0.08))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(15)
    }

    private var dailyReminderRow: some View {
        HStack(spacing: 12) {
            settingsIcon("bell", color: MivoColors.accent)
            rowText(title: "Daily reminders", subtitle: "Nudge to log sessions")
            Spacer()
            Toggle("", isOn: $notificationsOn)
                .tint(MivoColors.accent)
                .labelsHidden()
        }
        .padding(15)
    }

    @ViewBuilder
    private var interventionRows: some View {
        HStack(alignment: .top, spacing: 12) {
            settingsIcon("shield.lefthalf.filled", color: MivoColors.accent)
            rowText(title: "Selected app intervention", subtitle: interventionSelectionSummaryText)
            Spacer()
            Toggle("", isOn: $impulseProtectionEnabled)
                .tint(MivoColors.accent)
                .labelsHidden()
                .onChange(of: impulseProtectionEnabled) { _, enabled in
                    setImpulseProtection(enabled)
                }
        }
        .padding(15)

        rowSeparator()

        protectedAppRecommendationRow

        rowSeparator()

        Button {
            #if canImport(FamilyControls)
            if #available(iOS 16.0, *) {
                showImpulsePicker = true
            }
            #endif
        } label: {
            HStack(spacing: 12) {
                settingsIcon("app.badge.checkmark", color: MivoColors.blue)
                rowText(title: "Change selected apps", subtitle: "Pick which apps get the 5-second Mivo pause")
                Spacer()
                chevron
            }
            .padding(15)
        }
        .buttonStyle(SettingsRowButtonStyle())
    }

    private var protectedAppRecommendationRow: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 12) {
                settingsIcon("sparkles", color: MivoColors.accent)
                rowText(
                    title: aiProtectedAppLoading ? "Mivo is thinking..." : "AI recommendation",
                    subtitle: aiProtectedAppRecommendation?.rationale ?? "Mivo can suggest which apps to choose in the picker"
                )
                Spacer()
            }

            if let recommendation = aiProtectedAppRecommendation {
                HStack(spacing: 7) {
                    ForEach(recommendation.apps.prefix(4), id: \.self) { app in
                        Text(app)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(MivoColors.accent)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 6)
                            .background(MivoColors.accent.opacity(0.1))
                            .clipShape(Capsule())
                    }
                }
                .padding(.leading, 46)
            }
        }
        .padding(15)
    }

    private var screenTimeAccessRow: some View {
        Button {
            requestScreenTimeAccess()
        } label: {
            HStack(spacing: 12) {
                settingsIcon("waveform.path.ecg", color: screenTimeStatusColor)
                rowText(title: "Screen Time access", subtitle: screenTimeStatusText)
                Spacer()
                chevron
            }
            .padding(15)
        }
        .buttonStyle(SettingsRowButtonStyle())
    }

    private var monitoringRow: some View {
        HStack(spacing: 12) {
            settingsIcon("chart.bar.fill", color: monitoringActiveState ? MivoColors.blue : MivoColors.textSecondary)
            rowText(title: "Daily monitoring", subtitle: monitoringActiveState ? "Active - tracking device usage" : "Inactive")
            Spacer()
            if monitoringActiveState {
                Button("Stop") {
                    if #available(iOS 16.0, *) {
                        FamilyControlsManager.shared.stopMonitoring()
                        refreshSettingsSnapshot()
                        lastActionLog = "Monitoring stopped"
                    }
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.red)
            } else {
                Button("Start") {
                    lastActionLog = "Tapped: Start daily monitoring"
                    startDailyMonitoring()
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(MivoColors.accent)
            }
        }
        .padding(15)
    }
    
    private var blockerSelfTestRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                let hasRecent = FamilyControlsManager.shared.hasRecentBlockerSelfTestPass()
                settingsIcon("shield.checkered", color: hasRecent ? MivoColors.green : MivoColors.orange)
                rowText(
                    title: "Blocker self-test",
                    subtitle: hasRecent ? "Verified - blocker is working" : "Not verified recently"
                )
                Spacer()
                Button(blockerSelfTestRunning ? "Running..." : "Test") {
                    runBlockerSelfTest()
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(blockerSelfTestRunning ? MivoColors.textSecondary : MivoColors.accent)
                .disabled(blockerSelfTestRunning)
                
                Button {
                    showBlockerDiagnosticsSheet = true
                } label: {
                    Image(systemName: "info.circle")
                        .font(.system(size: 16))
                        .foregroundColor(MivoColors.accent)
                }
            }
            
            if let log = lastActionLog, log.contains("Blocker") {
                Text(log)
                    .font(.system(size: 11))
                    .foregroundColor(MivoColors.textSecondary)
                    .padding(.leading, 36)
            }
        }
        .padding(15)
    }

    private var accountabilityRow: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                settingsIcon("person.2.wave.2.fill", color: MivoColors.accent)
                rowText(title: "Accountability summary", subtitle: "Create a private weekly share text")
                Spacer()
                Toggle("", isOn: $accountabilityEnabled)
                    .tint(MivoColors.accent)
                    .labelsHidden()
                    .onChange(of: accountabilityEnabled) { _, enabled in
                        appVM.updateAccountabilityEnabled(enabled)
                        accountabilityShareText = appVM.accountabilityShareText()
                    }
            }
            .padding(15)

            if accountabilityEnabled {
                rowSeparator()
                VStack(alignment: .leading, spacing: 10) {
                    Text(accountabilityShareText.isEmpty ? appVM.accountabilityShareText() : accountabilityShareText)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(MivoColors.textSecondary)
                        .lineSpacing(3)
                    Button {
                        let text = appVM.accountabilityShareText()
                        UIPasteboard.general.string = text
                        accountabilityShareText = text
                        lastActionLog = "Accountability summary copied"
                        HapticsService.success()
                    } label: {
                        Label("Copy share text", systemImage: "doc.on.doc")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(MivoColors.accent)
                    }
                    .buttonStyle(.plain)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(15)
            }
        }
    }

    private var scrollScheduleRows: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                settingsIcon("clock.badge.checkmark", color: MivoColors.accent)
                rowText(title: "Scroll sessions", subtitle: appVM.todayScrollScheduleStatusText)
                Spacer()
            }
            .padding(15)

            rowSeparator()
            scrollScheduleStepper(title: "Session 1", hour: $firstScrollStartHour)
            rowSeparator()
            scrollScheduleStepper(title: "Session 2", hour: $secondScrollStartHour)

            Button {
                saveScrollSchedule()
            } label: {
                Label(appVM.isTodayScrollScheduleLocked ? "Locked until tomorrow" : "Lock today’s scroll times", systemImage: appVM.isTodayScrollScheduleLocked ? "lock.fill" : "checkmark.circle.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(MivoColors.accent)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(15)
            }
            .buttonStyle(.plain)
            .disabled(appVM.isTodayScrollScheduleLocked)
            .opacity(appVM.isTodayScrollScheduleLocked ? 0.58 : 1)
        }
    }

    private func scrollScheduleStepper(title: String, hour: Binding<Int>) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(MivoColors.textPrimary)
                Text("\(settingsHourLabel(hour.wrappedValue))-\(settingsHourLabel((hour.wrappedValue + 1) % 24))")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(MivoColors.textMuted)
            }
            Spacer()
            Button { adjustScrollHour(hour, by: -1) } label: {
                Image(systemName: "minus")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(MivoColors.textPrimary)
                    .frame(width: 32, height: 32)
                    .background(MivoColors.background)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(appVM.isTodayScrollScheduleLocked)
            .opacity(appVM.isTodayScrollScheduleLocked ? 0.45 : 1)
            Text(settingsHourLabel(hour.wrappedValue))
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundColor(MivoColors.textPrimary)
                .frame(width: 62)
            Button { adjustScrollHour(hour, by: 1) } label: {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(MivoColors.textPrimary)
                    .frame(width: 32, height: 32)
                    .background(MivoColors.background)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(appVM.isTodayScrollScheduleLocked)
            .opacity(appVM.isTodayScrollScheduleLocked ? 0.45 : 1)
        }
        .padding(15)
        .opacity(appVM.isTodayScrollScheduleLocked ? 0.72 : 1)
    }

    private var appRulesRows: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                settingsIcon("slider.horizontal.3", color: MivoColors.blue)
                rowText(title: "App-specific rules", subtitle: "Exact app identity may fall back to the protected group")
                Spacer()
            }
            .padding(15)

            ForEach(appVM.appInterventionRules) { rule in
                rowSeparator()
                appRuleRow(rule)
            }
        }
    }

    private func appRuleRow(_ rule: AppInterventionRule) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(rule.appName)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(MivoColors.textPrimary)
                Text(rule.mode.rawValue)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(MivoColors.textMuted)
            }
            Spacer()
            Menu {
                ForEach(AppRuleMode.allCases) { mode in
                    Button(mode.rawValue) {
                        var updated = rule
                        updated.mode = mode
                        appVM.updateAppInterventionRule(updated)
                        refreshSettingsSnapshot()
                    }
                }
            } label: {
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(MivoColors.accent)
                    .frame(width: 34, height: 34)
                    .background(MivoColors.background)
                    .clipShape(Circle())
            }
        }
        .padding(15)
    }

    private var deviceReportRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                settingsIcon("doc.text.magnifyingglass", color: MivoColors.textSecondary)
                rowText(title: "Last device report", subtitle: appVM.deviceActivityMinutesToday.map { "\($0) minutes today" } ?? "No report yet")
                Spacer()
            }

            if let report = appVM.lastDeviceActivityReportJSON, !report.isEmpty {
                Text(report)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(MivoColors.textMuted)
                    .lineLimit(4)
                    .padding(.leading, 46)
            }
        }
        .padding(15)
    }

    #if DEBUG
    private var extensionLogsRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                settingsIcon("ladybug", color: MivoColors.textSecondary)
                rowText(title: "Extension logs", subtitle: "Debug information")
                Spacer()
                Button("Clear") {
                    if #available(iOS 16.0, *) {
                        ScreenTimeDataCollector.shared.clearExtensionLogs()
                        lastActionLog = "Extension logs cleared"
                    }
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.red)
            }

            if #available(iOS 16.0, *) {
                if !extensionLogs.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(extensionLogs.suffix(4).reversed(), id: \.self) { log in
                            Text(log)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(MivoColors.textMuted)
                                .lineLimit(2)
                        }
                    }
                    .padding(.leading, 46)
                }
            }
        }
        .padding(15)
    }
    #endif

    private var diagnosticsRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                settingsIcon("wrench.and.screwdriver", color: MivoColors.textSecondary)
                rowText(title: "Entitlement diagnostics", subtitle: "Check App Group and Screen Time setup")
                Spacer()
                Button("Run") {
                    runAppGroupDiagnostics()
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(MivoColors.accent)
            }

            if let log = lastActionLog {
                Text(log)
                    .font(.system(size: 12))
                    .foregroundColor(MivoColors.textMuted)
                    .padding(.leading, 46)
            }
        }
        .padding(15)
    }

    @ViewBuilder
    private func settingsSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .heavy))
                .foregroundColor(MivoColors.textMuted)
                .tracking(0.8)
                .padding(.horizontal, 6)
            settingsCard {
                VStack(spacing: 0) {
                    content()
                }
            }
        }
    }

    private func settingsActionRow(icon: String, title: String, subtitle: String, destructive: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                settingsIcon(icon, color: destructive ? .red : MivoColors.textSecondary)
                rowText(title: title, subtitle: subtitle, destructive: destructive)
                Spacer()
                if destructive {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.red)
                } else {
                    chevron
                }
            }
            .padding(15)
        }
        .buttonStyle(SettingsRowButtonStyle())
    }

    private func settingsNavigationRow<Destination: View>(icon: String, title: String, subtitle: String, @ViewBuilder destination: () -> Destination) -> some View {
        NavigationLink {
            destination()
        } label: {
            HStack(spacing: 12) {
                settingsIcon(icon, color: MivoColors.textSecondary)
                rowText(title: title, subtitle: subtitle)
                Spacer()
                chevron
            }
            .padding(15)
        }
        .buttonStyle(SettingsRowButtonStyle())
    }

    private func rowText(title: String, subtitle: String, destructive: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(destructive ? .red : MivoColors.textPrimary)
            Text(subtitle)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(MivoColors.textMuted)
                .lineLimit(2)
        }
    }

    private func adminUserMeta(_ user: AdminUser) -> String {
        if let lastLogin = user.lastLoginAt, let date = ISO8601DateFormatter().date(from: lastLogin) {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            return "Last login \(formatter.string(from: date))"
        }
        if let created = ISO8601DateFormatter().date(from: user.createdAt) {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .none
            return "Created \(formatter.string(from: created))"
        }
        return "Created \(user.createdAt)"
    }

    @MainActor
    private func refreshAdminUsers() async {
        guard appVM.isAdminUser else { return }
        adminLoading = true
        adminMessage = nil
        do {
            adminUsers = try await appVM.loadAdminUsers()
            adminMessage = adminUsers.isEmpty ? "No users found yet." : "Loaded every account from the online Mivo database."
        } catch {
            adminUsers = []
            adminMessage = "Admin tools need the online Mivo backend running and configured in MIVO_AUTH_API_URL. The admin account can sign in, but user management cannot load without that server."
        }
        adminLoading = false
    }

    @MainActor
    private func deleteAdminUser(_ user: AdminUser) async {
        adminLoading = true
        do {
            try await appVM.deleteAdminUser(email: user.email)
            adminUsers.removeAll { $0.email == user.email }
            adminMessage = "Deleted \(user.email)."
        } catch {
            adminMessage = error.localizedDescription
        }
        adminLoading = false
    }

    private var chevron: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 13, weight: .bold))
            .foregroundColor(MivoColors.textMuted)
    }

    private var screenTimeStatusText: String {
        if let cached = cachedScreenTimeAuthorization {
            return cached ? "Authorized" : "Denied - open Settings to enable"
        }
        return "Tap to request access"
    }

    private var screenTimeStatusColor: Color {
        if let cached = cachedScreenTimeAuthorization {
            return cached ? MivoColors.blue : .red
        }
        return MivoColors.accent
    }

    private func syncScrollScheduleState() {
        let windows = appVM.dailyScrollSchedule()?.windows ?? appVM.onboardingProfile.preferredScrollWindows ?? []
        guard windows.count >= 2 else { return }
        firstScrollStartHour = windows[0].startHour
        secondScrollStartHour = windows[1].startHour
    }

    private func adjustScrollHour(_ hour: Binding<Int>, by delta: Int) {
        guard !appVM.isTodayScrollScheduleLocked else { return }
        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
            hour.wrappedValue = ((hour.wrappedValue + delta) % 24 + 24) % 24
        }
        HapticsService.selection()
    }

    private func saveScrollSchedule() {
        guard !appVM.isTodayScrollScheduleLocked else {
            lastActionLog = "Today’s scroll schedule is already locked. Choose again tomorrow morning."
            HapticsService.warning()
            return
        }
        let windows = [
            ScreenScrollWindow(
                id: "user-session-1",
                title: "Your session 1",
                startHour: firstScrollStartHour,
                endHour: min(24, firstScrollStartHour + 1),
                minutes: 15,
                reason: "You chose this time. Mivo monitors it for 3 days before recommending changes."
            ),
            ScreenScrollWindow(
                id: "user-session-2",
                title: "Your session 2",
                startHour: secondScrollStartHour,
                endHour: min(24, secondScrollStartHour + 1),
                minutes: 15,
                reason: "You chose this time. Mivo monitors it for 3 days before recommending changes."
            )
        ]
        appVM.saveDailyScrollScheduleForToday(windows)
        lastActionLog = "Today’s scroll sessions are locked until tomorrow."
        HapticsService.success()
    }

    private func settingsHourLabel(_ hour: Int) -> String {
        let normalized = ((hour % 24) + 24) % 24
        if normalized == 0 { return "12a" }
        if normalized < 12 { return "\(normalized)a" }
        if normalized == 12 { return "12p" }
        return "\(normalized - 12)p"
    }

    private func refreshSettingsSnapshot() {
        impulseProtectionEnabled = FamilyControlsManager.shared.isImpulseProtectionEnabled()
        cachedScreenTimeAuthorization = FamilyControlsManager.shared.cachedAuthorizationStatus()
        accountabilityEnabled = appVM.settings.accountabilityEnabled == true
        accountabilityShareText = appVM.accountabilityShareText()
        syncScrollScheduleState()
        if #available(iOS 16.0, *) {
            #if canImport(FamilyControls)
            impulseSelection = FamilyControlsManager.shared.loadFamilyActivitySelection()
            #endif
            monitoringActiveState = FamilyControlsManager.shared.isMonitoring()
        } else {
            monitoringActiveState = false
        }
        interventionSelectionSummaryText = currentInterventionSelectionSummary()
        #if DEBUG
        if #available(iOS 16.0, *) {
            extensionLogs = ScreenTimeDataCollector.shared.getExtensionLogs()
        }
        #endif
    }

    private func applyImpulseProtectionAfterRender() {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 150_000_000)
            if #available(iOS 16.0, *) {
                FamilyControlsManager.shared.applyImpulseProtectionIfNeeded()
            }
        }
    }

    private func requestScreenTimeAccess() {
        lastActionLog = "Tapped: Request Screen Time access"
        FamilyControlsManager.shared.requestAuthorization { granted in
            DispatchQueue.main.async {
                FamilyControlsManager.shared.saveAuthorizationFlag(granted)
                refreshSettingsSnapshot()
                if granted {
                    familyControlsMessage = "Screen Time access granted."
                    showFamilyControlsAlert = true
                } else {
                    familyControlsMessage = "Screen Time access denied. You can enable it in Settings."
                    showFamilyControlsSettingsAlert = true
                }
            }
        }
    }

    private var settingsHero: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    Circle()
                        .fill(MivoColors.accent)
                        .frame(width: 54, height: 54)
                    Text(String(appVM.user?.name.prefix(1).uppercased() ?? "?"))
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundColor(MivoColors.heroText)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Settings")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundColor(MivoColors.heroText)
                        .tracking(-0.6)
                    Text(appVM.user?.email ?? "Mivo account")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(MivoColors.heroText.opacity(0.74))
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                }

                Spacer()
                
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(MivoColors.heroText)
                    .frame(width: 42, height: 42)
                    .background(MivoColors.background.opacity(0.14))
                    .clipShape(Circle())
            }

            HStack(spacing: 10) {
                profileStat(value: "\(appVM.sessions.count)", label: "Sessions")
                profileStat(value: totalTimeLabel, label: "Tracked")
                profileStat(value: "\(appVM.truthChecks.count)", label: "Checks")
            }
        }
        .padding(20)
        .background(MivoColors.heroBg)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: MivoColors.textPrimary.opacity(0.11), radius: 18, y: 8)
    }

    private func profileStat(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundColor(MivoColors.heroText)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(MivoColors.heroText.opacity(0.64))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(MivoColors.background.opacity(0.14))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var interventionAppsSection: some View {
        settingsCard {
            VStack(spacing: 0) {
                HStack(alignment: .top, spacing: 12) {
                    settingsIcon("shield.lefthalf.filled", color: MivoColors.accent)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Selected app intervention")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(MivoColors.textPrimary)
                        Text(interventionSelectionSummaryText)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(MivoColors.textSecondary)
                            .lineLimit(2)
                    }

                    Spacer()

                    Toggle("", isOn: $impulseProtectionEnabled)
                        .tint(MivoColors.accent)
                        .labelsHidden()
                        .onChange(of: impulseProtectionEnabled) { _, enabled in
                            setImpulseProtection(enabled)
                        }
                }
                .padding(16)

                rowSeparator()

                Button {
                    #if canImport(FamilyControls)
                    if #available(iOS 16.0, *) {
                        showImpulsePicker = true
                    }
                    #endif
                } label: {
                    HStack(spacing: 12) {
                        settingsIcon("app.badge.checkmark", color: MivoColors.blue)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Change selected apps")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(MivoColors.textPrimary)
                            Text("Pick which apps get the 5-second Mivo pause.")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(MivoColors.textMuted)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(MivoColors.textMuted)
                    }
                    .padding(16)
                }
                .buttonStyle(SettingsRowButtonStyle())
            }
        }
    }

    private func currentInterventionSelectionSummary() -> String {
        #if canImport(FamilyControls)
        if #available(iOS 16.0, *) {
            let selection = FamilyControlsManager.shared.loadFamilyActivitySelection()
            let count = selection.applicationTokens.count + selection.categoryTokens.count + selection.webDomainTokens.count
            if count == 0 {
                return "No apps selected yet. Choose apps here or on the Interventions page."
            }
            let itemLabel = count == 1 ? "selection" : "selections"
            return impulseProtectionEnabled ? "\(count) \(itemLabel) protected with a pause." : "\(count) \(itemLabel) saved, currently off."
        }
        #endif
        return "App selection requires Screen Time support on iOS."
    }

    private func setImpulseProtection(_ enabled: Bool) {
        if #available(iOS 16.0, *) {
            if enabled && !FamilyControlsManager.shared.hasImpulseSelection() {
                impulseProtectionEnabled = false
                #if canImport(FamilyControls)
                showImpulsePicker = true
                #endif
                return
            }
            FamilyControlsManager.shared.setImpulseProtectionEnabled(enabled)
            impulseProtectionEnabled = FamilyControlsManager.shared.isImpulseProtectionEnabled()
            refreshSettingsSnapshot()
        } else {
            impulseProtectionEnabled = false
            refreshSettingsSnapshot()
        }
    }

    private func refreshProtectedAppRecommendation() {
        aiProtectedAppLoading = true
        Task {
            let recommendation = await AIService.recommendProtectedApps(
                profile: appVM.onboardingProfile,
                selectedApps: appVM.onboardingProfile.preferredApps,
                recentSessionSummary: AIDataStore.recentSummary(limit: 4)
            )
            await MainActor.run {
                aiProtectedAppRecommendation = recommendation
                aiProtectedAppLoading = false
            }
        }
    }

    private func settingsIcon(_ icon: String, color: Color) -> some View {
        Image(systemName: icon)
            .font(.system(size: 15, weight: .bold))
            .foregroundColor(color)
            .frame(width: 34, height: 34)
            .background(color.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
    }

    private var totalTimeLabel: String {
        // Sessions store their runtime in `actualDuration` (minutes/seconds depending on model)
        let totalSeconds = appVM.sessions.reduce(0) { $0 + $1.actualDuration }
        return totalSeconds.secondsToHoursMinutesSeconds()
     }
    
    // Screen Time Section (iOS 16+)
    @available(iOS 16.0, *)
    @ViewBuilder
    private var screenTimeSection: some View {
        let collector = ScreenTimeDataCollector.shared
        
        settingsCard {
            Button {
                if collector.authorizationStatus == .authorized {
                    // Show Screen Time usage view
                    showScreenTimeGuide = true
                } else {
                    // Show authorization prompt
                    showScreenTimeGuide = true
                }
            } label: {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(statusColor(for: collector.authorizationStatus).opacity(0.14))
                            .frame(width: 40, height: 40)
                        
                        Image(systemName: statusIcon(for: collector.authorizationStatus))
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(statusColor(for: collector.authorizationStatus))
                    }
                    
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Screen Time Tracking")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(MivoColors.textPrimary)
                        Text(statusText(for: collector.authorizationStatus))
                            .font(.system(size: 12))
                            .foregroundColor(MivoColors.textSecondary)
                    }
                    
                    Spacer()
                    
                    if collector.isMonitoring {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 8, height: 8)
                            Text("Active")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.green)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.green.opacity(0.12))
                        .clipShape(Capsule())
                    }
                    
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(MivoColors.textMuted)
                }
                .padding(16)
            }
            .buttonStyle(.plain)
        }
        .sheet(isPresented: $showScreenTimeGuide) {
            if collector.authorizationStatus == .authorized {
                NavigationStack {
                    ScreenTimeUsageView()
                        .environmentObject(appVM)
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Done") {
                                    showScreenTimeGuide = false
                                }
                            }
                        }
                }
            } else {
                NavigationStack {
                    VStack(spacing: 18) {
                        Image(systemName: "waveform.path.ecg")
                            .font(.system(size: 36, weight: .semibold))
                            .foregroundColor(MivoColors.accent)
                        Text("Enable Screen Time")
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .foregroundColor(MivoColors.textPrimary)
                        Text("Mivo uses Apple’s Family Controls permission to show real Screen Time reports.")
                            .font(.system(size: 15))
                            .foregroundColor(MivoColors.textSecondary)
                            .multilineTextAlignment(.center)
                            .lineSpacing(4)
                        Button {
                            Task {
                                _ = await appVM.requestScreenTimeAccessAndRefresh()
                                showScreenTimeGuide = false
                            }
                        } label: {
                            Text("Allow Screen Time")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(MivoColors.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 15)
                                .background(MivoColors.accent)
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(MivoColors.background)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") {
                                showScreenTimeGuide = false
                            }
                        }
                    }
                }
            }
        }
    }
    
    @available(iOS 16.0, *)
    private func statusColor(for status: MivoScreenTimeAuthorizationStatus) -> Color {
        switch status {
        case .authorized:
            return MivoColors.blue
        case .denied:
            return Color.red
        case .notDetermined:
            return MivoColors.accent
        case .unavailable:
            return MivoColors.muted
        }
    }
    
    @available(iOS 16.0, *)
    private func statusIcon(for status: MivoScreenTimeAuthorizationStatus) -> String {
        switch status {
        case .authorized:
            return "checkmark.circle.fill"
        case .denied:
            return "xmark.circle.fill"
        case .notDetermined:
            return "clock.badge.questionmark"
        case .unavailable:
            return "exclamationmark.triangle"
        }
    }
    
    @available(iOS 16.0, *)
    private func statusText(for status: MivoScreenTimeAuthorizationStatus) -> String {
        switch status {
        case .authorized:
            return "Real-time iOS data"
        case .denied:
            return "Access denied"
        case .notDetermined:
            return "Tap to enable accurate tracking"
        case .unavailable:
            return "Not available"
        }
    }

    @ViewBuilder
    private func settingsCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) {
            content()
        }
        .background(MivoColors.card)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(MivoColors.border.opacity(0.6), lineWidth: 1))
        .shadow(color: MivoColors.primary.opacity(0.06), radius: 10, y: 4)
    }

    private func statCell(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(MivoColors.textPrimary)
            Text(label)
                .font(.system(size: 13))
                .foregroundColor(MivoColors.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func rowSeparator() -> some View {
        Divider()
            .background(MivoColors.border)
            .padding(.horizontal, 16)
    }

    private func settingsRow(icon: String, label: String, destructive: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                settingsIcon(icon, color: destructive ? Color.red : MivoColors.textSecondary)
                Text(label)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(destructive ? Color.red : MivoColors.textPrimary)
                Spacer()
                if destructive {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundColor(.red)
                        .frame(width: 20)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(MivoColors.textMuted)
                }
            }
            .padding(16)
        }
        .buttonStyle(PlainButtonStyle())
    }

    private func startDailyMonitoring() {
        // First check if we have authorization
        guard FamilyControlsManager.shared.cachedAuthorizationStatus() == true else {
            monitoringMessage = "Please authorize Screen Time access first."
            showMonitoringAlert = true
            return
        }
        
        // Schedule daily monitoring
        FamilyControlsManager.shared.scheduleDailyMonitoring { result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    monitoringMessage = "Daily monitoring started successfully! The app will track your device usage in the background."
                    showMonitoringAlert = true
                    refreshSettingsSnapshot()
                    // Refresh the report
                    appVM.refreshScreenTimeData()
                case .failure(let error):
                    monitoringMessage = "Failed to start monitoring: \(error.localizedDescription)"
                    showMonitoringAlert = true
                }
            }
        }
    }
    
    private func runBlockerSelfTest() {
        // First check authorization
        guard FamilyControlsManager.shared.cachedAuthorizationStatus() == true else {
            blockerSelfTestMessage = "Please authorize Screen Time access first."
            showBlockerSelfTestAlert = true
            return
        }
        
        blockerSelfTestRunning = true
        lastActionLog = "Blocker self-test started - leave app, wait 15s, reopen"
        
        let success = FamilyControlsManager.shared.runBlockerSelfTest()
        
        if success {
            // Schedule a check after 20 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 20) { [self] in
                blockerSelfTestRunning = false
                
                if FamilyControlsManager.shared.hasRecentBlockerSelfTestPass() {
                    lastActionLog = "✅ Blocker self-test PASSED"
                    blockerSelfTestMessage = "Blocker is working correctly! The Device Activity extension called back successfully."
                } else {
                    lastActionLog = "⚠️ Blocker self-test did NOT callback"
                    blockerSelfTestMessage = "Self-test did not receive callback from extension. Check:\n1. Extension is built and signed\n2. Device was restarted after install\n3. Xcode is stopped during test"
                }
                showBlockerSelfTestAlert = true
            }
        } else {
            blockerSelfTestRunning = false
            lastActionLog = "❌ Blocker self-test failed to schedule"
            blockerSelfTestMessage = "Failed to schedule self-test. Device Activity may not be configured properly."
            showBlockerSelfTestAlert = true
        }
    }

    // MARK: - Diagnostics

    private func loadEmbeddedProvisioningPlist() -> [String: Any]? {
        guard let path = Bundle.main.path(forResource: "embedded", ofType: "mobileprovision") else { return nil }
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return nil }
        // The mobileprovision is a CMS container with an XML plist inside. Extract the XML plist substring.
        if let txt = String(data: data, encoding: .utf8) {
            guard let startRange = txt.range(of: "<?xml"), let endRange = txt.range(of: "</plist>", options: .backwards) else { return nil }
            let plistString = String(txt[startRange.lowerBound...endRange.upperBound])
            if let plistData = plistString.data(using: .utf8) {
                if let obj = try? PropertyListSerialization.propertyList(from: plistData, options: [], format: nil) as? [String: Any] {
                    return obj
                }
            }
        }
        return nil
    }

    private func diagnosticsFromEmbeddedProvisioning() -> String {
        var lines: [String] = []
        lines.append("Embedded provisioning diagnostics")
        lines.append("Timestamp: \(ISO8601DateFormatter().string(from: Date()))")

        if let plist = loadEmbeddedProvisioningPlist() {
            lines.append("Found embedded.mobileprovision in app bundle.")
            if let ent = plist["Entitlements"] as? [String: Any] {
                lines.append("\nEntitlements:")
                if let appGroups = ent["com.apple.security.application-groups"] as? [String] {
                    lines.append("  App Groups:")
                    for g in appGroups { lines.append("    - \(g)") }
                } else {
                    lines.append("  App Groups: (none)")
                }
                if let _ = ent["com.apple.developer.family-controls"] {
                    lines.append("  Family Controls entitlement: PRESENT")
                } else {
                    lines.append("  Family Controls entitlement: MISSING")
                }
                if let team = ent["com.apple.developer.team-identifier"] as? String {
                    lines.append("  Team identifier: \(team)")
                }
                if let appId = ent["application-identifier"] as? String {
                    lines.append("  Application identifier: \(appId)")
                }
                if let keychains = ent["keychain-access-groups"] as? [String] {
                    lines.append("  Keychain groups: \(keychains.joined(separator: ", "))")
                }
            } else {
                lines.append("No Entitlements key found inside provisioning plist.")
            }

            // If there is an optional Name / TeamName
            if let name = plist["Name"] as? String { lines.append("Profile Name: \(name)") }
            if let uuid = plist["UUID"] as? String { lines.append("Profile UUID: \(uuid)") }

        } else {
            lines.append("No embedded.mobileprovision found in app bundle or parsing failed.")
            lines.append("Note: On a device installed from TestFlight / App Store the embedded profile may not be accessible.")
        }

        // Also include the on-disk App Group availability check using UserDefaults(suiteName:)
        let appGroup = FamilyControlsManager.shared.appGroup
        if let ud = UserDefaults(suiteName: appGroup) {
            lines.append("\nApp Group suite available at runtime: YES (suiteName=\(appGroup))")
            if let _ = ud.string(forKey: "mivo.lastDeviceActivityReport") {
                lines.append("Found a lastDeviceActivityReport in the app group.")
            } else {
                lines.append("No lastDeviceActivityReport found in the app group (extension may not have written yet).")
            }
        } else {
            lines.append("\nApp Group suite available at runtime: NO (suiteName=\(appGroup))")
            lines.append("The app is falling back to UserDefaults.standard. Common causes: App Group not added to App ID or provisioning profile missing the group.")
        }

        // Cached family controls value
        if let cached = FamilyControlsManager.shared.cachedAuthorizationStatus() {
            lines.append("\nCached Family Controls authorization: \(cached ? "Authorized" : "Denied")")
        } else {
            lines.append("\nCached Family Controls authorization: Unknown (not requested on this device/install).")
        }

        return lines.joined(separator: "\n")
    }

    private func runAppGroupDiagnostics() {
        // Compose richer diagnostics and present in a sheet so user can copy it.
        var messages: [String] = []
        let group = FamilyControlsManager.shared.appGroup
        if let ud = UserDefaults(suiteName: group) {
            messages.append("App Group suite available: \(group)")
            if let _ = ud.string(forKey: "mivo.lastDeviceActivityReport") {
                messages.append("Found a lastDeviceActivityReport in the app group.")
            } else {
                messages.append("No lastDeviceActivityReport found in the app group (extension may not have written yet).")
            }
        } else {
            messages.append("App Group \(group) NOT available — the app is falling back to UserDefaults.standard.")
            messages.append("Common causes: App Group not registered in Apple Developer portal, App ID not updated, provisioning profile not regenerated, or Xcode did not re-sign the app.")
        }

        // Append embedded provisioning diagnostics
        let prov = diagnosticsFromEmbeddedProvisioning()
        messages.append("\n" + prov)

        provisioningDiagnostics = messages.joined(separator: "\n\n")
        showProvisioningDiagnosticsSheet = true
    }

    private func copyProvisioningDiagnosticsToClipboard() {
        UIPasteboard.general.string = provisioningDiagnostics ?? diagnosticsFromEmbeddedProvisioning()
    }

    private func exportDataAsync() async {
        // Perform data export asynchronously
        // For now, just show a placeholder message
        lastActionLog = "Data export initiated. Check console for file path."
    }

}

extension Int {
    func secondsToHoursMinutesSeconds() -> String {
        let hours = self / 3600
        let minutes = (self % 3600) / 60
        let seconds = self % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }
}

private struct SettingsRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .background(configuration.isPressed ? MivoColors.textPrimary.opacity(0.04) : Color.clear)
            .scaleEffect(configuration.isPressed ? 0.992 : 1)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}
