import AppKit
import SwiftUI

/// What colour a provider's bot mark is drawn in.
///
/// The mark stands where the provider's logo stood, so its colour is
/// **identity**, not status — the same job the logo was doing. That is what
/// keeps it clear of `UsageTint`, where colour means one thing only: how
/// close a limit is. The ring around the mark still carries that, unchanged.
///
/// **It is still a risk worth naming.** Rings were drawn in brand colours
/// once and it went badly, because Claude Code's orange-red at 3% used looked
/// like a warning. A brand colour on the disc is a weaker version of the same
/// hazard: the ring is the thing that turns red, but a red-ish body inside a
/// green ring is two colours disagreeing. If that reads badly on a real rail,
/// the fix is this table, not the ring.
enum BotMarkTint {
    /// Brand colours, for the providers that have one.
    ///
    /// Nil is not "unknown", it is **monochrome by design** — OpenAI, Cursor,
    /// GitHub, xAI, Ollama, OpenCode and the rest draw a black-or-white glyph
    /// and nothing else. Those get a colour of Pulse's own, see `assigned`.
    ///
    /// Marked below are the values taken from a product's palette with less
    /// certainty than the others; they are one line each to correct. Kimi's
    /// blue, Z.ai having no colour of its own, and MiniMax's red are what the
    /// person maintaining this app says they are.
    static func brand(for provider: Provider) -> Color? {
        switch provider {
        case .claudeCode: BotMarkPalette.rgb(0xD97757)
        case .deepSeek: BotMarkPalette.rgb(0x4D6BFE)
        case .volcengine: BotMarkPalette.rgb(0x1664FF)
        // Best-guess brand colours: right family, exact value unconfirmed.
        case .minimax, .minimaxCN: BotMarkPalette.rgb(0xE8483F)
        // Best-guess brand colours: right family, exact value unconfirmed.
        case .antigravity: BotMarkPalette.rgb(0x4285F4)
        case .glmCoding: BotMarkPalette.rgb(0x3A7BF7)
        case .kimiCode: BotMarkPalette.rgb(0x7AA5FF)
        // Fork-only provider: teal from Qoder's product palette (approx.).
        case .qoder: BotMarkPalette.rgb(0x0D9488)
        // Xiaomi's orange. The MiMo console is black-on-white, but the parent
        // brand's colour is the one a reader recognises on a rail.
        case .xiaomiMiMo: BotMarkPalette.rgb(0xFF6900)
