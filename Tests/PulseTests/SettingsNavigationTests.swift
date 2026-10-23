import Testing
@testable import Pulse

/// The settings window's back and forward (`SettingsNavigation`), as System
/// Settings has them.
@MainActor
@Suite("Settings back and forward")
struct SettingsNavigationTests {
    private let always: (SettingsPane) -> Bool = { _ in true }

    @Test("Back and forward retrace the panes visited, and a new visit drops what was ahead")
    func history() {
        let navigation = SettingsNavigation()
        navigation.pane = .usageCard
        navigation.open(.general)
        navigation.pane = .network

        navigation.goBack(where: always)
        #expect(navigation.pane == .general)
        navigation.goBack(where: always)
        #expect(navigation.pane == .usageCard)
        navigation.goForward(where: always)
        #expect(navigation.pane == .general)

        navigation.pane = .about
        #expect(navigation.forward.isEmpty)
        navigation.goBack(where: always)
        #expect(navigation.pane == .general)
    }

    @Test("Going back skips a pane that cannot be shown any more, and does nothing with nowhere to go")
    func skipsGone() {
        let navigation = SettingsNavigation()
        let removed = AccountKey(.codex)
        navigation.pane = .account(removed)
        navigation.pane = .usageCard

        navigation.goBack(where: { $0 != .account(removed) })
        #expect(navigation.pane == .appearance)
        navigation.goBack(where: always)
        #expect(navigation.pane == .appearance)
        #expect(navigation.back.isEmpty)
    }

    @Test("Choosing the pane already open is not a step")
    func samePane() {
        let navigation = SettingsNavigation()
        navigation.pane = .appearance
        #expect(navigation.back.isEmpty)
    }

    @Test("The panel lists Usage card, and Rings and figures is not a pane")
    func usageCardReplacesRings() {
        LocalizationSource.use(.english)
        defer { LocalizationSource.use(.system) }

        #expect(SettingsPane.panel == [.appearance, .usageCard, .placement])
        #expect(SettingsPane.usageCard.title == "Usage card")
        #expect(SettingsPane.notifications.title == "Exhaustion and reminders")
        #expect(SettingsPane.usageCard.searchTerms.contains("Percentages at the side"))
        #expect(SettingsPane.usageCard.searchTerms.contains("Exhaustion on the card"))
        #expect(SettingsPane.usageCard.searchTerms.contains("Which accounts"))
        #expect(SettingsPane.appearance.searchTerms.contains("Ring colour scheme"))
        #expect(SettingsPane.appearance.searchTerms.contains("Colour"))
        #expect(!SettingsPane.notifications.searchTerms.contains("What the card shows"))
        #expect(SettingsPane.notifications.searchTerms.contains("Exhaustion notifications"))
        #expect(SettingsPane.notifications.searchTerms.contains("Notify when a limit is running out"))
    }
}
