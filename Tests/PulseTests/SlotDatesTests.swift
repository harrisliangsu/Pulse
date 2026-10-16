import Foundation
import Testing
@testable import Pulse

/// `SlotDates` must answer exactly what the slot formatter answers: it only
/// replaces the formatter for speed.
@Suite("Slot dates")
struct SlotDatesTests {
    private static func formatter(in zone: TimeZone) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        formatter.timeZone = zone
        return formatter
    }

    /// Zones with clock changes of every kind: an hour each way, half an hour
    /// (Lord Howe), at midnight (Santiago, Havana), none at all (Shanghai).
    static let zones = ["America/New_York", "Europe/Berlin", "Australia/Lord_Howe",
                        "America/Santiago", "America/Havana", "Asia/Shanghai"]

    @Test("Every quarter-hour of two years reads back as the formatter reads it", arguments: zones)
    func matchesTheFormatter(zone: String) throws {
        let formatter = Self.formatter(in: try #require(TimeZone(identifier: zone)))
        // 2025 and 2026, with every clock change in them.
        var instant = Date(timeIntervalSince1970: 1_735_689_600 - 86_400)
        let end = instant + 2 * 366 * 86_400
        while instant < end {
            let key = formatter.string(from: instant)
            #expect(SlotDates.date(key, formatter: formatter) == formatter.date(from: key), "\(zone) \(key)")
            instant += 900
        }
    }

    @Test("Every midnight key, the shape the day archive asks for, reads back as the formatter reads it", arguments: zones)
    func midnights(zone: String) throws {
        let formatter = Self.formatter(in: try #require(TimeZone(identifier: zone)))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = formatter.timeZone
        var day = try #require(calendar.date(from: DateComponents(year: 2025, month: 1, day: 1, hour: 12)))
        for _ in 0..<730 {
            let parts = calendar.dateComponents([.year, .month, .day], from: day)
            let key = String(format: "%04d-%02d-%02d 00:00", parts.year!, parts.month!, parts.day!)
            #expect(SlotDates.date(key, formatter: formatter) == formatter.date(from: key), "\(zone) \(key)")
            day = try #require(calendar.date(byAdding: .day, value: 1, to: day))
        }
    }

    @Test("Anything not in the slot shape goes to the formatter")
    func otherShapes() throws {
        let formatter = Self.formatter(in: try #require(TimeZone(identifier: "Europe/Berlin")))
        for key in ["", "2026-10-14", "2026-10-14 16:15:00", "2026-1-14 16:15", "2026-10-14T16:15", "abcd-ef-gh ij:kl", "2026-13-40 25:61"] {
            #expect(SlotDates.date(key, formatter: formatter) == formatter.date(from: key), "\(key)")
        }
        #expect(SlotDates.fields(of: "2026-10-14 16:15") == DateComponents(year: 2026, month: 10, day: 14, hour: 16, minute: 15))
    }
}
