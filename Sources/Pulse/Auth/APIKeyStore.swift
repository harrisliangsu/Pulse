// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import CryptoKit
import Foundation
import IOKit

/// Where a key typed into Settings is kept: encrypted, in Pulse's own folder.
///
/// One file, `keys.dat`, holding AES-GCM boxes keyed by provider. The file is
/// owner-only, and the key that opens it is derived from this Mac rather than
/// stored anywhere, so a copy of the file on its own — in a backup, a synced
/// folder, a shared screen — opens nowhere.
///
/// **Every change is one locked read-modify-write.** Settings saving a key and
/// a console session renewed in the background can run at once; each reads
/// the whole file, changes one entry and writes it back, so without the lock
/// the later write put back the file as it was before the other's change —
/// one of the two keys gone. The atomic file write does not cover that: it
/// guards the file, not the read before it.
enum APIKeyStore {
    private static let lock = NSLock()

    private static func file(in directory: URL) -> URL {
        directory.appending(path: "keys.dat")
    }

    /// `slot` names a second credential a provider can hold beside its key —
    /// OpenCode Go's console session, which reads the account's request logs
    /// while the key reads its limits. Nil is the provider's own key.
    /// `directory` is Pulse's own folder; tests pass a temporary one.
    static func key(for provider: Provider, slot: String? = nil, in directory: URL = PulseStorage.directory) -> String? {
        guard
            let stored = load(directory)[entry(provider, slot)],
            let opened = LocalSecrets.open(stored, purpose: Self.purpose),
            let key = String(data: opened, encoding: .utf8),
            !key.isEmpty
        else { return nil }

        return key
    }

    /// Stores a key, or removes it when the field is cleared.
    @discardableResult
    static func setKey(
        _ key: String?, for provider: Provider, slot: String? = nil, in directory: URL = PulseStorage.directory
    ) -> Bool {
        lock.withLock { write(key, for: provider, slot: slot, in: directory) }
    }

    /// Puts `key` in place of `expected`, and only while `expected` is still
    /// what is kept. A renewal read the old credential before it went to the
    /// browser; by the time it comes back the person may have removed it, or
    /// saved another — and a renewal that arrives late must not write over
    /// either. False when it did not replace.
    @discardableResult
    static func replaceKey(
        _ expected: String, with key: String, for provider: Provider, slot: String? = nil,
        in directory: URL = PulseStorage.directory
    ) -> Bool {
        lock.withLock {
            guard Self.key(for: provider, slot: slot, in: directory) == expected else { return false }
            return write(key, for: provider, slot: slot, in: directory)
        }
    }

    /// The read-modify-write itself; callers hold `lock`.
    private static func write(_ key: String?, for provider: Provider, slot: String?, in directory: URL) -> Bool {
        // A file that exists but won't decode is not an empty one. Treating it
        // as empty meant saving one provider's key silently threw away every
        // other provider's — and said it had succeeded.
        guard var keys = readable(directory) else { return false }
        let trimmed = key?.trimmingCharacters(in: .whitespacesAndNewlines)

        if let trimmed, !trimmed.isEmpty {
            guard let sealed = LocalSecrets.seal(Data(trimmed.utf8), purpose: Self.purpose) else { return false }
            keys[entry(provider, slot)] = sealed
        } else {
            keys[entry(provider, slot)] = nil
        }

        return save(keys, in: directory)
    }

    /// The file's key for a credential. A slot is joined with `#`, which no
    /// provider's raw value contains, so a slot can never read another
    /// provider's key.
    private static func entry(_ provider: Provider, _ slot: String?) -> String {
        slot.map { "\(provider.rawValue)#\($0)" } ?? provider.rawValue
    }

    /// Distinct from the account logins' purpose, so a box from one store can
    /// never be opened by the other.
    private static let purpose = "Pulse api keys"

    // MARK: - The file

    private static func load(_ directory: URL) -> [String: Data] { readable(directory) ?? [:] }

    /// What is stored, or nil when there is a file here that cannot be read.
    /// An absent file is empty; an unreadable one is not.
    private static func readable(_ directory: URL) -> [String: Data]? {
        let file = file(in: directory)
        guard FileManager.default.fileExists(atPath: file.path) else { return [:] }

        guard
            let data = try? Data(contentsOf: file),
            let keys = try? JSONDecoder().decode([String: Data].self, from: data)
        else { return nil }

        return keys
    }

    private static func save(_ keys: [String: Data], in directory: URL) -> Bool {
        guard let data = try? JSONEncoder().encode(keys) else { return false }
        return LocalSecrets.write(data, to: file(in: directory))
    }
}
