import Foundation

/// Which character the Companion is.
///
/// Only the meerkat ships in V1. To add another character later:
///   1. add a case here (and set `isAvailable`),
///   2. add its artwork behind `CompanionArtworkRegistry` (see `CompanionArtwork.swift`),
///   3. give it a `defaultName`.
/// Nothing in the behaviour engine, persistence or widget knows which
/// character is selected — it only ever speaks in `CompanionState`.
enum CompanionType: String, Codable, CaseIterable, Identifiable {
    case meerkat

    var id: String { rawValue }

    /// A stored value from a newer build (a character this build doesn't have)
    /// decodes as the meerkat instead of discarding the user's preferences.
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = CompanionType(rawValue: raw) ?? .meerkat
    }

    var displayName: String {
        switch self {
        case .meerkat: return "Meerkat"
        }
    }

    var defaultName: String {
        switch self {
        case .meerkat: return "Milo"
        }
    }

    var tagline: String {
        switch self {
        case .meerkat: return "Upright, watchful and calm."
        }
    }

    /// Characters that exist in the enum but are not finished are never
    /// offered in Settings.
    var isAvailable: Bool {
        switch self {
        case .meerkat: return true
        }
    }

    static var available: [CompanionType] { allCases.filter(\.isAvailable) }
}
