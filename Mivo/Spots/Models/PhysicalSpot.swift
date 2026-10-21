import Foundation

/// The tie between a Spot setup on this phone and an official Mivo Spot — the
/// physical product, pre-programmed by Mivo with `https://usemivo.app/s/<ID>`.
///
/// The ID is the only thing the product carries. Everything about what the Spot
/// does lives in the surrounding `MivoSpot` (and nothing about it is written to,
/// or can be read from, the tag), so renaming a Spot or turning a Study Spot into
/// a Sleep Spot never touches the hardware.
///
/// This is a cache of the Mivo backend's registry, which is the source of truth
/// for who owns an ID and whether Mivo has switched it off. `SpotManager`
/// re-checks it in the background.
struct PhysicalSpotLink: Codable, Equatable {
    enum Status: String, Codable {
        /// Claimed by this account and working.
        case claimed
        /// Mivo has switched this Spot off (for example it was reported lost).
        case disabled
    }

    /// The public ID in the Spot's URL, e.g. `A7K92X`.
    var spotID: String
    /// The signed-in account's backend user ID at claim time. Informational:
    /// ownership is decided by the backend, never by this value.
    var ownerUserID: String?
    var status: Status
    var claimedAt: Date
    var lastScannedAt: Date?
    var lastVerifiedAt: Date?

    /// "A7K92X" → "…K92X" for places that show an ID without spelling all of it.
    var shortID: String { spotID.count > 4 ? "…" + spotID.suffix(4) : spotID }
}

/// The shape of an official Spot ID, and how one is normalised.
enum PhysicalSpotID {
    /// Uppercase letters and digits, 6–12 long. Mivo generates 8 from an alphabet
    /// without look-alike characters; the parser is more tolerant than the
    /// generator so older and shorter IDs still resolve. It is a lookup key only
    /// — a tag anyone can write is never trusted to say anything else.
    static let lengthRange = 6...12

    /// Trims, uppercases and validates. nil when it can't be a Spot ID.
    static func normalize(_ raw: String) -> String? {
        let id = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard lengthRange.contains(id.count) else { return nil }
        let valid = id.unicodeScalars.allSatisfy {
            ($0.value >= 65 && $0.value <= 90) || ($0.value >= 48 && $0.value <= 57)
        }
        return valid ? id : nil
    }
}

/// What the Mivo backend says an ID is to the person asking. It never says who
/// owns a Spot someone else has claimed.
enum PhysicalSpotState: String, Equatable {
    /// Nobody has claimed it: the person can set it up.
    case unclaimed
    /// Already claimed by this account (a new phone, or app data was cleared).
    case yours
    /// Claimed by a different account.
    case taken
    /// Switched off by Mivo.
    case disabled
    /// No such ID.
    case invalid
}

enum PhysicalSpotClaimOutcome: Equatable {
    case claimed(ownerUserID: String?, claimedAt: Date)
    case taken
    case disabled
    case invalid
}

/// One of the signed-in account's Spots as the backend sees it.
struct PhysicalSpotRecord: Equatable {
    var spotID: String
    var status: PhysicalSpotLink.Status
    var claimedAt: Date?
}

/// Why a claim didn't complete. `message` is what the person reads.
enum PhysicalSpotError: Error, Equatable {
    case taken
    case disabled
    case invalid
    case rateLimited
    case signedOut
    case offline
    case emptyName
    case tooManySpots
    case failed

    var message: String {
        switch self {
        case .taken: return "This Mivo Spot is already connected to another account."
        case .disabled: return "This Mivo Spot is switched off."
        case .invalid: return "We couldn't find this Mivo Spot."
        case .rateLimited: return "Too many tries. Wait a few minutes and tap your Mivo Spot again."
        case .signedOut: return "Sign in to Mivo to use this Spot."
        case .offline: return "Mivo couldn't reach the internet to check this Spot. Connect and tap it again."
        case .emptyName: return "Give the Spot a name first."
        case .tooManySpots: return "That's the most Spots Mivo can hold. Remove one first."
        case .failed: return "Something went wrong. Try again."
        }
    }
}

/// A scanned official Spot that needs the person to set it up, handed to the UI.
struct PhysicalSpotClaimRequest: Identifiable, Equatable {
    let id = UUID()
    let physicalID: String
    /// True when the backend already lists this Spot under this account — it only
    /// needs setting up on this phone, not claiming again.
    var alreadyYours = false
    /// Set when started from an existing Spot's "Connect a Mivo Spot": the Spot to
    /// attach it to, so the choice isn't asked again.
    var pairWithSpotID: String?
}
