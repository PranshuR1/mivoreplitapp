import Foundation

// MARK: - Admin Models

struct AdminAccount: Codable {
    let email: String
    let passwordHash: String
    let passwordSalt: String
    let createdAt: String
    var lastLoginAt: String?
}

struct UserAccountInfo: Codable, Identifiable {
    var id: String { email }
    let email: String
    let name: String
    let createdAt: String
    var onboardingProfile: OnboardingProfile?
    var sessionCount: Int = 0
    var totalMinutes: Int = 0
    var lastSessionDate: String?
    var truthCheckCount: Int = 0
}

enum AdminError: LocalizedError {
    case notAuthorized
    case invalidCredentials
    case alreadyInitialized
    case notInitialized
    
    var errorDescription: String? {
        switch self {
        case .notAuthorized:
            return "You are not authorized to access admin features"
        case .invalidCredentials:
            return "Invalid admin credentials"
        case .alreadyInitialized:
            return "Admin account already exists"
        case .notInitialized:
            return "Admin account not initialized"
        }
    }
}
