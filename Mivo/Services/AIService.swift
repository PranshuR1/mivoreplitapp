import Foundation

// MARK: - OpenRouter Service
enum OpenRouterService {
    private static let endpoint = URL(string: "https://openrouter.ai/api/v1/chat/completions")!
    // Two models: primary Claude Haiku, fallback Llama (free tier)
    private static let models = ["anthropic/claude-3-haiku", "meta-llama/llama-3-8b-instruct:free"]

    private static var apiKey: String {
        (Bundle.main.object(forInfoDictionaryKey: "MIVO_OPENROUTER_API_KEY") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    struct PlanPayload: Decodable {
        let targetMinutes: Int?
        let strictnessPercent: Int?
        let summary: String?
        let decisionReason: String?
        let windows: [WindowPayload]?

        struct WindowPayload: Decodable {
            let title: String?
            let startHour: Int?
            let endHour: Int?
            let minutes: Int?
            let reason: String?
        }
    }

    private struct EmergencyUnlockPayload: Decodable {
        let approved: Bool
        let message: String?
    }

    static func makePersonalizedPlan(
        sessions: [Session],
        profile: OnboardingProfile?,
        localPlan: ScreenTimeReductionPlan
    ) async -> ScreenTimeReductionPlan? {
        let prompt = buildPrompt(sessions: sessions, profile: profile, localPlan: localPlan)
        for model in models {
            if let result = await callModel(model: model, prompt: prompt, localPlan: localPlan) {
                return result
            }
        }
        return nil
    }

    private static func buildPrompt(sessions: [Session], profile: OnboardingProfile?, localPlan: ScreenTimeReductionPlan) -> String {
        let recentSessions = sessions.suffix(10).map {
            "- \($0.date): \($0.actualDuration) min, intention: \($0.intention.rawValue)"
        }.joined(separator: "\n")

        let intention = profile?.primaryIntention?.rawValue ?? "general"
        let scrollEst = profile?.scrollEstimateMinutes.map { "\($0)" } ?? "unknown"
        let apps = profile?.preferredApps.prefix(6).joined(separator: ", ") ?? "none listed"
        let dayIndex = localPlan.dayIndex
        let baseline = localPlan.baselineMinutes
        let localTarget = localPlan.targetMinutes
        let goal = profile?.dailyScrollGoalMinutes.map { "\($0)" } ?? "(not set — assume 30)"

        return """
You are a compassionate screen-time coach inside Mivo, an iOS focus app.

User profile:
- Primary reason for using Mivo: \(intention)
- Self-reported daily scroll estimate: \(scrollEst) min
- Apps they use most: \(apps)
- Plan day (day 1 = first day after 3-day observation): \(dayIndex)
- Blended baseline after observation: \(baseline) min
- User's daily scroll goal (end target, set during onboarding): \(goal) min
- Rule-based target today: \(localTarget) min

Recent sessions (last 10):
\(recentSessions.isEmpty ? "None yet." : recentSessions)

Generate a PERSONALIZED screen time plan that follows this philosophy:
- Day 1 of the plan equals the blended baseline (\(baseline) min) — start where
  the user actually is, never below.
- The plan ramps DOWN smoothly toward the user's goal (\(goal) min) over weeks,
  never below the goal. NEVER drop more than 5 min from one day to the next.
- Week 1 (plan days 1–7) is the lenient week: 2–4 min/day decrement.
- Week 2+ tightens slightly faster: the per-day decrement grows by ~1 min per
  week. "Harder every week, slowly but surely."
- Once the plan reaches the goal, it stays there — don't go lower.
- Suggest 2-4 scroll windows that fit the user's session patterns:
  2 windows if target is <=90 min, 3 windows if 91-180 min, 4 windows if >180 min.
  Prefer 1-hour windows; use 2-hour windows only when a single window has more
  than 60 allowed minutes.
- Be warm and personalized in summary/decisionReason (mention their main app or
  intention, and frame it as a gentle build-up, not a crash diet).

Respond ONLY with valid JSON, no markdown, no commentary:
{
  "targetMinutes": <int — for plan day \(dayIndex)>,
  "strictnessPercent": <int 0-95 — how much below baseline>,
  "summary": "<1-2 sentences, personalized>",
  "decisionReason": "<1-2 sentences explaining the plan>",
  "windows": [
    {"title": "<label>", "startHour": <0-23>, "endHour": <1-24>, "minutes": <int>, "reason": "<why>"}
  ]
}
"""
    }

    private static func callModel(model: String, prompt: String, localPlan: ScreenTimeReductionPlan) async -> ScreenTimeReductionPlan? {
        let key = apiKey
        guard !key.isEmpty else { return nil }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("https://usemivo.app", forHTTPHeaderField: "HTTP-Referer")
        request.timeoutInterval = 14

        let body: [String: Any] = [
            "model": model,
            "messages": [["role": "user", "content": prompt]],
            "max_tokens": 600,
            "temperature": 0.4
        ]
        guard let bodyData = try? JSONSerialization.data(withJSONObject: body) else { return nil }
        request.httpBody = bodyData

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }

        // Extract content from OpenRouter response envelope
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String else { return nil }

        // Strip any accidental markdown fences
        let cleaned = content
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "^```json\\s*", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\s*```$", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let payloadData = cleaned.data(using: .utf8),
              let payload = try? JSONDecoder().decode(PlanPayload.self, from: payloadData) else { return nil }

        // Build windows from payload; fall back to local windows if AI omitted them
        let aiWindows: [ScreenScrollWindow] = (payload.windows ?? []).enumerated().compactMap { idx, w in
            guard let start = w.startHour, let end = w.endHour, let mins = w.minutes else { return nil }
            return ScreenScrollWindow(
                id: "ai-window-\(idx)-\(model.prefix(6))",
                title: w.title ?? "Scroll session \(idx + 1)",
                startHour: min(max(start, 0), 23),
                endHour: min(24, max(end, start + 1)),
                minutes: max(5, mins),
                reason: w.reason ?? "Personalised by Mivo AI."
            )
        }
        let windows = aiWindows.isEmpty ? localPlan.windows : aiWindows

        let target = payload.targetMinutes ?? localPlan.targetMinutes
        let strictness = payload.strictnessPercent ?? localPlan.strictnessPercent
        let summary = payload.summary ?? localPlan.summary
        let reason = payload.decisionReason ?? localPlan.decisionReason

        return ScreenTimeReductionPlan(
            id: "ai-\(localPlan.dayIndex)-\(target)",
            collecting: false,
            daysCollected: localPlan.daysCollected,
            daysNeeded: localPlan.daysNeeded,
            dayIndex: localPlan.dayIndex,
            baselineMinutes: localPlan.baselineMinutes,
            targetMinutes: target,
            strictnessPercent: strictness,
            summary: summary,
            decisionReason: reason,
            windows: windows
        )
    }

    static func verifyEmergencyUnlock(
        reason: String,
        profile: OnboardingProfile?,
        recentSessions: [Session]
    ) async -> EmergencyUnlockReview? {
        let key = apiKey
        guard !key.isEmpty else { return nil }

        let prompt = emergencyUnlockPrompt(reason: reason, profile: profile, recentSessions: recentSessions)
        for model in models {
            if let review = await callEmergencyUnlockModel(model: model, prompt: prompt, key: key) {
                return review
            }
        }
        return nil
    }

    private static func emergencyUnlockPrompt(
        reason: String,
        profile: OnboardingProfile?,
        recentSessions: [Session]
    ) -> String {
        let apps = profile?.preferredApps.prefix(6).joined(separator: ", ") ?? "none listed"
        let recent = recentSessions.suffix(6).map {
            "- \($0.date): \($0.actualDuration)m, intention: \($0.intention.rawValue), emergency: \($0.emergencyUnlockUsed == true ? "yes" : "no")"
        }.joined(separator: "\n")

        return """
You are Mivo's emergency-unlock verifier. The user is asking for 5 extra minutes after their scrolling timer ended.

Approve only if the reason is concrete, time-sensitive, and hard to postpone, such as replying to a specific person, handling work/school, travel, directions, tickets, banking, health, safety, or another real-world task.

Reject if the reason is vague, recreational, habit-based, boredom-based, or simply wants more scrolling, such as "just because", "bored", "I want to scroll", "TikTok", "Instagram", "relax", "idk", or "more time".

User's protected apps: \(apps)
Recent sessions:
\(recent.isEmpty ? "None." : recent)

Emergency reason:
"\(reason)"

Respond ONLY with valid JSON:
{
  "approved": true | false,
  "message": "<short user-facing reason, max 18 words>"
}
"""
    }

    private static func callEmergencyUnlockModel(model: String, prompt: String, key: String) async -> EmergencyUnlockReview? {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("https://usemivo.app", forHTTPHeaderField: "HTTP-Referer")
        request.timeoutInterval = 8

        let body: [String: Any] = [
            "model": model,
            "messages": [["role": "user", "content": prompt]],
            "max_tokens": 120,
            "temperature": 0.1
        ]
        guard let bodyData = try? JSONSerialization.data(withJSONObject: body) else { return nil }
        request.httpBody = bodyData

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String else { return nil }

        let cleaned = content
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "^```json\\s*", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\s*```$", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let payloadData = cleaned.data(using: .utf8),
              let payload = try? JSONDecoder().decode(EmergencyUnlockPayload.self, from: payloadData) else { return nil }

        return EmergencyUnlockReview(
            approved: payload.approved,
            message: payload.message ?? (payload.approved ? "Approved for a concrete urgent task." : "Mivo needs a more specific urgent reason.")
        )
    }
}

// MARK: - AI Service
// Supports both online (OpenAI API) and offline (rule-based) recommendations

struct AIRequestBody: Encodable {
    let focusLevel: Int
    let timeAvailable: Int
    let intendedDuration: Int
    let taskDesc: String?
    let onboardingProfile: OnboardingProfilePayload?
    let recentSessionSummary: String?

    struct OnboardingProfilePayload: Encodable {
        let primaryIntention: String?
        let scrollEstimateMinutes: Int?
        let preferredApps: [String]
    }
}

struct ProtectedAppRecommendation: Codable {
    let apps: [String]
    let rationale: String
}

private struct ScreenTimeReductionPlanRequest: Encodable {
    let sessions: [Session]
    let truthChecks: [TruthCheckGuess]
    let todayScreenTimeMinutes: Int?
    let onboardingProfile: OnboardingProfile?
}

enum AIServiceError: Error {
    case networkUnavailable
    case serverError(Int)
    case decodingError
}

class AIService {
    /// A local adaptive decision so the pause is immediate and still works offline.
    /// Repeated openings inside the friction tracker's 30-minute window receive
    /// a slightly longer pause without escalating into a punitive cooldown.
    static func adaptiveInterventionPauseSeconds(
        attemptCount: Int,
        recentAttempts: [InterventionAttemptRecord],
        now: Date = Date()
    ) -> Int {
        let recentCutoff = now.addingTimeInterval(-30 * 60)
        let recentRecordedCount = recentAttempts.reduce(into: 0) { count, attempt in
            guard let date = ISO8601DateFormatter().date(from: attempt.occurredAt),
                  date >= recentCutoff,
                  date <= now else { return }
            count += 1
        }
        let effectiveCount = max(attemptCount, recentRecordedCount + 1)
        return effectiveCount >= 2 ? 10 : 5
    }

    // Replace with your deployed API URL when available
    // For local development with a running API server, use http://localhost:PORT/api
    static let apiBaseURL: String = {
        // Try reading from Info.plist first
        if let url = Bundle.main.object(forInfoDictionaryKey: "AI_API_BASE_URL") as? String,
           !url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return url.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let url = Bundle.main.object(forInfoDictionaryKey: "MIVO_AUTH_API_URL") as? String,
           !url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return url.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return ""
    }()

    static func verifyEmergencyUnlock(
        reason: String,
        sessions: [Session],
        profile: OnboardingProfile?
    ) async -> EmergencyUnlockReview {
        let trimmed = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        if let aiReview = await OpenRouterService.verifyEmergencyUnlock(
            reason: trimmed,
            profile: profile,
            recentSessions: sessions
        ) {
            return aiReview
        }

        return localEmergencyUnlockReview(reason: trimmed)
    }

    private static func localEmergencyUnlockReview(reason: String) -> EmergencyUnlockReview {
        let lower = reason.lowercased()
        let words = lower.split { !$0.isLetter && !$0.isNumber }
        guard reason.count >= 12, words.count >= 3 else {
            return EmergencyUnlockReview(
                approved: false,
                message: "Write a specific urgent reason, not just a short phrase."
            )
        }

        let urgentTerms = [
            "work", "boss", "client", "meeting", "school", "class", "teacher", "homework",
            "assignment", "parent", "family", "friend", "reply", "message", "call", "email",
            "doctor", "health", "medicine", "medication", "appointment", "bank", "payment",
            "ticket", "travel", "uber", "lyft", "map", "maps", "directions", "safety",
            "emergency", "code", "login", "verification", "two factor", "2fa"
        ]
        let driftTerms = [
            "bored", "scroll", "tiktok", "instagram", "youtube", "reddit", "relax",
            "fun", "idk", "don't know", "dont know", "more time", "just because",
            "habit", "nothing"
        ]

        let hasUrgentTerm = urgentTerms.contains { lower.contains($0) }
        let hasDriftTerm = driftTerms.contains { lower.contains($0) }

        if hasUrgentTerm {
            return EmergencyUnlockReview(
                approved: true,
                message: "Approved for a specific time-sensitive task."
            )
        }

        if hasDriftTerm {
            return EmergencyUnlockReview(
                approved: false,
                message: "That sounds like scrolling drift, not an emergency."
            )
        }

        if words.count >= 7 {
            return EmergencyUnlockReview(
                approved: true,
                message: "Approved because the reason is specific enough to review."
            )
        }

        return EmergencyUnlockReview(
            approved: false,
            message: "Be more specific about why this cannot wait."
        )
    }

    static func recommendFocus(
        focusLevel: Int,
        timeAvailable: Int,
        intendedDuration: Int,
        taskDesc: String?,
        profile: OnboardingProfile?,
        recentSessionSummary: String?
    ) async -> Result<FocusRecommendation, AIServiceError> {
        // If API URL is configured, try online first
        if !apiBaseURL.isEmpty, let url = URL(string: "\(apiBaseURL)/api/ai/recommend-focus") {
            do {
                let body = AIRequestBody(
                    focusLevel: focusLevel,
                    timeAvailable: timeAvailable,
                    intendedDuration: intendedDuration,
                    taskDesc: taskDesc,
                    onboardingProfile: profile.map {
                        .init(
                            primaryIntention: $0.primaryIntention?.rawValue,
                            scrollEstimateMinutes: $0.scrollEstimateMinutes,
                            preferredApps: $0.preferredApps
                        )
                    },
                    recentSessionSummary: recentSessionSummary
                )
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.timeoutInterval = 10
                request.httpBody = try JSONEncoder().encode(body)

                let (data, response) = try await URLSession.shared.data(for: request)
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
                    return .failure(.serverError(httpResponse.statusCode))
                }
                let recommendation = try JSONDecoder().decode(FocusRecommendation.self, from: data)
                return .success(recommendation)
            } catch {
                // Fall through to offline
            }
        }

        // Offline / fallback rule-based recommendation
        return .success(offlineRecommend(
            focusLevel: focusLevel,
            timeAvailable: timeAvailable,
            intendedDuration: intendedDuration
        ))
    }

    // MARK: - Offline AI Engine
    // Rule-based focus recommendation that mirrors the server logic
    // Works entirely offline — no network required
    static func offlineRecommend(
        focusLevel: Int,
        timeAvailable: Int,
        intendedDuration: Int
    ) -> FocusRecommendation {
        // Low focus or very short intended duration → Micro
        if focusLevel <= 2 || intendedDuration <= 10 {
            return FocusRecommendation(
                mode: .micro,
                workMinutes: 7,
                restMinutes: 2,
                rationale: "Your focus feels low right now. A short 7-minute burst is better than forcing a long session. Small wins matter.",
                dailySchedule: "Try one micro session now, then reassess in 30 minutes."
            )
        }

        // High focus + plenty of time → Classic 50/10 or 60/5
        if focusLevel >= 4 && timeAvailable >= 50 {
            let work = timeAvailable >= 60 ? 60 : 50
            let rest = work == 60 ? 5 : 10
            return FocusRecommendation(
                mode: .classic,
                workMinutes: work,
                restMinutes: rest,
                rationale: "You have good focus and plenty of time. A \(work)/\(rest) session will let you go deep without burning out.",
                dailySchedule: "One session now, one more this afternoon if needed."
            )
        }

        // Uncertain or wandering focus → Adaptive
        if focusLevel == 3 && timeAvailable >= 30 {
            return FocusRecommendation(
                mode: .adaptive,
                workMinutes: 10,
                restMinutes: 5,
                rationale: "With a middling focus level, starting adaptive lets Mivo extend your session as you warm up. No pressure to commit upfront.",
                dailySchedule: "Begin with 10 minutes and see how you feel."
            )
        }

        // Studying or structured need → Academic
        if intendedDuration >= 25 && focusLevel >= 3 {
            return FocusRecommendation(
                mode: .academic,
                workMinutes: 25,
                restMinutes: 5,
                rationale: "A 25/5 sprint gives your brain clear on/off cycles. It works especially well when you need structure to stay on task.",
                dailySchedule: "Aim for 2–4 sprints total today."
            )
        }

        // Default → Classic 25/5
        return FocusRecommendation(
            mode: .classic,
            workMinutes: 25,
            restMinutes: 5,
            rationale: "A classic 25-minute session is a solid starting point. It's long enough to get into flow but short enough to not feel daunting.",
            dailySchedule: "One session now. Add another later if you have time."
        )
    }

    static func recommendProtectedApps(
        profile: OnboardingProfile?,
        selectedApps: [String],
        recentSessionSummary: String?
    ) async -> ProtectedAppRecommendation {
        if !apiBaseURL.isEmpty, let url = URL(string: "\(apiBaseURL)/api/ai/recommend-protected-apps") {
            do {
                let body = AIRequestBody(
                    focusLevel: 3,
                    timeAvailable: 60,
                    intendedDuration: 25,
                    taskDesc: nil,
                    onboardingProfile: profile.map {
                        .init(
                            primaryIntention: $0.primaryIntention?.rawValue,
                            scrollEstimateMinutes: $0.scrollEstimateMinutes,
                            preferredApps: selectedApps.isEmpty ? $0.preferredApps : selectedApps
                        )
                    },
                    recentSessionSummary: recentSessionSummary
                )
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.timeoutInterval = 8
                request.httpBody = try JSONEncoder().encode(body)

                let (data, response) = try await URLSession.shared.data(for: request)
                if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                    if let decoded = try? JSONDecoder().decode(ProtectedAppRecommendation.self, from: data) {
                        return decoded
                    }
                    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        let apps = json["apps"] as? [String] ?? json["recommendedApps"] as? [String] ?? []
                        let rationale = json["rationale"] as? String ?? "Recommended from your onboarding answers and recent patterns."
                        if !apps.isEmpty {
                            return ProtectedAppRecommendation(apps: apps, rationale: rationale)
                        }
                    }
                }
            } catch {
                // fall back to offline recommendation
            }
        }

        return offlineProtectedAppRecommendation(profile: profile, selectedApps: selectedApps)
    }

    static func offlineProtectedAppRecommendation(profile: OnboardingProfile?, selectedApps: [String]) -> ProtectedAppRecommendation {
        let commonDistractions = ["TikTok", "Instagram", "YouTube", "Reddit", "Twitter / X", "Snapchat", "Facebook", "Threads"]
        let chosen = selectedApps.isEmpty ? (profile?.preferredApps ?? []) : selectedApps

        var scores: [String: Int] = Dictionary(uniqueKeysWithValues: commonDistractions.map { ($0, 1) })
        for app in chosen {
            scores[app, default: 1] += 5
        }

        if let intentions = profile?.intentions {
            if intentions.contains(.killTime) || intentions.contains(.bored) {
                scores["TikTok", default: 1] += 3
                scores["Instagram", default: 1] += 3
                scores["YouTube", default: 1] += 2
                scores["Reddit", default: 1] += 2
            }
            if intentions.contains(.relax) {
                scores["YouTube", default: 1] += 3
                scores["Instagram", default: 1] += 2
                scores["TikTok", default: 1] += 2
            }
            if intentions.contains(.lookingForSomethingSpecific) {
                scores["YouTube", default: 1] += 2
                scores["Reddit", default: 1] += 2
                scores["Twitter / X", default: 1] += 1
            }
        }

        if let primary = profile?.primaryIntention {
            switch primary {
            case .killTime, .bored:
                scores["TikTok", default: 1] += 2
                scores["Instagram", default: 1] += 2
            case .relax:
                scores["YouTube", default: 1] += 2
            case .lookingForSomethingSpecific:
                scores["Reddit", default: 1] += 1
            }
        }

        let apps = scores
            .sorted { lhs, rhs in
                if lhs.value == rhs.value { return lhs.key < rhs.key }
                return lhs.value > rhs.value
            }
            .prefix(4)
            .map(\.key)

        let rationale: String
        if chosen.isEmpty {
            rationale = "Start with the apps most likely to create quick, repeated checking loops."
        } else {
            rationale = "Based on what you selected, these are the apps Mivo would protect first."
        }

        return ProtectedAppRecommendation(apps: apps, rationale: rationale)
    }

    static func makeScreenTimeReductionPlan(
        sessions: [Session],
        truthChecks: [TruthCheckGuess],
        todayScreenTimeMinutes: Int?,
        profile: OnboardingProfile?,
        dailyObservations: [DailyScreenTimeObservation] = []
    ) -> ScreenTimeReductionPlan {
        // Plan structure:
        //   • Days 1–3: 3-day observation period. No enforced cap — Mivo just
        //     records the user's actual usage so it can build a personalized
        //     starting target from real data.
        //   • Plan day 1 (overall day 4): target equals the average of the
        //     user's onboarding report and the 3 observed daily totals.
        //   • Week 1 of plan (days 1–7): a "lenient week" — every day is a bit
        //     harder by 3 min/day.
        //   • Week 2+: the per-day decrement grows by 1 min per week (week 2 is
        //     -4/day, week 3 is -5/day, …), so it gets harder week by week
        //     "slowly but surely."
        //   • Floor at the user's daily-scroll goal (set in onboarding), or 30
        //     min if no goal is on file.
        let daysNeeded = 3
        let floorMinutes = max(15, profile?.dailyScrollGoalMinutes ?? 30)
        let observedDailyTotals = observedDailyScrollTotals(
            sessions: sessions,
            truthChecks: truthChecks,
            dailyObservations: dailyObservations
        )
        let totalsByDate = Dictionary(uniqueKeysWithValues: observedDailyTotals.map { ($0.date, $0.minutes) })
        let observationStart = observationStartDate(profile: profile, observedDailyTotals: observedDailyTotals)
        let completedCalendarDays = completedObservationDays(since: observationStart)
        let daysCollected = min(daysNeeded, completedCalendarDays)
        let observedSamples = observationDateKeys(from: observationStart, count: daysCollected)
            .compactMap { totalsByDate[$0] }
        let fallbackEstimate = max(profile?.scrollEstimateMinutes ?? 90, todayScreenTimeMinutes ?? 0, 45)
        let partialObservedAverage = averageMinutes(observedSamples)
        let baseline = max(partialObservedAverage ?? fallbackEstimate, 20)

        guard daysCollected >= daysNeeded else {
            // Observation period: no cap, just track usage.  Windows are
            // suggested from the user's preferred times (or sensible defaults)
            // but don't enforce a minute limit.
            let userWindows = userPreferredScrollWindows(from: profile, targetMinutes: baseline)
            let collectionWindows = userWindows.isEmpty ? recommendedScrollWindows(from: sessions, targetMinutes: baseline) : userWindows
            let observationWindows = collectionWindows.map { w in
                ScreenScrollWindow(
                    id: w.id, title: w.title, startHour: w.startHour, endHour: w.endHour,
                    minutes: 0,
                    reason: w.reason
                )
            }
            let remaining = max(0, daysNeeded - daysCollected)
            let dayLabel = min(daysCollected + 1, daysNeeded)
            return ScreenTimeReductionPlan(
                id: "collecting-\(daysCollected)",
                collecting: true,
                daysCollected: daysCollected,
                daysNeeded: daysNeeded,
                dayIndex: 0,
                baselineMinutes: baseline,
                targetMinutes: 0,
                strictnessPercent: 0,
                summary: "Day \(dayLabel) of \(daysNeeded) — observation mode. \(remaining) day\(remaining == 1 ? "" : "s") left, then your week-1 lenient plan begins from your self-report plus these 3 observed days.",
                decisionReason: "Mivo observes freely for 3 days — no cap, no restrictions. Plan day 1 starts at the average of your onboarding report and the 3 observed daily totals.",
                windows: observationWindows
            )
        }

        // Baseline after observation: onboarding self-report + the first 3
        // observed daily totals, averaged as separate inputs. Keeping the first
        // 3 days anchors the plan to the observation window instead of letting
        // the baseline drift after the plan starts.
        let missingDayFallback = max(profile?.scrollEstimateMinutes ?? 45, 20)
        let observationTotals = observationDateKeys(from: observationStart, count: daysNeeded)
            .map { totalsByDate[$0] ?? missingDayFallback }
        let blendedBaseline: Int = {
            var samples = observationTotals
            if let reported = profile?.scrollEstimateMinutes, reported > 0 {
                samples.append(reported)
            }
            return max(floorMinutes, averageMinutes(samples) ?? baseline)
        }()

        // dayIndex = 1 on the first plan day (overall day 4).
        let dayIndex = max(1, completedCalendarDays - daysNeeded + 1)
        let target = personalizedTargetMinutes(dayIndex: dayIndex, baseline: blendedBaseline, floor: floorMinutes)
        let strictness = max(0, min(95, Int(((Double(blendedBaseline) - Double(target)) / Double(max(blendedBaseline, 1)) * 100).rounded())))
        let activeWindows = recommendedScrollWindows(from: sessions, targetMinutes: target)

        let weekNum = (dayIndex - 1) / 7 + 1
        let perDayDecrement = 3 + (weekNum - 1)  // 3 for week 1, 4 for week 2, …
        let summaryLine: String
        if dayIndex == 1 {
            summaryLine = "Plan day 1 — week 1 starts at your blended baseline of \(blendedBaseline) min. This averages your self-report with the 3 observed days."
        } else if weekNum == 1 {
            summaryLine = "Plan day \(dayIndex) — lenient week 1. Today's target is \(target) min, \(blendedBaseline - target) min below your blended baseline."
        } else {
            summaryLine = "Plan day \(dayIndex) — week \(weekNum). Today's target is \(target) min (-\(perDayDecrement) min/day this week, \(strictness)% below your blended baseline)."
        }

        return ScreenTimeReductionPlan(
            id: "active-\(dayIndex)-\(target)",
            collecting: false,
            daysCollected: daysCollected,
            daysNeeded: daysNeeded,
            dayIndex: dayIndex,
            baselineMinutes: blendedBaseline,
            targetMinutes: target,
            strictnessPercent: strictness,
            summary: summaryLine,
            decisionReason: "Plan day 1 = the average of your onboarding report and the 3 observed daily totals. Week 1 trims 3 min/day; each week after that the daily trim grows by 1 min, with a \(floorMinutes)-min floor.",
            windows: activeWindows
        )
    }

    private static func observedDailyScrollTotals(
        sessions: [Session],
        truthChecks: [TruthCheckGuess],
        dailyObservations: [DailyScreenTimeObservation]
    ) -> [(date: String, minutes: Int)] {
        var totals = Dictionary(grouping: sessions, by: \.date)
            .mapValues { daySessions in
                daySessions.reduce(0) { $0 + max(0, $1.actualDuration) }
            }

        for observation in dailyObservations {
            totals[observation.date] = max(totals[observation.date, default: 0], max(0, observation.minutes))
        }

        for check in truthChecks {
            totals[check.date] = max(totals[check.date, default: 0], max(0, check.actual))
        }

        return totals
            .map { (date: $0.key, minutes: $0.value) }
    }

    private static func observationStartDate(
        profile: OnboardingProfile?,
        observedDailyTotals: [(date: String, minutes: Int)]
    ) -> Date {
        let calendar = Calendar.current
        let iso = ISO8601DateFormatter()
        if let startedAt = profile?.observationStartedAt,
           let date = iso.date(from: startedAt) {
            return calendar.startOfDay(for: date)
        }

        let dayFormatter = MivoDay.formatter
        if let firstObservedKey = observedDailyTotals.map(\.date).min(),
           let firstObservedDate = dayFormatter.date(from: firstObservedKey) {
            return calendar.startOfDay(for: firstObservedDate)
        }

        return calendar.startOfDay(for: Date())
    }

    private static func completedObservationDays(since startDate: Date, now: Date = Date()) -> Int {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: startDate)
        let today = calendar.startOfDay(for: now)
        return max(0, calendar.dateComponents([.day], from: start, to: today).day ?? 0)
    }

    private static func observationDateKeys(from startDate: Date, count: Int) -> [String] {
        guard count > 0 else { return [] }

        let calendar = Calendar.current
        let formatter = MivoDay.formatter
        let start = calendar.startOfDay(for: startDate)

        return (0..<count).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: start).map { formatter.string(from: $0) }
        }
    }

    private static func averageMinutes(_ samples: [Int]) -> Int? {
        guard !samples.isEmpty else { return nil }
        let total = samples.reduce(0, +)
        return Int((Double(total) / Double(samples.count)).rounded())
    }

    /// Computes the personalized daily target for plan day `dayIndex`.
    ///
    /// - Day 1: equals `baseline` (self-report plus 3 observed days averaged).
    /// - Week 1 (days 1–7): per-day decrement of 3 min.
    /// - Week 2+: per-day decrement grows by 1 min per week (week 2 = -4/day,
    ///   week 3 = -5/day, …).
    /// - Floored at `floor`.
    static func personalizedTargetMinutes(dayIndex: Int, baseline: Int, floor: Int) -> Int {
        guard dayIndex > 1 else { return max(floor, baseline) }
        var total = baseline
        for day in 2...dayIndex {
            // Decrement is determined by the week the *previous* day belongs to —
            // i.e. day 2 still uses week-1 decrement; day 9 uses week-2 decrement.
            let weekNumOfPriorDay = (day - 2) / 7 + 1
            let dailyDecrement = 3 + (weekNumOfPriorDay - 1)
            total -= dailyDecrement
            if total <= floor { return floor }
        }
        return max(floor, total)
    }

    /// How many plan days the personalized ramp takes to reach `goal` starting
    /// from `baseline`. Returns 1 if the baseline already meets the goal.
    /// Capped at 365 days for safety.
    static func daysUntilGoalReached(baseline: Int, goal: Int) -> Int {
        guard baseline > goal else { return 1 }
        for day in 1...365 {
            if personalizedTargetMinutes(dayIndex: day, baseline: baseline, floor: goal) <= goal {
                return day
            }
        }
        return 365
    }

    static func makeScreenTimeReductionPlanOnline(
        sessions: [Session],
        truthChecks: [TruthCheckGuess],
        todayScreenTimeMinutes: Int?,
        profile: OnboardingProfile?,
        dailyObservations: [DailyScreenTimeObservation] = []
    ) async -> ScreenTimeReductionPlan {
        let local = makeScreenTimeReductionPlan(
            sessions: sessions,
            truthChecks: truthChecks,
            todayScreenTimeMinutes: todayScreenTimeMinutes,
            profile: profile,
            dailyObservations: dailyObservations
        )
        guard !local.collecting else { return local }
        if let ai = await OpenRouterService.makePersonalizedPlan(
            sessions: sessions,
            profile: profile,
            localPlan: local
        ) {
            // AI personalizes the explanation only. Targets and windows stay on
            // the deterministic engine shared by Home, Settings, and enforcement.
            return ScreenTimeReductionPlan(
                id: "\(local.id)-narrative",
                collecting: local.collecting,
                daysCollected: local.daysCollected,
                daysNeeded: local.daysNeeded,
                dayIndex: local.dayIndex,
                baselineMinutes: local.baselineMinutes,
                targetMinutes: local.targetMinutes,
                strictnessPercent: local.strictnessPercent,
                summary: ai.summary,
                decisionReason: ai.decisionReason,
                windows: local.windows
            )
        }
        return local
    }

    private static func userPreferredScrollWindows(from profile: OnboardingProfile?, targetMinutes: Int) -> [ScreenScrollWindow] {
        guard let windows = profile?.preferredScrollWindows, !windows.isEmpty else { return [] }
        let allocations = evenMinuteAllocations(total: max(0, targetMinutes), count: windows.count)

        return windows.enumerated().map { index, window in
            let minutes = allocations.indices.contains(index) ? allocations[index] : 0
            let start = min(max(window.startHour, 0), 23)
            let duration = max(1, min(2, window.endHour - window.startHour))
            return ScreenScrollWindow(
                id: "user-window-\(index + 1)-\(window.startHour)",
                title: "Your session \(index + 1)",
                startHour: start,
                endHour: min(24, start + duration),
                minutes: minutes,
                reason: "You chose this time. Mivo will monitor for 3 days before recommending changes."
            )
        }
    }

    private static func recommendedScrollWindows(from sessions: [Session], targetMinutes: Int) -> [ScreenScrollWindow] {
        let bucketInfo: [(key: String, title: String, start: Int, end: Int, fallbackReason: String)] = [
            ("morning", "Morning check", 8, 9, "Useful if you tend to check early."),
            ("afternoon", "Afternoon reset", 14, 15, "Keeps scrolling away from the whole afternoon."),
            ("evening", "Evening scroll", 19, 20, "Matches common after-school or after-work drift."),
            ("night", "Night cap", 21, 22, "Contains late-night scrolling before it spreads.")
        ]

        var scores = Dictionary(uniqueKeysWithValues: bucketInfo.map { ($0.key, 0) })
        let calendar = Calendar.current
        let formatter = ISO8601DateFormatter()

        for session in sessions {
            guard let start = formatter.date(from: session.startTime) else { continue }
            let hour = calendar.component(.hour, from: start)
            let weight = max(session.actualDuration, 1)
            if hour >= 21 || hour < 6 {
                scores["night", default: 0] += weight
            } else if hour < 12 {
                scores["morning", default: 0] += weight
            } else if hour < 17 {
                scores["afternoon", default: 0] += weight
            } else {
                scores["evening", default: 0] += weight
            }
        }

        let windowCount = adaptiveWindowCount(for: targetMinutes)
        let rankedKeys = scores
            .sorted { lhs, rhs in
                if lhs.value == rhs.value { return lhs.key < rhs.key }
                return lhs.value > rhs.value
            }
            .map(\.key)

        var chosen = Array(rankedKeys.prefix(windowCount))
        if chosen.allSatisfy({ scores[$0, default: 0] == 0 }) {
            chosen = Array(defaultWindowKeys(count: windowCount))
        }

        let allocations = weightedMinuteAllocations(
            keys: chosen,
            scores: scores,
            targetMinutes: targetMinutes
        )

        return chosen.enumerated().compactMap { index, key in
            guard let info = bucketInfo.first(where: { $0.key == key }) else { return nil }
            let minutes = allocations.indices.contains(index) ? allocations[index] : 0
            let reason = scores[key, default: 0] > 0
                ? "Chosen because your collected sessions cluster here."
                : info.fallbackReason
            let windowSpanHours = targetMinutes > 180 && minutes > 60 ? 2 : 1
            return ScreenScrollWindow(
                id: "\(key)-\(index)",
                title: "Scroll session \(index + 1)",
                startHour: info.start,
                endHour: min(24, info.start + windowSpanHours),
                minutes: minutes,
                reason: reason
            )
        }
    }

    private static func adaptiveWindowCount(for targetMinutes: Int) -> Int {
        if targetMinutes > 180 { return 4 }
        if targetMinutes > 90 { return 3 }
        return 2
    }

    private static func defaultWindowKeys(count: Int) -> [String] {
        Array(["morning", "afternoon", "evening", "night"].prefix(max(2, min(4, count))))
    }

    private static func evenMinuteAllocations(total: Int, count: Int) -> [Int] {
        guard count > 0 else { return [] }
        guard total > 0 else { return Array(repeating: 0, count: count) }
        let base = total / count
        let remainder = total % count
        return (0..<count).map { base + ($0 < remainder ? 1 : 0) }
    }

    private static func weightedMinuteAllocations(keys: [String], scores: [String: Int], targetMinutes: Int) -> [Int] {
        guard !keys.isEmpty else { return [] }
        guard targetMinutes > 0 else { return Array(repeating: 0, count: keys.count) }

        let rawWeights = keys.map { max(scores[$0, default: 0], 0) }
        let totalRaw = rawWeights.reduce(0, +)
        if totalRaw == 0 {
            return evenMinuteAllocations(total: targetMinutes, count: keys.count)
        }

        let smoothing = max(1, totalRaw / max(1, keys.count * 3))
        let weights = rawWeights.map { $0 + smoothing }
        let totalWeight = weights.reduce(0, +)
        var allocations = weights.map { weight in
            max(5, Int((Double(targetMinutes) * Double(weight) / Double(max(totalWeight, 1))).rounded()))
        }

        var delta = targetMinutes - allocations.reduce(0, +)
        var index = 0
        while delta != 0 && !allocations.isEmpty {
            if delta > 0 {
                allocations[index % allocations.count] += 1
                delta -= 1
            } else if allocations[index % allocations.count] > 5 {
                allocations[index % allocations.count] -= 1
                delta += 1
            }
            index += 1
            if index > 500 { break }
        }
        return allocations
    }

    // New: estimate saved minutes per day for a user (tries remote AI then falls back to offline heuristic)
    static func estimateSavedMinutes(profile: OnboardingProfile?) async -> Int {
        // Try remote API if configured
        if !apiBaseURL.isEmpty, let url = URL(string: "\(apiBaseURL)/api/ai/estimate-saved") {
            do {
                let body = AIRequestBody(
                    focusLevel: 3,
                    timeAvailable: 60,
                    intendedDuration: 25,
                    taskDesc: nil,
                    onboardingProfile: profile.map { .init(primaryIntention: $0.primaryIntention?.rawValue, scrollEstimateMinutes: $0.scrollEstimateMinutes, preferredApps: $0.preferredApps) },
                    recentSessionSummary: nil
                )
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.timeoutInterval = 8
                request.httpBody = try JSONEncoder().encode(body)

                let (data, response) = try await URLSession.shared.data(for: request)
                if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                    // Expect JSON { "estimatedSavedMinutes": 42 }
                    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let v = json["estimatedSavedMinutes"] as? Int {
                        return v
                    }
                }
            } catch {
                // fall through to offline
            }
        }

        // Offline heuristic: enhanced version that uses onboarding answers
        let scroll = Double(profile?.scrollEstimateMinutes ?? 60)

        // Conservative base multiplier
        var multiplier: Double = 0.10

        // Intentions: increase multiplier for more (and more problematic) intentions
        if let ints = profile?.intentions, !ints.isEmpty {
            multiplier += Double(min(ints.count, 4)) * 0.03
            if ints.contains(.killTime) || ints.contains(.bored) { multiplier += 0.18 }
            if ints.contains(.relax) { multiplier += 0.06 }
            if ints.contains(.lookingForSomethingSpecific) { multiplier += 0.01 }
        }

        // Preferred apps: more apps selected => slightly higher multiplier (habit breadth)
        let appsCount = profile?.preferredApps.count ?? 0
        multiplier += min(Double(appsCount) * 0.02, 0.12)

        // Age factor
        var ageFactor = 1.0
        if let age = profile?.age {
            if age < 25 { ageFactor = 1.12 }
            else if age > 54 { ageFactor = 0.92 }
            else if age >= 35 && age <= 44 { ageFactor = 0.97 }
        }

        // Clamp multiplier into sensible bounds
        multiplier = max(0.06, min(multiplier, 0.75))

        // Compute raw estimate
        let raw = scroll * multiplier * ageFactor
        var estimated = Int(raw.rounded())

        // Boost if primary intention is aggressive
        if let primary = profile?.primaryIntention {
            if primary == .killTime || primary == .bored {
                estimated += Int(Double(max(estimated, 1)) * 0.12)
            }
        }

        // Ensure reasonable bounds
        if estimated < 3 { estimated = 3 }
        if estimated > 240 { estimated = 240 }
        return estimated
    }

    // New: estimate a life-year breakdown for visualization. Returns tuple of years per category.
    static func estimateLifeBreakdown(profile: OnboardingProfile?, lifeExpectancy: Int = 80) async -> (sleepYears: Int, workYears: Int, eatYears: Int, basicsYears: Int, scrollYears: Int, freeYears: Int) {
        if !apiBaseURL.isEmpty, let url = URL(string: "\(apiBaseURL)/api/ai/estimate-life-breakdown") {
            do {
                let body = AIRequestBody(
                    focusLevel: 3,
                    timeAvailable: 60,
                    intendedDuration: 25,
                    taskDesc: nil,
                    onboardingProfile: profile.map { .init(primaryIntention: $0.primaryIntention?.rawValue, scrollEstimateMinutes: $0.scrollEstimateMinutes, preferredApps: $0.preferredApps) },
                    recentSessionSummary: nil
                )
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.timeoutInterval = 8
                request.httpBody = try JSONEncoder().encode(body)

                let (data, response) = try await URLSession.shared.data(for: request)
                if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        let s = (json["sleepYears"] as? Int) ?? 0
                        let w = (json["workYears"] as? Int) ?? 0
                        let e = (json["eatYears"] as? Int) ?? 0
                        let b = (json["basicsYears"] as? Int) ?? 0
                        let sc = (json["scrollYears"] as? Int) ?? 0
                        let f = (json["freeYears"] as? Int) ?? max(0, lifeExpectancy - (s + w + e + b + sc))
                        return (s,w,e,b,sc,f)
                    }
                }
            } catch {
                // fall back
            }
        }

        // fallback heuristic similar to previous implementation but using lifeExpectancy param
        let scroll = Double(profile?.scrollEstimateMinutes ?? 60)
        let scrollH = scroll / 60.0
        let sleepH = 8.0
        let workH = 8.0
        let eatH = 2.0
        let basicsH = 1.0
        func years(for hours: Double) -> Int { Int(round((hours / 24.0) * Double(lifeExpectancy))) }
        let s = years(for: sleepH)
        let w = years(for: workH)
        let e = years(for: eatH)
        let b = years(for: basicsH)
        let sc = years(for: scrollH)
        var f = max(0, lifeExpectancy - (s + w + e + b + sc))
        let sum = s + w + e + b + sc + f
        if sum != lifeExpectancy {
            let diff = lifeExpectancy - sum
            f += diff
        }
        return (s,w,e,b,sc,f)
    }
}
