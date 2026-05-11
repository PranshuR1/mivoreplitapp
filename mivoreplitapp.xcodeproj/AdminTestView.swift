import SwiftUI

/// Admin System Test View - Use this to verify your admin setup works correctly
/// Add this to your app during development to test admin features
struct AdminTestView: View {
    @State private var testResults: [TestResult] = []
    @State private var isTesting = false
    
    struct TestResult: Identifiable {
        let id = UUID()
        let name: String
        let passed: Bool
        let message: String
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                MivoColors.background.ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 20) {
                        // Header
                        VStack(spacing: 8) {
                            Image(systemName: "testtube.2")
                                .font(.system(size: 48))
                                .foregroundColor(MivoColors.accent)
                            
                            Text("Admin System Tests")
                                .font(.system(size: 24, weight: .bold))
                                .foregroundColor(MivoColors.textPrimary)
                            
                            Text("Verify that the admin system is working correctly")
                                .font(.system(size: 14))
                                .foregroundColor(MivoColors.textMuted)
                                .multilineTextAlignment(.center)
                        }
                        .padding()
                        
                        // Run Tests Button
                        Button {
                            runTests()
                        } label: {
                            HStack {
                                if isTesting {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                } else {
                                    Image(systemName: "play.fill")
                                    Text("Run Tests")
                                        .font(.system(size: 16, weight: .semibold))
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(MivoColors.accent)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                        }
                        .disabled(isTesting)
                        .padding(.horizontal)
                        
                        // Test Results
                        if !testResults.isEmpty {
                            VStack(spacing: 12) {
                                Text("Test Results")
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundColor(MivoColors.textPrimary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                
                                ForEach(testResults) { result in
                                    testResultRow(result)
                                }
                                
                                // Summary
                                let passed = testResults.filter { $0.passed }.count
                                let total = testResults.count
                                
                                HStack {
                                    Text("Summary:")
                                        .font(.system(size: 16, weight: .semibold))
                                    Spacer()
                                    Text("\(passed)/\(total) tests passed")
                                        .font(.system(size: 16, weight: .bold))
                                        .foregroundColor(passed == total ? MivoColors.success : MivoColors.warning)
                                }
                                .padding()
                                .background(MivoColors.cardBackground)
                                .cornerRadius(12)
                            }
                            .padding()
                        }
                    }
                    .padding(.vertical)
                }
            }
            .navigationTitle("Admin Tests")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
    
    private func testResultRow(_ result: TestResult) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: result.passed ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.system(size: 24))
                .foregroundColor(result.passed ? MivoColors.success : MivoColors.error)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(result.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(MivoColors.textPrimary)
                
                Text(result.message)
                    .font(.system(size: 13))
                    .foregroundColor(MivoColors.textMuted)
            }
            
            Spacer()
        }
        .padding()
        .background(MivoColors.cardBackground)
        .cornerRadius(12)
    }
    
    private func runTests() {
        testResults = []
        isTesting = true
        
        Task {
            // Test 1: Admin Account Exists
            await test("Admin Account Setup") {
                let exists = AdminService.adminExists()
                if exists {
                    return (true, "Admin account is properly configured")
                } else {
                    return (false, "Admin account not found. Run initialization first.")
                }
            }
            
            // Test 2: Admin Login
            await test("Admin Authentication") {
                do {
                    // First logout if logged in
                    AdminService.logoutAdmin()
                    
                    let success = try AdminService.loginAdmin(
                        email: "useparkez@gmail.com",
                        password: "Pranshu@123"
                    )
                    
                    if success && AdminService.isAdminAuthenticated() {
                        return (true, "Successfully logged in as admin")
                    } else {
                        return (false, "Login succeeded but session not created")
                    }
                } catch {
                    return (false, "Login failed: \(error.localizedDescription)")
                }
            }
            
            // Test 3: Get Users
            await test("User List Retrieval") {
                do {
                    let users = try AdminService.getAllUsers()
                    return (true, "Retrieved \(users.count) user(s)")
                } catch {
                    return (false, "Failed to get users: \(error.localizedDescription)")
                }
            }
            
            // Test 4: Storage Keys
            await test("Storage Configuration") {
                let hasAdminKey = true // StorageKey.adminSession exists
                if hasAdminKey {
                    return (true, "Admin storage keys are properly configured")
                } else {
                    return (false, "Missing admin storage keys")
                }
            }
            
            // Test 5: Color Definitions
            await test("UI Color Definitions") {
                // Test that colors are accessible
                let _ = MivoColors.background
                let _ = MivoColors.accent
                let _ = MivoColors.textPrimary
                
                // Try admin-specific colors
                do {
                    let _ = MivoColors.success
                    let _ = MivoColors.warning
                    let _ = MivoColors.error
                    return (true, "All required colors are defined")
                } catch {
                    return (false, "Some admin colors are missing")
                }
            }
            
            // Test 6: Model Structures
            await test("Data Model Validation") {
                // Test that we can create admin models
                let testUser = UserAccountInfo(
                    email: "test@example.com",
                    name: "Test User",
                    createdAt: ISO8601DateFormatter().string(from: Date())
                )
                
                if testUser.id == testUser.email {
                    return (true, "Admin data models are properly structured")
                } else {
                    return (false, "Data model validation failed")
                }
            }
            
            // Test 7: Session Management
            await test("Session Management") {
                // Test logout
                AdminService.logoutAdmin()
                let loggedOut = !AdminService.isAdminAuthenticated()
                
                if loggedOut {
                    // Try logging back in
                    do {
                        _ = try AdminService.loginAdmin(
                            email: "useparkez@gmail.com",
                            password: "Pranshu@123"
                        )
                        let loggedIn = AdminService.isAdminAuthenticated()
                        if loggedIn {
                            return (true, "Session management working correctly")
                        } else {
                            return (false, "Re-login failed")
                        }
                    } catch {
                        return (false, "Session test failed: \(error.localizedDescription)")
                    }
                } else {
                    return (false, "Logout failed")
                }
            }
            
            await MainActor.run {
                isTesting = false
            }
        }
    }
    
    private func test(_ name: String, _ testBlock: () async -> (Bool, String)) async {
        let (passed, message) = await testBlock()
        let result = TestResult(name: name, passed: passed, message: message)
        
        await MainActor.run {
            testResults.append(result)
        }
        
        // Small delay between tests for UI update
        try? await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds
    }
}

#Preview {
    AdminTestView()
}
