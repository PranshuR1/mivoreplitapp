import Foundation

/// The person's chosen problem, rather than an inference about their mood.
enum AttentionProblem: String, Codable, CaseIterable, Identifiable {
    case study, bedtime, usefulSocial, automaticScrolling

    var id: String { rawValue }
    var title: String {
        switch self {
        case .study: return "I put off studying or work"
        case .bedtime: return "I scroll past bedtime"
        case .usefulSocial: return "I need messages, then get lost in feeds"
        case .automaticScrolling: return "I open apps without meaning to"
        }
    }
    var icon: String {
        switch self {
        case .study: return "book.closed"
        case .bedtime: return "moon"
        case .usefulSocial: return "bubble.left.and.bubble.right"
        case .automaticScrolling: return "hand.raised"
        }
    }
    var startingPoint: String {
        switch self {
        case .study: return "Name one small task. Protect it with Lock-in if you need a firmer boundary."
        case .bedtime: return "Try 15 quiet minutes before bed, then review whether the routine helped."
        case .usefulSocial: return "Open messages inside Mivo, where the feed is out of reach."
        case .automaticScrolling: return "Start with a short pause and one activity you'd rather do."
        }
    }
    var actionTitle: String {
        switch self {
        case .study: return "Choose one thing to finish"
        case .bedtime: return "Set up 15 quiet minutes"
        case .usefulSocial: return "Open my messages"
        case .automaticScrolling: return "Choose something to do instead"
        }
    }
    var suggestedTask: String {
        switch self {
        case .study: return "Finish one section of my notes"
        case .bedtime: return "Read two pages before bed"
        case .usefulSocial: return "Reply to the message I came for"
        case .automaticScrolling: return "Step outside for a minute"
        }
    }
}

enum AttentionEvidence: String, Codable {
    case selfReported, miloReviewed, keyholderApproved

    var label: String {
        switch self {
        case .selfReported: return "You marked this done"
        case .miloReviewed: return "Evidence reviewed by Milo"
        case .keyholderApproved: return "Approved by your keyholder"
        }
    }
}

struct AttentionCommitment: Codable, Equatable, Identifiable {
    enum Status: String, Codable { case planned, locked, completed, notDone, setAside }
    let id: String
    var title: String
    let createdAt: Date
    var status: Status = .planned
    var completedAt: Date?
    var evidence: AttentionEvidence?
    var lockID: String?

    var isOpen: Bool { status == .planned || status == .locked }
}

struct AttentionRecovery: Codable, Equatable, Identifiable {
    enum Choice: String, Codable, CaseIterable, Identifiable {
        // `messages` keeps the raw value it was saved under when it opened Clear.
        case smallerTask, messages = "clear", quietTime
        var id: String { rawValue }
        var title: String {
            switch self {
            case .smallerTask: return "Make the next task smaller"
            case .messages: return "Only open my messages"
            case .quietTime: return "Set up 15 quiet minutes"
            }
        }
    }
    let id: String
    let chosenAt: Date
    let choice: Choice
}

/// Saved per account, on this device. No viewed content, mood inference, or invented time saved.
struct AttentionJourney: Codable, Equatable {
    var problem: AttentionProblem?
    var commitments: [AttentionCommitment] = []
    var recoveries: [AttentionRecovery] = []

    var currentCommitment: AttentionCommitment? { commitments.first { $0.isOpen } }

    static func cleanTitle(_ raw: String) -> String? {
        let title = raw.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard title.count >= 3 else { return nil }
        return String(title.prefix(80))
    }

    @discardableResult
    mutating func addCommitment(_ raw: String, now: Date = Date()) -> Bool {
        guard currentCommitment == nil, let title = Self.cleanTitle(raw) else { return false }
        commitments.insert(AttentionCommitment(id: UUID().uuidString, title: title, createdAt: now), at: 0)
        return true
    }

    @discardableResult
    mutating func complete(_ id: String, now: Date = Date()) -> Bool {
        guard let index = commitments.firstIndex(where: { $0.id == id }),
              commitments[index].status == .planned, commitments[index].lockID == nil else { return false }
        commitments[index].status = .completed
        commitments[index].completedAt = now
        commitments[index].evidence = .selfReported
        return true
    }

    mutating func setAside(_ id: String) {
        guard let index = commitments.firstIndex(where: { $0.id == id && $0.status == .planned }) else { return }
        commitments[index].status = .setAside
    }

    @discardableResult
    mutating func resize(_ id: String, title raw: String) -> Bool {
        guard let title = Self.cleanTitle(raw),
              let index = commitments.firstIndex(where: { $0.id == id && $0.status == .planned }),
              commitments[index].lockID == nil else { return false }
        commitments[index].title = title
        return true
    }

    mutating func linkLock(id: String, task: String, startedAt: Date) {
        guard !commitments.contains(where: { $0.lockID == id }) else { return }
        if let index = commitments.firstIndex(where: {
            $0.status == .planned && $0.title == task && $0.createdAt <= startedAt
        }) {
            commitments[index].status = .locked
            commitments[index].lockID = id
        } else {
            commitments.insert(AttentionCommitment(
                id: "lock-\(id)", title: task, createdAt: startedAt, status: .locked, lockID: id
            ), at: 0)
        }
    }

    /// Idempotent, so foreground refresh and a repeated backend response cannot add wins.
    mutating func resolveLock(id: String, task: String, startedAt: Date, endedAt: Date, evidence: AttentionEvidence?) {
        linkLock(id: id, task: task, startedAt: startedAt)
        guard let index = commitments.firstIndex(where: { $0.lockID == id }) else { return }
        commitments[index].status = evidence == nil ? .notDone : .completed
        commitments[index].completedAt = evidence == nil ? nil : endedAt
        commitments[index].evidence = evidence
    }

    func completions(from start: Date, to end: Date) -> [AttentionCommitment] {
        commitments.filter {
            guard $0.status == .completed, let date = $0.completedAt else { return false }
            return date >= start && date < end
        }.sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
    }

    mutating func chooseRecovery(_ choice: AttentionRecovery.Choice, now: Date = Date(), calendar: Calendar = .current) {
        // A changed choice on the same day is still one return, not several wins.
        recoveries.removeAll { calendar.isDate($0.chosenAt, inSameDayAs: now) }
        recoveries.insert(AttentionRecovery(id: UUID().uuidString, chosenAt: now, choice: choice), at: 0)
    }
}
