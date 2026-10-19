import SwiftUI

/// Lets a user change their swap any time — reachable from Settings, and
/// also where "I'll decide later" from onboarding or the one-time prompt
/// eventually gets resolved.
struct SwapSettingsView: View {
    @EnvironmentObject var appVM: AppViewModel
    @State private var selection: UserSwap?

    var body: some View {
        ZStack {
            MivoColors.background.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Cold turkey rarely works. Swapping the reward does — one real, physical thing to reach for instead of opening the app.")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(MivoColors.textSecondary)
                        .lineSpacing(3)

                    SwapPickerRows(selection: $selection)

                    Button {
                        guard let selection else { return }
                        HapticsService.success()
                        appVM.saveUserSwap(selection)
                    } label: {
                        Text("Save")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(MivoColors.textPrimary)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .disabled(selection == nil || selection == appVM.userSwap)
                    .opacity(selection == nil || selection == appVM.userSwap ? 0.5 : 1)
                }
                .padding(20)
            }
        }
        .navigationTitle("Your swap")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { selection = appVM.userSwap }
    }
}
