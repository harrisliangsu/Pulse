import Testing
@testable import Pulse

/// Which feed the updater reads: the mirror or GitHub, and the language
/// Pulse is set to, so the notes in the update window come in that language.
struct AppUpdateFeedTests {
    @Test func followingTheSystemReadsTheMainFeed() {
        #expect(AppUpdate.feedURL(for: .system, host: .mirror) == "https://update.qunqin.org/appcast.xml")
        #expect(AppUpdate.feedURL(for: .system, host: .github)
            == "https://raw.githubusercontent.com/qunqin24/Pulse/main/appcast.xml")
    }

    @Test func aChosenLanguageReadsItsOwnFeed() {
        #expect(AppUpdate.feedURL(for: .chineseSimplified, host: .mirror) == "https://update.qunqin.org/appcast-zh.xml")
        // No Traditional notes are written; the Chinese ones read better than English.
        #expect(AppUpdate.feedURL(for: .chineseTraditional, host: .mirror) == "https://update.qunqin.org/appcast-zh.xml")
        #expect(AppUpdate.feedURL(for: .english, host: .github)
            == "https://raw.githubusercontent.com/qunqin24/Pulse/main/appcast-en.xml")
        #expect(AppUpdate.feedURL(for: .japanese, host: .mirror) == "https://update.qunqin.org/appcast-en.xml")
        #expect(AppUpdate.feedURL(for: .korean, host: .mirror) == "https://update.qunqin.org/appcast-en.xml")
    }

    @Test func aFailedHostHandsOverToTheOther() {
        #expect(AppUpdate.FeedHost.mirror.other == .github)
        #expect(AppUpdate.FeedHost.github.other == .mirror)
    }

    @Test @MainActor func theMirrorIsFirst() {
        #expect(AppUpdate().host == .mirror)
    }
}
