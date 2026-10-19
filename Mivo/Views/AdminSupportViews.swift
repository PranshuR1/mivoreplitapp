import SwiftUI

struct ParentalConsentReviewView: View {
    @EnvironmentObject private var appVM: AppViewModel
    @State private var requests: [ParentalConsentRequest] = []
    @State private var isLoading = true
    @State private var message: String?

    var body: some View {
        ZStack {
            MivoColors.background.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                consentSection
                    .padding(20)
                    .padding(.bottom, 40)
            }
            if isLoading { MivoLoadingOverlay(message: "Loading consent requests...") }
        }
        .navigationTitle("Parent Consent")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
        .alert("Parent consent", isPresented: Binding(
            get: { message != nil }, set: { if !$0 { message = nil } }
        )) { Button("OK", role: .cancel) {} } message: { Text(message ?? "") }
    }

    private var consentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Parent consent review", systemImage: "person.crop.circle.badge.checkmark")
                .font(.system(size: 17, weight: .bold))
                .foregroundColor(MivoColors.textPrimary)
            if requests.isEmpty {
                Text("No parent consent requests.").font(.system(size: 13)).foregroundColor(MivoColors.textSecondary)
            } else {
                ForEach(requests) { request in
                    VStack(alignment: .leading, spacing: 7) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(request.parentEmail).font(.system(size: 13, weight: .bold))
                                Text("Birth: \(request.birthMonth)/\(request.birthYear) - \(request.status.capitalized)")
                                    .font(.system(size: 11)).foregroundColor(MivoColors.textMuted)
                            }
                            Spacer()
                            if request.status == "pending" || request.status == "needs_information" {
                                Button("Approve") { Task { await review(request, status: "approved") } }
                                    .font(.system(size: 11, weight: .bold)).tint(MivoColors.blue)
                                Button("Reject") { Task { await review(request, status: "rejected") } }
                                    .font(.system(size: 11, weight: .bold)).tint(.red)
                            }
                        }
                        if request.evidenceStoragePath == nil && request.status == "pending" {
                            Text("Waiting for signed consent and identity evidence.")
                                .font(.system(size: 10)).foregroundColor(MivoColors.textSecondary)
                        }
                    }
                    .padding(10)
                    .background(MivoColors.background)
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                }
            }
        }
        .adminPanelStyle()
    }

    private func load() async {
        isLoading = true
        do {
            try await appVM.prepareAuthenticatedSession()
            await appVM.refreshServerAdminRole()
            guard appVM.isSuperAdminUser else { throw MivoBackendError.server("super_admin_required") }
            requests = try await MivoBackendService.loadAdminUserDashboard().consentRequests
        } catch {
            message = error.localizedDescription
        }
        isLoading = false
    }

    private func review(_ request: ParentalConsentRequest, status: String) async {
        do {
            try await MivoBackendService.reviewConsent(id: request.id, status: status, note: "Reviewed in Mivo super-admin settings")
            await load()
        } catch { message = error.localizedDescription }
    }
}

struct AdminUserProgressView: View {
    let user: AdminUserRecord
    @State private var detail: AdminUserDetail?
    @State private var timeline: [AdminTimelineEvent] = []
    @State private var selectedSession: AdminSessionRecord?
    @State private var message: String?
    @State private var showReset = false
    @State private var showDelete = false

    var body: some View {
        List {
            Section("Progress") {
                LabeledContent("Sessions", value: "\(user.sessionCount)")
                LabeledContent("Total time", value: "\(user.totalMinutes) min")
                LabeledContent("Reflections", value: "\(user.reflectionCount)")
                LabeledContent("Onboarding", value: user.onboardingComplete ? "Complete" : "Incomplete")
            }
            Section("Sanitized timeline") {
                if timeline.isEmpty {
                    Text("No account activity is available yet.").foregroundColor(.secondary)
                } else {
                    ForEach(timeline.prefix(40)) { event in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: timelineIcon(event.type))
                                .foregroundColor(MivoColors.accent)
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(event.type.replacingOccurrences(of: "_", with: " ").capitalized)
                                    .font(.subheadline.weight(.semibold))
                                Text("\(event.status.capitalized) · \(timelineDate(event.at))")
                                    .font(.caption).foregroundColor(.secondary)
                                if let minutes = event.durationMinutes {
                                    Text("\(minutes) minutes").font(.caption2).foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                }
                Text("This timeline excludes app identities, intentions, triggers, reflection text, and session notes.")
                    .font(.caption2).foregroundColor(.secondary)
            }
            Section("Sessions") {
                if let sessions = detail?.sessions, !sessions.isEmpty {
                    ForEach(sessions) { session in
                        Button { selectedSession = session } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(session.date).font(.headline)
                                Text("\(session.actualDuration)m actual / \(session.plannedDuration)m planned")
                                    .font(.caption).foregroundColor(.secondary)
                            }
                        }
                    }
                } else {
                    Text("No sessions saved.").foregroundColor(.secondary)
                }
            }
            Section("Administrative actions") {
                Button("Reset all progress", role: .destructive) { showReset = true }
                Button("Delete account", role: .destructive) { showDelete = true }
            }
        }
        .scrollContentBackground(.hidden)
        .background(MivoColors.background)
        .navigationTitle(user.name)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .sheet(item: $selectedSession) { session in
            AdminSessionEditor(userID: user.userId, session: session) {
                await load()
            }
        }
        .alert("Reset all progress?", isPresented: $showReset) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) { Task { await reset() } }
        } message: { Text("This keeps the account but clears sessions, reports, schedules, and onboarding completion. The action is audited.") }
        .alert("Delete account?", isPresented: $showDelete) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) { Task { await delete() } }
        } message: { Text("This permanently removes the Supabase Auth account and associated data. The action is audited.") }
        .alert("Admin action", isPresented: Binding(
            get: { message != nil }, set: { if !$0 { message = nil } }
        )) { Button("OK", role: .cancel) {} } message: { Text(message ?? "") }
    }

    private func load() async {
        do {
            async let loadedDetail = MivoBackendService.loadAdminUserDetail(userID: user.userId)
            async let loadedTimeline = ProductExpansionService.adminUserTimeline(userID: user.userId)
            detail = try await loadedDetail
            timeline = (try? await loadedTimeline) ?? []
        }
        catch { message = error.localizedDescription }
    }

    private func timelineIcon(_ type: String) -> String {
        switch type {
        case "account_created": return "person.crop.circle.badge.checkmark"
        case "onboarding": return "checklist"
        case "session": return "timer"
        case "experiment": return "flask"
        case "support": return "bubble.left.and.exclamationmark.bubble.right"
        default: return "waveform.path.ecg"
        }
    }

    private func timelineDate(_ value: String) -> String {
        guard let date = ISO8601DateFormatter().date(from: value) else { return value }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    private func reset() async {
        do {
            try await MivoBackendService.resetUserProgress(userID: user.userId, reason: "Reset from Mivo super-admin settings")
            message = "Progress reset completed."
            await load()
        } catch { message = error.localizedDescription }
    }

    private func delete() async {
        do {
            try await MivoBackendService.deleteUser(userID: user.userId, reason: "Deleted from Mivo super-admin settings")
            message = "Account deleted."
        } catch { message = error.localizedDescription }
    }
}

struct AdminSessionEditor: View {
    let userID: String
    let session: AdminSessionRecord
    let didSave: () async -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var planned: Int
    @State private var actual: Int
    @State private var reflection: String
    @State private var note: String
    @State private var reason = "Corrected by Mivo super-admin"
    @State private var message: String?

    init(userID: String, session: AdminSessionRecord, didSave: @escaping () async -> Void) {
        self.userID = userID
        self.session = session
        self.didSave = didSave
        _planned = State(initialValue: session.plannedDuration)
        _actual = State(initialValue: session.actualDuration)
        _reflection = State(initialValue: session.reflection ?? "")
        _note = State(initialValue: session.reflectionNote)
    }

    var body: some View {
        NavigationStack {
            Form {
                Stepper("Planned: \(planned) min", value: $planned, in: 0...1440)
                Stepper("Actual: \(actual) min", value: $actual, in: 0...1440)
                Picker("Reflection", selection: $reflection) {
                    Text("None").tag("")
                    Text("Yes").tag("Yes")
                    Text("Kind of").tag("Kind of")
                    Text("No").tag("No")
                }
                TextField("Reflection note", text: $note, axis: .vertical)
                TextField("Audit reason", text: $reason, axis: .vertical)
            }
            .navigationTitle("Edit session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { Task { await save() } }.disabled(reason.isEmpty) }
            }
            .alert("Session", isPresented: Binding(
                get: { message != nil }, set: { if !$0 { message = nil } }
            )) { Button("OK", role: .cancel) {} } message: { Text(message ?? "") }
        }
    }

    private func save() async {
        var updated = session
        updated.plannedDuration = planned
        updated.actualDuration = actual
        updated.reflection = reflection.isEmpty ? nil : reflection
        updated.reflectionNote = note
        do {
            try await MivoBackendService.updateSession(userID: userID, session: updated, reason: reason)
            await didSave()
            dismiss()
        } catch { message = error.localizedDescription }
    }
}

struct AnnouncementAdminView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appVM: AppViewModel
    @State private var announcements: [MivoAnnouncement] = []
    @State private var title = ""
    @State private var bodyText = ""
    @State private var publishNow = true
    @State private var hasExpiration = false
    @State private var expiration = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
    @State private var isLoading = true
    @State private var message: String?
    @State private var editingAnnouncement: MivoAnnouncement?

    var body: some View {
        ZStack {
            MivoColors.background.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) { composer; history }
                    .padding(16).padding(.bottom, 30)
            }
            if isLoading { MivoLoadingOverlay(message: "Loading announcements...") }
        }
        .navigationTitle("Announcements")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
        .onChange(of: appVM.canManageAnnouncements) { _, allowed in
            if !allowed { dismiss() }
        }
        .alert("Announcements", isPresented: Binding(
            get: { message != nil }, set: { if !$0 { message = nil } }
        )) { Button("OK", role: .cancel) {} } message: { Text(message ?? "") }
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Label(editingAnnouncement == nil ? "New announcement" : "Edit draft", systemImage: "megaphone.fill")
                    .font(.system(size: 17, weight: .bold))
                Spacer()
                if editingAnnouncement != nil {
                    Button("Cancel edit") { resetComposer() }
                        .font(.system(size: 12, weight: .bold))
                }
            }
            TextField("Title", text: $title).textFieldStyle(.roundedBorder)
            TextField("Message for all Mivo users", text: $bodyText, axis: .vertical)
                .lineLimit(4...8).textFieldStyle(.roundedBorder)
            if appVM.isSuperAdminUser && editingAnnouncement == nil {
                Toggle("Publish immediately", isOn: $publishNow).tint(MivoColors.accent)
            } else if !appVM.isSuperAdminUser {
                Label("Saved as a draft for founder approval", systemImage: "checkmark.shield.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(MivoColors.textSecondary)
            }
            Toggle("Set expiration", isOn: $hasExpiration).tint(MivoColors.accent)
            if hasExpiration { DatePicker("Expires", selection: $expiration, in: Date()...) }
            Button { Task { await saveAnnouncement() } } label: {
                let willPublish = appVM.isSuperAdminUser && publishNow && editingAnnouncement == nil
                Label(
                    editingAnnouncement == nil ? (willPublish ? "Publish to Everyone" : "Save Draft") : "Update Draft",
                    systemImage: willPublish ? "paperplane.fill" : "doc.fill"
                )
                    .font(.system(size: 15, weight: .bold))
                    .frame(maxWidth: .infinity).padding(.vertical, 13)
            }
            .buttonStyle(.borderedProminent).tint(MivoColors.accent)
            .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .adminPanelStyle()
    }

    private var history: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("History").font(.system(size: 17, weight: .bold)).padding(.bottom, 12)
            if announcements.isEmpty {
                Text("No announcements yet.").font(.system(size: 13)).foregroundColor(MivoColors.textSecondary).padding(.vertical, 12)
            } else {
                ForEach(Array(announcements.enumerated()), id: \.element.id) { index, item in
                    if index > 0 { Divider().overlay(MivoColors.border) }
                    VStack(alignment: .leading, spacing: 7) {
                        HStack {
                            Text(item.title).font(.system(size: 14, weight: .bold))
                            Spacer()
                            Text(item.status.capitalized)
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(item.status == "published" ? MivoColors.blue : MivoColors.textMuted)
                        }
                        Text(item.body).font(.system(size: 12)).foregroundColor(MivoColors.textSecondary).lineLimit(3)
                        if item.status == "draft" {
                            HStack(spacing: 16) {
                                Button("Edit") { beginEditing(item) }
                                    .font(.system(size: 12, weight: .bold))
                                if appVM.isSuperAdminUser {
                                    Button("Publish") { Task { await changeStatus(item, to: "published") } }
                                        .font(.system(size: 12, weight: .bold))
                                }
                            }
                        } else if item.status == "published" {
                            if appVM.isSuperAdminUser {
                                Button("Archive", role: .destructive) { Task { await changeStatus(item, to: "archived") } }
                                    .font(.system(size: 12, weight: .bold))
                            }
                        }
                    }.padding(.vertical, 12)
                }
            }
        }.adminPanelStyle()
    }

    private func load() async {
        isLoading = true
        do {
            try await appVM.prepareAuthenticatedSession()
            announcements = try await MivoBackendService.adminAnnouncements()
        } catch { message = error.localizedDescription }
        isLoading = false
    }

    private func saveAnnouncement() async {
        do {
            try await appVM.prepareAuthenticatedSession()
            let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
            let cleanBody = bodyText.trimmingCharacters(in: .whitespacesAndNewlines)
            if let editingAnnouncement {
                _ = try await MivoBackendService.updateAnnouncementDraft(
                    id: editingAnnouncement.id,
                    title: cleanTitle,
                    body: cleanBody,
                    expiresAt: hasExpiration ? expiration : nil
                )
                message = "Announcement draft updated."
            } else {
                let willPublish = appVM.isSuperAdminUser && publishNow
                _ = try await MivoBackendService.createAnnouncement(
                    title: cleanTitle,
                    body: cleanBody,
                    expiresAt: hasExpiration ? expiration : nil,
                    publishNow: willPublish
                )
                message = willPublish ? "Announcement published to Mivo users." : "Announcement draft saved for founder approval."
            }
            resetComposer()
            await load()
        } catch { message = error.localizedDescription }
    }

    private func beginEditing(_ announcement: MivoAnnouncement) {
        editingAnnouncement = announcement
        title = announcement.title
        bodyText = announcement.body
        if let rawDate = announcement.expiresAt,
           let date = ISO8601DateFormatter().date(from: rawDate) {
            hasExpiration = true
            expiration = date
        } else {
            hasExpiration = false
        }
    }

    private func resetComposer() {
        editingAnnouncement = nil
        title = ""
        bodyText = ""
        publishNow = true
        hasExpiration = false
        expiration = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
    }

    private func changeStatus(_ announcement: MivoAnnouncement, to status: String) async {
        do {
            try await appVM.prepareAuthenticatedSession()
            try await MivoBackendService.setAnnouncementStatus(id: announcement.id, status: status)
            await load()
        } catch { message = error.localizedDescription }
    }
}

struct AdminPushUserDestinationView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appVM: AppViewModel
    let userID: String
    @State private var user: AdminUserRecord?
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let user {
                AdminUserProgressView(user: user)
            } else if let errorMessage {
                ContentUnavailableView(
                    "User unavailable",
                    systemImage: "person.crop.circle.badge.exclamationmark",
                    description: Text(errorMessage)
                )
            } else {
                MivoLoadingOverlay(message: "Loading new account...")
            }
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
        }
        .task { await load() }
    }

    @MainActor
    private func load() async {
        guard isLoading else { return }
        do {
            try await appVM.prepareAuthenticatedSession()
            let dashboard = try await MivoBackendService.loadAdminUserDashboard()
            guard let match = dashboard.users.first(where: { $0.userId == userID }) else {
                throw MivoBackendError.server("user_not_found")
            }
            user = match
        } catch { errorMessage = error.localizedDescription }
        isLoading = false
    }
}

extension View {
    func adminPanelStyle() -> some View {
        self
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(MivoColors.card)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(MivoColors.border.opacity(0.7), lineWidth: 1))
    }
}
