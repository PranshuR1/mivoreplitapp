import SwiftUI

/// Settings → Companion and Home → Companion land here. First-time visitors see
/// the onboarding; after that, the Companion screen.
struct CompanionEntryView: View {
    @ObservedObject private var companion = CompanionStateManager.shared

    var body: some View {
        Group {
            if companion.preferences.hasCompletedOnboarding {
                CompanionHomeView()
            } else {
                CompanionOnboardingView()
            }
        }
        .animation(MivoMotion.stepEnter, value: companion.preferences.hasCompletedOnboarding)
    }
}

struct CompanionHomeView: View {
    @ObservedObject private var companion = CompanionStateManager.shared
    @EnvironmentObject private var appVM: AppViewModel
    @State private var previewToken = 0

    private var preferences: CompanionPreferences { companion.preferences }

    var body: some View {
        ZStack {
            MivoColors.background.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    hero
                    MivoHairline()
                    if preferences.isEnabled {
                        todaySection
                        MivoHairline()
                        progressSection
                        MivoHairline()
                    } else {
                        offSection
                        MivoHairline()
                    }
                    settingsSection
                }
                .padding(.horizontal, MivoMetrics.screenPadding)
                .padding(.bottom, MivoMetrics.scrollBottomPadding)
            }
        }
        .navigationTitle("Companion")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { CompanionDeviceActivityAdapter.sync(with: appVM) }
        .onDisappear { companion.acknowledgeUnlocks() }
    }

    // MARK: Hero

    private var hero: some View {
        VStack(spacing: 6) {
            CompanionFigureView(
                type: preferences.companionType,
                state: preferences.isEnabled ? companion.presentation.state : .sleeping,
                animated: preferences.animationsEnabled,
                stretchUnlocked: companion.progress.isUnlocked(.stretching),
                playToken: previewToken,
                accessibilityName: preferences.name
            )
            .frame(height: 190)
            .padding(.top, 18)
            .onTapGesture {
                // A small acknowledgement; never changes behaviour.
                HapticsService.selection()
                previewToken += 1
            }

            Text(preferences.name)
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(MivoColors.ink)

            MivoEyebrow(
                text: preferences.isEnabled ? companion.presentation.state.label : "Companion is off"
            )

            if preferences.isEnabled, let message = companion.presentation.message {
                Text(message)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(MivoColors.inkBody)
                    .multilineTextAlignment(.center)
                    .padding(.top, 8)
                    .frame(maxWidth: 280)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 26)
    }

    // MARK: Today

    private var todaySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            MivoEyebrow(text: "Today")
            Text(companion.todaySummary)
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(MivoColors.ink)
                .fixedSize(horizontal: false, vertical: true)

            if let hint = companion.presentation.recommendation.label {
                Text(hint)
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundColor(MivoColors.inkBody)
            }

            // Honest about what it can't see.
            if let limit = companion.presentation.dataLimits.first {
                Text(limit.note)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundColor(MivoColors.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }

            if let unlocked = companion.newlyUnlocked.first {
                HStack(spacing: 10) {
                    Image(systemName: "sparkle")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(MivoColors.kept)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(unlocked.title)
                            .font(.system(size: 13.5, weight: .bold))
                            .foregroundColor(MivoColors.ink)
                        Text(unlocked.detail)
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundColor(MivoColors.inkBody)
                    }
                }
                .padding(.top, 6)
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.vertical, MivoMetrics.sectionSpacing)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var offSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("\(preferences.name) is resting. Nothing about your Screen Time or pauses changes while Companion is off.")
                .font(.system(size: 14.5, weight: .medium))
                .foregroundColor(MivoColors.inkBody)
                .fixedSize(horizontal: false, vertical: true)
            MivoPrimaryButton(label: "Turn Companion on") {
                companion.setEnabled(true)
                CompanionDeviceActivityAdapter.sync(with: appVM)
            }
        }
        .padding(.vertical, MivoMetrics.sectionSpacing)
    }

    // MARK: Progress

    private var progressSection: some View {
        let today = companion.todayRecord
        return VStack(alignment: .leading, spacing: 0) {
            MivoEyebrow(text: "Progress")
                .padding(.top, MivoMetrics.sectionSpacing)
            MivoStatColumns(items: [
                .init(value: "\(today.pauses)", label: "Pauses today"),
                .init(value: "\(today.focusSessions)", label: "Focus today"),
                .init(value: "\(companion.currentStreak)", label: "Mindful days"),
            ])
            if companion.progress.bestStreak > 0 {
                Text("Best run: \(companion.progress.bestStreak) day\(companion.progress.bestStreak == 1 ? "" : "s"). A mindful day is any day with a pause or a focus session.")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundColor(MivoColors.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 6)
            }
            ForEach(CompanionMilestone.allCases) { milestone in
                milestoneRow(milestone)
            }
            .padding(.bottom, 4)
            Color.clear.frame(height: MivoMetrics.sectionSpacing - 4)
        }
    }

    private func milestoneRow(_ milestone: CompanionMilestone) -> some View {
        let earned = companion.progress.isUnlocked(milestone)
        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: earned ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 17, weight: .regular))
                .foregroundColor(earned ? MivoColors.kept : MivoColors.inkMuted.opacity(0.7))
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                Text(milestone.title)
                    .font(.system(size: 14.5, weight: .semibold))
                    .foregroundColor(earned ? MivoColors.ink : MivoColors.inkBody)
                Text(milestone.detail)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundColor(MivoColors.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
        .accessibilityValue(earned ? "Earned" : "Not yet")
    }

    // MARK: Settings summary

    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            MivoEyebrow(text: "Settings")
                .padding(.top, MivoMetrics.sectionSpacing)
                .padding(.bottom, 4)
            settingsLink("Companion", value: preferences.isEnabled ? "On" : "Off")
            MivoHairline(soft: true)
            settingsLink("Personality", value: preferences.personality.displayName)
            MivoHairline(soft: true)
            settingsLink("Speaks up", value: preferences.interventionFrequency.displayName)
            MivoHairline(soft: true)
            settingsLink("Quiet hours", value: quietHoursSummary)
            MivoHairline(soft: true)
            settingsLink("Bedtime", value: bedtimeSummary)
            MivoHairline(soft: true)
            settingsLink("Animations", value: preferences.animationsEnabled ? "On" : "Off")
            MivoHairline(soft: true)
            settingsLink("Notifications", value: preferences.notificationsEnabled ? "On" : "Off")
        }
    }

    private func settingsLink(_ label: String, value: String) -> some View {
        NavigationLink {
            CompanionSettingsView()
        } label: {
            MivoSettingsRow(label: label, value: value)
        }
        .buttonStyle(MivoPressStyle())
    }

    private var quietHoursSummary: String {
        let quiet = preferences.quietHours
        return quiet.isEnabled ? "\(quiet.start.displayText) – \(quiet.end.displayText)" : "Off"
    }

    private var bedtimeSummary: String {
        preferences.bedtime.isEnabled ? preferences.bedtime.bedtime.displayText : "Off"
    }
}
