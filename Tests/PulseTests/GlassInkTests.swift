import SwiftUI
import Testing
@testable import Pulse

/// The text on glass follows the Transparency slider from white to black.
@Suite("Glass ink")
struct GlassInkTests {
    @Test("Up to the default the text keeps the label colour and the scheme stays dark")
    func unchangedUpToTheDefault() {
        for t in [0.0, 0.3, PanelGlass.defaultTransparency] {
            #expect(PanelGlass.ink(transparency: t) == nil)
            #expect(PanelGlass.scheme(transparency: t) == .dark)
        }
    }

    @Test("Past the default the text darkens to black at the clearest end")
    func darkensToBlack() {
        #expect(PanelGlass.ink(transparency: 0.75) == Color(white: 0.5, opacity: 0.85))
        #expect(PanelGlass.ink(transparency: 1) == Color(white: 0, opacity: 0.85))
        #expect(PanelGlass.scheme(transparency: 0.75) == .dark)
        #expect(PanelGlass.scheme(transparency: 0.9) == .light)
    }
}
