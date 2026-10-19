import SwiftUI

/// Entry point presented from `InterventionFlowView`'s duration step. Picks
/// a game, then hands off to `IntentGameContainerView`. The only way back
/// out to the caller is `onSessionReady` (an approved duration, handed to
/// the existing `beginPause` pipeline unchanged) or a plain dismiss — this
/// view and everything under it never touches `ActiveSessionView` or
/// `FamilyControlsManager` directly.
struct IntentGamePickerView: View {
    let intention: Intention
    let onSessionReady: (Int) -> Void
    let onUseMivoClear: () -> Void

    @EnvironmentObject private var appVM: AppViewModel
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var loanService = TimeLoanService.shared
    @ObservedObject private var gameService = IntentGameService.shared

    @State private var lastPlayed: IntentGameType?

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                header
                DailyTimeBalanceView()
                    .padding(.top, 18)
                gamesGrid
                    .padding(.top, 22)
                surpriseMeButton
                    .padding(.top, 12)
                Spacer(minLength: 20)
            }
            .padding(.horizontal, MivoMetrics.screenPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(MivoColors.background.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .foregroundColor(MivoColors.inkMuted)
                    }
                }
            }
        }
        .onAppear {
            loanService.prepare(for: appVM)
            gameService.prepare(for: appVM)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            MivoEyebrow(text: "FOCUS BREAK")
            HStack(spacing: 8) {
                Text("Choose a quick game")
                    .font(.system(size: 25, weight: .bold))
                    .tracking(Font.mivoTracking(-0.025, at: 25))
                    .foregroundColor(MivoColors.ink)
                MivoBadge.trial()
            }
            Text("A short game sets your unlock time for \(intention.flowLabel.lowercased()). Chance games can add time now or trim your next planned session.")
                .font(.system(size: 13.5, weight: .medium))
                .foregroundColor(MivoColors.inkBody)
            Text("You opted into this trial from Settings — Mivo logs which games run and what they award so this can be judged on real use, not a guess.")
                .font(.system(size: 11.5, weight: .medium))
                .foregroundColor(MivoColors.inkMuted)
        }
        .padding(.top, 12)
    }

    private var gamesGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            ForEach(IntentGameType.allCases) { game in
                NavigationLink {
                    containerView(for: game)
                } label: {
                    gameCard(game)
                }
                .simultaneousGesture(TapGesture().onEnded { lastPlayed = game })
            }
        }
    }

    private func gameCard(_ game: IntentGameType) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: game.icon)
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(MivoColors.ink)
            Text(game.title)
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(MivoColors.ink)
            Text(game.tagline)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundColor(MivoColors.inkMuted)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .frame(height: 128, alignment: .topLeading)
        .background(MivoColors.ink.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: MivoMetrics.radius))
        .overlay(
            RoundedRectangle(cornerRadius: MivoMetrics.radius)
                .strokeBorder(MivoColors.hairline, lineWidth: 1)
        )
    }

    private var surpriseMeButton: some View {
        NavigationLink {
            containerView(for: gameService.nextGame(excluding: lastPlayed))
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                Text("Surprise me")
            }
            .font(.system(size: 14.5, weight: .semibold))
            .foregroundColor(MivoColors.background)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(MivoColors.ink)
            .clipShape(RoundedRectangle(cornerRadius: MivoMetrics.radius))
        }
        .buttonStyle(MivoPressStyle())
    }

    private func containerView(for game: IntentGameType) -> some View {
        IntentGameContainerView(
            gameType: game,
            onSessionReady: { minutes in
                onSessionReady(minutes)
            },
            onUseMivoClear: onUseMivoClear,
            onExit: { dismiss() }
        )
    }
}

/// Today remaining / tomorrow's projected allowance, and how much of
/// tomorrow is already spoken for by a pending loan. Read-only — reused
/// both here (top of the picker) and could be surfaced from Settings later.
struct DailyTimeBalanceView: View {
    @EnvironmentObject private var appVM: AppViewModel
    @ObservedObject private var loanService = TimeLoanService.shared

    private var todayRemaining: Int {
        DailyAllowanceService.todayRemainingMinutes(appVM: appVM, loans: loanService.loans)
    }
    private var tomorrowProjected: Int {
        DailyAllowanceService.tomorrowProjectedMinutes(appVM: appVM, loans: loanService.loans)
    }
    private var pendingAgainstTomorrow: Int {
        let tomorrow = MivoDay.key(offsetFromToday: 1)
        return loanService.loans
            .filter { $0.status == .pending && $0.repayDate == tomorrow }
            .reduce(0) { $0 + $1.borrowedMinutes }
    }

    var body: some View {
        HStack(spacing: 0) {
            balanceStat(label: "Today remaining", value: "\(todayRemaining)m")
            Divider().frame(height: 30).overlay(MivoColors.hairline)
            balanceStat(label: "Tomorrow projected", value: "\(tomorrowProjected)m")
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 4)
        .background(MivoColors.ink.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: MivoMetrics.radius))
        .overlay(
            RoundedRectangle(cornerRadius: MivoMetrics.radius)
                .strokeBorder(MivoColors.hairline, lineWidth: 1)
        )
        .overlay(alignment: .topTrailing) {
            if pendingAgainstTomorrow > 0 {
                Text("\(pendingAgainstTomorrow)m owed")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(MivoColors.deep)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(MivoColors.deep.opacity(0.12))
                    .clipShape(Capsule())
                    .offset(x: -8, y: -8)
            }
        }
    }

    private func balanceStat(label: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 20, weight: .bold))
                .monospacedDigit()
                .foregroundColor(MivoColors.ink)
            Text(label)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundColor(MivoColors.inkMuted)
        }
        .frame(maxWidth: .infinity)
    }
}

/// Hosts the chosen game, then branches on its result: enough today, a
/// borrowable shortfall, a hard-protection wall, or a reflection prompt.
/// Whichever branch resolves to, the container is dismissed at the end —
/// nothing here ever re-offers a second attempt at the same unlock flow.
struct IntentGameContainerView: View {
    let gameType: IntentGameType
    let onSessionReady: (Int) -> Void
    let onUseMivoClear: () -> Void
    let onExit: () -> Void

    @EnvironmentObject private var appVM: AppViewModel
    @ObservedObject private var loanService = TimeLoanService.shared
    @ObservedObject private var gameService = IntentGameService.shared
    @ObservedObject private var adjustmentService = DropPathTimeAdjustmentService.shared

    @State private var result: IntentGameResult?
    @State private var penaltyApplication: DropPathPenaltyApplication?
    private let sessionID = UUID().uuidString.lowercased()

    private var mivoClearEligible: Bool { ProductExpansionStore.shared.isEnabled(.mivoClear) }

    var body: some View {
        Group {
            if let result {
                resolvedView(for: result)
            } else {
                gameView
            }
        }
        .navigationBarBackButtonHidden(result != nil)
    }

    @ViewBuilder
    private var gameView: some View {
        switch gameType {
        case .focusCards:
            FocusCardsGameView(onFinished: handleResult)
        case .dropPath:
            DropPathGameView(onFinished: handleResult)
        case .steadyTap:
            EmptyView()
        case .paperFlight:
            PaperFlightGameView(onFinished: handleResult)
        }
    }

    private func handleResult(_ result: IntentGameResult) {
        gameService.record(result)
        if result.awardedMinutes < 0 {
            penaltyApplication = adjustmentService.removeFromNextScheduledSession(
                minutes: abs(result.awardedMinutes),
                sourceGame: result.gameType,
                appVM: appVM
            )
        }
        self.result = result
    }

    @ViewBuilder
    private func resolvedView(for result: IntentGameResult) -> some View {
        if result.awardedMinutes < 0, let penaltyApplication {
            DropPathPenaltyResultView(
                result: result,
                application: penaltyApplication,
                onDone: onExit
            )
        } else if result.needsReflection {
            ReflectionPromptView(onFinished: onExit)
        } else if result.gameType == .dropPath || result.gameType == .focusCards || result.gameType == .paperFlight {
            // Wins from signed chance games are deliberately immediate: they
            // do not turn into a loan or get deferred behind today's allowance.
            IntentGameResultView(result: result) {
                onSessionReady(result.awardedMinutes)
            }
        } else {
            let todayRemaining = DailyAllowanceService.todayRemainingMinutes(appVM: appVM, loans: loanService.loans)
            if result.awardedMinutes <= todayRemaining {
                IntentGameResultView(result: result) {
                    onSessionReady(result.awardedMinutes)
                }
            } else if appVM.isHardProtectionActive() {
                ProtectedTimeActiveView(
                    result: result,
                    onStayProtected: onExit,
                    onUseMivoClear: mivoClearEligible ? onUseMivoClear : nil
                )
            } else {
                let needed = result.awardedMinutes - todayRemaining
                let borrowMinutes = DailyAllowanceService.borrowable(needed: needed, appVM: appVM, loans: loanService.loans)
                let tomorrowProjected = DailyAllowanceService.tomorrowProjectedMinutes(appVM: appVM, loans: loanService.loans)
                TimeLoanConfirmationView(
                    awardedMinutes: result.awardedMinutes,
                    todayRemaining: todayRemaining,
                    borrowMinutes: borrowMinutes,
                    tomorrowProjectedBefore: tomorrowProjected,
                    onConfirm: {
                        loanService.borrow(
                            minutes: borrowMinutes,
                            sourceGame: result.gameType,
                            sourceSessionID: sessionID,
                            appVM: appVM
                        )
                        onSessionReady(todayRemaining + borrowMinutes)
                    },
                    onDecline: onExit,
                    onUseMivoClear: mivoClearEligible ? onUseMivoClear : nil
                )
            }
        }
    }
}

/// A negative chance-game outcome never starts an unlock session. The result is
/// applied immediately to the next remaining planned window, or held for the
/// first window tomorrow when today's schedule is already finished.
struct DropPathPenaltyResultView: View {
    let result: IntentGameResult
    let application: DropPathPenaltyApplication
    let onDone: () -> Void

    private var targetsToday: Bool { application.targetDate == MivoDay.todayKey }

    private var destinationText: String {
        if application.isPending {
            return "It will come off the first session you schedule tomorrow."
        }
        if let title = application.windowTitle {
            let cleanedTitle = title.replacingOccurrences(
                of: "today’s ",
                with: "",
                options: [.caseInsensitive, .anchored]
            )
            return "Removed from \(targetsToday ? "today’s" : "tomorrow’s") \(cleanedTitle.lowercased())."
        }
        return "Removed from your next planned session."
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            ZStack {
                Circle()
                    .fill(MivoColors.ink.opacity(0.08))
                    .frame(width: 104, height: 104)
                Image(systemName: "calendar.badge.minus")
                    .font(.system(size: 37, weight: .semibold))
                    .foregroundColor(MivoColors.ink)
            }

            Text("\(result.awardedMinutes) minutes")
                .font(.system(size: 32, weight: .bold))
                .monospacedDigit()
                .foregroundColor(MivoColors.ink)
                .padding(.top, 22)

            Text("Next session adjusted")
                .font(.system(size: 19, weight: .bold))
                .foregroundColor(MivoColors.ink)
                .padding(.top, 6)

            Text(destinationText)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(MivoColors.inkBody)
                .multilineTextAlignment(.center)
                .lineSpacing(5)
                .frame(maxWidth: 290)
                .padding(.top, 10)

            HStack(spacing: 9) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(MivoColors.kept)
                Text(application.isPending ? "Saved for tomorrow automatically" : "Your locked times stay the same")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundColor(MivoColors.inkBody)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(MivoColors.surfaceV2)
            .clipShape(RoundedRectangle(cornerRadius: MivoMetrics.radius))
            .padding(.top, 22)

            Spacer()
            MivoInkButton(label: "Done", action: onDone)
        }
        .padding(.horizontal, MivoMetrics.screenPadding)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(MivoColors.background.ignoresSafeArea())
    }
}

/// The plain "enough today, no loan" result — outcome label plus minutes.
struct IntentGameResultView: View {
    let result: IntentGameResult
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            ZStack {
                Circle().fill(MivoColors.kept.opacity(0.14)).frame(width: 96, height: 96)
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundColor(MivoColors.kept)
            }
            Text(result.outcomeLabel)
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(MivoColors.ink)
            Text("+\(result.awardedMinutes) min unlock time")
                .font(.system(size: 16, weight: .semibold))
                .monospacedDigit()
                .foregroundColor(MivoColors.deep)
            Spacer()
            MivoPrimaryButton(label: "Use \(result.awardedMinutes) min now", action: onContinue)
        }
        .padding(.horizontal, MivoMetrics.screenPadding)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(MivoColors.background.ignoresSafeArea())
    }
}

/// Shown when today's zero minutes come from a hard, deliberate protection
/// rather than the flexible allowance simply running low. The game already
/// ran and already showed a real outcome above this screen — this only
/// explains why no borrowing is offered, calmly, without shaming.
struct ProtectedTimeActiveView: View {
    let result: IntentGameResult
    let onStayProtected: () -> Void
    let onUseMivoClear: (() -> Void)?

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            ZStack {
                Circle().fill(MivoColors.accent.opacity(0.14)).frame(width: 96, height: 96)
                Image(systemName: "shield.fill")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundColor(MivoColors.accent)
            }
            Text("Protected time is active")
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(MivoColors.ink)
            Text("\(result.outcomeLabel) earned \(result.awardedMinutes) min, but this is a protected window you set deliberately — Mivo won't borrow against tomorrow to get around it.")
                .font(.system(size: 13.5, weight: .medium))
                .foregroundColor(MivoColors.inkBody)
                .multilineTextAlignment(.center)
                .lineSpacing(13.5 * 0.5)
                .frame(maxWidth: 280)
            Spacer()
            if let onUseMivoClear {
                MivoPrimaryButton(label: "Use Mivo Clear instead", action: onUseMivoClear)
                MivoTertiaryButton(label: "Stay protected", action: onStayProtected)
            } else {
                MivoPrimaryButton(label: "Stay protected", action: onStayProtected)
            }
        }
        .padding(.horizontal, MivoMetrics.screenPadding)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(MivoColors.background.ignoresSafeArea())
    }
}

/// Drop Path's "Reflect first" slot — a short read-and-confirm rather than a
/// numeric reward. Exits the flow without starting a session; not a retry.
struct ReflectionPromptView: View {
    let onFinished: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            ZStack {
                Circle().fill(MivoColors.info.opacity(0.14)).frame(width: 96, height: 96)
                Image(systemName: "quote.bubble.fill")
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundColor(MivoColors.info)
            }
            Text("Reflect first")
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(MivoColors.ink)
            Text("Before anything else — is this still what you want to spend time on right now?")
                .font(.system(size: 14.5, weight: .medium))
                .foregroundColor(MivoColors.inkBody)
                .multilineTextAlignment(.center)
                .lineSpacing(14.5 * 0.5)
                .frame(maxWidth: 280)
            Spacer()
            MivoPrimaryButton(label: "Done", action: onFinished)
        }
        .padding(.horizontal, MivoMetrics.screenPadding)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(MivoColors.background.ignoresSafeArea())
    }
}
