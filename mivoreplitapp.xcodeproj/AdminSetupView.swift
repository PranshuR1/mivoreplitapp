import SwiftUI

/// View to initialize the admin account on first launch
/// This should only be shown once when no admin exists
struct AdminSetupView: View {
    @State private var isInitializing = false
    @State private var setupComplete = false
    @State private var errorMessage: String?
    @Environment(\.dismiss) var dismiss
    
    // Hardcoded credentials
    private let adminEmail = "useparkez@gmail.com"
    private let adminPassword = "Pranshu@123"
    
    var body: some View {
        ZStack {
            MivoColors.background.ignoresSafeArea()
            
            VStack(spacing: 24) {
                Spacer()
                
                if setupComplete {
                    // Success State
                    VStack(spacing: 20) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 80))
                            .foregroundColor(MivoColors.success)
                        
                        Text("Admin Account Created")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundColor(MivoColors.textPrimary)
                        
                        Text("Your admin account has been successfully set up.")
                            .font(.system(size: 16))
                            .foregroundColor(MivoColors.textMuted)
                            .multilineTextAlignment(.center)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Email:")
                                    .foregroundColor(MivoColors.textMuted)
                                Spacer()
                                Text(adminEmail)
                                    .foregroundColor(MivoColors.textPrimary)
                                    .fontWeight(.medium)
                            }
                            HStack {
                                Text("Password:")
                                    .foregroundColor(MivoColors.textMuted)
                                Spacer()
                                Text("••••••••")
                                    .foregroundColor(MivoColors.textPrimary)
                                    .fontWeight(.medium)
                            }
                        }
                        .padding()
                        .background(MivoColors.cardBackground)
                        .cornerRadius(12)
                        
                        Button {
                            dismiss()
                        } label: {
                            Text("Continue")
                                .font(.system(size: 16, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(MivoColors.accent)
                                .foregroundColor(.white)
                                .cornerRadius(12)
                        }
                    }
                } else {
                    // Setup State
                    VStack(spacing: 20) {
                        Image(systemName: "gear.badge.checkmark")
                            .font(.system(size: 80))
                            .foregroundColor(MivoColors.accent)
                        
                        Text("Initialize Admin Account")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundColor(MivoColors.textPrimary)
                        
                        Text("This will create an admin account with full access to manage all users and view system statistics.")
                            .font(.system(size: 16))
                            .foregroundColor(MivoColors.textMuted)
                            .multilineTextAlignment(.center)
                        
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
                        
                        Button {
                            initializeAdmin()
                        } label: {
                            HStack {
                                if isInitializing {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                } else {
                                    Text("Create Admin Account")
                                        .font(.system(size: 16, weight: .semibold))
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(MivoColors.accent)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                        }
                        .disabled(isInitializing)
                        
                        Button {
                            dismiss()
                        } label: {
                            Text("Skip for Now")
                                .font(.system(size: 14))
                                .foregroundColor(MivoColors.textMuted)
                        }
                    }
                }
                
                Spacer()
            }
            .padding()
        }
    }
    
    private func initializeAdmin() {
        errorMessage = nil
        isInitializing = true
        
        Task {
            do {
                try AdminService.initializeAdmin(email: adminEmail, password: adminPassword)
                await MainActor.run {
                    isInitializing = false
                    setupComplete = true
                }
            } catch {
                await MainActor.run {
                    isInitializing = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}

#Preview {
    AdminSetupView()
}
