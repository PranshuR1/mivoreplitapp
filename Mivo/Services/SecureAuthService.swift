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
    var emailVerified: Bool?
    var onboardingProfile: OnboardingProfile?
}

struct TwoFactorChallenge: Identifiable, Codable, Hashable {
    enum Purpose: String, Codable, Hashable {
        case login
        case registration
        case passwordReset

        var emailSubject: String {
            switch self {
            case .login: return "Your Mivo sign-in code"
            case .registration: return "Verify your Mivo account"
            case .passwordReset: return "Reset your Mivo password"
            }
        }
    }

    let id: String
    let email: String
    let purpose: Purpose
    let codeHash: String
    let salt: String
    let expiresAt: Date

    func verifies(_ code: String) -> Bool {
        guard Date() < expiresAt else { return false }
        return SecureAuthService.hashCode(code, saltHex: salt) == codeHash
    }
}

enum SecureAuthService {
    private static let keychainService = "app.mivo.auth"
    private static let userAccount = "primary-user"
    private static let passwordIterations = 120_000

    static func loadRecord() -> SecureAuthRecord? {
        guard let data = KeychainStore.read(service: keychainService, account: userAccount) else {
            return migrateLegacyCredentialsIfNeeded()
        }
        return try? JSONDecoder().decode(SecureAuthRecord.self, from: data)
    }

    static func saveRecord(_ record: SecureAuthRecord) throws {
        let data = try JSONEncoder().encode(record)
        try KeychainStore.save(data, service: keychainService, account: userAccount)
    }

    static func deleteRecord() {
        KeychainStore.delete(service: keychainService, account: userAccount)
    }

    static func createRecord(email: String, password: String, name: String) throws -> SecureAuthRecord {
        let salt = randomBytes(count: 32)
        let record = SecureAuthRecord(
            email: email,
            name: name,
            createdAt: ISO8601DateFormatter().string(from: Date()),
            passwordHash: hashPassword(password, salt: salt, iterations: passwordIterations),
            passwordSalt: salt.hexString,
            passwordIterations: passwordIterations,
            emailVerified: false
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

    static func makeChallenge(email: String, purpose: TwoFactorChallenge.Purpose) -> (challenge: TwoFactorChallenge, code: String) {
        let code = String(format: "%06d", Int.random(in: 0...999_999))
        let salt = randomBytes(count: 16).hexString
        let challenge = TwoFactorChallenge(
            id: UUID().uuidString,
            email: email,
            purpose: purpose,
            codeHash: hashCode(code, saltHex: salt),
            salt: salt,
            expiresAt: Date().addingTimeInterval(10 * 60)
        )
        return (challenge, code)
    }

    static func hashCode(_ code: String, saltHex: String) -> String {
        let salt = Data(hexString: saltHex) ?? Data()
        var data = Data()
        data.append(salt)
        data.append(Data(code.trimmingCharacters(in: .whitespacesAndNewlines).utf8))
        return SHA256.hash(data: data).hexString
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
            emailVerified: true,
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
