import SwiftUI
import AuthenticationServices
import CryptoKit
import Security

struct LoginView: View {
    @EnvironmentObject var appVM: AppViewModel
    @Environment(\.colorScheme) private var colorScheme
    @State private var email = ""
    @State private var password = ""
    @State private var showPassword = false
    @State private var rememberMe = true
    @State private var loading = false
    @State private var error = ""
    @State private var accountRecoveryMessage: String?
    @State private var goToRegister = false
    @State private var goToForgotPassword = false
    @State private var appleNonce: String?
    let previewMode: Bool

    init(previewMode: Bool = false) {
        self.previewMode = previewMode
    }

    var body: some View {
        NavigationStack {
            ZStack {
                MivoColors.background.ignoresSafeArea()
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                        .frame(maxHeight: 80)

                    VStack(spacing: 28) {
                        HStack(spacing: 14) {
                            MivoLogo(size: 64)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Mivo")
                                    .font(.system(size: 28, weight: .bold, design: .rounded))
                                    .foregroundColor(MivoColors.brand)
                                    .tracking(-0.8)
                                Text("See the Pattern. Break the Loop.")
                                    .font(.system(size: 13))
                                    .foregroundColor(MivoColors.textSecondary)
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 28)

                        Text("Pause. Choose. Scroll on your terms.")
                            .font(.system(size: 15).italic())
                            .foregroundColor(MivoColors.textSecondary)
                            .multilineTextAlignment(.center)
                        .padding(.horizontal, 28)

                        // Form
                        VStack(spacing: 16) {
                            VStack(alignment: .leading, spacing: 7) {
                                Text("Email")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(MivoColors.textSecondary)
                                ZStack(alignment: .leading) {
                                    if email.isEmpty {
                                        Text("Enter your email")
                                            .font(.system(size: 16))
                                            .foregroundColor(MivoColors.textMuted)
                                            .padding(.horizontal, 18)
                                            .padding(.vertical, 16)
                                    }
                                    TextField("", text: $email)
                                        .keyboardType(.emailAddress)
                                        .autocapitalization(.none)
                                        .font(.system(size: 16))
                                        .foregroundColor(MivoColors.textPrimary)
                                        .padding(.horizontal, 18)
                                        .padding(.vertical, 16)
                                        .background(Color.clear)
                                }
                                .background(MivoColors.surfaceRaised.opacity(0.56))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .strokeBorder(MivoColors.border, lineWidth: 1)
                                )
                            }

                            VStack(alignment: .leading, spacing: 7) {
                                Text("Password")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(MivoColors.textSecondary)
                                ZStack(alignment: .trailing) {
                                    ZStack(alignment: .leading) {
                                        if password.isEmpty {
                                            Text("Enter your password")
                                                .font(.system(size: 16))
                                                .foregroundColor(MivoColors.textMuted)
                                                .padding(.horizontal, 18)
                                                .padding(.vertical, 16)
                                                .padding(.trailing, 44)
                                        }
                                        Group {
                                            if showPassword {
                                                TextField("", text: $password)
                                            } else {
                                                SecureField("", text: $password)
                                            }
                                        }
                                        .font(.system(size: 16))
                                        .foregroundColor(MivoColors.textPrimary)
                                        .padding(.horizontal, 18)
                                        .padding(.vertical, 16)
                                        .padding(.trailing, 44)
                                    }
                                    .background(MivoColors.surfaceRaised.opacity(0.56))
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .strokeBorder(MivoColors.border, lineWidth: 1)
                                    )

                                    Button {
                                        showPassword.toggle()
                                    } label: {
                                        Image(systemName: showPassword ? "eye.slash" : "eye")
                                            .foregroundColor(MivoColors.accentLight)
                                    }
                                    .padding(.trailing, 16)
                                }
                            }

                            Button {
                                goToForgotPassword = true
                            } label: {
                                Text("Forgot password?")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(MivoColors.accent)
                                    .frame(maxWidth: .infinity, alignment: .trailing)
                            }

                            Button {
                                withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                                    rememberMe.toggle()
                                }
                                HapticsService.selection()
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: rememberMe ? "checkmark.square.fill" : "square")
                                        .font(.system(size: 18, weight: .semibold))
                                        .foregroundColor(rememberMe ? MivoColors.accent : MivoColors.textMuted)
                                        .frame(width: 24)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Remember me")
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundColor(MivoColors.textPrimary)
                                        Text("Keep me signed in on this device.")
                                            .font(.system(size: 12))
                                            .foregroundColor(MivoColors.textMuted)
                                    }
                                    Spacer()
                                }
                                .padding(.vertical, 12)
                                .overlay(alignment: .bottom) {
                                    Rectangle().fill(MivoColors.border.opacity(0.34)).frame(height: 1)
                                }
                            }
                            .buttonStyle(.plain)

                            if !error.isEmpty {
                                Text(error)
                                    .font(.system(size: 13))
                                    .foregroundColor(MivoColors.timerRed)
                            }

                            Button {
                                handleLogin()
                            } label: {
                                Text(loading ? "Signing in..." : "Sign In")
                                    .font(.system(size: 17, weight: .semibold))
                                    .foregroundColor(MivoColors.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 18)
                                    .background(MivoColors.accent)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                            .disabled(loading)
                            .opacity(loading ? 0.7 : 1)
                            .padding(.top, 4)

                            HStack(spacing: 10) {
                                Rectangle().fill(MivoColors.border.opacity(0.5)).frame(height: 1)
                                Text("or")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(MivoColors.textMuted)
                                Rectangle().fill(MivoColors.border.opacity(0.5)).frame(height: 1)
                            }
                            .padding(.top, 6)

                            if previewMode || GoogleAuthService.isConfigured {
                                Button {
                                    handleGoogleSignIn()
                                } label: {
                                    HStack(spacing: 10) {
                                        Text("G")
                                            .font(.system(size: 15, weight: .bold))
                                            .foregroundColor(MivoColors.accent)
                                        Text("Continue with Google")
                                            .font(.system(size: 16, weight: .semibold))
                                            .foregroundColor(MivoColors.textPrimary)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 16)
                                    .background(MivoColors.surfaceRaised.opacity(0.56))
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .strokeBorder(MivoColors.border, lineWidth: 1)
                                    )
                                }
                                .disabled(loading)
                                .opacity(loading ? 0.7 : 1)
                            }

                            if previewMode {
                                Button {
                                    HapticsService.selection()
                                    error = "Founder preview only. Your signed-in account was not changed."
                                } label: {
                                    HStack(spacing: 10) {
                                        Image(systemName: "apple.logo")
                                        Text("Continue with Apple")
                                            .font(.system(size: 16, weight: .semibold))
                                    }
                                    .foregroundColor(MivoColors.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 16)
                                    .background(Color.black)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                }
                                .disabled(loading)
                                .opacity(loading ? 0.7 : 1)
                            } else {
                                SignInWithAppleButton(.continue) { request in
                                    let nonce = AppleSignInNonce.random()
                                    appleNonce = nonce
                                    request.requestedScopes = [.fullName, .email]
                                    request.nonce = AppleSignInNonce.sha256(nonce)
                                } onCompletion: { result in
                                    handleAppleSignIn(result)
                                }
                                .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                                .frame(height: 50)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .disabled(loading)
                                .opacity(loading ? 0.7 : 1)
                            }

                            if previewMode || DeviceBindingService.boundEmail == nil {
                                HStack(spacing: 0) {
                                    Text("New to Mivo? ")
                                        .font(.system(size: 14))
                                        .foregroundColor(MivoColors.textSecondary)
                                    Button("Create an account") {
                                        goToRegister = true
                                    }
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(MivoColors.accent)
                                }
                            }
                        }
                        .padding(.horizontal, 28)
                    }
                    .mivoReadableWidth(620)

                    Spacer()

                    HStack {
                        Spacer()
                        Image("feather")
                            .font(.system(size: 26))
                            .foregroundColor(MivoColors.accentLight.opacity(0.7))
                    }
                    .padding(28)
                }

                if loading {
                    MivoLoadingOverlay(message: "Signing you in...")
                        .transition(.opacity)
                }
            }
            .navigationDestination(isPresented: $goToRegister) {
                RegisterView(previewMode: previewMode)
            }
            .navigationDestination(isPresented: $goToForgotPassword) {
                ForgotPasswordView(previewMode: previewMode)
            }
            .alert("Account already on this device", isPresented: Binding(
                get: { accountRecoveryMessage != nil },
                set: { if !$0 { accountRecoveryMessage = nil } }
            )) {
                Button("Sign In", role: .cancel) {
                    accountRecoveryMessage = nil
                }
            } message: {
                Text(accountRecoveryMessage ?? "")
            }
            .onAppear {
                if previewMode {
                    email = ""
                    password = ""
                    rememberMe = true
                } else if DeviceBindingService.boundEmail != nil {
                    email = ""
                    rememberMe = true
                } else if let remembered = StorageService.load(String.self, forKey: .rememberedEmail), !remembered.isEmpty {
                    email = remembered
                    rememberMe = true
                }
            }
        }
    }

    func handleLogin() {
        if previewMode {
            HapticsService.selection()
            error = "Founder preview only. Your signed-in account was not changed."
            return
        }
        guard !email.trimmingCharacters(in: .whitespaces).isEmpty else {
            error = "Please enter your email."
            return
        }
        guard !password.isEmpty else {
            error = "Please enter your password."
            return
        }
        error = ""
        loading = true
        Task {
            do {
                try await appVM.login(
                    email: email.lowercased().trimmingCharacters(in: .whitespacesAndNewlines),
                    password: password,
                    rememberMe: rememberMe
                )
            } catch {
                await MainActor.run {
                    if case AppError.deviceBoundToAnotherAccount(_) = error {
                        self.accountRecoveryMessage = error.localizedDescription
                        self.error = ""
                    } else {
                        self.error = error.localizedDescription
                    }
                }
            }
            await MainActor.run {
                loading = false
            }
        }
    }

    func handleGoogleSignIn() {
        if previewMode {
            HapticsService.selection()
            error = "Founder preview only. Your signed-in account was not changed."
            return
        }
        error = ""
        loading = true
        Task {
            do {
                try await appVM.loginWithGoogle()
            } catch {
                await MainActor.run {
                    if error is GoogleSignInCancelled {
                        self.error = ""
                    } else if case AppError.deviceBoundToAnotherAccount(_) = error {
                        self.accountRecoveryMessage = error.localizedDescription
                        self.error = ""
                    } else {
                        self.error = error.localizedDescription
                    }
                }
            }
            await MainActor.run {
                loading = false
            }
        }
    }

    func handleAppleSignIn(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .failure(let authError):
            // User-cancelled sheets surface as ASAuthorizationError.canceled — not a real error.
            if (authError as? ASAuthorizationError)?.code == .canceled { return }
            error = authError.localizedDescription
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let idToken = String(data: tokenData, encoding: .utf8),
                  let nonce = appleNonce else {
                error = "Apple sign-in did not return a usable credential."
                return
            }
            error = ""
            loading = true
            Task {
                do {
                    try await appVM.loginWithApple(idToken: idToken, nonce: nonce)
                } catch {
                    await MainActor.run {
                        if case AppError.deviceBoundToAnotherAccount(_) = error {
                            self.accountRecoveryMessage = error.localizedDescription
                            self.error = ""
                        } else {
                            self.error = error.localizedDescription
                        }
                    }
                }
                await MainActor.run {
                    loading = false
                }
            }
        }
    }
}

/// Shared by both apps' Sign in with Apple buttons — the raw nonce is
/// generated here (view layer, matches Apple's own sample code) and its
/// SHA256 hash goes on the `ASAuthorizationAppleIDRequest`; the raw value
/// is sent to Supabase alongside the identity token so it can verify the
/// hash inside the token matches, guarding against replay.
enum AppleSignInNonce {
    static func random(length: Int = 32) -> String {
        precondition(length > 0)
        let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remainingLength = length
        while remainingLength > 0 {
            var randoms = [UInt8](repeating: 0, count: 16)
            let status = SecRandomCopyBytes(kSecRandomDefault, randoms.count, &randoms)
            precondition(status == errSecSuccess)
            for random in randoms {
                if remainingLength == 0 { break }
                if random < charset.count {
                    result.append(charset[Int(random)])
                    remainingLength -= 1
                }
            }
        }
        return result
    }

    static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).compactMap { String(format: "%02x", $0) }.joined()
    }
}
