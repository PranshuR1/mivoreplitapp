 import SwiftUI

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
                    
                    // Screen Time Tracking
                    if #available(iOS 16.0, *) {
                        screenTimeSection
                            .padding(.bottom, 12)
                    }
                    
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

                    // Device Activity (Screen Time) — request system permission
                    SectionHeader(title: "Device activity")
                        .padding(.bottom, 10)
                    settingsCard {
                        VStack(spacing: 0) {
                            // Clear row that explains this will trigger the system Screen Time / Family Controls prompt
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: "waveform.path.ecg")
                                    .font(.system(size: 18))
                                    .foregroundColor(MivoColors.textSecondary)
                                    .frame(width: 26)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Request Screen Time access")
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundColor(MivoColors.textPrimary)
                                    // Show cached status if available
                                    if let cached = FamilyControlsManager.shared.cachedAuthorizationStatus() {
                                        if cached {
                                            Text("Status: Authorized")
                                                .font(.system(size: 12))
                                                .foregroundColor(MivoColors.accentLight)
                                        } else {
                                            Text("Status: Denied — open Settings to enable")
                                                .font(.system(size: 12))
                                                .foregroundColor(.red)
                                        }
                                    } else {
                                        Text("We need Screen Time access to read device usage so Mivo can give accurate estimates. Tapping will show the system permission prompt.")
                                            .font(.system(size: 12))
                                            .foregroundColor(MivoColors.textMuted)
                                    }
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 14))
                                    .foregroundColor(MivoColors.textMuted)
                            }
                            .padding(16)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                // Call the same request flow but label is user-facing Screen Time language
                                DispatchQueue.main.async {
                                    lastActionLog = "Tapped: Request Screen Time access"
                                    // Perform the request and update cached flag / UI accordingly
                                    FamilyControlsManager.shared.requestAuthorization { granted in
                                        DispatchQueue.main.async {
                                            FamilyControlsManager.shared.saveAuthorizationFlag(granted)
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
                            }
                            
                            // Add an explicit 'Re-check' button for convenience
                            HStack {
                                Spacer()
                                Button(action: {
                                    // Attempt to request again (shows system prompt when possible)
                                    FamilyControlsManager.shared.requestAuthorization { granted in
                                        DispatchQueue.main.async {
                                            FamilyControlsManager.shared.saveAuthorizationFlag(granted)
                                            if granted {
                                                familyControlsMessage = "Screen Time access granted."
                                                showFamilyControlsAlert = true
                                            } else {
                                                familyControlsMessage = "Screen Time access denied. You can enable it in Settings."
                                                showFamilyControlsSettingsAlert = true
                                            }
                                        }
                                    }
                                }) {
                                    Text("Re-check / Request")
                                        .font(.system(size: 14, weight: .semibold))
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .background(MivoColors.accentLight)
                                        .foregroundColor(.white)
                                        .clipShape(RoundedRectangle(cornerRadius: 10))
                                }
                                Spacer()
                            }
                            .padding(.bottom, 6)
                            
                            // If cached status is Denied, offer a Clear & Re-request button to allow a fresh system prompt
                            if FamilyControlsManager.shared.cachedAuthorizationStatus() == false {
                                HStack {
                                    Spacer()
                                    Button(action: {
                                        FamilyControlsManager.shared.clearCachedAuthorizationFlag()
                                        // Slight delay to ensure UI updates
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                            FamilyControlsManager.shared.requestAuthorization { granted in
                                                DispatchQueue.main.async {
                                                    FamilyControlsManager.shared.saveAuthorizationFlag(granted)
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
                                    }) {
                                        Text("Clear & Re-request")
                                            .font(.system(size: 14, weight: .semibold))
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 8)
                                            .background(Color(.systemRed))
                                            .foregroundColor(.white)
                                            .clipShape(RoundedRectangle(cornerRadius: 10))
                                    }
                                    Spacer()
                                }
                                .padding(.bottom, 8)
                            }
                            
                            // If the OS per-app settings don't show Screen Time, offer a guide modal
                            if FamilyControlsManager.shared.cachedAuthorizationStatus() != true {
                                HStack {
                                    Spacer()
                                    Button(action: {
                                        showScreenTimeGuide = true
                                    }) {
                                        Text("How to enable Screen Time")
                                            .font(.system(size: 13, weight: .semibold))
                                            .padding(10)
                                            .background(Color(.systemGray6))
                                            .foregroundColor(MivoColors.textPrimary)
                                            .clipShape(RoundedRectangle(cornerRadius: 10))
                                    }
                                    Spacer()
                                }
                                .padding(.bottom, 8)
                            }
                            
                            rowSeparator()

                            settingsRow(icon: "playpause", label: "Start daily monitoring") {
                                DispatchQueue.main.async {
                                    lastActionLog = "Tapped: Start daily monitoring"
                                    startDailyMonitoring()
                                }
                            }
                            
                            rowSeparator()
                            
                            // Monitoring status
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: "chart.bar.fill")
                                    .font(.system(size: 18))
                                    .foregroundColor(MivoColors.textSecondary)
                                    .frame(width: 26)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Monitoring status")
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundColor(MivoColors.textPrimary)
                                    if #available(iOS 16.0, *), FamilyControlsManager.shared.isMonitoring() {
                                        Text("Active - tracking device usage")
                                            .font(.system(size: 12))
                                            .foregroundColor(MivoColors.accentLight)
                                    } else {
                                        Text("Inactive - tap 'Start daily monitoring' to begin")
                                            .font(.system(size: 12))
                                            .foregroundColor(MivoColors.textMuted)
                                    }
                                }
                                Spacer()
                                if #available(iOS 16.0, *), FamilyControlsManager.shared.isMonitoring() {
                                    Button(action: {
                                        FamilyControlsManager.shared.stopMonitoring()
                                        lastActionLog = "Monitoring stopped"
                                    }) {
                                        Text("Stop")
                                            .font(.system(size: 14, weight: .semibold))
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 6)
                                            .background(Color.red)
                                            .foregroundColor(.white)
                                            .clipShape(RoundedRectangle(cornerRadius: 8))
                                    }
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)

                            rowSeparator()

                            // Show last report preview to the user (if available)
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Last device activity report")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(MivoColors.textSecondary)
                                Text(appVM.lastDeviceActivityReportJSON ?? "No report yet")
                                    .font(.system(size: 12))
                                    .foregroundColor(MivoColors.textPrimary)
                                    .lineLimit(6)
                                    .padding(.vertical, 6)
                                
                                // Show parsed usage if available
                                if let minutes = appVM.deviceActivityMinutesToday {
                                    HStack {
                                        Image(systemName: "clock.fill")
                                            .foregroundColor(MivoColors.accentLight)
                                        Text("Total today: \(minutes) minutes (\(String(format: "%.1f", Double(minutes)/60.0)) hours)")
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundColor(MivoColors.textPrimary)
                                    }
                                    .padding(.vertical, 4)
                                }
                            }
                            .padding(16)
                            
                            #if DEBUG
                            rowSeparator()
                            
                            // View extension logs
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("Extension logs (debug)")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundColor(MivoColors.textSecondary)
                                    Spacer()
                                    Button(action: {
                                        if #available(iOS 16.0, *) {
                                            ScreenTimeDataCollector.shared.clearExtensionLogs()
                                            lastActionLog = "Extension logs cleared"
                                        }
                                    }) {
                                        Text("Clear")
                                            .font(.system(size: 12, weight: .semibold))
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(Color.red.opacity(0.7))
                                            .foregroundColor(.white)
                                            .clipShape(RoundedRectangle(cornerRadius: 6))
                                    }
                                }
                                
                                if #available(iOS 16.0, *) {
                                    let logs = ScreenTimeDataCollector.shared.getExtensionLogs()
                                    if logs.isEmpty {
                                        Text("No extension logs yet")
                                            .font(.system(size: 12))
                                            .foregroundColor(MivoColors.textMuted)
                                    } else {
                                        ScrollView {
                                            VStack(alignment: .leading, spacing: 4) {
                                                ForEach(logs.reversed(), id: \.self) { log in
                                                    Text(log)
                                                        .font(.system(size: 11, design: .monospaced))
                                                        .foregroundColor(MivoColors.textPrimary)
                                                }
                                            }
                                        }
                                        .frame(maxHeight: 150)
                                        .padding(8)
                                        .background(Color.black.opacity(0.05))
                                        .cornerRadius(8)
                                    }
                                } else {
                                    Text("iOS 16.0+ required")
                                        .font(.system(size: 12))
                                        .foregroundColor(MivoColors.textMuted)
                                }
                            }
                            .padding(16)
                            #endif

                            // App Group / entitlement diagnostics (one-tap)
                            rowSeparator()
                            HStack {
                                Image(systemName: "wrench.and.screwdriver")
                                    .foregroundColor(MivoColors.textSecondary)
                                    .frame(width: 20)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Run entitlement diagnostics")
                                        .font(.system(size: 15, weight: .medium))
                                        .foregroundColor(MivoColors.textPrimary)
                                    Text("Check whether the App Group is available and show next steps to fix provisioning.")
                                        .font(.system(size: 12))
                                        .foregroundColor(MivoColors.textMuted)
                                }
                                Spacer()
                                Button(action: {
                                    runAppGroupDiagnostics()
                                }) {
                                    Text("Run")
                                        .font(.system(size: 14, weight: .semibold))
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(MivoColors.accentLight)
                                        .foregroundColor(.white)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)

                            if let log = lastActionLog {
                                Text(log)
                                    .font(.system(size: 12))
                                    .foregroundColor(MivoColors.textMuted)
                                    .padding(.horizontal, 16)
                                    .padding(.bottom, 8)
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
            Text("This will delete your account, credentials, onboarding, sessions, and local app data permanently.")
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
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(MivoColors.border, lineWidth: 1))
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
            HStack {
                Image(systemName: icon)
                    .foregroundColor(MivoColors.textSecondary)
                    .frame(width: 24)
                Text(label)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(MivoColors.textPrimary)
                Spacer()
                if destructive {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundColor(.red)
                        .frame(width: 20)
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
                    // Refresh the report
                    appVM.refreshScreenTimeData()
                case .failure(let error):
                    monitoringMessage = "Failed to start monitoring: \(error.localizedDescription)"
                    showMonitoringAlert = true
                }
            }
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
