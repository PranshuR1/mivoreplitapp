import SwiftUI

/// Reusable header component for onboarding steps
struct OnboardingStepHeader: View {
    let step: Int
    let total: Int
    let eyebrow: String
    let title: String
    let subtitle: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Progress indicator
            HStack(spacing: 6) {
                ForEach(1...total, id: \.self) { index in
                    Capsule()
                        .fill(index <= step ? MivoColors.blue : MivoColors.muted.opacity(0.3))
                        .frame(height: 4)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.bottom, 8)
            
            // Eyebrow text
            Text(eyebrow.uppercased())
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(MivoColors.secondary)
                .tracking(1.2)
            
            // Title
            Text(title)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundColor(MivoColors.textPrimary)
                .lineSpacing(2)
            
            // Subtitle
            Text(subtitle)
                .font(.system(size: 15))
                .foregroundColor(MivoColors.textSecondary)
                .lineSpacing(5)
        }
    }
}

/// Reusable backdrop for onboarding screens
struct OnboardingBackdrop: View {
    var body: some View {
        ZStack {
            MivoColors.background.ignoresSafeArea()
            
            LinearGradient(
                colors: [
                    MivoColors.heroText,
                    MivoColors.background,
                    MivoColors.surface.opacity(0.5)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        }
    }
}

/// Bottom bar container for onboarding CTAs
struct OnboardingBottomBar<Content: View>: View {
    let content: Content
    
    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Subtle divider
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            MivoColors.muted.opacity(0.1),
                            MivoColors.muted.opacity(0.3),
                            MivoColors.muted.opacity(0.1)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 1)
            
            content
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
                .background(
                    MivoColors.background.opacity(0.95)
                        .background(.ultraThinMaterial)
                )
        }
    }
}

/// Primary button for onboarding
struct OnboardingPrimaryButton<TrailingIcon: View>: View {
    let title: String
    let trailingIcon: TrailingIcon
    let action: () -> Void
    
    init(_ title: String, @ViewBuilder trailingIcon: () -> TrailingIcon, action: @escaping () -> Void) {
        self.title = title
        self.trailingIcon = trailingIcon()
        self.action = action
    }
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                trailingIcon
                    .font(.system(size: 15, weight: .semibold))
            }
            .foregroundColor(MivoColors.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 17)
            .background(MivoColors.blue)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: MivoColors.blue.opacity(0.24), radius: 16, y: 8)
        }
        .buttonStyle(.plain)
    }
}

/// Entrance animation modifier for onboarding elements
struct OnboardingEntranceModifier: ViewModifier {
    let appear: Bool
    let delay: Double
    
    func body(content: Content) -> some View {
        content
            .opacity(appear ? 1 : 0)
            .offset(y: appear ? 0 : 20)
            .animation(.spring(response: 0.6, dampingFraction: 0.8).delay(delay), value: appear)
    }
}

extension View {
    func onboardingEntrance(_ appear: Bool, delay: Double = 0) -> some View {
        modifier(OnboardingEntranceModifier(appear: appear, delay: delay))
    }
}
