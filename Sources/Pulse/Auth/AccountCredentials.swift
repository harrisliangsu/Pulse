// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

/// The login Pulse holds for one account it signed in to itself.
///
/// This is the point where Pulse stops only *borrowing* credentials. Every
/// other route reads a token some other tool already stored; an added account
/// has no such tool behind it, so Pulse keeps the tokens and renews them.
struct AccountCredentials: Codable, Equatable, Sendable {
    var accessToken: String
    var refreshToken: String
    /// When the access token stops being accepted. Renewal happens before
    /// this, not after a request has already been refused.
    var expiresAt: Date
    /// What the provider called the account when it was added, used to seed
    /// the label so two subscriptions are not both called "Codex".
    var accountName: String?
    /// Codex's usage endpoint wants the account named in a header of its own,
    /// and the token is the only place it appears.
    var accountID: String?

    /// A minute's headroom: a token that expires while the request is in
    /// flight comes back refused, and the retry costs more than renewing early.
    var isFresh: Bool { expiresAt.timeIntervalSinceNow > 60 }
}

/// Where those logins are kept: encrypted, in Pulse's own folder, one file for
/// all of them, owner-only.
///
/// Separate from `APIKeyStore` on purpose. A pasted API key and a full OAuth
/// login are different things with different lifetimes, and a corrupt file
/// should not be able to take both down at once.
enum AccountCredentialStore {
    private static let purpose = "Pulse account logins"

    private static var file: URL {
        PulseStorage.directory.appending(path: "accounts.dat")
    }

    static func credentials(for account: AccountKey) -> AccountCredentials? {
        load()?[account.id]
    }

    /// Every read-modify-write of the file, so a renewal's check and its write
    /// cannot have a removal land between them, whichever thread they run on.
    private static let lock = NSLock()

    /// Stores a login, or forgets one when `nil` is passed.
    @discardableResult
    static func set(_ credentials: AccountCredentials?, for account: AccountKey) -> Bool {
        lock.withLock { write(credentials, for: account) }
    }

    private static func write(_ credentials: AccountCredentials?, for account: AccountKey) -> Bool {
        // A file that exists but won't decode is not an empty one. Treating it
        // as empty would silently throw away every other account's login and
        // report success — the same trap `APIKeyStore` was fixed for.
        guard var all = load() else { return false }

        all[account.id] = credentials
        return save(all)
    }

    /// Stores a renewal, unless what is already there outlives it.
    ///
    /// **A renewal is not an ordinary write.** Two passes can be renewing the
    /// same account at once — the second only because the first was given up
    /// on for taking too long — and the abandoned one answers last. Written
    /// plainly, that puts the older login back over the newer, and a provider
    /// that rotates refresh tokens will then refuse it: the account is signed
    /// out by the act of keeping it signed in. Which one lives longer is the
    /// question, and both of them answer it.
    ///
    /// Sign-out still goes through `set(_:for:)`, which is unconditional:
    /// forgetting a login is a decision, not a race.
    ///
    /// **A renewal never brings a login back.** Removing an account forgets
    /// its login while a renewal for it can still be out; when that answer
    /// came back to an empty slot it was written — "older than nothing" — and
    /// the access and refresh tokens the user had just asked Pulse to forget
    /// were on disk again. A renewal is of a login that is still there, or it
    /// is nothing. Nor is it written over another account's login that was
    /// signed in to the same slot meanwhile.
    @discardableResult
    static func renewed(_ credentials: AccountCredentials, for account: AccountKey) -> Bool {
        lock.withLock {
            guard let all = load(), acceptsRenewal(credentials, over: all[account.id]) else { return false }
            return write(credentials, for: account)
        }
    }

    /// The rule `renewed` writes by, apart from the file so it can be tested
    /// without touching a real login.
    static func acceptsRenewal(_ credentials: AccountCredentials, over existing: AccountCredentials?) -> Bool {
        guard let existing else { return false }
        if existing.expiresAt >= credentials.expiresAt { return false }
        if let held = existing.accountID, let renewing = credentials.accountID, held != renewing { return false }
        return true
    }

    // MARK: - The file

    /// What is stored, or nil when there is a file here that cannot be read.
    /// An absent file is empty; an unreadable one is not.
    private static func load() -> [String: AccountCredentials]? {
        guard FileManager.default.fileExists(atPath: file.path) else { return [:] }

        guard
            let sealed = try? Data(contentsOf: file),
            let plain = LocalSecrets.open(sealed, purpose: purpose),
            let all = try? JSONDecoder().decode([String: AccountCredentials].self, from: plain)
        else { return nil }

        return all
    }

    private static func save(_ all: [String: AccountCredentials]) -> Bool {
        guard
            let plain = try? JSONEncoder().encode(all),
            let sealed = LocalSecrets.seal(plain, purpose: purpose)
        else { return false }

        return LocalSecrets.write(sealed, to: file)
    }
}
