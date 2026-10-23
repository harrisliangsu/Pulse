// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import UserNotifications

/// How a newer Blinky is announced.
///
/// Notify first is the shipped default. A scheduled check posts a notification
/// and leaves Sparkle's window hidden until that notification is clicked.
/// Show the window is the previous behaviour: the offer comes forward as soon
/// as the check finds a version. Check for Updates… and About's Check now are
/// neither of those — the reader asked, so the window opens either way.
///
/// **This type decides. It does not post, activate, or talk to Sparkle.**
/// `AppUpdate` performs the action. The cases are the whole of the policy, so
/// a test can pin them without a window server or a notification centre.
enum UpdateDiscovery: String, CaseIterable, Identifiable, Sendable {
    /// A notification. The update window opens when that notification is clicked.
    case notifyFirst
    /// Sparkle's update window, as soon as a scheduled check finds a version.
    case showWindow

    var id: String { rawValue }

    var title: String {
        switch self {
        case .notifyFirst: String.localized("Notify first")
        case .showWindow: String.localized("Show the window")
        }
    }
}

enum UpdateAnnouncement {
    /// The notification's identifier. One at a time: a later find replaces it.
    static let notificationIdentifier = "blinky-update"

    /// What the system has said about posting a notification.
    ///
    /// A provisional or ephemeral grant can still deliver one, so it counts
    /// as authorized. Only an explicit denial falls straight through to the
    /// window. Not determined means nobody has been asked, which is its own
    /// step rather than a silent loss.
    enum Permission: Equatable, CaseIterable, Sendable {
        case notDetermined
        case authorized
        case denied
    }

    /// Who the find is for. A scheduled check is Sparkle's timer. Manual is
    /// Check for Updates… and About's Check now. A click on the notice is the
    /// reader asking to see the offer that check already found.
    enum Origin: Equatable, Sendable {
        case scheduled
        case manual
        case notificationClick
    }

    /// What `AppUpdate` should do. It does not include the Dock or the window
    /// server: showing the offer is one action, wherever it is performed.
    enum Action: Equatable, Sendable {
        /// Sparkle's offer window, brought forward. No notification.
        case showOffer
        /// Post the notification and leave the offer hidden.
        case notify
        /// Ask for notification permission, then `actionAfterPermission`.
        case askPermission
    }

    /// What `AppUpdate.check` does. Both end at the offer window: a held
    /// offer is the one already found, and a fresh check is the user-initiated
    /// path on which Sparkle shows the window itself.
    enum Check: Equatable, Sendable {
        case revealHeldOffer
        case startUserInitiatedCheck
    }

    static func permission(_ status: UNAuthorizationStatus) -> Permission {
        switch status {
        case .authorized, .provisional, .ephemeral:
            .authorized
        case .denied:
            .denied
        case .notDetermined:
            .notDetermined
        @unknown default:
            .notDetermined
        }
    }

    /// The policy for a find, or for the reader asking to see one.
    ///
    /// Manual and a notification click ignore the setting and the grant: the
    /// window is what was asked for. A scheduled check under Show the window
    /// does the same. Notify first posts when it can, asks when it has not
    /// been allowed to, and shows the window when the grant was refused — a
    /// refused grant must not swallow the update.
    static func action(
        origin: Origin,
        discovery: UpdateDiscovery,
        permission: Permission
    ) -> Action {
        switch origin {
        case .manual, .notificationClick:
            return .showOffer
        case .scheduled:
            switch discovery {
            case .showWindow:
                return .showOffer
            case .notifyFirst:
                switch permission {
                case .authorized: return .notify
                case .denied: return .showOffer
                case .notDetermined: return .askPermission
                }
            }
        }
    }

    /// The answer to `askPermission`.
    ///
    /// A grant posts the notice only while Notify first is still the choice.
    /// Anything else — denied, the centre unavailable, or the reader switching
    /// to Show the window while the prompt was up — shows the offer.
    static func actionAfterPermission(granted: Bool, discovery: UpdateDiscovery) -> Action {
        if granted, discovery == .notifyFirst { return .notify }
        return .showOffer
    }

    /// Whether Sparkle's standard driver should present a scheduled find.
    ///
    /// `immediateFocus` is Sparkle's own moment (just launched, or the Mac has
    /// been idle). It does not change the answer: a scheduled check near
    /// launch is still a scheduled check, and Notify first still notifies.
    /// Returning false means this app posts the notice or asks first, and
    /// shows the offer later. Returning true means Sparkle shows it now.
    static func sparkleShowsScheduledUpdate(
        discovery: UpdateDiscovery,
        permission: Permission,
        immediateFocus _: Bool = false
    ) -> Bool {
        action(origin: .scheduled, discovery: discovery, permission: permission) == .showOffer
    }

    /// `AppUpdate.check`, which is what Check for Updates…, Check now, and a
    /// click on the notice all call. A held offer is revealed. Anything else
    /// starts the user-initiated check, which shows Sparkle's window itself.
    static func check(holdingScheduledOffer: Bool) -> Check {
        holdingScheduledOffer ? .revealHeldOffer : .startUserInitiatedCheck
    }
}
