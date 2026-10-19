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
    /// Only populated by the Supabase login/refresh paths (see
    /// `fetchSupabaseUserState`) — lets `completeLogin` restore
    /// `onboardingComplete` and the rest of `AppSettings` on a device that
    /// has never locally synced them (e.g. right after a reinstall), instead
    /// of silently falling back to "onboarding not complete" for an account
    /// that already finished it.
    let settings: AppSettings?
    /// Everything else `user_state` holds beyond profile/settings — see
    /// `RestoredUserState`. Only populated by the same Supabase login/refresh
    /// paths as `settings` above, for the same reinstall-restore reason.
    let restoredState: RestoredUserState?

    init(
        email: String,
        name: String,
        createdAt: String,
        onboardingProfile: OnboardingProfile?,
        isAdmin: Bool?,
        adminToken: String?,
        remoteUserId: String? = nil,
        accessToken: String? = nil,
        refreshToken: String? = nil,
        settings: AppSettings? = nil,
        restoredState: RestoredUserState? = nil
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
        self.settings = settings
        self.restoredState = restoredState
    }
}

/// Everything `user_state` holds beyond `profile`/`settings` — pulled back
/// on login so a fresh install doesn't lose session history, truth checks,
/// scroll schedules, weekly reports, intervention rules, and both summaries
/// that were already being pushed to Supabase but never read back.
struct RestoredUserState: Codable {
    var profile: OnboardingProfile?
    var settings: AppSettings?
    var sessions: [Session]?
    var truthChecks: [TruthCheckGuess]?
    var dailyScrollSchedules: [DailyScrollSchedule]?
    var weeklyReports: [WeeklyReportSnapshot]?
    var appInterventionRules: [AppInterventionRule]?
    var accountabilitySummary: AccountabilitySummary?
    var widgetSharedSummary: WidgetSharedSummary?
    var aiDataset: [String]?
    var mivoStillSessions: [MivoStillSession]?
    var appFrictionProfiles: [AppFrictionProfile]?
    var userSwap: UserSwap?
    var interventionAttempts: [InterventionAttemptRecord]?
    var dailyScreenTimeObservations: [DailyScreenTimeObservation]?
    var timeLoans: [TimeLoan]?
    var intentGameHistory: [IntentGameHistoryEntry]?
    var dropPathTimeAdjustments: [DropPathTimeAdjustment]?
    var recallCheckIns: [RecallCheckIn]?
    var instagramWrapperSessions: [InstagramWrapperSession]?
    var instagramRecallPrompts: [InstagramRecallPrompt]?
}

/// A "Block my iPhone too" command written by the Mac companion app to
/// `cross_device_focus_sessions`. See `mivomac/IPHONE_FOCUS_RECEIVER.md`
/// for the full contract and `CrossDeviceFocusService` for how it's
/// applied/cleared.
struct CrossDeviceFocusCommand: Decodable {
    let id: String
    let sourceDevice: String
    let intention: String
    let mode: String
    let startsAt: Date
    let endsAt: Date
    let status: String
    let blockPhone: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case sourceDevice = "source_device"
        case intention, mode
        case startsAt = "starts_at"
        case endsAt = "ends_at"
        case status
        case blockPhone = "block_phone"
    }

    /// `starts_at`/`ends_at` come back from Postgres as `timestamptz`, which
    /// can include a fractional-second component — Foundation's default
    /// `.iso8601` `JSONDecoder` strategy (what this used to rely on) can't
    /// parse those and fails the whole decode silently (`try?` upstream in
    /// `fetchActiveCrossDeviceFocusCommand`), which reads identically to
    /// "no active command" — a real block from Mac would just never show up
    /// on the phone with no error anywhere. Parsing the two date fields by
    /// hand, with a fractional-seconds-tolerant fallback, removes that
    /// silent-failure path entirely.
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        sourceDevice = try values.decode(String.self, forKey: .sourceDevice)
        intention = try values.decode(String.self, forKey: .intention)
        mode = try values.decode(String.self, forKey: .mode)
        status = try values.decode(String.self, forKey: .status)
        blockPhone = try values.decode(Bool.self, forKey: .blockPhone)
        let startsAtRaw = try values.decode(String.self, forKey: .startsAt)
        let endsAtRaw = try values.decode(String.self, forKey: .endsAt)
        guard let parsedStartsAt = Self.parseDate(startsAtRaw), let parsedEndsAt = Self.parseDate(endsAtRaw) else {
            throw DecodingError.dataCorruptedError(forKey: .startsAt, in: values, debugDescription: "Unparseable timestamp")
        }
        startsAt = parsedStartsAt
        endsAt = parsedEndsAt
    }

    private static func parseDate(_ string: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: string) { return date }
        return ISO8601DateFormatter().date(from: string)
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
        let mivoStillSessions: [MivoStillSession]
        let appFrictionProfiles: [AppFrictionProfile]
        let userSwap: UserSwap?
        let interventionAttempts: [InterventionAttemptRecord]
        let dailyScreenTimeObservations: [DailyScreenTimeObservation]
        let timeLoans: [TimeLoan]
        let intentGameHistory: [IntentGameHistoryEntry]
        let dropPathTimeAdjustments: [DropPathTimeAdjustment]
        let recallCheckIns: [RecallCheckIn]
        let instagramWrapperSessions: [InstagramWrapperSession]
        let instagramRecallPrompts: [InstagramRecallPrompt]
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
        let errorDescription: String?

        enum CodingKeys: String, CodingKey {
            case code
            case errorCode = "error_code"
            case message
            case msg
            case errorDescription = "error_description"
        }
    }

    /// Mirrors every column `upsertUserState` writes into `user_state` — each
    /// column holds the plain `JSONEncoder` output of the matching Swift
    /// model (see `jsonObject(_:)`), so it decodes straight back into the
    /// same model types with no separate row-mapping needed.
    private struct SupabaseUserStateRow: Decodable {
        let profile: OnboardingProfile?
        let settings: AppSettings?
        let sessions: [Session]?
        let truthChecks: [TruthCheckGuess]?
        let dailyScrollSchedules: [DailyScrollSchedule]?
        let weeklyReports: [WeeklyReportSnapshot]?
        let appInterventionRules: [AppInterventionRule]?
        let accountabilitySummary: AccountabilitySummary?
        let widgetSharedSummary: WidgetSharedSummary?
        let aiDataset: [String]?
        let mivoStillSessions: [MivoStillSession]?
        let appFrictionProfiles: [AppFrictionProfile]?
        let userSwap: UserSwap?
        let interventionAttempts: [InterventionAttemptRecord]?
        let dailyScreenTimeObservations: [DailyScreenTimeObservation]?
        let timeLoans: [TimeLoan]?
        let intentGameHistory: [IntentGameHistoryEntry]?
        let dropPathTimeAdjustments: [DropPathTimeAdjustment]?
        let recallCheckIns: [RecallCheckIn]?
        let instagramWrapperSessions: [InstagramWrapperSession]?
        let instagramRecallPrompts: [InstagramRecallPrompt]?

        enum CodingKeys: String, CodingKey {
            case profile, settings, sessions
            case truthChecks = "truth_checks"
            case dailyScrollSchedules = "daily_scroll_schedules"
            case weeklyReports = "weekly_reports"
            case appInterventionRules = "app_intervention_rules"
            case accountabilitySummary = "accountability_summary"
            case widgetSharedSummary = "widget_shared_summary"
            case aiDataset = "ai_dataset"
            case mivoStillSessions = "mivo_still_sessions"
            case appFrictionProfiles = "app_friction_profiles"
            case userSwap = "user_swap"
            case interventionAttempts = "intervention_attempts"
            case dailyScreenTimeObservations = "daily_screen_time_observations"
            case timeLoans = "time_loans"
            case intentGameHistory = "intent_game_history"
            case dropPathTimeAdjustments = "drop_path_time_adjustments"
            case recallCheckIns = "recall_check_ins"
            case instagramWrapperSessions = "instagram_wrapper_sessions"
            case instagramRecallPrompts = "instagram_recall_prompts"
        }
    }

    private struct SupabaseDeviceBindingRow: Decodable {
        let deviceID: String
        let userID: String

        enum CodingKeys: String, CodingKey {
            case deviceID = "device_id"
            case userID = "user_id"
        }
    }

    private struct MacActivityRow: Decodable {
        let appName: String
        let category: String
        let startedAt: Date
        let endedAt: Date

        enum CodingKeys: String, CodingKey {
            case appName = "app_name"
            case category
            case startedAt = "started_at"
            case endedAt = "ended_at"
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

    /// Native "Sign in with Google" — `idToken` comes from `GIDSignIn`
    /// (see `MivoClearService.swift`'s `configureGoogleSignIn()` for the
    /// same client-ID lookup this reuses) and is exchanged directly with
    /// Supabase's `id_token` grant, so there's no browser redirect and no
    /// client secret involved. Only wired for the Supabase backend — the
    /// legacy REST backend has no equivalent endpoint.
    static func loginWithGoogle(idToken: String) async throws -> RemoteAuthUser {
        guard supabaseBaseURL != nil else { throw AppError.remoteAuthUnavailable }
        return try await supabaseSignInWithGoogle(idToken: idToken)
    }

    /// Native "Sign in with Apple" — `idToken`/`nonce` come from
    /// `LoginView`'s `SignInWithAppleButton` and are exchanged directly
    /// with the same Supabase `id_token` grant Google above uses, just
    /// with `provider: "apple"` and the raw nonce Supabase needs to
    /// verify against the hash baked into the identity token.
    static func loginWithApple(idToken: String, nonce: String) async throws -> RemoteAuthUser {
        guard supabaseBaseURL != nil else { throw AppError.remoteAuthUnavailable }
        return try await supabaseSignInWithApple(idToken: idToken, nonce: nonce)
    }

    /// Pushes a corrected display name to Supabase's `user_metadata` —
    /// used when the OAuth-derived fallback name (email prefix) gets
    /// replaced with one the user actually typed. Only wired for the
    /// Supabase backend, same as the OAuth sign-ins above.
    static func updateDisplayName(_ name: String, accessToken: String) async throws {
        guard supabaseBaseURL != nil else { return }
        try await supabaseUpdateUserMetadata(name: name, accessToken: accessToken)
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
        if DeviceBindingService.isExemptInstallation(installationID) {
            await releaseExemptDeviceBinding(installationID: installationID, user: user)
            return
        }
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

    /// An exempt installation (see `DeviceBindingService.exemptInstallationIDs`)
    /// must never end up bound to any account, at any point — not just
    /// "no new bindings going forward." This actively deletes any
    /// `device_bindings` row that might already exist for this device_id
    /// (e.g. written before the device was exempted, or by an older build),
    /// rather than merely skipping the write `claimDevice` would otherwise
    /// do. RLS restricts the delete to rows the signed-in user owns, so a
    /// row left behind by a different account only clears the next time
    /// that same account happens to sign in from this device — best-effort,
    /// matching every other device-binding call in this file.
    private static func releaseExemptDeviceBinding(installationID: String, user: RemoteAuthUser) async {
        guard let base = supabaseBaseURL,
              let bearer = user.accessToken,
              let encodedID = installationID.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "\(base.absoluteString)/rest/v1/device_bindings?device_id=eq.\(encodedID)") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        applySupabaseHeaders(to: &request, bearer: bearer)
        _ = try? await URLSession.shared.data(for: request)
    }

    /// General, non-admin push device registry — separate from
    /// `ReferralCampaignService.registerAdminPushDevice`, which writes to a
    /// purpose-built admin-alerting table. Cross-device focus commands
    /// (see `CrossDeviceFocusService`) need every signed-in user's device
    /// reachable, not just admins', so this writes to its own
    /// `user_push_devices` table via the same upsert pattern as
    /// `saveUserState` rather than reusing the admin RPC. Best-effort and
    /// non-throwing, matching `saveUserState` — a missed registration
    /// self-heals on the next successful call rather than needing the
    /// caller to handle failure.
    static func registerPushDevice(deviceToken: String, environment: String, installationID: String, record: SecureAuthRecord) async {
        guard let base = supabaseBaseURL,
              let userId = record.remoteUserId,
              let token = record.remoteAccessToken else { return }
        await upsertRows(
            table: "user_push_devices",
            onConflict: "user_id,installation_id",
            rows: [[
                "user_id": userId,
                "installation_id": installationID,
                "device_token": deviceToken,
                "environment": environment,
                "updated_at": ISO8601DateFormatter().string(from: Date())
            ]],
            bearer: token,
            base: base
        )
    }

    static func unregisterPushDevice(installationID: String, record: SecureAuthRecord) async {
        guard let base = supabaseBaseURL,
              let userId = record.remoteUserId,
              let token = record.remoteAccessToken,
              let encodedUserId = userId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let encodedInstallId = installationID.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "\(base.absoluteString)/rest/v1/user_push_devices?user_id=eq.\(encodedUserId)&installation_id=eq.\(encodedInstallId)") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        applySupabaseHeaders(to: &request, bearer: token)
        _ = try? await URLSession.shared.data(for: request)
    }

    /// The one active, not-yet-expired "Block my iPhone too" command for
    /// this account, if any — RLS already restricts the query to the
    /// caller's own `user_id`, so a non-nil result is inherently owned by
    /// the authenticated user (see `IPHONE_FOCUS_RECEIVER.md` point 3).
    static func fetchActiveCrossDeviceFocusCommand(record: SecureAuthRecord) async -> CrossDeviceFocusCommand? {
        guard let base = supabaseBaseURL,
              let userId = record.remoteUserId,
              let token = record.remoteAccessToken,
              let encodedUserId = userId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let encodedNow = ISO8601DateFormatter().string(from: Date()).addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "\(base.absoluteString)/rest/v1/cross_device_focus_sessions?select=*&user_id=eq.\(encodedUserId)&status=eq.active&block_phone=eq.true&ends_at=gt.\(encodedNow)&order=ends_at.desc&limit=1") else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        applySupabaseHeaders(to: &request, bearer: token)

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else { return nil }

        return try? JSONDecoder().decode([CrossDeviceFocusCommand].self, from: data).first
    }

    /// Whether this account has any Mac companion app activity synced —
    /// the signal Settings' "Mivo for Mac" row uses to show
    /// connected/not-connected. Deliberately just an existence check
    /// (`limit=1`) rather than pulling real rows; this only needs a yes/no.
    static func fetchHasMacActivity(record: SecureAuthRecord) async -> Bool {
        guard let base = supabaseBaseURL,
              let userId = record.remoteUserId,
              let token = record.remoteAccessToken,
              let encodedUserId = userId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "\(base.absoluteString)/rest/v1/mac_activity_records?select=id&user_id=eq.\(encodedUserId)&limit=1") else { return false }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        applySupabaseHeaders(to: &request, bearer: token)

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return false }
        return !rows.isEmpty
    }

    /// Today's Mac activity, aggregated client-side from the raw
    /// `mac_activity_records` rows Mivo for Mac has synced — same table
    /// `fetchHasMacActivity` above does its existence check against, just
    /// pulling real rows this time so Settings' "Mivo for Mac" screen can
    /// show what actually happened on the Mac today, not just a status.
    static func fetchMacActivitySummary(record: SecureAuthRecord) async -> MacActivitySummary? {
        guard let base = supabaseBaseURL,
              let userId = record.remoteUserId,
              let token = record.remoteAccessToken,
              let encodedUserId = userId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return nil }

        let todayStart = Calendar.current.startOfDay(for: Date())
        guard let encodedTodayStart = ISO8601DateFormatter().string(from: todayStart)
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
            let recordsURL = URL(string: "\(base.absoluteString)/rest/v1/mac_activity_records?select=app_name,category,started_at,ended_at&user_id=eq.\(encodedUserId)&started_at=gte.\(encodedTodayStart)&order=started_at.desc&limit=500"),
            let sessionsURL = URL(string: "\(base.absoluteString)/rest/v1/mac_focus_sessions?select=id&user_id=eq.\(encodedUserId)&started_at=gte.\(encodedTodayStart)") else { return nil }

        var recordsRequest = URLRequest(url: recordsURL)
        recordsRequest.httpMethod = "GET"
        applySupabaseHeaders(to: &recordsRequest, bearer: token)

        var sessionsRequest = URLRequest(url: sessionsURL)
        sessionsRequest.httpMethod = "GET"
        applySupabaseHeaders(to: &sessionsRequest, bearer: token)

        guard let (recordsData, recordsResponse) = try? await URLSession.shared.data(for: recordsRequest),
              let recordsHTTP = recordsResponse as? HTTPURLResponse,
              (200..<300).contains(recordsHTTP.statusCode) else { return nil }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let rows = try? decoder.decode([MacActivityRow].self, from: recordsData) else { return nil }

        var focusSeconds: TimeInterval = 0
        var driftSeconds: TimeInterval = 0
        var neutralSeconds: TimeInterval = 0
        var appSeconds: [String: TimeInterval] = [:]
        for row in rows {
            let duration = max(0, row.endedAt.timeIntervalSince(row.startedAt))
            switch row.category {
            case "focus": focusSeconds += duration
            case "drift": driftSeconds += duration
            default: neutralSeconds += duration
            }
            appSeconds[row.appName, default: 0] += duration
        }
        let topApps = appSeconds.sorted { $0.value > $1.value }.prefix(3)
            .map { MacActivitySummary.AppUsage(name: $0.key, minutes: Int($0.value / 60)) }

        let sessionsCount: Int
        if let (sessionsData, sessionsResponse) = try? await URLSession.shared.data(for: sessionsRequest),
           let sessionsHTTP = sessionsResponse as? HTTPURLResponse,
           (200..<300).contains(sessionsHTTP.statusCode),
           let sessionRows = try? JSONSerialization.jsonObject(with: sessionsData) as? [[String: Any]] {
            sessionsCount = sessionRows.count
        } else {
            sessionsCount = 0
        }

        return MacActivitySummary(
            totalMinutes: Int((focusSeconds + driftSeconds + neutralSeconds) / 60),
            focusMinutes: Int(focusSeconds / 60),
            driftMinutes: Int(driftSeconds / 60),
            topApps: topApps,
            focusSessionsToday: sessionsCount
        )
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
            payload["mivo_still_sessions"] = jsonObject(snapshot.mivoStillSessions)
            payload["app_friction_profiles"] = jsonObject(snapshot.appFrictionProfiles)
            payload["user_swap"] = snapshot.userSwap.map { jsonObject($0) } ?? NSNull()
            payload["intervention_attempts"] = jsonObject(snapshot.interventionAttempts)
            payload["daily_screen_time_observations"] = jsonObject(snapshot.dailyScreenTimeObservations)
            payload["time_loans"] = jsonObject(snapshot.timeLoans)
            payload["intent_game_history"] = jsonObject(snapshot.intentGameHistory)
            payload["drop_path_time_adjustments"] = jsonObject(snapshot.dropPathTimeAdjustments)
            payload["recall_check_ins"] = jsonObject(snapshot.recallCheckIns)
            payload["instagram_wrapper_sessions"] = jsonObject(snapshot.instagramWrapperSessions)
            payload["instagram_recall_prompts"] = jsonObject(snapshot.instagramRecallPrompts)
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

    /// Deletes the signed-in user's own account on whichever backend is configured.
    /// Throws if the account could not be removed remotely, so callers never report
    /// success for an account that still exists.
    static func deleteOwnAccount(email: String, password: String, record: SecureAuthRecord) async throws {
        if supabaseBaseURL != nil {
            try await supabaseDeleteOwnAccount(email: email, password: password, record: record)
            return
        }
        let _: AuthResponse = try await rawRequest(
            path: "/auth/delete-account",
            body: AuthRequest(email: email, password: password, name: nil, onboardingProfile: nil)
        )
    }

    private static func supabaseDeleteOwnAccount(email: String, password: String, record: SecureAuthRecord) async throws {
        guard let base = supabaseBaseURL, !supabaseAnonKey.isEmpty else { throw AppError.remoteAuthUnavailable }

        // Re-authenticate so deletion always runs on a token that is definitely
        // valid and definitely belongs to the person typing the password, rather
        // than a cached one that may have expired.
        guard let tokenURL = URL(string: "\(base.absoluteString)/auth/v1/token?grant_type=password") else {
            throw AppError.remoteAuthUnavailable
        }
        let session: SupabaseAuthResponse = try await supabaseAuthRequest(
            url: tokenURL,
            body: ["email": email, "password": password]
        )
        guard let bearer = session.accessToken, !bearer.isEmpty else {
            throw AppError.invalidCredentials
        }
        guard session.user?.id == record.remoteUserId || record.remoteUserId == nil else {
            throw AppError.invalidCredentials
        }

        var request = URLRequest(url: base.appendingPathComponent("rest/v1/rpc/delete_my_account"))
        request.httpMethod = "POST"
        applySupabaseHeaders(to: &request, bearer: bearer)
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "input_reason": "Self-serve deletion from Mivo Privacy Center"
        ])

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw AppError.remoteAuthUnavailable
        }

        let status = (response as? HTTPURLResponse)?.statusCode ?? 500
        guard (200..<300).contains(status) else {
            let payload = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let message = (payload?["message"] as? String) ?? (payload?["error"] as? String) ?? ""
            if message.contains("super_admin_self_delete_blocked") {
                throw AppError.accountDeletionBlockedForAdmin
            }
            if message.contains("authentication_required") || status == 401 {
                throw AppError.invalidCredentials
            }
            throw AppError.accountDeletionFailed(reason: message.isEmpty ? nil : message)
        }
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

        let state = await fetchSupabaseUserState(userId: user.id, accessToken: response.accessToken)
        let isAdmin = await fetchSupabaseAdminRole(userId: user.id, accessToken: response.accessToken)
        return RemoteAuthUser(
            email: userEmail,
            name: user.userMetadata?["name"] ?? String(userEmail.split(separator: "@").first ?? "Mivo"),
            createdAt: user.createdAt ?? ISO8601DateFormatter().string(from: Date()),
            onboardingProfile: state.profile,
            isAdmin: isAdmin,
            adminToken: nil,
            remoteUserId: user.id,
            accessToken: response.accessToken,
            refreshToken: response.refreshToken,
            settings: state.settings,
            restoredState: state
        )
    }

    private static func supabaseSignInWithGoogle(idToken: String) async throws -> RemoteAuthUser {
        guard let base = supabaseBaseURL, !supabaseAnonKey.isEmpty else { throw AppError.remoteAuthUnavailable }
        let url = URL(string: "\(base.absoluteString)/auth/v1/token?grant_type=id_token")!
        let response: SupabaseAuthResponse = try await supabaseAuthRequest(
            url: url,
            body: ["provider": "google", "id_token": idToken],
            surfaceServerMessageAs: googleServerRejection
        )

        guard let user = response.user, let userEmail = user.email else {
            throw AppError.googleSignInFailed("Google signed you in but did not share an email address, so Mivo could not create the account.")
        }

        let state = await fetchSupabaseUserState(userId: user.id, accessToken: response.accessToken)
        let isAdmin = await fetchSupabaseAdminRole(userId: user.id, accessToken: response.accessToken)
        return RemoteAuthUser(
            email: userEmail,
            name: user.userMetadata?["name"] ?? String(userEmail.split(separator: "@").first ?? "Mivo"),
            createdAt: user.createdAt ?? ISO8601DateFormatter().string(from: Date()),
            onboardingProfile: state.profile,
            isAdmin: isAdmin,
            adminToken: nil,
            remoteUserId: user.id,
            accessToken: response.accessToken,
            refreshToken: response.refreshToken,
            settings: state.settings,
            restoredState: state
        )
    }

    private static func supabaseSignInWithApple(idToken: String, nonce: String) async throws -> RemoteAuthUser {
        guard let base = supabaseBaseURL, !supabaseAnonKey.isEmpty else { throw AppError.remoteAuthUnavailable }
        let url = URL(string: "\(base.absoluteString)/auth/v1/token?grant_type=id_token")!
        let response: SupabaseAuthResponse = try await supabaseAuthRequest(
            url: url,
            body: ["provider": "apple", "id_token": idToken, "nonce": nonce]
        )

        guard let user = response.user, let userEmail = user.email else {
            throw AppError.invalidCredentials
        }

        let state = await fetchSupabaseUserState(userId: user.id, accessToken: response.accessToken)
        let isAdmin = await fetchSupabaseAdminRole(userId: user.id, accessToken: response.accessToken)
        return RemoteAuthUser(
            email: userEmail,
            name: user.userMetadata?["name"] ?? String(userEmail.split(separator: "@").first ?? "Mivo"),
            createdAt: user.createdAt ?? ISO8601DateFormatter().string(from: Date()),
            onboardingProfile: state.profile,
            isAdmin: isAdmin,
            adminToken: nil,
            remoteUserId: user.id,
            accessToken: response.accessToken,
            refreshToken: response.refreshToken,
            settings: state.settings,
            restoredState: state
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

    private static func supabaseUpdateUserMetadata(name: String, accessToken: String) async throws {
        guard let base = supabaseBaseURL, !supabaseAnonKey.isEmpty else { throw AppError.remoteAuthUnavailable }
        let url = base.appendingPathComponent("auth/v1/user")

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        applySupabaseHeaders(to: &request, bearer: accessToken)
        request.httpBody = try JSONSerialization.data(withJSONObject: ["data": ["name": name]])

        let response: URLResponse
        do {
            (_, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw AppError.remoteAuthUnavailable
        }

        let status = (response as? HTTPURLResponse)?.statusCode ?? 500
        guard (200..<300).contains(status) else {
            if status == 401 || status == 403 { throw AppError.invalidCredentials }
            throw AppError.remoteAuthUnavailable
        }
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

        let state = await fetchSupabaseUserState(userId: user.id, accessToken: response.accessToken)
        let isAdmin = await fetchSupabaseAdminRole(userId: user.id, accessToken: response.accessToken)
        return RemoteAuthUser(
            email: userEmail,
            name: user.userMetadata?["name"] ?? String(userEmail.split(separator: "@").first ?? "Mivo"),
            createdAt: user.createdAt ?? ISO8601DateFormatter().string(from: Date()),
            onboardingProfile: state.profile,
            isAdmin: isAdmin,
            adminToken: nil,
            remoteUserId: user.id,
            accessToken: response.accessToken,
            refreshToken: response.refreshToken,
            settings: state.settings,
            restoredState: state
        )
    }

    /// Restores everything `upsertUserState` has been pushing on every save
    /// — previously this only pulled back `profile`/`settings`, so a fresh
    /// install + login lost session history, truth checks, scroll
    /// schedules, weekly reports, intervention rules, and both summaries
    /// even though they were already sitting in Supabase, unused for restore.
    private static func fetchSupabaseUserState(userId: String, accessToken: String?) async -> RestoredUserState {
        guard let base = supabaseBaseURL,
              let token = accessToken,
              let encodedUserId = userId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "\(base.absoluteString)/rest/v1/user_state?select=profile,settings,sessions,truth_checks,daily_scroll_schedules,weekly_reports,app_intervention_rules,accountability_summary,widget_shared_summary,ai_dataset,mivo_still_sessions,app_friction_profiles,user_swap,intervention_attempts,daily_screen_time_observations,time_loans,intent_game_history,drop_path_time_adjustments,recall_check_ins,instagram_wrapper_sessions,instagram_recall_prompts&user_id=eq.\(encodedUserId)&limit=1") else { return RestoredUserState() }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        applySupabaseHeaders(to: &request, bearer: token)

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              let row = try? JSONDecoder().decode([SupabaseUserStateRow].self, from: data).first else { return RestoredUserState() }

        return RestoredUserState(
            profile: row.profile,
            settings: row.settings,
            sessions: row.sessions,
            truthChecks: row.truthChecks,
            dailyScrollSchedules: row.dailyScrollSchedules,
            weeklyReports: row.weeklyReports,
            appInterventionRules: row.appInterventionRules,
            accountabilitySummary: row.accountabilitySummary,
            widgetSharedSummary: row.widgetSharedSummary,
            aiDataset: row.aiDataset,
            mivoStillSessions: row.mivoStillSessions,
            appFrictionProfiles: row.appFrictionProfiles,
            userSwap: row.userSwap,
            interventionAttempts: row.interventionAttempts,
            dailyScreenTimeObservations: row.dailyScreenTimeObservations,
            timeLoans: row.timeLoans,
            intentGameHistory: row.intentGameHistory,
            dropPathTimeAdjustments: row.dropPathTimeAdjustments,
            recallCheckIns: row.recallCheckIns,
            instagramWrapperSessions: row.instagramWrapperSessions,
            instagramRecallPrompts: row.instagramRecallPrompts
        )
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

    /// Turns Supabase's rejection of a Google ID token into a message that names the real cause and fix,
    /// instead of the generic "Invalid email or password." the shared handler would otherwise show.
    private static func googleServerRejection(status: Int, serverMessage: String) -> AppError {
        let raw = serverMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = raw.lowercased()
        let hint: String
        if lower.contains("audience") {
            hint = "Supabase does not accept this app's Google client ID. In Supabase > Authentication > Providers > Google, add the iOS client ID to \"Client IDs\"."
        } else if lower.contains("nonce") {
            hint = "The Google token's nonce check failed. Enable \"Skip nonce checks\" for Google in Supabase, or send a nonce."
        } else if lower.contains("provider") && (lower.contains("not enabled") || lower.contains("unsupported")) {
            hint = "The Google provider is not enabled in Supabase."
        } else if lower.contains("signup") && lower.contains("disabled") {
            hint = "New signups are disabled in Supabase, so a first-time Google account cannot be created."
        } else if lower.contains("bad id token") || lower.contains("invalid id token") || lower.contains("jwt") {
            hint = "Supabase could not verify the Google token."
        } else {
            hint = "The server rejected the Google sign-in."
        }
        let detail = raw.isEmpty ? "HTTP \(status)" : "HTTP \(status): \(raw)"
        return AppError.googleSignInFailed("\(hint) (\(detail))")
    }

    private static func supabaseAuthRequest<Response: Decodable>(
        url: URL,
        body: [String: Any],
        surfaceServerMessageAs customError: ((Int, String) -> AppError)? = nil
    ) async throws -> Response {
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

            if let customError {
                let raw = supabaseError?.message ?? supabaseError?.msg ?? supabaseError?.errorDescription ?? ""
                throw customError(status, raw)
            }

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
            case "adminRequired": throw AppError.adminRequired
            case "cannotDeleteAdmin": throw AppError.accountDeletionBlockedForAdmin
            default: throw AppError.remoteAuthUnavailable
            }
        }

        guard let typed = try? JSONDecoder().decode(Response.self, from: data) else {
            throw AppError.accountDataMissing
        }
        return typed
    }
}
