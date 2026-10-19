import SwiftUI
import AuthenticationServices

struct RegisterView: View {
    @EnvironmentObject var appVM: AppViewModel
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var showPassword = false
    @State private var loading = false
    @State private var error = ""
    @State private var accountRecoveryMessage: String?
    @State private var appleNonce: String?
    let previewMode: Bool

    init(previewMode: Bool = false) {
        self.previewMode = previewMode
    }

    var body: some View {
        ZStack {
            MivoColors.background.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 28) {
                    VStack(alignment: .leading, spacing: 12) {
                        MivoLogo(size: 52)
                        Text("Create account")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundColor(MivoColors.textPrimary)
                            .tracking(-0.8)
                        Text("Create your account and save your progress across devices.")
                            .font(.system(size: 15))
                            .foregroundColor(MivoColors.textSecondary)
                            .lineSpacing(3)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(spacing: 16) {
                        fieldView(label: "Name", placeholder: "Your name", text: $name)
                        fieldView(label: "Email", placeholder: "Enter your email", text: $email, keyboard: .emailAddress)
                        passwordFieldView(label: "Password", placeholder: "Create a password", text: $password)
                        PasswordStrengthView(password: password, confirmPassword: confirmPassword)
                        passwordFieldView(label: "Confirm Password", placeholder: "Confirm your password", text: $confirmPassword)
                    }

                    if !error.isEmpty {
                        Text(error)
                            .font(.system(size: 13))
                            .foregroundColor(MivoColors.timerRed)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Button {
                        handleRegister()
                    } label: {
                        Text(loading ? "Creating account..." : "Create Account")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(MivoColors.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                            .background(MivoColors.accent)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .disabled(loading)
                    .opacity(loading ? 0.7 : 1)

                    HStack(spacing: 10) {
                        Rectangle().fill(MivoColors.border.opacity(0.5)).frame(height: 1)
                        Text("or")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(MivoColors.textMuted)
                        Rectangle().fill(MivoColors.border.opacity(0.5)).frame(height: 1)
                    }

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
                            error = "Founder preview only. No account was created."
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

                    Button {
                        dismiss()
                    } label: {
                        Text("Already have an account? Sign in")
                            .font(.system(size: 14))
                            .foregroundColor(MivoColors.textSecondary)
                    }
                }
                .padding(.horizontal, 28)
                .padding(.top, 60)
                .padding(.bottom, 40)
                .mivoReadableWidth(620)
            }
            .scrollContentBackground(.hidden)

            if loading {
                MivoLoadingOverlay(message: "Creating your account...")
                    .transition(.opacity)
            }
        }
        .navigationBarBackButtonHidden()
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button { dismiss() } label: {
                    Image(systemName: "arrow.left")
                        .foregroundColor(MivoColors.textSecondary)
                }
            }
        }
        // Keep the navigation bar background consistent with the app's creme background
        .toolbarBackground(MivoColors.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
        .tint(MivoColors.textSecondary)
        .toolbarColorScheme(.light, for: .navigationBar)
        .alert("Account already on this device", isPresented: Binding(
            get: { accountRecoveryMessage != nil },
            set: { if !$0 { accountRecoveryMessage = nil } }
        )) {
            Button("Go to Sign In") {
                accountRecoveryMessage = nil
                dismiss()
            }
            Button("Cancel", role: .cancel) {
                accountRecoveryMessage = nil
            }
        } message: {
            Text(accountRecoveryMessage ?? "")
        }
    }

    @ViewBuilder
    func fieldView(label: String, placeholder: String, text: Binding<String>, keyboard: UIKeyboardType = .default) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(label)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(MivoColors.textSecondary)
            ZStack(alignment: .leading) {
                if text.wrappedValue.isEmpty {
                    Text(placeholder)
                        .font(.system(size: 16))
                        .foregroundColor(MivoColors.textMuted)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 16)
                }
                TextField("", text: text)
                    .keyboardType(keyboard)
                    .autocapitalization(keyboard == .emailAddress ? .none : .words)
                    .font(.system(size: 16))
                    .foregroundColor(MivoColors.textPrimary)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 16)
            }
            .background(MivoColors.card)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(MivoColors.border, lineWidth: 1))
        }
    }

    @ViewBuilder
    func passwordFieldView(label: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(label)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(MivoColors.textSecondary)
            ZStack(alignment: .trailing) {
                ZStack(alignment: .leading) {
                    if text.wrappedValue.isEmpty {
                        Text(placeholder)
                            .font(.system(size: 16))
                            .foregroundColor(MivoColors.textMuted)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 16)
                            .padding(.trailing, 44)
                    }
                    Group {
                        if showPassword {
                            TextField("", text: text)
                        } else {
                            SecureField("", text: text)
                        }
                    }
                    .font(.system(size: 16))
                    .foregroundColor(MivoColors.textPrimary)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 16)
                    .padding(.trailing, 44)
                }
                .background(MivoColors.card)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(MivoColors.border, lineWidth: 1))
                Button { showPassword.toggle() } label: {
                    Image(systemName: showPassword ? "eye.slash" : "eye")
                        .foregroundColor(MivoColors.accentLight)
                }
                .padding(.trailing, 16)
            }
        }
    }

    func handleRegister() {
        if previewMode {
            HapticsService.selection()
            error = "Founder preview only. No account was created."
            return
        }
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { error = "Please enter your name."; return }
        guard !email.trimmingCharacters(in: .whitespaces).isEmpty else { error = "Please enter your email."; return }
        guard !password.isEmpty else { error = "Please enter a password."; return }
        guard PasswordRules.evaluate(password, confirmPassword: confirmPassword).isAcceptable else {
            error = "Password must be at least 8 characters and match the confirmation."
            return
        }
        guard password == confirmPassword else { error = "Passwords do not match."; return }
        error = ""
        loading = true
        Task {
            do {
                try await appVM.registerDirectly(
                    email: email.lowercased().trimmingCharacters(in: .whitespacesAndNewlines),
                    password: password,
                    name: name.trimmingCharacters(in: .whitespacesAndNewlines)
                )
                if let ticket = ParentalConsentTicketStore.load() {
                    try await MivoBackendService.claimApprovedParentalConsent(ticket: ticket)
                    ParentalConsentTicketStore.clear()
                }
                await MainActor.run {
                    loading = false
                }
            } catch {
                await MainActor.run {
                    if case AppError.deviceBoundToAnotherAccount(_) = error {
                        self.accountRecoveryMessage = error.localizedDescription
                        self.error = ""
                    } else {
                        self.error = error.localizedDescription
                    }
                    loading = false
                }
            }
        }
    }

    func handleGoogleSignIn() {
        if previewMode {
            HapticsService.selection()
            error = "Founder preview only. No account was created."
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

struct PasswordRules {
    let hasLength: Bool
    let hasUppercase: Bool
    let hasLowercase: Bool
    let hasNumber: Bool
    let hasSymbol: Bool
    let matchesConfirmation: Bool

    var score: Int {
        [hasLength, hasUppercase, hasLowercase, hasNumber, hasSymbol].filter { $0 }.count
    }

    var isAcceptable: Bool {
        hasLength && matchesConfirmation
    }

    var title: String {
        switch score {
        case 0, 1: return "Weak"
        case 2, 3: return "Getting better"
        case 4: return "Strong"
        default: return "Very strong"
        }
    }

    var color: Color {
        switch score {
        case 0, 1: return MivoColors.timerRed
        case 2, 3: return MivoColors.accent
        case 4: return MivoColors.blue
        default: return MivoColors.timerGreen
        }
    }

    static func evaluate(_ password: String, confirmPassword: String) -> PasswordRules {
        PasswordRules(
            hasLength: password.count >= 8,
            hasUppercase: password.rangeOfCharacter(from: .uppercaseLetters) != nil,
            hasLowercase: password.rangeOfCharacter(from: .lowercaseLetters) != nil,
            hasNumber: password.rangeOfCharacter(from: .decimalDigits) != nil,
            hasSymbol: password.rangeOfCharacter(from: CharacterSet.alphanumerics.inverted) != nil,
            matchesConfirmation: !confirmPassword.isEmpty && password == confirmPassword
        )
    }
}

struct PasswordStrengthView: View {
    let password: String
    let confirmPassword: String

    private var rules: PasswordRules {
        PasswordRules.evaluate(password, confirmPassword: confirmPassword)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Password strength")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(MivoColors.textSecondary)
                Spacer()
                Text(rules.title)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(rules.color)
            }

            HStack(spacing: 6) {
                ForEach(0..<5, id: \.self) { index in
                    Capsule()
                        .fill(index < rules.score ? rules.color : MivoColors.border.opacity(0.55))
                        .frame(height: 6)
                }
            }

            VStack(spacing: 7) {
                requirementRow("At least 8 characters", met: rules.hasLength)
                requirementRow("Uppercase and lowercase letters", met: rules.hasUppercase && rules.hasLowercase)
                requirementRow("At least 1 number", met: rules.hasNumber)
                requirementRow("Symbol recommended", met: rules.hasSymbol, optional: true)
                requirementRow("Passwords match", met: rules.matchesConfirmation)
            }
        }
        .padding(14)
        .background(MivoColors.surfaceRaised.opacity(0.52))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(MivoColors.border.opacity(0.6), lineWidth: 1))
    }

    private func requirementRow(_ text: String, met: Bool, optional: Bool = false) -> some View {
        HStack(spacing: 8) {
            Image(systemName: met ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(met ? MivoColors.timerGreen : MivoColors.textMuted)
            Text(optional && !met ? "\(text)" : text)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(met ? MivoColors.textPrimary : MivoColors.textMuted)
            Spacer()
        }
    }
}
