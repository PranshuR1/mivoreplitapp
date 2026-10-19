import Foundation

/// The explicit state model. Views never decide what the companion is doing —
/// they render whichever of these `CompanionStateManager` publishes.
enum CompanionState: String, Codable, CaseIterable, Identifiable {
    case sleeping
    case idle
    case happy
    case curious
    case watching
    case tired
    case concerned
    case focused
    case celebrating
    case intervening
    case resting

    var id: String { rawValue }

    /// Shown on the Companion screen as "Right now". Observational, never a verdict.
    var label: String {
        switch self {
        case .sleeping: return "Asleep"
        case .idle: return "Relaxed"
        case .happy: return "Happy"
        case .curious: return "Curious"
        case .watching: return "Keeping watch"
        case .tired: return "Sleepy"
        case .concerned: return "Checking in"
        case .focused: return "Focused"
        case .celebrating: return "Celebrating"
        case .intervening: return "With you"
        case .resting: return "Resting"
        }
    }

    /// The clip that plays by default for this state.
    var defaultAnimation: CompanionAnimation {
        switch self {
        case .sleeping: return .sleeping
        case .idle, .happy, .resting: return .idleBreathing
        case .curious: return .curious
        case .watching: return .lookingAround
        case .tired: return .tired
        case .concerned, .intervening: return .intervention
        case .focused: return .focused
        case .celebrating: return .celebration
        }
    }

    /// States that should never carry text: the companion is asleep or heads-down.
    var isSilent: Bool {
        switch self {
        case .sleeping, .focused, .resting: return true
        default: return false
        }
    }
}

/// Named animation clips. A state picks a default clip; the Animations
/// settings screen can play any of them as a preview.
enum CompanionAnimation: String, Codable, CaseIterable, Identifiable {
    case idleBreathing
    case blink
    case sleeping
    case stretching
    case lookingAround
    case curious
    case tired
    case focused
    case celebration
    case intervention

    var id: String { rawValue }

    var label: String {
        switch self {
        case .idleBreathing: return "Breathing"
        case .blink: return "Blink"
        case .sleeping: return "Sleeping"
        case .stretching: return "Stretch"
        case .lookingAround: return "Look around"
        case .curious: return "Curious"
        case .tired: return "Sleepy"
        case .focused: return "Focused"
        case .celebration: return "Celebrate"
        case .intervention: return "Pause"
        }
    }

    /// The state whose posture the clip is previewed in.
    var previewState: CompanionState {
        switch self {
        case .idleBreathing, .blink, .stretching: return .idle
        case .sleeping: return .sleeping
        case .lookingAround: return .watching
        case .curious: return .curious
        case .tired: return .tired
        case .focused: return .focused
        case .celebration: return .celebrating
        case .intervention: return .intervening
        }
    }

    /// Clips that finish on their own and then return to rest.
    var isOneShot: Bool {
        switch self {
        case .blink, .stretching, .celebration: return true
        default: return false
        }
    }
}
