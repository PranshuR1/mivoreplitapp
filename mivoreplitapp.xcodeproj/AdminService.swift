import Foundation
import CryptoKit
import Security

enum AdminService {
    private static let keychainService = "app.mivo.admin"
    private static let adminAccount = "admin-account"
    private static let sessionKey = "admin-session"
    private static let passwordIterations = 120_000
    
    // MARK: - Admin Account Management
    
    /// Initialize the admin account with the specified credentials
    static func initializeAdmin(email: String, password: String) throws {
        // Check if admin already exists
        if loadAdminAccount() != nil {
            throw AdminError.alreadyInitialized
        }
        
        let salt = randomBytes(count: 32)
        let admin = AdminAccount(
            email: email,
            passwordHash: hashPassword(password, salt: salt, iterations: passwordIterations),
            passwordSalt: salt.hexString,
            createdAt: ISO8601DateFormatter().string(from: Date())
        )
        
        try saveAdminAccount(admin)
    }
    
    /// Authenticate admin and create session
    static func loginAdmin(email: String, password: String) throws -> Bool {
        guard var admin = loadAdminAccount() else {
            throw AdminError.notInitialized
        }
        
        guard admin.email == email else {
            throw AdminError.invalidCredentials
        }
        
        guard let salt = Data(hexString: admin.passwordSalt) else {
            throw AdminError.invalidCredentials
        }
        
        let hash = hashPassword(password, salt: salt, iterations: passwordIterations)
        guard constantTimeEquals(hash, admin.passwordHash) else {
            throw AdminError.invalidCredentials
        }
        
        // Update last login
        admin.lastLoginAt = ISO8601DateFormatter().string(from: Date())
        try? saveAdminAccount(admin)
        
        // Create session
        StorageService.save("admin-active", forKey: .adminSession)
        
        return true
    }
    
    /// Check if admin is currently logged in
    static func isAdminAuthenticated() -> Bool {
        return StorageService.exists(forKey: .adminSession)
    }
    
    /// Log out admin
    static func logoutAdmin() {
        StorageService.remove(forKey: .adminSession)
    }
    
    /// Check if admin account exists
    static func adminExists() -> Bool {
        return loadAdminAccount() != nil
    }
    
    // MARK: - User Management
    
    /// Get all user accounts
    static func getAllUsers() throws -> [UserAccountInfo] {
        guard isAdminAuthenticated() else {
            throw AdminError.notAuthorized
        }
        
        var users: [UserAccountInfo] = []
        
        // Load all stored auth records from keychain
        // Since we use a single keychain service, we'll iterate through UserDefaults
        // to find all user data
        
        // Get the primary user if exists
        if let record = SecureAuthService.loadRecord() {
            let sessions = StorageService.load([Session].self, forKey: .sessions) ?? []
            let truthChecks = StorageService.load([TruthCheckGuess].self, forKey: .truthChecks) ?? []
            
            let userSessions = sessions.filter { _ in true } // All sessions for now
            let totalMinutes = userSessions.reduce(0) { $0 + $1.actualDuration }
            let lastSession = userSessions.sorted(by: { $0.startTime > $1.startTime }).first
            
            let userInfo = UserAccountInfo(
                email: record.email,
                name: record.name,
                createdAt: record.createdAt,
                onboardingProfile: record.onboardingProfile,
                sessionCount: userSessions.count,
                totalMinutes: totalMinutes,
                lastSessionDate: lastSession?.date,
                truthCheckCount: truthChecks.count
            )
            users.append(userInfo)
        }
        
        // Load additional users from a separate storage if you support multiple users
        if let additionalUsers = loadAllUserRecords() {
            users.append(contentsOf: additionalUsers)
        }
        
        return users
    }
    
    /// Delete a specific user
    static func deleteUser(email: String) throws {
        guard isAdminAuthenticated() else {
            throw AdminError.notAuthorized
        }
        
        // If this is the primary user, delete their data
        if let record = SecureAuthService.loadRecord(), record.email == email {
            SecureAuthService.deleteRecord()
            StorageService.remove(forKey: .user)
            StorageService.remove(forKey: .sessions)
            StorageService.remove(forKey: .truthChecks)
            StorageService.remove(forKey: .settings)
            StorageService.remove(forKey: .onboardingProfile)
            StorageService.remove(forKey: .authSession)
            StorageService.remove(forKey: .rememberedEmail)
            StorageService.remove(forKey: .pendingSessionFeedback)
            StorageService.remove(forKey: .aiDataset)
        }
        
        // Delete from additional users storage if needed
        deleteUserRecord(email: email)
    }
    
    /// Get detailed user information
    static func getUserDetails(email: String) throws -> (user: UserAccountInfo, sessions: [Session], truthChecks: [TruthCheckGuess]) {
        guard isAdminAuthenticated() else {
            throw AdminError.notAuthorized
        }
        
        guard let record = SecureAuthService.loadRecord(), record.email == email else {
            throw AppError.noAccount
        }
        
        let sessions = StorageService.load([Session].self, forKey: .sessions) ?? []
        let truthChecks = StorageService.load([TruthCheckGuess].self, forKey: .truthChecks) ?? []
        
        let totalMinutes = sessions.reduce(0) { $0 + $1.actualDuration }
        let lastSession = sessions.sorted(by: { $0.startTime > $1.startTime }).first
        
        let userInfo = UserAccountInfo(
            email: record.email,
            name: record.name,
            createdAt: record.createdAt,
            onboardingProfile: record.onboardingProfile,
            sessionCount: sessions.count,
            totalMinutes: totalMinutes,
            lastSessionDate: lastSession?.date,
            truthCheckCount: truthChecks.count
        )
        
        return (userInfo, sessions, truthChecks)
    }
    
    // MARK: - Private Helpers
    
    private static func loadAdminAccount() -> AdminAccount? {
        guard let data = KeychainStore.read(service: keychainService, account: adminAccount) else {
            return nil
        }
        return try? JSONDecoder().decode(AdminAccount.self, from: data)
    }
    
    private static func saveAdminAccount(_ admin: AdminAccount) throws {
        let data = try JSONEncoder().encode(admin)
        try KeychainStore.save(data, service: keychainService, account: adminAccount)
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
    
    // MARK: - Multi-user Storage (for future expansion)
    
    private static let allUsersKey = "app.mivo.allUsers"
    
    private static func loadAllUserRecords() -> [UserAccountInfo]? {
        guard let data = UserDefaults.standard.data(forKey: allUsersKey) else {
            return nil
        }
        return try? JSONDecoder().decode([UserAccountInfo].self, from: data)
    }
    
    private static func saveAllUserRecords(_ users: [UserAccountInfo]) {
        guard let data = try? JSONEncoder().encode(users) else { return }
        UserDefaults.standard.set(data, forKey: allUsersKey)
    }
    
    private static func deleteUserRecord(email: String) {
        guard var users = loadAllUserRecords() else { return }
        users.removeAll { $0.email == email }
        saveAllUserRecords(users)
    }
}

// MARK: - Keychain Store (if not already defined)

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

// MARK: - Data Extensions

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
