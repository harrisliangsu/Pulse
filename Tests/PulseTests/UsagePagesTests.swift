import Foundation
import Testing
@testable import Pulse

/// The menu's "Open usage page" links: only pages, only over HTTPS, and the
/// big four present.
@Suite("Usage pages")
struct UsagePagesTests {
    @Test("Every listed page is an https address")
    func pagesAreHTTPS() {
        for provider in Provider.builtIn {
            guard let page = provider.usagePage else { continue }
            #expect(page.scheme == "https", "\(provider)")
            #expect(page.host?.isEmpty == false, "\(provider)")
        }
    }

    @Test("The providers most people use have one", arguments: [Provider.claudeCode, .codex, .cursor, .copilot])
    func commonProvidersHaveOne(provider: Provider) {
        #expect(provider.usagePage != nil)
    }

    @Test("An extension has none: Pulse does not know where its service lives")
    func extensionHasNone() {
        #expect(Provider.pulseExtension.usagePage == nil)
    }
}
