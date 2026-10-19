import SwiftUI

/// Asks Google/Apple sign-ins to confirm their name when the provider didn't
/// return one and Mivo fell back to the email prefix (e.g. "jsmith42").
/// Presented as a compact sheet from `MainTabView`, driven by
/// `AppViewModel.evaluateNamePrompt()`.
struct NamePromptView: View {
    @EnvironmentObject var appVM: AppViewModel
    @State private var name: String = ""
    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                ZStack {
                    Circle().fill(MivoColors.accent.opacity(0.14)).frame(width: 44, height: 44)
                    Image(systemName: "person.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(MivoColors.accent)
                }
                Spacer()
                Button {
                    HapticsService.selection()
                    appVM.skipNamePromptForNow()
                } label: {
                    Text("Not now")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(MivoColors.inkMuted)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("What should we call you?")
                    .font(.system(size: 22, weight: .bold))
                    .tracking(Font.mivoTracking(-0.02, at: 22))
                    .foregroundColor(MivoColors.ink)
                Text("We didn't get a name from your sign-in, so we're using part of your email for now.")
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundColor(MivoColors.inkBody)
            }

            TextField("Your name", text: $name)
                .focused($fieldFocused)
                .textContentType(.name)
                .autocapitalization(.words)
                .disableAutocorrection(true)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(MivoColors.ink)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(MivoColors.surfaceV2)
                .clipShape(RoundedRectangle(cornerRadius: MivoMetrics.radius))
                .submitLabel(.done)
                .onSubmit(save)

            MivoPrimaryButton(
                label: "Save",
                disabled: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ) {
                HapticsService.selection()
                save()
            }
        }
        .padding(20)
        .padding(.top, 6)
        .background(MivoColors.background)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { fieldFocused = true }
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        Task { await appVM.saveDisplayName(trimmed) }
    }
}
