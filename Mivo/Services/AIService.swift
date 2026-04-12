import Foundation

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
        if let url = Bundle.main.object(forInfoDictionaryKey: "AI_API_BASE_URL") as? String, !url.isEmpty {
            return url
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
