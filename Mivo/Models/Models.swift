import Foundation

// MARK: - Types

enum Intention: String, Codable, CaseIterable {
    case killTime = "Kill time"
    case relax = "Relax"
    case bored = "Bored"
    case lookingForSomethingSpecific = "Looking for something specific"
}

enum ReflectionChoice: String, Codable {
    case yes = "Yes"
    case kindOf = "Kind of"
    case no = "No"
}

// MARK: - Models

struct Session: Codable, Identifiable {
    let id: String
    let date: String
    let startTime: String
    let endTime: String
    let plannedDuration: Int
    let actualDuration: Int
    let intention: Intention
    let extendedOnce: Bool
    let reflection: ReflectionChoice?
    let reflectionNote: String
}

struct TruthCheckGuess: Codable, Identifiable {
    let id: String
    let date: String
    let guess: Int
    let actual: Int
}

struct UserProfile: Codable {
    let email: String
    let name: String
    let createdAt: String
    // Optional onboarding profile stored with the user so AI and features can use it
    var onboardingProfile: OnboardingProfile?
}

struct AppSettings: Codable {
    var onboardingComplete: Bool
    var notificationsEnabled: Bool
}

struct OnboardingProfile: Codable {
    var primaryIntention: Intention?
    var scrollEstimateMinutes: Int?
    var preferredApps: [String]
    // allow multiple intentions to be stored from onboarding
    var intentions: [Intention]
    // optional demographic details
    var age: Int?
    var ageRange: String?

    init(primaryIntention: Intention? = nil, scrollEstimateMinutes: Int? = nil, preferredApps: [String] = []) {
        self.primaryIntention = primaryIntention
        self.scrollEstimateMinutes = scrollEstimateMinutes
        self.preferredApps = preferredApps
        self.intentions = []
        self.age = nil
        self.ageRange = nil
    }
}

struct StoredCredentials: Codable {
    let email: String
    let passwordHash: String
}

// MARK: - AI

enum FocusMode: String, Codable, CaseIterable {
    case classic, adaptive, open, micro, academic

    var displayName: String {
        switch self {
        case .classic: return "Classic Focus"
        case .adaptive: return "Adaptive Focus"
        case .open: return "Open Focus"
        case .micro: return "Micro Focus"
        case .academic: return "Academic Reset"
        }
    }

    var description: String {
        switch self {
        case .classic: return "Fixed duration and lock selected apps until the timer ends."
        case .adaptive: return "Starts small and extends automatically if you stay focused."
        case .open: return "No preset time. Timer runs until you end it."
        case .micro: return "Quick 5–10 minute protection."
        case .academic: return "A Mivo speciality:\n25/5 sprint system built for distracted brains."
        }
    }
}

struct FocusRecommendation: Codable {
    let mode: FocusMode
    let workMinutes: Int
    let restMinutes: Int
    let rationale: String
    let dailySchedule: String
}
