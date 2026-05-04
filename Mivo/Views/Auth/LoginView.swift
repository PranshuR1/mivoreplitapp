import SwiftUI

struct LoginView: View {
    @EnvironmentObject var appVM: AppViewModel
    @State private var email = ""
    @State private var password = ""
    @State private var showPassword = false
    @State private var rememberMe = true
    @State private var loading = false
    @State private var error = ""
    @State private var goToRegister = false
    @State private var goToForgotPassword = false

    var body: some View {
        NavigationStack {
            ZStack {
                MivoColors.background.ignoresSafeArea()
                VStack(spacing: 0) {
                    Spacer(minLength: 0).frame(maxHeight: 80)

                    VStack(spacing: 28) {
                        // Header
                        HStack(spacing: 14) {
                            MivoLogo(size: 64)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Mivo")
                                    .font(.system(size: 28, weight: .bold))
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
                                .background(MivoColors.card)
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16)
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
                                    .background(MivoColors.card)
                                    .clipShape(RoundedRectangle(cornerRadius: 16))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16)
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
                                .padding(14)
                                .background(MivoColors.card.opacity(0.72))
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(MivoColors.border.opacity(0.7), lineWidth: 1))
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
                                    .clipShape(Capsule())
                                    .shadow(color: MivoColors.accent.opacity(0.25), radius: 10, y: 4)
                            }
                            .disabled(loading)
                            .opacity(loading ? 0.7 : 1)
                            .padding(.top, 4)

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
                        .padding(.horizontal, 28)
                    }

                    Spacer()

                    HStack {
                        Spacer()
                        Image(systemName: "feather")
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
                RegisterView()
            }
            .navigationDestination(isPresented: $goToForgotPassword) {
                ForgotPasswordView()
            }
            .onAppear {
                if let remembered = StorageService.load(String.self, forKey: .rememberedEmail), !remembered.isEmpty {
                    email = remembered
                    rememberMe = true
                }
            }
        }
    }

    func handleLogin() {
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
                    self.error = error.localizedDescription
                }
            }
            await MainActor.run {
                loading = false
            }
        }
    }
}
