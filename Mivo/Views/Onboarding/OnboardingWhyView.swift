import SwiftUI

private struct IntentionOption {
    let intention: Intention
    let desc: String
    let icon: String
}

private let intentions: [IntentionOption] = [
    .init(intention: .killTime, desc: "Passing time without a specific goal", icon: "hourglass"),
    .init(intention: .relax, desc: "Unwinding and decompressing", icon: "leaf"),
    .init(intention: .bored, desc: "Nothing else felt worth doing", icon: "sparkles"),
    .init(intention: .lookingForSomethingSpecific, desc: "Searching for particular content", icon: "magnifyingglass"),
]

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
                            step: 1,
                            total: 10,
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
                            .background(MivoColors.white.opacity(0.56))
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
        .navigationBarBackButtonHidden(true)
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
