// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import AppKit
import Darwin

/// Reads the launch Apple event and the parent process into `LaunchSignals`.
/// The classification of those signals lives in `LaunchClassification`, which
/// has no AppKit in it.
enum LaunchSignalReader {
    /// `'lgit'`, `keyAELaunchedAsLogInItem`. The Carbon name is not in the
    /// Swift overlay this target links; the four-character code is the ABI.
    static let loginItemKeyword = AEKeyword(0x6C676974)

    static func flag(in event: NSAppleEventDescriptor?) -> LaunchSignals.LoginItemFlag {
        guard let event,
              event.eventClass == AEEventClass(kCoreEventClass),
              event.eventID == AEEventID(kAEOpenApplication)
        else { return .unreadable }

        guard let descriptor = event.paramDescriptor(forKeyword: loginItemKeyword) else {
            return .absent
        }
        return .present(descriptor.booleanValue)
    }

    /// Keeps a flag already read when the new event cannot supply one, so a
    /// handler that saw the open event is not wiped by a later nil.
    static func merge(existing: LaunchSignals, event: NSAppleEventDescriptor?) -> LaunchSignals {
        let read = flag(in: event)
        return LaunchSignals(
            loginItemFlag: read == .unreadable ? existing.loginItemFlag : read,
            parentBundleIdentifier: existing.parentBundleIdentifier,
            parentExecutableName: existing.parentExecutableName
        )
    }

    /// Fills the parent fields that are still empty. `pid` defaults to this
    /// process's parent; a test passes one it knows.
    static func withParent(_ signals: LaunchSignals, pid: pid_t = getppid()) -> LaunchSignals {
        var copy = signals
        if copy.parentBundleIdentifier == nil {
            copy.parentBundleIdentifier = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
        }
        if copy.parentExecutableName == nil {
            copy.parentExecutableName = executableName(pid: pid)
        }
        return copy
    }

    /// The parent's executable name, lowercased, without a path or extension.
    /// Nil when the path cannot be read.
    static func executableName(pid: pid_t) -> String? {
        let capacity = Int(MAXPATHLEN)
        guard capacity > 1 else { return nil }
        var buffer = [UInt8](repeating: 0, count: capacity)
        let length = buffer.withUnsafeMutableBytes { raw -> Int32 in
            guard let base = raw.baseAddress else { return 0 }
            return proc_pidpath(pid, base, UInt32(raw.count))
        }
        guard length > 0 else { return nil }
        // The call writes a trailing NUL inside `length` on some versions and
        // just past the bytes on others. Stop at the first NUL either way.
        let bytes = buffer.prefix { $0 != 0 }
        guard let path = String(bytes: bytes, encoding: .utf8), !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent.lowercased()
    }
}
