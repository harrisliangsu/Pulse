// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import AppKit
import Testing
@testable import Pulse

/// Sparkle's update window needs `.regular` or it opens behind everything.
/// The decision is pure; the window server is not involved.
@Suite("Update offer activation")
struct UpdateOfferActivationTests {
    @Test("The Dock icon stays for an update offer, and for a settings window only while that switch is on")
    func policy() {
        #expect(
            DockPresence.activationPolicy(
                trackedWindowOpen: false,
                showsDockIconInSettings: true,
                updateOfferVisible: false
            ) == .accessory
        )
        #expect(
            DockPresence.activationPolicy(
                trackedWindowOpen: false,
                showsDockIconInSettings: false,
                updateOfferVisible: true
            ) == .regular
        )
        #expect(
            DockPresence.activationPolicy(
                trackedWindowOpen: true,
                showsDockIconInSettings: true,
                updateOfferVisible: false
            ) == .regular
        )
        #expect(
            DockPresence.activationPolicy(
                trackedWindowOpen: true,
                showsDockIconInSettings: false,
                updateOfferVisible: false
            ) == .accessory
        )
        #expect(
            DockPresence.activationPolicy(
                trackedWindowOpen: true,
                showsDockIconInSettings: false,
                updateOfferVisible: true
            ) == .regular
        )
    }

    @Test("The offer window is Sparkle's update alert")
    func offerWindow() {
        #expect(AppUpdate.isSparkleUpdateOffer(frameAutosaveName: "SUUpdateAlert2", windowControllerClassName: nil))
        #expect(AppUpdate.isSparkleUpdateOffer(frameAutosaveName: "", windowControllerClassName: "SUUpdateAlert"))
        #expect(!AppUpdate.isSparkleUpdateOffer(frameAutosaveName: "", windowControllerClassName: nil))
        #expect(!AppUpdate.isSparkleUpdateOffer(frameAutosaveName: "SUStatus", windowControllerClassName: "SUStatusController"))
    }
}
