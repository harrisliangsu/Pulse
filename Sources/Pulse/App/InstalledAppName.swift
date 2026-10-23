// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

/// Renames an installed `Pulse.app` to `Blinky.app` once that name is free.
///
/// Sparkle 2.9 writes an update over `host.bundlePath`. The flag that would
/// install to `CFBundleName.app` instead, `SPARKLE_NORMALIZE_INSTALLED_APPLICATION_NAME`,
/// is compiled into the Sparkle framework and is off in the SwiftPM build, so
/// an installed `/Applications/Pulse.app` stays `Pulse.app` after the bytes
/// are replaced. Finder labels the file by that name. `SUBundleName` only
/// tells Sparkle which bundle to pick *inside the zip*.
///
/// `updaterWillRelaunchApplication` cannot fix the path. It runs in the
/// process that is about to quit, and the helper installs and relaunches
/// only after that. Renaming there would move the bundle the helper is
/// about to replace, and the relaunch would still aim at `Pulse.app`.
/// The process that comes back is this one: it moves the bundle, then
/// starts that renamed bundle and exits, so the process that stays up —
/// and the next Sparkle install — sees `Blinky.app`.
///
/// A `Blinky.app` already beside it is left where it is. That includes a
/// newer copy, an older one, a copy whose version cannot be read, and a
/// bundle that is not this app. Replacing any of them would delete a file
/// the person put there.
///
/// `--json`, `--recap`, and the status-line command return before this runs,
/// so a poll does not move the bundle. A translocated launch is a read-only
/// mount under `AppTranslocation` and is left alone. A symbolic link is left
/// alone, because moving it would retarget the link rather than the app.
enum InstalledAppName {
    static let legacyFileName = "Pulse.app"
    static let fileName = "Blinky.app"

    /// Set before the move when Open at login was on, and cleared by the
    /// launch that is already `Blinky.app` after it registers again.
    /// `SMAppService` stores the bundle path, so the registration made for
    /// `Pulse.app` does not follow the rename.
    static let pendingLoginItemKey = "installedAppName.reregisterLoginItem"

    struct BundleFacts: Equatable, Sendable {
        var version: String?
        var bundleIdentifier: String?
    }

    struct Snapshot: Equatable, Sendable {
        var bundleURL: URL
        var version: String?
        var bundleIdentifier: String?
        var isTranslocated: Bool
        var isSymbolicLink: Bool
        var destinationExists: Bool
        var destinationVersion: String?
        var destinationBundleIdentifier: String?
        var loginItemEnabled: Bool
        var pendingLoginItemReregister: Bool
    }

    enum Stay: Equatable, Sendable {
        case notLegacyName
        case translocated
        case symbolicLink
        /// Same bundle identifier, and a version strictly above this copy.
        case destinationNewer(version: String)
        /// Present, and not a newer copy of this app. Left in place.
        case destinationOccupied(version: String?)
    }

    enum Step: Equatable, Sendable {
        case rename(from: URL, to: URL, reregisterLoginItem: Bool)
        case reregisterLoginItem
        case stay(Stay)
    }

    enum Outcome: Equatable, Sendable {
        case renamed(to: URL, willReregisterLoginItem: Bool)
        case leftInPlace(Stay)
        case reregisteredLoginItem
        case renameFailed
    }

    struct Effects {
        var move: (URL, URL) throws -> Void
        /// Whether `url` is still on disk. Used when a move fails, so a second
        /// launch that lost the race does not clear the login-item flag the
        /// launch that won the rename still needs.
        var bundleExists: (URL) -> Bool
        var notePendingLoginItemReregister: (Bool) -> Void
        var refreshLoginItem: () -> Void
        /// Starts `Blinky.app` and, in the app, exits this process on success.
        var relaunch: (URL) -> Bool
    }

    static func destination(for bundleURL: URL) -> URL {
        bundleURL.deletingLastPathComponent().appending(path: fileName)
    }

    static func plan(_ snapshot: Snapshot) -> Step {
        let legacy = isLegacyFileName(snapshot.bundleURL)
        if legacy, !snapshot.isTranslocated, !snapshot.isSymbolicLink, !snapshot.destinationExists {
            let reregister = snapshot.loginItemEnabled || snapshot.pendingLoginItemReregister
            return .rename(
                from: snapshot.bundleURL,
                to: destination(for: snapshot.bundleURL),
                reregisterLoginItem: reregister
            )
        }
        // A translocated launch must not register that read-only path as the
        // login item. The flag stays set for the copy in Applications.
        if snapshot.pendingLoginItemReregister, !snapshot.isTranslocated {
            return .reregisterLoginItem
        }
        return .stay(stayReason(snapshot, legacy: legacy))
    }

    @discardableResult
    static func apply(_ snapshot: Snapshot, using effects: Effects) -> Outcome {
        switch plan(snapshot) {
        case .rename(let from, let to, let reregister):
            if reregister {
                effects.notePendingLoginItemReregister(true)
            }
            do {
                try effects.move(from, to)
            } catch {
                if reregister, effects.bundleExists(from) {
                    effects.notePendingLoginItemReregister(false)
                }
                return .renameFailed
            }
            _ = effects.relaunch(to)
            return .renamed(to: to, willReregisterLoginItem: reregister)
        case .reregisterLoginItem:
            // Cleared before the register, so a launch that fails to register
            // does not turn Open at login back on after the person switches it off.
            effects.notePendingLoginItemReregister(false)
            effects.refreshLoginItem()
            return .reregisteredLoginItem
        case .stay(let reason):
            return .leftInPlace(reason)
        }
    }

    /// The running app, when it is a bundle that still needs a rename or a
    /// login-item register. Every other launch returns nil and does no I/O
    /// beyond the name and the one defaults flag.
    static func currentSnapshot() -> Snapshot? {
        let url = Bundle.main.bundleURL
        guard url.pathExtension.caseInsensitiveCompare("app") == .orderedSame else { return nil }
        let pending = UserDefaults.standard.bool(forKey: pendingLoginItemKey)
        let legacy = isLegacyFileName(url)
        guard legacy || pending else { return nil }

        let translocated = isTranslocated(url)
        let symlink = (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink == true
        let destination = destination(for: url)
        let destinationExists = FileManager.default.fileExists(atPath: destination.path)
        let facts = destinationExists ? bundleFacts(at: destination) : BundleFacts()
        let mightRename = legacy && !translocated && !symlink && !destinationExists
        return Snapshot(
            bundleURL: url,
            version: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
            bundleIdentifier: Bundle.main.bundleIdentifier,
            isTranslocated: translocated,
            isSymbolicLink: symlink,
            destinationExists: destinationExists,
            destinationVersion: facts.version,
            destinationBundleIdentifier: facts.bundleIdentifier,
            loginItemEnabled: mightRename && LoginItem.isEnabled,
            pendingLoginItemReregister: pending
        )
    }

    static func adoptLegacyFileNameIfNeeded() {
        guard let snapshot = currentSnapshot() else { return }
        apply(snapshot, using: liveEffects)
    }

    static func bundleFacts(at bundleURL: URL) -> BundleFacts {
        let plistURL = bundleURL.appending(path: "Contents/Info.plist")
        guard
            let data = try? Data(contentsOf: plistURL),
            let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return BundleFacts() }
        return BundleFacts(
            version: plist["CFBundleShortVersionString"] as? String,
            bundleIdentifier: plist["CFBundleIdentifier"] as? String
        )
    }

    static func isLegacyFileName(_ bundleURL: URL) -> Bool {
        bundleURL.lastPathComponent.caseInsensitiveCompare(legacyFileName) == .orderedSame
    }

    static func isTranslocated(_ bundleURL: URL) -> Bool {
        let raw = bundleURL.path
        let resolved = bundleURL.resolvingSymlinksInPath().path
        return raw.contains("/AppTranslocation/") || resolved.contains("/AppTranslocation/")
    }

    /// Dotted numeric versions, the shape this app ships (`1.5.3`).
    /// A version that is not that shape does not compare, and the neighbour
    /// is then left in place.
    static func versionOrder(_ lhs: String, _ rhs: String) -> ComparisonResult? {
        func parts(_ value: String) -> [Int]? {
            let pieces = value.split(separator: ".", omittingEmptySubsequences: false)
            guard !pieces.isEmpty else { return nil }
            var numbers: [Int] = []
            for piece in pieces {
                guard !piece.isEmpty, piece.allSatisfy(\.isNumber), let number = Int(piece) else { return nil }
                numbers.append(number)
            }
            return numbers
        }
        guard let left = parts(lhs), let right = parts(rhs) else { return nil }
        let count = max(left.count, right.count)
        for index in 0..<count {
            let l = index < left.count ? left[index] : 0
            let r = index < right.count ? right[index] : 0
            if l < r { return .orderedAscending }
            if l > r { return .orderedDescending }
        }
        return .orderedSame
    }

    private static func stayReason(_ snapshot: Snapshot, legacy: Bool) -> Stay {
        guard legacy else { return .notLegacyName }
        if snapshot.isTranslocated { return .translocated }
        if snapshot.isSymbolicLink { return .symbolicLink }
        guard snapshot.destinationExists else { return .destinationOccupied(version: nil) }
        if
            let ours = snapshot.bundleIdentifier,
            let theirs = snapshot.destinationBundleIdentifier,
            ours == theirs,
            let ourVersion = snapshot.version,
            let theirVersion = snapshot.destinationVersion,
            versionOrder(theirVersion, ourVersion) == .orderedDescending
        {
            return .destinationNewer(version: theirVersion)
        }
        return .destinationOccupied(version: snapshot.destinationVersion)
    }

    private static var liveEffects: Effects {
        Effects(
            move: { try FileManager.default.moveItem(at: $0, to: $1) },
            bundleExists: { FileManager.default.fileExists(atPath: $0.path) },
            notePendingLoginItemReregister: { UserDefaults.standard.set($0, forKey: pendingLoginItemKey) },
            refreshLoginItem: { _ = LoginItem.refreshAfterBundleMoved() },
            relaunch: relaunch
        )
    }

    /// Registers the renamed bundle with Launch Services, opens it, and exits.
    /// `open -n` is a new process: this one still has the path it was executed
    /// from, and a Sparkle check later in this process would install back onto
    /// `Pulse.app`.
    @discardableResult
    static func relaunch(at bundleURL: URL) -> Bool {
        registerWithLaunchServices(bundleURL)
        let open = Process()
        open.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        open.arguments = ["-n", bundleURL.path]
        do {
            try open.run()
            open.waitUntilExit()
            guard open.terminationStatus == 0 else { return false }
            exit(0)
        } catch {
            return false
        }
    }

    private static func registerWithLaunchServices(_ bundleURL: URL) {
        let tool = "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
        guard FileManager.default.isExecutableFile(atPath: tool) else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = ["-f", bundleURL.path]
        guard (try? process.run()) != nil else { return }
        process.waitUntilExit()
    }
}
