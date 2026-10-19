import SwiftUI

/// The shared list of swap options — reused by onboarding's swap step, the
/// one-time existing-user prompt, and Settings' editable version. Each host
/// owns its own save/skip buttons; this view only owns the selection.
struct SwapPickerRows: View {
    @Binding var selection: UserSwap?

    @State private var usingCustom: Bool = false
    @State private var customText: String = ""

    var body: some View {
        VStack(spacing: 10) {
            ForEach(SwapSuggestion.allCases) { suggestion in
                row(
                    title: suggestion.title,
                    icon: suggestion.icon,
                    isSelected: !usingCustom && selection?.id == suggestion.id
                ) {
                    usingCustom = false
                    selection = suggestion.swap
                }
            }
            customRow
        }
        .onAppear {
            guard let selection, selection.isCustom else { return }
            usingCustom = true
            customText = selection.title
        }
    }

    private var customRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            row(
                title: "Something else",
                icon: "sparkles",
                isSelected: usingCustom
            ) {
                usingCustom = true
                let trimmed = customText.trimmingCharacters(in: .whitespacesAndNewlines)
                selection = trimmed.isEmpty ? nil : .custom(trimmed)
            }

            if usingCustom {
                TextField("What's your swap?", text: $customText)
                    .font(.system(size: 14.5, weight: .medium))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(Color.white.opacity(0.62))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .foregroundColor(MivoColors.textPrimary)
                    .padding(.leading, 46)
                    .onChange(of: customText) { _, newValue in
                        let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                        selection = trimmed.isEmpty ? nil : .custom(trimmed)
                    }
            }
        }
    }

    private func row(title: String, icon: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            HapticsService.selection()
            action()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(isSelected ? .white : MivoColors.textPrimary)
                    .frame(width: 34, height: 34)
                    .background(isSelected ? MivoColors.textPrimary : MivoColors.card)
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(MivoColors.textPrimary)
                    .multilineTextAlignment(.leading)

                Spacer(minLength: 8)

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(MivoColors.accent)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .background(isSelected ? MivoColors.accentMuted.opacity(0.5) : Color.white.opacity(0.62))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(isSelected ? MivoColors.accent.opacity(0.4) : MivoColors.border.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
