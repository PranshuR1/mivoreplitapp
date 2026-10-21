import Foundation

/// The identification layer: one Spot ID, carried in a link.
///
/// What goes on a physical tag is only this link — never the Spot's settings —
/// so editing a Spot never means rewriting the tag, and anything that can
/// present the link activates the same Spot.
///
/// Two link shapes exist:
///
/// - **`https://usemivo.app/s/<ID>`** — an official Mivo Spot. Mivo programs it
///   onto the tag before sale; `<ID>` is a short random code that the Mivo
///   backend knows (`PhysicalSpotID`). This is the product.
/// - **`https://usemivo.app/spot/<uuid>`** — the first version, where a person
///   wrote a sticker themselves. Still honoured so those stickers keep working;
///   nothing in the app writes this shape any more.
///
/// The link on a tag is the **universal link**. iOS's background tag reading only
/// routes a scanned tag to an app when its URL record is a universal link the app
/// is associated with (`applinks:usemivo.app`); a custom `mivo://` URL on a tag is
/// not handed to the app by the system. The custom scheme remains for in-app use
/// and the web fallback page's "Open in Mivo" button.
enum SpotLink {
    static let universalHost = "usemivo.app"
    /// Legacy, self-written stickers: `/spot/<uuid>`.
    static let pathComponent = "spot"
    /// Official Mivo Spots: `/s/<ID>`.
    static let physicalPathComponent = "s"
    static let customScheme = "mivo"
    /// `mivo://spot-prompt` — the shield extension's request to open Mivo.
    static let promptHost = "spot-prompt"

    static func universalURL(for spotID: String) -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = universalHost
        components.path = "/\(pathComponent)/\(spotID)"
        return components.url ?? URL(string: "https://\(universalHost)/\(pathComponent)/\(spotID)")!
    }

    static func customSchemeURL(for spotID: String) -> URL {
        URL(string: "\(customScheme)://\(pathComponent)/\(spotID)")!
    }

    /// The URL programmed onto an official Mivo Spot.
    static func physicalURL(for physicalID: String) -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = universalHost
        components.path = "/\(physicalPathComponent)/\(physicalID)"
        return components.url ?? URL(string: "https://\(universalHost)/\(physicalPathComponent)/\(physicalID)")!
    }

    /// What a link points at.
    enum Target: Equatable {
        /// An official Mivo Spot, by its public ID (uppercase).
        case physical(String)
        /// A Spot created by the first version, by its local ID (lowercase UUID).
        case legacy(String)
    }

    static func target(from url: URL) -> Target? {
        if let id = physicalSpotID(from: url) { return .physical(id) }
        if let id = spotID(from: url) { return .legacy(id) }
        return nil
    }

    /// Extracts an official Spot ID from `https://usemivo.app/s/<ID>` or
    /// `mivo://s/<ID>`, or nil for anything else.
    static func physicalSpotID(from url: URL) -> String? {
        let parts = url.pathComponents.filter { $0 != "/" }
        let candidate: String?
        switch url.scheme?.lowercased() {
        case "https":
            guard url.host?.lowercased() == universalHost else { return nil }
            candidate = parts.count == 2 && parts[0] == physicalPathComponent ? parts[1] : nil
        case customScheme:
            // mivo://s/<ID> parses with "s" as the host.
            guard url.host?.lowercased() == physicalPathComponent else { return nil }
            candidate = parts.count == 1 ? parts[0] : nil
        default:
            candidate = nil
        }
        return candidate.flatMap(PhysicalSpotID.normalize)
    }

    /// Extracts a legacy Spot ID from either legacy link shape, or nil for
    /// anything else (including official `/s/` links — see `physicalSpotID(from:)`).
    static func spotID(from url: URL) -> String? {
        let candidate: String?
        switch url.scheme?.lowercased() {
        case "https":
            guard url.host?.lowercased() == universalHost else { return nil }
            let parts = url.pathComponents.filter { $0 != "/" }
            candidate = parts.count == 2 && parts[0] == pathComponent ? parts[1] : nil
        case customScheme:
            // mivo://spot/<id> parses with "spot" as the host.
            guard url.host?.lowercased() == pathComponent else { return nil }
            let parts = url.pathComponents.filter { $0 != "/" }
            candidate = parts.count == 1 ? parts[0] : nil
        default:
            candidate = nil
        }
        guard let candidate else { return nil }
        let id = candidate.lowercased()
        return isValidSpotID(id) ? id : nil
    }

    /// Lowercase letters, digits and dashes, 8–64 long. Strict on purpose: the
    /// ID arrives from a tag anyone can write, so it is never trusted as more
    /// than a lookup key.
    static func isValidSpotID(_ id: String) -> Bool {
        guard (8...64).contains(id.count) else { return false }
        return id.unicodeScalars.allSatisfy {
            ($0.value >= 97 && $0.value <= 122) || ($0.value >= 48 && $0.value <= 57) || $0 == "-"
        }
    }
}
