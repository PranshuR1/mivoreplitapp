import Foundation

/// The notes the Mivo AI reads before it answers a question. The model was
/// trained to answer only from them, so a price or a policy changes by editing
/// MivoKnowledge.json (built by the "mivo ai" project), not by retraining.
///
/// `notes(for:)` scores exactly like `scripts/mivo_rag.py` in that project: keep the two in step.
struct MivoKnowledge: Decodable {
    struct Fact: Decodable {
        let id: String
        let kw: [String]
        let examples: [String]
        let fact: String
    }

    struct Weights: Decodable {
        let keyword: Double
        let factText: Double
        let example: Double
    }

    struct Prompts: Decodable {
        let proof: String
        let unlock: String
    }

    let system: String
    let contact: String
    let safety: String
    let facts: [Fact]
    let stop: [String]
    let weights: Weights
    let notesPerQuestion: Int
    let prompts: Prompts

    private struct Entry {
        let fact: Fact
        let keywords: Set<String>
        let factTokens: Set<String>
        let exampleTokens: Set<String>
    }

    private let stopWords: Set<String>
    private let index: [Entry]

    private enum CodingKeys: String, CodingKey {
        case system, contact, safety, facts, stop, weights, notesPerQuestion, prompts
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        system = try c.decode(String.self, forKey: .system)
        contact = try c.decode(String.self, forKey: .contact)
        safety = try c.decode(String.self, forKey: .safety)
        facts = try c.decode([Fact].self, forKey: .facts)
        stop = try c.decode([String].self, forKey: .stop)
        weights = try c.decode(Weights.self, forKey: .weights)
        notesPerQuestion = try c.decode(Int.self, forKey: .notesPerQuestion)
        prompts = try c.decode(Prompts.self, forKey: .prompts)

        let stopSet = Set(stop)
        stopWords = stopSet
        index = facts.map { fact in
            Entry(
                fact: fact,
                keywords: Set(fact.kw.map(Self.stem)),
                factTokens: Set(Self.tokens(fact.fact, stopWords: stopSet)),
                exampleTokens: Set(fact.examples.flatMap { Self.tokens($0, stopWords: stopSet) })
            )
        }
    }

    /// The bundled notes, or nil if the app was built without them.
    static let shared: MivoKnowledge? = {
        guard let url = Bundle.main.url(forResource: "MivoKnowledge", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(MivoKnowledge.self, from: data)
    }()

    // MARK: Retrieval

    private static let wordPattern = try! NSRegularExpression(pattern: "[a-z0-9$-]+")

    static func stem(_ word: String) -> String {
        if word.count > 5, word.hasSuffix("ing") { return String(word.dropLast(3)) }
        if word.count > 3, word.hasSuffix("s"), !word.hasSuffix("ss") { return String(word.dropLast(1)) }
        return word
    }

    static func tokens(_ text: String, stopWords: Set<String>) -> [String] {
        let lower = text.lowercased()
        let range = NSRange(lower.startIndex..., in: lower)
        return wordPattern.matches(in: lower, range: range).compactMap { match in
            guard let r = Range(match.range, in: lower) else { return nil }
            let word = String(lower[r])
            return stopWords.contains(word) ? nil : stem(word)
        }
    }

    /// The facts most likely to answer `question`, best first.
    func notes(for question: String) -> [Fact] {
        let q = Set(Self.tokens(question, stopWords: stopWords))
        let scored: [(score: Double, fact: Fact)] = index.compactMap { entry in
            let score = weights.keyword * Double(q.intersection(entry.keywords).count)
                + weights.factText * Double(q.intersection(entry.factTokens).count)
                + weights.example * Double(q.intersection(entry.exampleTokens).count)
            return score > 0 ? (score, entry.fact) : nil
        }
        return scored
            .sorted { $0.score != $1.score ? $0.score > $1.score : $0.fact.id < $1.fact.id }
            .prefix(notesPerQuestion)
            .map(\.fact)
    }

    /// The system prompt for a question: Milo's rules followed by the matching notes, numbered
    /// from 1. The model starts its reply with the number of the note it used, or 0.
    func questionPrompt(for question: String) -> (system: String, notes: [Fact]) {
        let found = notes(for: question)
        let lines = found.isEmpty
            ? "[1] (no notes matched)"
            : found.enumerated().map { "[\($0.offset + 1)] \($0.element.fact)" }.joined(separator: "\n")
        return (system + lines, found)
    }

    /// Splits "[2] text" into (2, "text"). The number is nil when the model left the tag off.
    static func splitTag(_ reply: String) -> (index: Int?, body: String) {
        let trimmed = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("["),
              let close = trimmed.firstIndex(of: "]"),
              let number = Int(trimmed[trimmed.index(after: trimmed.startIndex)..<close]) else { return (nil, trimmed) }
        let body = trimmed[trimmed.index(after: close)...].trimmingCharacters(in: .whitespacesAndNewlines)
        return (number, body)
    }

    /// The share of an answer's content words that also appear in a note.
    func overlap(of answer: String, with note: String) -> Double {
        let words = Set(Self.tokens(answer, stopWords: stopWords))
        guard !words.isEmpty else { return 0 }
        let noteWords = Set(Self.tokens(note, stopWords: stopWords))
        return Double(words.intersection(noteWords).count) / Double(words.count)
    }
}

/// Words that mean someone may be struggling. The reply is fixed, never generated.
enum MivoSafety {
    private static let patterns = [
        "hate myself", "kill myself", "suicid", "self harm", "self-harm", "hurt myself",
        "don't want to be here", "dont want to be here", "no reason to live", "want to die",
    ]

    static func needsCare(_ text: String) -> Bool {
        let lower = text.lowercased()
        return patterns.contains { lower.contains($0) }
    }

    static let reply = "I'm really glad you told me. I'm a small meerkat, not a doctor, so please reach out to someone you trust right now. If you're in the US, you can call or text 988 any time. You don't have to carry this alone."
}
