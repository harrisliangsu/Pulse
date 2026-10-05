import Testing
@testable import Pulse

/// Which feed the updater reads, so the notes in the update window come in
/// the language Pulse is set to.
struct AppUpdateFeedTests {
    private let base = "https://raw.githubusercontent.com/qunqin24/Pulse/main/appcast.xml"

    @Test func followingTheSystemReadsTheMainFeed() {
        #expect(AppUpdate.feedURL(for: .system, base: base) == nil)
    }

    @Test func aChosenLanguageReadsItsOwnFeed() {
        let zh = "https://raw.githubusercontent.com/qunqin24/Pulse/main/appcast-zh.xml"
        let en = "https://raw.githubusercontent.com/qunqin24/Pulse/main/appcast-en.xml"
        #expect(AppUpdate.feedURL(for: .chineseSimplified, base: base) == zh)
        // No Traditional notes are written; the Chinese ones read better than English.
        #expect(AppUpdate.feedURL(for: .chineseTraditional, base: base) == zh)
        #expect(AppUpdate.feedURL(for: .english, base: base) == en)
        #expect(AppUpdate.feedURL(for: .japanese, base: base) == en)
        #expect(AppUpdate.feedURL(for: .korean, base: base) == en)
    }

    @Test func anUnfamiliarFeedIsLeftAlone() {
        #expect(AppUpdate.feedURL(for: .english, base: nil) == nil)
        #expect(AppUpdate.feedURL(for: .english, base: "https://example.com/feed.xml") == nil)
    }
}
