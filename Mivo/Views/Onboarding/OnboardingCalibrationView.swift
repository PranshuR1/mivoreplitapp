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
                            step: 2,
                            total: 3,
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
                        OnboardingAppsView()
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
        .navigationBarBackButtonHidden()
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button { dismiss() } label: {
                    Image(systemName: "arrow.left")
                        .foregroundColor(MivoColors.textSecondary)
                }
            }
        }
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
                        .fill(LinearGradient(colors: [MivoColors.accentLight, MivoColors.accent], startPoint: .leading, endPoint: .trailing))
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
        .background(MivoColors.white.opacity(0.64))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(MivoColors.white.opacity(0.6), lineWidth: 1))
        .shadow(color: Color.black.opacity(0.04), radius: 14, y: 7)
    }
}
