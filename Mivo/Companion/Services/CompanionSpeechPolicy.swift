import Foundation

/// Decides whether the companion may speak *now*. The engine says what it would
/// say; this decides whether saying it would be nagging. It never touches
/// enforcement — a pause screen always appears, with or without words.
enum CompanionSpeechPolicy {
    /// On a pause screen the person is already looking at the companion, so the
    /// frequency gap doesn't apply — only this floor, which stops one screen
    /// from being claimed twice. The daily cap still does.
    static let pauseMessageGap: TimeInterval = 45

    static func canSpeak(
        runtime: CompanionRuntime,
        frequency: CompanionInterventionFrequency,
        now: Date,
        calendar: Calendar,
        duringPause: Bool = false
    ) -> Bool {
        if let last = runtime.lastMessageDate {
            let gap = now.timeIntervalSince(last)
            let required = duringPause ? min(frequency.messageGap, pauseMessageGap) : frequency.messageGap
            // A negative gap means the clock moved backwards (time-zone or
            // manual change); treat it as "recent" rather than free to speak.
            if gap < required { return false }
        }
        let today = CompanionDay.key(now, calendar: calendar)
        let spokenToday = runtime.messageCountDayKey == today ? runtime.messagesToday : 0
        return spokenToday < frequency.dailyMessageCap
    }

    static func recordSpoken(runtime: inout CompanionRuntime, now: Date, calendar: Calendar) {
        let today = CompanionDay.key(now, calendar: calendar)
        if runtime.messageCountDayKey != today {
            runtime.messageCountDayKey = today
            runtime.messagesToday = 0
        }
        runtime.messagesToday += 1
        runtime.lastMessageDate = now
        runtime.messageVariantCounter &+= 1
    }
}
