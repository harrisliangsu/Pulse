import Foundation

/// Actions for the credential or tool that this account actually uses.
enum ConnectionRemedy: Equatable {
    case signIn
    case editCredential
    case readBrowser
    case connectStatusLine
    case openApp(String)
    case copyCommand(String)
    case retry
    case help

    static func forReason(_ reason: ProviderUsage.Unavailability, account: AccountKey) -> Self? {
        if !account.isPrimary,
           [.signedOut, .claudeLoginExpired, .signInRequired, .grokLoginExpired,
            .cursorLoginExpired, .cursorSignInRequired,
            .kimiSignInRequired, .kimiLoginExpired].contains(reason) {
            return .signIn
        }
        switch reason {
        case .loading, .awaitingResponse: return nil
        case .notConnected: return .connectStatusLine
        case .claudeSignInRequired, .claudeLoginExpired: return .copyCommand("claude auth login")
        case .signInRequired: return .copyCommand("codex login")
        case .grokSignInRequired, .grokLoginExpired: return .copyCommand("grok")
        case .volcengineSignInRequired: return .copyCommand("arkcli auth login")
        case .claudeDesktopNotSignedIn, .claudeDesktopSessionExpired: return .openApp("Claude")
        case .cursorSignInRequired, .cursorLoginExpired: return .openApp("Cursor")
        case .antigravityNotRunning, .antigravityNotAnswering: return .openApp("Antigravity")
        // The remedy for both is the same thing: start it. A plan it has never
        // recorded is one sign-in away, and opening the app is the step before
        // that either way.
        case .devinAppMissing, .devinPlanUnread: return .openApp("Devin")
        case .notSignedIn, .signedOut, .kimiSignInRequired, .kimiLoginExpired: return .signIn
        case .apiKeyMissing, .apiKeyRefused, .devinOrganizationMissing: return .editCredential
        case .ollamaSessionMissing, .ollamaSessionExpired,
             .qoderSessionMissing, .qoderSessionExpired,
             .xiaomiSessionMissing, .xiaomiSessionExpired: return .readBrowser
