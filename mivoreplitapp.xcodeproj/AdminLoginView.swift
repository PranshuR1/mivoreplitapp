import SwiftUI

struct AdminLoginView: View {
    @EnvironmentObject var appVM: AppViewModel
    @State private var email = ""
    @State private var password = ""
    @State private var isLoggingIn = false
    @State private var errorMessage: String?
    @State private var showAdminDashboard = false
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            ZStack {
                MivoColors.background.ignoresSafeArea()
                
                VStack(spacing: 24) {
                    Spacer()
                    
                    // Admin Icon
                    VStack(spacing: 12) {
                        Image(systemName: "shield.checkered")
                            .font(.system(size: 60))
                            .foregroundColor(MivoColors.accent)
                        
                        Text("Admin Access")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundColor(MivoColors.textPrimary)
                        
                        Text("Manage all users and view statistics")
                            .font(.system(size: 14))
                            .foregroundColor(MivoColors.textMuted)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.bottom, 20)
                    
                    // Email Field
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Admin Email")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(MivoColors.textPrimary)
                        
                        HStack {
                            Image(systemName: "envelope")
                                .foregroundColor(MivoColors.textMuted)
                            TextField("admin@example.com", text: $email)
                                .foregroundColor(MivoColors.textPrimary)
                                .autocapitalization(.none)
                                .keyboardType(.emailAddress)
                                .textContentType(.emailAddress)
                        }
                        .padding()
                        .background(MivoColors.cardBackground)
                        .cornerRadius(10)
                    }
                    
                    // Password Field
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Password")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(MivoColors.textPrimary)
                        
                        HStack {
                            Image(systemName: "lock")
                                .foregroundColor(MivoColors.textMuted)
                            SecureField("Enter password", text: $password)
                                .foregroundColor(MivoColors.textPrimary)
                                .textContentType(.password)
                        }
                        .padding()
                        .background(MivoColors.cardBackground)
                        .cornerRadius(10)
                    }
                    
                    // Error Message
                    if let error = errorMessage {
                        HStack {
                            Image(systemName: "exclamationmark.triangle")
                            Text(error)
                                .font(.system(size: 14))
                        }
                        .foregroundColor(MivoColors.error)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(MivoColors.error.opacity(0.1))
                        .cornerRadius(10)
                    }
                    
                    // Login Button
                    Button {
                        loginAdmin()
                    } label: {
                        HStack {
                            if isLoggingIn {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            } else {
                                Text("Login as Admin")
                                    .font(.system(size: 16, weight: .semibold))
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(canLogin ? MivoColors.accent : MivoColors.textMuted.opacity(0.3))
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                    .disabled(!canLogin || isLoggingIn)
                    
                    Spacer()
                    
                    // Back Button
                    Button {
                        dismiss()
                    } label: {
                        Text("Back to Login")
                            .font(.system(size: 14))
                            .foregroundColor(MivoColors.textMuted)
                    }
                }
                .padding()
            }
            .navigationBarHidden(true)
        }
        .fullScreenCover(isPresented: $showAdminDashboard) {
            AdminDashboardView()
                .environmentObject(appVM)
        }
    }
    
    private var canLogin: Bool {
        !email.isEmpty && !password.isEmpty
    }
    
    private func loginAdmin() {
        errorMessage = nil
        isLoggingIn = true
        
        Task {
            do {
                let success = try AdminService.loginAdmin(email: email, password: password)
                await MainActor.run {
                    isLoggingIn = false
                    if success {
                        showAdminDashboard = true
                    }
                }
            } catch {
                await MainActor.run {
                    isLoggingIn = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}

#Preview {
    AdminLoginView()
        .environmentObject(AppViewModel())
}
