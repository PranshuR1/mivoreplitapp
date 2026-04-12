import SwiftUI

struct OnboardingWelcomeView: View {
    @EnvironmentObject var appVM: AppViewModel
    @State private var goToWhy = false
    @State private var appear = false
    @State private var revealedIndex: Int = -1

    var body: some View {
        NavigationStack {
            ZStack {
                MivoColors.background.ignoresSafeArea()
                VStack(spacing: 18) {
                    Spacer(minLength: 24)

                    // Centered logo and title
                    VStack(spacing: 8) {
                        MivoLogo(size: 68)

                        Text("Mivo")
                            .font(.system(size: 40, weight: .heavy, design: .rounded))
                            .foregroundColor(MivoColors.textPrimary)
                            .tracking(-1.2)
                    }
                    .frame(maxWidth: .infinity)

                    // Short intro (smaller so it fits on smaller screens)
                    Text("Not wellness. Not discipline. Just knowing what you are actually doing with your time.")
                        .font(.system(size: 15, design: .serif))
                        .foregroundColor(MivoColors.textSecondary)
                        .lineSpacing(6)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 36)

                    Divider()
                        .background(MivoColors.border)
                        .padding(.vertical, 6)

                    // Pillar cards reveal sequentially with pauses
                    VStack(spacing: 12) {
                        ForEach(pillarItems().indices, id: \.self) { idx in
                            let item = pillarItems()[idx]
                            PillarCard(item: item)
                                .opacity(revealedIndex >= idx ? 1 : 0)
                                .scaleEffect(revealedIndex >= idx ? 1 : 0.98)
                                .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(revealedIndex == idx ? 0 : 0), value: revealedIndex)
                        }
                    }
                    .padding(.horizontal, 28)

                    Spacer()

                    // Show Start button only after all pillars are revealed
                    if revealedIndex >= 2 {
                        Button {
                            goToWhy = true
                        } label: {
                            HStack(spacing: 8) {
                                Text("Start")
                                    .font(.system(size: 16, weight: .semibold))
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 16, weight: .medium))
                            }
                            .foregroundColor(MivoColors.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(MivoColors.accent)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                        .padding(.horizontal, 28)
                        .padding(.bottom, 36)
                    }
                }
                .onAppear {
                    appear = true
                    // Sequence: reveal first shortly, then next after 1s, then next after another 1s
                    let firstDelay = 0.25
                    let interval: Double = 1.0
                    DispatchQueue.main.asyncAfter(deadline: .now() + firstDelay) { revealedIndex = 0 }
                    DispatchQueue.main.asyncAfter(deadline: .now() + firstDelay + interval) { revealedIndex = 1 }
                    DispatchQueue.main.asyncAfter(deadline: .now() + firstDelay + interval * 2) { revealedIndex = 2 }
                 }
             }
            .navigationDestination(isPresented: $goToWhy) {
                OnboardingWhyView()
            }
        }
    }

    private func pillarItems() -> [PillarCard.Item] {
        [
            .init(systemImage: "eye", title: "Phase 1: Observe", description: "Watch your patterns without judgment."),
            .init(systemImage: "pause.circle", title: "Phase 2: Pause", description: "A gentle moment before you open an app."),
            .init(systemImage: "chart.bar", title: "Understand", description: "Plain language insights from your own data.")
        ]
    }
}

private struct PillarCard: View {
    struct Item { let systemImage: String; let title: String; let description: String }
    let item: Item

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(LinearGradient(colors: [MivoColors.accentMuted, MivoColors.card], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 44, height: 44)
                Image(systemName: item.systemImage)
                    .font(.system(size: 16))
                    .foregroundColor(MivoColors.accent)
            }

            VStack(alignment: .leading, spacing: 6) {
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
        .padding(12)
        .background(MivoColors.card)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(MivoColors.border, lineWidth: 1))
        .shadow(color: Color.black.opacity(0.03), radius: 6, y: 3)
    }
}
