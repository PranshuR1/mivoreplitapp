import SwiftUI

/// A compact blackjack-style decision game against Mivo Bot. The player draws
/// or holds toward 21, then the bot reveals its hand. A round is seeded with a
/// one-in-six player-win ticket; the generated bot hand still honors the visible
/// totals and closest-to-21 rules, so the result shown on screen matches the
/// actual cards rather than being an unrelated reward roll.
struct FocusCardsGameView: View {
    let onFinished: (IntentGameResult) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var playerCards: [Int] = []
    @State private var botCards: [Int] = []
    @State private var botRevealedCount = 1
    @State private var roundWillWin = false
    @State private var losingBotHitsTwentyOne = false
    @State private var resolving = false
    @State private var finished = false
    @State private var outcome: FocusCardsOutcome?

    private var playerTotal: Int { playerCards.reduce(0, +) }
    private var botTotal: Int { botCards.reduce(0, +) }
    private var botVisibleTotal: Int { botCards.prefix(botRevealedCount).reduce(0, +) }
    private var guidanceTarget: Int { FocusCardsRewards.guidanceTarget(forTotal: playerTotal) }
    private var canDraw: Bool {
        !resolving && !finished && playerCards.count < 5 && playerTotal < FocusCardsRewards.target
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            oddsBanner
                .padding(.top, 14)
            hands
                .padding(.top, 18)
            status
                .padding(.top, 18)
            Spacer(minLength: 18)
            if finished, let outcome {
                resultPanel(outcome)
            } else {
                actionButtons
            }
        }
        .padding(.horizontal, MivoMetrics.screenPadding)
        .padding(.bottom, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(MivoColors.background.ignoresSafeArea())
        .onAppear(perform: startRound)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(MivoColors.inkMuted)
                        .frame(width: 44, height: 44)
                }
                .disabled(resolving)
                .opacity(resolving ? 0.3 : 1)
                Spacer()
                MivoBadge(
                    text: "1 IN 6 WIN",
                    background: MivoColors.info.opacity(0.13),
                    foreground: MivoColors.info,
                    size: 8.5
                )
            }
            MivoEyebrow(text: "FOCUS CARDS · VS MIVO BOT")
            Text("Get closer to 21")
                .font(.system(size: 24, weight: .bold))
                .tracking(Font.mivoTracking(-0.025, at: 24))
                .foregroundColor(MivoColors.ink)
            Text("Draw another card or hold your total. The bot reveals after you commit.")
                .font(.system(size: 13.5, weight: .medium))
                .foregroundColor(MivoColors.inkBody)
                .lineSpacing(4)
        }
        .padding(.top, 4)
    }

    private var oddsBanner: some View {
        HStack(spacing: 10) {
            outcomeLegend(symbol: "+5–7m", label: "Win", color: MivoColors.kept)
            Rectangle().fill(MivoColors.hairline).frame(width: 1, height: 30)
            outcomeLegend(symbol: "−3m", label: "Bot closer", color: MivoColors.inkBody)
            Rectangle().fill(MivoColors.hairline).frame(width: 1, height: 30)
            outcomeLegend(symbol: "−5m", label: "Bust / bot 21", color: MivoColors.ink)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .background(MivoColors.surfaceV2)
        .clipShape(RoundedRectangle(cornerRadius: MivoMetrics.radius))
        .overlay(
            RoundedRectangle(cornerRadius: MivoMetrics.radius)
                .strokeBorder(MivoColors.hairline, lineWidth: 1)
        )
    }

    private func outcomeLegend(symbol: String, label: String, color: Color) -> some View {
        VStack(spacing: 3) {
            Text(symbol)
                .font(.system(size: 12, weight: .bold))
                .monospacedDigit()
                .foregroundColor(color)
            Text(label)
                .font(.system(size: 8.5, weight: .semibold))
                .foregroundColor(MivoColors.inkMuted)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity)
    }

    private var hands: some View {
        VStack(spacing: 14) {
            handBlock(
                title: "YOU",
                cards: playerCards,
                revealedCount: playerCards.count,
                displayedTotal: playerTotal,
                tint: MivoColors.info
            )
            handBlock(
                title: "MIVO BOT",
                cards: botCards,
                revealedCount: botRevealedCount,
                displayedTotal: botVisibleTotal,
                tint: MivoColors.accent
            )
        }
    }

    private func handBlock(
        title: String,
        cards: [Int],
        revealedCount: Int,
        displayedTotal: Int,
        tint: Color
    ) -> some View {
        VStack(spacing: 10) {
            HStack {
                MivoEyebrow(text: title, color: tint)
                Spacer()
                Text(title == "MIVO BOT" && revealedCount < cards.count ? "\(displayedTotal) + ?" : "\(displayedTotal)")
                    .font(.system(size: 16, weight: .bold))
                    .monospacedDigit()
                    .foregroundColor(MivoColors.ink)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(tint.opacity(0.11))
                    .clipShape(Capsule())
            }

            HStack(spacing: -8) {
                ForEach(Array(cards.enumerated()), id: \.offset) { index, value in
                    cardView(value: value, revealed: index < revealedCount, tint: tint)
                        .zIndex(Double(index))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(MivoColors.surfaceRaised.opacity(0.62))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(MivoColors.hairline, lineWidth: 1))
    }

    private func cardView(value: Int, revealed: Bool, tint: Color) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(revealed ? MivoColors.background : tint)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(revealed ? MivoColors.ink.opacity(0.14) : .white.opacity(0.35), lineWidth: 1)
                )
                .shadow(color: MivoColors.ink.opacity(0.10), radius: 4, y: 2)
            if revealed {
                Text("\(value)")
                    .font(.system(size: 23, weight: .bold))
                    .monospacedDigit()
                    .foregroundColor(MivoColors.ink)
            } else {
                Image(systemName: "circle.hexagongrid.fill")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundColor(.white.opacity(0.84))
            }
        }
        .frame(width: 54, height: 72)
        .rotation3DEffect(.degrees(revealed ? 0 : 180), axis: (x: 0, y: 1, z: 0))
        .animation(MivoMotion.standard(0.32), value: revealed)
    }

    @ViewBuilder
    private var status: some View {
        if resolving {
            HStack(spacing: 9) {
                ProgressView().tint(MivoColors.accent)
                Text("Mivo Bot is revealing its hand…")
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundColor(MivoColors.inkBody)
            }
            .frame(maxWidth: .infinity)
        } else if !finished {
            VStack(spacing: 4) {
                Text("Hold \(playerTotal) or draw toward \(guidanceTarget)")
                    .font(.system(size: 17, weight: .bold))
                    .monospacedDigit()
                    .foregroundColor(MivoColors.ink)
                Text("Closest to 21 wins. Going over is a bust.")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundColor(MivoColors.inkMuted)
            }
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 12) {
            Button { hold() } label: {
                Text("Hold \(playerTotal)")
                    .font(.system(size: 15.5, weight: .bold))
                    .monospacedDigit()
                    .foregroundColor(MivoColors.ink)
                    .frame(maxWidth: .infinity)
                    .frame(height: MivoMetrics.buttonHeight)
                    .overlay(
                        RoundedRectangle(cornerRadius: MivoMetrics.radius)
                            .strokeBorder(MivoColors.ink.opacity(0.18), lineWidth: 1)
                    )
            }
            .buttonStyle(MivoPressStyle())
            .disabled(resolving)

            Button { draw() } label: {
                HStack(spacing: 7) {
                    Image(systemName: "plus")
                    Text("Draw")
                }
                .font(.system(size: 15.5, weight: .bold))
                .foregroundColor(canDraw ? MivoColors.background : MivoColors.inkMuted)
                .frame(maxWidth: .infinity)
                .frame(height: MivoMetrics.buttonHeight)
                .background(canDraw ? MivoColors.ink : MivoColors.ink.opacity(0.09))
                .clipShape(RoundedRectangle(cornerRadius: MivoMetrics.radius))
            }
            .buttonStyle(MivoPressStyle())
            .disabled(!canDraw)
        }
    }

    private func resultPanel(_ outcome: FocusCardsOutcome) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill((outcome.playerWon ? MivoColors.kept : MivoColors.ink).opacity(0.11))
                        .frame(width: 44, height: 44)
                    Image(systemName: outcome.playerWon ? "trophy.fill" : "calendar.badge.minus")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(outcome.playerWon ? MivoColors.kept : MivoColors.ink)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(outcome.label)
                        .font(.system(size: 16.5, weight: .bold))
                        .foregroundColor(MivoColors.ink)
                    Text("You \(playerTotal) · Bot \(botTotal)")
                        .font(.system(size: 12.5, weight: .semibold))
                        .monospacedDigit()
                        .foregroundColor(MivoColors.inkBody)
                }
                Spacer()
                Text(outcome.minutes > 0 ? "+\(outcome.minutes)m" : "\(outcome.minutes)m")
                    .font(.system(size: 22, weight: .bold))
                    .monospacedDigit()
                    .foregroundColor(outcome.playerWon ? MivoColors.kept : MivoColors.ink)
            }

            MivoPrimaryButton(label: outcome.playerWon ? "Use time now" : "Apply to next session") {
                onFinished(
                    IntentGameResult.make(
                        gameType: .focusCards,
                        awardedMinutes: outcome.minutes,
                        outcomeLabel: outcome.label
                    )
                )
            }
        }
        .padding(14)
        .background(MivoColors.surfaceRaised.opacity(0.68))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(MivoColors.hairline, lineWidth: 1))
        .transition(.opacity.combined(with: .scale(scale: 0.97)))
    }

    private func startRound() {
        roundWillWin = Int.random(in: 0..<6) == 0
        losingBotHitsTwentyOne = Bool.random()
        playerCards = [Int.random(in: 2...10), Int.random(in: 2...10)]
        botCards = [Int.random(in: 2...10), 0]
        botRevealedCount = 1
        resolving = false
        finished = false
        outcome = nil
    }

    private func hold() {
        HapticsService.selection()
        resolveRound()
    }

    private func draw() {
        guard canDraw else { return }
        let room = FocusCardsRewards.target - playerTotal
        let card: Int
        if roundWillWin {
            // Winning-ticket rounds remain winnable; the visible card total and
            // bot comparison still determine the displayed blackjack outcome.
            card = Int.random(in: 1...max(1, min(10, room)))
        } else {
            card = Int.random(in: 1...10)
        }
        withAnimation(MivoMotion.standard(0.24)) { playerCards.append(card) }
        HapticsService.impact(style: .medium)
        if playerTotal >= FocusCardsRewards.target || playerCards.count >= 5 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.34, execute: resolveRound)
        }
    }

    private func resolveRound() {
        guard !resolving, !finished, let visibleCard = botCards.first else { return }
        resolving = true

        let desiredBotTotal: Int
        if roundWillWin {
            // A bot bust is a valid closest-to-21 win for every safe player
            // total, including a low opening hand.
            desiredBotTotal = 22 + Int.random(in: 0...3)
        } else if playerTotal > FocusCardsRewards.target {
            desiredBotTotal = max(17, visibleCard + 1)
        } else if losingBotHitsTwentyOne || playerTotal >= 20 {
            desiredBotTotal = FocusCardsRewards.target
        } else {
            desiredBotTotal = min(FocusCardsRewards.target, max(playerTotal + 1, visibleCard + 1))
        }

        botCards = makeBotCards(total: desiredBotTotal, visibleCard: visibleCard)
        botRevealedCount = 1
        let hiddenCount = max(0, botCards.count - 1)

        for step in 1...max(1, hiddenCount) {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(step) * 0.30) {
                guard step <= hiddenCount else { return }
                withAnimation(MivoMotion.standard(0.32)) { botRevealedCount = step + 1 }
                HapticsService.impact(style: .light)
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + Double(max(1, hiddenCount)) * 0.30 + 0.32) {
            let resolved = FocusCardsRewards.outcome(playerTotal: playerTotal, botTotal: botTotal)
            outcome = resolved
            resolving = false
            withAnimation(MivoMotion.standard(0.28)) { finished = true }
            if resolved.playerWon {
                HapticsService.success()
            } else {
                HapticsService.impact(style: .medium)
            }
        }
    }

    private func makeBotCards(total: Int, visibleCard: Int) -> [Int] {
        var cards = [visibleCard]
        var remaining = max(0, total - visibleCard)
        while remaining > 0 {
            let next = min(10, remaining)
            cards.append(next)
            remaining -= next
        }
        return cards
    }
}
