// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

/// What a session is called wherever one is listed.
///
/// **One rule for every list.** The conversation's own title where it has one;
/// a review session Codex ran by itself says so; else the project it ran in;
/// else "Untitled conversation". **Never the transcript's file name** — a
/// uuid or `rollout-2026-…` tells the reader nothing, and it is not a name the
/// user ever gave. The Token spend pane, the card's prompt-cache line and the
/// Settings prompt-cache list all go through here.
enum SessionLabel {
    static func text(title: String?, isReview: Bool, project: String?) -> String {
        if let title { return title }
        if isReview { return String.localized("Codex review") }
        if let project { return project }
        return String.localized("Untitled conversation")
    }

    /// Whether the label above is the session's own name rather than its
    /// project — which is when a row's subtitle should add the project, so
    /// it is never said twice.
    static func namesItself(title: String?, isReview: Bool) -> Bool {
        title != nil || isReview
    }
}

extension UsageLedger.Session {
    /// The row's name, from `SessionLabel`; `projectName` is the project as
    /// the list shows it (it can carry a parent folder where names collide).
    func label(projectName: String?) -> String {
        SessionLabel.text(title: title, isReview: isReview, project: projectName)
    }

    func namesItself() -> Bool { SessionLabel.namesItself(title: title, isReview: isReview) }
}
