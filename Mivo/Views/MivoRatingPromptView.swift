import SwiftUI

/// The once-a-day "leave a review / give feedback" card. Presented as a
/// compact sheet from `MainTabView`, driven by `AppViewModel.evaluateRatingPrompt()`
/// on the same 60-second poll every other periodic prompt already uses.
struct MivoRatingPromptView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var showFeedback = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 4) {
                ForEach(0..<5, id: \.self) { _ in
                    Image(systemName: "star.fill")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(MivoColors.accent)
                }
            }
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                Text("Leave Mivo a review?")
                    .font(.system(size: 22, weight: .bold))
                    .tracking(Font.mivoTracking(-0.02, at: 22))
                    .foregroundColor(MivoColors.ink)
                Text("Reviews are how other people find Mivo, and it takes about 30 seconds. Feedback shapes what gets built next.")
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundColor(MivoColors.inkBody)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 10) {
                MivoPrimaryButton(label: "Write a review") {
                    HapticsService.selection()
                    MivoRatingPromptAction.openWriteReview()
                    dismiss()
                }
                MivoInkButton(label: "Send feedback") {
                    HapticsService.selection()
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
