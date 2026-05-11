import SwiftUI

/// Main admin access point - add this to your app's settings or as a hidden gesture
struct AdminAccessView: View {
    @EnvironmentObject var appVM: AppViewModel
    @State private var showAdminSetup = false
    @State private var showAdminLogin = false
    
    var body: some View {
        VStack(spacing: 20) {
            if AdminService.adminExists() {
                // Admin exists, show login
                Button {
                    showAdminLogin = true
                } label: {
                    HStack {
                        Image(systemName: "shield.checkered")
                        Text("Admin Login")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(MivoColors.accent)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
            } else {
                // No admin, show setup
                Button {
                    showAdminSetup = true
                } label: {
                    HStack {
                        Image(systemName: "gear.badge.checkmark")
                        Text("Initialize Admin Account")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(MivoColors.accent)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
            }
        }
        .padding()
        .sheet(isPresented: $showAdminSetup) {
            AdminSetupView()
        }
        .fullScreenCover(isPresented: $showAdminLogin) {
            AdminLoginView()
                .environmentObject(appVM)
        }
    }
}

#Preview {
    AdminAccessView()
        .environmentObject(AppViewModel())
}
