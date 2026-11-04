import Foundation

/// Mivo's own AI. A Qwen2.5-1.5B (Apache-2.0) fine-tuned on Mivo's notes and Milo's voice,
/// reached through the authenticated `mivo-ai` Supabase function. The notes are
/// picked on the phone and sent with the question to the configured model service.
///
/// The model is small, so each task has a guard around it: answers may only use numbers from
/// the notes, and a yes from the proof or unlock review has to rest on real words.
actor MivoAI {
    static let shared = MivoAI()

    enum Failure: Error { case unavailable, unreadable }

    // MARK: Where the model lives

    private nonisolated static var baseURL: URL? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "MIVO_SUPABASE_URL") as? String else { return nil }
        let cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/rest/v1/?$", with: "", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return URL(string: cleaned)
    }

    private nonisolated static var anonKey: String {
        (Bundle.main.object(forInfoDictionaryKey: "MIVO_SUPABASE_ANON_KEY") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private nonisolated static var accessToken: String? {
        if let token = SecureAuthService.loadRecord()?.remoteAccessToken, !token.isEmpty { return token }
        guard let email = DeviceBindingService.boundEmail else { return nil }
        return SecureAuthService.loadRecord(email: email)?.remoteAccessToken
    }

    /// True when the app has its notes, the server address and a signed-in account.
    nonisolated static var isInstalled: Bool {
        MivoKnowledge.shared != nil && baseURL != nil && !anonKey.isEmpty && accessToken != nil
    }

    private func respond(system: String, user: String, maxTokens: Int, temperature: Float, prefill: String? = nil) async throws -> String {
        guard let baseURL = Self.baseURL, !Self.anonKey.isEmpty, let token = Self.accessToken,
              let url = URL(string: "functions/v1/mivo-ai", relativeTo: baseURL)?.absoluteURL else {
            throw Failure.unavailable
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        // A sleeping server takes up to a minute to wake; the callers fall back after that.
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(Self.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        var body: [String: Any] = ["system": system, "user": user, "max_tokens": maxTokens, "temperature": temperature]
        if let prefill { body["prefill"] = prefill }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let text = body["text"] as? String else { throw Failure.unavailable }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: Ask Milo

    /// Answers from Mivo's notes, with an explicit local-note fallback during service outages.
    func answer(_ question: String) async -> String? {
        let trimmed = String(question.trimmingCharacters(in: .whitespacesAndNewlines).prefix(300))
        guard !trimmed.isEmpty, let knowledge = MivoKnowledge.shared else { return nil }
        if MivoSafety.needsCare(trimmed) { return MivoSafety.reply }

        let prompt = knowledge.questionPrompt(for: trimmed)
        // The model reads notes well but can't pick which to cite, so the reply starts at the
        // retriever's best note. The checks below still reject an answer that drifts from it.
        guard let reply = try? await respond(
            system: prompt.system, user: trimmed, maxTokens: 180, temperature: 0.1,
            prefill: prompt.notes.isEmpty ? nil : "[1]"
        ), !reply.isEmpty else { return Self.noteFallback(knowledge: knowledge, notes: prompt.notes) }

        return Self.groundedAnswer(reply, knowledge: knowledge, notes: prompt.notes)
    }

    static func noteFallback(knowledge: MivoKnowledge, notes: [MivoKnowledge.Fact]) -> String {
        guard let note = notes.first else {
            return "I couldn't reach the AI service. You can email \(knowledge.contact) for help."
        }
        return "I couldn't reach the AI service. From Mivo's notes: \(note.fact)"
    }

    /// Model output is untrusted: reject invalid citations before indexing and
    /// require every number in the answer to come from the cited note.
    static func groundedAnswer(_ reply: String, knowledge: MivoKnowledge, notes: [MivoKnowledge.Fact]) -> String {
        let unsure = "I'm not sure about that one, and I'd rather not guess. You can email \(knowledge.contact)."
        let (index, body) = MivoKnowledge.splitTag(reply)
        guard let index, index > 0, index <= notes.count, !body.isEmpty else { return unsure }

        // A small model can still invent a price or drift off the note it cites. The numbers
        // must come from that note, and most of the answer's words must be in it.
        let cited = notes[index - 1].fact
        let allowed = Self.numbers(in: cited)
        guard Self.numbers(in: body).isSubset(of: allowed),
              knowledge.overlap(of: body, with: cited) >= 0.3 else { return unsure }
        return body
    }

    // MARK: Emergency unlock

    /// Reviews a request for five more minutes. Nil when the server can't be reached or
    /// its answer can't be read, so the caller falls back to its own rules.
    func reviewUnlock(reason: String, appName: String) async -> EmergencyUnlockReview? {
        guard let knowledge = MivoKnowledge.shared else { return nil }
        let trimmed = String(reason.trimmingCharacters(in: .whitespacesAndNewlines).prefix(300))
        guard !trimmed.isEmpty else { return EmergencyUnlockReview(approved: false, message: "Tell me what you need it for.") }
        // Under about three real words there is nothing specific to judge.
        guard trimmed.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).count >= 3 else {
            return EmergencyUnlockReview(approved: false, message: "I need something more specific, like what you're doing and who for.")
        }
        guard let raw = try? await respond(
            system: knowledge.prompts.unlock,
            user: "Protected app: \(appName)\nReason: \(trimmed)",
            maxTokens: 80, temperature: 0
        ), let json = Self.json(raw),
        let approved = json["approved"] as? Bool,
        let message = (json["reply"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !message.isEmpty
        else { return nil }
        return EmergencyUnlockReview(approved: approved, message: message)
    }

    // MARK: Lock-in proof

    /// Milo judges what someone says they finished. Photos are read for their text on the
    /// phone and dropped. Throws `unavailable` when the server can't be reached, so the caller can
    /// choose another path.
    func reviewProof(task: String, messages: [LockInMessage], images: [Data]) async throws -> MiloReview {
        guard let knowledge = MivoKnowledge.shared else { throw Failure.unavailable }

        let said = messages.filter { $0.role == .user }.map(\.text).joined(separator: "\n")
        var evidence = String(said.trimmingCharacters(in: .whitespacesAndNewlines).prefix(900))
        let photoText = await MivoPhotoText.read(images)
        if !photoText.isEmpty {
            evidence += (evidence.isEmpty ? "" : "\n") + "Words in their photo: " + String(photoText.joined(separator: " ").prefix(400))
        }
        guard !evidence.isEmpty else {
            return MiloReview(
                verdict: .needsMore,
                reply: images.isEmpty
                    ? "Tell me what you got done, with one specific detail."
                    : "I can't read that photo on this phone. Tell me in a sentence what you did, with one specific detail.",
                summary: ""
            )
        }

        let raw = try await respond(
            system: knowledge.prompts.proof,
            user: "Task: \(task)\n\nWhat they said:\n\(evidence)",
            maxTokens: 200, temperature: 0
        )
        guard let json = Self.json(raw),
              let verdictRaw = json["verdict"] as? String, let verdict = MiloVerdict(rawValue: verdictRaw),
              let reply = (json["reply"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !reply.isEmpty
        else { throw Failure.unreadable }

        let summary = (json["summary"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        // An unlock needs a summary a friend can read, and more than a few words behind it.
        if verdict == .convinced {
            let words = said.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).count + (photoText.isEmpty ? 0 : 3)
            guard words >= 4, !summary.isEmpty else {
                return MiloReview(verdict: .needsMore, reply: "Close. Can you tell me one specific thing you did?", summary: "")
            }
            return MiloReview(verdict: .convinced, reply: reply, summary: summary)
        }
        return MiloReview(verdict: verdict, reply: reply, summary: "")
    }

    // MARK: Helpers

    private static let numberPattern = try! NSRegularExpression(pattern: "\\d+(?:\\.\\d+)?")

    static func numbers(in text: String) -> Set<String> {
        let range = NSRange(text.startIndex..., in: text)
        return Set(numberPattern.matches(in: text, range: range).compactMap { Range($0.range, in: text).map { String(text[$0]) } })
    }

    static func json(_ text: String) -> [String: Any]? {
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}"), start < end,
              let data = String(text[start...end]).data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }
}
