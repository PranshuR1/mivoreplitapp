import Foundation

/// What a wrapper session is counted in before it starts.
enum WrapperSessionLimit: String, Codable, CaseIterable {
    case reels
    case minutes

    static let reelsPerSession = 10
    static let minutesPerSession = 10
    static let extraReelsPerTopUp = 5

    var title: String {
        switch self {
        case .reels: return "\(Self.reelsPerSession) Reels"
        case .minutes: return "\(Self.minutesPerSession) minutes"
        }
    }
}

/// The small daily allowance of wrapper time. Pure value logic — no clock,
/// no storage — so it can be unit tested. `ReelBalanceStore` persists it.
struct ReelBalance: Codable, Equatable {
    static let dailyAllowanceSeconds = 10 * 60

    /// Calendar day this balance belongs to, as `yyyy-MM-dd`.
    var dayKey: String
    /// Seconds used today out of the daily allowance.
    var spentSeconds: Int
    /// Seconds added today on top of the allowance (see `credit`).
    var bonusSeconds: Int

    init(dayKey: String, spentSeconds: Int = 0, bonusSeconds: Int = 0) {
        self.dayKey = dayKey
        self.spentSeconds = max(0, spentSeconds)
        self.bonusSeconds = max(0, bonusSeconds)
    }

    static func dayKey(for date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    static func fresh(on date: Date, calendar: Calendar = .current) -> ReelBalance {
        ReelBalance(dayKey: dayKey(for: date, calendar: calendar))
    }

    var remainingSeconds: Int {
        max(0, Self.dailyAllowanceSeconds + bonusSeconds - spentSeconds)
    }

    var isEmpty: Bool { remainingSeconds == 0 }

    /// Whole minutes left, rounded up, so "1 minute left" shows until it is really gone.
    var remainingMinutes: Int { (remainingSeconds + 59) / 60 }

    /// The same balance, reset if `date` is a different day than `dayKey`.
    func rolled(to date: Date, calendar: Calendar = .current) -> ReelBalance {
        dayKey == Self.dayKey(for: date, calendar: calendar) ? self : .fresh(on: date, calendar: calendar)
    }

    /// Spends up to `seconds`; returns how many were actually available.
    @discardableResult
    mutating func spend(seconds: Int) -> Int {
        let spendable = min(max(0, seconds), remainingSeconds)
        spentSeconds += spendable
        return spendable
    }

    /// Study time earns wrapper time at a fixed rate, up to a daily cap.
    static let studySecondsPerScrollSecond = 3
    static let dailyEarnCapSeconds = 60 * 60

    /// Wrapper seconds a stretch of study is worth, before the cap.
    static func scrollSeconds(forStudySeconds seconds: Int) -> Int {
        max(0, seconds) / studySecondsPerScrollSecond
    }

    /// Credits `seconds` of study at 3 minutes of study per minute of scroll,
    /// never taking today's earned time past the cap. Returns the wrapper
    /// seconds actually added. Unlike the daily allowance, a credit only lasts
    /// for the day it is earned on.
    @discardableResult
    mutating func creditStudy(seconds: Int) -> Int {
        let room = max(0, Self.dailyEarnCapSeconds - bonusSeconds)
        let earned = min(Self.scrollSeconds(forStudySeconds: seconds), room)
        bonusSeconds += earned
        return earned
    }
}

/// Persists today's `ReelBalance` on this device (UserDefaults), one balance
/// per signed-in account so a second account on the same phone starts clean.
final class ReelBalanceStore {
    static let shared = ReelBalanceStore()
    static let defaultsKey = "mivo.wrapper.reelBalance"

    private let defaults: UserDefaults
    private let calendar: Calendar
    private let now: () -> Date
    private let account: () -> String?

    init(
        defaults: UserDefaults = .standard,
        calendar: Calendar = .current,
        now: @escaping () -> Date = Date.init,
        account: @escaping () -> String? = { StorageService.activeUserEmail }
    ) {
        self.defaults = defaults
        self.calendar = calendar
        self.now = now
        self.account = account
    }

    private var key: String { AccountScopedKey.make(Self.defaultsKey, account: account()) }

    /// Forgets the signed-in account's balance (account deletion).
    func erase() { defaults.removeObject(forKey: key) }

    /// Today's balance, reset to the full allowance on a new day.
    func current() -> ReelBalance {
        let stored = defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(ReelBalance.self, from: $0) }
        let today = now()
        let balance = stored?.rolled(to: today, calendar: calendar) ?? .fresh(on: today, calendar: calendar)
        return balance
    }

    func save(_ balance: ReelBalance) {
        guard let data = try? JSONEncoder().encode(balance) else { return }
        defaults.set(data, forKey: key)
    }
}

/// Keeps one account's stored values apart from another's on the same phone.
enum AccountScopedKey {
    static func make(_ base: String, account: String?) -> String {
        let id = (account ?? "").trimmingCharacters(in: .whitespaces).lowercased()
        return id.isEmpty ? base : "\(base).\(id)"
    }
}
