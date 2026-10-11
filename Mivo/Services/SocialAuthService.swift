import AuthenticationServices
import CryptoKit
import Foundation
import UIKit

struct SocialCredential {
    let provider: String
    let idToken: String
    let name: String?
}

enum SocialAuthError: LocalizedError {
    case cancelled
    case googleNotConfigured
    case failed

    var errorDescription: String? {
        switch self {
        case .cancelled: return nil
        case .googleNotConfigured: return "Google sign-in isn't set up yet. Add MIVO_GOOGLE_CLIENT_ID to the app configuration."
        case .failed: return "Sign-in failed. Please try again."
        }
    }
}

@MainActor
final class SocialAuthService: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding, ASWebAuthenticationPresentationContextProviding {
    static let shared = SocialAuthService()

    private var appleContinuation: CheckedContinuation<SocialCredential, Error>?
    private var webSession: ASWebAuthenticationSession?

    static var googleClientID: String? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "MIVO_GOOGLE_CLIENT_ID") as? String else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasSuffix(".apps.googleusercontent.com") else { return nil }
        return trimmed
    }

    // MARK: Apple

    func signInWithApple() async throws -> SocialCredential {
        try await withCheckedThrowingContinuation { continuation in
            appleContinuation = continuation
            let request = ASAuthorizationAppleIDProvider().createRequest()
            request.requestedScopes = [.fullName, .email]
            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.presentationContextProvider = self
            controller.performRequests()
        }
    }

    nonisolated func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        Task { @MainActor in
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let token = String(data: tokenData, encoding: .utf8) else {
                appleContinuation?.resume(throwing: SocialAuthError.failed)
                appleContinuation = nil
                return
            }
            let name = [credential.fullName?.givenName, credential.fullName?.familyName]
                .compactMap { $0 }.joined(separator: " ")
            appleContinuation?.resume(returning: SocialCredential(provider: "apple", idToken: token, name: name.isEmpty ? nil : name))
            appleContinuation = nil
        }
    }

    nonisolated func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        Task { @MainActor in
            let cancelled = (error as? ASAuthorizationError)?.code == .canceled
            appleContinuation?.resume(throwing: cancelled ? SocialAuthError.cancelled : SocialAuthError.failed)
            appleContinuation = nil
        }
    }

    // MARK: Google (OAuth code + PKCE, no SDK)

    func signInWithGoogle() async throws -> SocialCredential {
        guard let clientID = Self.googleClientID else { throw SocialAuthError.googleNotConfigured }
        let scheme = clientID.split(separator: ".").reversed().joined(separator: ".")
        let redirect = "\(scheme):/oauth2redirect"
        let verifier = Self.randomString(byteCount: 48)
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncoded
        let state = Self.randomString(byteCount: 16)

        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        components.queryItems = [
            .init(name: "client_id", value: clientID),
            .init(name: "redirect_uri", value: redirect),
            .init(name: "response_type", value: "code"),
            .init(name: "scope", value: "openid email profile"),
            .init(name: "code_challenge", value: challenge),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "state", value: state),
            .init(name: "prompt", value: "select_account"),
        ]

        let callback: URL = try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: components.url!, callbackURLScheme: scheme) { url, error in
                if let url {
                    continuation.resume(returning: url)
                } else if (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin {
                    continuation.resume(throwing: SocialAuthError.cancelled)
                } else {
                    continuation.resume(throwing: SocialAuthError.failed)
                }
            }
            session.presentationContextProvider = self
            webSession = session
            if !session.start() { continuation.resume(throwing: SocialAuthError.failed) }
        }
        webSession = nil

        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        guard items.first(where: { $0.name == "state" })?.value == state,
              let code = items.first(where: { $0.name == "code" })?.value else {
            throw SocialAuthError.failed
        }

        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var form = URLComponents()
        form.queryItems = [
            .init(name: "client_id", value: clientID),
            .init(name: "code", value: code),
            .init(name: "code_verifier", value: verifier),
            .init(name: "grant_type", value: "authorization_code"),
            .init(name: "redirect_uri", value: redirect),
        ]
        request.httpBody = form.percentEncodedQuery?.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let idToken = json["id_token"] as? String else {
            throw SocialAuthError.failed
        }
        return SocialCredential(provider: "google", idToken: idToken, name: nil)
    }

    // MARK: Presentation

    nonisolated func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor { Self.anchor() }
    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor { Self.anchor() }

    private nonisolated static func anchor() -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
            return scene?.keyWindow ?? scene?.windows.first ?? ASPresentationAnchor()
        }
    }

    private static func randomString(byteCount: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        _ = SecRandomCopyBytes(kSecRandomDefault, byteCount, &bytes)
        return Data(bytes).base64URLEncoded
    }
}

private extension Data {
    var base64URLEncoded: String {
        base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
}
