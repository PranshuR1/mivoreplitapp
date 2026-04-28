import SwiftUI

struct OnboardingBackdrop: View {
    var body: some View {
        ZStack {
            MivoColors.background.ignoresSafeArea()

            LinearGradient(
                colors: [
                    Color(hex: "#F6EEE6").opacity(0.92),
                    MivoColors.background,
                    Color(hex: "#D8E2D3").opacity(0.46)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        }
    }
}

struct OnboardingStepHeader: View {
    let step: Int
    let total: Int
    let eyebrow: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Text(eyebrow.uppercased())
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(MivoColors.accent)

                Spacer()

                HStack(spacing: 5) {
                    ForEach(1...total, id: \.self) { index in
                        Capsule()
                            .fill(index <= step ? MivoColors.accent : MivoColors.white.opacity(0.72))
                            .frame(width: index == step ? 22 : 7, height: 7)
                            .animation(.spring(response: 0.42, dampingFraction: 0.84), value: step)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(MivoColors.white.opacity(0.46))
                .clipShape(Capsule())
            }

            Text(title)
                .font(.system(size: 31, weight: .bold, design: .rounded))
                .foregroundColor(MivoColors.textPrimary)
                .lineSpacing(2)

            Text(subtitle)
                .font(.system(size: 15))
                .foregroundColor(MivoColors.textSecondary)
                .lineSpacing(6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct OnboardingPrimaryButton<Icon: View>: View {
    let title: String
    var enabled = true
    let icon: Icon
    let action: () -> Void

    init(_ title: String, enabled: Bool = true, @ViewBuilder icon: () -> Icon, action: @escaping () -> Void) {
        self.title = title
        self.enabled = enabled
        self.icon = icon()
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                icon
                    .font(.system(size: 15, weight: .semibold))
            }
            .foregroundColor(MivoColors.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 17)
            .background(enabled ? MivoColors.textPrimary : MivoColors.textMuted.opacity(0.36))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: enabled ? MivoColors.textPrimary.opacity(0.18) : .clear, radius: 16, y: 8)
        }
        .disabled(!enabled)
        .buttonStyle(.plain)
    }
}

struct OnboardingOptionRow<Leading: View>: View {
    let title: String
    let subtitle: String
    let isSelected: Bool
    let leading: Leading

    init(title: String, subtitle: String, isSelected: Bool, @ViewBuilder leading: () -> Leading) {
        self.title = title
        self.subtitle = subtitle
        self.isSelected = isSelected
        self.leading = leading()
    }

    var body: some View {
        HStack(spacing: 14) {
            leading
                .frame(width: 42, height: 42)
                .background(isSelected ? MivoColors.accent : Color(hex: "#DFE7DA"))
                .foregroundColor(isSelected ? MivoColors.white : Color(hex: "#4E7152"))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(MivoColors.textPrimary)
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundColor(MivoColors.textSecondary)
                    .lineLimit(2)
                    .lineSpacing(3)
            }

            Spacer()

            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 21, weight: .semibold))
                .foregroundColor(isSelected ? MivoColors.accent : MivoColors.textMuted.opacity(0.58))
        }
        .padding(15)
        .background(isSelected ? MivoColors.white.opacity(0.92) : MivoColors.white.opacity(0.58))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(isSelected ? MivoColors.accent.opacity(0.75) : MivoColors.white.opacity(0.58), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(isSelected ? 0.07 : 0.03), radius: isSelected ? 14 : 8, y: isSelected ? 8 : 4)
        .scaleEffect(isSelected ? 1.015 : 1)
        .animation(.spring(response: 0.36, dampingFraction: 0.82), value: isSelected)
    }
}

struct OnboardingBottomBar<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(MivoColors.white.opacity(0.4))
                .frame(height: 1)
            content
                .padding(.horizontal, 24)
                .padding(.top, 14)
                .padding(.bottom, 34)
        }
        .background(.ultraThinMaterial)
    }
}

extension View {
    func onboardingEntrance(_ active: Bool, delay: Double = 0) -> some View {
        opacity(active ? 1 : 0)
            .offset(y: active ? 0 : 16)
            .animation(.spring(response: 0.58, dampingFraction: 0.86).delay(delay), value: active)
    }
}
