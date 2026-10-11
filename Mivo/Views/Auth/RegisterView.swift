import SwiftUI

struct RegisterView: View {
    @EnvironmentObject var appVM: AppViewModel
    @Environment(\.dismiss) var dismiss
    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var showPassword = false
    @State private var loading = false
    @State private var error = ""

    var body: some View {
        ZStack {
            MivoColors.background.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 28) {
                    // Header
                    VStack(alignment: .leading, spacing: 12) {
                        MivoLogo(size: 52)
                        Text("Create account")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundColor(MivoColors.textPrimary)
                            .tracking(-0.8)
                        Text("Create your account and save your progress across devices.")
                            .font(.system(size: 15))
                            .foregroundColor(MivoColors.textSecondary)
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
                            .fixedSize(horizontal: false, vertical: true)
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
                            .clipShape(Capsule())
                    }
                    .disabled(loading)
                    .opacity(loading ? 0.7 : 1)

                    HStack(spacing: 12) {
                        Rectangle().fill(MivoColors.border).frame(height: 1)
                        Text("or")
                            .font(.system(size: 13))
                            .foregroundColor(MivoColors.textMuted)
                        Rectangle().fill(MivoColors.border).frame(height: 1)
                    }

                    VStack(spacing: 12) {
                        socialButton(title: "Sign up with Apple", systemImage: "apple.logo") {
                            handleSocial { try await SocialAuthService.shared.signInWithApple() }
                        }
                        socialButton(title: "Sign up with Google", systemImage: "g.circle.fill") {
                            handleSocial { try await SocialAuthService.shared.signInWithGoogle() }
                        }
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
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(MivoColors.border, lineWidth: 1))
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
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(MivoColors.border, lineWidth: 1))
                Button { showPassword.toggle() } label: {
                    Image(systemName: showPassword ? "eye.slash" : "eye")
                        .foregroundColor(MivoColors.accentLight)
                }
                .padding(.trailing, 16)
            }
        }
    }

    private func socialButton(title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage).font(.system(size: 18, weight: .semibold))
                Text(title).font(.system(size: 16, weight: .semibold))
            }
            .foregroundColor(MivoColors.textPrimary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(MivoColors.card)
            .clipShape(Capsule())
            .overlay(Capsule().strokeBorder(MivoColors.border, lineWidth: 1))
        }
        .disabled(loading)
    }

    func handleSocial(_ obtain: @escaping () async throws -> SocialCredential) {
        error = ""
        Task {
            do {
                let credential = try await obtain()
                await MainActor.run { loading = true }
                try await appVM.socialLogin(credential)
            } catch SocialAuthError.cancelled {
            } catch {
                await MainActor.run { self.error = error.localizedDescription }
            }
            await MainActor.run { loading = false }
        }
    }

    func handleRegister() {
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
                await MainActor.run {
                    loading = false
                }
            } catch {
                await MainActor.run {
                    self.error = error.localizedDescription
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
        .background(MivoColors.white.opacity(0.52))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(MivoColors.border.opacity(0.6), lineWidth: 1))
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
