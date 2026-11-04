import Foundation

/// Where locks and their history live. The manager only talks to this, so the rules
/// around a lock can be exercised without touching real storage.
protocol LockInPersisting: AnyObject {
    /// The signed-in account the data belongs to. nil before sign-in.
    var accountEmail: String? { get set }

    func loadCurrent() -> LockIn?
    func saveCurrent(_ lock: LockIn?)
    func loadHistory() -> [LockIn]
    func saveHistory(_ history: [LockIn])
    func loadKeyholder() -> LockInKeyholder?
    func saveKeyholder(_ keyholder: LockInKeyholder?)
    /// The apps used for the last lock, offered again next time.
    func loadLastApps() -> ScreenTimeAppSelection?
    func saveLastApps(_ apps: ScreenTimeAppSelection)
    /// Removes everything stored for the current account.
    func erase()
}

/// Mivo's existing persistence: `StorageService`, keyed per account, so a lock
/// follows the same sign-out and delete-account rules as every other piece of user
/// data (`removeUserScopedMivoData` already sweeps these keys).
final class StorageLockInPersistence: LockInPersisting {
    var accountEmail: String?

    init(accountEmail: String? = StorageService.activeUserEmail) {
        self.accountEmail = accountEmail
    }

    func loadCurrent() -> LockIn? { load(LockIn.self, .mivoLockIn) }

    func saveCurrent(_ lock: LockIn?) {
        if let lock {
            save(lock, .mivoLockIn)
        } else {
            remove(.mivoLockIn)
        }
    }

    func loadHistory() -> [LockIn] { load([LockIn].self, .mivoLockInHistory) ?? [] }
    func saveHistory(_ history: [LockIn]) { save(history, .mivoLockInHistory) }

    func loadKeyholder() -> LockInKeyholder? { load(LockInKeyholder.self, .mivoLockInKeyholder) }

    func saveKeyholder(_ keyholder: LockInKeyholder?) {
        if let keyholder {
            save(keyholder, .mivoLockInKeyholder)
        } else {
            remove(.mivoLockInKeyholder)
        }
    }

    func loadLastApps() -> ScreenTimeAppSelection? { load(ScreenTimeAppSelection.self, .mivoLockInLastApps) }
    func saveLastApps(_ apps: ScreenTimeAppSelection) { save(apps, .mivoLockInLastApps) }

    func erase() {
        remove(.mivoLockIn)
        remove(.mivoLockInHistory)
        remove(.mivoLockInKeyholder)
        remove(.mivoLockInLastApps)
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
final class InMemoryLockInPersistence: LockInPersisting {
    var accountEmail: String?
    private var current: LockIn?
    private var history: [LockIn] = []
    private var keyholder: LockInKeyholder?
    private var lastApps: ScreenTimeAppSelection?

    init() {}

    func loadCurrent() -> LockIn? { current }
    func saveCurrent(_ lock: LockIn?) { current = lock }
    func loadHistory() -> [LockIn] { history }
    func saveHistory(_ history: [LockIn]) { self.history = history }
    func loadKeyholder() -> LockInKeyholder? { keyholder }
    func saveKeyholder(_ keyholder: LockInKeyholder?) { self.keyholder = keyholder }
    func loadLastApps() -> ScreenTimeAppSelection? { lastApps }
    func saveLastApps(_ apps: ScreenTimeAppSelection) { lastApps = apps }
    func erase() { current = nil; history = []; keyholder = nil; lastApps = nil }
}
