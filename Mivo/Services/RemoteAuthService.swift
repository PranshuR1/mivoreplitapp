import Foundation

struct RemoteAuthUser: Codable {
    let email: String
    let name: String
    let createdAt: String
    let onboardingProfile: OnboardingProfile?
    let isAdmin: Bool?
    let adminToken: String?
    let remoteUserId: String?
    let accessToken: String?
    let refreshToken: String?

    init(
        email: String,
        name: String,
        createdAt: String,
        onboardingProfile: OnboardingProfile?,
        isAdmin: Bool?,
        adminToken: String?,
        remoteUserId: String? = nil,
        accessToken: String? = nil,
        refreshToken: String? = nil
    ) {
        self.email = email
        self.name = name
        self.createdAt = createdAt
        self.onboardingProfile = onboardingProfile
        self.isAdmin = isAdmin
        self.adminToken = adminToken
        self.remoteUserId = remoteUserId
        self.accessToken = accessToken
        self.refreshToken = refreshToken
    }
}

struct AdminUser: Codable, Identifiable {
    var id: String { email }
    let email: String
    let name: String
    let createdAt: String
    let onboardingProfile: OnboardingProfile?
    let isAdmin: Bool?
    let role: String?
    let lastLoginAt: String?
    let updatedAt: String?
}

struct PendingRegistration {
    let email: String
    let password: String
    let name: String
}

enum RemoteAuthService {
    struct UserStateSnapshot: Encodable {
        let profile: OnboardingProfile
        let settings: AppSettings
        let sessions: [Session]
        let truthChecks: [TruthCheckGuess]
        let dailyScrollSchedules: [DailyScrollSchedule]
        let weeklyReports: [WeeklyReportSnapshot]
        let appInterventionRules: [AppInterventionRule]
        let accountabilitySummary: AccountabilitySummary?
        let widgetSharedSummary: WidgetSharedSummary?
        let aiDataset: [String]
    }

    private struct AuthRequest: Codable {
        let email: String
        let password: String?
        let name: String?
        let onboardingProfile: OnboardingProfile?
    }

    private struct AdminRequest: Codable {
        let adminToken: String
        let targetEmail: String?
    }

    private struct AuthResponse: Codable {
        let ok: Bool?
        let exists: Bool?
        let user: RemoteAuthUser?
        let adminToken: String?
        let users: [AdminUser]?
        let error: String?
    }

    private struct SupabaseAuthResponse: Decodable {
        let accessToken: String?
        let refreshToken: String?
        let user: SupabaseUser?

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case refreshToken = "refresh_token"
            case user
        }
    }

    private struct SupabaseUser: Decodable {
        let id: String
        let email: String?
        let createdAt: String?
        let userMetadata: [String: String]?

        enum CodingKeys: String, CodingKey {
            case id
            case email
            case createdAt = "created_at"
            case userMetadata = "user_metadata"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(String.self, forKey: .id)
            email = try container.decodeIfPresent(String.self, forKey: .email)
            createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt)
            userMetadata = (try? container.decode([String: SupabaseMetadataValue].self, forKey: .userMetadata))?
                .compactMapValues(\.stringValue)
        }
    }

    private struct SupabaseMetadataValue: Decodable {
        let stringValue: String?

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let value = try? container.decode(String.self) {
                stringValue = value
            } else if let value = try? container.decode(Bool.self) {
                stringValue = value ? "true" : "false"
            } else if let value = try? container.decode(Int.self) {
                stringValue = String(value)
            } else if let value = try? container.decode(Double.self) {
                stringValue = String(value)
            } else {
                stringValue = nil
            }
        }
    }

    private struct SupabaseErrorResponse: Decodable {
        let code: Int?
        let errorCode: String?
        let message: String?
        let msg: String?

        enum CodingKeys: String, CodingKey {
            case code
            case errorCode = "error_code"
            case message
            case msg
        }
    }

    private struct SupabaseUserStateRow: Decodable {
        let profile: OnboardingProfile?
    }

    private struct SupabaseDeviceBindingRow: Decodable {
        let deviceID: String
        let userID: String

        enum CodingKeys: String, CodingKey {
            case deviceID = "device_id"
            case userID = "user_id"
        }
    }

    static var isConfigured: Bool {
        supabaseBaseURL != nil || baseURL != nil
    }

    private static var baseURL: URL? {
        if let raw = Bundle.main.object(forInfoDictionaryKey: "MIVO_AUTH_API_URL") as? String,
           !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return URL(string: raw.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        return nil
    }

    private static var supabaseBaseURL: URL? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "MIVO_SUPABASE_URL") as? String else { return nil }
        let trimmed = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/rest/v1/?$", with: "", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !trimmed.isEmpty else { return nil }
        return URL(string: trimmed)
    }

    private static var supabaseAnonKey: String {
        (Bundle.main.object(forInfoDictionaryKey: "MIVO_SUPABASE_ANON_KEY") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    static func register(email: String, password: String, name: String, onboardingProfile: OnboardingProfile?) async throws -> RemoteAuthUser {
        if supabaseBaseURL != nil {
            return try await supabaseRegister(email: email, password: password, name: name, onboardingProfile: onboardingProfile)
        }
        return try await request(
            path: "/auth/register",
            body: AuthRequest(email: email, password: password, name: name, onboardingProfile: onboardingProfile)
        )
    }

    static func login(email: String, password: String) async throws -> RemoteAuthUser {
        if supabaseBaseURL != nil {
            return try await supabaseLogin(email: email, password: password)
        }

        let response: AuthResponse = try await rawRequest(
            path: "/auth/login",
            body: AuthRequest(email: email, password: password, name: nil, onboardingProfile: nil)
        )
        guard let user = response.user else { throw AppError.accountDataMissing }
        return RemoteAuthUser(
            email: user.email,
            name: user.name,
            createdAt: user.createdAt,
            onboardingProfile: user.onboardingProfile,
            isAdmin: user.isAdmin,
            adminToken: response.adminToken,
            remoteUserId: user.remoteUserId,
            accessToken: user.accessToken,
            refreshToken: user.refreshToken
        )
    }

    static func claimDevice(installationID: String, user: RemoteAuthUser) async throws {
        guard let base = supabaseBaseURL else { return }
        guard let userID = user.remoteUserId,
              let bearer = user.accessToken,
              !userID.isEmpty,
              !bearer.isEmpty else {
            throw AppError.accountDataMissing
        }

        let now = ISO8601DateFormatter().string(from: Date())
        var request = URLRequest(url: base.appendingPathComponent("rest/v1/device_bindings"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("return=minimal", forHTTPHeaderField: "Prefer")
        applySupabaseHeaders(to: &request, bearer: bearer)
        request.httpBody = try JSONSerialization.data(withJSONObject: [[
            "device_id": installationID,
            "user_id": userID,
            "account_email": user.email.lowercased(),
            "created_at": now,
            "last_seen_at": now
        ]])

        let response: URLResponse
        do {
            (_, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw AppError.remoteAuthUnavailable
        }

        let status = (response as? HTTPURLResponse)?.statusCode ?? 500
        if (200..<300).contains(status) { return }
        guard status == 409 else { throw AppError.remoteAuthUnavailable }

        guard let encodedID = installationID.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let lookupURL = URL(string: "\(base.absoluteString)/rest/v1/device_bindings?select=device_id,user_id&device_id=eq.\(encodedID)&limit=1") else {
            throw AppError.remoteAuthUnavailable
        }
        var lookup = URLRequest(url: lookupURL)
        lookup.httpMethod = "GET"
        applySupabaseHeaders(to: &lookup, bearer: bearer)

        let data: Data
        let lookupResponse: URLResponse
        do {
            (data, lookupResponse) = try await URLSession.shared.data(for: lookup)
        } catch {
            throw AppError.remoteAuthUnavailable
        }

        let lookupStatus = (lookupResponse as? HTTPURLResponse)?.statusCode ?? 500
        guard (200..<300).contains(lookupStatus) else { throw AppError.remoteAuthUnavailable }
        let rows = (try? JSONDecoder().decode([SupabaseDeviceBindingRow].self, from: data)) ?? []
        guard rows.contains(where: { $0.deviceID == installationID && $0.userID == userID }) else {
            throw AppError.deviceBoundToAnotherAccount(hint: nil)
        }

    }

    static func accountExists(email: String) async throws -> Bool {
        guard supabaseBaseURL == nil else { return false }
        let response: AuthResponse = try await rawRequest(
            path: "/auth/exists",
            body: AuthRequest(email: email, password: nil, name: nil, onboardingProfile: nil)
        )
        return response.exists == true
    }

    static func validateStoredSession(record: SecureAuthRecord) async throws -> RemoteAuthUser {
        guard supabaseBaseURL != nil else { throw AppError.remoteAuthUnavailable }
        guard let accessToken = record.remoteAccessToken, !accessToken.isEmpty else {
            throw AppError.invalidCredentials
        }

        do {
            return try await supabaseCurrentUser(
                accessToken: accessToken,
                refreshToken: record.remoteRefreshToken,
                fallback: record
            )
        } catch AppError.invalidCredentials {
            guard let refreshToken = record.remoteRefreshToken, !refreshToken.isEmpty else {
                throw AppError.invalidCredentials
            }
            let refreshed = try await supabaseRefreshSession(refreshToken: refreshToken)
            return RemoteAuthUser(
                email: refreshed.email,
                name: refreshed.name,
                createdAt: refreshed.createdAt,
                onboardingProfile: record.onboardingProfile,
                isAdmin: record.isAdmin,
                adminToken: record.adminToken,
                remoteUserId: refreshed.remoteUserId,
                accessToken: refreshed.accessToken,
                refreshToken: refreshed.refreshToken
            )
        }
    }

    static func resetPassword(email: String, newPassword: String) async throws {
        guard supabaseBaseURL == nil else { throw AppError.remoteAuthUnavailable }
        let _: AuthResponse = try await rawRequest(
            path: "/auth/reset-password",
            body: AuthRequest(email: email, password: newPassword, name: nil, onboardingProfile: nil)
        )
    }

    static func saveProfile(email: String, onboardingProfile: OnboardingProfile) async {
        if supabaseBaseURL != nil, let record = SecureAuthService.loadRecord(email: email) {
            await saveUserState(email: email, name: record.name, snapshot: nil, profile: onboardingProfile, record: record)
            return
        }

        let _: AuthResponse? = try? await rawRequest(
            path: "/auth/profile",
            body: AuthRequest(email: email, password: nil, name: nil, onboardingProfile: onboardingProfile)
        )
    }

    static func saveUserState(email: String, name: String, snapshot: UserStateSnapshot, record: SecureAuthRecord) async {
        await saveUserState(email: email, name: name, snapshot: snapshot, profile: snapshot.profile, record: record)
    }

    private static func saveUserState(
        email: String,
        name: String,
        snapshot: UserStateSnapshot?,
        profile: OnboardingProfile,
        record: SecureAuthRecord
    ) async {
        guard let base = supabaseBaseURL,
              !supabaseAnonKey.isEmpty,
              let userId = record.remoteUserId,
              let token = record.remoteAccessToken else { return }

        await upsertRows(
            table: "user_profiles",
            onConflict: "user_id",
            rows: [[
                "user_id": userId,
                "email": email,
                "name": name,
                "created_at": record.createdAt,
                "updated_at": ISO8601DateFormatter().string(from: Date())
            ]],
            bearer: token,
            base: base
        )

        await upsertRows(
            table: "onboarding_profiles",
            onConflict: "user_id",
            rows: [onboardingRow(userId: userId, profile: profile)],
            bearer: token,
            base: base
        )

        if let snapshot {
            await upsertRows(
                table: "app_settings",
                onConflict: "user_id",
                rows: [settingsRow(userId: userId, settings: snapshot.settings)],
                bearer: token,
                base: base
            )
            await upsertRows(
                table: "sessions",
                onConflict: "user_id,id",
                rows: snapshot.sessions.map { sessionRow(userId: userId, session: $0) },
                bearer: token,
                base: base
            )
            await upsertRows(
                table: "truth_checks",
                onConflict: "user_id,id",
                rows: snapshot.truthChecks.map { truthCheckRow(userId: userId, check: $0) },
                bearer: token,
                base: base
            )
            await upsertRows(
                table: "daily_scroll_schedules",
                onConflict: "user_id,id",
                rows: snapshot.dailyScrollSchedules.map { dailyScheduleRow(userId: userId, schedule: $0) },
                bearer: token,
                base: base
            )
            await upsertRows(
                table: "weekly_reports",
                onConflict: "user_id,id",
                rows: snapshot.weeklyReports.map { weeklyReportRow(userId: userId, report: $0) },
                bearer: token,
                base: base
            )
            await upsertRows(
                table: "app_intervention_rules",
                onConflict: "user_id,id",
                rows: snapshot.appInterventionRules.map { appRuleRow(userId: userId, rule: $0) },
                bearer: token,
                base: base
            )
            await upsertRows(
                table: "user_summaries",
                onConflict: "user_id",
                rows: [summaryRow(
                    userId: userId,
                    accountability: snapshot.accountabilitySummary,
                    widget: snapshot.widgetSharedSummary
                )],
                bearer: token,
                base: base
            )
            await upsertRows(
                table: "ai_summary_entries",
                onConflict: "user_id,entry_index",
                rows: snapshot.aiDataset.enumerated().map {
                    [
                        "user_id": userId,
                        "entry_index": $0.offset,
                        "summary": $0.element,
                        "updated_at": ISO8601DateFormatter().string(from: Date())
                    ]
                },
                bearer: token,
                base: base
            )
        }

        await upsertUserState(
            email: email,
            name: name,
            userId: userId,
            snapshot: snapshot,
            profile: profile,
            bearer: token,
            base: base
        )
    }

    private static func upsertUserState(
        email: String,
        name: String,
        userId: String,
        snapshot: UserStateSnapshot?,
        profile: OnboardingProfile,
        bearer: String,
        base: URL
    ) async {
        var payload: [String: Any] = [
            "user_id": userId,
            "email": email,
            "name": name,
            "profile": jsonObject(profile),
            "updated_at": ISO8601DateFormatter().string(from: Date())
        ]

        if let snapshot {
            payload["settings"] = jsonObject(snapshot.settings)
            payload["sessions"] = jsonObject(snapshot.sessions)
            payload["truth_checks"] = jsonObject(snapshot.truthChecks)
            payload["daily_scroll_schedules"] = jsonObject(snapshot.dailyScrollSchedules)
            payload["weekly_reports"] = jsonObject(snapshot.weeklyReports)
            payload["app_intervention_rules"] = jsonObject(snapshot.appInterventionRules)
            payload["accountability_summary"] = snapshot.accountabilitySummary.map { jsonObject($0) } ?? NSNull()
            payload["widget_shared_summary"] = snapshot.widgetSharedSummary.map { jsonObject($0) } ?? NSNull()
            payload["ai_dataset"] = jsonObject(snapshot.aiDataset)
        }

        await upsertRows(table: "user_state", onConflict: "user_id", rows: [payload], bearer: bearer, base: base)
    }

    private static func upsertRows(
        table: String,
        onConflict: String,
        rows: [[String: Any]],
        bearer: String,
        base: URL
    ) async {
        guard !rows.isEmpty,
              let encodedConflict = onConflict.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "\(base.absoluteString)/rest/v1/\(table)?on_conflict=\(encodedConflict)") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        applySupabaseHeaders(to: &request, bearer: bearer)
        request.setValue("resolution=merge-duplicates", forHTTPHeaderField: "Prefer")
        request.httpBody = try? JSONSerialization.data(withJSONObject: rows)
        _ = try? await URLSession.shared.data(for: request)
    }

    private static func onboardingRow(userId: String, profile: OnboardingProfile) -> [String: Any] {
        [
            "user_id": userId,
            "observation_started_at": nullIfNil(profile.observationStartedAt),
            "referral_source": nullIfNil(profile.referralSource),
            "referral_ambassador_name": nullIfNil(profile.referralAmbassadorName),
            "referral_campaign_code": nullIfNil(profile.referralCode),
            "primary_intention": nullIfNil(profile.primaryIntention?.rawValue),
            "scroll_estimate_minutes": nullIfNil(profile.scrollEstimateMinutes),
            "preferred_apps": profile.preferredApps,
            "preferred_scroll_windows": jsonObject(profile.preferredScrollWindows ?? []),
            "intentions": profile.intentions.map(\.rawValue),
            "age": nullIfNil(profile.age),
            "age_range": nullIfNil(profile.ageRange),
            "check_in_interval_minutes": nullIfNil(profile.checkInIntervalMinutes),
            "daily_scroll_goal_minutes": nullIfNil(profile.dailyScrollGoalMinutes),
            "raw_profile": jsonObject(profile),
            "updated_at": ISO8601DateFormatter().string(from: Date())
        ]
    }

    private static func settingsRow(userId: String, settings: AppSettings) -> [String: Any] {
        [
            "user_id": userId,
            "onboarding_complete": settings.onboardingComplete,
            "notifications_enabled": settings.notificationsEnabled,
            "tutorial_complete": nullIfNil(settings.tutorialComplete),
            "notifications_choice_made": nullIfNil(settings.notificationsChoiceMade),
            "accountability_enabled": nullIfNil(settings.accountabilityEnabled),
            "check_in_interval_minutes": nullIfNil(settings.checkInIntervalMinutes),
            "raw_settings": jsonObject(settings),
            "updated_at": ISO8601DateFormatter().string(from: Date())
        ]
    }

    private static func sessionRow(userId: String, session: Session) -> [String: Any] {
        [
            "user_id": userId,
            "id": session.id,
            "date": session.date,
            "start_time": session.startTime,
            "end_time": session.endTime,
            "planned_duration": session.plannedDuration,
            "actual_duration": session.actualDuration,
            "intention": session.intention.rawValue,
            "extended_once": session.extendedOnce,
            "reflection": nullIfNil(session.reflection?.rawValue),
            "reflection_note": session.reflectionNote,
            "urge_reason": nullIfNil(session.urgeReason?.rawValue),
            "urge_note": nullIfNil(session.urgeNote),
            "outcome_score": nullIfNil(session.outcomeScore?.rawValue),
            "emergency_unlock_used": nullIfNil(session.emergencyUnlockUsed),
            "emergency_unlock_reason": nullIfNil(session.emergencyUnlockReason),
            "raw_session": jsonObject(session),
            "updated_at": ISO8601DateFormatter().string(from: Date())
        ]
    }

    private static func truthCheckRow(userId: String, check: TruthCheckGuess) -> [String: Any] {
        [
            "user_id": userId,
            "id": check.id,
            "date": check.date,
            "guess": check.guess,
            "actual": check.actual,
            "raw_truth_check": jsonObject(check),
            "updated_at": ISO8601DateFormatter().string(from: Date())
        ]
    }

    private static func dailyScheduleRow(userId: String, schedule: DailyScrollSchedule) -> [String: Any] {
        [
            "user_id": userId,
            "id": schedule.id,
            "date": schedule.date,
            "windows": jsonObject(schedule.windows),
            "created_at": schedule.createdAt,
            "raw_schedule": jsonObject(schedule),
            "updated_at": ISO8601DateFormatter().string(from: Date())
        ]
    }

    private static func weeklyReportRow(userId: String, report: WeeklyReportSnapshot) -> [String: Any] {
        [
            "user_id": userId,
            "id": report.id,
            "week_start": report.weekStart,
            "week_end": report.weekEnd,
            "total_minutes": report.totalMinutes,
            "recovered_minutes": report.recoveredMinutes,
            "session_count": report.sessionCount,
            "top_urge_reason": nullIfNil(report.topUrgeReason?.rawValue),
            "hardest_window": report.hardestWindow,
            "extended_count": report.extendedCount,
            "emergency_unlock_count": report.emergencyUnlockCount,
            "recommendation": report.recommendation,
            "raw_report": jsonObject(report),
            "updated_at": ISO8601DateFormatter().string(from: Date())
        ]
    }

    private static func appRuleRow(userId: String, rule: AppInterventionRule) -> [String: Any] {
        [
            "user_id": userId,
            "id": rule.id,
            "app_name": rule.appName,
            "mode": rule.mode.rawValue,
            "raw_rule": jsonObject(rule),
            "updated_at": ISO8601DateFormatter().string(from: Date())
        ]
    }

    private static func summaryRow(
        userId: String,
        accountability: AccountabilitySummary?,
        widget: WidgetSharedSummary?
    ) -> [String: Any] {
        [
            "user_id": userId,
            "accountability_week_start": nullIfNil(accountability?.weekStart),
            "accountability_week_end": nullIfNil(accountability?.weekEnd),
            "accountability_share_text": nullIfNil(accountability?.shareText),
            "widget_recovered_minutes_today": nullIfNil(widget?.recoveredMinutesToday),
            "widget_screen_time_minutes_today": nullIfNil(widget?.screenTimeMinutesToday),
            "widget_next_scroll_window": nullIfNil(widget?.nextScrollWindow),
            "widget_plan_state": nullIfNil(widget?.planState),
            "widget_streak_text": nullIfNil(widget?.streakText),
            "widget_updated_at": nullIfNil(widget?.updatedAt),
            "accountability_summary": accountability.map { jsonObject($0) } ?? NSNull(),
            "widget_shared_summary": widget.map { jsonObject($0) } ?? NSNull(),
            "updated_at": ISO8601DateFormatter().string(from: Date())
        ]
    }

    static func adminUsers(adminToken: String) async throws -> [AdminUser] {
        let response: AuthResponse = try await rawRequest(
            path: "/auth/admin/users",
            body: AdminRequest(adminToken: adminToken, targetEmail: nil)
        )
        return response.users ?? []
    }

    static func adminUser(adminToken: String, email: String) async throws -> AdminUser {
        let response: AuthResponse = try await rawRequest(
            path: "/auth/admin/user",
            body: AdminRequest(adminToken: adminToken, targetEmail: email)
        )
        guard let user = response.user else { throw AppError.noAccount }
        return AdminUser(
            email: user.email,
            name: user.name,
            createdAt: user.createdAt,
            onboardingProfile: user.onboardingProfile,
            isAdmin: user.isAdmin,
            role: nil,
            lastLoginAt: nil,
            updatedAt: nil
        )
    }

    static func adminDeleteUser(adminToken: String, email: String) async throws {
        let _: AuthResponse = try await rawRequest(
            path: "/auth/admin/delete-user",
            body: AdminRequest(adminToken: adminToken, targetEmail: email)
        )
    }

    private static func request(path: String, body: AuthRequest) async throws -> RemoteAuthUser {
        let response: AuthResponse = try await rawRequest(path: path, body: body)
        guard let user = response.user else { throw AppError.accountDataMissing }
        return user
    }

    private static func supabaseRegister(email: String, password: String, name: String, onboardingProfile: OnboardingProfile?) async throws -> RemoteAuthUser {
        guard let base = supabaseBaseURL, !supabaseAnonKey.isEmpty else { throw AppError.remoteAuthUnavailable }
        let url = base.appendingPathComponent("auth/v1/signup")
        let response: SupabaseAuthResponse = try await supabaseAuthRequest(
            url: url,
            body: [
                "email": email,
                "password": password,
                "data": ["name": name]
            ]
        )

        guard let user = response.user, let userEmail = user.email ?? Optional(email) else {
            throw AppError.accountDataMissing
        }

        if response.accessToken == nil {
            return try await supabaseLogin(email: email, password: password)
        }

        let isAdmin = await fetchSupabaseAdminRole(userId: user.id, accessToken: response.accessToken)
        return RemoteAuthUser(
            email: userEmail,
            name: user.userMetadata?["name"] ?? name,
            createdAt: user.createdAt ?? ISO8601DateFormatter().string(from: Date()),
            onboardingProfile: onboardingProfile,
            isAdmin: isAdmin,
            adminToken: nil,
            remoteUserId: user.id,
            accessToken: response.accessToken,
            refreshToken: response.refreshToken
        )
    }

    private static func supabaseLogin(email: String, password: String) async throws -> RemoteAuthUser {
        guard let base = supabaseBaseURL, !supabaseAnonKey.isEmpty else { throw AppError.remoteAuthUnavailable }
        let url = URL(string: "\(base.absoluteString)/auth/v1/token?grant_type=password")!
        let response: SupabaseAuthResponse = try await supabaseAuthRequest(
            url: url,
            body: ["email": email, "password": password]
        )

        guard let user = response.user, let userEmail = user.email ?? Optional(email) else {
            throw AppError.invalidCredentials
        }

        let profile = await fetchSupabaseProfile(userId: user.id, accessToken: response.accessToken)
        let isAdmin = await fetchSupabaseAdminRole(userId: user.id, accessToken: response.accessToken)
        return RemoteAuthUser(
            email: userEmail,
            name: user.userMetadata?["name"] ?? String(userEmail.split(separator: "@").first ?? "Mivo"),
            createdAt: user.createdAt ?? ISO8601DateFormatter().string(from: Date()),
            onboardingProfile: profile,
            isAdmin: isAdmin,
            adminToken: nil,
            remoteUserId: user.id,
            accessToken: response.accessToken,
            refreshToken: response.refreshToken
        )
    }

    private static func supabaseCurrentUser(
        accessToken: String,
        refreshToken: String?,
        fallback record: SecureAuthRecord
    ) async throws -> RemoteAuthUser {
        guard let base = supabaseBaseURL, !supabaseAnonKey.isEmpty else { throw AppError.remoteAuthUnavailable }
        let url = base.appendingPathComponent("auth/v1/user")

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        applySupabaseHeaders(to: &request, bearer: accessToken)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw AppError.remoteAuthUnavailable
        }

        let status = (response as? HTTPURLResponse)?.statusCode ?? 500
        guard (200..<300).contains(status) else {
            if status == 401 || status == 403 || status == 404 {
                throw AppError.invalidCredentials
            }
            throw AppError.remoteAuthUnavailable
        }

        guard let user = try? JSONDecoder().decode(SupabaseUser.self, from: data),
              let userEmail = user.email ?? Optional(record.email) else {
            throw AppError.accountDataMissing
        }

        let isAdmin = await fetchSupabaseAdminRole(userId: user.id, accessToken: accessToken)
        return RemoteAuthUser(
            email: userEmail,
            name: user.userMetadata?["name"] ?? record.name,
            createdAt: user.createdAt ?? record.createdAt,
            onboardingProfile: record.onboardingProfile,
            isAdmin: isAdmin,
            adminToken: record.adminToken,
            remoteUserId: user.id,
            accessToken: accessToken,
            refreshToken: refreshToken
        )
    }

    private static func supabaseRefreshSession(refreshToken: String) async throws -> RemoteAuthUser {
        guard let base = supabaseBaseURL, !supabaseAnonKey.isEmpty else { throw AppError.remoteAuthUnavailable }
        let url = URL(string: "\(base.absoluteString)/auth/v1/token?grant_type=refresh_token")!
        let response: SupabaseAuthResponse = try await supabaseAuthRequest(
            url: url,
            body: ["refresh_token": refreshToken]
        )

        guard let user = response.user, let userEmail = user.email else {
            throw AppError.invalidCredentials
        }

        let profile = await fetchSupabaseProfile(userId: user.id, accessToken: response.accessToken)
        let isAdmin = await fetchSupabaseAdminRole(userId: user.id, accessToken: response.accessToken)
        return RemoteAuthUser(
            email: userEmail,
            name: user.userMetadata?["name"] ?? String(userEmail.split(separator: "@").first ?? "Mivo"),
            createdAt: user.createdAt ?? ISO8601DateFormatter().string(from: Date()),
            onboardingProfile: profile,
            isAdmin: isAdmin,
            adminToken: nil,
            remoteUserId: user.id,
            accessToken: response.accessToken,
            refreshToken: response.refreshToken
        )
    }

    private static func fetchSupabaseProfile(userId: String, accessToken: String?) async -> OnboardingProfile? {
        guard let base = supabaseBaseURL,
              let token = accessToken,
              let encodedUserId = userId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "\(base.absoluteString)/rest/v1/user_state?select=profile&user_id=eq.\(encodedUserId)&limit=1") else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        applySupabaseHeaders(to: &request, bearer: token)

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              let rows = try? JSONDecoder().decode([SupabaseUserStateRow].self, from: data) else { return nil }

        return rows.first?.profile
    }

    private static func fetchSupabaseAdminRole(userId: String, accessToken: String?) async -> Bool {
        guard let base = supabaseBaseURL,
              let token = accessToken,
              let encodedUserId = userId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "\(base.absoluteString)/rest/v1/app_admins?select=role&user_id=eq.\(encodedUserId)&limit=1") else {
            return false
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        applySupabaseHeaders(to: &request, bearer: token)
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return false
        }
        guard let role = rows.first?["role"] as? String else { return false }
        return role == "super_admin" || role == "admin"
    }

    private static func supabaseAuthRequest<Response: Decodable>(url: URL, body: [String: Any]) async throws -> Response {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        applySupabaseHeaders(to: &request, bearer: supabaseAnonKey)
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw AppError.remoteAuthUnavailable
        }

        let status = (response as? HTTPURLResponse)?.statusCode ?? 500
        guard (200..<300).contains(status) else {
            let supabaseError = try? JSONDecoder().decode(SupabaseErrorResponse.self, from: data)
            let errorCode = supabaseError?.errorCode?.lowercased()
            let message = (supabaseError?.message ?? supabaseError?.msg ?? "").lowercased()

            if status == 429 || errorCode == "over_email_send_rate_limit" {
                throw AppError.signupEmailRateLimited
            }
            if errorCode == "email_not_confirmed" || message.contains("email not confirmed") {
                throw AppError.emailConfirmationRequired
            }
            if status == 400 || status == 401 { throw AppError.invalidCredentials }
            if status == 422 { throw AppError.emailAlreadyExists }
            throw AppError.remoteAuthUnavailable
        }

        guard let decoded = try? JSONDecoder().decode(Response.self, from: data) else {
            throw AppError.accountDataMissing
        }
        return decoded
    }

    private static func applySupabaseHeaders(to request: inout URLRequest, bearer: String) {
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 12
    }

    private static func jsonObject<T: Encodable>(_ value: T) -> Any {
        guard let data = try? JSONEncoder().encode(value),
              let object = try? JSONSerialization.jsonObject(with: data) else {
            return NSNull()
        }
        return object
    }

    private static func nullIfNil(_ value: Any?) -> Any {
        value ?? NSNull()
    }

    private static func rawRequest<Response: Decodable, Body: Encodable>(path: String, body: Body) async throws -> Response {
        guard let baseURL else { throw AppError.remoteAuthUnavailable }
        let url = baseURL.appendingPathComponent(path.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 12
        request.httpBody = try JSONEncoder().encode(body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw AppError.remoteAuthUnavailable
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 500
        let decoded = try? JSONDecoder().decode(AuthResponse.self, from: data)

        guard (200..<300).contains(status) else {
            switch decoded?.error {
            case "emailAlreadyExists": throw AppError.emailAlreadyExists
            case "invalidCredentials": throw AppError.invalidCredentials
            case "noAccount": throw AppError.noAccount
            case "weakPassword": throw AppError.weakPassword
            case "adminRequired", "cannotDeleteAdmin": throw AppError.adminRequired
            default: throw AppError.remoteAuthUnavailable
            }
        }

        guard let typed = try? JSONDecoder().decode(Response.self, from: data) else {
            throw AppError.accountDataMissing
        }
        return typed
    }
}
