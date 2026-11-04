import Foundation

extension AppViewModel {
    func chooseAttentionProblem(_ problem: AttentionProblem) {
        attentionJourney.problem = problem
        persistAttentionJourney()
    }

    @discardableResult
    func addAttentionCommitment(_ title: String) -> Bool {
        guard user != nil, attentionJourney.addCommitment(title) else { return false }
        persistAttentionJourney()
        return true
    }

    func completeAttentionCommitment(_ id: String) {
        guard attentionJourney.complete(id) else { return }
        persistAttentionJourney()
    }

    func setAsideAttentionCommitment(_ id: String) {
        attentionJourney.setAside(id)
        persistAttentionJourney()
    }

    @discardableResult
    func resizeAttentionCommitment(_ id: String, title: String) -> Bool {
        guard attentionJourney.resize(id, title: title) else { return false }
        persistAttentionJourney()
        return true
    }

    func chooseAttentionRecovery(_ choice: AttentionRecovery.Choice) {
        guard user != nil else { return }
        attentionJourney.chooseRecovery(choice)
        persistAttentionJourney()
    }

    /// The manager is bound before this is called. Never import another account's history.
    func syncAttentionCommitments(current: LockIn?, history: [LockIn]) {
        guard let email = user?.email.lowercased().trimmingCharacters(in: .whitespacesAndNewlines),
              LockInManager.shared.accountEmail == email else { return }
        var updated = attentionJourney
        if let current {
            updated.linkLock(id: current.id, task: current.task, startedAt: current.startedAt)
        }
        for lock in history {
            guard let releasedAt = lock.releasedAt, let reason = lock.releaseReason else { continue }
            let evidence: AttentionEvidence?
            switch reason {
            case .miloConvinced: evidence = .miloReviewed
            case .keyholderApproved: evidence = .keyholderApproved
            case .timeRanOut, .cancelledEarly: evidence = nil
            }
            updated.resolveLock(id: lock.id, task: lock.task, startedAt: lock.startedAt,
                                endedAt: releasedAt, evidence: evidence)
        }
        guard updated != attentionJourney else { return }
        attentionJourney = updated
        persistAttentionJourney()
    }

    private func persistAttentionJourney() {
        guard let email = user?.email else { return }
        StorageService.save(attentionJourney, forKey: .attentionJourney, email: email)
    }

    /// A proposal only. Existing enforcement is used after the person explicitly approves it.
    var attentionExperimentSuggestion: ExperimentTemplate {
        let now = Date()
        let start = Calendar.current.date(byAdding: .day, value: -7, to: now) ?? now
        let recent = sessions.filter {
            guard let date = WeeklyExperiment.experimentDate(from: $0.startTime) else { return false }
            return date >= start && date <= now
        }
        let extensions = recent.filter(\.extendedOnce).count
        let automatic = recent.filter { $0.urgeReason == .habit || $0.urgeReason == .bored }.count
        if recent.count >= 3, extensions >= 2 {
            return ExperimentTemplate(
                id: "attention-extensions", type: .reduceExtensions,
                title: "Keep the time you originally chose",
                detail: "You extended \(extensions) of \(recent.count) saved sessions in the last seven days. Try keeping the original limit for one week.",
                rule: WeeklyExperimentRule(startHour: nil, endHour: nil, allowedMinutes: nil, strongerFrictionEnabled: false),
                sourceExperimentID: nil
            )
        }
        if recent.count >= 3, automatic >= 2 {
            return ExperimentTemplate(
                id: "attention-pause", type: .strongerFriction,
                title: "A stronger pause when you return",
                detail: "You described boredom or habit in \(automatic) of \(recent.count) saved sessions this week. Try a longer pause on repeated openings.",
                rule: WeeklyExperimentRule(startHour: nil, endHour: nil, allowedMinutes: nil, strongerFrictionEnabled: true),
                sourceExperimentID: nil
            )
        }
        let problem = attentionJourney.problem ?? .automaticScrolling
        let isBedtime = problem == .bedtime
        let basis = attentionJourney.problem == nil
            ? "A starting suggestion, rather than a measured pattern."
            : "Based on the problem you chose, rather than a measured pattern."
        return ExperimentTemplate(
            id: "attention-\(problem.rawValue)", type: isBedtime ? .protectedWindow : .strongerFriction,
            title: isBedtime ? "Protect one hour before bed" : "Put a pause between impulse and action",
            detail: "\(basis) \(isBedtime ? "Choose an hour that fits your bedtime." : "Try a stronger pause on repeated openings.") Review how it felt after seven days.",
            rule: WeeklyExperimentRule(startHour: isBedtime ? 22 : nil, endHour: isBedtime ? 23 : nil,
                                       allowedMinutes: isBedtime ? 0 : nil, strongerFrictionEnabled: !isBedtime),
            sourceExperimentID: nil
        )
    }
}
