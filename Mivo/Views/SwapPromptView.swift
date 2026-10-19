import SwiftUI

/// One-time ask for existing users who signed up before this feature shipped
/// and so never saw `OnboardingSwapView`. See `AppViewModel.evaluateSwapPrompt()`
/// for the ask-once gating.
struct SwapPromptView: View {
    @EnvironmentObject var appVM: AppViewModel
    @State private var selection: UserSwap? = nil

    var body: some View {
        ZStack {
            MivoColors.background.ignoresSafeArea()
            VStack(spacing: 16) {
                HStack {
                    Spacer()
                    Button {
                        HapticsService.selection()
                        appVM.skipSwapPromptForNow()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(MivoColors.textSecondary)
                            .frame(width: 32, height: 32)
                            .background(MivoColors.card)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 8)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Pick your swap")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundColor(MivoColors.textPrimary)
                    Text("Cold turkey rarely works. Swapping the reward does — pick one real, physical thing to reach for instead of opening the app. Not sure? Any of these work.")
                        .font(.system(size: 15))
                        .foregroundColor(MivoColors.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                ScrollView(showsIndicators: false) {
                    SwapPickerRows(selection: $selection)
                }

                Spacer(minLength: 8)

                VStack(spacing: 10) {
                    Button {
                        guard let selection else { return }
                        HapticsService.success()
                        appVM.saveUserSwap(selection)
                    } label: {
                        Text("Set my swap")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(MivoColors.textPrimary)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .shadow(color: MivoColors.textPrimary.opacity(0.18), radius: 16, y: 8)
                    }
                    .disabled(selection == nil)
                    .opacity(selection == nil ? 0.5 : 1)

                    Button("I'll decide later") {
                        HapticsService.selection()
                        appVM.skipSwapPromptForNow()
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(MivoColors.textMuted)
                }
                .padding(.bottom, 8)
            }
            .padding(.horizontal, 28)
        }
    }
}
