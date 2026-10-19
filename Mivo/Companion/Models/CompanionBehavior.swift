import Foundation

/// What the person's current pattern *is*. Adding a classification means one
/// case here plus one branch in `CompanionBehaviorEngine.classify` — only add
/// one when Mivo actually has the data to support it.
enum CompanionBehavior: String, Codable, CaseIterable {
    case quietHours
    case focusSession
    case lateNightUse
    case repeatedIntervention
    case intentionalBreak
    case postInterventionContinuation
    case thresholdExceeded
    case approachingLimit
    case extendedUse
    case normalUse
}

/// How much the moment matters. Even `.firm` is observational — there is no
/// level that scolds.
enum CompanionSeverity: Int, Codable, Comparable {
    case calm
    case gentle
    case notice
    case firm

    static func < (lhs: CompanionSeverity, rhs: CompanionSeverity) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// What Mivo might offer next. Each maps onto an action Mivo already has.
enum CompanionRecommendation: String, Codable {
    case none
    /// Step away for a few minutes (the existing "I've changed my mind" / leave).
    case stepAway
    /// Start a Mivo Still session.
    case startFocus

    var label: String? {
        switch self {
        case .none: return nil
        case .stepAway: return "A few minutes away could feel good."
        case .startFocus: return "A focus session might help."
        }
    }
}

enum CompanionMessageTopic: String, CaseIterable {
    case pauseOpening
    case longerThanUsual
    case stillHere
    case nearTarget
    case overTarget
    case lateNight
    case repeatedPauses
    case breakTaken
    case focusStarted
    case focusDone
    case focusInvitation
    case bedtime
}

/// The engine's full answer for one moment.
struct CompanionBehaviorResult: Equatable {
    var behavior: CompanionBehavior
    var state: CompanionState
    var animation: CompanionAnimation
    var topic: CompanionMessageTopic?
    var severity: CompanionSeverity
    var recommendation: CompanionRecommendation
    /// How long before this behaviour should speak again.
    var cooldown: TimeInterval
    var dataLimits: [CompanionDataLimit]
}
