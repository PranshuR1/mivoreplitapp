import Foundation

/// Personality changes *copy only*. It never feeds the behaviour engine,
/// cooldowns, or any Screen Time enforcement.
enum CompanionPersonality: String, Codable, CaseIterable, Identifiable {
    case gentle
    case playful
    case direct
    case quiet

    var id: String { rawValue }

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = CompanionPersonality(rawValue: raw) ?? .gentle
    }

    var displayName: String {
        switch self {
        case .gentle: return "Gentle"
        case .playful: return "Playful"
        case .direct: return "Direct"
        case .quiet: return "Quiet"
        }
    }

    var summary: String {
        switch self {
        case .gentle: return "Soft, observational nudges."
        case .playful: return "A little lighter, never a lecture."
        case .direct: return "Short and factual."
        case .quiet: return "Mostly body language, hardly any words."
        }
    }

    var example: String {
        switch self {
        case .gentle: return "“You've been here a little while.”"
        case .playful: return "“This scroll turned into a journey.”"
        case .direct: return "“30 minutes reached.”"
        case .quiet: return "(a quiet look)"
        }
    }

    /// Quiet speaks only for the few moments where silence would be unkind.
    var usesText: Bool { self != .quiet }
}
