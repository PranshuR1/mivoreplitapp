import Foundation

/// A user's pre-committed, real-world substitute for opening a blocked app —
/// the same idea as replacing a drink with M&M's: keep the cue, keep the
/// physical routine, swap only the reward. Chosen in advance (onboarding,
/// the one-time existing-user prompt, or Settings) so there's nothing left
/// to decide in the two-second window an urge actually hits.
struct UserSwap: Codable, Equatable {
    var id: String
    var title: String
    var icon: String
    var isCustom: Bool

    static func custom(_ title: String) -> UserSwap {
        UserSwap(id: "custom", title: title, icon: "sparkles", isCustom: true)
    }
}

/// Deliberately physical and off-screen — anything that could itself be done
/// by scrolling further defeats the point.
enum SwapSuggestion: String, CaseIterable, Identifiable {
    case gum, water, stretch, stepOutside, textSomeone, fidget

    var id: String { rawValue }

    var title: String {
        switch self {
        case .gum: return "Chew gum or a mint"
        case .water: return "Drink a glass of water"
        case .stretch: return "Stretch for 30 seconds"
        case .stepOutside: return "Step outside for a minute"
        case .textSomeone: return "Text one specific person"
        case .fidget: return "Squeeze a fidget object"
        }
    }

    var icon: String {
        switch self {
        case .gum: return "leaf.fill"
        case .water: return "drop.fill"
        case .stretch: return "figure.flexibility"
        case .stepOutside: return "figure.walk"
        case .textSomeone: return "message.fill"
        case .fidget: return "hand.raised.fill"
        }
    }

    var swap: UserSwap {
        UserSwap(id: rawValue, title: title, icon: icon, isCustom: false)
    }
}
