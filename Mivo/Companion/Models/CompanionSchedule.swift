import Foundation

/// Day keys for the Companion. Same shape and calendar rules as `MivoDay`
/// (`yyyy-MM-dd`, Gregorian, device time zone) but takes the calendar as a
/// parameter so rollover and time-zone behaviour can be tested, and so this
/// file compiles in the widget target.
enum CompanionDay {
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar
    }

    static func key(_ date: Date, calendar: Calendar = CompanionDay.calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    static func key(offset days: Int, from reference: Date, calendar: Calendar = CompanionDay.calendar) -> String {
        key(calendar.date(byAdding: .day, value: days, to: reference) ?? reference, calendar: calendar)
    }
}

/// A wall-clock time of day, independent of any date.
struct CompanionClockTime: Codable, Equatable, Hashable {
    var minutesFromMidnight: Int

    init(hour: Int, minute: Int = 0) {
        minutesFromMidnight = Self.normalize(hour * 60 + minute)
    }

    init(minutesFromMidnight: Int) {
        self.minutesFromMidnight = Self.normalize(minutesFromMidnight)
    }

    var hour: Int { minutesFromMidnight / 60 }
    var minute: Int { minutesFromMidnight % 60 }

    func adding(minutes: Int) -> CompanionClockTime {
        CompanionClockTime(minutesFromMidnight: minutesFromMidnight + minutes)
    }

    /// The minute-of-day of `date` as the given calendar (and so time zone) sees it.
    static func of(_ date: Date, calendar: Calendar) -> CompanionClockTime {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return CompanionClockTime(hour: parts.hour ?? 0, minute: parts.minute ?? 0)
    }

    /// Whether this time falls in `[start, end)`, wrapping past midnight when
    /// `start > end`. `start == end` is an empty window, not a 24-hour one.
    func isWithin(start: CompanionClockTime, end: CompanionClockTime) -> Bool {
        let m = minutesFromMidnight
        if start.minutesFromMidnight == end.minutesFromMidnight { return false }
        if start.minutesFromMidnight < end.minutesFromMidnight {
            return m >= start.minutesFromMidnight && m < end.minutesFromMidnight
        }
        return m >= start.minutesFromMidnight || m < end.minutesFromMidnight
    }

    /// Next moment at/after `date` that this clock time occurs.
    func nextOccurrence(after date: Date, calendar: Calendar) -> Date? {
        calendar.nextDate(
            after: date,
            matching: DateComponents(hour: hour, minute: minute, second: 0),
            matchingPolicy: .nextTime
        )
    }

    var displayText: String {
        let h12 = hour % 12 == 0 ? 12 : hour % 12
        return String(format: "%d:%02d %@", h12, minute, hour < 12 ? "AM" : "PM")
    }

    private static func normalize(_ minutes: Int) -> Int {
        ((minutes % 1440) + 1440) % 1440
    }
}

/// Quiet hours: the companion sleeps and says nothing. Never affects Mivo's
/// own pauses or shields.
struct CompanionTimeWindow: Codable, Equatable {
    var isEnabled: Bool
    var start: CompanionClockTime
    var end: CompanionClockTime

    static let defaultQuietHours = CompanionTimeWindow(
        isEnabled: true,
        start: CompanionClockTime(hour: 23, minute: 30),
        end: CompanionClockTime(hour: 6, minute: 30)
    )

    func contains(_ date: Date, calendar: Calendar) -> Bool {
        guard isEnabled else { return false }
        return CompanionClockTime.of(date, calendar: calendar).isWithin(start: start, end: end)
    }
}

enum CompanionBedtimePhase: String, Codable, Equatable {
    case none
    /// The hour (configurable) before bedtime: the companion starts to look sleepy.
    case windingDown
    /// Bedtime until wake time.
    case night
}

/// Bedtime behaviour: tired posture and "it's getting late" copy. Distinct from
/// quiet hours — bedtime changes how the companion talks, quiet hours silence it.
struct CompanionBedtime: Codable, Equatable {
    static let windDownRange = 15...180

    var isEnabled: Bool
    var bedtime: CompanionClockTime
    var wakeTime: CompanionClockTime
    var windDownMinutes: Int

    static let `default` = CompanionBedtime(
        isEnabled: true,
        bedtime: CompanionClockTime(hour: 22, minute: 30),
        wakeTime: CompanionClockTime(hour: 7, minute: 0),
        windDownMinutes: 60
    )

    func phase(at date: Date, calendar: Calendar) -> CompanionBedtimePhase {
        guard isEnabled else { return .none }
        let now = CompanionClockTime.of(date, calendar: calendar)
        if now.isWithin(start: bedtime, end: wakeTime) { return .night }
        let windDown = min(max(windDownMinutes, Self.windDownRange.lowerBound), Self.windDownRange.upperBound)
        if now.isWithin(start: bedtime.adding(minutes: -windDown), end: bedtime) { return .windingDown }
        return .none
    }
}
