import Testing
@testable import Pulse

/// Which feed the updater reads. This fork has one host: its own files on
/// GitHub. A language Pulse is set to reads that language's copy, so the
/// notes in the update window come in that language. The qunqin.org mirror
/// is not a host.
struct AppUpdateFeedTests {
    private static let base = "https://raw.githubusercontent.com/harrisliangsu/Pulse/main/"

    @Test func followingTheSystemReadsTheMainFeed() {
        #expect(AppUpdate.feedURL(for: .system) == Self.base + "appcast.xml")
    }

    @Test func aChosenLanguageReadsItsOwnFeed() {
        #expect(AppUpdate.feedURL(for: .chineseSimplified) == Self.base + "appcast-zh.xml")
        // No Traditional notes are written; the Chinese ones read better than English.
        #expect(AppUpdate.feedURL(for: .chineseTraditional) == Self.base + "appcast-zh.xml")
        #expect(AppUpdate.feedURL(for: .english) == Self.base + "appcast-en.xml")
        #expect(AppUpdate.feedURL(for: .japanese) == Self.base + "appcast-en.xml")
        #expect(AppUpdate.feedURL(for: .korean) == Self.base + "appcast-en.xml")
    }

    @Test func anotherBaseStillPicksTheFile() {
        let other = "https://example.invalid/feeds/"
        #expect(AppUpdate.feedURL(for: .system, base: other) == other + "appcast.xml")
        #expect(AppUpdate.feedURL(for: .english, base: other) == other + "appcast-en.xml")
    }

    @Test func onlyThisForksGitHubFeedIsAcceptedAsABase() {
        #expect(AppUpdate.feedBase(from: nil) == AppUpdate.githubBase)
        #expect(AppUpdate.feedBase(from: "https://update.qunqin.org/appcast.xml") == AppUpdate.githubBase)
        #expect(AppUpdate.feedBase(from: "https://raw.githubusercontent.com/qunqin24/Pulse/main/appcast.xml") == AppUpdate.githubBase)
        #expect(
            AppUpdate.feedBase(from: "https://raw.githubusercontent.com/harrisliangsu/Pulse/main/appcast.xml")
                == AppUpdate.githubBase
        )
        #expect(
            AppUpdate.feedBase(from: "https://raw.githubusercontent.com/harrisliangsu/Pulse/main/appcast-zh.xml")
                == AppUpdate.githubBase
        )
    }
}
