import Foundation
import Testing
@testable import Pulse

/// `Pulse.app` becomes `Blinky.app` on launch when that name is free.
/// A neighbour already called `Blinky.app` stays, newer or not. The login
/// item is registered again only on the launch that is already at the new path.
@Suite("Installed app name")
struct InstalledAppNameTests {
    private let identifier = "io.github.qunqin24.Pulse"

    @Test("A Pulse.app with no neighbour is renamed, and an enabled login item is marked for the next launch")
    func renamesWhenTheNameIsFree() {
        let root = URL(fileURLWithPath: "/Applications")
        let pulse = root.appending(path: "Pulse.app")
        let blinky = InstalledAppName.destination(for: pulse)
        var pending: [Bool] = []
        var relaunched: [URL] = []
        var refreshed = 0
        let outcome = InstalledAppName.apply(
            snapshot(url: pulse, loginItemEnabled: true),
            using: effects(
                pending: { pending.append($0) },
                refreshed: { refreshed += 1 },
                relaunched: { relaunched.append($0); return true }
            )
        )
        #expect(outcome == .renamed(to: blinky, willReregisterLoginItem: true))
        #expect(pending == [true])
        #expect(relaunched == [blinky])
        #expect(refreshed == 0)
        #expect(InstalledAppName.plan(snapshot(url: pulse, loginItemEnabled: false)) == .rename(
            from: pulse, to: blinky, reregisterLoginItem: false
        ))
    }

    @Test("The file name matches without regard to case")
    func caseFold() {
        let pulse = URL(fileURLWithPath: "/Applications/pulse.app")
        let step = InstalledAppName.plan(snapshot(url: pulse))
        #expect(step == .rename(
            from: pulse,
            to: InstalledAppName.destination(for: pulse),
            reregisterLoginItem: false
        ))
    }

    @Test("Blinky.app, a moved-aside name, and a loose binary stay")
    func leavesOtherNames() {
        #expect(InstalledAppName.plan(snapshot(url: URL(fileURLWithPath: "/Applications/Blinky.app"))) == .stay(.notLegacyName))
        #expect(InstalledAppName.plan(snapshot(url: URL(fileURLWithPath: "/Applications/Pulse copy.app"))) == .stay(.notLegacyName))
        #expect(InstalledAppName.plan(snapshot(url: URL(fileURLWithPath: "/tmp/Pulse"))) == .stay(.notLegacyName))
    }

    @Test("A newer Blinky.app is not replaced")
    func leavesANewerNeighbour() {
        let pulse = URL(fileURLWithPath: "/Applications/Pulse.app")
        let step = InstalledAppName.plan(snapshot(
            url: pulse,
            version: "1.5.3",
            destinationExists: true,
            destinationVersion: "1.5.10",
            destinationBundleIdentifier: identifier,
            loginItemEnabled: true
        ))
        #expect(step == .stay(.destinationNewer(version: "1.5.10")))
    }

    @Test("An older or equal Blinky.app is left in place, as is one that is not this app")
    func leavesAnyExistingNeighbour() {
        let pulse = URL(fileURLWithPath: "/Applications/Pulse.app")
        #expect(InstalledAppName.plan(snapshot(
            url: pulse,
            destinationExists: true,
            destinationVersion: "1.5.2",
            destinationBundleIdentifier: identifier
        )) == .stay(.destinationOccupied(version: "1.5.2")))
        #expect(InstalledAppName.plan(snapshot(
            url: pulse,
            destinationExists: true,
            destinationVersion: "1.5.3",
            destinationBundleIdentifier: identifier
        )) == .stay(.destinationOccupied(version: "1.5.3")))
        #expect(InstalledAppName.plan(snapshot(
            url: pulse,
            version: "1.5",
            destinationExists: true,
            destinationVersion: "1.5.0",
            destinationBundleIdentifier: identifier
        )) == .stay(.destinationOccupied(version: "1.5.0")))
        #expect(InstalledAppName.plan(snapshot(
            url: pulse,
            destinationExists: true,
            destinationVersion: "9.0.0",
            destinationBundleIdentifier: "com.example.other"
        )) == .stay(.destinationOccupied(version: "9.0.0")))
        #expect(InstalledAppName.plan(snapshot(
            url: pulse,
            destinationExists: true,
            destinationVersion: nil,
            destinationBundleIdentifier: nil
        )) == .stay(.destinationOccupied(version: nil)))
        #expect(InstalledAppName.plan(snapshot(
            url: pulse,
            destinationExists: true,
            destinationVersion: "1.5.3-beta",
            destinationBundleIdentifier: identifier
        )) == .stay(.destinationOccupied(version: "1.5.3-beta")))
    }

    @Test("A translocated or linked Pulse.app is not moved, and a pending login item waits")
    func leavesTranslocatedAndLinks() {
        let pulse = URL(fileURLWithPath: "/private/var/folders/ab/AppTranslocation/UUID/d/Pulse.app")
        #expect(InstalledAppName.isTranslocated(pulse))
        #expect(InstalledAppName.plan(snapshot(url: pulse, isTranslocated: true)) == .stay(.translocated))
        #expect(InstalledAppName.plan(snapshot(
            url: pulse,
            isTranslocated: true,
            pendingLoginItemReregister: true
        )) == .stay(.translocated))
        #expect(InstalledAppName.plan(snapshot(
            url: URL(fileURLWithPath: "/Applications/Pulse.app"),
            isSymbolicLink: true
        )) == .stay(.symbolicLink))
    }

    @Test("The launch that is already Blinky.app registers the login item once")
    func reregistersOnTheRenamedBundle() {
        var pending: [Bool] = []
        var refreshed = 0
        let outcome = InstalledAppName.apply(
            snapshot(
                url: URL(fileURLWithPath: "/Applications/Blinky.app"),
                pendingLoginItemReregister: true
            ),
            using: effects(pending: { pending.append($0) }, refreshed: { refreshed += 1 })
        )
        #expect(outcome == .reregisteredLoginItem)
        #expect(pending == [false])
        #expect(refreshed == 1)
    }

    @Test("A neighbour that blocked the rename still gets a pending login item registered here")
    func reregistersWhenTheRenameIsRefused() {
        let outcome = InstalledAppName.apply(
            snapshot(
                destinationExists: true,
                destinationVersion: "9.0",
                destinationBundleIdentifier: identifier,
                pendingLoginItemReregister: true
            ),
            using: effects()
        )
        #expect(outcome == .reregisteredLoginItem)
    }

    @Test("A failed move clears the login-item flag only while Pulse.app is still there")
    func failedMove() {
        var pending: [Bool] = []
        var relaunched = 0
        let stillThere = InstalledAppName.apply(
            snapshot(loginItemEnabled: true),
            using: effects(
                move: { _, _ in throw CocoaError(.fileWriteNoPermission) },
                exists: { _ in true },
                pending: { pending.append($0) },
                relaunched: { _ in relaunched += 1; return true }
            )
        )
        #expect(stillThere == .renameFailed)
        #expect(pending == [true, false])
        #expect(relaunched == 0)

        pending.removeAll()
        let wonByTheOtherLaunch = InstalledAppName.apply(
            snapshot(loginItemEnabled: true),
            using: effects(
                move: { _, _ in throw CocoaError(.fileWriteFileExists) },
                exists: { _ in false },
                pending: { pending.append($0) }
            )
        )
        #expect(wonByTheOtherLaunch == .renameFailed)
        #expect(pending == [true])
    }

    @Test("The move itself renames the directory and does not touch a newer Blinky.app")
    func movesOnDisk() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "installed-name-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let pulse = root.appending(path: "Pulse.app")
        let blinky = InstalledAppName.destination(for: pulse)
        try writeBundle(pulse, version: "1.5.3", marker: "from-pulse")
        try writeBundle(blinky, version: "1.6.0", marker: "keep-blinky")

        let facts = InstalledAppName.bundleFacts(at: blinky)
        #expect(facts.version == "1.6.0")
        #expect(facts.bundleIdentifier == identifier)

        var moved = 0
        let blocked = InstalledAppName.apply(
            snapshot(
                url: pulse,
                destinationExists: true,
                destinationVersion: facts.version,
                destinationBundleIdentifier: facts.bundleIdentifier,
                loginItemEnabled: true
            ),
            using: effects(move: { from, to in
                moved += 1
                try FileManager.default.moveItem(at: from, to: to)
            })
        )
        #expect(blocked == .leftInPlace(.destinationNewer(version: "1.6.0")))
        #expect(moved == 0)
        #expect(try String(contentsOf: blinky.appending(path: "marker"), encoding: .utf8) == "keep-blinky")
        #expect(FileManager.default.fileExists(atPath: pulse.path))

        try FileManager.default.removeItem(at: blinky)
        var relaunched: [URL] = []
        let renamed = InstalledAppName.apply(
            snapshot(url: pulse, loginItemEnabled: false),
            using: effects(
                move: { try FileManager.default.moveItem(at: $0, to: $1) },
                exists: { FileManager.default.fileExists(atPath: $0.path) },
                relaunched: { relaunched.append($0); return false }
            )
        )
        #expect(renamed == .renamed(to: blinky, willReregisterLoginItem: false))
        #expect(relaunched == [blinky])
        #expect(!FileManager.default.fileExists(atPath: pulse.path))
        #expect(try String(contentsOf: blinky.appending(path: "marker"), encoding: .utf8) == "from-pulse")
        #expect(InstalledAppName.bundleFacts(at: blinky).version == "1.5.3")
    }

    private func snapshot(
        url: URL = URL(fileURLWithPath: "/Applications/Pulse.app"),
        version: String? = "1.5.3",
        isTranslocated: Bool = false,
        isSymbolicLink: Bool = false,
        destinationExists: Bool = false,
        destinationVersion: String? = nil,
        destinationBundleIdentifier: String? = nil,
        loginItemEnabled: Bool = false,
        pendingLoginItemReregister: Bool = false
    ) -> InstalledAppName.Snapshot {
        InstalledAppName.Snapshot(
            bundleURL: url,
            version: version,
            bundleIdentifier: identifier,
            isTranslocated: isTranslocated,
            isSymbolicLink: isSymbolicLink,
            destinationExists: destinationExists,
            destinationVersion: destinationVersion,
            destinationBundleIdentifier: destinationBundleIdentifier,
            loginItemEnabled: loginItemEnabled,
            pendingLoginItemReregister: pendingLoginItemReregister
        )
    }

    private func effects(
        move: @escaping (URL, URL) throws -> Void = { _, _ in },
        exists: @escaping (URL) -> Bool = { _ in true },
        pending: @escaping (Bool) -> Void = { _ in },
        refreshed: @escaping () -> Void = {},
        relaunched: @escaping (URL) -> Bool = { _ in true }
    ) -> InstalledAppName.Effects {
        InstalledAppName.Effects(
            move: move,
            bundleExists: exists,
            notePendingLoginItemReregister: pending,
            refreshLoginItem: refreshed,
            relaunch: relaunched
        )
    }

    private func writeBundle(_ url: URL, version: String, marker: String) throws {
        try FileManager.default.createDirectory(at: url.appending(path: "Contents"), withIntermediateDirectories: true)
        let plist: [String: Any] = [
            "CFBundleShortVersionString": version,
            "CFBundleIdentifier": identifier
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: url.appending(path: "Contents/Info.plist"))
        try Data(marker.utf8).write(to: url.appending(path: "marker"))
    }
}
