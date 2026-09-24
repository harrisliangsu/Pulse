import AppKit
import SwiftUI

/// Layout constants for the detail bubble. Shared with
/// `FloatingPanelController.Layout` (which derives `expandedWidth` from
/// these plus `DockLayout`) and with `FloatingUsagePanelView`'s vertical
/// alignment math, so the AppKit panel frame and the SwiftUI content never
/// drift apart.
enum DetailCardLayout {
    static var width: CGFloat { 250 * PanelMetrics.scale }
    static var padding: CGFloat { 18 * PanelMetrics.scale }
    /// The rings' own curve: the outer edge of a ring's stroke, 20pt at
    /// standard size.
    ///
    /// One circle sets every curve on the panel — the rail's ends are this
    /// plus the band beside a ring (`DockLayout.cornerRadius`), the card's
    /// corners are this — so the three shapes read as one family instead of
    /// three radii picked separately. It also sits where the card's own
    /// content puts it: 18pt of padding round a bar whose ends are 3pt round.
    static var cornerRadius: CGFloat { (DockLayout.ringDiameter + DockLayout.ringLineWidth) / 2 }

    static var pointerWidth: CGFloat { 20 * PanelMetrics.scale }
    static var pointerHeight: CGFloat { 40 * PanelMetrics.scale }
    /// Gap between the pointer's tip and the dock rail. The tip approaches
    /// the rail but doesn't need to touch it.
    static var horizontalGap: CGFloat { 8 * PanelMetrics.scale }

    /// Vertical rhythm between header / progress row / progress row.
    static var contentSpacing: CGFloat { 14 * PanelMetrics.scale }
    /// Spacing between a row's title line, its progress bar, and its
    /// percent line.
    static var rowInternalSpacing: CGFloat { 7 * PanelMetrics.scale }
    static var progressBarHeight: CGFloat { 6 * PanelMetrics.scale }
    /// Rendered line height of the header row (icon + title).
    static var headerHeight: CGFloat { 19 * PanelMetrics.scale }

    // Type scales with everything else. It did not, once: the card's *width*
    // followed `PanelMetrics` while every font in it was written as a constant,
    // so at Small a 205pt card still tried to hold 14pt text and truncated its
    // own title, and at Large a 305pt card held the same 11.5pt rows and read
    // as half empty next to rings that had grown. The line-height budgets above
    // were already scaled, which is what makes these ratios hold at every size.
    static var titleFontSize: CGFloat { 14 * PanelMetrics.scale }
    static var rowFontSize: CGFloat { 11.5 * PanelMetrics.scale }
    static var messageFontSize: CGFloat { 12 * PanelMetrics.scale }
    static var footnoteFontSize: CGFloat { 11 * PanelMetrics.scale }
    /// The provider's mark in the header.
    static var headerIconSize: CGFloat { 16 * PanelMetrics.scale }
    /// Rendered line height of a row's title/percent text.
    static var rowTextLineHeight: CGFloat { 14 * PanelMetrics.scale }

    static var rowHeight: CGFloat {
        rowTextLineHeight + rowInternalSpacing + progressBarHeight + rowInternalSpacing + rowTextLineHeight
            // The forecast is a fourth line under every limit, and the panel's
            // frame is worked out from this before SwiftUI lays anything out.
            // Left out, a top-docked card with five limits ran 84pt past the
            // window and was sliced flat against its edge.
            + (PanelMetrics.showsForecast ? rowInternalSpacing + rowTextLineHeight : 0)
    }

    /// Starting guess for the card's height, used for the very first layout
    /// pass only. The real height depends on how many limits the provider
    /// reports, so `FloatingUsagePanelView` measures it and works from that
    /// instead — see its `cardHeight`.
    static var estimatedHeight: CGFloat { height(forWindows: 2) }

    /// Room the panel has to leave for the tallest card it might have to show.
    ///
    /// The panel's frame is fixed, and a card taller than it gets sliced off
    /// square against the window's edge — which looks like a rendering bug,
    /// not like a card that didn't fit. Providers report a variable number of
    /// limits (Codex adds one group per model with its own limits), so this
    /// budgets for more than are on screen today. Codex also adds the reset
    /// intel block; that height is in the budget before any card opens, so
    /// opening one does not resize the window.
    static var maximumHeight: CGFloat { height(forWindows: 5, footnote: true) + codexIntelHeight }

    /// Prediction line, a wrapped forecast phrase, the latest announcement
    /// (one line of relative time, then a type-and-clock line that may wrap),
    /// and banked credits. The prediction, the forecast, the type line, and
    /// the credits may each take two lines. The budget is that tall case — a
    /// watch, a latest announcement, and reset cards together — even when a
    /// given card draws fewer of them. The relative time stays on one line.
    /// The type's explanation is a tooltip on those words, not another row
    /// and not an icon. The link to the site sits on the prediction line, so
    /// it adds no row of its own.
    static var codexIntelHeight: CGFloat {
        contentSpacing
            + rowTextLineHeight * 2
            + rowInternalSpacing + rowTextLineHeight * 2
            + rowInternalSpacing + rowTextLineHeight
            + rowInternalSpacing + rowTextLineHeight * 2
            + rowInternalSpacing + rowTextLineHeight * 2
    }

    static func height(forWindows count: Int, footnote: Bool = false) -> CGFloat {
        padding * 2
            + headerHeight
            + CGFloat(count) * (contentSpacing + rowHeight)
            + (footnote ? contentSpacing + footnoteHeight : 0)
    }

    /// Rendered line height of the "as of …" line under the limits.
    static var footnoteHeight: CGFloat { 13 * PanelMetrics.scale }
}

struct UsageDetailCard: View {
    /// Liquid Glass instead of flat black, matching the rail.
    var usesGlass: Bool = false
    let usage: ProviderUsage
    /// What this account is called. The provider's own name for the first
    /// account of it, the user's label for the rest — two subscriptions to the
    /// same plan are told apart by nothing else, and a card headed "Codex" on
    /// both of them is a card that cannot say which one you are looking at.
    var title: String?
    /// Which screen edge the panel is docked against; the pointer goes on the
    /// side facing the rail.
    let edge: PanelEdge
    /// Show what is left rather than what is gone, matching the rail.
    var showsRemaining: Bool = false
    /// Say whether each limit will last its window.
    var showsForecast: Bool = false
    /// Where the pointer's tip should sit along the side facing the rail,
    /// measured from the card's own top or leading edge. The card gets pushed
    /// around by the panel's own edges (see
    /// `FloatingUsagePanelView.cardPadding`), so the pointer can't just ride
    /// at the card's centre — it has to be placed independently to keep aiming
    /// at the selected ring.
    let pointerCenter: CGFloat
    /// The panel is never key, so Settings and Quit on the menu bar extras
    /// are a hunt. These ride the card header: they take no extra height.
    var openSettings: (() -> Void)? = nil
    /// Codex Resets' public status. Nil until a fetch or the disk cache lands.
    /// The prediction row still says there is no prediction rather than
    /// leaving a hole. A latest announcement is a separate row under that.
    ///
    /// A snapshot. The open card does not keep this: see `codexResets`.
    var codexReset: CodexResetStatus? = nil
    /// The store the open card reads, so a `latest` that arrives after the
    /// card is up still draws the row. Nil in previews, which pass
    /// `codexReset` instead.
    var codexResets: UsageStore? = nil
    /// Banked credits for the primary Codex login. Nil when the app server
    /// has not answered; the line is omitted.
    var codexCredits: CodexCreditSummary? = nil

    /// Where Red alert turns red, so the card's bars agree with the rail's rings.
    @Environment(\.usageWarningThreshold) private var warningThreshold
    /// The colour language, so the bars agree with the rings.
    @Environment(\.ringColourScheme) private var ringColourScheme

    var body: some View {
        VStack(alignment: .leading, spacing: DetailCardLayout.contentSpacing) {
            header

            // However many limits the provider reports — one account-wide
            // window for some plans, several once per-model limits apply.
            ForEach(usage.windows) { window in
                ProgressMetricRow(
                    title: window.name,
                    resetDescription: Self.resetText(window),
                    progress: showsRemaining ? window.remainingFraction : window.usedFraction,
                    accent: window.tint(warningAt: warningThreshold, scheme: ringColourScheme),
                    percentageText: window.percentText(remaining: showsRemaining),
                    isSpent: UsageTint.isSpent(window),
                    showsRemaining: showsRemaining,
                    // Every provider, not a chosen few: what this needs is a
                    // percentage, a reset and a length the provider actually
                    // stated, and `BurnRate` refuses the windows that lack one
                    // rather than being told in advance which they are.
                    burn: showsForecast ? BurnRate.reading(for: window) : nil
                )
                .transition(Self.rowTransition)
            }

            // **A card with only a title in it reads as a card that failed to
            // load.** Every provider until DeepSeek reported at least one
            // limit, so an empty body could only mean an unavailable reading
            // and the message below covered it. DeepSeek on "balance only"
            // reports money and no limits *by design*, and the money is then
            // the whole reading — so it is what the card says.
            if usage.windows.isEmpty, let balance = usage.creditBalance {
                ValueRow(title: String.localized("Credit balance"), value: balance)
            }

            // The same rule for the other way a body can come out empty: a
            // reading that says nothing at all still has to say *that*.
            if saysNothing {
                Text(ProviderUsage.Unavailability.noLimitsReported.message)
                    .font(.system(size: DetailCardLayout.messageFontSize, weight: .regular, design: .rounded))
                    .foregroundStyle(.primary.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)
            }

            if case .unavailable(let reason) = usage.state {
                Text(reason.message)
                    .font(.system(size: DetailCardLayout.messageFontSize, weight: .regular, design: .rounded))
                    .foregroundStyle(.primary.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)
            }

            if usage.provider == .codex {
                // Identity follows the announcement. The row is a branch that
                // is absent until `latest` exists, and this card is inserted
                // under the rail's reveal spring — a later value has to
                // replace the block, not hope the spring diffs it in.
                codexIntel
                    .id(CodexResetCardLines.identity(resolvedCodexReset))
                    .animation(nil, value: CodexResetCardLines.identity(resolvedCodexReset))
            }

            if let footnote {
                Text(footnote)
                    .font(.system(size: DetailCardLayout.footnoteFontSize, weight: .regular, design: .rounded))
                    .foregroundStyle(.primary.opacity(0.4))
            }
        }
        .padding(DetailCardLayout.padding)
        .frame(width: DetailCardLayout.width, alignment: .leading)
        // Room for the pointer on the side facing the rail. The shape below
        // covers the whole frame, body and pointer together.
        .padding(Self.pointerSide(for: edge), DetailCardLayout.pointerWidth)
        // **Inside the card, never ahead of it.** Switching between two cards
        // of different heights keeps this one view and swaps its rows: the
        // outline grows on the panel's spring, but a row the new card adds is
        // laid out at its final place at once, so it stood outside a card
        // that had not reached it yet — the text arriving before the card.
        // Masked to the same outline, the card uncovers it as it grows.
        // The content only: the surface keeps its own edge, where glass
        // draws a rim this would cut.
        .mask { bubble }
        // The card follows the rail's surface: a glass capsule beside a solid
        // black card reads as two different components, not one panel.
        .background(PanelSurface(shape: bubble, usesGlass: usesGlass))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String.localized("\(title ?? usage.provider.displayName) usage details"))
    }

    /// A limit the next card has and this one did not waits for the card to
    /// grow, then settles in; one it loses leaves at once.
    ///
    /// Arriving with the outline instead — the default — put the row at its
    /// final place on the first frame, so it either stood outside a card that
    /// had not reached it yet or, masked, was wiped on by the card's edge. Both
    /// read as a row popping in. A short wait lets the outline get ahead of
    /// it, so it is a card that grew, and then filled.
    ///
    /// **Short, because the rail is swept.** Running the pointer down the
    /// rings switches cards every tenth of a second, and every switch restarts
    /// this. At 0.14s + 0.22s the card spent most of a sweep empty — a black
    /// card with nothing in it. 0.06s + 0.14s still trails the outline and is
    /// done before the next ring.
    private static var rowTransition: AnyTransition {
        .asymmetric(
            insertion: .opacity
                .combined(with: .offset(y: -6))
                .animation(.easeOut(duration: 0.14).delay(0.06)),
            removal: .opacity.animation(.easeOut(duration: 0.06))
        )
    }

    private var bubble: UsageBubbleShape {
        UsageBubbleShape(
            edge: edge,
            pointerCenter: pointerCenter,
            cornerRadius: DetailCardLayout.cornerRadius,
            pointerWidth: DetailCardLayout.pointerWidth,
            pointerHeight: DetailCardLayout.pointerHeight
        )
    }

    /// Which side of the card the tail leaves from: the one facing the rail.
    private static func pointerSide(for edge: PanelEdge) -> Edge.Set {
        switch edge {
        case .left: .leading
        case .right: .trailing
        case .top: .top
        }
    }

    /// Whether the body would otherwise be nothing but the header.
    ///
    /// An unavailable reading is excluded because its own message is about to
    /// say something better than "no limits reported" — which route failed,
    /// or what to sign in to.
    private var saysNothing: Bool {
        guard usage.windows.isEmpty, usage.creditBalance == nil else { return false }
        if case .unavailable = usage.state { return false }
        return true
    }

    /// A line under the limits saying how much to trust them: Claude Code's
    /// figures only refresh while a session is running, so an old reading has
    /// to say so rather than pass for current.
    private var footnote: String? {
        switch usage.state {
        case .live, .unavailable:
            nil
        case .stale:
            usage.observedAt.map { String.localized("As of \(Self.relative($0))") }
                ?? String.localized("Reading may be out of date")
        }
    }

    private static func resetText(_ window: UsageWindow) -> String {
        // **The fallback may only state a length the provider stated.**
        // `windowSeconds` is sometimes a sort key rather than a measurement —
        // Cursor's billing cycle stored as a flat 30 days, Kimi's rolling
        // weekly allowance, Grok Bot's week — and printing one here would put
        // a figure nobody reported on the card, under a heading that reads
        // like a reported one. Nothing is said instead, which is the truth.
        guard let resets = window.resetsAt else {
            return window.reportsLength ? window.lengthText : ""
        }

        let formatter = DateFormatter()
        formatter.locale = LocalizationSource.locale
        // Same day: the time is enough. Otherwise the date matters too.
        formatter.setLocalizedDateFormatFromTemplate(
            Calendar.current.isDateInToday(resets) ? "jmm" : "MMMdjmm"
        )
        return String.localized("Resets \(formatter.string(from: resets))")
    }

    private static func relative(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    /// Irregular Codex reset intel, plus banked credits when the app server
    /// has them. Not the 5-hour or weekly `resetsAt` rows above.
    ///
    /// The prediction row is unchanged: an explicit time, a watch, or
    /// "No prediction yet". A latest announcement is an extra row under
    /// that, including when the prediction is empty. Account reset cards,
    /// when the app server has them, stay underneath: they are this login's
    /// inventory, not the public announcement.
    private var codexIntel: some View {
        VStack(alignment: .leading, spacing: DetailCardLayout.rowInternalSpacing) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(localized: "Predicted reset")
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                CodexResetsLink()

                Spacer(minLength: 8)

                Text(predictionValue)
                    .foregroundStyle(.primary.opacity(0.9))
                    .multilineTextAlignment(.trailing)
                    .lineLimit(2)
            }

            if let detail = predictionDetail {
                Text(verbatim: detail)
                    .foregroundStyle(.primary.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)
                    .lineLimit(2)
            }

            if let latest = codexLines.latest {
                latestAnnouncement(latest)
            }

            if let codexCredits, codexCredits.showsOnCard, usage.account.isPrimary {
                creditLine(codexCredits)
            }
        }
        .font(.system(size: DetailCardLayout.rowFontSize, weight: .regular, design: .rounded))
    }

    /// The status this card draws. The store wins while the panel is
    /// showing it, because that read is what invalidates an open card.
    private var resolvedCodexReset: CodexResetStatus? {
        if usage.provider == .codex, let codexResets {
            codexResets.codexResetStatus
        } else {
            codexReset
        }
    }

    private var codexLines: CodexResetCardLines {
        CodexResetCardLines.make(resolvedCodexReset)
    }

    /// Relative time, then type and local clock. Hovering the type — not an
    /// icon, and not the clock — shows the explanation, the same `.help` the
    /// header buttons already use. This panel has no popover. VoiceOver hears
    /// that explanation as the row's hint when there is one.
    private func latestAnnouncement(_ latest: CodexResetCardLines.Latest) -> some View {
        VStack(alignment: .leading, spacing: DetailCardLayout.rowInternalSpacing) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(localized: "Last reset")
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer(minLength: 8)

                Text(latest.relative)
                    .foregroundStyle(.primary.opacity(0.9))
                    .multilineTextAlignment(.trailing)
                    .lineLimit(1)
            }

            latestTypeLine(latest)
                .foregroundStyle(.primary.opacity(0.55))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String.localized("Last reset"))
        .accessibilityValue(latest.spoken)
        .codexResetHint(latest.help)
        .fixedSize(horizontal: false, vertical: true)
    }

    /// Type, then the local clock. The tooltip sits on the type. Every
    /// translation of the joined line uses the same separator, so the type
    /// can be its own view and the clock stays beside it. When the pair does
    /// not fit, the clock drops to the next line — still inside the two-line
    /// budget — rather than the type being clipped to make room for an icon.
    @ViewBuilder
    private func latestTypeLine(_ latest: CodexResetCardLines.Latest) -> some View {
        let type = Text(verbatim: latest.typeLabel)
            .lineLimit(1)
            .codexResetTooltip(latest.help)
        if latest.typeLabel.isEmpty {
            Text(verbatim: latest.absolute)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .codexResetTooltip(latest.help)
        } else if latest.absolute.isEmpty {
            type
        } else {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    type
                    Text(verbatim: " · \(latest.absolute)")
                        .lineLimit(1)
                }
                VStack(alignment: .leading, spacing: 0) {
                    type
                    Text(verbatim: latest.absolute)
                        .lineLimit(1)
                }
            }
        }
    }

    private var predictionValue: String {
        switch resolvedCodexReset?.card {
        case .scheduled(let date):
            Self.clock(date)
        case .watch(let watch):
            Self.watchHeadline(watch)
        case .empty, nil:
            .localized("No prediction yet")
        }
    }

    /// The API's own forecast phrase. Absent for an explicit time and for the
    /// empty state — `expires_at` is never rendered.
    private var predictionDetail: String? {
        guard case .watch(let watch) = resolvedCodexReset?.card else { return nil }
        return watch.forecastWindow
    }

    private static func watchHeadline(_ watch: CodexResetStatus.Watch) -> String {
        let level = switch watch.level {
        case "elevated": String.localized("Elevated")
        case "strong": String.localized("Strong")
        default: watch.level
        }
        guard let chance = watch.chancePercent else { return level }
        let figure = "\(chance)%"
        return .localized("\(level) · \(figure) chance")
    }

    private func creditLine(_ credits: CodexCreditSummary) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(localized: "Reset cards")
                    .foregroundStyle(.primary)
                Spacer(minLength: 8)
                Text(creditCount(credits.available))
                    .foregroundStyle(.primary.opacity(0.9))
                    .lineLimit(1)
            }
            if let expiry = creditExpiry(credits) {
                Text(expiry)
                    .foregroundStyle(.primary.opacity(0.55))
                    .lineLimit(1)
            }
        }
    }

    private func creditCount(_ available: Int) -> String {
        available == 1
            ? .localized("1 available")
            : .localized("\("\(available)") available")
    }

    private func creditExpiry(_ credits: CodexCreditSummary) -> String? {
        guard
            let expires = credits.nextExpiresAt,
            expires > Date(),
            let remaining = Self.remainingFormatter.string(from: Date(), to: expires)
        else { return nil }
        return .localized("Next expires in \(remaining)")
    }

    private static func clock(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = LocalizationSource.locale
        formatter.setLocalizedDateFormatFromTemplate(
            Calendar.current.isDateInToday(date) ? "jmm" : "MMMdjmm"
        )
        return formatter.string(from: date)
    }

    private static var remainingFormatter: DateComponentsFormatter {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.day, .hour]
        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = 2
        formatter.calendar = {
            var calendar = Calendar.current
            calendar.locale = LocalizationSource.locale
            return calendar
        }()
        return formatter
    }

    private var header: some View {
        // Another account's header replaces this one rather than cross-fading
        // through it: two titles of different lengths drawn over each other
        // for the length of the fade read as a smudge. Stacked so the outgoing
        // one keeps no room in the row while it leaves.
        ZStack(alignment: .leading) {
            HStack(spacing: 8) {
                LobeIconView(provider: usage.provider, size: DetailCardLayout.headerIconSize)
                    .foregroundStyle(.primary)

                Text(localized: "\(title ?? usage.provider.displayName) Usage")
                    // One line, always. The card's height is worked out from
                    // `DetailCardLayout` before SwiftUI lays anything out, so a
                    // header that wrapped would make the card taller than the
                    // window budgeted for it and get sliced off against the edge.
                    .lineLimit(1)
                    .font(.system(size: DetailCardLayout.titleFontSize, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)

                Spacer(minLength: 0)

                if let openSettings {
                    HeaderIconButton(
                        systemImage: "gearshape",
                        label: String.localized("Settings…"),
                        action: openSettings
                    )
                    HeaderIconButton(
                        systemImage: "power",
                        label: String.localized("Quit Pulse")
                    ) {
                        NSApplication.shared.terminate(nil)
                    }
                }
            }
            .id("\(usage.id)|\(title ?? "")")
            .transition(Self.headerTransition)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The old one gone almost at once, the new one in straight away.
    ///
    /// No wait before the new one: waiting left the header blank for most of a
    /// sweep down the rail (see `rowTransition`). The overlap that remains is
    /// a few hundredths of a second with the old title nearly gone — not the
    /// two-titles smudge a plain cross-fade drew.
    private static var headerTransition: AnyTransition {
        .asymmetric(
            insertion: .opacity.animation(.easeOut(duration: 0.1)),
            removal: .opacity.animation(.easeOut(duration: 0.06))
        )
    }
}

private extension View {
    /// System tooltip on the reset type. Absent text adds nothing, because
    /// an empty `.help` is still a tooltip.
    @ViewBuilder
    func codexResetTooltip(_ text: String?) -> some View {
        if let text, !text.isEmpty {
            self.help(text)
        } else {
            self
        }
    }

    /// The same explanation, for VoiceOver, on the last-reset block. The
    /// type's tooltip is not in that block's accessibility tree.
    @ViewBuilder
    func codexResetHint(_ text: String?) -> some View {
        if let text, !text.isEmpty {
            self.accessibilityHint(text)
        } else {
            self
        }
    }
}

/// Opens codex-resets.com. It lives on the prediction row, which is always
/// drawn, so a card with no latest announcement still has a way to the site.
/// The old credit sentence is not what this says: the arrow is the control,
/// and VoiceOver hears it as a link that opens Codex Resets.
private struct CodexResetsLink: View {
    @State private var hovering = false

    private static let name = "Codex Resets"

    private var label: String { String.localized("Open \(Self.name)") }

    var body: some View {
        let side = DetailCardLayout.rowTextLineHeight
        Image(systemName: "arrow.up.right")
            .font(.system(size: DetailCardLayout.footnoteFontSize, weight: .semibold))
            .foregroundStyle(.primary.opacity(hovering ? 1 : 0.75))
            .frame(width: side, height: side)
            .contentShape(Rectangle())
            .overlay {
                PointerHand(onHover: { hovering = $0 }) {
                    NSWorkspace.shared.open(CodexResetClient.site)
                }
            }
            .help(label)
            .accessibilityElement()
            .accessibilityLabel(label)
            .accessibilityAddTraits(.isLink)
            .accessibilityAction(.default) {
                NSWorkspace.shared.open(CodexResetClient.site)
            }
    }
}

/// Settings and Quit on the card. `.onHover` is silent on this panel, and a
/// SwiftUI `Button` under a tracking overlay that declines `hitTest` is a
/// hole in the transparent window — the press lands on the page behind.
/// `PointerHand` claims the point and fires the action.
private struct HeaderIconButton: View {
    let systemImage: String
    let label: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        let size = DetailCardLayout.headerIconSize
        Image(systemName: systemImage)
            .font(.system(size: size * 0.9, weight: .medium))
            .foregroundStyle(.primary.opacity(hovering ? 0.95 : 0.55))
            .frame(width: size, height: size)
            .scaleEffect(hovering ? 1.32 : 1)
            .animation(.spring(response: 0.22, dampingFraction: 0.72), value: hovering)
            .frame(width: size + 16, height: size + 16)
            .overlay {
                PointerHand(onHover: { hovering = $0 }, onClick: action)
            }
            .help(label)
            .accessibilityElement()
            .accessibilityLabel(label)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction(named: Text(verbatim: label), action)
    }
}

/// A figure with no percentage behind it, for a provider that reports one.
///
/// No bar: there is nothing to fill it with. A bar drawn at zero beside a real
/// balance would read as an empty account, which is the opposite of what a
/// healthy balance means.
///
/// No explanatory line under it either. It said that the provider reports no
/// limit to measure the figure against, which is true and is also the one
/// thing the card has already made obvious by having nothing else on it.
private struct ValueRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .foregroundStyle(.primary)
                .font(.system(size: DetailCardLayout.rowFontSize, weight: .regular, design: .rounded))

            Spacer(minLength: 0)

            Text(value)
                .font(.system(size: DetailCardLayout.rowFontSize, weight: .medium, design: .rounded))
                .foregroundStyle(.primary.opacity(0.9))
                .lineLimit(1)
                .layoutPriority(1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(value)
    }
}

private struct ProgressMetricRow: View {
    let title: String
    let resetDescription: String
    let progress: Double
    let accent: Color
    let percentageText: String
    let isSpent: Bool
    /// Which way the figure beside the bar is counted, so the word next to it
    /// can agree with it.
    let showsRemaining: Bool
    /// What the rate says about this window, or nil when nothing may be said.
    var burn: BurnRate.Reading?

    /// "88% Used", or "12% Left" when the figure is counted the other way.
    private var figureLabel: String {
        showsRemaining
            ? .localized("\(percentageText) Left")
            : .localized("\(percentageText) Used")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DetailCardLayout.rowInternalSpacing) {
            // The name gets the row to itself. It used to share the line with
            // the reset time, which is fine for "5-hour limit" and falls apart
            // the moment a limit is scoped to something: "5-hour limit ·
            // Claude and GPT" next to "Resets 9月6日 18:14" does not fit in a
            // 250pt card, and it was the *name* that got cut — the half that
            // says which limit this is.
            Text(title)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.tail)
                .font(.system(size: DetailCardLayout.rowFontSize, weight: .regular, design: .rounded))

            ProgressView(value: progress)
                .progressViewStyle(PulseProgressStyle(accent: accent))

            // The two short facts pair off on the line below instead: what is
            // gone, and when it comes back.
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                // **The word has to follow the figure.** `percentageText` is
                // what is *left* when the setting is on, and this said "Used"
                // regardless — so a limit 88% gone read "12% Used" on the card
                // while the rail an inch away said "12% left".
                // Built outside the call rather than as a ternary inside it:
                // `Scripts/localization-keys.py` reads a conditional there as
                // the bare tail — "Left" — which matched an unrelated key and
                // let a missing one through the check that exists to catch it.
                Text(figureLabel)
                    .font(.system(size: DetailCardLayout.rowFontSize, weight: .medium, design: .rounded))
                    .foregroundStyle(accent)
                    // Swapped outright. A cross-fade drew two figures over each
                    // other; a numeric roll left the digits mid-turn — blank —
                    // for most of a sweep down the rail, since every switch
                    // restarts it. A figure that is simply the next one is
                    // readable on every frame.
                    .contentTransition(.identity)

                Spacer(minLength: 0)

                Text(resetDescription)
                    .font(.system(size: DetailCardLayout.rowFontSize, weight: .regular, design: .rounded))
                    .foregroundStyle(.primary.opacity(0.45))
                    .lineLimit(1)
                    .layoutPriority(1)
            }

            burnLine
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(
            showsRemaining
                ? String.localized("\(percentageText) left. \(resetDescription)")
                : String.localized("\(percentageText) used. \(resetDescription)")
        )
    }
}

extension ProgressMetricRow {
    /// How fast it is going, and — only when the evidence carries it — when it
    /// runs out.
    ///
    /// One line, dimmer than the figures above it, because it is the one thing
    /// on this card the provider did not say — though both halves of it are
    /// figures the provider *did* say, subtracted. It is absent far more often than
    /// present, and that is the design rather than a gap: a rate is only
    /// measurable while a limit is actually moving, and the prediction is only
    /// offered when it lands before the reset.
    @ViewBuilder
    var burnLine: some View {
        if let burn, !isSpent {
            Group {
                if let seconds = burn.timeToExhaustion {
                    Text(localized: "Runs out in \(BurnRate.approximate(seconds))")
                        .foregroundStyle(Color.pulseWarning.opacity(0.9))
                } else if burn.exhaustsBeforeReset {
                    // **The verdict without the time.** Beyond the horizon the
                    // hours are not worth stating, but the answer still is —
                    // and this was silent here once, which showed the good news
                    // and hid the bad. A weekly window's exhaustion is nearly
                    // always further out than two hours, so that was most of
                    // the warnings there are.
                    Text(localized: "Won't last the window")
                        .foregroundStyle(Color.pulseWarning.opacity(0.9))
                } else {
                    Text(localized: "Expected to last the window")
                        .foregroundStyle(.primary.opacity(0.45))
                }
            }
            .font(.system(size: DetailCardLayout.rowFontSize, weight: .regular, design: .rounded))
            .lineLimit(1)
        }
    }
}

private struct PulseProgressStyle: ProgressViewStyle {
    let accent: Color

    func makeBody(configuration: Configuration) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.17))

                Capsule()
                    .fill(accent)
                    .frame(width: proxy.size.width * (configuration.fractionCompleted ?? 0))
            }
        }
        .frame(height: DetailCardLayout.progressBarHeight)
    }
}

#Preview("Detail card") {
    UsageDetailCard(
        usage: .unavailable(.claudeCode, reason: .loading),
        edge: .right,
        pointerCenter: DetailCardLayout.estimatedHeight / 2,
        openSettings: {}
    )
    .padding(40)
    .background(.gray)
}
