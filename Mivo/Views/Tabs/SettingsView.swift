import SwiftUI
import Charts
import UserNotifications

#if canImport(FamilyControls)
import FamilyControls
#endif

struct SettingsView: View {
    @EnvironmentObject var appVM: AppViewModel
    @ObservedObject private var expansion = ProductExpansionStore.shared
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
    @State private var lateNightProtectionEnabled = false
    @State private var lateNightStartHour = 22
    @State private var lateNightWakeHour = 7
    @State private var scrollScheduleWindows: [ScreenScrollWindow] = [
        ScreenScrollWindow(id: "settings-session-1", title: "Your session 1", startHour: 14, endHour: 15, minutes: 15, reason: "You chose this time."),
        ScreenScrollWindow(id: "settings-session-2", title: "Your session 2", startHour: 20, endHour: 21, minutes: 15, reason: "You chose this time.")
    ]
    @State private var blockerSelfTestRunning = false
    @State private var blockerSelfTestMessage: String? = nil
    @State private var showBlockerSelfTestAlert = false
    @State private var showBlockerDiagnosticsSheet = false
    @State private var adminPushStatus = "Checking notification access..."
    @State private var showPreSignInPreview = false
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

                    NavigationLink {
                        accountAdvancedSettingsPage
                    } label: {
                        accountSummaryRow
                    }
                    .buttonStyle(SettingsRowButtonStyle())

                    settingsStatusStrip

                    settingsSection("Your plan") {
                        settingsCategoryRow(
                            icon: "calendar.badge.clock",
                            color: MivoColors.accent,
                            title: "Daily schedule",
                            subtitle: "Reminders and today’s scroll windows",
                            destination: { dailyPlanSettingsPage }
                        )
                        rowSeparator()
                        settingsCategoryRow(
                            icon: "moon.stars.fill",
                            color: MivoColors.accent,
                            title: "Late-night protection",
                            subtitle: "Wake time, longer pauses, and last scroll",
                            destination: { dailyPlanSettingsPage }
                        )
                        rowSeparator()
                        settingsCategoryRow(
                            icon: "person.2.fill",
                            color: MivoColors.orange,
                            title: "Accountability",
                            subtitle: "Private weekly summaries and partners",
                            destination: { dailyPlanSettingsPage }
                        )
                    }

                    settingsSection("Protection") {
                        settingsCategoryRow(
                            icon: "shield.lefthalf.filled",
                            color: MivoColors.accent,
                            title: "Selected apps",
                            subtitle: interventionSelectionSummaryText,
                            destination: { protectionSettingsPage }
                        )
                        rowSeparator()
                        settingsCategoryRow(
                            icon: "slider.horizontal.3",
                            color: MivoColors.blue,
                            title: "App-specific rules",
                            subtitle: "Adaptive friction and intervention behavior",
                            destination: { protectionSettingsPage }
                        )
                        if expansion.isEnabled(.mivoClear) {
                            rowSeparator()
                            settingsCategoryRow(
                                icon: "sparkles.rectangle.stack.fill",
                                color: MivoColors.accent,
                                title: "Mivo Clear BETA",
                                subtitle: "Focused Instagram, TikTok, and YouTube",
                                destination: { protectionSettingsPage }
                            )
                        }
                    }

                    settingsSection("Progress & tools") {
                        settingsCategoryRow(
                            icon: "flask.fill",
                            color: MivoColors.blue,
                            title: "Experiments",
                            subtitle: "Start, track, and review seven-day changes",
                            destination: { toolsSettingsPage }
                        )
                        rowSeparator()
                        settingsCategoryRow(
                            icon: "calendar.badge.chartbar",
                            color: MivoColors.accent,
                            title: "Weekly report",
                            subtitle: "Swipe through your recap and weekly statistics",
                            destination: { weeklyReportSettingsPage }
                        )
                        rowSeparator()
                        settingsCategoryRow(
                            icon: "hand.raised.square.fill",
                            color: MivoColors.blue,
                            title: "Privacy Center",
                            subtitle: "Permissions, synced data, export, and deletion",
                            destination: { toolsSettingsPage }
                        )
                    }

                    settingsSection("Preferences") {
                        appearancePreferenceRow
                    }

                    settingsSection("Account") {
                        settingsCategoryRow(
                            icon: "bell.fill",
                            color: MivoColors.accent,
                            title: "Notifications",
                            subtitle: notificationsOn ? "Daily reminders are on" : "Manage reminders and alerts",
                            destination: { dailyPlanSettingsPage }
                        )
                        rowSeparator()
                        settingsCategoryRow(
                            icon: "arrow.down.to.line",
                            color: MivoColors.accent,
                            title: "Data & advanced",
                            subtitle: "Export, diagnostics, sign out, and reset",
                            destination: { accountAdvancedSettingsPage }
                        )
                        rowSeparator()
                        settingsCategoryRow(
                            icon: "questionmark.circle.fill",
                            color: MivoColors.accent,
                            title: "Help & feedback",
                            subtitle: "Report a bug or request a feature",
                            destination: { toolsSettingsPage }
                        )
                    }

                    if appVM.canAccessSuperAdminCenter {
                        settingsSection("Super Admin") {
                            settingsNavigationRow(
                                icon: "rectangle.3.group.fill",
                                title: "Super Admin Center",
                                subtitle: "Full access to users, analytics, campaigns, and security"
                            ) {
                                MivoAdminCenterView()
                                    .environmentObject(appVM)
                            }
                            rowSeparator()
                            settingsNavigationRow(
                                icon: "bell.badge.fill",
                                title: "Announcement drafts",
                                subtitle: "Create, review, publish, or archive announcements"
                            ) {
                                AnnouncementAdminView()
                            }
                            rowSeparator()
                            settingsNavigationRow(
                                icon: "person.3.fill",
                                title: "User database",
                                subtitle: "Search users, review progress, and manage roles"
                            ) {
                                AdminUserDatabaseView()
                            }
                            rowSeparator()
                            settingsActionRow(
                                icon: "app.badge.fill",
                                title: "New-account alerts",
                                subtitle: adminPushStatus
                            ) {
                                if let url = URL(string: UIApplication.openSettingsURLString) {
                                    UIApplication.shared.open(url)
                                }
                            }
                            if appVM.canReplayFounderOnboarding {
                                rowSeparator()
                                settingsActionRow(
                                    icon: "person.crop.circle.badge.questionmark",
                                    title: "Preview before sign-in",
                                    subtitle: "View the first-open story, sign in, registration, and recovery screens"
                                ) {
                                    showPreSignInPreview = true
                                }
                                rowSeparator()
                                settingsActionRow(
                                    icon: "arrow.counterclockwise.circle.fill",
                                    title: "Re-run onboarding",
                                    subtitle: "Experience all 12 steps again without deleting your data"
                                ) {
                                    appVM.startFounderOnboardingReplay()
                                }
                            }
                        }
                    } else if appVM.canManageAnnouncements {
                        settingsSection("Admin") {
                            settingsNavigationRow(
                                icon: "bell.badge.fill",
                                title: "Announcement drafts",
                                subtitle: "Prepare drafts for founder approval"
                            ) {
                                AnnouncementAdminView()
                            }
                        }
                    }

                    if appVM.isAmbassadorUser {
                        settingsSection("Ambassador") {
                            settingsNavigationRow(
                                icon: "person.2.badge.gearshape.fill",
                                title: "Your referrals",
                                subtitle: "People who entered your assigned ambassador name"
                            ) {
                                AmbassadorDashboardView()
                            }
                        }
                    }

                    Text("Mivo \(appVersionText) · Data stays on your device")
                        .font(.system(size: 12))
                        .foregroundColor(MivoColors.textMuted)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.bottom, 100)
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .mivoReadableWidth()
            }
        }
        .navigationBarHidden(true)
        .fullScreenCover(isPresented: $appVM.onboardingReplayActive) {
            OnboardingWelcomeView(replayMode: true)
                .environmentObject(appVM)
        }
        .fullScreenCover(isPresented: $showPreSignInPreview) {
            FounderPreSignInPreviewView()
                .environmentObject(appVM)
        }
        .onAppear {
            refreshSettingsSnapshot()
            applyImpulseProtectionAfterRender()
            refreshProtectedAppRecommendation()
            Task {
                await appVM.refreshServerAdminRole()
                await refreshAdminPushStatus()
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
                            .cornerRadius(8)
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
                        .clipShape(RoundedRectangle(cornerRadius: 8))
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

    private var settingsStatusStrip: some View {
        HStack(spacing: 8) {
            settingsStatusCell(
                title: "Screen Time",
                value: cachedScreenTimeAuthorization == true ? "Ready" : "Needs access",
                icon: cachedScreenTimeAuthorization == true ? "checkmark.shield.fill" : "exclamationmark.shield.fill",
                color: cachedScreenTimeAuthorization == true ? MivoColors.blue : MivoColors.orange
            )
            Divider().overlay(MivoColors.border.opacity(0.4)).padding(.vertical, 10)
            settingsStatusCell(
                title: "Protection",
                value: impulseProtectionEnabled ? "On" : "Off",
                icon: "lock.shield.fill",
                color: impulseProtectionEnabled ? MivoColors.accent : MivoColors.textMuted
            )
            Divider().overlay(MivoColors.border.opacity(0.4)).padding(.vertical, 10)
            settingsStatusCell(
                title: "Today",
                value: appVM.isTodayScrollScheduleLocked ? "Locked" : "Not locked",
                icon: "calendar.badge.clock",
                color: appVM.isTodayScrollScheduleLocked ? MivoColors.green : MivoColors.textMuted
            )
        }
        .mivoC3Section(verticalPadding: 8)
    }

    private func settingsStatusCell(title: String, value: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(color)
            Text(value)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(MivoColors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(MivoColors.textMuted)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
        .padding(12)
    }

    private func settingsCategoryRow(
        icon: String,
        color: Color,
        title: String,
        subtitle: String,
        destination: @escaping () -> AnyView
    ) -> some View {
        NavigationLink {
            destination()
        } label: {
            HStack(spacing: 13) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(color)
                    .frame(width: 40, height: 40)
                    .background(color.opacity(0.11))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                rowText(title: title, subtitle: subtitle)
                Spacer(minLength: 8)
                chevron
            }
            .padding(.vertical, 13)
            .padding(.horizontal, 2)
        }
        .buttonStyle(SettingsRowButtonStyle())
    }

    private var dailyPlanSettingsPage: AnyView {
        AnyView(settingsSubpage(title: "Daily Plan", subtitle: "Shape when Mivo checks in and when scrolling is available.") {
            settingsSection("Reminders") {
                dailyReminderRow
            }
            settingsSection("Late-Night Protection") {
                lateNightProtectionRows
            }
            settingsSection("Accountability") {
                accountabilityRow
            }
            settingsSection("Scroll Schedule") {
                scrollScheduleRows
            }
        })
    }

    private var appearancePreferenceRow: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 13) {
                Image(systemName: "circle.lefthalf.filled")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(MivoColors.blue)
                    .frame(width: 40, height: 40)
                    .background(MivoColors.blue.opacity(0.11))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                rowText(title: "Appearance", subtitle: "System follows your iPhone automatically")
            }

            Picker("Appearance", selection: Binding(
                get: { appVM.appearanceMode },
                set: { mode in
                    appVM.setAppearanceMode(mode)
                    HapticsService.selection()
                }
            )) {
                ForEach(AppAppearanceMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .tint(MivoColors.accent)
            .accessibilityHint("Choose whether Mivo follows the iPhone appearance or always uses light or dark mode")
        }
        .padding(.vertical, 13)
        .padding(.horizontal, 2)
    }

    private var protectionSettingsPage: AnyView {
        AnyView(settingsSubpage(title: "App Protection", subtitle: "Manage protected apps, intervention behavior, and Screen Time access.") {
            if expansion.isEnabled(.mivoClear) {
                settingsSection("Focused Social") {
                    settingsNavigationRow(
                        icon: "sparkles.rectangle.stack.fill",
                        title: "Mivo Clear BETA",
                        subtitle: "Map Instagram, TikTok, and YouTube"
                    ) {
                        MivoClearSettingsView().environmentObject(appVM)
                    }
                }
            }
            settingsSection("Protected Apps") {
                interventionRows
            }
            settingsSection("App Rules") {
                appRulesRows
            }
            settingsSection("Screen Time") {
                screenTimeAccessRow
                rowSeparator()
                monitoringRow
                rowSeparator()
                blockerSelfTestRow
            }
        })
    }

    private var toolsSettingsPage: AnyView {
        AnyView(settingsSubpage(title: "Mivo Tools", subtitle: "Review progress, run experiments, and get support.") {
            settingsSection("Progress & Change") {
                if expansion.isEnabled(.monthlyEffectReport) {
                    settingsNavigationRow(icon: "chart.line.uptrend.xyaxis", title: "Mivo Effect", subtitle: "Your monthly pattern and estimated change") {
                        MonthlyEffectReportView().environmentObject(appVM)
                    }
                }
                if expansion.isEnabled(.monthlyEffectReport) && expansion.isEnabled(.experimentLibrary) {
                    rowSeparator()
                }
                if expansion.isEnabled(.experimentLibrary) {
                    settingsNavigationRow(icon: "flask.fill", title: "Experiments", subtitle: "Start, track, and review seven-day experiments") {
                        ExperimentLibraryView().environmentObject(appVM)
                    }
                }
                if expansion.isEnabled(.experimentLibrary) && expansion.isEnabled(.appPersonalities) {
                    rowSeparator()
                }
                if expansion.isEnabled(.appPersonalities) {
                    settingsNavigationRow(icon: "slider.horizontal.3", title: "App personalities", subtitle: "Set device-local friction for each app") {
                        AppPersonalitiesView().environmentObject(appVM)
                    }
                }
            }

            settingsSection("Privacy & Guidance") {
                if expansion.isEnabled(.accountabilityPartners) {
                    settingsNavigationRow(icon: "person.2.fill", title: "Accountability partner", subtitle: "Share a private weekly summary") {
                        AccountabilityPartnersView().environmentObject(appVM)
                    }
                    rowSeparator()
                }
                settingsNavigationRow(icon: "hand.raised.square.fill", title: "Privacy Center", subtitle: "Permissions, synced data, export, and deletion") {
                    MivoPrivacyCenterView().environmentObject(appVM)
                }
                rowSeparator()
                settingsActionRow(icon: "play.rectangle.fill", title: "Replay app tour", subtitle: "Practice Mivo’s newest tools again") {
                    appVM.restartTutorial()
                }
            }

            settingsSection("Reports & Support") {
                settingsNavigationRow(icon: "calendar", title: "Weekly report", subtitle: "Five-page recap with comparisons and charts") {
                    WeeklyReportView()
                }
                rowSeparator()
                settingsNavigationRow(icon: "shield", title: "Intervention preview", subtitle: "Practice the 5-second pause") {
                    InterventionView(intention: nil, duration: nil)
                }
                rowSeparator()
                settingsNavigationRow(icon: "bubble.left.fill", title: "Send feedback", subtitle: "Report a bug or request a feature") {
                    FeedbackSubmissionView()
                }
            }
        })
    }

    private var weeklyReportSettingsPage: AnyView {
        AnyView(
            WeeklyReportView()
                .environmentObject(appVM)
        )
    }

    private var accountAdvancedSettingsPage: AnyView {
        AnyView(settingsSubpage(title: "Account & Advanced", subtitle: "Manage data, diagnostics, and account access.") {
            settingsSection("Your Data") {
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

            settingsSection("Account Actions") {
                settingsActionRow(icon: "rectangle.portrait.and.arrow.right", title: "Sign out", subtitle: "Return to the login screen", destructive: true) {
                    showLogoutAlert = true
                }
                rowSeparator()
                settingsActionRow(icon: "trash", title: "Reset all data", subtitle: "Delete local account, sessions, and settings", destructive: true) {
                    showResetAlert = true
                }
            }
        })
    }

    private func settingsSubpage<Content: View>(
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        ZStack {
            MivoColors.background.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    Text(subtitle)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(MivoColors.textSecondary)
                        .lineSpacing(3)
                    content()
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 36)
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { refreshSettingsSnapshot() }
    }

    private var settingsHeader: some View {
        HStack(alignment: .top, spacing: 12) {
            MivoLogo(size: 38)
            VStack(alignment: .leading, spacing: 5) {
                Text("Settings")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(MivoColors.textPrimary)
                Text("Your account, plan, and protection.")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(MivoColors.textSecondary)
            }
            Spacer()
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
                    Text(maskedAccountEmail)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(MivoColors.textSecondary)
                        .lineLimit(1)
                    if appVM.accountRole != "user" {
                        Text(roleBadgeText)
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
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(MivoColors.textMuted)
        }
        .padding(.vertical, 14)
        .overlay(alignment: .bottom) {
            Rectangle().fill(MivoColors.border.opacity(0.30)).frame(height: 1)
        }
    }

    private var maskedAccountEmail: String {
        guard let email = appVM.user?.email, let at = email.firstIndex(of: "@") else { return "No email" }
        let local = String(email[..<at])
        let domain = String(email[at...])
        return "\(local.prefix(1))***\(domain)"
    }

    private var appVersionText: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }

    private var roleBadgeText: String {
        switch appVM.accountRole {
        case "super_admin": return "SUPER ADMIN"
        case "admin": return "ADMIN"
        case "ambassador": return "AMBASSADOR"
        default: return "USER"
        }
    }

    @MainActor
    private func refreshAdminPushStatus() async {
        guard appVM.isSuperAdminUser else { return }
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            adminPushStatus = "Enabled on this device"
        case .denied:
            adminPushStatus = "Disabled - tap to open Settings"
        case .notDetermined:
            adminPushStatus = "Not requested yet"
        @unknown default:
            adminPushStatus = "Status unavailable"
        }
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
    private var lateNightProtectionRows: some View {
        HStack(alignment: .top, spacing: 12) {
            settingsIcon("moon.stars.fill", color: MivoColors.blue)
            rowText(
                title: "Protect sleep",
                subtitle: "Use a calmer screen, a longer pause, and one optional last scroll"
            )
            Spacer()
            Toggle("", isOn: $lateNightProtectionEnabled)
                .tint(MivoColors.accent)
                .labelsHidden()
                .onChange(of: lateNightProtectionEnabled) { _, _ in
                    saveLateNightProtection()
                }
        }
        .padding(15)

        if lateNightProtectionEnabled {
            rowSeparator()
            lateNightTimeRow(
                icon: "moonrise.fill",
                title: "Night starts",
                subtitle: "Selected apps get at least a 15-second pause",
                selection: $lateNightStartHour,
                hours: Array(20...23)
            )

            rowSeparator()
            lateNightTimeRow(
                icon: "sunrise.fill",
                title: "Wake-up time",
                subtitle: "Mivo shows this before a late-night scroll",
                selection: $lateNightWakeHour,
                hours: Array(5...10)
            )
        }
    }

    private func lateNightTimeRow(
        icon: String,
        title: String,
        subtitle: String,
        selection: Binding<Int>,
        hours: [Int]
    ) -> some View {
        HStack(spacing: 12) {
            settingsIcon(icon, color: MivoColors.accent)
            rowText(title: title, subtitle: subtitle)
            Spacer()
            Picker(title, selection: selection) {
                ForEach(hours, id: \.self) { hour in
                    Text(settingsHourLabel(hour)).tag(hour)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .tint(MivoColors.accent)
            .onChange(of: selection.wrappedValue) { _, _ in
                saveLateNightProtection()
            }
        }
        .padding(15)
    }

    private func saveLateNightProtection() {
        appVM.updateLateNightProtection(
            enabled: lateNightProtectionEnabled,
            startHour: lateNightStartHour,
            wakeHour: lateNightWakeHour
        )
        HapticsService.selection()
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
            ForEach(scrollScheduleWindows.indices, id: \.self) { index in
                if index > 0 { rowSeparator() }
                scrollScheduleStepper(index: index)
            }

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

    private func scrollScheduleStepper(index: Int) -> some View {
        let window = scrollScheduleWindows[index]
        let duration = max(1, window.endHour - window.startHour)
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Session \(index + 1)")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(MivoColors.textPrimary)
                Text("\(settingsHourLabel(window.startHour))-\(settingsHourLabel(window.endHour)) · \(window.minutes)m allowed · \(duration)h")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(MivoColors.textMuted)
            }
            Spacer()
            Menu {
                ForEach(0...max(0, 24 - duration), id: \.self) { candidate in
                    Button {
                        setScrollWindowStart(at: index, to: candidate)
                    } label: {
                        if candidate == window.startHour {
                            Label(settingsHourLabel(candidate), systemImage: "checkmark")
                        } else {
                            Text(settingsHourLabel(candidate))
                        }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Text(settingsHourLabel(window.startHour))
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 9, weight: .bold))
                }
                .foregroundColor(MivoColors.textPrimary)
                .padding(.horizontal, 10)
                .frame(height: 36)
                .background(MivoColors.background)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
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
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(MivoColors.textMuted)
                .textCase(.uppercase)
                .padding(.horizontal, 2)
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
        let windows = appVM.dailyScrollSchedule()?.windows
            ?? appVM.onboardingProfile.preferredScrollWindows
            ?? appVM.adaptiveScreenTimePlan().windows
        guard !windows.isEmpty else { return }
        scrollScheduleWindows = windows
    }

    private func setScrollWindowStart(at index: Int, to requestedStart: Int) {
        guard !appVM.isTodayScrollScheduleLocked else { return }
        guard scrollScheduleWindows.indices.contains(index) else { return }
        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
            let window = scrollScheduleWindows[index]
            let duration = max(1, window.endHour - window.startHour)
            let maxStart = max(0, 24 - duration)
            let start = min(max(0, requestedStart), maxStart)
            scrollScheduleWindows[index] = ScreenScrollWindow(
                id: window.id,
                title: window.title,
                startHour: start,
                endHour: min(24, start + duration),
                minutes: window.minutes,
                reason: window.reason
            )
        }
        HapticsService.selection()
    }

    private func saveScrollSchedule() {
        guard !appVM.isTodayScrollScheduleLocked else {
            lastActionLog = "Today’s scroll schedule is already locked. Choose again tomorrow morning."
            HapticsService.warning()
            return
        }
        appVM.saveDailyScrollScheduleForToday(scrollScheduleWindows)
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
        lateNightProtectionEnabled = appVM.lateNightProtectionEnabled
        lateNightStartHour = appVM.lateNightStartHour
        lateNightWakeHour = appVM.lateNightWakeHour
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
                        .tracking(-0.6)
                        .foregroundColor(MivoColors.heroText)
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
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
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
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
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
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
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
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
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
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
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
        .overlay(alignment: .top) {
            Rectangle().fill(MivoColors.border.opacity(0.30)).frame(height: 1)
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(MivoColors.border.opacity(0.30)).frame(height: 1)
        }
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
            .padding(.horizontal, 2)
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

private struct FounderPreSignInPreviewView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appVM: AppViewModel
    @State private var showingFirstLaunchStory = true

    var body: some View {
        Group {
            if showingFirstLaunchStory {
                MivoFirstLaunchIntroView(
                    onComplete: {
                        withAnimation(.easeInOut(duration: 0.24)) {
                            showingFirstLaunchStory = false
                        }
                    },
                    onExit: { dismiss() }
                )
                .transition(.opacity)
            } else {
                ZStack(alignment: .top) {
                    LoginView(previewMode: true)
                        .environmentObject(appVM)

                    HStack(spacing: 10) {
                        Text("FOUNDER PREVIEW")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(MivoColors.accent)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 6)
                            .background(MivoColors.card)
                            .clipShape(Capsule())
                            .overlay(Capsule().strokeBorder(MivoColors.border.opacity(0.7), lineWidth: 1))

                        Spacer()

                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(MivoColors.textPrimary)
                                .frame(width: 34, height: 34)
                                .background(MivoColors.card)
                                .clipShape(Circle())
                                .overlay(Circle().strokeBorder(MivoColors.border.opacity(0.7), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Close founder preview")
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 8)
                }
                .transition(.opacity)
            }
        }
        .interactiveDismissDisabled()
    }
}

private enum AdminUserFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case onboarded = "Onboarded"
    case active = "Active"
    case ambassador = "Ambassador"

    var id: String { rawValue }
}

private struct AmbassadorDatabaseFilterOption: Identifiable {
    let id: String
    let name: String
}

struct AdminUserDatabaseView: View {
    @EnvironmentObject private var appVM: AppViewModel
    @State private var users: [AdminCampaignUser] = []
    @State private var searchText = ""
    @State private var filter: AdminUserFilter = .all
    @State private var page = 0
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var ambassadorAssignmentUser: AdminCampaignUser?
    @State private var selectedAmbassadorID = "all"
    @State private var limitsAmbassadorDates = false
    @State private var ambassadorCreatedFrom = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
    @State private var ambassadorCreatedThrough = Date()

    private let pageSize = 25

    private var filteredUsers: [AdminCampaignUser] {
        users.filter { user in
            let matchesSearch = searchText.isEmpty
                || user.name.localizedCaseInsensitiveContains(searchText)
                || user.email.localizedCaseInsensitiveContains(searchText)
                || user.userId.localizedCaseInsensitiveContains(searchText)
                || (user.ambassadorDisplayName?.localizedCaseInsensitiveContains(searchText) == true)
            let matchesFilter: Bool
            switch filter {
            case .all: matchesFilter = true
            case .onboarded: matchesFilter = user.onboardingComplete
            case .active: matchesFilter = user.sessionCount > 0
            case .ambassador:
                let matchesAmbassador = user.isAmbassadorReferral
                    && (selectedAmbassadorID == "all" || user.ambassadorFilterID == selectedAmbassadorID)
                let matchesDates: Bool
                if limitsAmbassadorDates {
                    matchesDates = user.createdAt
                        .flatMap(parseAdminDate)
                        .map { created in
                            let calendar = Calendar.current
                            let start = calendar.startOfDay(for: ambassadorCreatedFrom)
                            let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: ambassadorCreatedThrough)) ?? ambassadorCreatedThrough
                            return created >= start && created < end
                        } ?? false
                } else {
                    matchesDates = true
                }
                matchesFilter = matchesAmbassador && matchesDates
            }
            return matchesSearch && matchesFilter
        }
    }

    private var ambassadorOptions: [AmbassadorDatabaseFilterOption] {
        var options: [String: AmbassadorDatabaseFilterOption] = [:]
        users.filter(\.isAmbassadorReferral).forEach { user in
            guard let id = user.ambassadorFilterID, let name = user.ambassadorDisplayName else { return }
            options[id] = AmbassadorDatabaseFilterOption(id: id, name: name)
        }
        return options.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var pageCount: Int { max(1, Int(ceil(Double(filteredUsers.count) / Double(pageSize)))) }
    private var visibleUsers: [AdminCampaignUser] {
        let safePage = min(page, pageCount - 1)
        let start = safePage * pageSize
        guard start < filteredUsers.count else { return [] }
        return Array(filteredUsers[start..<min(start + pageSize, filteredUsers.count)])
    }

    var body: some View {
        ZStack {
            MivoColors.background.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    summaryStrip

                    Picker("User filter", selection: $filter) {
                        ForEach(AdminUserFilter.allCases) { item in
                            Text(item.rawValue).tag(item)
                        }
                    }
                    .pickerStyle(.segmented)

                    if filter == .ambassador {
                        ambassadorFilterPanel
                    }

                    if let errorMessage {
                        ContentUnavailableView(
                            "User database unavailable",
                            systemImage: "person.3.sequence.fill",
                            description: Text(errorMessage)
                        )
                        Button("Try Again") { Task { await load() } }
                            .buttonStyle(.borderedProminent)
                            .tint(MivoColors.accent)
                    } else if !isLoading {
                        userResults
                        pagination
                    }
                }
                .padding(16)
                .padding(.bottom, 30)
            }

            if isLoading { MivoLoadingOverlay(message: "Loading users...") }
        }
        .navigationTitle("User Database")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { Task { await load() } } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(isLoading)
                .accessibilityLabel("Refresh users")
            }
        }
        .searchable(text: $searchText, prompt: "Search name, email, or user ID")
        .onChange(of: searchText) { _, _ in page = 0 }
        .onChange(of: filter) { _, _ in page = 0 }
        .onChange(of: selectedAmbassadorID) { _, _ in page = 0 }
        .onChange(of: limitsAmbassadorDates) { _, _ in page = 0 }
        .onChange(of: ambassadorCreatedFrom) { _, newValue in
            if newValue > ambassadorCreatedThrough { ambassadorCreatedThrough = newValue }
            page = 0
        }
        .onChange(of: ambassadorCreatedThrough) { _, newValue in
            if newValue < ambassadorCreatedFrom { ambassadorCreatedFrom = newValue }
            page = 0
        }
        .task { await load() }
        .sheet(item: $ambassadorAssignmentUser) { user in
            AmbassadorAssignmentView(user: user) {
                ambassadorAssignmentUser = nil
                await load()
            }
            .environmentObject(appVM)
        }
    }

    private var summaryStrip: some View {
        HStack(spacing: 8) {
            databaseStat("Total", value: users.count, icon: "person.3.fill")
            databaseStat("Onboarded", value: users.filter(\.onboardingComplete).count, icon: "checkmark.circle.fill")
            databaseStat("Active", value: users.filter { $0.sessionCount > 0 }.count, icon: "waveform.path.ecg")
        }
    }

    private var ambassadorFilterPanel: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "person.crop.circle.badge.checkmark")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(MivoColors.accent)
                    .frame(width: 36, height: 36)
                    .background(MivoColors.accent.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 2) {
                    Text("Referred by ambassador")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(MivoColors.textPrimary)
                    Text("Based on the ambassador name entered during onboarding")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(MivoColors.textMuted)
                }
                Spacer(minLength: 8)
                Picker("Ambassador", selection: $selectedAmbassadorID) {
                    Text("All ambassadors").tag("all")
                    ForEach(ambassadorOptions) { option in
                        Text(option.name).tag(option.id)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .tint(MivoColors.accent)
            }
            .padding(13)

            Divider().overlay(MivoColors.border).padding(.leading, 61)

            Toggle(isOn: $limitsAmbassadorDates) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Account creation dates")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(MivoColors.textPrimary)
                    Text(limitsAmbassadorDates ? "Only show accounts created in this range" : "Showing all creation dates")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(MivoColors.textMuted)
                }
            }
            .tint(MivoColors.accent)
            .padding(13)

            if limitsAmbassadorDates {
                Divider().overlay(MivoColors.border).padding(.leading, 13)
                HStack(spacing: 14) {
                    DatePicker("From", selection: $ambassadorCreatedFrom, in: ...ambassadorCreatedThrough, displayedComponents: .date)
                    DatePicker("To", selection: $ambassadorCreatedThrough, in: ambassadorCreatedFrom...Date(), displayedComponents: .date)
                }
                .font(.system(size: 12, weight: .semibold))
                .padding(13)
            }
        }
        .background(MivoColors.card)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(MivoColors.border.opacity(0.65), lineWidth: 1))
    }

    private func databaseStat(_ title: String, value: Int, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(MivoColors.accent)
            Text("\(value)")
                .font(.system(size: 21, weight: .bold, design: .rounded))
                .foregroundColor(MivoColors.textPrimary)
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(MivoColors.textMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(MivoColors.card)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(MivoColors.border.opacity(0.65), lineWidth: 1))
    }

    private var userResults: some View {
        LazyVStack(spacing: 0) {
            HStack {
                Text("\(filteredUsers.count) result\(filteredUsers.count == 1 ? "" : "s")")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(MivoColors.textSecondary)
                Spacer()
                Text("25 per page")
                    .font(.system(size: 11))
                    .foregroundColor(MivoColors.textMuted)
            }
            .padding(14)

            if visibleUsers.isEmpty {
                Divider().overlay(MivoColors.border)
                Text("No users match this search.")
                    .font(.system(size: 13))
                    .foregroundColor(MivoColors.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(28)
            } else {
                ForEach(Array(visibleUsers.enumerated()), id: \.element.id) { index, user in
                    if index > 0 { Divider().overlay(MivoColors.border).padding(.leading, 62) }
                    NavigationLink {
                        AdminUserProgressView(user: user)
                    } label: {
                        databaseUserRow(user)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .background(MivoColors.card)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(MivoColors.border.opacity(0.65), lineWidth: 1))
    }

    private func databaseUserRow(_ user: AdminCampaignUser) -> some View {
        HStack(spacing: 12) {
            Text(String(user.name.prefix(1)).uppercased())
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(MivoColors.textPrimary)
                .frame(width: 36, height: 36)
                .background(MivoColors.background)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(user.name)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(MivoColors.textPrimary)
                        .lineLimit(1)
                    if user.email.lowercased() == appVM.user?.email.lowercased() {
                        Text(appVM.isSuperAdminUser ? "SUPER ADMIN" : "ADMIN")
                            .font(.system(size: 8, weight: .black))
                            .foregroundColor(MivoColors.accent)
                    }
                }
                Text(user.email)
                    .font(.system(size: 11))
                    .foregroundColor(MivoColors.textSecondary)
                    .lineLimit(1)
                Text("\(user.sessionCount) sessions · \(user.truthCheckCount ?? 0) truth checks · \(user.reflectionCount) reflections")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(MivoColors.textMuted)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(user.calibrationComplete == true ? "Calibrated" : "Not calibrated")
                    if let last = user.lastActiveAt { Text("· Active \(shortAdminDate(last))") }
                    else if let created = user.createdAt { Text("· Joined \(shortAdminDate(created))") }
                }
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(MivoColors.textMuted)
                .lineLimit(1)

                if user.isAmbassadorReferral, let ambassador = user.ambassadorAttributionLabel {
                    Text("Referred by \(ambassador) · Account created \(shortAdminDate(user.ambassadorReferredAt ?? user.createdAt ?? ""))")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(MivoColors.accent)
                        .lineLimit(2)
                }
            }
            Spacer()
            if user.onboardingComplete {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(MivoColors.blue)
                    .accessibilityLabel("Onboarding complete")
            }
            if user.email.lowercased() != appVM.user?.email.lowercased() {
                Menu {
                    ForEach(["user", "admin", "ambassador"], id: \.self) { role in
                        Button {
                            Task { await setRole(user, role: role) }
                        } label: {
                            Label(role.capitalized, systemImage: user.accountRole == role ? "checkmark" : "person.badge.key")
                        }
                    }
                } label: {
                    Text((user.accountRole ?? "user").capitalized)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(MivoColors.accent)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 5)
                        .background(MivoColors.background)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(MivoColors.textMuted)
        }
        .padding(13)
    }

    @ViewBuilder
    private var pagination: some View {
        if pageCount > 1 {
            HStack(spacing: 16) {
                Button { page = max(0, page - 1) } label: {
                    Image(systemName: "chevron.left")
                        .frame(width: 38, height: 34)
                }
                .buttonStyle(.bordered)
                .disabled(page == 0)

                Text("Page \(page + 1) of \(pageCount)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(MivoColors.textSecondary)

                Button { page = min(pageCount - 1, page + 1) } label: {
                    Image(systemName: "chevron.right")
                        .frame(width: 38, height: 34)
                }
                .buttonStyle(.bordered)
                .disabled(page >= pageCount - 1)
            }
            .frame(maxWidth: .infinity)
        }
    }

    @MainActor
    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            try await appVM.prepareAuthenticatedCampaignSession()
            let dashboard = try await ReferralCampaignService.loadAdminDashboard()
            users = dashboard.users
            page = min(page, max(0, pageCount - 1))
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func setRole(_ user: AdminCampaignUser, role: String) async {
        do {
            try await appVM.prepareAuthenticatedCampaignSession()
            try await ReferralCampaignService.setUserRole(userID: user.userId, role: role)
            await load()
            if role == "ambassador" {
                ambassadorAssignmentUser = users.first(where: { $0.userId == user.userId }) ?? user
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct AdminAnalyticsView: View {
    @EnvironmentObject private var appVM: AppViewModel
    @State private var dashboard: AdminProductDashboard?
    @State private var isLoading = true
    @State private var errorMessage: String?

    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        ZStack {
            MivoColors.background.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                if let dashboard {
                    VStack(spacing: 14) {
                        overview(dashboard)
                        growthChart(dashboard)
                        retention(dashboard)
                        behavior(dashboard)
                        funnel(dashboard)
                        sources(dashboard)
                        versions(dashboard)
                    }
                    .padding(16).padding(.bottom, 30)
                } else if let errorMessage, !isLoading {
                    VStack(spacing: 14) {
                        ContentUnavailableView("Analytics unavailable", systemImage: "chart.xyaxis.line", description: Text(errorMessage))
                        Button("Try Again") { Task { await load() } }
                            .buttonStyle(.borderedProminent)
                            .tint(MivoColors.accent)
                    }
                    .padding(20)
                }
            }
            if isLoading { MivoLoadingOverlay(message: "Calculating Mivo analytics...") }
        }
        .navigationTitle("Admin Overview")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { Task { await load() } } label: { Image(systemName: "arrow.clockwise") } } }
        .task { await load() }
        .refreshable { await load() }
    }

    private func overview(_ data: AdminProductDashboard) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Main dashboard", icon: "gauge.with.dots.needle.67percent")
            LazyVGrid(columns: columns, spacing: 8) {
                metric("Registered users", "\(data.overview.totalUsers)", "person.3.fill")
                metric("Daily active", "\(data.overview.dau)", "sun.max.fill")
                metric("Monthly active", "\(data.overview.mau)", "calendar")
                metric("New today", "\(data.overview.newToday)", "person.badge.plus")
                metric("New this week", "\(data.overview.newWeek)", "calendar.badge.plus")
                metric("New this month", "\(data.overview.newMonth)", "calendar.badge.clock")
                metric("Sessions / user", decimal(data.overview.avgSessions), "timer")
                metric("Truth checks / user", decimal(data.overview.avgTruth), "checkmark.bubble")
            }
            Label("App Store views, true downloads, uninstall estimates, and crash data require App Store Connect or a crash-reporting integration.", systemImage: "info.circle")
                .font(.system(size: 11)).foregroundColor(MivoColors.textSecondary)
        }.analyticsPanel()
    }

    private func growthChart(_ data: AdminProductDashboard) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Last 30 days", icon: "chart.line.uptrend.xyaxis")
            Chart(data.timeseries) { point in
                LineMark(x: .value("Date", point.date), y: .value("Active users", point.activeUsers))
                    .foregroundStyle(MivoColors.blue).interpolationMethod(.catmullRom)
                PointMark(x: .value("Date", point.date), y: .value("Active users", point.activeUsers))
                    .foregroundStyle(MivoColors.blue).symbolSize(18)
            }
            .chartXAxis(.hidden)
            .frame(height: 170)
            HStack { Label("Active users", systemImage: "circle.fill").foregroundColor(MivoColors.blue); Spacer(); Text("Downloads appear after App Store connection") }
                .font(.system(size: 10, weight: .semibold)).foregroundColor(MivoColors.textMuted)
        }.analyticsPanel()
    }

    private func retention(_ data: AdminProductDashboard) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Retention", icon: "arrow.triangle.2.circlepath")
            HStack(spacing: 8) {
                percentCell("Day 1", data.retention.d1)
                percentCell("Day 7", data.retention.d7)
                percentCell("Day 30", data.retention.d30)
            }
        }.analyticsPanel()
    }

    private func behavior(_ data: AdminProductDashboard) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Mivo behavior", icon: "brain.head.profile")
            HStack(spacing: 8) {
                percentCell("Onboarding", data.overview.onboardingPct ?? 0)
                percentCell("Reflections", data.overview.reflectionPct ?? 0)
                VStack(alignment: .leading, spacing: 4) {
                    Text(decimal(data.overview.avgTruthGap) + "m").font(.system(size: 19, weight: .bold))
                    Text("Truth gap").font(.system(size: 10)).foregroundColor(MivoColors.textMuted)
                }.frame(maxWidth: .infinity).padding(10).background(MivoColors.background).clipShape(RoundedRectangle(cornerRadius: 7))
            }
            ForEach(data.triggers.prefix(5)) { item in
                HStack { Text(item.trigger.replacingOccurrences(of: "_", with: " ").capitalized); Spacer(); Text("\(item.count)") }
                    .font(.system(size: 12, weight: .semibold)).foregroundColor(MivoColors.textSecondary)
            }
        }.analyticsPanel()
    }

    private func funnel(_ data: AdminProductDashboard) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Activation funnel", icon: "line.3.horizontal.decrease")
            ForEach(Array(data.funnel.enumerated()), id: \.element.id) { index, item in
                let previous = index == 0 ? item.count : data.funnel[index - 1].count
                VStack(alignment: .leading, spacing: 5) {
                    HStack { Text(item.stage); Spacer(); Text("\(item.count) · \(conversion(item.count, from: previous))") }
                        .font(.system(size: 12, weight: .semibold))
                    ProgressView(value: Double(item.count), total: Double(max(1, data.overview.totalUsers)))
                        .tint(MivoColors.accent)
                }
            }
        }.analyticsPanel()
    }

    private func sources(_ data: AdminProductDashboard) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Campaign sources", icon: "megaphone.fill")
            if data.sources.isEmpty { Text("No source attribution yet.").font(.system(size: 12)).foregroundColor(MivoColors.textMuted) }
            ForEach(data.sources) { source in
                HStack { Text(source.source.capitalized); Spacer(); Text("\(source.signups) sign-ups · \(source.onboarded) activated") }
                    .font(.system(size: 12, weight: .semibold)).foregroundColor(MivoColors.textSecondary)
            }
        }.analyticsPanel()
    }

    private func versions(_ data: AdminProductDashboard) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("App versions", icon: "square.stack.3d.up.fill")
            if data.versions.isEmpty { Text("Version distribution begins with this build.").font(.system(size: 12)).foregroundColor(MivoColors.textMuted) }
            ForEach(data.versions) { item in
                HStack { Text(item.version ?? "Unknown"); Spacer(); Text("\(item.users) users") }.font(.system(size: 12, weight: .semibold))
            }
        }.analyticsPanel()
    }

    private func metric(_ label: String, _ value: String, _ icon: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon).foregroundColor(MivoColors.accent)
            Text(value).font(.system(size: 22, weight: .bold, design: .rounded))
            Text(label).font(.system(size: 10, weight: .semibold)).foregroundColor(MivoColors.textMuted)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(11).background(MivoColors.background).clipShape(RoundedRectangle(cornerRadius: 7))
    }

    private func percentCell(_ title: String, _ value: Double) -> some View {
        VStack(alignment: .leading, spacing: 4) { Text("\(value, specifier: "%.1f")%").font(.system(size: 19, weight: .bold)); Text(title).font(.system(size: 10)).foregroundColor(MivoColors.textMuted) }
            .frame(maxWidth: .infinity, alignment: .leading).padding(10).background(MivoColors.background).clipShape(RoundedRectangle(cornerRadius: 7))
    }
    private func sectionTitle(_ title: String, icon: String) -> some View { Label(title, systemImage: icon).font(.system(size: 16, weight: .bold)).foregroundColor(MivoColors.textPrimary) }
    private func decimal(_ value: Double?) -> String { String(format: "%.1f", value ?? 0) }
    private func conversion(_ value: Int, from previous: Int) -> String { previous == 0 ? "—" : String(format: "%.0f%%", 100.0 * Double(value) / Double(previous)) }
    private func load() async { isLoading = true; do { try await appVM.prepareAuthenticatedCampaignSession(); dashboard = try await ReferralCampaignService.loadProductDashboard() } catch { errorMessage = error.localizedDescription }; isLoading = false }
}

private struct FeedbackSubmissionView: View {
    @EnvironmentObject private var appVM: AppViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var type = "feedback"
    @State private var subject = ""
    @State private var message = ""
    @State private var isSending = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Picker("Type", selection: $type) { Text("Feedback").tag("feedback"); Text("Bug").tag("bug"); Text("Feature request").tag("feature"); Text("Support").tag("support"); Text("Delete my account").tag("deletion") }
            TextField("Subject", text: $subject)
            TextField("What happened?", text: $message, axis: .vertical).lineLimit(6...12)
            Button(isSending ? "Sending..." : "Send to Mivo") { Task { await submit() } }
                .disabled(isSending || subject.isEmpty || message.isEmpty)
        }
        .scrollContentBackground(.hidden).background(MivoColors.background)
        .navigationTitle("Send Feedback").navigationBarTitleDisplayMode(.inline)
        .alert("Feedback", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage=nil } })) { Button("OK") {} } message: { Text(errorMessage ?? "") }
    }
    private func submit() async { isSending=true; do { try await appVM.prepareAuthenticatedCampaignSession(); try await ReferralCampaignService.submitFeedback(type:type,subject:subject,message:message); dismiss() } catch { errorMessage=error.localizedDescription }; isSending=false }
}

struct AdminFeedbackView: View {
    @EnvironmentObject private var appVM: AppViewModel
    @State private var items: [AdminFeedbackItem] = []
    @State private var loading = true
    @State private var errorMessage: String?
    var body: some View {
        ZStack {
            MivoColors.background.ignoresSafeArea()
            ScrollView { LazyVStack(spacing: 10) {
                ForEach(items) { item in NavigationLink { AdminFeedbackDetailView(item:item) { await load() } } label: {
                    HStack(spacing: 12) {
                        Image(systemName: item.type == "bug" ? "ladybug.fill" : "bubble.left.fill").foregroundColor(MivoColors.accent).frame(width:34,height:34).background(MivoColors.card).clipShape(RoundedRectangle(cornerRadius:7))
                        VStack(alignment:.leading,spacing:3) { Text(item.subject).font(.system(size:14,weight:.bold)); Text(item.message).font(.system(size:11)).foregroundColor(MivoColors.textSecondary).lineLimit(2) }
                        Spacer(); Text(item.status.capitalized).font(.system(size:10,weight:.bold)).foregroundColor(MivoColors.blue); Image(systemName:"chevron.right").foregroundColor(MivoColors.textMuted)
                    }.padding(13).background(MivoColors.card).clipShape(RoundedRectangle(cornerRadius:8))
                }.buttonStyle(.plain) }
                if items.isEmpty && !loading { ContentUnavailableView("No feedback",systemImage:"checkmark.bubble",description:Text("New reports will appear here.")) }
            }.padding(16) }
            if loading { MivoLoadingOverlay(message:"Loading feedback...") }
        }.navigationTitle("Feedback & Bugs").navigationBarTitleDisplayMode(.inline).task { await load() }.refreshable { await load() }
          .alert("Feedback",isPresented:Binding(get:{errorMessage != nil},set:{if !$0{errorMessage=nil}})){Button("OK") {}} message:{Text(errorMessage ?? "")}
    }
    private func load() async { loading=true; do { try await appVM.prepareAuthenticatedCampaignSession(); items=try await ReferralCampaignService.adminFeedback() } catch { errorMessage=error.localizedDescription }; loading=false }
}

private struct AdminFeedbackDetailView: View {
    let item: AdminFeedbackItem
    let didSave: () async -> Void
    @State private var status: String; @State private var assigned: String; @State private var notes: String; @State private var message: String?
    init(item:AdminFeedbackItem,didSave:@escaping()async->Void){self.item=item;self.didSave=didSave;_status=State(initialValue:item.status);_assigned=State(initialValue:item.assignedTo ?? "");_notes=State(initialValue:item.internalNotes ?? "")}
    var body: some View { Form { Section("Report") { Text(item.subject).font(.headline); Text(item.message); LabeledContent("Type",value:item.type.capitalized); LabeledContent("Version",value:item.appVersion ?? "Unknown"); LabeledContent("Device",value:item.deviceInfo ?? "Unknown") }; Section("Team") { Picker("Status",selection:$status){ForEach(["new","investigating","fixed","closed"],id:\.self){Text($0.capitalized).tag($0)}};TextField("Assigned team member",text:$assigned);TextField("Internal notes",text:$notes,axis:.vertical).lineLimit(4...8);Button("Save changes"){Task{await save()}} } }.navigationTitle("Feedback").navigationBarTitleDisplayMode(.inline).alert("Feedback",isPresented:Binding(get:{message != nil},set:{if !$0{message=nil}})){Button("OK") {}} message:{Text(message ?? "")} }
    private func save() async { do { try await ReferralCampaignService.updateFeedback(id:item.id,status:status,assignedTo:assigned,notes:notes);await didSave();message="Feedback updated." } catch { message=error.localizedDescription } }
}

private extension View {
    func analyticsPanel() -> some View { padding(14).frame(maxWidth:.infinity,alignment:.leading).background(MivoColors.card).clipShape(RoundedRectangle(cornerRadius:8)).overlay(RoundedRectangle(cornerRadius:8).strokeBorder(MivoColors.border.opacity(0.65),lineWidth:1)) }
}

private extension AdminCampaignUser {
    var isAmbassadorReferral: Bool {
        referralSource?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "ambassador"
            && !(referralAmbassadorName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }

    var ambassadorFilterID: String? {
        guard isAmbassadorReferral else { return nil }
        if let ambassadorUserId, !ambassadorUserId.isEmpty {
            return "user:\(ambassadorUserId)"
        }
        guard let entered = referralAmbassadorName?.trimmingCharacters(in: .whitespacesAndNewlines), !entered.isEmpty else { return nil }
        return "name:\(entered.lowercased())"
    }

    var ambassadorDisplayName: String? {
        guard let entered = referralAmbassadorName?.trimmingCharacters(in: .whitespacesAndNewlines), !entered.isEmpty else { return nil }
        guard let account = ambassadorAccountName?.trimmingCharacters(in: .whitespacesAndNewlines),
              !account.isEmpty,
              account.caseInsensitiveCompare(entered) != .orderedSame else {
            return ambassadorUserId == nil ? "\(entered) (unassigned)" : entered
        }
        return "\(account) · entered as \(entered)"
    }

    var ambassadorAttributionLabel: String? {
        guard let entered = referralAmbassadorName?.trimmingCharacters(in: .whitespacesAndNewlines), !entered.isEmpty else { return nil }
        guard let account = ambassadorAccountName?.trimmingCharacters(in: .whitespacesAndNewlines),
              !account.isEmpty,
              account.caseInsensitiveCompare(entered) != .orderedSame else {
            return entered
        }
        return "\(entered) (assigned to \(account))"
    }
}

private func parseAdminDate(_ iso: String) -> Date? {
    let fractional = ISO8601DateFormatter()
    fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return fractional.date(from: iso) ?? ISO8601DateFormatter().date(from: iso)
}

private func shortAdminDate(_ iso: String) -> String {
    guard let date = parseAdminDate(iso) else { return iso }
    let formatter = DateFormatter(); formatter.dateStyle = .short; return formatter.string(from: date)
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
