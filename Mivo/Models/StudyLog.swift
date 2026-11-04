import Foundation

/// One finished study session.
struct StudyEntry: Codable, Equatable, Identifiable {
    /// Where the session was run. Only a session run on this phone can earn
    /// scroll time or start the free week; `.remote` ones came down from the
    /// account (the website, or another device) and only count for the streak.
    enum Origin: String, Codable {
        case phone
        case remote
        case desktop
    }

    enum CodingKeys: String, CodingKey {
        case id, task, startedAt, endedAt, recordedSeconds, scrollSecondsEarned, origin, focusedSeconds, plan
    }

    var id = UUID()
    var task: String
    var startedAt: Date
    var endedAt: Date
    /// Seconds of the session that are on video. 0 when it was not recorded.
    var recordedSeconds: Int
    /// Wrapper seconds this session added to today's balance.
    var scrollSecondsEarned: Int
    var origin: Origin = .phone
    /// Desktop focus credit excludes distraction, away and uncertain intervals.
    var focusedSeconds: Int? = nil
    /// Private local setup. Never included in the account's study payload or public room.
    var plan: PhoneStudyPlan? = nil

    var seconds: Int {
        let elapsed = max(0, Int(endedAt.timeIntervalSince(startedAt)))
        return origin == .desktop ? min(elapsed, max(0, focusedSeconds ?? 0)) : elapsed
    }
    var minutes: Int { seconds / 60 }
    var wasRecorded: Bool { recordedSeconds > 0 }
}

extension StudyEntry {
    /// Logs saved before `origin` existed have none: they were all run on the phone.
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        task = try values.decode(String.self, forKey: .task)
        startedAt = try values.decode(Date.self, forKey: .startedAt)
        endedAt = try values.decode(Date.self, forKey: .endedAt)
        recordedSeconds = try values.decode(Int.self, forKey: .recordedSeconds)
        scrollSecondsEarned = try values.decode(Int.self, forKey: .scrollSecondsEarned)
        origin = try values.decodeIfPresent(Origin.self, forKey: .origin) ?? .phone
        focusedSeconds = try values.decodeIfPresent(Int.self, forKey: .focusedSeconds)
        plan = try values.decodeIfPresent(PhoneStudyPlan.self, forKey: .plan)
    }
}

/// A session the account holds that this phone may not have: the task and the
/// times, nothing else. It never carries video or scroll time.
struct RemoteStudySession: Equatable {
    var id: UUID
    var task: String
    var startedAt: Date
    var endedAt: Date
    var source: String? = nil
    var focusedSeconds: Int? = nil
}

/// Every finished session, and the streak they add up to. Pure value logic —
/// no clock, no storage — so it can be unit tested.
struct StudyLog: Codable, Equatable {
    /// A day counts once it holds one block of this much study. The bar is low
    /// on purpose: the streak rewards starting, not finishing a marathon.
    static let dayThresholdSeconds = 10 * 60

    var entries: [StudyEntry] = []

    /// When the first session run on this phone began; the free week
    /// (`StudyTrial`) counts from here. Sessions that came down from the
    /// account never earned scroll time here, so they do not start it.
    var firstSessionAt: Date? { entries.filter { $0.origin != .remote }.map(\.startedAt).min() }

    /// Sessions run on this phone that the account does not hold yet.
    func unsynced(alreadySynced: Set<UUID>) -> [StudyEntry] {
        entries.filter { $0.origin == .phone && !alreadySynced.contains($0.id) }
    }

    /// Brings the account's sessions in. A session run on this phone is left
    /// alone; remote copies follow account edits. One that came from the account
    /// earlier and is gone from it now
    /// (deleted on the website) is dropped, but only inside `windowStart...`,
    /// the stretch of time the account actually answered for. Sessions run on
    /// this phone are never removed: the phone keeps its own copy.
    mutating func merge(remote: [RemoteStudySession], windowStart: Date) {
        let remoteIDs = Set(remote.map(\.id))
        entries.removeAll { $0.origin != .phone && $0.startedAt >= windowStart && !remoteIDs.contains($0.id) }
        var indices = Dictionary(entries.enumerated().map { ($0.element.id, $0.offset) }, uniquingKeysWith: { first, _ in first })
        for session in remote where session.endedAt > session.startedAt {
            let entry = StudyEntry(
                id: session.id, task: session.task, startedAt: session.startedAt, endedAt: session.endedAt,
                recordedSeconds: 0, scrollSecondsEarned: entries.first(where: { $0.id == session.id })?.scrollSecondsEarned ?? 0,
                origin: session.source == "desktop" ? .desktop : .remote, focusedSeconds: session.focusedSeconds
            )
            if let index = indices[session.id] {
                // Website edits update remote copies, while phone receipts remain authoritative.
                if entries[index].origin != .phone { entries[index] = entry }
            } else {
                indices[session.id] = entries.count
                entries.append(entry)
            }
        }
        entries.sort { $0.startedAt < $1.startedAt }
    }

    /// Study seconds per local day (`yyyy-MM-dd`). A session that crosses
    /// midnight counts toward both days.
    func secondsByDay(calendar: Calendar = .current) -> [String: Int] {
        var totals: [String: Int] = [:]
        for entry in entries {
            var cursor = entry.startedAt
            while cursor < entry.endedAt {
                let nextMidnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: cursor)) ?? entry.endedAt
                let boundary = min(entry.endedAt, nextMidnight)
                let elapsed = entry.endedAt.timeIntervalSince(entry.startedAt)
                let seconds: Int
                if entry.origin == .desktop, elapsed > 0 {
                    // Split the credited total proportionally; cumulative rounding preserves it.
                    seconds = Int(Double(entry.seconds) * boundary.timeIntervalSince(entry.startedAt) / elapsed)
                        - Int(Double(entry.seconds) * cursor.timeIntervalSince(entry.startedAt) / elapsed)
                } else {
                    seconds = Int(boundary.timeIntervalSince(cursor))
                }
                totals[ReelBalance.dayKey(for: cursor, calendar: calendar), default: 0] += seconds
                cursor = boundary
            }
        }
        return totals
    }

    func seconds(on date: Date, calendar: Calendar = .current) -> Int {
        secondsByDay(calendar: calendar)[ReelBalance.dayKey(for: date, calendar: calendar)] ?? 0
    }

    /// Consecutive days that reached the threshold. If today has not reached it
    /// yet the count runs back from yesterday, so an unfinished day does not
    /// read as a broken streak.
    func streak(asOf now: Date, calendar: Calendar = .current) -> Int {
        let totals = secondsByDay(calendar: calendar)
        func counts(_ date: Date) -> Bool {
            (totals[ReelBalance.dayKey(for: date, calendar: calendar)] ?? 0) >= Self.dayThresholdSeconds
        }
        var day = calendar.startOfDay(for: now)
        if !counts(day) { day = calendar.date(byAdding: .day, value: -1, to: day) ?? day }
        var count = 0
        while counts(day) {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return count
    }
}

/// Milo's lines on the study receipt. Fixed: the rule for what earns scroll
/// time is the same every day, so there is nothing to argue with.
enum MiloStudyVoice {
    static func receipt(earnedScrollMinutes: Int, recorded: Bool, capReached: Bool, streak: Int, lockedScrollMinutes: Int = 0) -> String {
        if !recorded {
            return "No video, so no scroll time this round. The minutes still count for your streak."
        }
        if lockedScrollMinutes > 0 {
            return "Your \(StudyTrial.days) free days are over, so the \(lockedScrollMinutes) minutes of scroll this earned weren't added. Mivo Plus lets future sessions earn scroll time. The studying and your streak still count."
        }
        if earnedScrollMinutes == 0 {
            return capReached
                ? "Today's scroll time is already full. The studying still counts."
                : "That's a start, and starting is the hard part."
        }
        if streak >= 2 {
            return "\(streak) days in a row. You earned \(earnedScrollMinutes) minutes of scroll. Enjoy them."
        }
        return "You did the thing. \(earnedScrollMinutes) minutes of scroll are yours."
    }
}

/// The person's study room as the account holds it: one link friends open to
/// see they are studying. The room is shown only while it is open.
struct StudyRoomState: Equatable {
    struct Visitor: Equatable, Identifiable {
        var id: UUID
        var name: String
    }

    var hasRoom: Bool
    var code: String
    var displayName: String
    var isOpen: Bool
    var showTask: Bool
    /// A session is running and has been heard from in the last two minutes.
    var studying: Bool
    var sitting: [Visitor]

    static let none = StudyRoomState(
        hasRoom: false, code: "", displayName: "", isOpen: false, showTask: true, studying: false, sitting: []
    )

    var url: URL? {
        hasRoom && !code.isEmpty ? URL(string: "https://usemivo.app/room/\(code)") : nil
    }
}

/// The setup the person chose for a phone study block. Opaque Screen Time tokens stay on-device.
struct PhoneStudyPlan: Codable, Equatable {
    var outcome = ""
    var minutes = 25
    var websites: [String] = []
    var usesPaper = true
    var distractionSelection: Data? = nil
    var distractionCount = 0

    var goalSeconds: Int { min(120, max(15, minutes)) * 60 }
    var hasDistractions: Bool { distractionSelection != nil && distractionCount > 0 }

    static func website(_ input: String) -> String? {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !value.isEmpty, !value.contains(where: \.isWhitespace),
              let parts = URLComponents(string: value.contains("://") ? value : "https://" + value),
              ["http", "https"].contains(parts.scheme ?? ""), parts.user == nil, parts.password == nil,
              var host = parts.host, !host.isEmpty else { return nil }
        while host.hasSuffix(".") { host.removeLast() }
        if host.hasPrefix("www.") { host.removeFirst(4) }
        guard host.contains(".") || host == "localhost" else { return nil }
        return host
    }
}
