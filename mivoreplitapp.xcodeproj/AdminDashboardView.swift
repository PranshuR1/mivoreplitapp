import SwiftUI

struct AdminDashboardView: View {
    @EnvironmentObject var appVM: AppViewModel
    @State private var users: [UserAccountInfo] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showDeleteConfirmation = false
    @State private var userToDelete: UserAccountInfo?
    @State private var selectedUser: UserAccountInfo?
    @State private var showUserDetails = false
    @State private var searchText = ""
    
    var filteredUsers: [UserAccountInfo] {
        if searchText.isEmpty {
            return users
        }
        return users.filter { user in
            user.email.localizedCaseInsensitiveContains(searchText) ||
            user.name.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                MivoColors.background.ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Header Stats
                    adminStatsHeader
                    
                    // Search Bar
                    searchBar
                    
                    // User List
                    if isLoading {
                        Spacer()
                        ProgressView("Loading users...")
                            .foregroundColor(MivoColors.textPrimary)
                        Spacer()
                    } else if let error = errorMessage {
                        Spacer()
                        VStack(spacing: 12) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.system(size: 48))
                                .foregroundColor(MivoColors.error)
                            Text(error)
                                .foregroundColor(MivoColors.textMuted)
                                .multilineTextAlignment(.center)
                            Button("Retry") {
                                loadUsers()
                            }
                            .foregroundColor(MivoColors.accent)
                        }
                        .padding()
                        Spacer()
                    } else if filteredUsers.isEmpty {
                        Spacer()
                        VStack(spacing: 12) {
                            Image(systemName: "person.3")
                                .font(.system(size: 48))
                                .foregroundColor(MivoColors.textMuted)
                            Text(searchText.isEmpty ? "No users found" : "No users match your search")
                                .foregroundColor(MivoColors.textMuted)
                        }
                        Spacer()
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 12) {
                                ForEach(filteredUsers) { user in
                                    userRow(user)
                                }
                            }
                            .padding()
                        }
                    }
                }
            }
            .navigationTitle("Admin Dashboard")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        loadUsers()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .foregroundColor(MivoColors.accent)
                    }
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        AdminService.logoutAdmin()
                        appVM.logout()
                    } label: {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                            .foregroundColor(MivoColors.error)
                    }
                }
            }
            .alert("Delete User", isPresented: $showDeleteConfirmation, presenting: userToDelete) { user in
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) {
                    deleteUser(user)
                }
            } message: { user in
                Text("Are you sure you want to delete \(user.email)? This action cannot be undone.")
            }
            .sheet(item: $selectedUser) { user in
                UserDetailsView(user: user)
            }
        }
        .onAppear {
            loadUsers()
        }
    }
    
    // MARK: - UI Components
    
    private var adminStatsHeader: some View {
        VStack(spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Total Users")
                        .font(.system(size: 12))
                        .foregroundColor(MivoColors.textMuted)
                    Text("\(users.count)")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(MivoColors.textPrimary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Total Sessions")
                        .font(.system(size: 12))
                        .foregroundColor(MivoColors.textMuted)
                    Text("\(totalSessions)")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(MivoColors.textPrimary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Total Minutes")
                        .font(.system(size: 12))
                        .foregroundColor(MivoColors.textMuted)
                    Text("\(totalMinutes)")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(MivoColors.accent)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding()
            .background(MivoColors.cardBackground)
            .cornerRadius(12)
            .padding(.horizontal)
            .padding(.top)
        }
    }
    
    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(MivoColors.textMuted)
            TextField("Search users...", text: $searchText)
                .foregroundColor(MivoColors.textPrimary)
        }
        .padding(12)
        .background(MivoColors.cardBackground)
        .cornerRadius(10)
        .padding()
    }
    
    private func userRow(_ user: UserAccountInfo) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(user.name)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(MivoColors.textPrimary)
                    Text(user.email)
                        .font(.system(size: 14))
                        .foregroundColor(MivoColors.textMuted)
                }
                
                Spacer()
                
                Menu {
                    Button {
                        selectedUser = user
                        showUserDetails = true
                    } label: {
                        Label("View Details", systemImage: "info.circle")
                    }
                    
                    Button(role: .destructive) {
                        userToDelete = user
                        showDeleteConfirmation = true
                    } label: {
                        Label("Delete User", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .foregroundColor(MivoColors.textPrimary)
                        .padding(8)
                        .background(MivoColors.background)
                        .clipShape(Circle())
                }
            }
            
            Divider()
                .background(MivoColors.textMuted.opacity(0.3))
            
            HStack(spacing: 20) {
                statItem(icon: "clock", label: "Sessions", value: "\(user.sessionCount)")
                statItem(icon: "timer", label: "Minutes", value: "\(user.totalMinutes)")
                statItem(icon: "checkmark.shield", label: "Truth Checks", value: "\(user.truthCheckCount)")
            }
            
            if let lastSession = user.lastSessionDate {
                HStack {
                    Image(systemName: "calendar")
                        .font(.system(size: 12))
                        .foregroundColor(MivoColors.textMuted)
                    Text("Last session: \(lastSession)")
                        .font(.system(size: 12))
                        .foregroundColor(MivoColors.textMuted)
                }
            }
            
            HStack {
                Image(systemName: "person.crop.circle")
                    .font(.system(size: 12))
                    .foregroundColor(MivoColors.textMuted)
                Text("Created: \(formatDate(user.createdAt))")
                    .font(.system(size: 12))
                    .foregroundColor(MivoColors.textMuted)
            }
        }
        .padding()
        .background(MivoColors.cardBackground)
        .cornerRadius(12)
        .onTapGesture {
            selectedUser = user
        }
    }
    
    private func statItem(icon: String, label: String, value: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundColor(MivoColors.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(MivoColors.textPrimary)
                Text(label)
                    .font(.system(size: 10))
                    .foregroundColor(MivoColors.textMuted)
            }
        }
    }
    
    // MARK: - Computed Properties
    
    private var totalSessions: Int {
        users.reduce(0) { $0 + $1.sessionCount }
    }
    
    private var totalMinutes: Int {
        users.reduce(0) { $0 + $1.totalMinutes }
    }
    
    // MARK: - Actions
    
    private func loadUsers() {
        isLoading = true
        errorMessage = nil
        
        Task {
            do {
                let loadedUsers = try AdminService.getAllUsers()
                await MainActor.run {
                    self.users = loadedUsers
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.isLoading = false
                }
            }
        }
    }
    
    private func deleteUser(_ user: UserAccountInfo) {
        Task {
            do {
                try AdminService.deleteUser(email: user.email)
                await MainActor.run {
                    users.removeAll { $0.email == user.email }
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
    
    private func formatDate(_ isoString: String) -> String {
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: isoString) else {
            return isoString
        }
        
        let displayFormatter = DateFormatter()
        displayFormatter.dateStyle = .medium
        displayFormatter.timeStyle = .short
        return displayFormatter.string(from: date)
    }
}

// MARK: - User Details View

struct UserDetailsView: View {
    let user: UserAccountInfo
    @Environment(\.dismiss) var dismiss
    @State private var sessions: [Session] = []
    @State private var truthChecks: [TruthCheckGuess] = []
    @State private var isLoading = true
    
    var body: some View {
        NavigationView {
            ZStack {
                MivoColors.background.ignoresSafeArea()
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // User Info Section
                        VStack(alignment: .leading, spacing: 12) {
                            Text("User Information")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundColor(MivoColors.textPrimary)
                            
                            detailRow(label: "Name", value: user.name)
                            detailRow(label: "Email", value: user.email)
                            detailRow(label: "Created", value: formatDate(user.createdAt))
                            
                            if let lastSession = user.lastSessionDate {
                                detailRow(label: "Last Session", value: lastSession)
                            }
                        }
                        .padding()
                        .background(MivoColors.cardBackground)
                        .cornerRadius(12)
                        
                        // Stats Section
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Statistics")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundColor(MivoColors.textPrimary)
                            
                            HStack {
                                statCard(title: "Sessions", value: "\(sessions.count)", icon: "clock")
                                statCard(title: "Total Time", value: "\(user.totalMinutes)m", icon: "timer")
                            }
                            HStack {
                                statCard(title: "Truth Checks", value: "\(truthChecks.count)", icon: "checkmark.shield")
                                statCard(title: "Avg Session", value: sessions.isEmpty ? "0m" : "\(user.totalMinutes / sessions.count)m", icon: "chart.bar")
                            }
                        }
                        .padding()
                        .background(MivoColors.cardBackground)
                        .cornerRadius(12)
                        
                        // Onboarding Profile
                        if let profile = user.onboardingProfile {
                            onboardingProfileSection(profile)
                        }
                        
                        // Recent Sessions
                        if !sessions.isEmpty {
                            recentSessionsSection
                        }
                        
                        // Truth Checks
                        if !truthChecks.isEmpty {
                            truthChecksSection
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("User Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(MivoColors.accent)
                }
            }
            .onAppear {
                loadDetails()
            }
        }
    }
    
    private func detailRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 14))
                .foregroundColor(MivoColors.textMuted)
            Spacer()
            Text(value)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(MivoColors.textPrimary)
        }
    }
    
    private func statCard(title: String, value: String, icon: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundColor(MivoColors.accent)
            Text(value)
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(MivoColors.textPrimary)
            Text(title)
                .font(.system(size: 12))
                .foregroundColor(MivoColors.textMuted)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(MivoColors.background)
        .cornerRadius(10)
    }
    
    private func onboardingProfileSection(_ profile: OnboardingProfile) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Onboarding Profile")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(MivoColors.textPrimary)
            
            if let intention = profile.primaryIntention {
                detailRow(label: "Primary Intention", value: intention.rawValue)
            }
            
            if let estimate = profile.scrollEstimateMinutes {
                detailRow(label: "Scroll Estimate", value: "\(estimate) minutes")
            }
            
            if !profile.preferredApps.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Preferred Apps")
                        .font(.system(size: 14))
                        .foregroundColor(MivoColors.textMuted)
                    Text(profile.preferredApps.joined(separator: ", "))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(MivoColors.textPrimary)
                }
            }
            
            if let age = profile.age {
                detailRow(label: "Age", value: "\(age)")
            }
            
            if let ageRange = profile.ageRange {
                detailRow(label: "Age Range", value: ageRange)
            }
        }
        .padding()
        .background(MivoColors.cardBackground)
        .cornerRadius(12)
    }
    
    private var recentSessionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent Sessions (\(min(sessions.count, 5)))")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(MivoColors.textPrimary)
            
            ForEach(Array(sessions.prefix(5)), id: \.id) { session in
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(session.intention.rawValue)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(MivoColors.textPrimary)
                        Text(session.date)
                            .font(.system(size: 12))
                            .foregroundColor(MivoColors.textMuted)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("\(session.actualDuration)m")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(MivoColors.accent)
                        Text("planned: \(session.plannedDuration)m")
                            .font(.system(size: 12))
                            .foregroundColor(MivoColors.textMuted)
                    }
                }
                .padding()
                .background(MivoColors.background)
                .cornerRadius(8)
            }
        }
        .padding()
        .background(MivoColors.cardBackground)
        .cornerRadius(12)
    }
    
    private var truthChecksSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Truth Checks (\(min(truthChecks.count, 5)))")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(MivoColors.textPrimary)
            
            ForEach(Array(truthChecks.prefix(5)), id: \.id) { check in
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(check.date)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(MivoColors.textPrimary)
                        Text("Guess: \(check.guess)m · Actual: \(check.actual)m")
                            .font(.system(size: 12))
                            .foregroundColor(MivoColors.textMuted)
                    }
                    Spacer()
                    let difference = abs(check.guess - check.actual)
                    let accuracy = check.actual > 0 ? 100 - min(100, (difference * 100) / check.actual) : 0
                    Text("\(accuracy)%")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(accuracy >= 80 ? MivoColors.success : accuracy >= 50 ? MivoColors.warning : MivoColors.error)
                }
                .padding()
                .background(MivoColors.background)
                .cornerRadius(8)
            }
        }
        .padding()
        .background(MivoColors.cardBackground)
        .cornerRadius(12)
    }
    
    private func loadDetails() {
        Task {
            do {
                let details = try AdminService.getUserDetails(email: user.email)
                await MainActor.run {
                    self.sessions = details.sessions.sorted(by: { $0.startTime > $1.startTime })
                    self.truthChecks = details.truthChecks.sorted(by: { $0.date > $1.date })
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.isLoading = false
                }
            }
        }
    }
    
    private func formatDate(_ isoString: String) -> String {
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: isoString) else {
            return isoString
        }
        
        let displayFormatter = DateFormatter()
        displayFormatter.dateStyle = .medium
        displayFormatter.timeStyle = .short
        return displayFormatter.string(from: date)
    }
}

// MARK: - Preview

#Preview {
    AdminDashboardView()
        .environmentObject(AppViewModel())
}
