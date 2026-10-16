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
        navigation.pane = .rings
        navigation.open(.general)
        navigation.pane = .network

        navigation.goBack(where: always)
        #expect(navigation.pane == .general)
        navigation.goBack(where: always)
        #expect(navigation.pane == .rings)
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
        navigation.pane = .rings

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
}
