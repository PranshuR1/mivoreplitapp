import SwiftUI

private struct Estimate {
    let label: String
    let value: Int
}

private let estimates: [Estimate] = [
    .init(label: "Less than 30 min", value: 20),
    .init(label: "30–60 minutes", value: 45),
    .init(label: "1–2 hours", value: 90),
    .init(label: "2–3 hours", value: 150),
    .init(label: "4–5 hours", value: 270),
    .init(label: "5+ hours", value: 360),
]

struct OnboardingCalibrationView: View {
    @EnvironmentObject var appVM: AppViewModel
    @Environment(\.dismiss) var dismiss
    @State private var selected: Int? = nil
    @State private var goNext = false

    var body: some View {
        ZStack {
            MivoColors.background.ignoresSafeArea()
            VStack(spacing: 0) {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("2 of 3")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(MivoColors.textMuted)
                            .tracking(0.5)
                            .padding(.bottom, 12)

                        Text("How much time do you think you scroll per day?")
                            .font(.system(size: 26, weight: .bold))
                            .foregroundColor(MivoColors.textPrimary)
                            .tracking(-0.8)
                            .lineSpacing(4)
                            .padding(.bottom, 12)

                        Text("This is your starting estimate. Mivo will quietly compare it to reality over time.")
                            .font(.system(size: 15))
                            .foregroundColor(MivoColors.textSecondary)
                            .lineSpacing(6)
                            .padding(.bottom, 28)

                        VStack(spacing: 10) {
                            ForEach(estimates, id: \.value) { item in
                                Button {
                                    selected = item.value
                                } label: {
                                    HStack(spacing: 14) {
                                        ZStack {
                                            Circle()
                                                .strokeBorder(MivoColors.accentLight, lineWidth: 1.5)
                                                .frame(width: 20, height: 20)
                                            if selected == item.value {
                                                Circle()
                                                    .fill(MivoColors.accent)
                                                    .frame(width: 20, height: 20)
                                                Circle()
                                                    .fill(MivoColors.white)
                                                    .frame(width: 8, height: 8)
                                            }
                                        }
                                        Text(item.label)
                                            .font(.system(size: 15, weight: .medium))
                                            .foregroundColor(selected == item.value ? MivoColors.accent : MivoColors.textPrimary)
                                        Spacer()
                                    }
                                    .padding(16)
                                    .background(selected == item.value ? MivoColors.accentMuted : MivoColors.card)
                                    .clipShape(RoundedRectangle(cornerRadius: 14))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 14)
                                            .strokeBorder(selected == item.value ? MivoColors.accent : MivoColors.border, lineWidth: 1)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.bottom, 24)

                        Text("There is no right answer. Mivo works better when you're honest.")
                            .font(.system(size: 13).italic())
                            .foregroundColor(MivoColors.textMuted)
                            .lineSpacing(4)
                    }
                    .padding(.horizontal, 28)
                    .padding(.top, 16)
                    .padding(.bottom, 20)
                }

                VStack(spacing: 0) {
                    Divider().background(MivoColors.border)

                    NavigationLink {
                        OnboardingAppsView()
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
                        .background(MivoColors.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .simultaneousGesture(TapGesture().onEnded {
                        if let val = selected {
                            var profile = OnboardingProfile()
                            profile.scrollEstimateMinutes = val
                            appVM.saveOnboardingProfile(profile)
                        }
                    })
                    .padding(.horizontal, 28)
                    .padding(.top, 12)
                    .padding(.bottom, 40)
                }
                .background(MivoColors.background)
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
}
