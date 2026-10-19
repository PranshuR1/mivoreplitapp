import Foundation

@MainActor
final class ProductExpansionStore: ObservableObject {
    static let shared = ProductExpansionStore()

    @Published private(set) var featureFlags: [MivoFeatureFlag] = []
    @Published private(set) var recoveryPlans: [RecoveryPlan] = []
    @Published private(set) var appProfiles: [AppFrictionProfile] = []
    @Published private(set) var monthlyReports: [MonthlyEffectReport] = []
    @Published private(set) var accountabilityConnections: [AccountabilityConnection] = []
    @Published private(set) var adminSnapshot: AdminExpansionSnapshot = .empty
    @Published private(set) var isRefreshingAdmin = false
    @Published var lastError: String?

    private var loadedEmail: String?

    private init() {}

    func prepare(for appVM: AppViewModel) async {
        guard let email = appVM.user?.email else { return }
        if loadedEmail != email {
            loadedEmail = email
            featureFlags = StorageService.load([MivoFeatureFlag].self, forKey: .featureFlags, email: email) ?? []
            recoveryPlans = StorageService.load([RecoveryPlan].self, forKey: .recoveryPlans, email: email) ?? []
            appProfiles = StorageService.load([AppFrictionProfile].self, forKey: .appFrictionProfiles, email: email)
                ?? defaultProfiles(from: appVM.appInterventionRules)
            monthlyReports = StorageService.load([MonthlyEffectReport].self, forKey: .monthlyEffectReports, email: email) ?? []
            accountabilityConnections = StorageService.load([AccountabilityConnection].self, forKey: .accountabilityConnections, email: email) ?? []
        }

        await restoreBackupOnlyRecordsIfNeeded(email: email)
        proposeRecoveryIfNeeded(using: appVM)
        generateMonthlyReport(using: appVM)
        await refreshFeatureFlags(email: email)
        syncMivoClearAvailability()
        let diagnosticsOptIn = StorageService.load(Bool.self, forKey: .diagnosticsEnabled, email: email) ?? false
        MivoDiagnosticsService.shared.startForActiveUser(remoteAllowed: isEnabled(.diagnostics) && diagnosticsOptIn)
        if isEnabled(.accountabilityPartners) {
            await refreshAccountabilityConnections(email: email)
        }
    }

    func isEnabled(_ key: MivoFeatureKey, appVersion: String? = nil) -> Bool {
        guard let flag = featureFlags.first(where: { $0.key == key.rawValue }) else {
            switch key {
            case .accountabilityPartners, .diagnostics:
                return false
            case .mivoClear, .mivoClearInstagram, .mivoClearTikTok, .mivoClearYouTube, .mivoClearSnapchat:
                // Clear stays off until each platform operator has confirmed Mivo
                // is permitted to present their service this way (App Review
                // guideline 5.2.2). Turning on the server flag is the deliberate
                // act that records that confirmation.
                return false
            default: return true
            }
        }
        guard flag.enabled, !flag.automaticallyPaused else { return false }
        let role = SecureAuthService.loadRecord()?.accountRole ?? "user"
        let founderPreview = flag.founderPreview && role == "super_admin"
        if let targetRole = flag.targetRole, targetRole != role, !founderPreview { return false }
        let installedVersion = appVersion
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? "0"
        if let minimum = flag.minimumVersion, compareVersions(installedVersion, minimum) == .orderedAscending {
            return false
        }
        if founderPreview { return true }
        guard flag.rolloutPercentage > 0 else { return false }
        let userSeed = SecureAuthService.loadRecord()?.remoteUserId ?? DeviceBindingService.boundEmail ?? "mivo"
        let bucket = abs(userSeed.unicodeScalars.reduce(17) { (($0 &* 31) &+ Int($1.value)) % 10_000 }) % 100
        return bucket < flag.rolloutPercentage
    }

    private func syncMivoClearAvailability() {
        let defaults = UserDefaults(suiteName: MivoScreenTimeKeys.appGroup)
        let masterEnabled = isEnabled(.mivoClear)
        for platform in MivoClearPlatform.supportedCases {
            defaults?.set(masterEnabled && isEnabled(platform.featureKey),
                          forKey: MivoScreenTimeKeys.mivoClearEnabledPrefix + platform.rawValue)
        }
        defaults?.set(false, forKey: MivoScreenTimeKeys.mivoClearEnabledPrefix + MivoClearPlatform.snapchat.rawValue)
        defaults?.synchronize()
    }

    func todayGuide(using appVM: AppViewModel) -> TodayGuide {
        if appVM.pendingExpiredRunningSession != nil || appVM.pendingSessionFeedback != nil {
            return TodayGuide(kind: .expiredSession, eyebrow: "SESSION READY", title: "Finish the session",
                              detail: "Save what happened so Mivo can re-lock your apps and keep today's pattern accurate.",
                              actionTitle: "Review session", icon: "checkmark.circle.fill", progress: nil)
        }
        if let recovery = currentRecoveryPlan, recovery.status == .proposed {
            return TodayGuide(kind: .rescue, eyebrow: "A GENTLER RESET", title: "Choose today's recovery",
                              detail: recovery.reason, actionTitle: "Review recovery", icon: "arrow.counterclockwise.circle.fill", progress: nil)
        }
        if appVM.pendingTimeTruthPrompt != nil {
            return TodayGuide(kind: .truthCheck, eyebrow: "DAILY TRUTH", title: "Estimate before the reveal",
                              detail: "Make today's guess before looking at the actual total.", actionTitle: "Start truth check",
                              icon: "eye.fill", progress: nil)
        }
        if appVM.pendingDailyScrollSchedulePrompt != nil || !appVM.isTodayScrollScheduleLocked {
            return TodayGuide(kind: .dailySchedule, eyebrow: "TODAY'S PLAN", title: "Choose your scroll windows",
                              detail: "Set the times that feel realistic today. They lock after you confirm them.",
                              actionTitle: "Set today's times", icon: "calendar.badge.clock", progress: nil)
        }
        let plan = appVM.adaptiveScreenTimePlan()
        let hour = Calendar.current.component(.hour, from: Date())
        if let active = plan.windows.first(where: { hour >= $0.startHour && hour < $0.endHour }) {
            return TodayGuide(kind: .nextWindow, eyebrow: "WINDOW OPEN", title: "\(active.minutes) minutes available",
                              detail: "Your \(hourLabel(active.startHour))-\(hourLabel(active.endHour)) window is open.",
                              actionTitle: "Start intentionally", icon: "play.circle.fill", progress: nil)
        }
        if let next = nextWindow(in: plan.windows, after: hour) {
            return TodayGuide(kind: .nextWindow, eyebrow: "NEXT WINDOW", title: "Starts at \(hourLabel(next.startHour))",
                              detail: "You have \(next.minutes) planned minutes in this window.",
                              actionTitle: "View today's plan", icon: "clock.fill", progress: nil)
        }
        return TodayGuide(kind: .complete, eyebrow: "TODAY", title: "Your plan is set",
                          detail: "Come back for tonight's truth check and reflection.", actionTitle: "View patterns",
                          icon: "checkmark.seal.fill", progress: 1)
    }

    var currentRecoveryPlan: RecoveryPlan? {
        recoveryPlans.first { $0.status == .proposed || $0.status == .active }
    }

    var approvedFrictionProfile: AppFrictionProfile? {
        appProfiles.first(where: { $0.userApproved })
    }

    func acceptRecovery(_ plan: RecoveryPlan) {
        updateRecovery(plan, status: .active)
    }

    func declineRecovery(_ plan: RecoveryPlan) {
        updateRecovery(plan, status: .declined)
    }

    func updateAppProfile(_ profile: AppFrictionProfile) {
        if let index = appProfiles.firstIndex(where: { $0.id == profile.id }) { appProfiles[index] = profile }
        else { appProfiles.append(profile) }
        persist(appProfiles, key: .appFrictionProfiles)
    }

    func experimentTemplates(using appVM: AppViewModel) -> [ExperimentTemplate] {
        [
            ExperimentTemplate(id: "template-window", type: .protectedWindow, title: "Protect one difficult hour",
                               detail: "Choose one recurring problem hour and keep it protected for seven days.",
                               rule: WeeklyExperimentRule(startHour: 21, endHour: 22, allowedMinutes: 0, strongerFrictionEnabled: false), sourceExperimentID: nil),
            ExperimentTemplate(id: "template-extension", type: .reduceExtensions, title: "Keep original session limits",
                               detail: "Try seven days without extending a planned session.",
                               rule: WeeklyExperimentRule(startHour: nil, endHour: nil, allowedMinutes: nil, strongerFrictionEnabled: false), sourceExperimentID: nil),
            ExperimentTemplate(id: "template-friction", type: .strongerFriction, title: "Pause repeated openings",
                               detail: "Use stronger friction after repeated opening attempts for seven days.",
                               rule: WeeklyExperimentRule(startHour: nil, endHour: nil, allowedMinutes: nil, strongerFrictionEnabled: true), sourceExperimentID: nil)
        ]
    }

    func repeatExperimentTemplates(using appVM: AppViewModel) -> [ExperimentTemplate] {
        appVM.completedWeeklyExperiments.prefix(8).map {
            ExperimentTemplate(id: "history-\($0.id)", type: $0.type, title: $0.title,
                               detail: "Repeat the rule you previously approved for another seven days.",
                               rule: $0.rule, sourceExperimentID: $0.id)
        }
    }

    @discardableResult
    func startExperiment(_ template: ExperimentTemplate, using appVM: AppViewModel) -> WeeklyExperiment? {
        guard appVM.canStartWeeklyExperiment else {
            lastError = "Review the current experiment or its result before starting another."
            return nil
        }
        guard let proposal = appVM.createWeeklyExperimentProposal(from: template) else {
            lastError = "Mivo could not prepare this experiment. Try again after reviewing the current experiment."
            return nil
        }
        lastError = nil
        return proposal
    }

    func weeklySummary(using appVM: AppViewModel, connectionID: String = "preview") -> SharedWeeklySummary {
        let calendar = Calendar.current
        let now = Date()
        let start = calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: now)) ?? now
        let formatter = MivoDay.formatter
        let sessions = appVM.sessions.filter {
            guard let date = ISO8601DateFormatter().date(from: $0.startTime) else { return false }
            return date >= start && date <= now
        }
        let checks = appVM.truthChecks.filter { $0.date >= formatter.string(from: start) }
        let averageError = checks.isEmpty ? nil : checks.reduce(0) { $0 + abs($1.actual - $1.guess) } / checks.count
        return SharedWeeklySummary(
            id: UUID().uuidString.lowercased(), connectionId: connectionID,
            weekStart: formatter.string(from: start), weekEnd: formatter.string(from: now),
            plannedMinutes: sessions.reduce(0) { $0 + $1.plannedDuration },
            reflectedDays: Set(sessions.filter { $0.reflection != nil }.map(\.date)).count,
            truthAccuracyTrend: averageError.map { "Average estimate was within \($0) minutes" } ?? "No truth trend yet",
            experimentStatus: appVM.activeWeeklyExperiment.map { "Day \($0.dayNumber) of 7" } ?? "No active experiment",
            encouragement: "A steady week of noticing patterns and choosing intentionally.",
            expiresAt: ISO8601DateFormatter().string(from: calendar.date(byAdding: .day, value: 14, to: now) ?? now),
            sentAt: nil
        )
    }

    func invitePartner(email: String, using appVM: AppViewModel) async {
        do {
            let connection = try await ProductExpansionService.inviteAccountabilityPartner(email: email, summary: weeklySummary(using: appVM))
            accountabilityConnections.removeAll { $0.id == connection.id }
            accountabilityConnections.insert(connection, at: 0)
            persist(accountabilityConnections, key: .accountabilityConnections)
        } catch { lastError = error.localizedDescription }
    }

    func setAutomaticSharing(_ enabled: Bool, connection: AccountabilityConnection) async {
        do {
            let updated = try await ProductExpansionService.setAccountabilitySharing(connectionID: connection.id, enabled: enabled)
            replaceConnection(updated)
        } catch { lastError = error.localizedDescription }
    }

    func revoke(_ connection: AccountabilityConnection) async {
        do {
            try await ProductExpansionService.revokeAccountabilityConnection(id: connection.id)
            var updated = connection; updated.status = .revoked; updated.revokedAt = ISO8601DateFormatter().string(from: Date())
            replaceConnection(updated)
        } catch { lastError = error.localizedDescription }
    }

    func refreshAdmin() async {
        isRefreshingAdmin = true
        defer { isRefreshingAdmin = false }
        do {
            async let snapshot = ProductExpansionService.adminExpansionSnapshot()
            async let flags = ProductExpansionService.adminFeatureFlags()
            adminSnapshot = try await snapshot
            featureFlags = try await flags
            if let email = loadedEmail { StorageService.save(featureFlags, forKey: .featureFlags, email: email) }
            lastError = nil
        } catch { lastError = error.localizedDescription }
    }

    func updateFlag(_ flag: MivoFeatureFlag) async {
        do {
            let saved = try await ProductExpansionService.updateFeatureFlag(flag)
            featureFlags.removeAll { $0.key == saved.key }
            featureFlags.append(saved)
            featureFlags.sort { $0.title < $1.title }
            if let email = loadedEmail { StorageService.save(featureFlags, forKey: .featureFlags, email: email) }
        } catch { lastError = error.localizedDescription }
    }

    func repair(_ issue: AdminDataQualityIssue) async {
        do { try await ProductExpansionService.repairDataQualityIssue(id: issue.id); await refreshAdmin() }
        catch { lastError = error.localizedDescription }
    }

    func resolve(_ item: AdminReviewItem, action: String) async {
        do { try await ProductExpansionService.resolveReviewItem(id: item.id, action: action); await refreshAdmin() }
        catch { lastError = error.localizedDescription }
    }

    private func refreshFeatureFlags(email: String) async {
        guard ProductExpansionService.isConfigured else { return }
        do {
            featureFlags = try await ProductExpansionService.myFeatureFlags()
            StorageService.save(featureFlags, forKey: .featureFlags, email: email)
        } catch { lastError = error.localizedDescription }
    }

    /// `saveRecoveryPlan`/`saveMonthlyEffectReport` were push-only until
    /// this was added — Supabase held a full history that a signed-out
    /// device (or a reinstall) had no way to read back. Runs once per
    /// `loadedEmail` change, same as the other `prepare()` steps. Merges
    /// by id rather than replacing outright: a plan/report that already
    /// exists locally may reflect a more recent status change
    /// (`acceptRecovery`/`declineRecovery`) than what's landed on the
    /// server yet, so only items missing locally are added, never
    /// overwritten.
    private func restoreBackupOnlyRecordsIfNeeded(email: String) async {
        guard ProductExpansionService.isConfigured else { return }
        async let plans = try? ProductExpansionService.recoveryPlans()
        async let reports = try? ProductExpansionService.monthlyEffectReports()
        if let remotePlans = await plans {
            let localIDs = Set(recoveryPlans.map(\.id))
            let missing = remotePlans.filter { !localIDs.contains($0.id) }
            if !missing.isEmpty {
                recoveryPlans.append(contentsOf: missing)
                persist(recoveryPlans, key: .recoveryPlans)
            }
        }
        if let remoteReports = await reports {
            let localIDs = Set(monthlyReports.map(\.id))
            let missing = remoteReports.filter { !localIDs.contains($0.id) }
            if !missing.isEmpty {
                monthlyReports.append(contentsOf: missing)
                monthlyReports.sort { $0.monthKey > $1.monthKey }
                persist(monthlyReports, key: .monthlyEffectReports)
            }
        }
    }

    private func refreshAccountabilityConnections(email: String) async {
        do {
            accountabilityConnections = try await ProductExpansionService.accountabilityConnections()
            StorageService.save(accountabilityConnections, forKey: .accountabilityConnections, email: email)
        } catch { lastError = error.localizedDescription }
    }

    private func proposeRecoveryIfNeeded(using appVM: AppViewModel) {
        guard isEnabled(.recoveryMode), currentRecoveryPlan == nil else { return }
        let calendar = Calendar.current
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: Date()) else { return }
        let formatter = MivoDay.formatter
        let key = formatter.string(from: yesterday)
        guard !recoveryPlans.contains(where: { $0.date == key }) else { return }
        let sessions = appVM.sessions.filter { $0.date == key }
        guard !sessions.isEmpty else { return }
        let schedule = appVM.dailyScrollSchedule(for: key)
        let outside = sessions.reduce(0) { total, session in
            guard let date = ISO8601DateFormatter().date(from: session.startTime) else { return total }
            let hour = calendar.component(.hour, from: date)
            let inside = schedule?.windows.contains { hour >= $0.startHour && hour < $0.endHour } == true
            return total + (inside ? 0 : session.actualDuration)
        }
        let difficult = sessions.filter { $0.extendedOnce && $0.outcomeScore == .notWorthIt }.count
        let target = max(1, appVM.adaptiveScreenTimePlan().targetMinutes)
        guard outside >= max(30, target / 2) || difficult >= 2 else { return }
        let reason = difficult >= 2
            ? "Two extended sessions did not feel worthwhile. Today can be simpler without changing your protections."
            : "Yesterday included \(outside) minutes outside your planned windows. Reset without guilt and keep one clear next action."
        let now = ISO8601DateFormatter().string(from: Date())
        recoveryPlans.insert(RecoveryPlan(id: UUID().uuidString.lowercased(), date: key, status: .proposed,
                                          reason: reason, outsideWindowMinutes: outside,
                                          notWorthwhileExtensionCount: difficult, createdAt: now, resolvedAt: nil), at: 0)
        persist(recoveryPlans, key: .recoveryPlans)
        if let proposal = recoveryPlans.first {
            Task { try? await ProductExpansionService.saveRecoveryPlan(proposal) }
        }
    }

    private func generateMonthlyReport(using appVM: AppViewModel) {
        guard isEnabled(.monthlyEffectReport) else { return }
        let calendar = Calendar.current
        let now = Date()
        let formatter = DateFormatter(); formatter.dateFormat = "yyyy-MM"
        let monthKey = formatter.string(from: now)
        guard !monthlyReports.contains(where: { $0.monthKey == monthKey }) else { return }
        let start = calendar.date(byAdding: .day, value: -29, to: calendar.startOfDay(for: now)) ?? now
        let priorStart = calendar.date(byAdding: .day, value: -30, to: start) ?? start
        let recent = sessions(appVM.sessions, from: start, to: now)
        let prior = sessions(appVM.sessions, from: priorStart, to: start)
        let dayKeys = Set(recent.map(\.date))
        let total = recent.reduce(0) { $0 + $1.actualDuration }
        let outside = outsideMinutes(recent, schedules: appVM.dailyScrollSchedules)
        let priorOutside = outsideMinutes(prior, schedules: appVM.dailyScrollSchedules)
        let extensionRate = recent.isEmpty ? 0 : Double(recent.filter(\.extendedOnce).count) / Double(recent.count)
        let scored = recent.filter { $0.outcomeScore != nil }
        let worthwhileRate = scored.isEmpty ? 0 : Double(scored.filter { $0.outcomeScore == .worthIt }.count) / Double(scored.count)
        let dateFormatter = MivoDay.formatter
        let checks = appVM.truthChecks.filter { $0.date >= dateFormatter.string(from: start) }
        let truthError = checks.isEmpty ? 0 : Double(checks.reduce(0) { $0 + abs($1.actual - $1.guess) }) / Double(checks.count)
        let estimated = max(0, priorOutside - outside)
        let report = MonthlyEffectReport(
            id: monthKey, monthKey: monthKey, validDays: dayKeys.count, sessionCount: recent.count,
            averageDailyMinutes: dayKeys.isEmpty ? 0 : total / dayKeys.count, outsideWindowMinutes: outside,
            scheduleAdherence: total == 0 ? 1 : max(0, 1 - Double(outside) / Double(total)), extensionRate: extensionRate,
            averageTruthError: truthError, worthwhileRate: worthwhileRate,
            completedExperiments: appVM.weeklyExperiments.filter { $0.status == .completed && ($0.endsAt ?? "") >= ISO8601DateFormatter().string(from: start) }.count,
            estimatedReducedMinutes: estimated, generatedAt: ISO8601DateFormatter().string(from: now)
        )
        monthlyReports.insert(report, at: 0)
        monthlyReports = Array(monthlyReports.prefix(18))
        persist(monthlyReports, key: .monthlyEffectReports)
        if report.hasEnoughData { Task { try? await ProductExpansionService.saveMonthlyEffectReport(report) } }
    }

    private func updateRecovery(_ plan: RecoveryPlan, status: RecoveryPlanStatus) {
        guard let index = recoveryPlans.firstIndex(where: { $0.id == plan.id }) else { return }
        recoveryPlans[index].status = status
        recoveryPlans[index].resolvedAt = ISO8601DateFormatter().string(from: Date())
        persist(recoveryPlans, key: .recoveryPlans)
        Task { try? await ProductExpansionService.saveRecoveryPlan(recoveryPlans[index]) }
    }

    private func persist<T: Encodable>(_ value: T, key: StorageKey) {
        guard let email = loadedEmail else { return }
        StorageService.save(value, forKey: key, email: email)
    }

    private func replaceConnection(_ value: AccountabilityConnection) {
        accountabilityConnections.removeAll { $0.id == value.id }
        accountabilityConnections.insert(value, at: 0)
        persist(accountabilityConnections, key: .accountabilityConnections)
    }

    private func defaultProfiles(from rules: [AppInterventionRule]) -> [AppFrictionProfile] {
        rules.map {
            AppFrictionProfile(id: $0.id, appName: $0.appName, strength: .balanced, pauseSeconds: 5,
                               intentionEveryOpening: false, rescueAfterMinutes: 20, extensionsAllowed: true,
                               strongerLateNight: true, userApproved: false)
        }
    }

    private func sessions(_ sessions: [Session], from start: Date, to end: Date) -> [Session] {
        sessions.filter {
            guard let date = ISO8601DateFormatter().date(from: $0.startTime) else { return false }
            return date >= start && date < end.addingTimeInterval(1)
        }
    }

    private func outsideMinutes(_ sessions: [Session], schedules: [DailyScrollSchedule]) -> Int {
        sessions.reduce(0) { total, session in
            guard let date = ISO8601DateFormatter().date(from: session.startTime),
                  let schedule = schedules.first(where: { $0.date == session.date }) else {
                return total + session.actualDuration
            }
            let hour = Calendar.current.component(.hour, from: date)
            let inside = schedule.windows.contains { hour >= $0.startHour && hour < $0.endHour }
            return total + (inside ? 0 : session.actualDuration)
        }
    }

    private func compareVersions(_ lhs: String, _ rhs: String) -> ComparisonResult {
        lhs.compare(rhs, options: .numeric)
    }

    private func nextWindow(in windows: [ScreenScrollWindow], after hour: Int) -> ScreenScrollWindow? {
        windows.sorted { $0.startHour < $1.startHour }.first { $0.startHour > hour }
            ?? windows.sorted { $0.startHour < $1.startHour }.first
    }

    private func hourLabel(_ hour: Int) -> String {
        let normalized = ((hour % 24) + 24) % 24
        if normalized == 0 { return "12 AM" }
        if normalized < 12 { return "\(normalized) AM" }
        if normalized == 12 { return "12 PM" }
        return "\(normalized - 12) PM"
    }

}

private extension MivoFeatureFlag {
    var title: String { MivoFeatureKey(rawValue: key)?.title ?? key.replacingOccurrences(of: "_", with: " ").capitalized }
}
