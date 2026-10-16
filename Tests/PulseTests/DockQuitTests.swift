import Foundation
import CoreServices
import Testing
@testable import Pulse

/// The Dock's Quit closes Pulse's windows; every other quit quits.
@Suite("Dock quit")
struct DockQuitTests {
    private let quitClass = AEEventClass(kCoreEventClass)
    private let quitID = AEEventID(kAEQuitApplication)

    @Test("Only a quit from the Dock, with no reason, closes the windows instead")
    func onlyTheDock() {
        #expect(DockQuit.closesWindowsOnly(eventClass: quitClass, eventID: quitID, sender: "com.apple.dock", hasQuitReason: false))
        // Logout, restart and shutdown always quit.
        #expect(!DockQuit.closesWindowsOnly(eventClass: quitClass, eventID: quitID, sender: "com.apple.dock", hasQuitReason: true))
        #expect(!DockQuit.closesWindowsOnly(eventClass: quitClass, eventID: quitID, sender: "com.apple.loginwindow", hasQuitReason: true))
        // A script, or no event at all (⌘Q, the menus), quits.
        #expect(!DockQuit.closesWindowsOnly(eventClass: quitClass, eventID: quitID, sender: "com.apple.ScriptEditor2", hasQuitReason: false))
        #expect(!DockQuit.closesWindowsOnly(eventClass: quitClass, eventID: quitID, sender: nil, hasQuitReason: false))
        #expect(!DockQuit.isFromDock(nil))
        // Not a quit event.
        #expect(!DockQuit.closesWindowsOnly(eventClass: quitClass, eventID: AEEventID(kAEOpenApplication), sender: "com.apple.dock", hasQuitReason: false))
    }
}
