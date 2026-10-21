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
            .frame(height: 54)
            .background(buttonBackground)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(variant == .secondary ? MivoColors.border : .clear, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .opacity((disabled || loading) ? 0.5 : 1)
        }
        .buttonStyle(MivoPressStyle())
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
            .background(MivoColors.surfaceRaised.opacity(0.58))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
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
            .textCase(.uppercase)
    }
}

// MARK: - Seamless Layout

struct MivoPageHeader: View {
    let title: String
    var subtitle: String? = nil
    var eyebrow: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            if let eyebrow {
                Text(eyebrow.uppercased())
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(MivoColors.accent)
            }
            Text(title)
                .font(.system(size: 27, weight: .bold, design: .rounded))
                .foregroundColor(MivoColors.textPrimary)
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(MivoColors.textSecondary)
                    .lineSpacing(3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - C3 Insight-First Surfaces

struct MivoFeatureIcon: View {
    let systemName: String
    var tint: Color = MivoColors.accent
    var size: CGFloat = 42

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size * 0.38, weight: .bold))
            .foregroundColor(tint)
            .frame(width: size, height: size)
            .background(tint.opacity(0.10))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct MivoSectionLabel: View {
    let title: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(MivoColors.textMuted)
            Spacer()
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(MivoColors.blue)
                    .buttonStyle(.plain)
            }
        }
    }
}

struct MivoSection<Content: View>: View {
    let title: String?
    let content: Content

    init(_ title: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title {
                Text(title.uppercased())
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(MivoColors.textMuted)
            }
            content
        }
        .mivoSectionSurface()
    }
}

extension View {
    func mivoReadableWidth(_ maxWidth: CGFloat = 760) -> some View {
        self
            .frame(maxWidth: maxWidth)
            .frame(maxWidth: .infinity)
    }

    func mivoSectionSurface(padding: CGFloat = 16) -> some View {
        self
            .padding(.vertical, padding)
            .padding(.horizontal, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(MivoColors.surface.opacity(0.25))
            .overlay(alignment: .top) {
                Rectangle().fill(MivoColors.border.opacity(0.36)).frame(height: 1)
            }
            .overlay(alignment: .bottom) {
                Rectangle().fill(MivoColors.border.opacity(0.36)).frame(height: 1)
            }
    }

    func mivoInsetSurface() -> some View {
        self
            .background(MivoColors.surfaceRaised.opacity(0.52))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(MivoColors.border.opacity(0.34), lineWidth: 1)
            }
    }

    func mivoC3Section(verticalPadding: CGFloat = 18) -> some View {
        self
            .padding(.vertical, verticalPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .top) {
                Rectangle().fill(MivoColors.border.opacity(0.30)).frame(height: 1)
            }
    }
}

struct MivoProgressSegments: View {
    let completed: Int
    var total: Int = 7
    var tint: Color = MivoColors.blue

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<max(1, total), id: \.self) { index in
                Capsule()
                    .fill(index < completed ? tint : MivoColors.border.opacity(0.28))
                    .frame(height: 7)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Progress")
        .accessibilityValue("\(min(max(0, completed), total)) of \(total) days")
    }
}

struct MivoPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
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

/// Stands in for a figure Mivo cannot currently measure.
///
/// Showing this instead of a plausible-looking number is the point: a wrong
/// total silently teaches the user the wrong thing about their own behaviour.
struct MivoDataUnavailable: View {
    let reason: MivoDataUnavailableReason
    var compact: Bool = false
    var retry: (() -> Void)?

    var body: some View {
        if compact {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 11, weight: .bold))
                Text(reason.title)
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundColor(MivoColors.textMuted)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(reason.title). \(reason.detail)")
        } else {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(MivoColors.accent)
                    .frame(width: 32, height: 32)
                    .background(MivoColors.accent.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(reason.title)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(MivoColors.textPrimary)
                    Text(reason.detail)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(MivoColors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                if let retry, let action = reason.recoveryAction {
                    Button(action, action: retry)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(MivoColors.accent)
                        .buttonStyle(.plain)
                }
            }
            .padding(14)
            .background(MivoColors.surfaceRaised)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(MivoColors.border.opacity(0.45), lineWidth: 1)
            )
            .accessibilityElement(children: .combine)
        }
    }
}
