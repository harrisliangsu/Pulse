// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

/// Counts the recap cards say in words, where one of them has a singular that
/// a plural key cannot give ("1 day", "One night ran past midnight").
///
/// The choice between the keys is made here, outside the key, so a key is
/// always one whole sentence a translator can write.
enum RecapWords {
    /// "6 days", "1 day".
    static func days(_ count: Int) -> String {
        count == 1 ? .localized("1 day") : .localized("\("\(count)") days")
    }

    /// The unit after a count of days set as a figure: "days", "day".
    static func daysUnit(_ count: Int) -> String {
        count == 1 ? .localized("day") : .localized("days")
    }

    /// "412 sessions", "1 session".
    static func sessions(_ count: Int) -> String {
        count == 1 ? .localized("1 session") : .localized("\("\(count)") sessions")
    }

    /// "5 agents", "1 agent".
    static func agents(_ count: Int) -> String {
        count == 1 ? .localized("1 agent") : .localized("\("\(count)") agents")
    }

    /// "8 active days", "1 active day".
    static func activeDays(_ count: Int) -> String {
        count == 1 ? .localized("1 active day") : .localized("\("\(count)") active days")
    }

    /// The unit after a count of tools: "tools", "tool".
    static func toolsUnit(_ count: Int) -> String {
        count == 1 ? .localized("tool") : .localized("tools")
    }

    /// "11 nights ran past midnight", "One night ran past midnight".
    static func nightsPastMidnight(_ count: Int) -> String {
        count == 1 ? .localized("One night ran past midnight") : .localized("\("\(count)") nights ran past midnight")
    }
}
