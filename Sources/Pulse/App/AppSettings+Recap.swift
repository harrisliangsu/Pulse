// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

// The monthly recap: which month was last announced, what the reader pays (for
// the payback card only), and whether project names are hidden. The
// notification itself is a rule and lives with the others
// (`AppSettings+Notifications`). `recapMonthlyPrice`'s observer, which
// normalises what it is given, is in the main file — see its note.

extension AppSettings.Key {
    static let recapAnnouncedMonth = "settings.recapAnnouncedMonth"
    static let recapMonthlyPrice = "settings.recapMonthlyPrice"
    static let recapHidesProjects = "settings.recapHidesProjects"
}

extension AppSettings {
    func recapAnnouncedMonthChanged(from old: String?) {
        guard recapAnnouncedMonth != old else { return }
        defaults.set(recapAnnouncedMonth, forKey: Key.recapAnnouncedMonth)
    }

    func recapHidesProjectsChanged(from old: Bool) {
        guard recapHidesProjects != old else { return }
        defaults.set(recapHidesProjects, forKey: Key.recapHidesProjects)
    }

    /// The settings `init` has no parameter for.
    func restoreRecap(from defaults: UserDefaults) {
        recapAnnouncedMonth = defaults.string(forKey: Key.recapAnnouncedMonth)
        recapMonthlyPrice = RecapPrice.normalized(defaults.object(forKey: Key.recapMonthlyPrice) as? Double)
        recapHidesProjects = defaults.bool(forKey: Key.recapHidesProjects)
    }
}
