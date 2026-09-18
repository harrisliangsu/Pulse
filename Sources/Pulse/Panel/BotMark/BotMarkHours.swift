import Foundation

/// Whether a turn is happening outside working hours.
///
/// Used for one thing: a working mark takes `angry` into its playlist at
/// night and at weekends, because a turn at eleven is still work and the
/// character has an opinion about it.
///
/// **The hours are a guess and are meant to be edited.** Nobody's calendar is
/// in this app, so there is nothing to read: 09:00–21:00 Monday to Friday is a
/// default, not a fact about the person using it. Kept in one place, and out
/// of the mood table, so changing it is one line and so it cannot creep into
/// anything that claims to be a reading.
enum BotMarkHours {
    static let start = 9
    static let end = 21

    static func isOvertime(at date: Date = Date(), calendar: Calendar = .current) -> Bool {
        guard let hour = calendar.dateComponents([.hour], from: date).hour else { return false }
        // `isDateInWeekend` rather than a weekday number: which days are the
        // weekend is a property of the calendar, not a pair of constants.
        return calendar.isDateInWeekend(date) || hour < start || hour >= end
    }
}
