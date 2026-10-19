import Foundation

enum CompanionInterventionOutcome: String, Codable, Equatable {
    /// The person went through the pause and chose to continue.
    case continued
    /// The person walked away — the "intentional exit".
    case exited
}

/// Small, aggregate bookkeeping the behaviour engine needs between launches.
/// Absolute timestamps only — nothing here depends on a running timer, so a
/// device restart or backgrounding loses nothing.
struct CompanionRuntime: Codable, Equatable {
    var currentState: CompanionState = .idle
    var lastInterventionDate: Date?
    var lastOutcome: CompanionInterventionOutcome?
    var lastOutcomeDate: Date?
    /// Today's screen-time total when the last pause resolved; lets the engine
    /// tell "kept going afterwards" from "stopped".
    var minutesAtLastIntervention: Int?
    var minutesAtLastInterventionDayKey: String?
    var cooldownUntil: Date?
    var lastMessageDate: Date?
    var messageCountDayKey: String = ""
    var messagesToday: Int = 0
    var messageVariantCounter: Int = 0
    var lastFocusCompletedAt: Date?
    var lastFocusNudgeDayKey: String?
    var lastBedtimeNoticeDayKey: String?

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        currentState = c.value(.currentState, default: .idle)
        lastInterventionDate = c.optional(.lastInterventionDate)
        lastOutcome = c.optional(.lastOutcome)
        lastOutcomeDate = c.optional(.lastOutcomeDate)
        minutesAtLastIntervention = c.optional(.minutesAtLastIntervention)
        minutesAtLastInterventionDayKey = c.optional(.minutesAtLastInterventionDayKey)
        cooldownUntil = c.optional(.cooldownUntil)
        lastMessageDate = c.optional(.lastMessageDate)
        messageCountDayKey = c.value(.messageCountDayKey, default: "")
        messagesToday = c.value(.messagesToday, default: 0)
        messageVariantCounter = c.value(.messageVariantCounter, default: 0)
        lastFocusCompletedAt = c.optional(.lastFocusCompletedAt)
        lastFocusNudgeDayKey = c.optional(.lastFocusNudgeDayKey)
        lastBedtimeNoticeDayKey = c.optional(.lastBedtimeNoticeDayKey)
    }
}
