import Foundation

/// A throwaway defaults suite that never lands in `~/Library/Preferences`.
///
/// A suite named like `PulseTests.x.<UUID>` is a file there, and
/// `removePersistentDomain` only empties it: cfprefsd writes the empty plist
/// back afterwards, even when the test deletes it first. That left a file per
/// test run until there were thousands. A suite named by an absolute path is
/// stored at that path instead, so each one gets its own temporary directory
/// and cleanup removes the directory — with nowhere left to write, nothing
/// comes back.
enum TestDefaults {
    static func make(_ label: String) -> (UserDefaults, cleanup: () -> Void) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PulseTests.\(label).\(UUID().uuidString)", isDirectory: true)
        try! FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let name = directory.appendingPathComponent("defaults").path
        let suite = UserDefaults(suiteName: name)!
        return (suite, {
            suite.removePersistentDomain(forName: name)
            try? FileManager.default.removeItem(at: directory)
        })
    }
}
