import SwiftUI

private struct Estimate {
    let label: String
    let value: Int
    let detail: String
}

private let estimates: [Estimate] = [
    .init(label: "Less than 30 min", value: 20, detail: "Light check-ins"),
    .init(label: "30-60 minutes", value: 45, detail: "A little drift"),
    .init(label: "1-2 hours", value: 90, detail: "Noticeable habit"),
    .init(label: "2-3 hours", value: 150, detail: "Easy to lose time"),
    .init(label: "4-5 hours", value: 270, detail: "Needs guardrails"),
    .init(label: "5+ hours", value: 360, detail: "Deep reset mode"),
]

struct OnboardingCalibrationView: View {
    @EnvironmentObject var appVM: AppViewModel
    @Environment(\.dismiss) var dismiss
    @State private var selected: Int? = nil
    @State private var appear = false

    var body: some View {
        ZStack {
            OnboardingBackdrop()

            VStack(spacing: 0) {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 24) {
                        OnboardingStepHeader(
                            step: 3,
                            total: 12,
                            eyebrow: "Baseline",
                            title: "How much time disappears?",
                            subtitle: "A rough estimate is enough. This gives Mivo a starting line for your first report."
                        )
                        .onboardingEntrance(appear)

                        estimateMeter
                            .onboardingEntrance(appear, delay: 0.08)

                        VStack(spacing: 10) {
                            ForEach(Array(estimates.enumerated()), id: \.element.value) { index, item in
                                Button {
                                    withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
                                        selected = item.value
                                    }
                                    HapticsService.selection()
                                } label: {
                                    OnboardingOptionRow(
                                        title: item.label,
                                        subtitle: item.detail,
                                        isSelected: selected == item.value
                                    ) {
                                        Image(systemName: selected == item.value ? "timer.circle.fill" : "timer")
                                            .font(.system(size: 18, weight: .semibold))
                                    }
                                }
                                .buttonStyle(.plain)
                                .onboardingEntrance(appear, delay: 0.14 + Double(index) * 0.04)
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 24)
                    .padding(.bottom, 120)
                }

                OnboardingBottomBar {
                    NavigationLink {
                        OnboardingGoalView()
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
                        .background(selected == nil ? MivoColors.textMuted.opacity(0.36) : MivoColors.textPrimary)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .shadow(color: selected == nil ? .clear : MivoColors.textPrimary.opacity(0.18), radius: 16, y: 8)
                    }
                    .simultaneousGesture(TapGesture().onEnded {
                        if let val = selected {
                            var profile = OnboardingProfile()
                            profile.scrollEstimateMinutes = val
                            appVM.saveOnboardingProfile(profile)
                            HapticsService.impact(style: .light)
                        }
                    })
                    .disabled(selected == nil)
                }
            }
        }
        .onboardingNavigationChromeHidden()
        .onAppear { appear = true }
    }

    private var estimateMeter: some View {
        let minutes = selected ?? 0
        let progress = min(Double(minutes) / 360.0, 1)

        return VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text(minutes == 0 ? "--" : "\(minutes)")
                    .font(.system(size: 42, weight: .bold).monospacedDigit())
                    .foregroundColor(MivoColors.textPrimary)
                    .contentTransition(.numericText())
                Text("min / day")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(MivoColors.textSecondary)
                Spacer()
                Image(systemName: "chart.bar.fill")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundColor(MivoColors.accentLight)
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(MivoColors.accentMuted)
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [MivoColors.accentLight, MivoColors.accent],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(12, proxy.size.width * progress))
                        .animation(.spring(response: 0.46, dampingFraction: 0.86), value: progress)
                }
            }
            .frame(height: 12)

            Text(selected == nil ? "Choose the closest range." : "Good. We’ll compare this against your real pattern later.")
                .font(.system(size: 13))
                .foregroundColor(MivoColors.textSecondary)
        }
        .padding(18)
        .background(Color.white.opacity(0.64))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.white.opacity(0.6), lineWidth: 1))
        .shadow(color: Color.black.opacity(0.04), radius: 14, y: 7)
    }
}

private struct OnboardingScrollWindowsView: View {
    @EnvironmentObject var appVM: AppViewModel
    @Environment(\.dismiss) var dismiss
    @State private var firstStartHour = 14
    @State private var secondStartHour = 20
    @State private var appear = false

    var body: some View {
        ZStack {
            OnboardingBackdrop()

            VStack(spacing: 0) {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 24) {
                        OnboardingStepHeader(
                            step: 5,
                            total: 12,
                            eyebrow: "Schedule",
                            title: "When do you want to scroll?",
                            subtitle: "You choose the first two daily scroll sessions. Mivo will follow these for 3 days, then recommend better times from your real pattern."
                        )
                        .onboardingEntrance(appear)

                        VStack(spacing: 14) {
                            scrollWindowPicker(
                                title: "Scroll session 1",
                                subtitle: "Pick the first time you want scrolling to be allowed.",
                                hour: $firstStartHour,
                                icon: "sun.max.fill"
                            )
                            .onboardingEntrance(appear, delay: 0.08)

                            scrollWindowPicker(
                                title: "Scroll session 2",
                                subtitle: "Pick the second time. You can change it later in Settings.",
                                hour: $secondStartHour,
                                icon: "moon.fill"
                            )
                            .onboardingEntrance(appear, delay: 0.14)
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Label("First 3 days", systemImage: "calendar.badge.clock")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(MivoColors.accent)
                            Text("Mivo will not choose your times yet. It watches what happens around your selected sessions, then recommends two times after enough data is collected.")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(MivoColors.textSecondary)
                                .lineSpacing(4)
                        }
                        .padding(16)
                        .background(Color.white.opacity(0.62))
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.white.opacity(0.58), lineWidth: 1))
                        .onboardingEntrance(appear, delay: 0.2)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 24)
                    .padding(.bottom, 120)
                }

                OnboardingBottomBar {
                    NavigationLink {
                        OnboardingAppsView()
                    } label: {
                        HStack(spacing: 10) {
                            Text("Use these times")
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
                        saveWindows()
                        HapticsService.impact(style: .light)
                    })
                }
            }
        }
        .onboardingNavigationChromeHidden()
        .onAppear {
            let windows = appVM.onboardingProfile.preferredScrollWindows ?? []
            if windows.count >= 2 {
                firstStartHour = windows[0].startHour
                secondStartHour = windows[1].startHour
            }
            appear = true
        }
    }

    private func scrollWindowPicker(title: String, subtitle: String, hour: Binding<Int>, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(MivoColors.white)
                    .frame(width: 42, height: 42)
                    .background(MivoColors.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(MivoColors.textPrimary)
                    Text(subtitle)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(MivoColors.textSecondary)
                }
                Spacer()
            }

            HStack(spacing: 12) {
                VStack(spacing: 3) {
                    Text(hourLabel(hour.wrappedValue))
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundColor(MivoColors.textPrimary)
                        .contentTransition(.numericText())
                    Text("1-hour window")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(MivoColors.textMuted)
                }
                .frame(maxWidth: .infinity)

                Menu {
                    ForEach(0..<24, id: \.self) { candidate in
                        Button {
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                                hour.wrappedValue = candidate
                            }
                            HapticsService.selection()
                        } label: {
                            if hour.wrappedValue == candidate {
                                Label(hourLabel(candidate), systemImage: "checkmark")
                            } else {
                                Text(hourLabel(candidate))
                            }
                        }
                    }
                } label: {
                    Label("Pick time", systemImage: "clock.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(OnboardingTheme.textPrimary)
                        .padding(.horizontal, 14)
                        .frame(height: 42)
                        .background(Color.white.opacity(0.7))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.58), lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .background(Color.white.opacity(0.62))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color.white.opacity(0.58), lineWidth: 1))
    }

    private func saveWindows() {
        var profile = OnboardingProfile()
        profile.preferredScrollWindows = makeWindows(first: firstStartHour, second: secondStartHour)
        appVM.saveOnboardingProfile(profile)
    }

    private func makeWindows(first: Int, second: Int) -> [ScreenScrollWindow] {
        [
            ScreenScrollWindow(
                id: "user-session-1",
                title: "Your session 1",
                startHour: first,
                endHour: min(24, first + 1),
                minutes: 15,
                reason: "You chose this time. Mivo will monitor it for 3 days."
            ),
            ScreenScrollWindow(
                id: "user-session-2",
                title: "Your session 2",
                startHour: second,
                endHour: min(24, second + 1),
                minutes: 15,
                reason: "You chose this time. Mivo will monitor it for 3 days."
            )
        ]
    }

    private func hourLabel(_ hour: Int) -> String {
        let normalized = ((hour % 24) + 24) % 24
        if normalized == 0 { return "12 AM" }
        if normalized < 12 { return "\(normalized) AM" }
        if normalized == 12 { return "12 PM" }
        return "\(normalized - 12) PM"
    }
}

// MARK: - Goal step (NEW)

/// Asks the user how much scrolling they want to do per day — the floor that
/// the personalized plan ramps down to from the observation average.
struct OnboardingGoalView: View {
    @EnvironmentObject var appVM: AppViewModel
    @Environment(\.dismiss) var dismiss
    @State private var selectedMinutes: Int = 60
    @State private var appear = false

    /// Goal options in minutes. UIKit-style wheel options.
    private let goalOptions: [Int] = [15, 20, 30, 45, 60, 75, 90, 120, 150, 180]

    var body: some View {
        ZStack {
            OnboardingBackdrop()

            VStack(spacing: 0) {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 24) {
                        OnboardingStepHeader(
                            step: 4,
                            total: 12,
                            eyebrow: "Goal",
                            title: "How much do you want to scroll each day?",
                            subtitle: "Pick a daily target. Mivo will work toward this number from your real 3-day average — gently, over weeks, not overnight."
                        )
                        .onboardingEntrance(appear)

                        goalSummaryCard
                            .onboardingEntrance(appear, delay: 0.08)

                        wheelPickerCard
                            .onboardingEntrance(appear, delay: 0.14)

                        rationaleCard
                            .onboardingEntrance(appear, delay: 0.2)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 24)
                    .padding(.bottom, 120)
                }

                OnboardingBottomBar {
                    NavigationLink {
                        OnboardingScrollWindowsView()
                    } label: {
                        HStack(spacing: 10) {
                            Text("Set my goal")
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
                        var profile = appVM.onboardingProfile
                        profile.dailyScrollGoalMinutes = selectedMinutes
                        appVM.saveOnboardingProfile(profile)
                        HapticsService.impact(style: .light)
                    })
                }
            }
        }
        .onboardingNavigationChromeHidden()
        .onAppear {
            // Pre-fill from saved value (if any), otherwise default to 60.
            if let saved = appVM.onboardingProfile.dailyScrollGoalMinutes, goalOptions.contains(saved) {
                selectedMinutes = saved
            }
            appear = true
        }
    }

    private var goalSummaryCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(selectedMinutes)")
                    .font(.system(size: 56, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundColor(MivoColors.textPrimary)
                    .contentTransition(.numericText())
                Text("min / day")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(MivoColors.textSecondary)
                Spacer()
                Image(systemName: "target")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(MivoColors.accent)
            }

            Text(goalDescription)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(MivoColors.textSecondary)
                .lineSpacing(3)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.64))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.white.opacity(0.6), lineWidth: 1))
        .shadow(color: Color.black.opacity(0.04), radius: 14, y: 7)
    }

    private var wheelPickerCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "dial.medium")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(MivoColors.accent)
                Text("Spin to choose")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(MivoColors.textPrimary)
                Spacer()
            }

            Picker("Goal minutes per day", selection: $selectedMinutes) {
                ForEach(goalOptions, id: \.self) { mins in
                    Text(displayLabel(forMinutes: mins))
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundColor(MivoColors.textPrimary)
                        .tag(mins)
                }
            }
            .pickerStyle(.wheel)
            .frame(height: 160)
            .onChange(of: selectedMinutes) { _, _ in HapticsService.selection() }
        }
        .padding(16)
        .background(Color.white.opacity(0.58))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.white.opacity(0.58), lineWidth: 1))
    }

    private var rationaleCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("How Mivo gets you there", systemImage: "arrow.down.right.circle.fill")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(MivoColors.accent)
            Text("After the 3-day observation, Mivo will tell you exactly how many days it will take to reach \(selectedMinutes) min/day. Week 1 is gentle; the daily trim grows a little every week — slowly but surely.")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(MivoColors.textSecondary)
                .lineSpacing(4)
        }
        .padding(16)
        .background(Color.white.opacity(0.62))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.white.opacity(0.58), lineWidth: 1))
    }

    private var goalDescription: String {
        switch selectedMinutes {
        case ..<25: return "A tight goal — you only want a few quick check-ins per day."
        case ..<45: return "A short scroll budget — enough to catch up on what matters."
        case ..<75: return "A balanced goal — one or two relaxed sessions per day."
        case ..<120: return "A moderate goal — comfortable room for downtime without losing the day."
        default: return "A generous goal — Mivo will still tighten things up over time."
        }
    }

    private func displayLabel(forMinutes minutes: Int) -> String {
        if minutes < 60 { return "\(minutes) min" }
        let h = minutes / 60
        let m = minutes % 60
        return m == 0 ? "\(h)h" : "\(h)h \(m)m"
    }
}
