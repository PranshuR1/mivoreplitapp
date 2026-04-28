import SwiftUI

struct ForgotPasswordView: View {
    @EnvironmentObject var appVM: AppViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var email = ""
    @State private var code = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var challenge: TwoFactorChallenge?
    @State private var loading = false
    @State private var message = ""
    @State private var resetComplete = false

    var body: some View {
        ZStack {
            MivoColors.background.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 10) {
                        MivoLogo(size: 52)
                        Text("Reset password")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundColor(MivoColors.textPrimary)
                        Text("We’ll send a verification code before changing your password.")
                            .font(.system(size: 15))
                            .foregroundColor(MivoColors.textSecondary)
                    }

                    authField(label: "Email", placeholder: "Enter your email", text: $email, keyboard: .emailAddress)

                    if challenge != nil {
                        authField(label: "Code", placeholder: "6-digit code", text: $code, keyboard: .numberPad)
                        secureField(label: "New password", placeholder: "Create a new password", text: $password)
                        secureField(label: "Confirm password", placeholder: "Confirm new password", text: $confirmPassword)
                    }

                    if !message.isEmpty {
                        Text(message)
                            .font(.system(size: 13))
                            .foregroundColor(resetComplete ? MivoColors.timerGreen : MivoColors.timerRed)
                    }

                    Button {
                        challenge == nil ? sendCode() : resetPassword()
                    } label: {
                        Text(buttonTitle)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(MivoColors.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                            .background(MivoColors.accent)
                            .clipShape(Capsule())
                    }
                    .disabled(loading)
                    .opacity(loading ? 0.7 : 1)
                }
                .padding(.horizontal, 28)
                .padding(.top, 60)
                .padding(.bottom, 40)
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
        .toolbarBackground(MivoColors.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
    }

    private var buttonTitle: String {
        if loading { return challenge == nil ? "Sending..." : "Resetting..." }
        return challenge == nil ? "Send code" : "Reset password"
    }

    private func sendCode() {
        let normalizedEmail = email.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        loading = true
        message = ""
        Task {
            do {
                let newChallenge = try await appVM.beginPasswordReset(email: normalizedEmail)
                await MainActor.run {
                    challenge = newChallenge
                    loading = false
                }
            } catch {
                await MainActor.run {
                    message = error.localizedDescription
                    loading = false
                }
            }
        }
    }

    private func resetPassword() {
        guard let challenge else { return }
        guard password == confirmPassword else {
            message = "Passwords do not match."
            return
        }
        loading = true
        message = ""
        do {
            try appVM.completePasswordReset(code: code, newPassword: password, challenge: challenge)
            resetComplete = true
            message = "Password reset. You can sign in now."
        } catch {
            message = error.localizedDescription
        }
        loading = false
    }

    private func authField(label: String, placeholder: String, text: Binding<String>, keyboard: UIKeyboardType) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(label)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(MivoColors.textSecondary)
            TextField(placeholder, text: text)
                .keyboardType(keyboard)
                .autocapitalization(.none)
                .font(.system(size: 16))
                .foregroundColor(MivoColors.textPrimary)
                .padding(.horizontal, 18)
                .padding(.vertical, 16)
                .background(MivoColors.card)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(MivoColors.border, lineWidth: 1))
        }
    }

    private func secureField(label: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(label)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(MivoColors.textSecondary)
            SecureField(placeholder, text: text)
                .font(.system(size: 16))
                .foregroundColor(MivoColors.textPrimary)
                .padding(.horizontal, 18)
                .padding(.vertical, 16)
                .background(MivoColors.card)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(MivoColors.border, lineWidth: 1))
        }
    }
}
