import SwiftUI
import UIKit
import UserNotifications

#if canImport(FamilyControls)
import FamilyControls
#endif

private let availableApps = [
    "Instagram", "TikTok", "Twitter / X", "YouTube",
    "Reddit", "Facebook", "LinkedIn", "Snapchat", "Pinterest", "Threads"
]

struct OnboardingAppsView: View {
    @EnvironmentObject var appVM: AppViewModel
    @Environment(\.dismiss) var dismiss
    @State private var selected: Set<String> = []
    @State private var loading = false
    @State private var appear = false
    @State private var notificationsEnabled = false
    @State private var notificationChoiceMade = false
    @State private var showNotificationChoice = false
    @State private var protectedAppsEnabled = FamilyControlsManager.shared.isImpulseProtectionEnabled()
    @State private var setupMessage: String? = nil
    @State private var goToCheckIn = false
    @State private var aiRecommendation: ProtectedAppRecommendation?
    @State private var aiRecommendationLoading = false
    #if canImport(FamilyControls)
    @State private var impulseSelection = FamilyActivitySelection()
    @State private var showImpulsePicker = false
    #endif

    var body: some View {
        ZStack {
            OnboardingBackdrop()

            VStack(spacing: 0) {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 24) {
                        OnboardingStepHeader(
                            step: 5,
                            total: 10,
                            eyebrow: "Apps",
                            title: "Where should Mivo pay attention?",
                            subtitle: "Choose the places that tend to pull you in. This stays private and helps your first insights feel relevant."
                        )
                        .onboardingEntrance(appear)

                        selectedSummary
                            .onboardingEntrance(appear, delay: 0.08)

                        setupPromptCard
                            .onboardingEntrance(appear, delay: 0.12)

                        FlowLayout(spacing: 10) {
                            ForEach(Array(availableApps.enumerated()), id: \.element) { index, app in
                                Button {
                                    withAnimation(.spring(response: 0.34, dampingFraction: 0.8)) {
                                        if selected.contains(app) { selected.remove(app) }
                                        else { selected.insert(app) }
                                    }
                                    HapticsService.selection()
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: appIcon(for: app))
                                            .font(.system(size: 12, weight: .semibold))
                                        if selected.contains(app) {
                                            Image(systemName: "checkmark")
                                                .font(.system(size: 11, weight: .semibold))
                                        }
                                        Text(app)
                                            .font(.system(size: 14, weight: .medium))
                                    }
                                    .foregroundColor(selected.contains(app) ? MivoColors.white : MivoColors.textSecondary)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 11)
                                    .background(selected.contains(app) ? MivoColors.accent : MivoColors.white.opacity(0.62))
                                    .clipShape(Capsule())
                                    .overlay(
                                        Capsule()
                                            .strokeBorder(selected.contains(app) ? MivoColors.accent : MivoColors.white.opacity(0.58), lineWidth: 1)
                                    )
                                    .shadow(color: Color.black.opacity(selected.contains(app) ? 0.08 : 0.025), radius: selected.contains(app) ? 12 : 6, y: 4)
                                }
                                .buttonStyle(.plain)
                                .onboardingEntrance(appear, delay: 0.14 + Double(index) * 0.025)
                            }
                        }

                        Text("You can change this later in Settings.")
                            .font(.system(size: 13).italic())
                            .foregroundColor(MivoColors.textMuted)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 24)
                    .padding(.bottom, 120)
                }

                OnboardingBottomBar {
                    Button {
                        continueAfterRequiredSetup()
                    } label: {
                        HStack(spacing: 8) {
                            Text(setupComplete ? "I'm ready" : requiredSetupButtonTitle)
                                .font(.system(size: 16, weight: .semibold))
                            Image(systemName: setupComplete ? "checkmark" : "lock.fill")
                                .font(.system(size: 16, weight: .medium))
                        }
                        .foregroundColor(MivoColors.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 17)
                        .background(setupComplete ? MivoColors.textPrimary : MivoColors.textMuted.opacity(0.52))
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .shadow(color: setupComplete ? MivoColors.textPrimary.opacity(0.18) : .clear, radius: 16, y: 8)
                    }
                    .disabled(loading)
                }
            }
        }
        .navigationBarBackButtonHidden()
        .navigationDestination(isPresented: $goToCheckIn) {
            CheckInOnboardingView_Internal()
        }
        .confirmationDialog("Notifications", isPresented: $showNotificationChoice, titleVisibility: .visible) {
            Button("Allow notifications") {
                requestNotifications()
            }
            Button("Not now") {
                declineNotifications()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Mivo can send reminders and time truth check-ins. You can also continue without them.")
        }
        #if canImport(FamilyControls)
        .familyActivityPicker(isPresented: $showImpulsePicker, selection: $impulseSelection)
        .onChange(of: impulseSelection) { _, newValue in
            if #available(iOS 16.0, *) {
                FamilyControlsManager.shared.saveFamilyActivitySelection(newValue)
                if FamilyControlsManager.shared.hasImpulseSelection() {
                    protectedAppsEnabled = true
                    FamilyControlsManager.shared.setImpulseProtectionEnabled(true)
                    setupMessage = "Protected apps are on. Mivo will pause before those apps open."
                    HapticsService.success()
                }
            }
        }
        #endif
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button { dismiss() } label: {
                    Image(systemName: "arrow.left")
                        .foregroundColor(MivoColors.textSecondary)
                }
            }
        }
        .onAppear {
            appear = true
            refreshSetupState()
            refreshAIRecommendation()
        }
        .onChange(of: selected) { _, _ in
            refreshAIRecommendation()
        }
    }

    private var setupComplete: Bool {
        protectedAppsEnabled && notificationChoiceMade
    }

    private var requiredSetupButtonTitle: String {
        if !protectedAppsEnabled && !notificationChoiceMade {
            return "Choose protection and notifications"
        }
        if !protectedAppsEnabled {
            return "Choose protected apps"
        }
        return "Choose notification preference"
    }

    private var selectedSummary: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(selected.isEmpty ? "No apps selected yet" : "\(selected.count) app\(selected.count == 1 ? "" : "s") selected")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(MivoColors.textPrimary)
                    .contentTransition(.numericText())
                Text(selected.isEmpty ? "Tap any apps that feel familiar." : "Nice. Your reflection map is getting sharper.")
                    .font(.system(size: 13))
                    .foregroundColor(MivoColors.textSecondary)
            }

            Spacer()

            Image(systemName: selected.isEmpty ? "square.grid.2x2" : "checkmark.seal.fill")
                .font(.system(size: 24, weight: .semibold))
                .foregroundColor(selected.isEmpty ? Color(hex: "#A97B5B") : MivoColors.accent)
        }
        .padding(18)
        .background(MivoColors.white.opacity(0.62))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(MivoColors.white.opacity(0.58), lineWidth: 1))
    }

    private var notificationPreferenceTitle: String {
        if notificationsEnabled {
            return "Notifications on"
        }
        if notificationChoiceMade {
            return "Notifications off"
        }
        return "Choose notifications"
    }

    private var notificationPreferenceSubtitle: String {
        if notificationsEnabled {
            return "Mivo can send helpful reminders."
        }
        if notificationChoiceMade {
            return "You can turn reminders on later in Settings."
        }
        return "Allow reminders, or choose Not now and continue."
    }

    private var notificationPreferenceActionTitle: String {
        if notificationsEnabled {
            return "On"
        }
        if notificationChoiceMade {
            return "Change"
        }
        return "Choose"
    }

    private var setupPromptCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "checklist.checked")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(MivoColors.accent)
                    .frame(width: 40, height: 40)
                    .background(MivoColors.accent.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text("Turn on Mivo’s protection")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundColor(MivoColors.textPrimary)
                    Text("Choose the apps that should pause, then decide whether Mivo can send reminders at the right moments.")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(MivoColors.textSecondary)
                        .lineSpacing(3)
                }
            }

            aiRecommendationCard

            VStack(spacing: 10) {
                setupActionRow(
                    icon: protectedAppsEnabled ? "shield.checkered" : "shield",
                    title: protectedAppsEnabled ? "Apps protected" : "Choose apps to protect",
                    subtitle: protectedAppsEnabled ? "Your selected apps will show the Mivo pause." : "Open Apple’s picker and select distracting apps.",
                    isComplete: protectedAppsEnabled,
                    actionTitle: protectedAppsEnabled ? "Change" : "Choose",
                    action: chooseProtectedApps
                )

                setupActionRow(
                    icon: notificationChoiceMade ? (notificationsEnabled ? "bell.badge.fill" : "bell.slash") : "bell",
                    title: notificationPreferenceTitle,
                    subtitle: notificationPreferenceSubtitle,
                    isComplete: notificationChoiceMade,
                    actionTitle: notificationPreferenceActionTitle,
                    action: { showNotificationChoice = true }
                )
            }

            if let setupMessage {
                Text(setupMessage)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(MivoColors.textSecondary)
                    .padding(.top, 2)
            }
        }
        .padding(18)
        .background(MivoColors.white.opacity(0.66))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(MivoColors.white.opacity(0.58), lineWidth: 1))
        .shadow(color: Color.black.opacity(0.04), radius: 16, y: 8)
    }

    private var aiRecommendationCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(MivoColors.accent)
                Text(aiRecommendationLoading ? "Mivo is thinking..." : "Mivo recommends protecting")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(MivoColors.textPrimary)
                Spacer()
            }

            if let recommendation = aiRecommendation {
                FlowLayout(spacing: 7) {
                    ForEach(recommendation.apps, id: \.self) { app in
                        Label(app, systemImage: appIcon(for: app))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(MivoColors.accent)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(MivoColors.accent.opacity(0.1))
                            .clipShape(Capsule())
                    }
                }

                Text(recommendation.rationale)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(MivoColors.textMuted)
                    .lineSpacing(2)
            } else {
                Text("Pick a few familiar apps below and Mivo will suggest what to protect first.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(MivoColors.textMuted)
            }
        }
        .padding(12)
        .background(MivoColors.background.opacity(0.62))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func setupActionRow(
        icon: String,
        title: String,
        subtitle: String,
        isComplete: Bool,
        actionTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(isComplete ? MivoColors.secondary : MivoColors.accent)
                    .frame(width: 34, height: 34)
                    .background((isComplete ? MivoColors.secondary : MivoColors.accent).opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(MivoColors.textPrimary)
                    Text(subtitle)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(MivoColors.textMuted)
                        .lineLimit(2)
                }

                Spacer()

                Text(actionTitle)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(isComplete ? MivoColors.secondary : MivoColors.white)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 8)
                    .background(isComplete ? MivoColors.secondary.opacity(0.12) : MivoColors.accent)
                    .clipShape(Capsule())
            }
            .padding(12)
            .background(MivoColors.background.opacity(0.62))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func refreshSetupState() {
        protectedAppsEnabled = FamilyControlsManager.shared.isImpulseProtectionEnabled()
        #if canImport(FamilyControls)
        if #available(iOS 16.0, *) {
            impulseSelection = FamilyControlsManager.shared.loadFamilyActivitySelection()
            protectedAppsEnabled = protectedAppsEnabled && FamilyControlsManager.shared.hasImpulseSelection()
        }
        #endif

        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                let isEnabled = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional || settings.authorizationStatus == .ephemeral
                let hasSystemChoice = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional || settings.authorizationStatus == .ephemeral || settings.authorizationStatus == .denied
                notificationsEnabled = isEnabled
                notificationChoiceMade = appVM.settings.notificationsChoiceMade ?? hasSystemChoice
                var updated = appVM.settings
                updated.notificationsEnabled = isEnabled
                updated.notificationsChoiceMade = notificationChoiceMade
                appVM.settings = updated
                appVM.persistCurrentSettings()
            }
        }
    }

    private func continueAfterRequiredSetup() {
        refreshSetupState()
        guard setupComplete else {
            if !protectedAppsEnabled && !notificationChoiceMade {
                setupMessage = "Choose protected apps and choose a notification preference to continue."
            } else if !protectedAppsEnabled {
                setupMessage = "Choose at least one app to protect before continuing."
            } else {
                setupMessage = "Choose whether to allow notifications before continuing."
            }
            HapticsService.warning()
            return
        }

        loading = true
        var profile = OnboardingProfile()
        profile.preferredApps = Array(selected)
        appVM.saveOnboardingProfile(profile)
        HapticsService.impact(style: .light)
        goToCheckIn = true
        loading = false
    }

    private func chooseProtectedApps() {
        HapticsService.selection()
        #if canImport(FamilyControls)
        guard #available(iOS 16.0, *) else {
            setupMessage = "App protection needs iOS Screen Time support."
            return
        }

        FamilyControlsManager.shared.requestAuthorization { granted in
            DispatchQueue.main.async {
                FamilyControlsManager.shared.saveAuthorizationFlag(granted)
                if granted {
                    showImpulsePicker = true
                } else {
                    setupMessage = "Screen Time permission is needed before choosing protected apps."
                    HapticsService.warning()
                }
            }
        }
        #else
        setupMessage = "App protection is unavailable in this build."
        #endif
    }

    private func refreshAIRecommendation() {
        aiRecommendationLoading = true
        let selectedApps = Array(selected)
        Task {
            var profile = appVM.onboardingProfile
            if !selectedApps.isEmpty {
                profile.preferredApps = selectedApps
            }
            let recommendation = await AIService.recommendProtectedApps(
                profile: profile,
                selectedApps: selectedApps,
                recentSessionSummary: AIDataStore.recentSummary(limit: 4)
            )
            await MainActor.run {
                aiRecommendation = recommendation
                aiRecommendationLoading = false
            }
        }
    }

    private func requestNotifications() {
        HapticsService.selection()
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
            DispatchQueue.main.async {
                notificationsEnabled = granted
                notificationChoiceMade = true
                var updated = appVM.settings
                updated.notificationsEnabled = granted
                updated.notificationsChoiceMade = true
                appVM.settings = updated
                appVM.persistCurrentSettings()
                setupMessage = granted ? "Notifications are on." : "Notifications were not enabled. You can turn them on later in Settings."
                granted ? HapticsService.success() : HapticsService.warning()
            }
        }
    }

    private func declineNotifications() {
        HapticsService.selection()
        notificationsEnabled = false
        notificationChoiceMade = true
        var updated = appVM.settings
        updated.notificationsEnabled = false
        updated.notificationsChoiceMade = true
        appVM.settings = updated
        appVM.persistCurrentSettings()
        setupMessage = "Notifications are off. You can turn them on later in Settings."
        HapticsService.success()
    }

    private func appIcon(for app: String) -> String {
        switch app {
        case "YouTube": return "play.rectangle.fill"
        case "LinkedIn": return "briefcase.fill"
        case "Pinterest": return "pin.fill"
        case "Twitter / X", "Threads": return "at"
        case "Reddit": return "bubble.left.and.bubble.right.fill"
        case "Snapchat": return "camera.fill"
        default: return "app.fill"
        }
    }
}

// Simple flow layout for chips
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = computeRows(proposal: proposal, subviews: subviews)
        var totalHeight: CGFloat = 0
        for (i, row) in rows.enumerated() {
            let rowHeight = row.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0
            totalHeight += rowHeight
            if i < rows.count - 1 { totalHeight += spacing }
        }
        return CGSize(width: proposal.width ?? 0, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = computeRows(proposal: proposal, subviews: subviews)
        var y = bounds.minY
        for row in rows {
            var x = bounds.minX
            let rowHeight = row.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0
            for view in row {
                let size = view.sizeThatFits(.unspecified)
                view.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += rowHeight + spacing
        }
    }

    private func computeRows(proposal: ProposedViewSize, subviews: Subviews) -> [[LayoutSubview]] {
        var rows: [[LayoutSubview]] = [[]]
        var rowWidth: CGFloat = 0
        let maxWidth = proposal.width ?? .infinity
        for view in subviews {
            let w = view.sizeThatFits(.unspecified).width
            if rowWidth + w > maxWidth && !rows[rows.count - 1].isEmpty {
                rows.append([])
                rowWidth = 0
            }
            rows[rows.count - 1].append(view)
            rowWidth += w + spacing
        }
        return rows
    }
}

// MARK: - Internal onboarding age/result views (embedded to ensure they're in-scope)


private struct CheckInOnboardingView_Internal: View {
    @EnvironmentObject var appVM: AppViewModel
    @Environment(\.dismiss) var dismiss
    @State private var selectedMinutes = 3
    @State private var appear = false

    private let options = [2, 3, 5]

    var body: some View {
        ZStack {
            OnboardingBackdrop()

            VStack(spacing: 0) {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 24) {
                        OnboardingStepHeader(
                            step: 6,
                            total: 10,
                            eyebrow: "Check-ins",
                            title: "How often should Mivo pause?",
                            subtitle: "For longer sessions, Mivo will briefly pause the protected app so you can check whether you still want to keep scrolling."
                        )
                        .onboardingEntrance(appear)

                        VStack(alignment: .leading, spacing: 16) {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: "hourglass")
                                    .font(.system(size: 20, weight: .bold))
                                    .foregroundColor(MivoColors.accent)
                                    .frame(width: 42, height: 42)
                                    .background(MivoColors.accent.opacity(0.12))
                                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                                VStack(alignment: .leading, spacing: 5) {
                                    Text("5-second check-in")
                                        .font(.system(size: 18, weight: .bold, design: .rounded))
                                        .foregroundColor(MivoColors.textPrimary)
                                    Text("Sessions under 5 minutes stay uninterrupted. Longer sessions get a quiet 5-second pause at your chosen rhythm.")
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundColor(MivoColors.textSecondary)
                                        .lineSpacing(4)
                                }
                            }

                            VStack(spacing: 10) {
                                ForEach(options, id: \.self) { minutes in
                                    Button {
                                        withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
                                            selectedMinutes = minutes
                                        }
                                        HapticsService.selection()
                                    } label: {
                                        HStack(spacing: 12) {
                                            Image(systemName: selectedMinutes == minutes ? "checkmark.circle.fill" : "circle")
                                                .font(.system(size: 20, weight: .semibold))
                                                .foregroundColor(selectedMinutes == minutes ? MivoColors.accent : MivoColors.textMuted)
                                            VStack(alignment: .leading, spacing: 3) {
                                                Text("Every \(minutes) minutes")
                                                    .font(.system(size: 16, weight: .bold))
                                                    .foregroundColor(MivoColors.textPrimary)
                                                Text(minutes == 3 ? "Recommended balance" : intervalSubtitle(for: minutes))
                                                    .font(.system(size: 12, weight: .medium))
                                                    .foregroundColor(MivoColors.textSecondary)
                                            }
                                            Spacer()
                                            Text("5s")
                                                .font(.system(size: 13, weight: .bold).monospacedDigit())
                                                .foregroundColor(MivoColors.textPrimary)
                                                .padding(.horizontal, 10)
                                                .padding(.vertical, 7)
                                                .background(MivoColors.white.opacity(0.62))
                                                .clipShape(Capsule())
                                        }
                                        .padding(15)
                                        .background(selectedMinutes == minutes ? MivoColors.accent.opacity(0.12) : MivoColors.white.opacity(0.62))
                                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                                .strokeBorder(selectedMinutes == minutes ? MivoColors.accent.opacity(0.42) : MivoColors.white.opacity(0.58), lineWidth: 1)
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .padding(18)
                        .background(MivoColors.white.opacity(0.64))
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(MivoColors.white.opacity(0.58), lineWidth: 1))
                        .onboardingEntrance(appear, delay: 0.08)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 24)
                    .padding(.bottom, 120)
                }

                OnboardingBottomBar {
                    NavigationLink {
                        AgeOnboardingView_Internal()
                    } label: {
                        HStack(spacing: 10) {
                            Text("Use this reminder")
                                .font(.system(size: 16, weight: .semibold))
                            Image(systemName: "arrow.right")
                                .font(.system(size: 15, weight: .semibold))
                        }
                        .foregroundColor(MivoColors.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 17)
                        .background(MivoColors.textPrimary)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .shadow(color: MivoColors.textPrimary.opacity(0.18), radius: 16, y: 8)
                    }
                    .simultaneousGesture(TapGesture().onEnded(savePreference))
                }
            }
            .onAppear {
                selectedMinutes = appVM.settings.checkInIntervalMinutes ?? appVM.onboardingProfile.checkInIntervalMinutes ?? 3
                FamilyControlsManager.shared.setCheckInIntervalMinutes(selectedMinutes)
                appear = true
            }
        }
        .navigationBarBackButtonHidden()
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button { dismiss() } label: {
                    Image(systemName: "arrow.left")
                        .foregroundColor(MivoColors.textSecondary)
                }
            }
        }
    }

    private func intervalSubtitle(for minutes: Int) -> String {
        minutes < 3 ? "More frequent check-ins" : "More room between pauses"
    }

    private func savePreference() {
        var updatedSettings = appVM.settings
        updatedSettings.checkInIntervalMinutes = selectedMinutes
        appVM.settings = updatedSettings
        appVM.persistCurrentSettings()

        var profile = appVM.onboardingProfile
        profile.checkInIntervalMinutes = selectedMinutes
        appVM.saveOnboardingProfile(profile)
        HapticsService.impact(style: .light)
    }
}

private struct AgeOnboardingView_Internal: View {
    @EnvironmentObject var appVM: AppViewModel
    @Environment(\.dismiss) var dismiss
    @State private var ageText = ""
    @State private var selectedRange: String? = nil
    @State private var appear = false
    @State private var highlightCategory: String? = nil
    @State private var lifeCounts: (sleepYears: Int, workYears: Int, eatYears: Int, basicsYears: Int, scrollYears: Int, freeYears: Int)? = nil

    private let ranges = ["Under 18", "18-24", "25-34", "35-44", "45-54", "55+"]
    private let lifeExpectancy = 80

    var body: some View {
        ZStack {
            OnboardingBackdrop()

            VStack(spacing: 0) {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 24) {
                        OnboardingStepHeader(
                            step: 7,
                            total: 10,
                            eyebrow: "Personalize",
                            title: "How should we frame your time?",
                            subtitle: "Your age helps Mivo turn daily scrolling into a life-sized view. It stays on device."
                        )
                        .onboardingEntrance(appear)

                        ageCard
                            .onboardingEntrance(appear, delay: 0.08)

                        rangeGrid
                            .onboardingEntrance(appear, delay: 0.16)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 24)
                    .padding(.bottom, 120)
                }

                let hasSelection = (Int(ageText) ?? 0) > 0 || selectedRange != nil
                OnboardingBottomBar {
                    NavigationLink {
                        let ageVal = Int(ageText)
                        LifeBreakdownView_Internal(providedAge: ageVal, providedAgeRange: selectedRange)
                    } label: {
                        HStack(spacing: 10) {
                            Text("Show life breakdown")
                                .font(.system(size: 16, weight: .semibold))
                            Image(systemName: "sparkles")
                                .font(.system(size: 15, weight: .semibold))
                        }
                        .foregroundColor(MivoColors.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 17)
                        .background(hasSelection ? MivoColors.textPrimary : MivoColors.textMuted.opacity(0.36))
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .shadow(color: hasSelection ? MivoColors.textPrimary.opacity(0.18) : .clear, radius: 16, y: 8)
                    }
                    .disabled(!hasSelection)
                    .simultaneousGesture(TapGesture().onEnded {
                        if hasSelection {
                            var profile = appVM.onboardingProfile
                            if let age = Int(ageText), age > 0 { profile.age = age }
                            profile.ageRange = selectedRange
                            appVM.saveOnboardingProfile(profile)
                            HapticsService.success()
                        }
                    })
                }
            }
            .onAppear { appear = true }
        }
        .navigationBarBackButtonHidden()
    }

    private var ageCard: some View {
        VStack(spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Exact age")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(MivoColors.textSecondary)
                    Text("Optional, but more accurate")
                        .font(.system(size: 12))
                        .foregroundColor(MivoColors.textMuted)
                }
                Spacer()
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 20))
                    .foregroundColor(Color(hex: "#A97B5B"))
            }

            ZStack {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color(hex: "#4A2E1F"))
                    .frame(height: 116)

                if ageText.isEmpty {
                    Text("Enter age")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundColor(Color.white.opacity(0.42))
                }

                NumericTextField(text: $ageText, placeholder: "", fontSize: 46)
                    .frame(height: 86)
                    .padding(.horizontal, 20)
            }
        }
        .padding(18)
        .background(MivoColors.white.opacity(0.64))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(MivoColors.white.opacity(0.58), lineWidth: 1))
        .shadow(color: Color.black.opacity(0.04), radius: 16, y: 8)
    }

    private var rangeGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Or choose a range")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(MivoColors.textSecondary)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(ranges, id: \.self) { range in
                    Button {
                        withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
                            selectedRange = (selectedRange == range ? nil : range)
                        }
                        HapticsService.selection()
                    } label: {
                        Text(range)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(selectedRange == range ? MivoColors.white : MivoColors.textPrimary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(selectedRange == range ? MivoColors.accent : MivoColors.white.opacity(0.62))
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(selectedRange == range ? MivoColors.accent : MivoColors.white.opacity(0.58), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

// Full-screen life breakdown view: large grid fills screen; other UI appears after a delay
private struct LifeBreakdownView_Internal: View {
    @EnvironmentObject var appVM: AppViewModel
    @Environment(\.dismiss) var dismiss

    // Accept explicit provided age/range to avoid reading from appVM too early
    let providedAge: Int?
    let providedAgeRange: String?

    // AI-provided counts (in years) for categories — computed for the visualized life span (boxesCount)
    @State private var lifeCounts: (sleepYears: Int, workYears: Int, eatYears: Int, basicsYears: Int, scrollYears: Int, freeYears: Int)? = nil
    // Precomputed mapping of each box index to category to avoid recomputing
    @State private var lifeMap: [String] = []

    // visual states
    @State private var started: Bool = false // user pressed "Let's visualize..." -> starts fetch & reveal
    @State private var loading: Bool = false
    @State private var appear = false
    @State private var showDetails = false

    // reveal sequence
    @State private var visibleCells: Int = 0          // how many cells are currently visible in the grid (left->right)
    @State private var highlightedCategory: String? = nil

    // floating textbox while highlighting a category
    @State private var floatingText: String? = nil
    @State private var showFloatingText: Bool = false

    // batch reveal size to reduce frequent UI updates (tuneable)
    private let revealBatchSize = 1

    // computed grid parameters
    private func boxesForAge(_ age: Int?, ageRange: String?) -> Int {
        // Prefer explicit provided age/range over appVM stored values
        if let a = age {
            switch a {
            case 0...17: return 60
            case 18...24: return 60
            case 25...34: return 50
            case 35...44: return 40
            case 45...54: return 30
            default: return 20
            }
        }
        if let range = ageRange {
            switch range {
            case "Under 18": return 60
            case "18-24": return 60
            case "25-34": return 50
            case "35-44": return 40
            case "45-54": return 30
            case "55+": return 20
            default: return 50
            }
        }
        // fallback to stored profile age if nothing provided
        if let storedAge = appVM.onboardingProfile.age { return boxesForAge(storedAge, ageRange: nil) }
        if let storedRange = appVM.onboardingProfile.ageRange { return boxesForAge(nil, ageRange: storedRange) }
        return 50
    }

    // Build an array mapping each year index to a category string based on lifeCounts (order preserved)
    private func buildCategoryMap(for counts: (sleepYears: Int, workYears: Int, eatYears: Int, basicsYears: Int, scrollYears: Int, freeYears: Int), totalBoxes: Int) -> [String] {
        var map: [String] = Array(repeating: "free", count: max(0, totalBoxes))
        var idx = 0
        let buckets: [(String, Int)] = [ ("sleep", counts.sleepYears), ("work", counts.workYears), ("eat", counts.eatYears), ("basics", counts.basicsYears), ("scroll", counts.scrollYears), ("free", counts.freeYears) ]
        for (cat, years) in buckets {
            for _ in 0..<max(0, years) {
                if idx >= totalBoxes { break }
                map[idx] = cat
                idx += 1
            }
            if idx >= totalBoxes { break }
        }
        // If anything left, keep as free
        return map
    }

    // Short floating label text for a category using computed counts (e.g., "17 years — Sleeping")
    private func floatingLabelFor(category: String, counts: (sleepYears: Int, workYears: Int, eatYears: Int, basicsYears: Int, scrollYears: Int, freeYears: Int)) -> String {
        func yrs(_ n: Int) -> String { return "\(n) \(n == 1 ? "year" : "years")" }
        switch category {
        case "sleep": return "\(yrs(counts.sleepYears)) — Sleeping"
        case "work": return "\(yrs(counts.workYears)) — Working"
        case "eat": return "\(yrs(counts.eatYears)) — Eating"
        case "basics": return "\(yrs(counts.basicsYears)) — Basics"
        case "scroll":
            // Prefer explicit user input (minutes/day) when available
            if let minutes = appVM.onboardingProfile.scrollEstimateMinutes, minutes > 0 {
                let hrs = Double(minutes) / 60.0
                return String(format: "On track to spend %.1f hrs/day on your phone", hrs)
            }
            // Fallback: estimate daily hours from the fraction of life spent scrolling
            let boxes = boxesForAge(providedAge, ageRange: providedAgeRange)
            if boxes > 0 {
                let fraction = Double(counts.scrollYears) / Double(boxes)
                let dailyHours = fraction * 24.0
                return String(format: "On track to spend %.1f hrs/day on your phone", dailyHours)
            }
            return "\(yrs(counts.scrollYears)) — Phone Scrolling"
        default: return "\(yrs(counts.freeYears)) — Free time"
        }
    }

    var body: some View {
        ZStack {
            OnboardingBackdrop()
            let boxes = boxesForAge(providedAge, ageRange: providedAgeRange)

            VStack(spacing: 0) {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 22) {
                        OnboardingStepHeader(
                            step: 8,
                            total: 10,
                            eyebrow: "Perspective",
                            title: "Your time, made visible",
                            subtitle: "Each square is roughly one year ahead. We’ll color the picture so your phone time has context."
                        )
                        .onboardingEntrance(appear)

                        yearPreviewCard(boxes: boxes)
                            .onboardingEntrance(appear, delay: 0.08)

                        lifeGridCard(boxes: boxes)
                            .onboardingEntrance(appear, delay: 0.16)

                        if showDetails, let counts = lifeCounts {
                            lifeLegend(counts: counts)
                                .onboardingEntrance(showDetails, delay: 0.02)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 24)
                    .padding(.bottom, 124)
                }

                OnboardingBottomBar {
                    if showDetails {
                        NavigationLink {
                            ResultOnboardingView_Internal(providedAge: providedAge, providedAgeRange: providedAgeRange)
                        } label: {
                            HStack(spacing: 10) {
                                Text("Show time we can recover")
                                    .font(.system(size: 16, weight: .semibold))
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 15, weight: .semibold))
                            }
                            .foregroundColor(MivoColors.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 17)
                            .background(MivoColors.textPrimary)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .shadow(color: MivoColors.textPrimary.opacity(0.18), radius: 16, y: 8)
                        }
                    } else {
                        OnboardingPrimaryButton(started ? "Visualizing..." : "Build my life map", enabled: !loading) {
                            Image(systemName: "sparkles")
                        } action: {
                            startVisualization(boxes: boxes)
                        }
                    }
                }
            }
            .onAppear { appear = true }
        }
        .navigationBarBackButtonHidden()
    }

    private func yearPreviewCard(boxes: Int) -> some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color(hex: "#4A2E1F"))
                    .frame(width: 72, height: 72)
                Text("\(boxes)")
                    .font(.system(size: 25, weight: .bold).monospacedDigit())
                    .foregroundColor(.white)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text("Years ahead")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(MivoColors.textPrimary)
                Text("Not a prediction. A lens for seeing attention as something precious.")
                    .font(.system(size: 13))
                    .foregroundColor(MivoColors.textSecondary)
                    .lineSpacing(3)
            }
        }
        .padding(18)
        .background(MivoColors.white.opacity(0.64))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(MivoColors.white.opacity(0.58), lineWidth: 1))
    }

    private func lifeGridCard(boxes: Int) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(showDetails ? "Life map" : started ? "Building your map" : "Preview")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(MivoColors.textPrimary)
                Spacer()
                if started && !showDetails {
                    ProgressView()
                        .tint(MivoColors.accent)
                }
            }

            let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 10)
            let counts = lifeCounts ?? (sleepYears: 0, workYears: 0, eatYears: 0, basicsYears: 0, scrollYears: 0, freeYears: boxes)
            let map = lifeMap.isEmpty ? buildCategoryMap(for: counts, totalBoxes: boxes) : lifeMap

            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(0..<boxes, id: \.self) { index in
                    let category = map[index]
                    let isVisible = index < visibleCells
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isVisible ? colorForCategory(category) : Color(hex: "#E8DED2"))
                        .aspectRatio(1, contentMode: .fit)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(Color.white.opacity(0.46), lineWidth: 1)
                        )
                        .scaleEffect(highlightedCategory == category && isVisible ? 1.08 : 1)
                        .opacity(started ? 1 : 0.72)
                        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: visibleCells)
                }
            }

            if let floatingText, showFloatingText {
                Text(floatingText)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(MivoColors.textPrimary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(hex: "#F3EBE3"))
                    .clipShape(Capsule())
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(18)
        .background(MivoColors.white.opacity(0.66))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(MivoColors.white.opacity(0.58), lineWidth: 1))
        .shadow(color: Color.black.opacity(0.04), radius: 16, y: 8)
    }

    private func lifeLegend(counts: (sleepYears: Int, workYears: Int, eatYears: Int, basicsYears: Int, scrollYears: Int, freeYears: Int)) -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            legendItem(color: colorForCategory("sleep"), label: "Sleep · \(counts.sleepYears)y")
            legendItem(color: colorForCategory("work"), label: "Work · \(counts.workYears)y")
            legendItem(color: colorForCategory("eat"), label: "Meals · \(counts.eatYears)y")
            legendItem(color: colorForCategory("basics"), label: "Basics · \(counts.basicsYears)y")
            legendItem(color: colorForCategory("scroll"), label: "Phone · \(counts.scrollYears)y")
            legendItem(color: colorForCategory("free"), label: "Open · \(counts.freeYears)y")
        }
    }

    private func startVisualization(boxes: Int) {
        guard !loading else { return }
        started = true
        loading = true
        HapticsService.impact(style: .light)

        Task {
            let counts = await AIService.estimateLifeBreakdown(profile: appVM.onboardingProfile, lifeExpectancy: boxes)
            var s = counts.sleepYears, w = counts.workYears, e = counts.eatYears, b = counts.basicsYears, sc = counts.scrollYears, f = counts.freeYears
            let total = s + w + e + b + sc + f
            if total != boxes { f += boxes - total }
            let adjusted = (s, w, e, b, sc, f)
            let map = buildCategoryMap(for: adjusted, totalBoxes: boxes)

            await MainActor.run {
                lifeCounts = adjusted
                lifeMap = map
                visibleCells = 0
            }

            let categoriesOrder = ["sleep", "work", "eat", "basics", "scroll", "free"]
            var startIndex = 0
            for category in categoriesOrder {
                let count = map.filter { $0 == category }.count
                if count == 0 { continue }
                await MainActor.run {
                    floatingText = floatingLabelFor(category: category, counts: adjusted)
                    showFloatingText = true
                    highlightedCategory = category
                }

                var revealed = 0
                while revealed < count {
                    revealed += min(revealBatchSize, count - revealed)
                    await MainActor.run {
                        withAnimation(.easeOut(duration: 0.16)) {
                            visibleCells = startIndex + revealed
                        }
                    }
                    try? await Task.sleep(nanoseconds: 180_000_000)
                }

                try? await Task.sleep(nanoseconds: 650_000_000)
                startIndex += count
            }

            await MainActor.run {
                showFloatingText = false
                highlightedCategory = nil
                showDetails = true
                loading = false
                HapticsService.success()
            }
        }
    }

    // Helper to choose a color for a category
    func colorForCategory(_ cat: String) -> Color {
        switch cat {
        case "sleep": return Color(red: 0.91, green: 0.31, blue: 0.35) // red-ish for sleep
        case "work": return MivoColors.accent
        case "eat": return Color(red: 0.96, green: 0.65, blue: 0.22)
        case "basics": return MivoColors.card
        case "scroll": return MivoColors.accentLight
        default: return MivoColors.background
        }
    }
}

private struct ResultOnboardingView_Internal: View {
    @EnvironmentObject var appVM: AppViewModel
    @Environment(\.dismiss) var dismiss

    // Accept provided age/range so remaining life matches the visualization
    let providedAge: Int?
    let providedAgeRange: String?

    @State private var estimateMinutes: Int? = nil
    @State private var estimateYears: Double? = nil
    @State private var displayYears: Double = 0.0
    @State private var appear = false
    @State private var spin = false

    var body: some View {
        ZStack {
            OnboardingBackdrop()

            VStack(spacing: 0) {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 24) {
                        OnboardingStepHeader(
                            step: 9,
                            total: 10,
                            eyebrow: "Recovery",
                            title: "We can recover this time",
                            subtitle: "Small pauses compound. Mivo turns tiny choices into visible time we can bring back."
                        )
                        .onboardingEntrance(appear)

                        recoveredWheel
                            .onboardingEntrance(appear, delay: 0.08)

                        if let mins = estimateMinutes, let years = estimateYears {
                            recoveredStats(minutes: mins, years: years)
                                .onboardingEntrance(appear, delay: 0.18)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 24)
                    .padding(.bottom, 124)
                }

                OnboardingBottomBar {
                    NavigationLink {
                        WidgetOnboardingView_Internal()
                    } label: {
                        HStack(spacing: 10) {
                            Text("Continue")
                                .font(.system(size: 16, weight: .semibold))
                            Image(systemName: "arrow.right")
                                .font(.system(size: 15, weight: .semibold))
                        }
                        .foregroundColor(MivoColors.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 17)
                        .background(MivoColors.textPrimary)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .shadow(color: MivoColors.textPrimary.opacity(0.18), radius: 16, y: 8)
                    }
                    .simultaneousGesture(TapGesture().onEnded {
                        HapticsService.impact(style: .light)
                    })
                }
            }
            .onAppear {
                appear = true
                computeEstimates()
            }
         }
         .navigationBarBackButtonHidden(true)
    }

    private var recoveredWheel: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(Color(hex: "#4A2E1F"))
                .frame(height: 330)

            Circle()
                .stroke(Color.white.opacity(0.12), lineWidth: 18)
                .frame(width: 220, height: 220)

            Circle()
                .trim(from: 0, to: CGFloat(trimFraction()))
                .stroke(
                    AngularGradient(gradient: Gradient(colors: [Color(hex: "#F3EBE3"), Color(hex: "#E6B17E"), MivoColors.accent]), center: .center),
                    style: StrokeStyle(lineWidth: 18, lineCap: .round)
                )
                .rotationEffect(.degrees(spin ? 270 : -90))
                .frame(width: 220, height: 220)
                .animation(.interpolatingSpring(stiffness: 70, damping: 11).speed(0.48), value: estimateYears)

            VStack(spacing: 7) {
                Text((estimateYears != nil || displayYears > 0) ? String(format: "%.2f", displayYears > 0 ? displayYears : (estimateYears ?? 0)) : "--")
                    .font(.system(size: 48, weight: .bold).monospacedDigit())
                    .foregroundColor(.white)
                    .contentTransition(.numericText())
                Text("years we can recover")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Color.white.opacity(0.68))
            }
        }
        .onTapGesture {
            HapticsService.impact(style: .medium)
            withAnimation(.easeOut(duration: 1.6)) { spin.toggle() }
        }
    }

    private func recoveredStats(minutes: Int, years: Double) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                recoveryStatCard(value: "\(minutes)", label: "minutes saved / day", icon: "clock.fill")
                recoveryStatCard(value: String(format: "%.1f", years * 365), label: "days we can recover", icon: "sun.max.fill")
            }

            Text("That estimate comes from your baseline, selected apps, and reasons for scrolling. It will become sharper as Mivo learns your pattern.")
                .font(.system(size: 13))
                .foregroundColor(MivoColors.textSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .padding(.horizontal, 8)
        }
    }

    private func recoveryStatCard(value: String, label: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(Color(hex: "#A97B5B"))
            Text(value)
                .font(.system(size: 25, weight: .bold).monospacedDigit())
                .foregroundColor(MivoColors.textPrimary)
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(MivoColors.textSecondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(MivoColors.white.opacity(0.64))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(MivoColors.white.opacity(0.58), lineWidth: 1))
    }

    // Compute the trim fraction for the wheel: yearsRecovered / remainingYears (clamped 0..1)
    func trimFraction() -> Double {
        guard let yrs = estimateYears else { return 0.0 }
        let life = 80
        let age = providedAge ?? appVM.onboardingProfile.age ?? 30
        var remaining = Double(life - age)
        if remaining <= 0 { remaining = Double(life) }
        if remaining <= 0 { return 0 }
        return min(1.0, yrs / remaining)
    }

    func computeEstimates() {
        let profile = appVM.onboardingProfile

        func heuristicSavedMinutes() -> Int {
            let scroll = Double(profile.scrollEstimateMinutes ?? 60)
            var multiplier: Double = 0.10
            if !profile.intentions.isEmpty {
                multiplier += Double(min(profile.intentions.count, 4)) * 0.03
                if profile.intentions.contains(.killTime) || profile.intentions.contains(.bored) { multiplier += 0.18 }
                if profile.intentions.contains(.relax) { multiplier += 0.06 }
            }
            multiplier += min(Double(profile.preferredApps.count) * 0.02, 0.12)
            var ageFactor: Double = 1.0
            let ageForFactor = providedAge ?? profile.age ?? 30
            if ageForFactor < 25 { ageFactor = 1.12 }
            else if ageForFactor > 54 { ageFactor = 0.92 }
            else if ageForFactor >= 35 && ageForFactor <= 44 { ageFactor = 0.97 }
            multiplier = max(0.06, min(multiplier, 0.75))
            var heuristicSaved = Int((scroll * multiplier * ageFactor).rounded())
            if let primary = profile.primaryIntention {
                if primary == .killTime || primary == .bored { heuristicSaved += Int(Double(max(heuristicSaved, 1)) * 0.12) }
            }
            if heuristicSaved < 3 { heuristicSaved = 3 }
            return min(heuristicSaved, 240)
        }

        func yearsRecovered(for saved: Int) -> Double {
            let life = 80
            let age = providedAge ?? profile.age ?? 30
            var remaining = life - age
            if remaining <= 0 { remaining = life }
            return (Double(saved) / (60.0 * 24.0)) * Double(remaining)
        }

        func publishEstimate(saved: Int, shouldSaveSummary: Bool) {
            let yearsRecovered = yearsRecovered(for: saved)
            withAnimation(.easeOut(duration: 0.85)) {
                estimateMinutes = saved
                estimateYears = yearsRecovered
            }
            displayYears = 0
            let steps = 22
            let duration: Double = 0.72
            for i in 0...steps {
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * (duration / Double(steps))) {
                    let pct = Double(i) / Double(steps)
                    displayYears = pct * yearsRecovered
                }
            }
            HapticsService.impact(style: .medium)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { HapticsService.success() }

            guard shouldSaveSummary else { return }
            var parts: [String] = []
            if !profile.intentions.isEmpty {
                let names = profile.intentions.map { $0.rawValue }
                parts.append("Intentions: \(names.joined(separator: ", "))")
            }
            if let s = profile.scrollEstimateMinutes { parts.append("RawEstimate: \(s) min/day") }
            parts.append("PredictedSavedMinPerDay: \(saved)")
            parts.append(String(format: "PredictedRecoveredYears: %.2f", yearsRecovered))
            if let a = profile.age { parts.append("Age: \(a)") }
            appVM.appendAISummary(parts.joined(separator: " | "))
        }

        let heuristicSaved = heuristicSavedMinutes()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            publishEstimate(saved: heuristicSaved, shouldSaveSummary: false)
        }

        Task {
            let aiSaved = await AIService.estimateSavedMinutes(profile: profile)
            var saved = max(aiSaved, heuristicSaved)
            if saved < 3 { saved = 3 }
            if saved > 240 { saved = 240 }
            await MainActor.run {
                if saved != heuristicSaved {
                    publishEstimate(saved: saved, shouldSaveSummary: true)
                } else {
                    publishEstimate(saved: saved, shouldSaveSummary: true)
                }
            }
        }
    }
}

private struct WidgetOnboardingView_Internal: View {
    @EnvironmentObject var appVM: AppViewModel
    @Environment(\.dismiss) var dismiss
    @State private var appear = false
    
    var body: some View {
        ZStack {
            OnboardingBackdrop()
            
            VStack(spacing: 0) {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 24) {
                        OnboardingStepHeader(
                            step: 10,
                            total: 10,
                            eyebrow: "Widget",
                            title: "Keep Mivo visible",
                            subtitle: "Add the Mivo widget so your scroll time and next window stay visible before you drift."
                        )
                        .onboardingEntrance(appear)
                        
                        widgetPreview
                            .onboardingEntrance(appear, delay: 0.08)
                        
                        VStack(spacing: 12) {
                            widgetInstruction(number: "1", text: "Long-press your Home Screen.")
                            widgetInstruction(number: "2", text: "Tap +, search Mivo, then choose the small or medium widget.")
                            widgetInstruction(number: "3", text: "Place it somewhere you will see before opening scroll apps.")
                        }
                        .onboardingEntrance(appear, delay: 0.16)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 24)
                    .padding(.bottom, 124)
                }
                
                OnboardingBottomBar {
                    OnboardingPrimaryButton("I added it") {
                        Image(systemName: "checkmark")
                    } action: {
                        dismiss()
                        Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 50_000_000)
                            appVM.completeOnboarding()
                            HapticsService.success()
                        }
                    }
                }
            }
            .onAppear { appear = true }
        }
        .navigationBarBackButtonHidden(true)
    }
    
    private var widgetPreview: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 9) {
                Text("Mivo")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(MivoColors.textPrimary)
                Text("42m")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundColor(MivoColors.textPrimary)
                Text("scrolled today")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(MivoColors.textSecondary)
                Spacer()
                Text("Learning mode")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(MivoColors.textPrimary)
            }
            .padding(18)
            .frame(width: 150, height: 150)
            .background(Color(hex: "#F2E8DC"))
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .shadow(color: Color.black.opacity(0.08), radius: 18, y: 10)
            
            VStack(alignment: .leading, spacing: 10) {
                Label("Today’s scroll time", systemImage: "iphone")
                Label("Next scroll window", systemImage: "clock")
                Label("Current plan state", systemImage: "target")
            }
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(MivoColors.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private func widgetInstruction(number: String, text: String) -> some View {
        HStack(spacing: 12) {
            Text(number)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(MivoColors.white)
                .frame(width: 28, height: 28)
                .background(MivoColors.textPrimary)
                .clipShape(Circle())
            
            Text(text)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(MivoColors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MivoColors.white.opacity(0.62))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(MivoColors.white.opacity(0.7), lineWidth: 1)
        )
    }
}

// Small UIKit-backed blur wrapper for SwiftUI
private struct BlurView: UIViewRepresentable {
    let style: UIBlurEffect.Style
    init(style: UIBlurEffect.Style = .systemMaterial) { self.style = style }
    func makeUIView(context: Context) -> UIVisualEffectView {
        let view = UIVisualEffectView(effect: UIBlurEffect(style: style))
        view.clipsToBounds = true
        return view
    }
    func updateUIView(_ uiView: UIVisualEffectView, context: Context) {
        uiView.effect = UIBlurEffect(style: style)
    }
}

// Lightweight UIKit-backed numeric text field for smoother entry
private struct NumericTextField: UIViewRepresentable {
    @Binding var text: String
    var placeholder: String = ""
    var fontSize: CGFloat = 36

    func makeUIView(context: Context) -> UITextField {
        let tf = UITextField()
        tf.keyboardType = .numberPad
        tf.textAlignment = .center
        tf.font = UIFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .bold)
        tf.textColor = .white
        tf.placeholder = placeholder
        tf.delegate = context.coordinator

        // Add a toolbar with Done button to dismiss number pad
        let toolbar = UIToolbar(frame: CGRect(x: 0, y: 0, width: UIScreen.main.bounds.width, height: 44))
        let flex = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
        let done = UIBarButtonItem(title: "Done", style: .done, target: context.coordinator, action: #selector(Coordinator.doneTapped))
        toolbar.items = [flex, done]
        tf.inputAccessoryView = toolbar

        tf.addTarget(context.coordinator, action: #selector(Coordinator.editingChanged(_:)), for: .editingChanged)
        return tf
    }

    func updateUIView(_ uiView: UITextField, context: Context) {
        if uiView.text != text { uiView.text = text }
        // keep placeholder and font in sync
        uiView.placeholder = placeholder
        uiView.font = UIFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .bold)
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject, UITextFieldDelegate {
        var parent: NumericTextField
        init(_ p: NumericTextField) { parent = p }

        @objc func editingChanged(_ tf: UITextField) {
            // keep only digits
            let filtered = tf.text?.filter { $0.isNumber } ?? ""
            if filtered != parent.text { parent.text = filtered }
        }

        @objc func doneTapped() {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }
    }
}

// Helper to convert SwiftUI Color to UIColor safely
private extension UIColor {
    convenience init(dynamicColor color: Color) {
        if #available(iOS 15.0, *) {
            self.init(ciColor: CIColor(color: UIColor(color)))
        } else {
            // Fallback: use fixed color
            let components = UIColor.black.cgColor.components ?? [0,0,0]
            self.init(red: components[0], green: components.count > 1 ? components[1] : 0, blue: components.count > 2 ? components[2] : 0, alpha: 1)
        }
    }
}

// Shared legend item helper view used by multiple onboarding views
@ViewBuilder
private func legendItem(color: Color, label: String) -> some View {
    HStack(spacing: 8) {
        RoundedRectangle(cornerRadius: 3)
            .fill(color)
            .frame(width: 18, height: 12)
            .overlay(RoundedRectangle(cornerRadius: 3).stroke(MivoColors.border, lineWidth: 1))
        Text(label)
            .font(.system(size: 13))
            .foregroundColor(MivoColors.textSecondary)
    }
}
