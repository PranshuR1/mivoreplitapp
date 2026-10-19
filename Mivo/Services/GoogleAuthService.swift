import Foundation
#if canImport(GoogleSignIn)
import GoogleSignIn
import UIKit
#endif

/// "Sign in with Google" for the Mivo account itself — distinct from
/// `YouTubeFocusService` in MivoClearService.swift, which requests
/// read-only YouTube API access as an *additional* scope on an account
/// that's already signed in some other way. This one only needs the
/// default profile/email scope GIDSignIn requests, exchanged with
/// Supabase's native `id_token` grant (see
/// `RemoteAuthService.loginWithGoogle`) rather than a browser redirect.
/// Thrown when the user dismisses the Google sheet; callers should treat it as a no-op.
struct GoogleSignInCancelled: Error {}

enum GoogleAuthService {
    static var isConfigured: Bool {
        clientID != nil
    }

    private static var clientID: String? {
        for key in ["MIVO_GOOGLE_CLIENT_ID", "GIDClientID"] {
            guard let raw = Bundle.main.object(forInfoDictionaryKey: key) as? String else { continue }
            let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty,
               !value.contains("$("),
               !value.localizedCaseInsensitiveContains("not-configured") {
                return value
            }
        }
        return nil
    }

    @MainActor
    static func signIn() async throws -> String {
        #if canImport(GoogleSignIn)
        guard let clientID else { throw AppError.remoteAuthUnavailable }
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
        guard let presenter = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?.rootViewController else {
            throw AppError.remoteAuthUnavailable
        }
        return try await withCheckedThrowingContinuation { continuation in
            GIDSignIn.sharedInstance.signIn(withPresenting: presenter) { result, error in
                if let error {
                    let nsError = error as NSError
                    // -5 is GIDSignInError.canceled: the user closed the Google sheet. Not a failure.
                    if nsError.domain == "com.google.GIDSignIn", nsError.code == -5 {
                        continuation.resume(throwing: GoogleSignInCancelled())
                    } else {
                        continuation.resume(throwing: AppError.googleSignInFailed("Google sign-in could not finish: \(nsError.localizedDescription) (code \(nsError.code))."))
                    }
                } else if let idToken = result?.user.idToken?.tokenString {
                    continuation.resume(returning: idToken)
                } else {
                    continuation.resume(throwing: AppError.accountDataMissing)
                }
            }
        }
        #else
        throw AppError.remoteAuthUnavailable
        #endif
    }
}
