import Foundation
import UserNotifications

/// One day in the fresh-start week as shown on Home.
enum ComebackDayMark: Equatable {
    case under
    case over
    case unmeasured
    case today
    case upcoming
}

struct ComebackWeekSummary: Equatable {
    let dayIndex: Int
    let todayTarget: Int
    let marks: [ComebackDayMark]
    let underCount: Int
    let measuredCount: Int
    let why: String?
}

// MARK: - Comeback (fresh start for people who stopped using Mivo)

extension AppViewModel {
    /// Home shows a quiet restart row for this long after a dismissed offer.
    var comebackRestartOfferLapseDays: Int? {
        guard comebackAnchor == nil || comebackAnchorIsOlderThanLapse,
              let lapse = comebackLapse, lapse.status == .snoozed,
              let detected = MivoDay.daysSince(lapse.detectedDay),
              detected <= MivoComeback.snoozeVisibleDays else { return nil }
        return lapse.lapseDays
    }

    private var comebackAnchorIsOlderThanLapse: Bool {
        guard let anchor = comebackAnchor, let lapse = comebackLapse else { return true }
        return anchor.startDay < lapse.detectedDay
    }

    // MARK: Detection

    /// Call on every foreground. Compares today with the last day the app was
    /// open *before* stamping today, which is what makes a gap visible at all.
    func evaluateComebackPrompt(now: Date = Date()) {
        guard isLoggedIn, settings.onboardingComplete, let email = user?.email else {
            pendingComebackPrompt = nil
            return
        }
        let today = MivoDay.key(now)

        let stored = StorageService.load(String.self, forKey: .lastActiveDay, email: email)
        let lastActive = stored ?? inferredLastActiveDay()
        if stored != today {
            StorageService.save(today, forKey: .lastActiveDay, email: email)
        }

        if let lastActive,
           let days = MivoComeback.lapseDays(lastActiveDay: lastActive, today: today),
           days >= MivoComeback.lapseThresholdDays {
            let record = ComebackLapseRecord(
                lastActiveDay: lastActive,
                detectedDay: today,
                lapseDays: days,
                status: .pending
            )
            comebackLapse = record
            StorageService.save(record, forKey: .comebackLapse, email: email)
        }

        // An interrupted offer (app killed mid-flow) comes back until resolved.
        if pendingComebackPrompt == nil, let lapse = comebackLapse, lapse.status == .pending {
            pendingComebackPrompt = makeComebackPrompt(lapseDays: lapse.lapseDays, isManual: false)
        }

        if let lapse = comebackLapse, lapse.status == .snoozed,
           let detected = MivoDay.daysSince(lapse.detectedDay),
           detected > MivoComeback.snoozeVisibleDays {
            clearComebackLapse()
        }

        scheduleComebackNudges()
    }

    /// Best guess at the last day the person did something deliberate, for the
    /// first launch after this feature ships when no open has been stamped yet.
    /// Passive signals (Screen Time reports) are left out: they can arrive
    /// without the person ever opening Mivo.
    private func inferredLastActiveDay() -> String? {
        var keys = sessions.map(\.date)
            + truthChecks.map(\.date)
            + dailyScrollSchedules.map(\.date)
        if let started = onboardingProfile.observationStartedAt,
           let date = ISO8601DateFormatter().date(from: started) {
            keys.append(MivoDay.key(date))
        }
        return MivoComeback.latestDay(keys)
    }

    // MARK: Presenting

    func makeComebackPrompt(lapseDays: Int, isManual: Bool) -> ComebackPrompt {
        let today = todayKey()
        return ComebackPrompt(
            id: "comeback-\(today)-\(lapseDays)-\(isManual ? "manual" : "lapse")",
            lapseDays: lapseDays,
            isManual: isManual,
            baseline: MivoComeback.baseline(
                observations: dailyScreenTimeObservations,
                setupEstimate: onboardingProfile.scrollEstimateMinutes,
                today: today
            ),
            lowestDay: MivoComeback.lowestDay(observations: dailyScreenTimeObservations, today: today),
            floorMinutes: max(15, onboardingProfile.dailyScrollGoalMinutes ?? 30)
        )
    }

    /// Entry point for Settings and the Home restart row. Works any time, not
    /// only after a detected lapse. Always worded as a voluntary restart: by the
    /// time someone taps it, "it's been N days" describes a gap they've already
    /// come back from.
    func presentComebackFlow() {
        guard isLoggedIn, settings.onboardingComplete else { return }
        pendingComebackPrompt = makeComebackPrompt(lapseDays: 0, isManual: true)
    }

    // MARK: Resolving

    /// Starting a fresh start replaces the plan state that was there before,
    /// rather than layering on it:
    ///   - the daily goal is whatever was chosen in the flow;
    ///   - today's already-locked windows keep their times but are re-sized to
    ///     the new target (they carry minutes from the old plan);
    ///   - loans and Drop Path penalties taken against the old plan are cleared;
    ///   - prompts that belong to the old ramp (goal question, forecast) are
    ///     dropped, since the flow already answered or replaced them.
    /// Protections the person chose themselves (selected apps, pause style,
    /// experiments) are deliberately left alone.
    func startComeback(
        prompt: ComebackPrompt,
        baseline: ComebackBaseline,
        pace: ComebackPace,
        goalMinutes: Int,
        reason: ComebackLapseReason?,
        why: String?,
        nudges: Bool
    ) {
        guard let email = user?.email else { return }
        let floor = max(15, goalMinutes)

        let startMinutes = MivoComeback.startMinutes(baseline: baseline.minutes, pace: pace, floor: floor)

        // Goal first: every number below is measured against it. The saved
        // preferred windows keep their times but are re-sized too, since
        // Settings offers them as the starting point for the next schedule.
        var profile = onboardingProfile
        profile.dailyScrollGoalMinutes = goalMinutes
        if let preferred = profile.preferredScrollWindows, !preferred.isEmpty {
            profile.preferredScrollWindows = MivoComeback.fit(preferred, toTarget: startMinutes)
        }
        saveOnboardingProfile(profile)
        saveForCurrentUser(true, forKey: .scrollGoalPromptShown)
        pendingScrollGoalPrompt = nil
        pendingGoalForecastPrompt = nil
        let anchor = ComebackAnchor(
            startDay: todayKey(),
            baselineMinutes: baseline.minutes,
            baselineSource: baseline.source,
            startMinutes: startMinutes,
            dailyStepMinutes: pace.dailyStepMinutes,
            pace: pace,
            reason: reason,
            lapseDays: prompt.lapseDays,
            why: why,
            nudgesEnabled: nudges,
            createdAt: ISO8601DateFormatter().string(from: Date())
        )
        comebackAnchor = anchor
        StorageService.save(anchor, forKey: .comebackAnchor, email: email)
        clearComebackLapse()
        pendingComebackPrompt = nil

        resizeTodaysScheduleToTarget(startMinutes)
        // A schedule prompt raised before the restart carries windows sized
        // for the old plan, and would be reused as-is. Rebuild it.
        pendingDailyScrollSchedulePrompt = nil
        TimeLoanService.shared.clearPendingLoans(appVM: self)
        DropPathTimeAdjustmentService.shared.clearPendingAdjustments(appVM: self)

        // The plan just changed under everything that reads it: protection
        // (learning mode ends), the widget, and today's windows.
        syncLearningModeProtectionState()
        updateWidgetSharedSummary()
        scheduleComebackNudges()
        HapticsService.success()
        evaluateDailyScrollSchedulePrompt()
    }

    /// Today's schedule may already be locked from before the restart, with
    /// window minutes drawn from the old plan. The times stay; the minutes are
    /// re-split in the same proportions so they add up to the new target.
    private func resizeTodaysScheduleToTarget(_ target: Int) {
        let today = todayKey()
        guard let index = dailyScrollSchedules.firstIndex(where: { $0.date == today }) else { return }
        let existing = dailyScrollSchedules[index]
        guard !existing.windows.isEmpty else { return }

        dailyScrollSchedules[index] = DailyScrollSchedule(
            id: existing.id,
            date: existing.date,
            windows: MivoComeback.fit(existing.windows, toTarget: target),
            createdAt: existing.createdAt
        )
        saveForCurrentUser(dailyScrollSchedules, forKey: .dailyScrollSchedules)
    }

    /// "Not now": stop asking, keep a quiet way back on Home.
    func snoozeComeback() {
        if var lapse = comebackLapse, lapse.status == .pending, let email = user?.email {
            lapse.status = .snoozed
            comebackLapse = lapse
            StorageService.save(lapse, forKey: .comebackLapse, email: email)
        }
        pendingComebackPrompt = nil
    }

    private func clearComebackLapse() {
        comebackLapse = nil
        if let email = user?.email {
            StorageService.remove(forKey: .comebackLapse, email: email)
        }
    }

    // MARK: Home

    func comebackWeek() -> ComebackWeekSummary? {
        guard let anchor = comebackAnchor,
              let dayIndex = MivoComeback.dayIndex(anchor: anchor, today: todayKey()),
              dayIndex <= MivoComeback.cardDays else { return nil }
        let floor = max(15, onboardingProfile.dailyScrollGoalMinutes ?? 30)
        let minutesByDay = Dictionary(
            dailyScreenTimeObservations.map { ($0.date, $0.minutes) },
            uniquingKeysWith: max
        )

        var marks: [ComebackDayMark] = []
        var under = 0
        var measured = 0
        for day in 1...MivoComeback.cardDays {
            if day > dayIndex { marks.append(.upcoming); continue }
            if day == dayIndex { marks.append(.today); continue }
            let key = MivoDay.key(offsetFromToday: day - dayIndex)
            guard let minutes = minutesByDay[key], minutes > 0 else { marks.append(.unmeasured); continue }
            measured += 1
            if minutes <= MivoComeback.target(anchor: anchor, dayIndex: day, floor: floor) {
                under += 1
                marks.append(.under)
            } else {
                marks.append(.over)
            }
        }
        return ComebackWeekSummary(
            dayIndex: dayIndex,
            todayTarget: MivoComeback.target(anchor: anchor, dayIndex: dayIndex, floor: floor),
            marks: marks,
            underCount: under,
            measuredCount: measured,
            why: anchor.why
        )
    }

    // MARK: Nudges

    /// Three gentle local notifications at 3, 7 and 14 days out, rebuilt on
    /// every open so they only ever fire if the person actually goes quiet.
    /// Never prompts for permission: if notifications aren't already allowed,
    /// this does nothing.
    func scheduleComebackNudges() {
        let center = UNUserNotificationCenter.current()
        let ids = MivoComeback.nudgeDays.map { "mivo.comeback.nudge.\($0)" }
        center.removePendingNotificationRequests(withIdentifiers: ids)
        guard isLoggedIn, settings.onboardingComplete, settings.notificationsEnabled,
              comebackAnchor?.nudgesEnabled ?? true else { return }

        let copy: [Int: (title: String, body: String)] = [
            3: ("Still want less screen time?",
                "No catching up needed. Open Mivo for a fresh start at a pace that fits today."),
            7: ("Your fresh start is waiting",
                "A week away undoes nothing. Restarting takes under a minute."),
            14: ("Mivo is here when you are",
                 "Restart whenever it suits you, at whatever pace you want.")
        ]

        center.getNotificationSettings { notificationSettings in
            guard notificationSettings.authorizationStatus == .authorized
                    || notificationSettings.authorizationStatus == .provisional else { return }
            for days in MivoComeback.nudgeDays {
                guard let text = copy[days] else { continue }
                let content = UNMutableNotificationContent()
                content.title = text.title
                content.body = text.body
                content.sound = .default
                let trigger = UNTimeIntervalNotificationTrigger(
                    timeInterval: TimeInterval(days * 24 * 60 * 60),
                    repeats: false
                )
                center.add(UNNotificationRequest(
                    identifier: "mivo.comeback.nudge.\(days)",
                    content: content,
                    trigger: trigger
                ))
            }
        }
    }
}
