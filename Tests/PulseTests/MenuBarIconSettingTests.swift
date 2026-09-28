import AppKit
import Foundation
import Testing
@testable import Pulse

@Suite("Menu bar icon setting")
struct MenuBarIconSettingTests {
    @Test("The icon remains visible by default and uses a dedicated callback")
    @MainActor
    func defaultAndCallback() {
        let key = "settings.hidesMenuBarIcon"
        defer { UserDefaults.standard.removeObject(forKey: key) }

        let settings = AppSettings()
        #expect(!settings.hidesMenuBarIcon)

        var menuBarChanges = 0
        var panelChanges = 0
        settings.onMenuBarIconChange = { menuBarChanges += 1 }
        settings.onChange = { panelChanges += 1 }

        settings.hidesMenuBarIcon = true
        #expect(menuBarChanges == 1)
        #expect(panelChanges == 0)

        settings.hidesMenuBarIcon = true
        #expect(menuBarChanges == 1)
        #expect(panelChanges == 0)
    }

    @Test("The menu bar remains when both other entry points are unavailable")
    func preservesAnEntryPoint() {
        // `panelVisible` means an actual panel can be shown. Before provider
        // selection the caller passes false even if the preference is true.
        #expect(AppDelegate.menuBarIconMustRemainVisible(
            panelVisible: false, hasRegisteredShortcut: false
        ))
        #expect(!AppDelegate.menuBarIconMustRemainVisible(
            panelVisible: true, hasRegisteredShortcut: false
        ))
        #expect(!AppDelegate.menuBarIconMustRemainVisible(
            panelVisible: false, hasRegisteredShortcut: true
        ))
    }

    @Test("The status menu can be rebuilt and keeps its keyboard shortcuts")
    @MainActor
    func statusMenuRebuild() {
        let delegate = AppDelegate()
        let menu = NSMenu()

        delegate.menuNeedsUpdate(menu)
        delegate.menuNeedsUpdate(menu)

        // Whether a service is chosen comes from this machine's defaults, so
        // the menu is checked for either state rather than assuming one.
        // Until one is, the menu leads with the way back to the chooser.
        let lead = delegate.settings.needsProviderSelection ? 2 : 0
        if lead > 0 {
            #expect(menu.items[0].title == String.localized("Choose services to start monitoring…"))
            #expect(menu.items[1].isSeparatorItem)
        }
        // Once one is, the panel's switch comes first — somebody who wants
        // only the menu bar turns the rail off from here.
        var rest = Array(menu.items.dropFirst(lead))
        if !delegate.settings.needsProviderSelection {
            #expect(rest.first?.title == String.localized("Show floating panel"))
            #expect(rest.first?.state == (delegate.settings.isPanelVisible ? .on : .off))
            rest.removeFirst()
        }
        #expect(rest.map(\.keyEquivalent) == [",", "", "q"])
        #expect(rest[0].keyEquivalentModifierMask == .command)
        #expect(rest[2].keyEquivalentModifierMask == .command)
    }
}
