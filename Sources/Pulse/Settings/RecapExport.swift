// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import AppKit
import UniformTypeIdentifiers

/// Getting a card out of the window: a file, a folder of files, the clipboard,
/// the share sheet.
///
/// **The card is drawn again for each, by `RecapRenderer`, at its full
/// 1080 × 1920** — never a screenshot of the scaled preview. Rendering is
/// `ImageRenderer`, which is main-actor only; one card takes well under a
/// second, and "Save all" yields between cards so the window keeps answering.
///
/// **Nothing is kept.** A file is written where the person chose. Sharing
/// writes one PNG into its own folder (a UUID) under `Pulse Recap/` in the
/// temporary folder, because the share sheet takes a file and the app it hands
/// the file to may still be reading it when the next share is made — an earlier
/// share's folder is never removed by a later one. The whole `Pulse Recap`
/// folder goes when the recap window closes (`removeShareFolder`), and macOS
/// clears the temporary folder itself.
///
/// **Save all overwrites.** A file of the same name in the folder the person
/// picked is replaced (the names carry the period and the card, so a second
/// save of the same recap lands on the first); the open panel has already asked
/// where, and nothing else in that folder is touched.
@MainActor
enum RecapExport {
    enum Outcome: Equatable {
        case saved
        case copied
        /// The share sheet is open; it reports the rest itself.
        case presented
        case cancelled
        case failed
    }

    /// "pulse-recap-2026-09-02-opener.png": the period, the card's place in
    /// the deck, and its name — sorted in a folder in the order they are shown.
    static func fileName(for card: RecapCard, in deck: RecapDeck) -> String {
        let place = (deck.cards.firstIndex(of: card) ?? 0) + 1
        return "pulse-recap-\(deck.recap.period.key)-\(String(format: "%02d", place))-\(card.rawValue).png"
    }

    // MARK: - File

    static func save(_ card: RecapCard, of deck: RecapDeck, from window: NSWindow?) async -> Outcome {
        guard let data = RecapRenderer.png(of: card, in: deck) else { return .failed }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = fileName(for: card, in: deck)
        panel.canCreateDirectories = true
        guard await run(panel, in: window) == .OK, let url = panel.url else { return .cancelled }
        return write(data, to: url) ? .saved : .failed
    }

    /// Every card of the deck, poster included, into a folder the person picks.
    static func saveAll(_ deck: RecapDeck, from window: NSWindow?) async -> Outcome {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = .localized("Save here")
        guard await run(panel, in: window) == .OK, let folder = panel.url else { return .cancelled }

        for card in deck.cards {
            guard let data = RecapRenderer.png(of: card, in: deck),
                  write(data, to: folder.appendingPathComponent(fileName(for: card, in: deck))) else { return .failed }
            // Let the window draw between cards.
            await Task.yield()
        }
        return .saved
    }

    private static func run(_ panel: NSSavePanel, in window: NSWindow?) async -> NSApplication.ModalResponse {
        guard let window else { return panel.runModal() }
        return await withCheckedContinuation { continuation in
            panel.beginSheetModal(for: window) { continuation.resume(returning: $0) }
        }
    }

    private static func write(_ data: Data, to url: URL) -> Bool {
        do {
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    // MARK: - Clipboard

    static func copy(_ card: RecapCard, of deck: RecapDeck) -> Outcome {
        guard let image = RecapRenderer.image(of: card, in: deck) else { return .failed }
        let bitmap = NSBitmapImageRep(cgImage: image)
        guard let png = bitmap.representation(using: .png, properties: [:]) else { return .failed }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setData(png, forType: .png)
        // Apps that read only TIFF (older ones, some chat clients) still get it.
        if let tiff = bitmap.tiffRepresentation { pasteboard.setData(tiff, forType: .tiff) }
        return .copied
    }

    // MARK: - Share

    private static var shareFolder: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("Pulse Recap", isDirectory: true)
    }

    /// Opens the system share sheet on the card's PNG, anchored to `view`.
    static func share(_ card: RecapCard, of deck: RecapDeck, from view: NSView) -> Outcome {
        guard let data = RecapRenderer.png(of: card, in: deck) else { return .failed }
        let folder = shareFolder.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let url = folder.appendingPathComponent(fileName(for: card, in: deck))
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
        } catch {
            return .failed
        }
        NSSharingServicePicker(items: [url]).show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
        return .presented
    }

    /// Removes every file this window handed to the share sheet. Called when
    /// the recap window closes, never between shares.
    static func removeShareFolder() {
        try? FileManager.default.removeItem(at: shareFolder)
    }
}
