import Foundation

/// Builds `CompanionSignals` from what Mivo's existing Screen Time stack
/// already knows. It reads; it never schedules, monitors or writes Screen
/// Time state, and it adds no DeviceActivity schedule of its own.
///
/// What this can't know on iOS, and therefore never claims: how many times an
/// app was opened, how long the current continuous session has been, or which
/// app is on screen. Those fields don't exist in `CompanionSignals`.
@MainActor
enum CompanionDeviceActivityAdapter {
    #if DEBUG
    static var previewAccountEmail: String?
    #endif

    /// Prepares the manager for the signed-in account and pushes fresh signals
    /// into it. Safe to call often; does nothing beyond a cheap check while
    /// Companion is off.
    static func sync(with appVM: AppViewModel, appInForeground: Bool = true, now: Date = Date()) {
        let manager = CompanionStateManager.shared
        #if DEBUG
        // Lets `CompanionPreviewHost` review these screens without an account.
        let fallbackEmail = previewAccountEmail
        #else
        let fallbackEmail: String? = nil
        #endif
        manager.prepare(forEmail: appVM.isLoggedIn ? appVM.user?.email : fallbackEmail)
        guard manager.isActive else { return }
        manager.refresh(
            with: signals(from: appVM, appInForeground: appInForeground, now: now),
            appNotificationsEnabled: appVM.settings.notificationsEnabled
        )
    }

    static func signals(from appVM: AppViewModel, appInForeground: Bool, now: Date = Date()) -> CompanionSignals {
        let controls = FamilyControlsManager.shared
        let authorized = controls.liveAuthorizationStatus()

        // Today's total only counts if the report really is from today; a
        // report left over from yesterday must not read as today's usage.
        var todayMinutes: Int?
        if authorized, let minutes = appVM.deviceActivityMinutesToday {
            let isToday = appVM.deviceActivityReportGeneratedAt.map { MivoDay.key($0) == MivoDay.key(now) } ?? true
            todayMinutes = isToday ? minutes : nil
        }

        var target: Int?
        if authorized {
            let plan = appVM.adaptiveScreenTimePlan()
            if !plan.collecting, plan.targetMinutes > 0 { target = plan.targetMinutes }
        }

        let (typical, typicalDays) = typicalDailyMinutes(from: appVM.dailyScreenTimeObservations, excluding: MivoDay.key(now))

        var signals = CompanionSignals.neutral(now: now)
        signals.screenTimeAuthorized = authorized
        signals.hasProtectedApps = controls.hasImpulseSelection()
        signals.todayScreenMinutes = todayMinutes
        signals.dailyTargetMinutes = target
        signals.typicalDailyMinutes = typical
        signals.typicalDaysCount = typicalDays
        signals.appInForeground = appInForeground
        signals.mivoSessionActive = controls.isMivoSessionActive()
        signals.focusActive = controls.isStillLockActive(now: now)
        signals.mivoLateNightActive = appVM.isLateNightProtectionActive(at: now)
        signals.interventionsLastHour = interventionsInLastHour(appVM.interventionAttempts, now: now)
        return signals
    }

    /// Mean of up to the last 14 recorded days, not counting today.
    static func typicalDailyMinutes(from observations: [DailyScreenTimeObservation], excluding todayKey: String) -> (Int?, Int) {
        let recent = observations
            .filter { $0.date != todayKey && $0.minutes > 0 }
            .sorted { $0.date > $1.date }
            .prefix(14)
        guard !recent.isEmpty else { return (nil, 0) }
        let mean = recent.reduce(0) { $0 + $1.minutes } / recent.count
        return (mean, recent.count)
    }

    /// Pauses Mivo itself started in the last hour, from the attempt log it
    /// already keeps — no new log.
    static func interventionsInLastHour(_ attempts: [InterventionAttemptRecord], now: Date) -> Int {
        let formatter = ISO8601DateFormatter()
        return attempts.reduce(0) { count, attempt in
            guard let date = formatter.date(from: attempt.occurredAt) else { return count }
            let age = now.timeIntervalSince(date)
            return (age >= 0 && age <= 3600) ? count + 1 : count
        }
    }
}
