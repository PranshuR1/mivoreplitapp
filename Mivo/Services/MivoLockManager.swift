import Foundation
import Security

/// Keeps the lock and its Screen Time passcode in the Keychain rather than in
/// UserDefaults: "Reset all data" and signing out never touch it, and with
/// `ThisDeviceOnly` it never goes into a backup, so the passcode can't be read
/// back out of one on a Mac.
enum MivoLockVault {
    private static let service = "app.mivo.lock"
    private static let lockAccount = "lock"
    private static let codeAccount = "screen-time-passcode"

    static func loadLock() -> MivoLock? {
        guard let data = read(account: lockAccount) else { return nil }
        return try? JSONDecoder().decode(MivoLock.self, from: data)
    }

    @discardableResult
    static func saveLock(_ lock: MivoLock?) -> Bool {
        guard let lock else { return delete(account: lockAccount) }
        guard let data = try? JSONEncoder().encode(lock) else { return false }
        return write(data, account: lockAccount)
    }

    static func loadCode() -> String? {
        read(account: codeAccount).flatMap { String(data: $0, encoding: .utf8) }
    }

    @discardableResult
    static func saveCode(_ code: String) -> Bool {
        write(Data(code.utf8), account: codeAccount)
    }

    @discardableResult
    static func deleteCode() -> Bool {
        delete(account: codeAccount)
    }

    private static func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    private static func read(account: String) -> Data? {
        var query = baseQuery(account: account)
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecReturnData as String] = true
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    private static func write(_ data: Data, account: String) -> Bool {
        let query = baseQuery(account: account)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var addQuery = query
            attributes.forEach { addQuery[$0.key] = $0.value }
            return SecItemAdd(addQuery as CFDictionary, nil) == errSecSuccess
        }
        return status == errSecSuccess
    }

    private static func delete(account: String) -> Bool {
        let status = SecItemDelete(baseQuery(account: account) as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}

/// The one place the lock changes. See `MivoLock` for what it holds.
@MainActor
final class MivoLockManager: ObservableObject {
    static let shared = MivoLockManager()

    enum UnlockError: LocalizedError {
        case offline
        case notOpenYet
        case couldNotSave

        var errorDescription: String? {
            switch self {
            case .offline:
                return "Mivo checks the time online so the wait can't be skipped by changing the clock. Connect to the internet and try again."
            case .notOpenYet:
                return "The wait isn't over yet."
            case .couldNotSave:
                return "Mivo couldn't save that. Try again."
            }
        }
    }

    @Published private(set) var lock: MivoLock?
    @Published private(set) var hasCode: Bool

    private init() {
        lock = MivoLockVault.loadLock()
        hasCode = MivoLockVault.loadCode() != nil
    }

    var isLocked: Bool { lock != nil }

    /// Whether the in-app off-switches are held. Read straight from the
    /// Keychain so `FamilyControlsManager` can ask from any thread.
    nonisolated static func holdsOffSwitches() -> Bool {
        MivoLockVault.loadLock() != nil
    }

    /// iOS 26.4 is the first version where the Screen Time passcode guards
    /// turning off an app's Screen Time access and deleting the app.
    nonisolated static var systemLockAvailable: Bool {
        ProcessInfo.processInfo.isOperatingSystemAtLeast(
            OperatingSystemVersion(majorVersion: 26, minorVersion: 4, patchVersion: 0)
        )
    }

    /// The code to type into Settings while setting up. The same code comes
    /// back until it is forgotten, because the person may already have typed
    /// it into Settings before leaving setup. Nil while a lock that uses the
    /// passcode is on, so setup can't be used to read it.
    func codeForSetup() -> String? {
        if let lock, lock.usesScreenTimePasscode { return nil }
        if let code = MivoLockVault.loadCode() { return code }
        let code = MivoLockCode.make()
        // Only show a code that is safely stored: showing one that isn't
        // would leave the person with a passcode nobody can give back.
        guard MivoLockVault.saveCode(code), MivoLockVault.loadCode() == code else { return nil }
        hasCode = true
        return code
    }

    /// The passcode, only once no lock is on, so it can be turned off in Settings.
    func revealedCode() -> String? {
        lock == nil ? MivoLockVault.loadCode() : nil
    }

    func forgetCode() {
        guard lock == nil else { return }
        MivoLockVault.deleteCode()
        hasCode = MivoLockVault.loadCode() != nil
    }

    /// Turns protection and opening social apps in Mivo on, then holds them.
    func startLock(delay: TimeInterval, usesScreenTimePasscode: Bool) -> Bool {
        guard lock == nil else { return false }
        if #available(iOS 16.0, *), FamilyControlsManager.shared.hasImpulseSelection() {
            FamilyControlsManager.shared.setImpulseProtectionEnabled(true)
        }
        FamilyControlsManager.shared.setInstagramWrapperEnabled(true)
        let newLock = MivoLock(
            lockedAt: Date(),
            delay: delay,
            unlockRequestedAt: nil,
            usesScreenTimePasscode: usesScreenTimePasscode
        )
        guard MivoLockVault.saveLock(newLock) else { return false }
        lock = newLock
        return true
    }

    func addScreenTimePasscode() {
        update { $0.usesScreenTimePasscode = true }
    }

    func lengthenDelay(to delay: TimeInterval) {
        update { $0.lengthenDelay(to: delay) }
    }

    func stayLocked() {
        update { $0.stayLocked() }
    }

    func requestUnlock() async throws {
        guard let now = await MivoTrustedClock.now() else { throw UnlockError.offline }
        guard update({ $0.requestUnlock(at: now) }) else { throw UnlockError.couldNotSave }
    }

    /// The only way the in-app holds lift: the server's clock has to agree
    /// the wait is over.
    func endLock() async throws {
        guard let current = lock else { return }
        guard let now = await MivoTrustedClock.now() else { throw UnlockError.offline }
        guard case .open = current.phase(at: now) else { throw UnlockError.notOpenYet }
        guard MivoLockVault.saveLock(nil) else { throw UnlockError.couldNotSave }
        lock = nil
    }

    @discardableResult
    private func update(_ change: (inout MivoLock) -> Void) -> Bool {
        guard var current = lock else { return false }
        change(&current)
        guard MivoLockVault.saveLock(current) else { return false }
        lock = current
        return true
    }
}
