import SwiftUI

struct OnboardingWelcomeView: View {
    @State private var goToWhy = false
    @State private var appear = false
    @State private var pulse = false

    var body: some View {
        NavigationStack {
            ZStack {
                OnboardingBackdrop()

                VStack(spacing: 0) {
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 26) {
                            focusHero
                                .onboardingEntrance(appear, delay: 0.05)

                            VStack(spacing: 12) {
                                Text("Build a quieter phone")
                                    .font(.system(size: 34, weight: .bold, design: .rounded))
                                    .foregroundColor(MivoColors.textPrimary)
                                    .multilineTextAlignment(.center)

                                Text("Mivo learns where your attention leaks, then helps you pause before the loop starts.")
                                    .font(.system(size: 16))
                                    .foregroundColor(MivoColors.textSecondary)
                                    .multilineTextAlignment(.center)
                                    .lineSpacing(6)
                                    .padding(.horizontal, 10)
                            }
                            .onboardingEntrance(appear, delay: 0.16)

                            VStack(spacing: 12) {
                                ForEach(Array(pillarItems().enumerated()), id: \.offset) { index, item in
                                    PillarCard(item: item)
                                        .onboardingEntrance(appear, delay: 0.26 + Double(index) * 0.08)
                                }
                            }
                            .padding(.top, 4)
                        }
                        .padding(.horizontal, 24)
                        .padding(.top, 48)
                        .padding(.bottom, 120)
                    }

                    OnboardingBottomBar {
                        OnboardingPrimaryButton("Begin setup") {
                            Image(systemName: "arrow.right")
                        } action: {
                            HapticsService.impact(style: .light)
                            goToWhy = true
                        }
                        .onboardingEntrance(appear, delay: 0.42)
                    }
                }
            }
            .navigationDestination(isPresented: $goToWhy) {
                OnboardingWhyView()
            }
            .onAppear {
                appear = true
                withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            }
        }
    }

    private var focusHero: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 38, style: .continuous)
                .fill(Color(hex: "#28392F"))
                .frame(height: 244)
                .overlay(alignment: .topTrailing) {
                    VStack(alignment: .trailing, spacing: 8) {
                        Text("Today")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(Color.white.opacity(0.7))
                        Text("2h 14m")
                            .font(.system(size: 26, weight: .bold).monospacedDigit())
                            .foregroundColor(.white)
                    }
                    .padding(22)
                }

            Circle()
                .stroke(Color(hex: "#D8E2D3").opacity(0.18), lineWidth: 18)
                .frame(width: pulse ? 190 : 168, height: pulse ? 190 : 168)

            Circle()
                .trim(from: 0.08, to: 0.78)
                .stroke(Color(hex: "#E6B17E"), style: StrokeStyle(lineWidth: 13, lineCap: .round))
                .frame(width: 154, height: 154)
                .rotationEffect(.degrees(pulse ? 18 : -8))

            VStack(spacing: 10) {
                MivoLogo(size: 58)
                Text("Mivo")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                Text("Attention protected")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Color.white.opacity(0.68))
            }
        }
    }

    private func pillarItems() -> [PillarCard.Item] {
        [
            .init(systemImage: "eye", title: "See the pattern", description: "Spot the moments your phone becomes automatic."),
            .init(systemImage: "pause.circle", title: "Add friction", description: "A short pause helps you choose before you scroll."),
            .init(systemImage: "chart.line.uptrend.xyaxis", title: "Improve gently", description: "Clear reports make progress feel visible.")
        ]
    }
}

private struct PillarCard: View {
    struct Item {
        let systemImage: String
        let title: String
        let description: String
    }

    let item: Item

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: item.systemImage)
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 44, height: 44)
                .background(Color(hex: "#DFE7DA"))
                .foregroundColor(Color(hex: "#4E7152"))
                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))

            VStack(alignment: .leading, spacing: 5) {
                Text(item.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(MivoColors.textPrimary)
                Text(item.description)
                    .font(.system(size: 13))
                    .foregroundColor(MivoColors.textSecondary)
                    .lineSpacing(3)
            }

            Spacer()
        }
        .padding(15)
        .background(MivoColors.white.opacity(0.62))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(MivoColors.white.opacity(0.55), lineWidth: 1))
        .shadow(color: Color.black.opacity(0.035), radius: 12, y: 6)
    }
}
