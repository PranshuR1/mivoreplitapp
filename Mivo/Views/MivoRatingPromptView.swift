import SwiftUI

/// The periodic "rate us / give feedback" card. Presented as a compact sheet
/// from `MainTabView`, driven by `AppViewModel.evaluateRatingPrompt()` on the
/// same 60-second poll every other periodic prompt already uses.
struct MivoRatingPromptView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var showFeedback = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                ZStack {
                    Circle().fill(MivoColors.accent.opacity(0.14)).frame(width: 44, height: 44)
                    Image(systemName: "heart.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(MivoColors.accent)
                }
                Spacer()
                Button {
                    HapticsService.selection()
                    MivoRatingPromptStore.stopForever()
                    dismiss()
                } label: {
                    Text("Stop showing")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(MivoColors.inkMuted)
                }
                .accessibilityHint("Never ask again")
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Enjoying Mivo?")
                    .font(.system(size: 22, weight: .bold))
                    .tracking(Font.mivoTracking(-0.02, at: 22))
                    .foregroundColor(MivoColors.ink)
                Text("A rating helps other people find Mivo. Feedback shapes what gets built next.")
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundColor(MivoColors.inkBody)
            }

            VStack(spacing: 10) {
                MivoPrimaryButton(label: "Rate on the App Store") {
                    HapticsService.selection()
                    MivoRatingPromptAction.requestReview()
                    MivoRatingPromptStore.stopForever()
                    dismiss()
                }
                MivoInkButton(label: "Send feedback") {
                    HapticsService.selection()
                    MivoRatingPromptStore.stopForever()
                    showFeedback = true
                }
                MivoTertiaryButton(label: "Not now") {
                    HapticsService.selection()
                    dismiss()
                }
            }
        }
        .padding(20)
        .padding(.top, 6)
        .background(MivoColors.background)
        .sheet(isPresented: $showFeedback, onDismiss: { dismiss() }) {
            NavigationStack {
                FeedbackSubmissionView()
            }
        }
    }
}
