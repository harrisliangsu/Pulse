import Carbon.HIToolbox
import AppKit
import Testing
@testable import Pulse

/// What Pulse will and will not accept as a global shortcut, and how a stored
/// one survives a launch.
///
/// The rules here are the ones that cannot be checked by looking at the screen:
/// a combination with no real modifier in it registers happily and then takes a
/// letter away from every text field on the Mac, and a stored value that stops
/// parsing has to read as no shortcut rather than as some other key.
@Suite("Global shortcut")
struct GlobalShortcutTests {
    /// kVK_ANSI_P, which is what the settings pane's example uses.
    private static let p: UInt16 = 35

    @Test("A modifier that is not ⇧ alone is required")
    func requiresRealModifier() {
        #expect(GlobalShortcut(keyCode: Self.p, modifiers: []) == nil)
        #expect(GlobalShortcut(keyCode: Self.p, modifiers: [.shift]) == nil)
        #expect(GlobalShortcut(keyCode: Self.p, modifiers: [.command]) != nil)
        #expect(GlobalShortcut(keyCode: Self.p, modifiers: [.option]) != nil)
        #expect(GlobalShortcut(keyCode: Self.p, modifiers: [.control]) != nil)
        #expect(GlobalShortcut(keyCode: Self.p, modifiers: [.shift, .command]) != nil)
    }

    /// Caps lock and the function key arrive in the same field and are not part
    /// of a combination; keeping them would make two presses of the same keys
    /// store two different shortcuts.
    @Test("Modifiers outside the four are dropped")
    func keepsOnlyTheFour() {
        let shortcut = GlobalShortcut(
            keyCode: Self.p,
            modifiers: [.command, .capsLock, .function, .numericPad]
        )
        #expect(shortcut?.modifiers == [.command])
    }

    @Test("A stored shortcut comes back as itself")
    func storageRoundTrips() {
        let shortcut = GlobalShortcut(keyCode: Self.p, modifiers: [.command, .option, .shift])
        #expect(GlobalShortcut(storage: shortcut!.storage) == shortcut)
    }

    /// Written by a version that stored them differently, or edited by hand.
    @Test("Storage that no longer parses is no shortcut")
    func storageRejectsRubbish() {
        #expect(GlobalShortcut(storage: "") == nil)
        #expect(GlobalShortcut(storage: "35") == nil)
        #expect(GlobalShortcut(storage: "35:") == nil)
        #expect(GlobalShortcut(storage: "P:command") == nil)
        #expect(GlobalShortcut(storage: "35:1:2") == nil)
        // Parses, but says no modifiers — which is a shortcut Pulse would not
        // have written and must not honour now.
        #expect(GlobalShortcut(storage: "35:0") == nil)
    }

    @Test("Modifiers are written in the system's order")
    func displayOrder() {
        let all = GlobalShortcut(keyCode: Self.p, modifiers: [.command, .shift, .option, .control])
        #expect(all?.display == "⌃⌥⇧⌘P")

        let pair = GlobalShortcut(keyCode: Self.p, modifiers: [.command, .option])
        #expect(pair?.display == "⌥⌘P")
    }

    /// Better a combination the reader cannot name than one shown as some
    /// other key.
    @Test("An unlisted key code is shown as a number, not as a guess")
    func unknownKeyLabel() {
        #expect(GlobalShortcut.label(for: 200) == "#200")
    }

    @Test("Carbon gets the same four modifiers")
    func carbonModifiers() {
        let shortcut = GlobalShortcut(keyCode: Self.p, modifiers: [.command, .option])
        let bits = shortcut!.carbonModifiers
        #expect(bits & UInt32(cmdKey) != 0)
        #expect(bits & UInt32(optionKey) != 0)
        #expect(bits & UInt32(controlKey) == 0)
        #expect(bits & UInt32(shiftKey) == 0)
    }
}
