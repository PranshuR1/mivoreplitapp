import Foundation

/// Tunables for classification. One place, so tests and tuning never hunt
/// through the engine.
struct CompanionThresholds {
    var approachingFraction = 0.75
    var repeatedInterventionCount = 3
    var continuationWindow: TimeInterval = 30 * 60
    var continuationExtraMinutes = 10
    var intentionalBreakWindow: TimeInterval = 20 * 60
    var celebrationWindow: TimeInterval = 60
    var focusAfterglowWindow: TimeInterval = 10 * 60
    var extendedRatio = 1.3
    var extendedMinimumExtraMinutes = 30
    var extendedMinimumHistoryDays = 5
    var recentInterventionForLateNight: TimeInterval = 45 * 60

    static let standard = CompanionThresholds()
}

/// Pure behaviour layer: signals + preferences in, a decision out. No UI, no
/// storage, no clock of its own — `signals.now` and the calendar are
/// parameters, which is what makes midnight, time-zone and cooldown behaviour
/// testable.
struct CompanionBehaviorEngine {
    var thresholds: CompanionThresholds = .standard
    var calendar: Calendar = CompanionDay.calendar

    func evaluate(signals: CompanionSignals, preferences: CompanionPreferences) -> CompanionBehaviorResult {
        let limits = dataLimits(for: signals)
        let phase = preferences.bedtime.phase(at: signals.now, calendar: calendar)

        // Quiet hours outrank everything: asleep, silent. Mivo's own pauses
        // and shields are untouched — only the companion goes quiet.
        if preferences.quietHours.contains(signals.now, calendar: calendar) {
            return result(.quietHours, .sleeping, .sleeping, nil, .calm, .none, 0, limits)
        }

        if signals.focusActive {
            return result(.focusSession, .focused, .focused, nil, .calm, .none, 0, limits)
        }

        var decision = classify(signals: signals, phase: phase, limits: limits)

        if signals.pauseInProgress {
            // The pause screen is up: the companion is with the person. The
            // message still reflects the underlying context, so a late-night
            // pause says "It's getting late", not a generic line.
            decision.state = .intervening
            decision.animation = .intervention
            if decision.topic == nil { decision.topic = .pauseOpening }
        }
        return decision
    }

    // MARK: - Classification

    private func classify(signals: CompanionSignals, phase: CompanionBedtimePhase, limits: [CompanionDataLimit]) -> CompanionBehaviorResult {
        let now = signals.now
        let inCooldown = (signals.cooldownUntil ?? .distantPast) > now && !signals.pauseInProgress
        let usage = signals.screenTimeAuthorized == false ? nil : signals.todayScreenMinutes

        // Late-night use needs evidence the phone is actually in use: Mivo
        // open, a Mivo session running, a pause on screen, or a very recent pause.
        let isLateNight = phase == .night || signals.mivoLateNightActive
        let recentPause = signals.lastInterventionDate.map { now.timeIntervalSince($0) <= thresholds.recentInterventionForLateNight } ?? false
        if isLateNight, signals.appInForeground || signals.mivoSessionActive || signals.pauseInProgress || recentPause {
            return result(.lateNightUse, .tired, .tired, inCooldown ? nil : .lateNight, .gentle, .stepAway, 20 * 60, limits)
        }

        if signals.interventionsLastHour >= thresholds.repeatedInterventionCount {
            return inCooldown
                ? result(.repeatedIntervention, .resting, .idleBreathing, nil, .notice, .startFocus, 45 * 60, limits)
                : result(.repeatedIntervention, .concerned, .intervention, .repeatedPauses, .notice, .startFocus, 45 * 60, limits)
        }

        // A positive reaction, only when the person isn't mid-pause.
        if !signals.pauseInProgress, let reaction = positiveReaction(signals) {
            return reaction.withLimits(limits)
        }

        if let outcome = signals.lastOutcome, outcome == .continued,
           let outcomeDate = signals.lastOutcomeDate,
           now.timeIntervalSince(outcomeDate) <= thresholds.continuationWindow,
           let usage, let atLast = signals.minutesAtLastIntervention,
           signals.minutesAtLastInterventionDayKey == CompanionDay.key(now, calendar: calendar),
           usage - atLast >= thresholds.continuationExtraMinutes {
            return inCooldown
                ? result(.postInterventionContinuation, .resting, .idleBreathing, nil, .gentle, .stepAway, 20 * 60, limits)
                : result(.postInterventionContinuation, .concerned, .intervention, .stillHere, .gentle, .stepAway, 20 * 60, limits)
        }

        if let usage, let target = signals.dailyTargetMinutes, target > 0 {
            if usage >= target {
                return inCooldown
                    ? result(.thresholdExceeded, .resting, .idleBreathing, nil, .notice, .stepAway, 30 * 60, limits)
                    : result(.thresholdExceeded, .watching, .lookingAround, .overTarget, .notice, .stepAway, 30 * 60, limits)
            }
            if Double(usage) >= Double(target) * thresholds.approachingFraction {
                return inCooldown
                    ? result(.approachingLimit, .resting, .idleBreathing, nil, .gentle, .none, 30 * 60, limits)
                    : result(.approachingLimit, .curious, .curious, .nearTarget, .gentle, .none, 30 * 60, limits)
            }
        }

        if let usage, let typical = signals.typicalDailyMinutes,
           signals.typicalDaysCount >= thresholds.extendedMinimumHistoryDays,
           Double(usage) >= Double(typical) * thresholds.extendedRatio,
           usage - typical >= thresholds.extendedMinimumExtraMinutes {
            return inCooldown
                ? result(.extendedUse, .resting, .idleBreathing, nil, .gentle, .none, 60 * 60, limits)
                : result(.extendedUse, .curious, .curious, .longerThanUsual, .gentle, .none, 60 * 60, limits)
        }

        // Nothing stands out. Bedtime only changes posture, not the message.
        if inCooldown { return result(.normalUse, .resting, .idleBreathing, nil, .calm, .none, 0, limits) }
        if phase != .none { return result(.normalUse, .tired, .tired, nil, .calm, .none, 0, limits) }
        return result(.normalUse, .idle, .idleBreathing, nil, .calm, .none, 0, limits)
    }

    /// Stepping away from a pause, or finishing a focus session, earns a short
    /// celebration and then a calmer "happy" while the moment is still recent.
    private func positiveReaction(_ signals: CompanionSignals) -> CompanionBehaviorResult? {
        let now = signals.now
        var latest: (date: Date, topic: CompanionMessageTopic)?

        if signals.lastOutcome == .exited, let date = signals.lastOutcomeDate,
           now.timeIntervalSince(date) <= thresholds.intentionalBreakWindow {
            latest = (date, .breakTaken)
        }
        if let date = signals.lastFocusCompletedAt,
           now.timeIntervalSince(date) <= thresholds.focusAfterglowWindow,
           latest == nil || date > latest!.date {
            latest = (date, .focusDone)
        }
        guard let latest, latest.date <= now else { return nil }

        let fresh = now.timeIntervalSince(latest.date) <= thresholds.celebrationWindow
        return CompanionBehaviorResult(
            behavior: .intentionalBreak,
            state: fresh ? .celebrating : .happy,
            animation: fresh ? .celebration : .idleBreathing,
            topic: fresh ? latest.topic : nil,
            severity: .calm,
            recommendation: .none,
            cooldown: 0,
            dataLimits: []
        )
    }

    private func dataLimits(for signals: CompanionSignals) -> [CompanionDataLimit] {
        if signals.screenTimeAuthorized == false || signals.screenTimeAuthorized == nil {
            return [.screenTimeNotAuthorized]
        }
        var limits: [CompanionDataLimit] = []
        if !signals.hasProtectedApps { limits.append(.noProtectedApps) }
        if signals.todayScreenMinutes == nil { limits.append(.noUsageReportYet) }
        return limits
    }

    private func result(
        _ behavior: CompanionBehavior,
        _ state: CompanionState,
        _ animation: CompanionAnimation,
        _ topic: CompanionMessageTopic?,
        _ severity: CompanionSeverity,
        _ recommendation: CompanionRecommendation,
        _ cooldown: TimeInterval,
        _ limits: [CompanionDataLimit]
    ) -> CompanionBehaviorResult {
        CompanionBehaviorResult(
            behavior: behavior, state: state, animation: animation, topic: topic,
            severity: severity, recommendation: recommendation, cooldown: cooldown, dataLimits: limits
        )
    }
}

private extension CompanionBehaviorResult {
    func withLimits(_ limits: [CompanionDataLimit]) -> CompanionBehaviorResult {
        var copy = self
        copy.dataLimits = limits
        return copy
    }
}
