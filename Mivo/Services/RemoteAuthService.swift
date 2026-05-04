import Foundation

struct RemoteAuthUser: Codable {
    let email: String
    let name: String
    let createdAt: String
    let onboardingProfile: OnboardingProfile?
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

    private struct AuthResponse: Codable {
        let ok: Bool?
        let exists: Bool?
        let user: RemoteAuthUser?
        let error: String?
    }

    static var isConfigured: Bool {
        baseURL != nil
    }

    private static var baseURL: URL? {
        if let raw = Bundle.main.object(forInfoDictionaryKey: "MIVO_AUTH_API_URL") as? String,
           !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return URL(string: raw.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        return nil
    }

    static func register(email: String, password: String, name: String, onboardingProfile: OnboardingProfile?) async throws -> RemoteAuthUser {
        try await request(
            path: "/auth/register",
            body: AuthRequest(email: email, password: password, name: name, onboardingProfile: onboardingProfile)
        )
    }

    static func login(email: String, password: String) async throws -> RemoteAuthUser {
        try await request(
            path: "/auth/login",
            body: AuthRequest(email: email, password: password, name: nil, onboardingProfile: nil)
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

    private static func request(path: String, body: AuthRequest) async throws -> RemoteAuthUser {
        let response: AuthResponse = try await rawRequest(path: path, body: body)
        guard let user = response.user else { throw AppError.accountDataMissing }
        return user
    }

    private static func rawRequest<Response: Decodable>(path: String, body: AuthRequest) async throws -> Response {
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
            default: throw AppError.remoteAuthUnavailable
            }
        }

        guard let typed = try? JSONDecoder().decode(Response.self, from: data) else {
            throw AppError.accountDataMissing
        }
        return typed
    }
}
