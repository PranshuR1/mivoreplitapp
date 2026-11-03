import Foundation

/// One app's sessions in Mivo, measured against what was said before each one.
struct AppUsageRow: Identifiable, Equatable {
    let app: SocialApp
    var id: String { app.rawValue }
    let sessions: Int
    let minutes: Int
    let shortVideos: Int
    /// Share of placed time (sign-in and unplaceable pages left out) spent on
    /// what they said they came for. Nil without measured sections.
    let onPurposeShare: Double?
    let reminders: Int
    let returned: Int
    let blocked: Int
    /// The purpose picked most often here.
    let usualPurpose: AppPurpose?
    /// Where the most off-purpose time went, and how much.
    let topDrift: AppSection?
    let topDriftSeconds: Int
}

/// Mivo's read of how each app was used inside Mivo against what was said:
/// time kept to the purpose, reminders and whether they worked, and attempts
/// to leave a locked purpose. Pure: sessions in, numbers out, so it can be tested.
struct AppPurposeReport: Equatable {
    /// Below this much placed time a share is noise, not a finding.
    static let minimumTrackedSeconds = 120

    let days: Int
    let rows: [AppUsageRow]
    let sessionCount: Int
    let totalMinutes: Int
    let totalShortVideos: Int
    let onPurposeShare: Double?
    let reminders: Int
    let returned: Int
    let blocked: Int
    /// Sessions that could be judged (not messages, some placed time), and of
    /// those, the ones that stayed on purpose and stopped at the pick.
    let keptCandidates: Int
    let keptSessions: Int
    /// Answers to "How do you feel now?".
    let feelingCounts: [SessionFeeling: Int]
    /// Sessions opened while studying or just after, and how many of those
    /// ended back at studying.
    let escapes: Int
    let returnedToStudy: Int
    /// Plain findings, most telling first.
    let findings: [String]

    init(sessions: [InstagramWrapperSession], days: Int) {
        self.days = max(days, 1)
        sessionCount = sessions.count

        let grouped = Dictionary(grouping: sessions, by: \.app)
        rows = grouped.map { app, sessions in Self.row(app: app, sessions: sessions) }
            .sorted { ($0.minutes, $0.sessions) > ($1.minutes, $1.sessions) }

        totalMinutes = rows.reduce(0) { $0 + $1.minutes }
        totalShortVideos = rows.reduce(0) { $0 + $1.shortVideos }
        reminders = rows.reduce(0) { $0 + $1.reminders }
        returned = rows.reduce(0) { $0 + $1.returned }
        blocked = rows.reduce(0) { $0 + $1.blocked }

        let placed = sessions.reduce(0) { $0 + Self.placedSeconds($1) }
        let off = sessions.reduce(0) { $0 + $1.offPurposeSeconds }
        onPurposeShare = placed >= Self.minimumTrackedSeconds ? max(0, 1 - Double(off) / Double(placed)) : nil

        let judged = sessions.filter { $0.purpose != "messages" && Self.placedSeconds($0) >= 30 }
        keptCandidates = judged.count
        keptSessions = judged.filter(Self.wasKept).count

        var feelings: [SessionFeeling: Int] = [:]
        for feeling in sessions.compactMap({ $0.feeling.flatMap(SessionFeeling.init(rawValue:)) }) {
            feelings[feeling, default: 0] += 1
        }
        feelingCounts = feelings
        escapes = sessions.filter { $0.afterStudyMinutes != nil }.count
        returnedToStudy = sessions.filter(\.returnedToStudy).count

        findings = Self.findings(sessions: sessions, rows: rows, reminders: reminders, returned: returned, onPurposeShare: onPurposeShare)
    }

    var hasData: Bool { sessionCount > 0 }

    var answeredFeelings: Int { feelingCounts.values.reduce(0, +) }

    func feelingShare(_ feeling: SessionFeeling) -> Double? {
        answeredFeelings == 0 ? nil : Double(feelingCounts[feeling, default: 0]) / Double(answeredFeelings)
    }

    /// Stayed on purpose (under a tenth of the time elsewhere) and didn't
    /// keep going once the pick was used.
    static func wasKept(_ session: InstagramWrapperSession) -> Bool {
        let placed = placedSeconds(session)
        guard placed > 0, Double(session.offPurposeSeconds) / Double(placed) < 0.1 else { return false }
        return !wentPastPick(session)
    }

    static func wentPastPick(_ session: InstagramWrapperSession) -> Bool {
        guard session.slowDownCause == "pick" else { return false }
        if session.limitKind == WrapperSessionLimit.reels.rawValue { return session.reelsAfterSlowdown > 0 }
        guard let slowed = session.secondsToSlowdown else { return false }
        return durationSeconds(session) - slowed > 30
    }

    /// From 10 pm to 5 am, when the same app tends to feel different.
    static func isLateNight(_ session: InstagramWrapperSession, calendar: Calendar = .current) -> Bool {
        guard let start = ISO8601DateFormatter().date(from: session.startedAt) else { return false }
        let hour = calendar.component(.hour, from: start)
        return hour >= 22 || hour < 5
    }

    // MARK: - Per app

    private static func row(app: SocialApp, sessions: [InstagramWrapperSession]) -> AppUsageRow {
        let placed = sessions.reduce(0) { $0 + placedSeconds($1) }
        let off = sessions.reduce(0) { $0 + $1.offPurposeSeconds }

        var driftBySection: [AppSection: Int] = [:]
        for session in sessions {
            guard let purpose = session.purpose.flatMap(app.purpose(id:)) else { continue }
            for (raw, seconds) in session.sectionSeconds {
                guard let section = AppSection(rawValue: raw), purpose.isDrifting(in: section) else { continue }
                driftBySection[section, default: 0] += seconds
            }
        }
        let topDrift = driftBySection.max { ($0.value, $0.key.rawValue) < ($1.value, $1.key.rawValue) }

        let purposeCounts = Dictionary(grouping: sessions.compactMap(\.purpose), by: { $0 }).mapValues(\.count)
        let usual = purposeCounts.max { ($0.value, $0.key) < ($1.value, $1.key) }.flatMap { app.purpose(id: $0.key) }

        return AppUsageRow(
            app: app,
            sessions: sessions.count,
            minutes: (sessions.reduce(0) { $0 + durationSeconds($1) } + 30) / 60,
            shortVideos: sessions.reduce(0) { $0 + $1.reelCount },
            onPurposeShare: placed >= minimumTrackedSeconds ? max(0, 1 - Double(off) / Double(placed)) : nil,
            reminders: sessions.reduce(0) { $0 + $1.driftReminders },
            returned: sessions.reduce(0) { $0 + $1.returnedToPurpose },
            blocked: sessions.reduce(0) { $0 + $1.blockedAttempts },
            usualPurpose: usual,
            topDrift: topDrift?.key,
            topDriftSeconds: topDrift?.value ?? 0
        )
    }

    /// Seconds spent in parts of the app Mivo could place.
    static func placedSeconds(_ session: InstagramWrapperSession) -> Int {
        session.sectionSeconds.reduce(0) { total, entry in
            guard let section = AppSection(rawValue: entry.key), !section.isNeutral else { return total }
            return total + entry.value
        }
    }

    /// Measured seconds when sections were recorded, else start to end.
    static func durationSeconds(_ session: InstagramWrapperSession) -> Int {
        let measured = session.sectionSeconds.values.reduce(0, +)
        if measured > 0 { return measured }
        let formatter = ISO8601DateFormatter()
        guard let start = formatter.date(from: session.startedAt),
              let end = formatter.date(from: session.endedAt) else { return 0 }
        return max(0, Int(end.timeIntervalSince(start).rounded()))
    }

    // MARK: - Findings

    private static func findings(
        sessions: [InstagramWrapperSession],
        rows: [AppUsageRow],
        reminders: Int,
        returned: Int,
        onPurposeShare: Double?
    ) -> [String] {
        var lines: [String] = []

        // Where saying one thing and doing another happened most: the app,
        // purpose and part of the app with the most off-purpose time.
        struct Key: Hashable { let app: SocialApp; let purpose: String; let section: AppSection }
        var drift: [Key: Int] = [:]
        for session in sessions {
            guard let id = session.purpose, let purpose = session.app.purpose(id: id) else { continue }
            for (raw, seconds) in session.sectionSeconds {
                guard let section = AppSection(rawValue: raw), purpose.isDrifting(in: section) else { continue }
                drift[Key(app: session.app, purpose: id, section: section), default: 0] += seconds
            }
        }
        if let worst = drift.filter({ $0.value >= 60 }).max(by: { ($0.value, $0.key.section.rawValue) < ($1.value, $1.key.section.rawValue) }),
           let purpose = worst.key.app.purpose(id: worst.key.purpose) {
            let same = sessions.filter { $0.app == worst.key.app && $0.purpose == worst.key.purpose }
            let placed = same.reduce(0) { $0 + placedSeconds($1) }
            let share = placed > 0 ? Int((Double(worst.value) / Double(placed) * 100).rounded()) : 0
            lines.append("On \(worst.key.app.title) you came to \(purpose.goal) \(times(same.count)), and \(share)% of that time went to \(worst.key.app.name(of: worst.key.section)).")
        }

        lines.append(contentsOf: feelingFindings(sessions: sessions))

        let afterStudy = sessions.filter { $0.afterStudyMinutes != nil }
        if !afterStudy.isEmpty {
            let back = afterStudy.filter(\.returnedToStudy).count
            lines.append(back == 0
                ? "You opened a social app straight from studying \(times(afterStudy.count)), and didn't go back."
                : "You opened a social app straight from studying \(times(afterStudy.count)), and went back to it \(times(back)).")
        }

        if reminders > 0 {
            lines.append(returned == reminders
                ? "Mivo reminded you what you came for \(times(reminders)), and you went back every time."
                : "Mivo reminded you what you came for \(times(reminders)). You went back \(times(returned)).")
        }

        let messageAttempts = sessions.filter { $0.purpose == "messages" }.reduce(0) { $0 + $1.blockedAttempts }
        if messageAttempts > 0 {
            lines.append("In messages-only, you tried to leave messages \(times(messageAttempts)).")
        }
        let videoAttempts = sessions.filter { $0.limitKind == WrapperSessionLimit.reels.rawValue }.reduce(0) { $0 + $1.blockedAttempts }
        if videoAttempts > 0 {
            lines.append("While counting short videos, you tried to go elsewhere \(times(videoAttempts)).")
        }

        if let top = rows.first, rows.count > 1, top.minutes > 0 {
            lines.append("Most of your time in Mivo was \(top.app.title): \(top.minutes) min over \(top.sessions) session\(top.sessions == 1 ? "" : "s").")
        }

        if let onPurposeShare, onPurposeShare >= 0.9, lines.isEmpty {
            lines.append("You stayed on what you came for \(Int((onPurposeShare * 100).rounded()))% of the time.")
        }
        return lines
    }

    /// Which app and purpose (late at night or not) leaves them worse, and
    /// which leaves them better, once there are three answers to go on.
    private static func feelingFindings(sessions: [InstagramWrapperSession]) -> [String] {
        struct Key: Hashable { let app: SocialApp; let purpose: String; let night: Bool }
        var groups: [Key: [SessionFeeling]] = [:]
        for session in sessions {
            guard let feeling = session.feeling.flatMap(SessionFeeling.init(rawValue:)),
                  let purpose = session.purpose else { continue }
            groups[Key(app: session.app, purpose: purpose, night: isLateNight(session)), default: []].append(feeling)
        }
        func describe(_ key: Key) -> String? {
            guard let purpose = key.app.purpose(id: key.purpose) else { return nil }
            return "\(purpose.title) on \(key.app.title)\(key.night ? " after 10 pm" : "")"
        }
        func strongest(_ feeling: SessionFeeling) -> (key: Key, count: Int, total: Int)? {
            groups.compactMap { key, answers -> (key: Key, count: Int, total: Int)? in
                let count = answers.filter { $0 == feeling }.count
                guard answers.count >= 3, Double(count) / Double(answers.count) >= 0.5 else { return nil }
                return (key, count, answers.count)
            }
            .max { lhs, rhs in
                let l = Double(lhs.count) / Double(lhs.total), r = Double(rhs.count) / Double(rhs.total)
                return l != r ? l < r : lhs.total < rhs.total
            }
        }

        var lines: [String] = []
        if let worst = strongest(.worse), let name = describe(worst.key) {
            lines.append("\(name) left you feeling worse \(worst.count) of \(worst.total) times. Try leaving it out this week.")
        }
        if let best = strongest(.better), let name = describe(best.key) {
            lines.append("\(name) left you feeling better \(best.count) of \(best.total) times.")
        }
        return lines
    }

    private static func times(_ count: Int) -> String {
        count == 1 ? "once" : (count == 2 ? "twice" : "\(count) times")
    }
}

extension AppViewModel {
    /// Every app opened in Mivo in the last `days` days, today included.
    func appPurposeReport(days: Int = 7, now: Date = Date()) -> AppPurposeReport {
        let calendar = MivoDay.calendar
        let start = calendar.date(byAdding: .day, value: -(max(days, 1) - 1), to: calendar.startOfDay(for: now)) ?? now
        let startKey = MivoDay.key(start)
        // Day keys are yyyy-MM-dd, so they compare in date order as strings.
        return AppPurposeReport(sessions: instagramWrapperSessions.filter { $0.date >= startKey }, days: days)
    }
}
