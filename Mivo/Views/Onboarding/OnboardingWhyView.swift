import SwiftUI

private struct IntentionOption {
    let intention: Intention
    let desc: String
    let icon: String
}

private struct ReferralSourceOption {
    let value: String
    let title: String
    let desc: String
    let icon: String
}

private let referralSources: [ReferralSourceOption] = [
    .init(value: "youtube", title: "YouTube", desc: "A video, short, creator, or channel", icon: "play.rectangle.fill"),
    .init(value: "instagram", title: "Instagram", desc: "A post, reel, story, or creator", icon: "camera.fill"),
    .init(value: "tiktok", title: "TikTok", desc: "A video, search, or creator mention", icon: "music.note"),
    .init(value: "friend", title: "Friend", desc: "Someone sent it to you or told you", icon: "person.2.fill"),
    .init(value: "linkedin", title: "LinkedIn", desc: "A post, profile, comment, or message", icon: "briefcase.fill"),
    .init(value: "ambassador", title: "Ambassador", desc: "A Mivo ambassador introduced you", icon: "person.crop.circle.badge.checkmark"),
]

private let intentions: [IntentionOption] = [
    .init(intention: .killTime, desc: "Passing time without a specific goal", icon: "hourglass"),
    .init(intention: .relax, desc: "Unwinding and decompressing", icon: "leaf"),
    .init(intention: .bored, desc: "Nothing else felt worth doing", icon: "sparkles"),
    .init(intention: .lookingForSomethingSpecific, desc: "Searching for particular content", icon: "magnifyingglass"),
]

struct OnboardingReferralSourceView: View {
    @EnvironmentObject var appVM: AppViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var selected: String? = nil
    @State private var ambassadorName = ""
    @State private var appear = false
    @FocusState private var ambassadorNameFocused: Bool

    private var canFinish: Bool {
        guard let selected else { return false }
        return selected != "ambassador" || !ambassadorName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        ZStack {
            OnboardingBackdrop()

            VStack(spacing: 0) {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 24) {
                        OnboardingStepHeader(
                            step: 12,
                            total: 12,
                            eyebrow: "Source",
                            title: "Where did you find us?",
                            subtitle: "Pick the place that brought you here. This helps us understand what is actually reaching people."
                        )
                        .onboardingEntrance(appear)

                        VStack(spacing: 12) {
                            ForEach(Array(referralSources.enumerated()), id: \.element.value) { index, item in
                                Button {
                                    withAnimation(.spring(response: 0.34, dampingFraction: 0.78)) {
                                        selected = item.value
                                    }
                                    HapticsService.selection()
                                } label: {
                                    OnboardingOptionRow(
                                        title: item.title,
                                        subtitle: item.desc,
                                        isSelected: selected == item.value
                                    ) {
                                        Image(systemName: item.icon)
                                            .font(.system(size: 17, weight: .semibold))
                                    }
                                }
                                .buttonStyle(.plain)
                                .onboardingEntrance(appear, delay: 0.08 + Double(index) * 0.05)

                                if item.value == "ambassador", selected == "ambassador" {
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text("Ambassador's name")
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundColor(MivoColors.textSecondary)

                                        TextField("Enter their name", text: $ambassadorName)
                                            .textInputAutocapitalization(.words)
                                            .autocorrectionDisabled(false)
                                            .focused($ambassadorNameFocused)
                                            .font(.system(size: 16, weight: .medium))
                                            .foregroundColor(MivoColors.textPrimary)
                                            .padding(.horizontal, 16)
                                            .frame(height: 54)
                                            .background(MivoColors.card)
                                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                                    .strokeBorder(MivoColors.accent.opacity(0.45), lineWidth: 1)
                                            )
                                            .onChange(of: ambassadorName) { _, value in
                                                if value.count > 80 {
                                                    ambassadorName = String(value.prefix(80))
                                                }
                                            }
                                    }
                                    .padding(.leading, 12)
                                    .transition(.move(edge: .top).combined(with: .opacity))
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 24)
                    .padding(.bottom, 120)
                }

                OnboardingBottomBar {
                    OnboardingPrimaryButton("Finish setup") {
                        Image(systemName: "checkmark")
                    } action: {
                        guard let selected else { return }
                        var profile = OnboardingProfile()
                        profile.referralSource = selected
                        profile.referralAmbassadorName = selected == "ambassador"
                            ? ambassadorName.trimmingCharacters(in: .whitespacesAndNewlines)
                            : nil
                        appVM.saveOnboardingProfile(profile)
                        dismiss()
                        Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 50_000_000)
                            appVM.completeOnboarding()
                            HapticsService.success()
                        }
                    }
                    .disabled(!canFinish)
                    .opacity(canFinish ? 1 : 0.5)
                    .simultaneousGesture(TapGesture().onEnded {
                        HapticsService.impact(style: .light)
                    })
                }
            }
        }
        .onboardingNavigationChromeHidden()
        .background(DisableBackSwipe())
        .onAppear {
            selected = appVM.onboardingProfile.referralSource
            ambassadorName = appVM.onboardingProfile.referralAmbassadorName ?? ""
            appear = true
        }
        .onChange(of: selected) { _, value in
            if value == "ambassador" {
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 220_000_000)
                    ambassadorNameFocused = true
                }
            } else {
                ambassadorNameFocused = false
            }
        }
    }
}

struct OnboardingWhyView: View {
    @EnvironmentObject var appVM: AppViewModel
    @State private var selected: Set<Intention> = []
    @State private var appear = false

    var body: some View {
        ZStack {
            OnboardingBackdrop()

            VStack(spacing: 0) {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 24) {
                        OnboardingStepHeader(
                            step: 2,
                            total: 12,
                            eyebrow: "Pattern",
                            title: "What usually pulls you in?",
                            subtitle: "Pick the reasons that feel true. Mivo uses this to make the pause feel personal, not preachy."
                        )
                        .onboardingEntrance(appear)

                        VStack(spacing: 12) {
                            ForEach(Array(intentions.enumerated()), id: \.element.intention) { index, item in
                                Button {
                                    withAnimation(.spring(response: 0.34, dampingFraction: 0.78)) {
                                        if selected.contains(item.intention) {
                                            selected.remove(item.intention)
                                        } else {
                                            selected.insert(item.intention)
                                        }
                                    }
                                    HapticsService.selection()
                                } label: {
                                    OnboardingOptionRow(
                                        title: item.intention.rawValue,
                                        subtitle: item.desc,
                                        isSelected: selected.contains(item.intention)
                                    ) {
                                        Image(systemName: item.icon)
                                            .font(.system(size: 17, weight: .semibold))
                                    }
                                }
                                .buttonStyle(.plain)
                                .onboardingEntrance(appear, delay: 0.08 + Double(index) * 0.05)
                            }
                        }

                        Text("\(selected.count) selected")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(MivoColors.textSecondary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(MivoColors.surfaceRaised.opacity(0.56))
                            .clipShape(Capsule())
                            .opacity(selected.isEmpty ? 0 : 1)
                            .animation(.easeInOut(duration: 0.2), value: selected.count)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 24)
                    .padding(.bottom, 120)
                }

                OnboardingBottomBar {
                    NavigationLink {
                        OnboardingCalibrationView()
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
                        .background(selected.isEmpty ? MivoColors.textMuted.opacity(0.36) : MivoColors.textPrimary)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .shadow(color: selected.isEmpty ? .clear : MivoColors.textPrimary.opacity(0.18), radius: 16, y: 8)
                    }
                    .simultaneousGesture(TapGesture().onEnded {
                        guard !selected.isEmpty else { return }
                        var profile = OnboardingProfile()
                        profile.intentions = Array(selected)
                        profile.primaryIntention = profile.intentions.first
                        appVM.saveOnboardingProfile(profile)
                        HapticsService.impact(style: .light)
                    })
                    .disabled(selected.isEmpty)
                }
            }
        }
        .onboardingNavigationChromeHidden()
        .background(DisableBackSwipe())
        .onAppear { appear = true }
    }
}

struct DisableBackSwipe: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UIViewController {
        Controller()
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}

    class Controller: UIViewController {
        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            navigationController?.interactivePopGestureRecognizer?.isEnabled = false
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            navigationController?.interactivePopGestureRecognizer?.isEnabled = true
        }
    }
}
