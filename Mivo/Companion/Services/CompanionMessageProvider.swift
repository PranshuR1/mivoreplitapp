import Foundation

/// Values a message may mention. Only ever real numbers Mivo has; a topic that
/// needs a number it doesn't have falls back to wording without one.
struct CompanionMessageContext: Equatable {
    var companionName: String = "Milo"
    var minutes: Int?
    var targetMinutes: Int?
}

/// All companion copy. Content only — which topic fires is the engine's
/// decision, and personality never feeds back into it.
///
/// Voice rules: observational, never a verdict. No guilt, no shame, no
/// diagnosis. `CompanionCopyTests` scans every string below for banned
/// phrasing.
enum CompanionMessageProvider {
    /// Text for a topic, or `nil` when this personality stays silent for it.
    /// `variant` is reduced modulo the number of options, so any counter works
    /// and the choice is deterministic.
    static func message(
        for topic: CompanionMessageTopic,
        personality: CompanionPersonality,
        context: CompanionMessageContext = CompanionMessageContext(),
        variant: Int = 0
    ) -> String? {
        let options = variants(for: topic, personality: personality, context: context)
        guard !options.isEmpty else { return nil }
        return options[((variant % options.count) + options.count) % options.count]
    }

    static func variants(
        for topic: CompanionMessageTopic,
        personality: CompanionPersonality,
        context: CompanionMessageContext = CompanionMessageContext()
    ) -> [String] {
        let name = context.companionName
        switch (topic, personality) {

        case (.pauseOpening, .gentle):
            return ["Still what you came here for?", "A small pause before you go in.", "Take a breath first."]
        case (.pauseOpening, .playful):
            return ["Quick check before the scroll begins.", "Door's open. Still the plan?", "Knock knock. Is this the plan?"]
        case (.pauseOpening, .direct):
            return ["Pause. Then choose.", "Is this what you came for?"]

        case (.longerThanUsual, .gentle):
            return ["Today's running a bit longer than usual.", "A little more than a usual day."]
        case (.longerThanUsual, .playful):
            return ["Busy day for the thumbs.", "Today's feed has been generous."]
        case (.longerThanUsual, .direct):
            return ["Above your usual day."]

        case (.stillHere, .gentle):
            return ["You've been here a little while.", "That went by quickly."]
        case (.stillHere, .playful):
            return ["This scroll turned into a journey.", "Time flew right by."]
        case (.stillHere, .direct):
            return ["More time has passed."]

        case (.nearTarget, .gentle):
            return ["You're getting close to today's target.", "Nearly at today's target."]
        case (.nearTarget, .playful):
            return ["Almost at today's line. No pressure.", "Today's finish line is in sight."]
        case (.nearTarget, .direct):
            if let minutes = context.minutes, let target = context.targetMinutes {
                return ["\(minutes) of \(target) minutes."]
            }
            return ["Close to today's target."]

        case (.overTarget, .gentle):
            return ["Maybe a good stopping point.", "Want a few minutes away?"]
        case (.overTarget, .playful):
            return ["Today's line is behind us. Stretch break?", "Past the line. Fresh air, maybe?"]
        case (.overTarget, .direct):
            if let target = context.targetMinutes { return ["\(target) minutes reached."] }
            return ["Today's target reached."]
        case (.overTarget, .quiet):
            return ["A good stopping point."]

        case (.lateNight, .gentle):
            return ["It's getting late.", "Maybe wind down soon?"]
        case (.lateNight, .playful):
            return ["The moon's out. The scroll can wait.", "Late hour. Cozy-blanket hour."]
        case (.lateNight, .direct):
            return ["It's late.", "Past bedtime."]
        case (.lateNight, .quiet):
            return ["It's late."]

        case (.repeatedPauses, .gentle):
            return ["Want a few minutes away?", "A few pauses already. Something else, maybe?"]
        case (.repeatedPauses, .playful):
            return ["Lap three! Try something else for a bit?", "Round and round. Want a change of scenery?"]
        case (.repeatedPauses, .direct):
            return ["Several pauses in the last hour."]

        case (.breakTaken, .gentle):
            return ["Nice pause.", "That took some intention."]
        case (.breakTaken, .playful):
            return ["Smooth move.", "Look at you, choosing things."]
        case (.breakTaken, .direct):
            return ["Pause completed."]

        case (.focusStarted, .gentle):
            return ["I'll keep you company."]
        case (.focusStarted, .playful):
            return ["Focus mode: paws up."]
        case (.focusStarted, .direct):
            return ["Focus started."]

        case (.focusDone, .gentle):
            return ["That was a good stretch of focus."]
        case (.focusDone, .playful):
            return ["Focus session: done and dusted."]
        case (.focusDone, .direct):
            return ["Focus session complete."]

        // Notification copy. Opt-in, so Quiet still gets words — a silent
        // notification can't exist — in the gentle voice.
        case (.focusInvitation, _):
            return ["Want to start a focus session?"]
        case (.bedtime, .playful):
            return ["\(name) has curled up for the night."]
        case (.bedtime, .direct):
            return ["\(name) is going to sleep."]
        case (.bedtime, _):
            return ["\(name)'s settling down for the night."]

        // Quiet personality: body language, not words.
        case (_, .quiet):
            return []
        }
    }

    /// The "Today" line on the Companion screen. Rewards intentional behaviour
    /// and says nothing negative on a quiet day.
    static func todaySummary(pauses: Int, focusSessions: Int) -> String {
        switch (pauses, focusSessions) {
        case (0, 0):
            return "A calm day so far."
        case (let p, 0):
            return "Nice — you've taken \(p) intentional pause\(p == 1 ? "" : "s")."
        case (0, let f):
            return "Nice — \(f) focus session\(f == 1 ? "" : "s") finished today."
        case (let p, let f):
            return "Nice — \(p) intentional pause\(p == 1 ? "" : "s") and \(f) focus session\(f == 1 ? "" : "s") today."
        }
    }
}
