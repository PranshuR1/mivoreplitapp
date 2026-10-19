import CryptoKit
import Foundation
import Security

struct SecureAuthRecord: Codable {
    var email: String
    var name: String
    var createdAt: String
    var passwordHash: String
    var passwordSalt: String
    var passwordIterations: Int
    var isAdmin: Bool?
    var accountRole: String? = nil
    var adminToken: String?
    var onboardingProfile: OnboardingProfile?
    var remoteUserId: String?
    var remoteAccessToken: String?
    var remoteRefreshToken: String?
}

struct DeviceBindingRecord: Codable {
    let installationID: String
    let userID: String
    let email: String
    var failedAccountAttempts: Int?
}

enum DeviceBindingService {
    private static let keychainService = "app.mivo.device-binding"
    private static let installationAccount = "installation-id"
    private static let bindingAccount = "bound-account"

    /// Dev/test installations permanently exempted from the one-device-per-account
    /// restriction — neither the local Keychain binding below nor the server-side
    /// `RemoteAuthService.claimDevice` row is ever written or enforced for these, so
    /// signing into any account from one of these devices never binds it.
    static let exemptInstallationIDs: Set<String> = [
        "b37a76e0-6e80-4c90-b702-689613c5d04e"
    ]

    static func isExemptInstallation(_ installationID: String) -> Bool {
        exemptInstallationIDs.contains(installationID)
    }

    /// Checked ahead of `loadBinding()` — an exempt device must never read
    /// back as bound, even if a binding record was written to the Keychain
    /// before this device's ID was added to `exemptInstallationIDs` (or by
    /// a build that predates the exemption entirely). Without this check
    /// here specifically, `LoginView`'s "New to Mivo? Create an account"
    /// link would still hide on this device despite `bind()`/`assertAllows`
    /// already refusing to write new bindings for it.
    static var boundEmail: String? {
        guard let id = try? installationID(), !isExemptInstallation(id) else { return nil }
        return loadBinding()?.email
    }

    static var boundEmailHint: String? {
        guard let id = try? installationID(), !isExemptInstallation(id) else { return nil }
        return loadBinding().map { emailHint(for: $0.email, attempt: 1) }
    }

    static func installationID() throws -> String {
        if let data = KeychainStore.read(service: keychainService, account: installationAccount),
           let value = String(data: data, encoding: .utf8),
           !value.isEmpty {
            if isExemptInstallation(value) { purgeLocalBindingIfPresent() }
            return value
        }

        let value = UUID().uuidString.lowercased()
        guard let data = value.data(using: .utf8) else { throw AppError.secureStorageFailed }
        try KeychainStore.save(data, service: keychainService, account: installationAccount)
        return value
    }

    /// Belt-and-suspenders alongside the `boundEmail`/`boundEmailHint`
    /// checks above: actually clears any stale local binding for an exempt
    /// device rather than just hiding it, so `assertAllows`/`bind` never
    /// see leftover state from before this device was exempted either.
    private static func purgeLocalBindingIfPresent() {
        guard loadBinding() != nil else { return }
        KeychainStore.delete(service: keychainService, account: bindingAccount)
    }

    static func assertAllows(email: String) throws {
        if let id = try? installationID(), isExemptInstallation(id) { return }
        guard var binding = loadBinding() else { return }
        let normalizedEmail = normalizeEmail(email)
        guard binding.email == normalizedEmail else {
            let attempts = min((binding.failedAccountAttempts ?? 0) + 1, 3)
            binding.failedAccountAttempts = attempts
            try saveBinding(binding)
            throw AppError.deviceBoundToAnotherAccount(hint: emailHint(for: binding.email, attempt: attempts))
        }

        if binding.failedAccountAttempts != nil {
            binding.failedAccountAttempts = nil
            try saveBinding(binding)
        }
    }

    static func bind(userID: String, email: String, replacingLocalBinding: Bool = false) throws {
        let id = try installationID()
        guard !isExemptInstallation(id) else { return }
        let normalizedEmail = normalizeEmail(email)
        if !replacingLocalBinding {
            try assertAllows(email: normalizedEmail)
        }
        let record = DeviceBindingRecord(
            installationID: id,
            userID: userID,
            email: normalizedEmail,
            failedAccountAttempts: nil
        )
        try saveBinding(record)
    }

    static func releaseIfBound(email: String) {
        guard loadBinding()?.email == normalizeEmail(email) else { return }
        KeychainStore.delete(service: keychainService, account: bindingAccount)
    }

    private static func loadBinding() -> DeviceBindingRecord? {
        guard let data = KeychainStore.read(service: keychainService, account: bindingAccount) else {
            return nil
        }
        return try? JSONDecoder().decode(DeviceBindingRecord.self, from: data)
    }

    private static func saveBinding(_ binding: DeviceBindingRecord) throws {
        let data = try JSONEncoder().encode(binding)
        try KeychainStore.save(data, service: keychainService, account: bindingAccount)
    }

    private static func emailHint(for email: String, attempt: Int) -> String {
        guard attempt < 3 else { return email }
        let parts = email.split(separator: "@", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return masked(parts.first ?? email, visible: attempt) }

        let localVisible = attempt == 1 ? 1 : min(3, parts[0].count)
        let local = masked(parts[0], visible: localVisible)
        if attempt == 2 {
            return "\(local)@\(parts[1])"
        }

        let domainParts = parts[1].split(separator: ".", maxSplits: 1).map(String.init)
        let domainName = masked(domainParts[0], visible: 1)
        let suffix = domainParts.count == 2 ? ".\(domainParts[1])" : ""
        return "\(local)@\(domainName)\(suffix)"
    }

    private static func masked(_ value: String, visible: Int) -> String {
        let visibleCount = min(max(visible, 1), value.count)
        let prefix = value.prefix(visibleCount)
        let maskCount = max(value.count - visibleCount, 3)
        return String(prefix) + String(repeating: "*", count: maskCount)
    }

    private static func normalizeEmail(_ email: String) -> String {
        email.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum SecureAuthService {
    private static let keychainService = "app.mivo.auth"
    private static let legacyUserAccount = "primary-user"
    private static let userAccountPrefix = "user-"
    private static let passwordIterations = 120_000

    static func loadRecord() -> SecureAuthRecord? {
        if let email = StorageService.load(String.self, forKey: .rememberedEmail),
           let record = loadRecord(email: email) {
            return record
        }

        guard let data = KeychainStore.read(service: keychainService, account: legacyUserAccount),
              let record = try? JSONDecoder().decode(SecureAuthRecord.self, from: data) else {
            return migrateLegacyCredentialsIfNeeded()
        }
        try? saveRecord(record)
        return record
    }

    static func loadRecord(email: String) -> SecureAuthRecord? {
        let normalized = normalizeEmail(email)
        if let data = KeychainStore.read(service: keychainService, account: accountKey(for: normalized)),
           let record = try? JSONDecoder().decode(SecureAuthRecord.self, from: data) {
            return record
        }

        guard let data = KeychainStore.read(service: keychainService, account: legacyUserAccount),
              let legacyRecord = try? JSONDecoder().decode(SecureAuthRecord.self, from: data),
              normalizeEmail(legacyRecord.email) == normalized else {
            return nil
        }
        try? saveRecord(legacyRecord)
        return legacyRecord
    }

    static func saveRecord(_ record: SecureAuthRecord) throws {
        var normalizedRecord = record
        normalizedRecord.email = normalizeEmail(record.email)
        let data = try JSONEncoder().encode(normalizedRecord)
        try KeychainStore.save(data, service: keychainService, account: accountKey(for: normalizedRecord.email))
    }

    static func deleteRecord() {
        if let email = StorageService.load(String.self, forKey: .rememberedEmail) {
            deleteRecord(email: email)
        }
        KeychainStore.delete(service: keychainService, account: legacyUserAccount)
    }

    static func deleteRecord(email: String) {
        KeychainStore.delete(service: keychainService, account: accountKey(for: normalizeEmail(email)))
    }

    static func deleteAllRecords() {
        KeychainStore.deleteAll(service: keychainService)
    }

    static func createRecord(email: String, password: String, name: String) throws -> SecureAuthRecord {
        let salt = randomBytes(count: 32)
        let record = SecureAuthRecord(
            email: normalizeEmail(email),
            name: name,
            createdAt: ISO8601DateFormatter().string(from: Date()),
            passwordHash: hashPassword(password, salt: salt, iterations: passwordIterations),
            passwordSalt: salt.hexString,
            passwordIterations: passwordIterations
        )
        try saveRecord(record)
        return record
    }

    static func verifyPassword(_ password: String, for record: SecureAuthRecord) -> Bool {
        if record.passwordIterations == 0 {
            return constantTimeEquals(simpleHash(password), record.passwordHash)
        }

        guard let salt = Data(hexString: record.passwordSalt) else { return false }
        let hash = hashPassword(password, salt: salt, iterations: record.passwordIterations)
        return constantTimeEquals(hash, record.passwordHash)
    }

    static func updatePassword(_ password: String, for record: SecureAuthRecord) throws -> SecureAuthRecord {
        let salt = randomBytes(count: 32)
        var updated = record
        updated.passwordSalt = salt.hexString
        updated.passwordIterations = passwordIterations
        updated.passwordHash = hashPassword(password, salt: salt, iterations: passwordIterations)
        try saveRecord(updated)
        return updated
    }

    private static func accountKey(for email: String) -> String {
        "\(userAccountPrefix)\(simpleHash(normalizeEmail(email)))"
    }

    private static func normalizeEmail(_ email: String) -> String {
        email.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func hashPassword(_ password: String, salt: Data, iterations: Int) -> String {
        var digestInput = Data()
        digestInput.append(salt)
        digestInput.append(Data(password.utf8))

        var digest = Data(SHA256.hash(data: digestInput))
        for _ in 1..<iterations {
            var round = Data()
            round.append(salt)
            round.append(digest)
            round.append(Data(password.utf8))
            digest = Data(SHA256.hash(data: round))
        }
        return digest.hexString
    }

    private static func randomBytes(count: Int) -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        let status = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        if status != errSecSuccess {
            for index in bytes.indices {
                bytes[index] = UInt8.random(in: UInt8.min...UInt8.max)
            }
        }
        return Data(bytes)
    }

    private static func constantTimeEquals(_ lhs: String, _ rhs: String) -> Bool {
        let left = Array(lhs.utf8)
        let right = Array(rhs.utf8)
        guard left.count == right.count else { return false }

        var difference: UInt8 = 0
        for index in left.indices {
            difference |= left[index] ^ right[index]
        }
        return difference == 0
    }

    private static func migrateLegacyCredentialsIfNeeded() -> SecureAuthRecord? {
        guard let legacyUser = StorageService.load(UserProfile.self, forKey: .user),
              let legacyCredentials = StorageService.load(StoredCredentials.self, forKey: .credentials) else {
            return nil
        }

        let record = SecureAuthRecord(
            email: legacyCredentials.email,
            name: legacyUser.name,
            createdAt: legacyUser.createdAt,
            passwordHash: legacyCredentials.passwordHash,
            passwordSalt: "legacy",
            passwordIterations: 0,
            onboardingProfile: legacyUser.onboardingProfile
        )
        try? saveRecord(record)
        return record
    }
}

private enum KeychainStore {
    static func save(_ data: Data, service: String, account: String) throws {
        let query = baseQuery(service: service, account: account)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var addQuery = query
            attributes.forEach { addQuery[$0.key] = $0.value }
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw AppError.secureStorageFailed }
        } else if status != errSecSuccess {
            throw AppError.secureStorageFailed
        }
    }

    static func read(service: String, account: String) -> Data? {
        var query = baseQuery(service: service, account: account)
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecReturnData as String] = true

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else { return nil }
        return result as? Data
    }

    static func delete(service: String, account: String) {
        SecItemDelete(baseQuery(service: service, account: account) as CFDictionary)
    }

    static func deleteAll(service: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service
        ]
        SecItemDelete(query as CFDictionary)
    }

    private static func baseQuery(service: String, account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}

private extension Data {
    init?(hexString: String) {
        guard hexString.count.isMultiple(of: 2) else { return nil }
        var bytes: [UInt8] = []
        var index = hexString.startIndex

        while index < hexString.endIndex {
            let next = hexString.index(index, offsetBy: 2)
            guard let byte = UInt8(hexString[index..<next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        self = Data(bytes)
    }

    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}

private extension SHA256.Digest {
    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}
