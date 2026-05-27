import Foundation

// MARK: - OpenRouter Service
enum OpenRouterService {
    private static let apiKey = "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"
    private static let endpoint = URL(string: "https://openrouter.ai/api/v1/chat/completions")!
    // Two models: primary Claude Haiku, fallback Llama (free tier)
    private static let models = ["anthropic/claude-3-haiku", "meta-llama/llama-3-8b-instruct:free"]

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

        return """
You are a compassionate screen-time coach inside Mivo, an iOS focus app.

User profile:
- Primary reason for using Mivo: \(intention)
- Self-reported daily scroll estimate: \(scrollEst) min
- Apps they use most: \(apps)
- Days past observation period: \(dayIndex)
- Observed baseline (avg daily screen time from sessions): \(baseline) min
- Rule-based target today: \(localTarget) min

Recent sessions (last 10):
\(recentSessions.isEmpty ? "None yet." : recentSessions)

Generate a PERSONALIZED screen time plan. Rules:
- Week 1 (days 1–7): target should stay close to baseline — reduce by at most 10%. Floor: 90 min.
- Week 2 (days 8–14): reduce by 10–20%. Floor: 60 min.
- Week 3+ (days 15+): target ~60 min. Max reduction 40%.
- Suggest exactly 2 scroll windows fitting the user's session patterns.
- Be warm and personalized in summary/decisionReason (mention their main app or intention).

Respond ONLY with valid JSON, no markdown, no commentary:
{
  "targetMinutes": <int>,
  "strictnessPercent": <int 0-40>,
  "summary": "<1-2 sentences, personalized>",
  "decisionReason": "<1-2 sentences explaining the plan>",
  "windows": [
    {"title": "<label>", "startHour": <0-23>, "endHour": <1-24>, "minutes": <int>, "reason": "<why>"},
    {"title": "<label>", "startHour": <0-23>, "endHour": <1-24>, "minutes": <int>, "reason": "<why>"}
  ]
}
"""
    }

    private static func callModel(model: String, prompt: String, localPlan: ScreenTimeReductionPlan) async -> ScreenTimeReductionPlan? {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("https://mivo.app", forHTTPHeaderField: "HTTP-Referer")
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
                title: w.title ?? (idx == 0 ? "Scroll session 1" : "Scroll session 2"),
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
        profile: OnboardingProfile?
    ) -> ScreenTimeReductionPlan {
        // Plan structure:
        //   • Days 1–3: 3-day observation period. No enforced cap — Mivo just
        //     records the user's actual usage so it can build a personalized
        //     starting target from real data.
        //   • Day 4+: Personalized plan. Day 1 of the plan equals the average
        //     of the 3 observation days; each subsequent day trims 10 minutes,
        //     down to a 30-minute floor.
        let daysNeeded = 3
        let perDayDecrement = 10
        let floorMinutes = 30
        let dailyTotals = Dictionary(grouping: sessions, by: \.date)
            .mapValues { daySessions in
                daySessions.reduce(0) { $0 + $1.actualDuration }
            }
        let observedDays = Set(Array(dailyTotals.keys) + truthChecks.map(\.date))
        let daysCollected = observedDays.count
        let fallbackEstimate = max(profile?.scrollEstimateMinutes ?? 90, todayScreenTimeMinutes ?? 0, 45)
        let baseline = max(
            dailyTotals.isEmpty ? fallbackEstimate : dailyTotals.values.reduce(0, +) / max(dailyTotals.count, 1),
            20
        )

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
                summary: "Day \(dayLabel) of \(daysNeeded) — observation mode. \(remaining) day\(remaining == 1 ? "" : "s") left before your personalized plan starts at the average of these 3 days.",
                decisionReason: "Mivo observes freely for 3 days — no cap, no restrictions. Your personalized plan begins on day 4 at the average of these 3 days, then trims by \(perDayDecrement) min per day down to a \(floorMinutes)-min floor.",
                windows: observationWindows
            )
        }

        // Past-3-day average — the 3 most-recent observed daily totals.
        let recentTotals = dailyTotals
            .sorted { $0.key > $1.key }
            .prefix(3)
            .map(\.value)
        let pastThreeDayAverage: Int = {
            guard !recentTotals.isEmpty else { return baseline }
            return max(floorMinutes, recentTotals.reduce(0, +) / recentTotals.count)
        }()

        // Plan day 1 = past-3-day average; subtract 10 min per subsequent day.
        let dayIndex = max(1, daysCollected - daysNeeded + 1)
        let decremented = pastThreeDayAverage - (dayIndex - 1) * perDayDecrement
        let target = max(floorMinutes, decremented)
        let strictness = max(0, min(95, Int(((Double(pastThreeDayAverage) - Double(target)) / Double(max(pastThreeDayAverage, 1)) * 100).rounded())))
        let activeWindows = recommendedScrollWindows(from: sessions, targetMinutes: target)

        let summaryLine: String
        if dayIndex == 1 {
            summaryLine = "Plan day 1 — starting at your 3-day observation average of \(pastThreeDayAverage) min. Mivo will trim this by \(perDayDecrement) min each day."
        } else {
            summaryLine = "Plan day \(dayIndex) — target is \(target) min/day, \(pastThreeDayAverage - target) min below your 3-day observation average and \(strictness)% lighter overall."
        }

        return ScreenTimeReductionPlan(
            id: "active-\(dayIndex)-\(target)",
            collecting: false,
            daysCollected: daysCollected,
            daysNeeded: daysNeeded,
            dayIndex: dayIndex,
            baselineMinutes: pastThreeDayAverage,
            targetMinutes: target,
            strictnessPercent: strictness,
            summary: summaryLine,
            decisionReason: "Mivo starts your personalized plan at the average of your 3 observation days, then trims by \(perDayDecrement) min each day down to a \(floorMinutes)-min floor. The two scroll windows split the daily target where your sessions cluster.",
            windows: activeWindows
        )
    }

    static func makeScreenTimeReductionPlanOnline(
        sessions: [Session],
        truthChecks: [TruthCheckGuess],
        todayScreenTimeMinutes: Int?,
        profile: OnboardingProfile?
    ) async -> ScreenTimeReductionPlan {
        let local = makeScreenTimeReductionPlan(
            sessions: sessions,
            truthChecks: truthChecks,
            todayScreenTimeMinutes: todayScreenTimeMinutes,
            profile: profile
        )
        guard !local.collecting else { return local }
        if let ai = await OpenRouterService.makePersonalizedPlan(
            sessions: sessions,
            profile: profile,
            localPlan: local
        ) { return ai }
        return local
    }

    private static func userPreferredScrollWindows(from profile: OnboardingProfile?, targetMinutes: Int) -> [ScreenScrollWindow] {
        guard let windows = profile?.preferredScrollWindows, !windows.isEmpty else { return [] }
        let firstMinutes = max(8, Int((Double(targetMinutes) * 0.55).rounded()))
        let secondMinutes = max(7, targetMinutes - firstMinutes)

        return windows.prefix(2).enumerated().map { index, window in
            let minutes = index == 0 ? firstMinutes : secondMinutes
            return ScreenScrollWindow(
                id: "user-window-\(index + 1)-\(window.startHour)",
                title: index == 0 ? "Your session 1" : "Your session 2",
                startHour: min(max(window.startHour, 0), 23),
                endHour: min(24, max(window.startHour + 1, window.endHour)),
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

        let rankedKeys = scores
            .sorted { lhs, rhs in
                if lhs.value == rhs.value { return lhs.key < rhs.key }
                return lhs.value > rhs.value
            }
            .map(\.key)

        var chosen = Array(rankedKeys.prefix(2))
        if chosen.allSatisfy({ scores[$0, default: 0] == 0 }) {
            chosen = ["afternoon", "evening"]
        }

        let firstMinutes = max(8, Int((Double(targetMinutes) * 0.55).rounded()))
        let secondMinutes = max(7, targetMinutes - firstMinutes)

        return chosen.enumerated().compactMap { index, key in
            guard let info = bucketInfo.first(where: { $0.key == key }) else { return nil }
            let minutes = index == 0 ? firstMinutes : secondMinutes
            let reason = scores[key, default: 0] > 0
                ? "Chosen because your collected sessions cluster here."
                : info.fallbackReason
            let windowSpanHours = minutes >= 20 ? 2 : 1
            return ScreenScrollWindow(
                id: "\(key)-\(index)",
                title: index == 0 ? "Scroll session 1" : "Scroll session 2",
                startHour: info.start,
                endHour: min(24, info.start + windowSpanHours),
                minutes: minutes,
                reason: reason
            )
        }
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
