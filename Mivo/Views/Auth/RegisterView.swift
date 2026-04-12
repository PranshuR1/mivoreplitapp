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
                        Text("Everything stays on your device.")
                            .font(.system(size: 15))
                            .foregroundColor(MivoColors.textSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(spacing: 16) {
                        fieldView(label: "Name", placeholder: "Your name", text: $name)
                        fieldView(label: "Email", placeholder: "Enter your email", text: $email, keyboard: .emailAddress)
                        passwordFieldView(label: "Password", placeholder: "Create a password", text: $password)
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
                            .clipShape(Capsule())
                    }
                    .disabled(loading)
                    .opacity(loading ? 0.7 : 1)

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

    func handleRegister() {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { error = "Please enter your name."; return }
        guard !email.trimmingCharacters(in: .whitespaces).isEmpty else { error = "Please enter your email."; return }
        guard !password.isEmpty else { error = "Please enter a password."; return }
        guard password == confirmPassword else { error = "Passwords do not match."; return }
        error = ""
        loading = true
        do {
            try appVM.register(email: email.lowercased().trimmingCharacters(in: .whitespaces), password: password, name: name.trimmingCharacters(in: .whitespaces))
        } catch {
            self.error = error.localizedDescription
        }
        loading = false
    }
}
