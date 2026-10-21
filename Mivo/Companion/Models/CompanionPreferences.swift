import Foundation

/// How often the companion *speaks up*. This never changes when Mivo pauses or
/// shields an app — enforcement is configured elsewhere and is untouched.
enum CompanionInterventionFrequency: String, Codable, CaseIterable, Identifiable {
    case minimal
    case balanced
    case attentive

    var id: String { rawValue }

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = CompanionInterventionFrequency(rawValue: raw) ?? .balanced
    }

    var displayName: String {
        switch self {
        case .minimal: return "Rarely"
        case .balanced: return "Balanced"
        case .attentive: return "Often"
        }
    }

    var summary: String {
        switch self {
        case .minimal: return "A few words a day, when something stands out."
        case .balanced: return "Speaks up through the day, never nagging."
        case .attentive: return "Frequent check-ins, still never nagging."
        }
    }

    /// Minimum gap between two companion messages.
    var messageGap: TimeInterval {
        switch self {
        case .minimal: return 20 * 60
        case .balanced: return 8 * 60
        case .attentive: return 4 * 60
        }
    }

    var dailyMessageCap: Int {
        switch self {
        case .minimal: return 5
        case .balanced: return 12
        case .attentive: return 24
        }
    }

    /// How long the companion rests, silently, after an intervention resolves.
    var postInterventionCooldown: TimeInterval {
        switch self {
        case .minimal: return 30 * 60
        case .balanced: return 10 * 60
        case .attentive: return 5 * 60
        }
    }
}

/// Everything the user can configure. Runtime values (cooldowns, last state)
/// live in `CompanionRuntime` so "Reset preferences" never wipes progress.
struct CompanionPreferences: Codable, Equatable {
    static let currentSchemaVersion = 1
    static let maxNameLength = 16

    var schemaVersion: Int = CompanionPreferences.currentSchemaVersion
    var isEnabled: Bool = true
    var hasCompletedOnboarding: Bool = false
    var companionType: CompanionType = .meerkat
    var name: String = CompanionType.meerkat.defaultName
    var personality: CompanionPersonality = .gentle
    var interventionFrequency: CompanionInterventionFrequency = .balanced
    var quietHours: CompanionTimeWindow = .defaultQuietHours
    var bedtime: CompanionBedtime = .default
    var animationsEnabled: Bool = true
    /// Whether the companion wanders around inside Mivo. Needs animations on.
    var roamingEnabled: Bool = true
    var notificationsEnabled: Bool = false

    static let `default` = CompanionPreferences()

    init() {}

    /// Companion presence requires both the switch and a finished onboarding —
    /// the privacy explanation is shown before it ever reacts to anything.
    var isActive: Bool { isEnabled && hasCompletedOnboarding }

    /// On by default but not yet introduced: Home offers to meet the companion.
    var isAwaitingIntroduction: Bool { isEnabled && !hasCompletedOnboarding }

    /// Back to defaults, keeping on/off and onboarding so the flow doesn't replay.
    func resetToDefaults() -> CompanionPreferences {
        var fresh = CompanionPreferences()
        fresh.isEnabled = isEnabled
        fresh.hasCompletedOnboarding = hasCompletedOnboarding
        return fresh
    }

    static func sanitizedName(_ raw: String, for type: CompanionType) -> String {
        let collapsed = raw
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        let capped = String(collapsed.prefix(maxNameLength)).trimmingCharacters(in: .whitespaces)
        return capped.isEmpty ? type.defaultName : capped
    }

    // Tolerant decoding: a missing or unreadable field falls back to its
    // default instead of failing the whole load and silently resetting the user.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = c.value(.schemaVersion, default: Self.currentSchemaVersion)
        isEnabled = c.value(.isEnabled, default: true)
        hasCompletedOnboarding = c.value(.hasCompletedOnboarding, default: false)
        companionType = c.value(.companionType, default: .meerkat)
        personality = c.value(.personality, default: .gentle)
        interventionFrequency = c.value(.interventionFrequency, default: .balanced)
        quietHours = c.value(.quietHours, default: .defaultQuietHours)
        bedtime = c.value(.bedtime, default: .default)
        animationsEnabled = c.value(.animationsEnabled, default: true)
        roamingEnabled = c.value(.roamingEnabled, default: true)
        notificationsEnabled = c.value(.notificationsEnabled, default: false)
        name = Self.sanitizedName(c.value(.name, default: ""), for: companionType)
    }
}

extension KeyedDecodingContainer {
    func value<T: Decodable>(_ key: Key, default fallback: @autoclosure () -> T) -> T {
        (try? decodeIfPresent(T.self, forKey: key)) ?? fallback()
    }

    func optional<T: Decodable>(_ key: Key) -> T? {
        try? decodeIfPresent(T.self, forKey: key)
    }
}
