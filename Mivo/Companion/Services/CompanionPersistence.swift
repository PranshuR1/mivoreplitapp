import Foundation

/// Where companion data lives. The default uses Mivo's existing per-user
/// `StorageService` (UserDefaults, scoped by account email) — no new
/// persistence framework.
protocol CompanionPersistence {
    func loadPreferences() -> CompanionPreferences?
    func savePreferences(_ value: CompanionPreferences)
    func loadRuntime() -> CompanionRuntime?
    func saveRuntime(_ value: CompanionRuntime)
    func loadProgress() -> CompanionProgress?
    func saveProgress(_ value: CompanionProgress)
}

struct StorageCompanionPersistence: CompanionPersistence {
    let email: String

    func loadPreferences() -> CompanionPreferences? {
        StorageService.load(CompanionPreferences.self, forKey: .companionPreferences, email: email)
    }
    func savePreferences(_ value: CompanionPreferences) {
        StorageService.save(value, forKey: .companionPreferences, email: email)
    }
    func loadRuntime() -> CompanionRuntime? {
        StorageService.load(CompanionRuntime.self, forKey: .companionRuntime, email: email)
    }
    func saveRuntime(_ value: CompanionRuntime) {
        StorageService.save(value, forKey: .companionRuntime, email: email)
    }
    func loadProgress() -> CompanionProgress? {
        StorageService.load(CompanionProgress.self, forKey: .companionProgress, email: email)
    }
    func saveProgress(_ value: CompanionProgress) {
        StorageService.save(value, forKey: .companionProgress, email: email)
    }
}

/// Used by tests and previews.
final class InMemoryCompanionPersistence: CompanionPersistence {
    var preferences: CompanionPreferences?
    var runtime: CompanionRuntime?
    var progress: CompanionProgress?

    init(preferences: CompanionPreferences? = nil, runtime: CompanionRuntime? = nil, progress: CompanionProgress? = nil) {
        self.preferences = preferences
        self.runtime = runtime
        self.progress = progress
    }

    func loadPreferences() -> CompanionPreferences? { preferences }
    func savePreferences(_ value: CompanionPreferences) { preferences = value }
    func loadRuntime() -> CompanionRuntime? { runtime }
    func saveRuntime(_ value: CompanionRuntime) { runtime = value }
    func loadProgress() -> CompanionProgress? { progress }
    func saveProgress(_ value: CompanionProgress) { progress = value }
}
