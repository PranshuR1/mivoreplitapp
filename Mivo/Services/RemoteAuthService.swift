import Foundation

struct RemoteAuthUser: Codable {
    let email: String
    let name: String
    let createdAt: String
    let onboardingProfile: OnboardingProfile?
    let isAdmin: Bool?
    let adminToken: String?
}

struct AdminUser: Codable, Identifiable {
    var id: String { email }
    let email: String
    let name: String
    let createdAt: String
    let onboardingProfile: OnboardingProfile?
    let isAdmin: Bool?
    let role: String?
    let lastLoginAt: String?
    let updatedAt: String?
}

struct PendingRegistration {
    let email: String
    let password: String
    let name: String
}

enum RemoteAuthService {
    private struct AuthRequest: Codable {
        let email: String
        let password: String?
        let name: String?
        let onboardingProfile: OnboardingProfile?
    }

    private struct AdminRequest: Codable {
        let adminToken: String
        let targetEmail: String?
    }

    private struct AuthResponse: Codable {
        let ok: Bool?
        let exists: Bool?
        let user: RemoteAuthUser?
        let adminToken: String?
        let users: [AdminUser]?
        let error: String?
    }

    static var isConfigured: Bool {
        baseURL != nil
    }

    private static var baseURL: URL? {
        if let raw = Bundle.main.object(forInfoDictionaryKey: "MIVO_AUTH_API_URL") as? String,
           let url = configuredURL(from: raw) {
            return url
        }

        return nil
    }

    private static func configuredURL(from raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("$("), !trimmed.hasSuffix(")") else { return nil }
        return URL(string: trimmed)
    }

    static func register(email: String, password: String, name: String, onboardingProfile: OnboardingProfile?) async throws -> RemoteAuthUser {
        try await request(
            path: "/auth/register",
            body: AuthRequest(email: email, password: password, name: name, onboardingProfile: onboardingProfile)
        )
    }

    static func login(email: String, password: String) async throws -> RemoteAuthUser {
        let response: AuthResponse = try await rawRequest(
            path: "/auth/login",
            body: AuthRequest(email: email, password: password, name: nil, onboardingProfile: nil)
        )
        guard let user = response.user else { throw AppError.accountDataMissing }
        return RemoteAuthUser(
            email: user.email,
            name: user.name,
            createdAt: user.createdAt,
            onboardingProfile: user.onboardingProfile,
            isAdmin: user.isAdmin,
            adminToken: response.adminToken
        )
    }

    static func socialLogin(_ credential: SocialCredential) async throws -> RemoteAuthUser {
        struct SocialRequest: Codable {
            let provider: String
            let idToken: String
            let name: String?
        }
        let response: AuthResponse = try await rawRequest(
            path: "/auth/social",
            body: SocialRequest(provider: credential.provider, idToken: credential.idToken, name: credential.name)
        )
        guard let user = response.user else { throw AppError.accountDataMissing }
        return RemoteAuthUser(
            email: user.email,
            name: user.name,
            createdAt: user.createdAt,
            onboardingProfile: user.onboardingProfile,
            isAdmin: user.isAdmin,
            adminToken: response.adminToken
        )
    }

    static func accountExists(email: String) async throws -> Bool {
        let response: AuthResponse = try await rawRequest(
            path: "/auth/exists",
            body: AuthRequest(email: email, password: nil, name: nil, onboardingProfile: nil)
        )
        return response.exists == true
    }

    static func resetPassword(email: String, newPassword: String) async throws {
        let _: AuthResponse = try await rawRequest(
            path: "/auth/reset-password",
            body: AuthRequest(email: email, password: newPassword, name: nil, onboardingProfile: nil)
        )
    }

    static func saveProfile(email: String, onboardingProfile: OnboardingProfile) async {
        let _: AuthResponse? = try? await rawRequest(
            path: "/auth/profile",
            body: AuthRequest(email: email, password: nil, name: nil, onboardingProfile: onboardingProfile)
        )
    }

    static func adminUsers(adminToken: String) async throws -> [AdminUser] {
        let response: AuthResponse = try await rawRequest(
            path: "/auth/admin/users",
            body: AdminRequest(adminToken: adminToken, targetEmail: nil)
        )
        return response.users ?? []
    }

    static func adminUser(adminToken: String, email: String) async throws -> AdminUser {
        let response: AuthResponse = try await rawRequest(
            path: "/auth/admin/user",
            body: AdminRequest(adminToken: adminToken, targetEmail: email)
        )
        guard let user = response.user else { throw AppError.noAccount }
        return AdminUser(
            email: user.email,
            name: user.name,
            createdAt: user.createdAt,
            onboardingProfile: user.onboardingProfile,
            isAdmin: user.isAdmin,
            role: nil,
            lastLoginAt: nil,
            updatedAt: nil
        )
    }

    static func adminDeleteUser(adminToken: String, email: String) async throws {
        let _: AuthResponse = try await rawRequest(
            path: "/auth/admin/delete-user",
            body: AdminRequest(adminToken: adminToken, targetEmail: email)
        )
    }

    private static func request(path: String, body: AuthRequest) async throws -> RemoteAuthUser {
        let response: AuthResponse = try await rawRequest(path: path, body: body)
        guard let user = response.user else { throw AppError.accountDataMissing }
        return user
    }

    private static func rawRequest<Response: Decodable, Body: Encodable>(path: String, body: Body) async throws -> Response {
        guard let baseURL else { throw AppError.remoteAuthUnavailable }
        let url = baseURL.appendingPathComponent(path.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 12
        request.httpBody = try JSONEncoder().encode(body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw AppError.remoteAuthUnavailable
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 500
        let decoded = try? JSONDecoder().decode(AuthResponse.self, from: data)

        guard (200..<300).contains(status) else {
            switch decoded?.error {
            case "emailAlreadyExists": throw AppError.emailAlreadyExists
            case "invalidCredentials": throw AppError.invalidCredentials
            case "noAccount": throw AppError.noAccount
            case "weakPassword": throw AppError.weakPassword
            case "passwordResetUnavailable": throw AppError.passwordResetUnavailable
            case "invalidSocialToken", "emailNotVerified": throw AppError.socialSignInFailed
            case "socialNotConfigured": throw AppError.socialSignInUnavailable
            case "adminRequired", "cannotDeleteAdmin": throw AppError.adminRequired
            default: throw AppError.remoteAuthUnavailable
            }
        }

        guard let typed = try? JSONDecoder().decode(Response.self, from: data) else {
            throw AppError.accountDataMissing
        }
        return typed
    }
}
