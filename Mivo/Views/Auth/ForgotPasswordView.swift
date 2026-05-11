import SwiftUI

struct ForgotPasswordView: View {
    @EnvironmentObject var appVM: AppViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
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
                        Text("Enter your email and choose a new password.")
                            .font(.system(size: 15))
                            .foregroundColor(MivoColors.textSecondary)
                    }

                    authField(label: "Email", placeholder: "Enter your email", text: $email, keyboard: .emailAddress)
                    secureField(label: "New password", placeholder: "Create a new password", text: $password)
                    PasswordStrengthView(password: password, confirmPassword: confirmPassword)
                    secureField(label: "Confirm password", placeholder: "Confirm new password", text: $confirmPassword)

                    if !message.isEmpty {
                        Text(message)
                            .font(.system(size: 13))
                            .foregroundColor(resetComplete ? MivoColors.timerGreen : MivoColors.timerRed)
                    }

                    Button {
                        resetPassword()
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

                    if resetComplete {
                        Button {
                            dismiss()
                        } label: {
                            Text("Back to sign in")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(MivoColors.textPrimary)
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
                .padding(.horizontal, 28)
                .padding(.top, 60)
                .padding(.bottom, 40)
            }

            if loading {
                MivoLoadingOverlay(message: "Resetting password...")
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
        .toolbarBackground(MivoColors.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
    }

    private var buttonTitle: String {
        if loading { return "Resetting..." }
        if resetComplete { return "Password reset" }
        return "Reset password"
    }

    private func resetPassword() {
        let normalizedEmail = email.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedEmail.isEmpty else {
            message = "Enter the email for your Mivo account."
            return
        }
        guard PasswordRules.evaluate(password, confirmPassword: confirmPassword).isAcceptable else {
            message = "Password must be at least 8 characters and match the confirmation."
            return
        }
        guard password == confirmPassword else {
            message = "Passwords do not match."
            return
        }
        loading = true
        message = ""
        Task {
            do {
                try await appVM.resetPasswordWithoutVerification(email: normalizedEmail, newPassword: password)
                await MainActor.run {
                    resetComplete = true
                    message = "Password reset. You can sign in now."
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

    private func authField(label: String, placeholder: String, text: Binding<String>, keyboard: UIKeyboardType) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(label)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(MivoColors.textSecondary)
            TextField(placeholder, text: text)
                .keyboardType(keyboard)
                .textContentType(keyboard == .numberPad ? .oneTimeCode : .emailAddress)
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
