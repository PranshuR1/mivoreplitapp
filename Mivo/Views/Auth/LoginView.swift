import SwiftUI

struct LoginView: View {
    @EnvironmentObject var appVM: AppViewModel
    @State private var email = ""
    @State private var password = ""
    @State private var showPassword = false
    @State private var rememberMe = true
    @State private var loading = false
    @State private var error = ""
    @State private var accountRecoveryMessage: String?
    @State private var goToRegister = false
    @State private var goToForgotPassword = false
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
}
