import Foundation

/// A lock the person sets in a calm moment so Mivo can't be switched off in
/// the moment the urge is strongest. It has two layers:
///
/// - Inside Mivo: protection, the protected-app list, opening social apps in
///   Mivo and late-night protection can't be turned off or shrunk, signing
///   out keeps the shields up, and "Reset all data" is refused.
/// - In iOS 26.4 and later: Mivo makes up the Screen Time passcode, the person
///   types it into Settings ▸ Screen Time ▸ Lock Screen Time Settings, and Mivo
///   keeps it hidden. iOS then asks for that passcode before turning off
///   Mivo's Screen Time access or deleting Mivo.
///
/// Both come undone the same way: ask, wait out the delay chosen when locking,
/// then end the lock within `openWindow`. The wait can grow while locked but
/// never shrink, and an unlock left unused lapses back to locked. Only
/// `MivoLockManager.endLock()` lifts the in-app holds, so the open phase alone
/// releases nothing.
struct MivoLock: Codable, Equatable {
    enum Phase: Equatable {
        /// Nothing asked: every off-switch is held.
        case locked
        /// Asked to unlock; the lock can be ended from `opensAt`.
        case waiting(opensAt: Date)
        /// The wait is over; the lock can be ended until `closesAt`.
        case open(closesAt: Date)
    }

    /// How long an unlock stays usable once its wait is over. Short, so a wait
    /// asked for in a bad moment and then forgotten doesn't leave Mivo open.
    static let openWindow: TimeInterval = 30 * 60

    static let delayChoices: [TimeInterval] = [
        60 * 60,
        24 * 60 * 60,
        3 * 24 * 60 * 60,
        7 * 24 * 60 * 60
    ]
    static let defaultDelay: TimeInterval = 24 * 60 * 60

    var lockedAt: Date
    var delay: TimeInterval
    var unlockRequestedAt: Date?
    /// The person said they set Mivo's code as the Screen Time passcode.
    var usesScreenTimePasscode: Bool

    func phase(at now: Date) -> Phase {
        guard let requested = unlockRequestedAt else { return .locked }
        let opensAt = requested.addingTimeInterval(delay)
        if now < opensAt { return .waiting(opensAt: opensAt) }
        let closesAt = opensAt.addingTimeInterval(Self.openWindow)
        return now < closesAt ? .open(closesAt: closesAt) : .locked
    }

    /// Starts the wait. Does nothing while a wait is already running or open,
    /// so asking twice can't restart or skip it.
    mutating func requestUnlock(at now: Date) {
        guard phase(at: now) == .locked else { return }
        unlockRequestedAt = now
    }

    mutating func stayLocked() {
        unlockRequestedAt = nil
    }

    /// The wait only grows. A longer wait also pushes back a running one.
    mutating func lengthenDelay(to newDelay: TimeInterval) {
        delay = max(delay, newDelay)
    }

    static func delayLabel(_ delay: TimeInterval) -> String {
        let hours = Int((delay / 3600).rounded())
        if hours < 24 { return hours == 1 ? "1 hour" : "\(hours) hours" }
        let days = hours / 24
        if days == 7 { return "1 week" }
        return days == 1 ? "1 day" : "\(days) days"
    }
}

/// The Screen Time passcode Mivo makes up. Random, and never an easy pattern,
/// so it can't be guessed or remembered from its shape.
enum MivoLockCode {
    static func make() -> String {
        var generator = SystemRandomNumberGenerator()
        return make(using: &generator)
    }

    static func make<G: RandomNumberGenerator>(using generator: inout G) -> String {
        while true {
            let code = (0..<4).map { _ in String(Int.random(in: 0...9, using: &generator)) }.joined()
            if isHardToGuess(code) { return code }
        }
    }

    /// Four digits, at least three different ones, not a straight run up or
    /// down (1234, 8765), and not a year (19xx, 20xx).
    static func isHardToGuess(_ code: String) -> Bool {
        let digits = code.compactMap(\.wholeNumberValue)
        guard code.count == 4, digits.count == 4 else { return false }
        guard Set(digits).count >= 3 else { return false }
        let steps = zip(digits.dropFirst(), digits).map { $0 - $1 }
        if steps.allSatisfy({ $0 == 1 }) || steps.allSatisfy({ $0 == -1 }) { return false }
        if code.hasPrefix("19") || code.hasPrefix("20") { return false }
        return true
    }
}

/// Reads the time from a server instead of the iPhone clock, so the wait
/// can't be skipped by moving the date forward in Settings.
enum MivoTrustedClock {
    /// The `Date` header plus any `Age` a cache added to it.
    static func date(fromDateHeader header: String, age: String?) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        guard let date = formatter.date(from: header) else { return nil }
        let ageSeconds = age.flatMap { TimeInterval($0.trimmingCharacters(in: .whitespaces)) } ?? 0
        return date.addingTimeInterval(max(0, ageSeconds))
    }

    static func now() async -> Date? {
        var components = URLComponents(string: "https://usemivo.app/")!
        components.queryItems = [URLQueryItem(name: "t", value: UUID().uuidString)]
        var request = URLRequest(
            url: components.url!,
            cachePolicy: .reloadIgnoringLocalAndRemoteCacheData,
            timeoutInterval: 10
        )
        request.httpMethod = "HEAD"
        guard let (_, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse,
              let header = http.value(forHTTPHeaderField: "Date") else { return nil }
        return date(fromDateHeader: header, age: http.value(forHTTPHeaderField: "Age"))
    }
}
