import SwiftUI

private struct IntentionOption {
    let intention: Intention
    let desc: String
}

private let intentions: [IntentionOption] = [
    .init(intention: .killTime, desc: "Passing time without a specific goal"),
    .init(intention: .relax, desc: "Unwinding and decompressing"),
    .init(intention: .bored, desc: "Nothing else felt worth doing"),
    .init(intention: .lookingForSomethingSpecific, desc: "Searching for particular content"),
]

struct OnboardingWhyView: View {
    @EnvironmentObject var appVM: AppViewModel
//    @Environment(\.dismiss) var dismiss
    @State private var selected: Set<Intention> = []
    @State private var goNext = false

    var body: some View {
        ZStack {
            MivoColors.background.ignoresSafeArea()
            VStack(spacing: 0) {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("1 of 3")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(MivoColors.textMuted)
                            .tracking(0.5)
                            .padding(.bottom, 12)

                        Text("Why do you usually open social apps?")
                            .font(.system(size: 26, weight: .bold))
                            .foregroundColor(MivoColors.textPrimary)
                            .tracking(-0.8)
                            .lineSpacing(4)
                            .padding(.bottom, 12)

                        Text("Most scrolling happens on autopilot. Knowing your reason helps Mivo understand your patterns.")
                            .font(.system(size: 15))
                            .foregroundColor(MivoColors.textSecondary)
                            .lineSpacing(6)
                            .padding(.bottom, 32)

                        VStack(spacing: 10) {
                            ForEach(intentions, id: \.intention) { item in
                                Button {
                                    if selected.contains(item.intention) { selected.remove(item.intention) }
                                    else { selected.insert(item.intention) }
                                } label: {
                                    HStack(spacing: 14) {
                                        ZStack {
                                            Circle()
                                                .strokeBorder(MivoColors.accentLight, lineWidth: 1.5)
                                                .frame(width: 22, height: 22)
                                            if selected.contains(item.intention) {
                                                Circle()
                                                    .fill(MivoColors.accent)
                                                    .frame(width: 22, height: 22)
                                                Image(systemName: "checkmark")
                                                    .font(.system(size: 11, weight: .semibold))
                                                    .foregroundColor(.white)
                                            }
                                        }
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(item.intention.rawValue)
                                                .font(.system(size: 15, weight: .semibold))
                                                .foregroundColor(selected.contains(item.intention) ? MivoColors.accent : MivoColors.textPrimary)
                                            Text(item.desc)
                                                .font(.system(size: 13))
                                                .foregroundColor(MivoColors.textSecondary)
                                        }
                                        Spacer()
                                    }
                                    .padding(16)
                                    .background(selected.contains(item.intention) ? MivoColors.accentMuted : MivoColors.card)
                                    .clipShape(RoundedRectangle(cornerRadius: 14))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 14)
                                            .strokeBorder(selected.contains(item.intention) ? MivoColors.accent : MivoColors.border, lineWidth: 1)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.horizontal, 28)
                    .padding(.top, 16)
                    .padding(.bottom, 20)
                }

                VStack(spacing: 0) {
                    Divider().background(MivoColors.border)

                    NavigationLink {
                        OnboardingCalibrationView()
                    } label: {
                        HStack(spacing: 8) {
                            Text("Next")
                                .font(.system(size: 16, weight: .semibold))
                            Image(systemName: "arrow.right")
                                .font(.system(size: 16, weight: .medium))
                        }
                        .foregroundColor(MivoColors.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(selected.isEmpty ? MivoColors.card : MivoColors.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .simultaneousGesture(TapGesture().onEnded {
                        // Save selections before navigating
                        guard !selected.isEmpty else { return }
                        var profile = OnboardingProfile()
                        profile.intentions = Array(selected)
                        profile.primaryIntention = profile.intentions.first
                        appVM.saveOnboardingProfile(profile)
                    })
                    .padding(.horizontal, 28)
                    .padding(.top, 12)
                    .padding(.bottom, 40)
                    .disabled(selected.isEmpty)
                }
                .background(MivoColors.background)
            }
        }
        .navigationBarBackButtonHidden(true)
        // Disable swipe-to-go-back while on this required onboarding step
        .background(DisableBackSwipe())
    }
}

// Small helper to disable the interactive pop gesture (swipe back)
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
            // Re-enable when leaving
            navigationController?.interactivePopGestureRecognizer?.isEnabled = true
        }
    }
}
