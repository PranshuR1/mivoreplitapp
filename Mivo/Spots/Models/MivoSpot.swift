import Foundation

/// The apps (and categories/sites) a Spot covers.
///
/// A `FamilyActivitySelection` is opaque by design — Apple hands out tokens, not
/// bundle identifiers — so the selection travels as the data the existing
/// protected-apps code already persists, next to a few best-effort display
/// strings captured when it was chosen.
struct SpotAppSelection: Codable, Equatable {
    /// JSON-encoded `FamilyActivitySelection`; nil until apps are chosen.
    var data: Data?
    /// Names resolved at selection time. Apple does not guarantee a name for
    /// every token, so this can be shorter than `applicationCount`.
    var appNames: [String]
    var applicationCount: Int
    var categoryCount: Int
    var webDomainCount: Int

    static let empty = SpotAppSelection(
        data: nil, appNames: [], applicationCount: 0, categoryCount: 0, webDomainCount: 0
    )

    var isEmpty: Bool { applicationCount + categoryCount + webDomainCount == 0 }

    /// "Instagram, TikTok, YouTube" when every app has a name, otherwise a count.
    var summary: String {
        if isEmpty { return "No apps yet" }
        if applicationCount > 0, appNames.count == applicationCount,
           categoryCount == 0, webDomainCount == 0 {
            return Self.joined(appNames, limit: 3)
        }
        var parts: [String] = []
        if applicationCount > 0 { parts.append(applicationCount == 1 ? "1 app" : "\(applicationCount) apps") }
        if categoryCount > 0 { parts.append(categoryCount == 1 ? "1 category" : "\(categoryCount) categories") }
        if webDomainCount > 0 { parts.append(webDomainCount == 1 ? "1 site" : "\(webDomainCount) sites") }
        return parts.joined(separator: " · ")
    }

    static func joined(_ names: [String], limit: Int) -> String {
        guard names.count > limit else { return names.joined(separator: ", ") }
        return names.prefix(limit).joined(separator: ", ") + " +\(names.count - limit)"
    }
}

/// How a Spot setup made by the first version is tied to something physical:
/// a sticker the person wrote themselves, or a Shortcuts automation.
///
/// Official Mivo Spots use `MivoSpot.physical` instead (`PhysicalSpotLink`).
/// This stays so those earlier setups keep working; nothing creates an
/// `.ndefTag` binding any more.
struct SpotTagBinding: Codable, Equatable {
    enum Carrier: String, Codable {
        /// An NDEF tag the person wrote the Spot link onto (first version).
        case ndefTag
        /// An iOS Shortcuts automation that runs the Spot intent.
        case shortcut
        /// Superseded by `MivoSpot.physical`. Kept so old data still decodes.
        case mivoProduct
    }

    var carrier: Carrier
    /// The tag's hardware serial as hex, when iOS exposed it while writing.
    var identifier: String?
    var connectedAt: Date
    var lastScannedAt: Date?
}

struct MivoSpot: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    /// An emoji, or `sf:<symbol name>` for an SF Symbol. See `SpotIcon`.
    var icon: String
    var createdAt: Date
    var selectedApplications: SpotAppSelection
    var mode: SpotMode
    /// nil means "until I end it" (capped — see `SpotKeys.openEndedCapHours`).
    var defaultDurationMinutes: Int?
    /// A self-written sticker or Shortcut from the first version. See `SpotTagBinding`.
    var tag: SpotTagBinding?
    /// The official Mivo Spot this setup runs from. nil makes it a Digital Spot.
    /// Optional with a nil default, so Spots saved before this existed decode as is.
    var physical: PhysicalSpotLink?
    var isEnabled: Bool

    init(
        id: String = MivoSpot.makeID(),
        name: String,
        icon: String = SpotIcon.defaultIcon,
        createdAt: Date = Date(),
        selectedApplications: SpotAppSelection = .empty,
        mode: SpotMode = .pause,
        defaultDurationMinutes: Int? = 60,
        tag: SpotTagBinding? = nil,
        physical: PhysicalSpotLink? = nil,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.createdAt = createdAt
        self.selectedApplications = selectedApplications
        self.mode = mode
        self.defaultDurationMinutes = defaultDurationMinutes
        self.tag = tag
        self.physical = physical
        self.isEnabled = isEnabled
    }

    /// Lowercase so the same ID survives being written to a tag and read back
    /// through a case-sensitive universal-link path.
    static func makeID() -> String { UUID().uuidString.lowercased() }

    var nfcIdentifier: String? { tag?.identifier }
    var isPhysical: Bool { physical != nil }
    /// Something outside the app triggers this Spot: an official Mivo Spot, or a
    /// first-version sticker or Shortcut.
    var isConnected: Bool { physical != nil || tag != nil }
    /// "Mivo Spot" once an official Spot is connected, "Digital Spot" until then.
    var kindLabel: String { isPhysical ? "Mivo Spot" : "Digital Spot" }
    /// The link that starts this Spot: its official URL, or the first-version link.
    var link: URL {
        if let physical { return SpotLink.physicalURL(for: physical.spotID) }
        return SpotLink.universalURL(for: id)
    }
    /// A Mivo-switched-off Spot can't start, whatever the person's own switch says.
    var isSwitchedOffByMivo: Bool { physical?.status == .disabled }

    var durationLabel: String {
        guard let minutes = defaultDurationMinutes else { return "Until I end it" }
        return SpotFormat.duration(minutes: minutes)
    }
}

/// Emoji-or-symbol icons. Stored as a single string so a Spot stays one small value.
enum SpotIcon {
    static let defaultIcon = "sf:mappin.and.ellipse"
    private static let symbolPrefix = "sf:"

    enum Kind: Equatable {
        case symbol(String)
        case emoji(String)
    }

    static func kind(of icon: String) -> Kind {
        if icon.hasPrefix(symbolPrefix) { return .symbol(String(icon.dropFirst(symbolPrefix.count))) }
        return icon.isEmpty ? .symbol("mappin.and.ellipse") : .emoji(icon)
    }

    static func symbol(_ name: String) -> String { symbolPrefix + name }

    /// Normalises user-typed emoji input to a single character, falling back to
    /// the default symbol when nothing usable was entered.
    static func emoji(from text: String) -> String {
        guard let first = text.trimmingCharacters(in: .whitespacesAndNewlines).first else { return defaultIcon }
        return String(first)
    }
}

/// The suggested starting points offered in the setup flow.
struct SpotTemplate: Identifiable, Equatable {
    let id: String
    let name: String
    let icon: String
    let suggestedMode: SpotMode

    static let all: [SpotTemplate] = [
        SpotTemplate(id: "study", name: "Study Desk", icon: SpotIcon.symbol("books.vertical"), suggestedMode: .focus),
        SpotTemplate(id: "bedside", name: "Bedside", icon: SpotIcon.symbol("bed.double"), suggestedMode: .pause),
        SpotTemplate(id: "kitchen", name: "Kitchen", icon: SpotIcon.symbol("fork.knife"), suggestedMode: .intention),
        SpotTemplate(id: "car", name: "Car", icon: SpotIcon.symbol("car"), suggestedMode: .awareness),
        SpotTemplate(id: "gym", name: "Gym", icon: SpotIcon.symbol("dumbbell"), suggestedMode: .focus),
        SpotTemplate(id: "office", name: "Office", icon: SpotIcon.symbol("briefcase"), suggestedMode: .focus),
        SpotTemplate(id: "library", name: "Library", icon: SpotIcon.symbol("building.columns"), suggestedMode: .focus),
        SpotTemplate(id: "living-room", name: "Living Room", icon: SpotIcon.symbol("sofa"), suggestedMode: .intention),
        SpotTemplate(id: "commute", name: "Commute", icon: SpotIcon.symbol("tram"), suggestedMode: .awareness),
        SpotTemplate(id: "bathroom", name: "Bathroom", icon: SpotIcon.symbol("shower"), suggestedMode: .pause),
        SpotTemplate(id: "cafe", name: "Café", icon: SpotIcon.symbol("cup.and.saucer"), suggestedMode: .awareness),
        SpotTemplate(id: "custom", name: "", icon: SpotIcon.defaultIcon, suggestedMode: .pause)
    ]

    var isCustom: Bool { id == "custom" }
    var displayName: String { isCustom ? "Custom" : name }
}

/// Symbols offered next to the emoji field.
enum SpotIconChoices {
    static let symbols = [
        "books.vertical", "desktopcomputer", "bed.double", "fork.knife", "car", "dumbbell",
        "house", "door.left.hand.open", "sofa", "figure.walk", "cup.and.saucer", "leaf",
        "briefcase", "building.columns", "tram", "shower"
    ]
}

enum SpotFormat {
    /// "25 min", "1 hr", "1 hr 12 min".
    static func duration(minutes: Int) -> String {
        let minutes = max(0, minutes)
        if minutes < 60 { return "\(minutes) min" }
        let hours = minutes / 60
        let rest = minutes % 60
        return rest == 0 ? "\(hours) hr" : "\(hours) hr \(rest) min"
    }

    /// Compact form for stats and summaries: "1h 12m", "8m".
    static func compact(minutes: Int) -> String {
        let minutes = max(0, minutes)
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        let rest = minutes % 60
        return rest == 0 ? "\(hours)h" : "\(hours)h \(rest)m"
    }
}
