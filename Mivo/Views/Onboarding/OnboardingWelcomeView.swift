import SwiftUI

struct OnboardingWelcomeView: View {
    @State private var goToWhy = false
    @State private var appear = false

    var body: some View {
        NavigationStack {
            ZStack {
                OnboardingBackdrop()

                VStack(spacing: 0) {
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 26) {
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
                            .padding(.top, 22)
                            .onboardingEntrance(appear, delay: 0.05)

                            focusHero
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
            }
        }
    }

    private var focusHero: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 38, style: .continuous)
                .fill(LinearGradient(colors: [Color(hex: "#26382E"), Color(hex: "#3F5947")], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(height: 226)

            Circle()
                .stroke(Color(hex: "#D8E2D3").opacity(0.18), lineWidth: 18)
                .frame(width: 166, height: 166)

            Circle()
                .trim(from: 0.12, to: 0.86)
                .stroke(Color(hex: "#E6B17E"), style: StrokeStyle(lineWidth: 12, lineCap: .round))
                .frame(width: 144, height: 144)
                .rotationEffect(.degrees(-12))

            VStack(spacing: 10) {
                Image(systemName: "pause.fill")
                    .font(.system(size: 26, weight: .bold))
                    .frame(width: 64, height: 64)
                    .background(Color.white.opacity(0.16))
                    .clipShape(Circle())
                Text("A pause before autopilot")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                Text("Reflect first. Scroll only when you mean it.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Color.white.opacity(0.68))
            }

            VStack {
                HStack {
                    Text("Private by design")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Color.white.opacity(0.76))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.white.opacity(0.12))
                        .clipShape(Capsule())
                    Spacer()
                }
                Spacer()
            }
            .padding(18)
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
