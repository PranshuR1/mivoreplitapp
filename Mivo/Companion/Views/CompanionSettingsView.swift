import SwiftUI

struct CompanionSettingsView: View {
    @ObservedObject private var companion = CompanionStateManager.shared
    @EnvironmentObject private var appVM: AppViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var draftName = ""
    @FocusState private var nameFocused: Bool
    @State private var previewTokens: [CompanionAnimation: Int] = [:]
    @State private var confirmReset = false

    private var preferences: CompanionPreferences { companion.preferences }

    var body: some View {
        ZStack {
            MivoColors.background.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    companionSection
                    personalitySection
                    frequencySection
                    quietHoursSection
                    bedtimeSection
                    animationsSection
                    notificationsSection
                    privacySection
                    resetSection
                }
                .padding(.horizontal, MivoMetrics.screenPadding)
                .padding(.bottom, MivoMetrics.scrollBottomPadding)
            }
        }
        .navigationTitle("Companion settings")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { draftName = preferences.name }
        .onChange(of: nameFocused) { _, focused in if !focused { commitName() } }
        .confirmationDialog("Reset companion settings?", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Reset settings", role: .destructive) {
                companion.resetPreferences()
                draftName = companion.preferences.name
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Name, personality, quiet hours and the rest go back to their defaults. Your progress is kept.")
        }
    }

    // MARK: Sections

    private var companionSection: some View {
        section("Companion") {
            toggleRow("Show my companion", isOn: Binding(
                get: { preferences.isEnabled },
                set: { newValue in
                    companion.setEnabled(newValue)
                    if newValue { CompanionDeviceActivityAdapter.sync(with: appVM) }
                }
            ))
            MivoHairline(soft: true)
            HStack {
                Text("Name")
                    .font(.system(size: 14.5, weight: .semibold))
                    .foregroundColor(MivoColors.ink)
                Spacer(minLength: 12)
                TextField(preferences.companionType.defaultName, text: $draftName)
                    .focused($nameFocused)
                    .multilineTextAlignment(.trailing)
                    .font(.system(size: 14.5, weight: .medium))
                    .foregroundColor(MivoColors.inkBody)
                    .submitLabel(.done)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .onSubmit { commitName() }
                    .onChange(of: draftName) { _, value in
                        if value.count > CompanionPreferences.maxNameLength {
                            draftName = String(value.prefix(CompanionPreferences.maxNameLength))
                        }
                    }
            }
            .padding(.vertical, 15)
            .frame(minHeight: 44)
            MivoHairline(soft: true)
            VStack(alignment: .leading, spacing: 10) {
                ForEach(CompanionType.available) { type in
                    HStack(spacing: 14) {
                        CompanionFigureView(type: type, state: .idle, animated: false, accessibilityName: nil)
                            .frame(width: 40, height: 52)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(type.displayName)
                                .font(.system(size: 14.5, weight: .semibold))
                                .foregroundColor(MivoColors.ink)
                            Text(type.tagline)
                                .font(.system(size: 12.5, weight: .medium))
                                .foregroundColor(MivoColors.inkMuted)
                        }
                        Spacer()
                        Image(systemName: preferences.companionType == type ? "checkmark.circle.fill" : "circle")
                            .foregroundColor(preferences.companionType == type ? MivoColors.kept : MivoColors.inkMuted)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { companion.updatePreferences { $0.companionType = type } }
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(preferences.companionType == type ? [.isButton, .isSelected] : .isButton)
                }
                // Only characters that are finished appear as choices.
                Text("More companions are on the way.")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundColor(MivoColors.inkMuted)
            }
            .padding(.vertical, 14)
        }
    }

    private var personalitySection: some View {
        section("Personality", footer: "Personality only changes the words. It never changes when Mivo pauses or blocks an app.") {
            ForEach(CompanionPersonality.allCases) { personality in
                MivoOptionRow(
                    label: personality.displayName,
                    note: personality.example,
                    isSelected: preferences.personality == personality
                ) {
                    companion.updatePreferences { $0.personality = personality }
                }
                .padding(.vertical, 3)
            }
        }
    }

    private var frequencySection: some View {
        section("How often it speaks up", footer: "This only limits the companion's words. Your pauses and shields work exactly as before.") {
            ForEach(CompanionInterventionFrequency.allCases) { frequency in
                MivoOptionRow(
                    label: frequency.displayName,
                    note: frequency.summary,
                    isSelected: preferences.interventionFrequency == frequency
                ) {
                    companion.updatePreferences { $0.interventionFrequency = frequency }
                }
                .padding(.vertical, 3)
            }
        }
    }

    private var quietHoursSection: some View {
        section("Quiet hours", footer: "While it's asleep the companion shows no messages and sends no notifications. Mivo's own pauses still run.") {
            toggleRow("Let it sleep", isOn: Binding(
                get: { preferences.quietHours.isEnabled },
                set: { value in companion.updatePreferences { $0.quietHours.isEnabled = value } }
            ))
            if preferences.quietHours.isEnabled {
                MivoHairline(soft: true)
                timeRow("From", \.quietHours.start)
                MivoHairline(soft: true)
                timeRow("Until", \.quietHours.end)
            }
        }
    }

    private var bedtimeSection: some View {
        section("Bedtime", footer: "Around bedtime the companion gets sleepy and speaks more gently about the hour.") {
            toggleRow("Wind down at night", isOn: Binding(
                get: { preferences.bedtime.isEnabled },
                set: { value in companion.updatePreferences { $0.bedtime.isEnabled = value } }
            ))
            if preferences.bedtime.isEnabled {
                MivoHairline(soft: true)
                timeRow("Bedtime", \.bedtime.bedtime)
                MivoHairline(soft: true)
                timeRow("Wake time", \.bedtime.wakeTime)
                MivoHairline(soft: true)
                HStack {
                    Text("Starts getting sleepy")
                        .font(.system(size: 14.5, weight: .semibold))
                        .foregroundColor(MivoColors.ink)
                    Spacer()
                    Stepper(
                        "\(preferences.bedtime.windDownMinutes) min before",
                        value: Binding(
                            get: { preferences.bedtime.windDownMinutes },
                            set: { value in companion.updatePreferences { $0.bedtime.windDownMinutes = value } }
                        ),
                        in: CompanionBedtime.windDownRange,
                        step: 15
                    )
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(MivoColors.inkBody)
                    .fixedSize()
                }
                .padding(.vertical, 10)
            }
        }
    }

    private var animationsSection: some View {
        section("Animations") {
            toggleRow("Animate the companion", isOn: Binding(
                get: { preferences.animationsEnabled },
                set: { value in companion.updatePreferences { $0.animationsEnabled = value } }
            ))
            if reduceMotion {
                Text("Reduce Motion is on in iOS, so the companion stays still. Previews below are paused too.")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundColor(MivoColors.inkMuted)
                    .padding(.bottom, 8)
            }
            MivoEyebrow(text: "Preview")
                .padding(.top, 8)
                .padding(.bottom, 10)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 10)], spacing: 10) {
                ForEach(CompanionAnimation.allCases) { clip in
                    animationTile(clip)
                }
            }
            .padding(.bottom, 6)
        }
    }

    private func animationTile(_ clip: CompanionAnimation) -> some View {
        let unlocked = companion.progress.isUnlocked(clip)
        return Button {
            guard unlocked else { return }
            HapticsService.selection()
            previewTokens[clip, default: 0] += 1
        } label: {
            VStack(spacing: 6) {
                CompanionFigureView(
                    type: preferences.companionType,
                    state: clip.previewState,
                    clip: clip,
                    animated: true,
                    stretchUnlocked: true,
                    playToken: previewTokens[clip, default: 0]
                )
                .frame(height: 84)
                .opacity(unlocked ? 1 : 0.35)
                Text(clip.label)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(unlocked ? MivoColors.ink : MivoColors.inkMuted)
                if !unlocked {
                    Text("After 3 pauses")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundColor(MivoColors.inkMuted)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(MivoColors.surfaceV2)
            .clipShape(RoundedRectangle(cornerRadius: MivoMetrics.radius))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(unlocked ? "Preview \(clip.label) animation" : "\(clip.label) animation, unlocks after three pauses")
    }

    private var notificationsSection: some View {
        section("Notifications", footer: notificationsFooter) {
            toggleRow("Companion notifications", isOn: Binding(
                get: { preferences.notificationsEnabled },
                set: { value in companion.updatePreferences { $0.notificationsEnabled = value } }
            ))
            .disabled(!appVM.settings.notificationsEnabled)
            .opacity(appVM.settings.notificationsEnabled ? 1 : 0.5)
        }
    }

    private var notificationsFooter: String {
        if !appVM.settings.notificationsEnabled {
            return "Notifications are off in Mivo. Turn them on in Settings first — Companion never asks for permission on its own."
        }
        return "A bedtime note and, at most once a day, a gentle offer to start a focus session. Never during quiet hours."
    }

    private var privacySection: some View {
        section("Privacy") {
            Text("Mivo Companion reacts to your Screen Time patterns — not what's on your screen. It never sees what you type, your messages, photos, web pages or passwords, and it stores only small daily counts on this device.")
                .font(.system(size: 13.5, weight: .medium))
                .foregroundColor(MivoColors.inkBody)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 4)
        }
    }

    private var resetSection: some View {
        VStack(spacing: 0) {
            MivoTertiaryButton(label: "Reset companion settings", color: MivoColors.inkMuted) {
                confirmReset = true
            }
            .padding(.top, 14)
        }
    }

    // MARK: Building blocks

    private func section<Content: View>(
        _ title: String,
        footer: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                MivoEyebrow(text: title)
                    .padding(.bottom, 6)
                content()
                if let footer {
                    Text(footer)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundColor(MivoColors.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 8)
                }
            }
            .padding(.vertical, MivoMetrics.sectionSpacing)
            MivoHairline()
        }
    }

    private func toggleRow(_ label: String, isOn: Binding<Bool>) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 14.5, weight: .semibold))
                .foregroundColor(MivoColors.ink)
            Spacer(minLength: 12)
            MivoToggle(isOn: isOn, label: label)
        }
        .padding(.vertical, 12)
        .frame(minHeight: 44)
    }

    private func timeRow(_ label: String, _ keyPath: WritableKeyPath<CompanionPreferences, CompanionClockTime>) -> some View {
        DatePicker(
            selection: Binding(
                get: { Self.date(for: preferences[keyPath: keyPath]) },
                set: { newValue in
                    let time = CompanionClockTime.of(newValue, calendar: Calendar.current)
                    companion.updatePreferences { $0[keyPath: keyPath] = time }
                }
            ),
            displayedComponents: .hourAndMinute
        ) {
            Text(label)
                .font(.system(size: 14.5, weight: .semibold))
                .foregroundColor(MivoColors.ink)
        }
        .padding(.vertical, 6)
        .frame(minHeight: 44)
    }

    private static func date(for time: CompanionClockTime) -> Date {
        Calendar.current.date(bySettingHour: time.hour, minute: time.minute, second: 0, of: Date()) ?? Date()
    }

    private func commitName() {
        let sanitized = CompanionPreferences.sanitizedName(draftName, for: preferences.companionType)
        draftName = sanitized
        companion.updatePreferences { $0.name = sanitized }
    }
}
