import SwiftUI

struct OnboardingAgeView: View {
    @EnvironmentObject var appVM: AppViewModel
    @Environment(\.dismiss) var dismiss
    @State private var ageText = ""
    @State private var selectedRange: String? = nil
    @State private var goNext = false
    @State private var appear = false

    private let ranges = ["Under 18", "18-24", "25-34", "35-44", "45-54", "55+"]

    var body: some View {
        ZStack {
            MivoColors.background.ignoresSafeArea()
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Age")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundColor(MivoColors.textPrimary)
                    Text("This helps Mivo tailor suggestions for your life stage. Optional.")
                        .font(.system(size: 15))
                        .foregroundColor(MivoColors.textSecondary)
                }
                .padding(.horizontal, 28)

                VStack(spacing: 12) {
                    TextField("Enter your age", text: $ageText)
                        .keyboardType(.numberPad)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 14)
                        .background(Color.white.opacity(0.62))
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .foregroundColor(MivoColors.textPrimary)
                        .onChange(of: ageText) { _, _ in HapticsService.selection() }

                    Text("Or pick an age range")
                        .font(.system(size: 13))
                        .foregroundColor(MivoColors.textMuted)

                    HStack(spacing: 10) {
                        ForEach(ranges, id: \.self) { r in
                            Button {
                                withAnimation { selectedRange = (selectedRange == r ? nil : r) }
                                HapticsService.impact(style: .light)
                            } label: {
                                Text(r)
                                    .font(.system(size: 13, weight: .medium))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 10)
                                    .background(selectedRange == r ? MivoColors.accentMuted : MivoColors.card)
                                    .foregroundColor(selectedRange == r ? MivoColors.accent : MivoColors.textPrimary)
                                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 8)
                }
                .padding(.horizontal, 28)

                Spacer()

                NavigationLink {
                    OnboardingResultView()
                } label: {
                    Text("Continue")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(MivoColors.textPrimary)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .shadow(color: MivoColors.textPrimary.opacity(0.18), radius: 16, y: 8)
                }
                .simultaneousGesture(TapGesture().onEnded {
                    // Save age info
                    var profile = OnboardingProfile()
                    if let age = Int(ageText), age > 0 { profile.age = age }
                    profile.ageRange = selectedRange
                    appVM.saveOnboardingProfile(profile)
                    HapticsService.success()
                })
                .padding(.horizontal, 28)
                .padding(.bottom, 40)
                .disabled(ageText.isEmpty && selectedRange == nil)
            }
            .opacity(appear ? 1 : 0)
            .offset(y: appear ? 0 : 12)
            .animation(.easeOut(duration: 0.45), value: appear)
            .onAppear { appear = true }
        }
        .onboardingNavigationChromeHidden()
    }
}
