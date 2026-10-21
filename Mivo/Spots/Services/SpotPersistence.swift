import Foundation

/// Where Spots and their history live. The manager only talks to this, so the
/// rules around Spots can be exercised without touching real storage.
protocol SpotPersisting: AnyObject {
    /// The signed-in account the data belongs to. nil before sign-in.
    var accountEmail: String? { get set }

    func loadSpots() -> [MivoSpot]
    func saveSpots(_ spots: [MivoSpot])
    func loadSessions() -> [SpotSession]
    func saveSessions(_ sessions: [SpotSession])
    func loadActiveSession() -> SpotSession?
    func saveActiveSession(_ session: SpotSession?)
    /// Removes everything stored for the current account.
    func erase()
}

/// Mivo's existing persistence: `StorageService`, keyed per account, so a Spot
/// follows the same sign-out and delete-account rules as every other piece of
/// user data (`removeUserScopedMivoData` already sweeps these keys).
final class StorageSpotPersistence: SpotPersisting {
    var accountEmail: String?

    init(accountEmail: String? = StorageService.activeUserEmail) {
        self.accountEmail = accountEmail
    }

    func loadSpots() -> [MivoSpot] { load([MivoSpot].self, .mivoSpots) ?? [] }
    func saveSpots(_ spots: [MivoSpot]) { save(spots, .mivoSpots) }
    func loadSessions() -> [SpotSession] { load([SpotSession].self, .mivoSpotSessions) ?? [] }
    func saveSessions(_ sessions: [SpotSession]) { save(sessions, .mivoSpotSessions) }
    func loadActiveSession() -> SpotSession? { load(SpotSession.self, .mivoSpotActiveSession) }

    func saveActiveSession(_ session: SpotSession?) {
        if let session {
            save(session, .mivoSpotActiveSession)
        } else {
            remove(.mivoSpotActiveSession)
        }
    }

    func erase() {
        remove(.mivoSpots)
        remove(.mivoSpotSessions)
        remove(.mivoSpotActiveSession)
    }

    private func load<T: Decodable>(_ type: T.Type, _ key: StorageKey) -> T? {
        guard let accountEmail else { return StorageService.load(type, forKey: key) }
        return StorageService.load(type, forKey: key, email: accountEmail)
    }

    private func save<T: Encodable>(_ value: T, _ key: StorageKey) {
        if let accountEmail {
            StorageService.save(value, forKey: key, email: accountEmail)
        } else {
            StorageService.save(value, forKey: key)
        }
    }

    private func remove(_ key: StorageKey) {
        if let accountEmail {
            StorageService.remove(forKey: key, email: accountEmail)
        } else {
            StorageService.remove(forKey: key)
        }
    }
}

/// Test double.
final class InMemorySpotPersistence: SpotPersisting {
    var accountEmail: String?
    private var spots: [MivoSpot] = []
    private var sessions: [SpotSession] = []
    private var active: SpotSession?

    init() {}

    func loadSpots() -> [MivoSpot] { spots }
    func saveSpots(_ spots: [MivoSpot]) { self.spots = spots }
    func loadSessions() -> [SpotSession] { sessions }
    func saveSessions(_ sessions: [SpotSession]) { self.sessions = sessions }
    func loadActiveSession() -> SpotSession? { active }
    func saveActiveSession(_ session: SpotSession?) { active = session }
    func erase() { spots = []; sessions = []; active = nil }
}
