import Foundation

enum IntentGameType: String, Codable, CaseIterable, Identifiable {
    case focusCards, dropPath, steadyTap, paperFlight

    /// Steady Tap remains a decodable legacy value so old game history and
    /// loans continue loading, but it is no longer offered as a playable game.
    static let allCases: [IntentGameType] = [.focusCards, .dropPath, .paperFlight]

    var id: String { rawValue }

    var title: String {
        switch self {
        case .focusCards: return "Focus Cards"
        case .dropPath: return "Drop Path"
        case .steadyTap: return "Steady Tap"
        case .paperFlight: return "Paper Flight"
        }
    }

    var tagline: String {
        switch self {
        case .focusCards: return "Draw or hold. Get closer to 21 than the bot."
        case .dropPath: return "Four paths trim time. Two add it now."
        case .steadyTap: return "Keep a steady rhythm."
        case .paperFlight: return "Collect time boosts. Survive the flight."
        }
    }

    var icon: String {
        switch self {
        case .focusCards: return "rectangle.stack.fill"
        case .dropPath: return "circle.hexagongrid.fill"
        case .steadyTap: return "hand.tap.fill"
        case .paperFlight: return "paperplane.fill"
        }
    }
}

/// Transient — what a game hands back to `IntentGameContainerView` the
/// moment it finishes. Not itself persisted; `IntentGameHistoryEntry` below
/// is the on-disk record.
struct IntentGameResult: Identifiable, Equatable {
    let id: String
    let gameType: IntentGameType
    /// Signed for chance games: positive minutes can be used immediately,
    /// while negative minutes are removed from the next planned scroll session.
    let awardedMinutes: Int
    let completed: Bool
    let outcomeLabel: String
    /// Drop Path's "Reflect first" slot only — a non-numeric outcome that
    /// shows a short prompt instead of unlock minutes.
    let needsReflection: Bool

    static func make(
        gameType: IntentGameType,
        awardedMinutes: Int,
        outcomeLabel: String,
        needsReflection: Bool = false,
        completed: Bool = true
    ) -> IntentGameResult {
        IntentGameResult(
            id: UUID().uuidString.lowercased(),
            gameType: gameType,
            awardedMinutes: awardedMinutes,
            completed: completed,
            outcomeLabel: outcomeLabel,
            needsReflection: needsReflection
        )
    }
}

/// Persisted history, purely for `DailyTimeBalanceView`'s "played today"
/// stat — kept separate from `IntentGameResult` so that type stays exactly
/// the transient shape a game hands back.
struct IntentGameHistoryEntry: Codable, Identifiable, Equatable {
    let id: String
    let date: String
    let gameType: IntentGameType
    /// A signed time change. Entries written before signed chance-game outcomes
    /// were introduced are already positive and decode without migration.
    let awardedMinutes: Int
}

// MARK: - Reward tables
//
// Chance games are intentionally signed. Steady Tap bottoms out at a positive
// award. Values stay separate from animation state so the
// actual outcome rules remain directly testable.

enum FocusCardsRewards {
    static let target = 21

    /// The guidance target can never move backward below the cards the player
    /// already holds, including the brief bust/result state.
    static func guidanceTarget(forTotal total: Int) -> Int {
        max(target, total)
    }

    static func outcome(playerTotal: Int, botTotal: Int) -> FocusCardsOutcome {
        if playerTotal > target { return .playerBust }
        if botTotal > target { return playerTotal == target ? .playerTwentyOne : .botBust }
        if botTotal == target {
            return playerTotal == target ? .botWinsTie : .botTwentyOne
        }

        let playerDistance = target - playerTotal
        let botDistance = target - botTotal
        if playerDistance < botDistance {
            return playerTotal == target ? .playerTwentyOne : .playerCloser
        }
        if playerDistance == botDistance { return .botWinsTie }
        return .botCloser
    }
}

enum FocusCardsOutcome: Equatable {
    case playerTwentyOne
    case playerCloser
    case botBust
    case playerBust
    case botTwentyOne
    case botCloser
    case botWinsTie

    var playerWon: Bool {
        switch self {
        case .playerTwentyOne, .playerCloser, .botBust: return true
        case .playerBust, .botTwentyOne, .botCloser, .botWinsTie: return false
        }
    }

    var minutes: Int {
        switch self {
        case .playerTwentyOne: return 7
        case .playerCloser, .botBust: return 5
        case .playerBust, .botTwentyOne: return -5
        case .botCloser, .botWinsTie: return -3
        }
    }

    var label: String {
        switch self {
        case .playerTwentyOne: return "21 — you win"
        case .playerCloser: return "Closer than the bot"
        case .botBust: return "Bot went over 21"
        case .playerBust: return "Over 21"
        case .botTwentyOne: return "Bot reached 21"
        case .botCloser: return "Bot was closer"
        case .botWinsTie: return "Bot wins the tie"
        }
    }
}

enum DropPathSlot: CaseIterable {
    /// Slot order matters. A five-row Galton path lands with weights
    /// 1, 5, 10, 10, 5, 1, so keeping both gains off-center makes a removal
    /// outcome 22/32 (68.75%) likely even though four of the six visible slots
    /// are removals.
    case minusFiveEdge, plusThree, minusThreeLeft, minusFiveCenter, plusFive, minusThreeEdge

    var minutes: Int {
        switch self {
        case .minusFiveEdge, .minusFiveCenter: return -5
        case .minusThreeLeft, .minusThreeEdge: return -3
        case .plusThree: return 3
        case .plusFive: return 5
        }
    }

    var isGain: Bool { minutes > 0 }

    var shortLabel: String { minutes > 0 ? "+\(minutes)m" : "\(minutes)m" }

    var label: String {
        isGain ? "+\(minutes) minutes now" : "\(minutes) minutes next session"
    }
}

// MARK: - Drop Path scheduled-time adjustments

struct DropPathTimeAdjustment: Codable, Identifiable, Equatable {
    let id: String
    let minutesRemoved: Int
    let createdAt: String
    let targetDate: String
    var sourceGame: IntentGameType? = nil
    var appliedWindowID: String?
    var appliedWindowTitle: String?
    var appliedAt: String?

    var isPending: Bool { appliedAt == nil }
}

/// Immediate, display-ready receipt returned after a negative Drop Path result.
/// Pending means tomorrow's schedule has not been chosen yet; the persisted
/// adjustment is applied automatically as soon as that schedule is saved.
struct DropPathPenaltyApplication: Equatable {
    let minutesRemoved: Int
    let targetDate: String
    let windowTitle: String?
    let isPending: Bool
}

struct ScheduledTimeReductionApplication: Equatable {
    let minutesRemoved: Int
    let targetDate: String
    let windowID: String
    let windowTitle: String
}

enum PaperFlightRewards {
    static let startingMinutes = 2
    static let minimumLandingReward = 5
    static let maximumLandingReward = 10

    static func landingReward(for accumulatedMinutes: Int) -> Int {
        min(maximumLandingReward, max(minimumLandingReward, accumulatedMinutes))
    }

    static func outcome(
        landedSafely: Bool,
        accumulatedMinutes: Int,
        loss: PaperFlightLoss
    ) -> PaperFlightOutcome {
        if landedSafely {
            return PaperFlightOutcome(
                playerWon: true,
                minutes: landingReward(for: accumulatedMinutes),
                label: "Safe carrier landing"
            )
        }
        return PaperFlightOutcome(
            playerWon: false,
            minutes: loss.minutes,
            label: loss.label
        )
    }
}

enum PaperFlightLoss: CaseIterable, Equatable {
    case rocketStrike
    case waterCrash

    var minutes: Int {
        switch self {
        case .rocketStrike: return -3
        case .waterCrash: return -5
        }
    }

    var label: String {
        switch self {
        case .rocketStrike: return "Rocket strike"
        case .waterCrash: return "Missed the carrier"
        }
    }
}

struct PaperFlightOutcome: Equatable {
    let playerWon: Bool
    let minutes: Int
    let label: String
}

// MARK: - Time Loan

struct TimeLoan: Codable, Identifiable, Equatable {
    let id: String
    let borrowedMinutes: Int
    /// ISO8601.
    let borrowedAt: String
    /// `MivoDay` key — always `borrowedAt`'s day + 1. No multi-day loans, so
    /// this is the only date a loan is ever measured against.
    let repayDate: String
    var repaidAt: String?
    var status: TimeLoanStatus
    let sourceGame: IntentGameType
    let sourceSessionID: String?
}

enum TimeLoanStatus: String, Codable {
    case pending
    /// Tomorrow's own allowance fully covered what was borrowed.
    case repaid
    /// Tomorrow's own allowance was smaller than what was borrowed — the
    /// shortfall is forgiven here, never carried to the day after.
    case cleared
}

/// Pure settlement math — no storage, no `AppViewModel` access, so every
/// rule ("no multi-day debt," "FIFO when several loans share a repay date")
/// is verifiable with synthetic input rather than trusted on faith.
enum TimeLoanMath {
    /// Never more than what's actually needed, never more than tomorrow can
    /// still cover once loans already pending against that date are
    /// subtracted.
    static func borrowable(needed: Int, tomorrowRawTarget: Int, alreadyPendingAgainstTomorrow: Int) -> Int {
        let room = max(0, tomorrowRawTarget - alreadyPendingAgainstTomorrow)
        return max(0, min(needed, room))
    }

    /// Settles every `.pending` loan whose `repayDate` has arrived
    /// (`<= today`), FIFO by `borrowedAt`, against `todayRawTarget` — today's
    /// own live target, read once by the caller. Loans sharing a repay date
    /// never together draw more than that one number; whatever's left over
    /// when the target runs out is `.cleared`, not carried further. In the
    /// rare case of multiple distinct overdue repay dates (the app unopened
    /// for several days), each is settled against the same current
    /// `todayRawTarget` as a reasonable stand-in for a date that has already
    /// passed with no data of its own — never a source of extra debt either
    /// way, only ever forgiveness.
    static func settleDueLoans(
        _ loans: [TimeLoan],
        today: String,
        todayRawTarget: Int,
        now: Date = Date()
    ) -> [TimeLoan] {
        var result = loans
        let dueIndices = result.indices.filter {
            result[$0].status == .pending && result[$0].repayDate <= today
        }
        let sortedIndices = dueIndices.sorted { result[$0].borrowedAt < result[$1].borrowedAt }

        var remainingRoom = max(0, todayRawTarget)
        let nowString = ISO8601DateFormatter().string(from: now)
        for index in sortedIndices {
            let owed = result[index].borrowedMinutes
            if remainingRoom >= owed {
                result[index].status = .repaid
                remainingRoom -= owed
            } else {
                result[index].status = .cleared
                remainingRoom = 0
            }
            result[index].repaidAt = nowString
        }
        return result
    }
}
