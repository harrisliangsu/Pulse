// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation
import Observation
import Sparkle

/// Keeping Pulse up to date, through Sparkle.
///
/// **An EdDSA key is what makes this safe without an Apple Developer ID.**
/// Sparkle refuses any archive not signed by the key in `Info.plist`, whoever
/// served it — so the update path is verifiable even though the app itself
/// carries only an ad-hoc signature. Apple's signing and notarisation are
/// recommended by Sparkle rather than required, and the one thing they would
/// fix — Gatekeeper blocking the *first* launch — is not something an updater
/// can help with anyway.
///
/// **Nothing starts unless Pulse is running from a bundle.** Sparkle needs an
/// `Info.plist` carrying the feed URL and that public key, its framework in
/// `Contents/Frameworks`, and a version to compare against; a `swift run`
/// build has none of them. Started anyway it would log complaints about a
/// missing feed forever, and telling a developer their working copy is out of
/// date is noise.
///
/// Sparkle owns the schedule and the windows it puts up. What is kept here is
/// only what the rest of the app asks about: whether a check can happen at
/// all, whether one is running, and whether a newer version was found — which
/// is what the menu bar shows.
@MainActor
@Observable
final class AppUpdate {
    struct Release: Equatable, Sendable {
        let version: String
    }

    /// Set once Sparkle has found something newer, so the menu bar can say so.
    private(set) var newer: Release?
    private(set) var isChecking = false
    /// The last check couldn't reach the feed. Worth showing, because "no
    /// update" and "no answer" look identical otherwise.
    private(set) var didFail = false

    /// This build's version, or nil when it isn't running from a bundle.
    var current: String? {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
    }

    var canCheck: Bool { controller != nil }

    /// Sparkle's own daily schedule. Stored by Sparkle, not by `AppSettings`,
    /// so it can't drift from what the updater is actually doing.
    var checksAutomatically: Bool {
        get { controller?.updater.automaticallyChecksForUpdates ?? false }
        set { controller?.updater.automaticallyChecksForUpdates = newValue }
    }

    private var controller: SPUStandardUpdaterController?
    private let relay = UpdaterRelay()

    init() {
        // The feed URL is the tell: present only in a bundle built by
        // Scripts/bundle.sh, which is also the only place the framework is.
        guard
            Bundle.main.bundleIdentifier != nil,
            Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil
        else { return }

        relay.owner = self
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: relay,
            userDriverDelegate: nil
        )
    }

    /// The feed to read for the language Pulse is set to, or nil to read
    /// Info.plist's.
    ///
    /// The notes in the update window come in one language: each item in
    /// `appcast.xml` carries one `<description xml:lang>` per language and
    /// Sparkle shows the one the **system's** languages pick, which Pulse's own
    /// language setting cannot reach. So a Pulse set to a language reads that
    /// language's copy of the feed (`appcast-zh.xml`, `appcast-en.xml`, written
    /// by `Scripts/appcast.py` beside the main one). The changelog is written in
    /// Chinese and English; Japanese and Korean read the English.
    nonisolated static func feedURL(for language: AppLanguage, base: String?) -> String? {
        guard let base, base.hasSuffix("/appcast.xml") else { return nil }
        let file: String
        switch language {
        case .system: return nil
        case .chineseSimplified, .chineseTraditional: file = "appcast-zh.xml"
        case .english, .japanese, .korean: file = "appcast-en.xml"
        }
        return String(base.dropLast("appcast.xml".count)) + file
    }

    /// Asks now, and shows Sparkle's own window with whatever it finds.
    func check() {
        guard let controller else { return }
        isChecking = true
        didFail = false
        controller.updater.checkForUpdates()
    }

    /// Asks quietly, for a screen that is about to state the result: no
    /// Sparkle window, just `newer` / `didFail` brought up to date. Opening
    /// About calls this, so "up to date" there is an answer, not a default.
    /// Skipped while any check or update is already under way — that one will
    /// report, and starting another would only abort it.
    func probe() {
        guard
            let updater = controller?.updater,
            !isChecking,
            !updater.sessionInProgress,
            updater.canCheckForUpdates
        else { return }
        isChecking = true
        didFail = false
        updater.checkForUpdateInformation()
    }

    /// Nothing to do: Sparkle runs its own schedule from the moment it starts.
    /// Kept so the app's launch path doesn't have to know which updater is
    /// behind this.
    func checkIfDue() {}

    fileprivate func finishCheck(found item: SUAppcastItem?) {
        isChecking = false
        didFail = false
        newer = item.map { Release(version: $0.displayVersionString) }
    }

    fileprivate func failCheck(_ failed: Bool) {
        isChecking = false
        if failed { didFail = true }
    }

    /// Every cycle ends here, whichever of the calls above it made first, so a
    /// cycle that made none of them cannot leave the row saying "Checking…".
    fileprivate func endCycle() {
        isChecking = false
    }
}

/// Sparkle's delegate, kept apart from `AppUpdate` itself.
///
/// `SPUUpdaterDelegate` is an `@objc` protocol, so it has to be an `NSObject`
/// and its methods cannot be main-actor-isolated. Rather than fight that on a
/// type that is also `@Observable`, this stands between the two and hops onto
/// the main actor — where Sparkle calls it from in any case.
private final class UpdaterRelay: NSObject, SPUUpdaterDelegate {
    /// Weak: the app owns the updater, not the other way round.
    weak var owner: AppUpdate?

    /// Read at every check, so a language changed in Settings applies to the
    /// next one.
    nonisolated func feedURLString(for updater: SPUUpdater) -> String? {
        AppUpdate.feedURL(
            for: LocalizationSource.language,
            base: Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String
        )
    }

    nonisolated func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        MainActor.assumeIsolated { owner?.finishCheck(found: item) }
    }

    nonisolated func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        MainActor.assumeIsolated { owner?.finishCheck(found: nil) }
    }

    nonisolated func updater(_ updater: SPUUpdater, didAbortWithError error: any Error) {
        // Sparkle aborts for benign reasons too — the user closing its window
        // is one — and reporting those as "couldn't reach the feed" would be a
        // lie on the one row that exists to tell the truth about that. Only a
        // failure to *reach or read* the feed counts.
        let failed = (error as NSError).domain == NSURLErrorDomain
            || (error as NSError).code == Int(SUError.appcastError.rawValue)
        MainActor.assumeIsolated { owner?.failCheck(failed) }
    }

    nonisolated func updater(
        _ updater: SPUUpdater,
        didFinishUpdateCycleFor updateCheck: SPUUpdateCheck,
        error: (any Error)?
    ) {
        MainActor.assumeIsolated { owner?.endCycle() }
    }
}
