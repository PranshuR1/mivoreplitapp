import Foundation

/// The Mivo backend's registry of official Spots: which IDs exist, who has
/// claimed them, and which Mivo has switched off. `SpotManager` only talks to
/// this, so the claim rules can be exercised without a network.
///
/// Every method throws `PhysicalSpotError` and nothing else.
protocol SpotRegistry: AnyObject {
    /// What an ID is to the signed-in person. Never says who owns someone else's Spot.
    func resolve(_ physicalID: String) async throws -> PhysicalSpotState
    /// Claims an unclaimed Spot for the signed-in account. Atomic on the backend;
    /// claiming a Spot you already own succeeds again.
    func claim(_ physicalID: String) async throws -> PhysicalSpotClaimOutcome
    /// Gives a Spot up so it can be claimed again. No effect on a Spot you don't own.
    func release(_ physicalID: String) async throws
    /// The signed-in account's Spots as the backend sees them.
    func mine() async throws -> [PhysicalSpotRecord]
}

final class BackendSpotRegistry: SpotRegistry {
    func resolve(_ physicalID: String) async throws -> PhysicalSpotState {
        do { return try await MivoBackendService.resolvePhysicalSpot(id: physicalID) }
        catch { throw Self.map(error) }
    }

    func claim(_ physicalID: String) async throws -> PhysicalSpotClaimOutcome {
        do { return try await MivoBackendService.claimPhysicalSpot(id: physicalID) }
        catch { throw Self.map(error) }
    }

    func release(_ physicalID: String) async throws {
        do { try await MivoBackendService.releasePhysicalSpot(id: physicalID) }
        catch { throw Self.map(error) }
    }

    func mine() async throws -> [PhysicalSpotRecord] {
        do { return try await MivoBackendService.myPhysicalSpots() }
        catch { throw Self.map(error) }
    }

    static func map(_ error: Error) -> PhysicalSpotError {
        if let known = error as? PhysicalSpotError { return known }
        if let backend = error as? MivoBackendError {
            switch backend {
            case .unavailable:
                return .offline
            case .authenticationRequired:
                return .signedOut
            case .server(let message):
                let lowered = message.lowercased()
                if lowered.contains("rate_limited") { return .rateLimited }
                if lowered.contains("authentication_required") || lowered.contains("jwt") { return .signedOut }
                return .failed
            }
        }
        return error is URLError ? .offline : .failed
    }
}

/// Test double. Behaves like the backend: IDs are random-looking strings the
/// test registers, claims are first-come, and nothing reveals another owner.
final class InMemorySpotRegistry: SpotRegistry {
    struct Entry: Equatable {
        var ownerID: String?
        var disabled = false
        var claimedAt: Date?
    }

    /// The account making the calls.
    var currentUserID = "user-1"
    var entries: [String: Entry] = [:]
    /// When set, every call throws it (offline, signed out, …).
    var failure: PhysicalSpotError?
    private(set) var resolveCalls = 0
    private(set) var claimCalls = 0
    private(set) var releaseCalls = 0
    private(set) var mineCalls = 0

    init(unclaimed ids: [String] = []) {
        for id in ids { entries[id] = Entry() }
    }

    func resolve(_ physicalID: String) async throws -> PhysicalSpotState {
        resolveCalls += 1
        if let failure { throw failure }
        guard let entry = entries[physicalID] else { return .invalid }
        if entry.disabled { return .disabled }
        guard let owner = entry.ownerID else { return .unclaimed }
        return owner == currentUserID ? .yours : .taken
    }

    func claim(_ physicalID: String) async throws -> PhysicalSpotClaimOutcome {
        claimCalls += 1
        if let failure { throw failure }
        guard var entry = entries[physicalID] else { return .invalid }
        if entry.disabled { return .disabled }
        if let owner = entry.ownerID, owner != currentUserID { return .taken }
        let at = entry.claimedAt ?? Date()
        entry.ownerID = currentUserID
        entry.claimedAt = at
        entries[physicalID] = entry
        return .claimed(ownerUserID: currentUserID, claimedAt: at)
    }

    func release(_ physicalID: String) async throws {
        releaseCalls += 1
        if let failure { throw failure }
        guard var entry = entries[physicalID], entry.ownerID == currentUserID else { return }
        entry.ownerID = nil
        entry.claimedAt = nil
        entries[physicalID] = entry
    }

    func mine() async throws -> [PhysicalSpotRecord] {
        mineCalls += 1
        if let failure { throw failure }
        return entries
            .filter { $0.value.ownerID == currentUserID }
            .map { PhysicalSpotRecord(spotID: $0.key, status: $0.value.disabled ? .disabled : .claimed, claimedAt: $0.value.claimedAt) }
            .sorted { $0.spotID < $1.spotID }
    }
}
