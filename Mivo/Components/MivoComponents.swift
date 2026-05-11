import SwiftUI

// MARK: - MivoButton

struct MivoButton: View {
    enum Variant { case primary, secondary, ghost }

    let label: String
    let action: () -> Void
    var variant: Variant = .primary
    var loading: Bool = false
    var disabled: Bool = false
    var icon: String? = nil

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if loading {
                    ProgressView()
                        .tint(variant == .primary ? MivoColors.white : MivoColors.accent)
                        .scaleEffect(0.85)
                } else {
                    if let icon {
                        Image(systemName: icon)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(variant == .primary ? MivoColors.white : MivoColors.accent)
                    }
                    Text(label)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(buttonTextColor)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(buttonBackground)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(variant == .secondary ? MivoColors.border : .clear, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .opacity((disabled || loading) ? 0.5 : 1)
        }
        .disabled(disabled || loading)
    }

    var buttonTextColor: Color {
        switch variant {
        case .primary: return MivoColors.white
        case .secondary: return MivoColors.accent
        case .ghost: return MivoColors.textMuted
        }
    }

    var buttonBackground: some View {
        Group {
            switch variant {
            case .primary: MivoColors.accent
            case .secondary: MivoColors.card
            case .ghost: Color.clear
            }
        }
    }
}

// MARK: - MivoCard

struct MivoCard<Content: View>: View {
    let content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View {
        content()
            .padding(16)
            .background(MivoColors.card)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(MivoColors.border, lineWidth: 1)
            )
    }
}

// MARK: - MivoLoadingOverlay

struct MivoLoadingOverlay: View {
    let message: String

    var body: some View {
        ZStack {
            Color.black.opacity(0.14)
                .ignoresSafeArea()

            VStack(spacing: 12) {
                ProgressView()
                    .tint(MivoColors.accent)
                    .scaleEffect(1.08)
                Text(message)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(MivoColors.textPrimary)
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 18)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(MivoColors.white.opacity(0.5), lineWidth: 1)
            )
            .shadow(color: MivoColors.primary.opacity(0.18), radius: 18, y: 8)
        }
    }
}

// MARK: - MivoTextField

struct MivoTextField: View {
    let label: String?
    let placeholder: String
    @Binding var text: String
    var error: String? = nil
    var isSecure: Bool = false
    var keyboardType: UIKeyboardType = .default
    var submitLabel: SubmitLabel = .done
    var onSubmit: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let label {
                Text(label)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(MivoColors.textSecondary)
            }
            Group {
                if isSecure {
                    SecureField(placeholder, text: $text)
                } else {
                    TextField(placeholder, text: $text)
                        .keyboardType(keyboardType)
                }
            }
            .font(.system(size: 16))
            .foregroundColor(MivoColors.textPrimary)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(MivoColors.card)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(error != nil ? MivoColors.timerRed : MivoColors.border, lineWidth: 1)
            )
            .submitLabel(submitLabel)
            .onSubmit { onSubmit?() }

            if let error {
                Text(error)
                    .font(.system(size: 13))
                    .foregroundColor(MivoColors.timerRed)
            }
        }
    }
}

// MARK: - MivoLogo

struct MivoLogo: View {
    var size: CGFloat = 52

    var body: some View {
        Image("MivoLogo")
            .resizable()
            .scaledToFill()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.22))
    }
}

// MARK: - Helpers

struct SectionHeader: View {
    let title: String
    var body: some View {
        Text(title)
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(MivoColors.textMuted)
            .tracking(0.5)
            .textCase(.uppercase)
    }
}

extension View {
    func mivoBackground() -> some View {
        self.background(MivoColors.background.ignoresSafeArea())
    }
}

// MARK: - Formats

func formatDuration(_ minutes: Int) -> String {
    if minutes == 0 { return "0m" }
    if minutes < 60 { return "\(minutes)m" }
    let h = minutes / 60
    let m = minutes % 60
    return m > 0 ? "\(h)h \(m)m" : "\(h)h"
}

func formatSeconds(_ totalSeconds: Int) -> String {
    let s = abs(totalSeconds)
    let m = s / 60
    let sec = s % 60
    return String(format: "%d:%02d", m, sec)
}

func greeting() -> String {
    let hour = Calendar.current.component(.hour, from: Date())
    if hour < 12 { return "Good morning" }
    if hour < 17 { return "Good afternoon" }
    return "Good evening"
}
