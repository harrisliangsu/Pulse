import SwiftUI

/// What every coding agent on this Mac has cost, added up.
///
/// **Deliberately not the account card.** That one is per provider, opened
/// from that provider's own pane, and answers "how heavily am I using this".
/// This answers a question no pane could answer before, because its subject is
/// not a provider: *across everything I use, where did the work go.* The
/// figures here are sums the card cannot show and splits it has no room for —
/// a share per agent, a ranking per model — and none of it appears on the
/// rail, which is for what is left rather than for what is gone.
///
/// **Only agents that keep transcripts here.** Money is reconstructed from
/// what the CLIs wrote on this Mac at models.dev's published rates; a provider
/// that reports its own statistics instead gives one token total per model and
/// no money at all, and folding that into a combined cost would put a figure
/// on the total that half of it cannot carry.
struct TokenSpendView: View {
    let summary: SpendSummary
    /// The agent being looked at on its own, or nil for the combined view.
    @Binding var focus: SpendAgent?
    /// That agent's figures, worked out over the same span. Built by the same
    /// function as the combined one, from a dictionary of one — so the split
    /// and the whole cannot drift apart or be counted differently.
    let focused: SpendSummary
    @Binding var span: SpendSpan
    let isLoading: Bool
    let refresh: () -> Void

    /// Which column the day table is sorted by. Its own state rather than a
    /// setting: it is a way of reading the table in front of you, not a
    /// preference about the app.
    @State private var sort = DayColumn.date
    @State private var ascending = false
    /// How many rows a page holds, and which page is on screen. Ten by
    /// default: a table long enough to scroll past is a table nobody reads to
    /// the end of, and the span picker above is the coarse control.
    @State private var pageSize = 10
    @State private var page = 0
    /// The session list pages separately: it is hundreds of rows where the day
    /// table is tens, and a shared page number would jump both at once.
    @State private var sessionPageSize = 10
    @State private var sessionPage = 0

    /// Enough to see where the work goes without turning the pane into a
    /// table. The rest is in the ledger and nobody reads a fortieth row.
    private static let modelLimit = 8

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            if let focus { agentHeader(focus) }

            SettingsGroup(String.localized("Span")) {
                SettingsRow(
                    String.localized("Counting"),
                    subtitle: String.localized("Read from this Mac's transcripts, priced at models.dev's published rates.")
                ) {
                    HStack(spacing: 8) {
                        Picker("", selection: $span) {
                            ForEach(SpendSpan.allCases) { span in
                                Text(span.title).tag(span)
                            }
                        }
                        .labelsHidden()
                        .frame(maxWidth: SettingsLayout.controlWidth, alignment: .trailing)

                        Button(String.localized("Rescan")) { refresh() }
                            .disabled(isLoading)
                    }
                }
            }

            // The span picker stays in both views, so narrowing the window
            // while looking at one agent does not throw the reader back out.
            if let focus {
                if focused.isEmpty {
                    nothingForAgent(focus)
                } else {
                    total(focused)
                    kinds(focused)
                    streaks(focused)
                    if span != .today { hourly(focused) }
                    if span != .today { daily(focused) }
                    if focused.months.count > 1 { monthly(focused) }
                    if !focused.models.isEmpty { models(focused) }
                    if !focused.projects.isEmpty { projects(focused) }
                    if !focused.sessions.isEmpty { sessions(focused) }
                    footnote(focused)
                }
            } else if summary.isEmpty {
                empty
            } else {
                total(summary)
                kinds(summary)
                streaks(summary)
                if span != .today { hourly(summary) }
                if span != .today { daily(summary) }
                if summary.months.count > 1 { monthly(summary) }
                agents
                if summary.models.count > 1 { models(summary) }
                if !summary.projects.isEmpty { projects(summary) }
                if !summary.sessions.isEmpty { sessions(summary) }
                footnote(summary)
            }
        }
    }

    // MARK: - One agent

    /// The way back, and what is being looked at. A row rather than a bare
    /// button: this pane has no navigation stack of its own, so the only thing
    /// saying "you have gone one level in" is on screen here.
    private func agentHeader(_ agent: SpendAgent) -> some View {
        Button {
            focus = nil
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 11, weight: .semibold))
                Text(localized: "All agents")
                    .font(.system(size: 12))
                Text(verbatim: "·")
                    .foregroundStyle(.secondary)
                if let icon = agent.iconProvider { LobeIconView(provider: icon, size: 13) }
                Text(agent.displayName)
                    .font(.system(size: 12, weight: .medium))
            }
        }
        .buttonStyle(.plain)
        .padding(.leading, 4)
    }

    private func nothingForAgent(_ agent: SpendAgent) -> some View {
        SettingsGroup(agent.displayName) {
            SettingsRow(
                String.localized("Nothing in this span"),
                subtitle: String.localized("Try a longer span, or rescan.")
            ) {
                EmptyView()
            }
        }
    }

    // MARK: - Nothing to show

    private var empty: some View {
        SettingsGroup(String.localized("Total")) {
            SettingsRow(
                isLoading ? String.localized("Reading…") : String.localized("Nothing yet"),
                subtitle: isLoading
                    ? String.localized("Going through this Mac's transcripts.")
                    // Says which agents, because the answer "nothing" is only
                    // true of the two that leave transcripts — somebody whose
                    // work is all in a third would otherwise read this as a
                    // fault.
                    : String.localized("Claude Code and Codex write the logs this is counted from. Nothing from either has been found on this Mac.")
            ) {
                EmptyView()
            }
        }
    }

    // MARK: - The figure

    private func total(_ summary: SpendSummary) -> some View {
        SettingsGroup(focus == nil ? String.localized("Total") : String.localized("This agent")) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(Self.money(summary.cost))
                        .font(.system(size: 28, weight: .semibold))
                        .monospacedDigit()

                    Text(String.localized("\(TokenCount.short(summary.tokens)) tokens"))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                // **A day is not one bar.** Over any other span the bars are
                // days; over today there is only one of those, and the shape
                // worth seeing is the hours it was spread across.
                if span == .today {
                    HourProfile(hours: summary.hours)
                        .frame(height: 78)
                } else if summary.days.count > 1 {
                    SpendChart(days: summary.days)
                        .frame(height: 78)
                }

                HStack(spacing: 16) {
                    if span == .today {
                        caption(
                            String.localized("Active hours"),
                            String.localized("\("\(summary.activeHours)") of \("24")")
                        )
                        if let hour = summary.peakHour {
                            // Its own label: "busiest" is a day over every
                            // other span and an hour over this one, and
                            // Chinese names each of those outright.
                            caption(
                                String.localized("Busiest hour"),
                                "\(Self.hour(hour)) · \(TokenCount.short(summary.hours[hour] ?? 0))"
                            )
                        }
                    } else {
                        // Days with work on them, not days in the span: the
                        // second is the picker's own setting read back.
                        caption(
                            String.localized("Active days"),
                            String.localized("\("\(summary.activeDays)") of \("\(max(summary.days.count, 1))")")
                        )

                        if let busiest = summary.busiestDay, busiest.tokens > 0 {
                            caption(
                                String.localized("Busiest"),
                                "\(Self.shortDate(busiest.date)) · \(TokenCount.short(busiest.tokens))"
                            )
                        }
                    }

                    if focus == nil, summary.agents.count > 1 {
                        caption(String.localized("Agents"), "\(summary.agents.count)")
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
    }

    // MARK: - What kind of token

    /// Fresh input, cache written, cache read, output.
    ///
    /// **The split is the point, not the total.** These four are priced an
    /// order of magnitude apart — a cache read costs a tenth of fresh input on
    /// most price lists — so a bill that looks surprising next to a token
    /// count is usually explained here and nowhere else.
    private func kinds(_ summary: SpendSummary) -> some View {
        let tally = summary.tally
        let total = max(tally.total, 1)

        return SettingsGroup(String.localized("By kind")) {
            VStack(spacing: 0) {
                ForEach(Array(Self.kindRows(tally).enumerated()), id: \.offset) { index, row in
                    if index > 0 { SettingsRowDivider() }
                    SettingsRow(row.label, subtitle: row.note) {
                        HStack(spacing: 10) {
                            ShareBar(share: Double(row.tokens) / Double(total))
                                .frame(width: 64, height: 6)

                            Text(String.localized("\(TokenCount.short(row.tokens)) tokens"))
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                                // One line, always. Grouped by ten thousands
                                // these read "1246万 tokens", which is wider
                                // than the English it was measured against and
                                // was wrapping under its own bar.
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                        }
                    }
                }
            }
        }
    }

    private static func kindRows(_ tally: TokenTally) -> [(label: String, note: String, tokens: Int)] {
        [
            (String.localized("Input"), String.localized("Sent fresh, not served from the cache."), tally.input),
            (String.localized("Cache write"), String.localized("Put into the prompt cache to be re-used."), tally.cacheWrite),
            (String.localized("Cache read"), String.localized("Served from the cache, and priced far lower."), tally.cacheRead),
            (String.localized("Output"), String.localized("Written back by the model."), tally.output),
        ]
    }

    // MARK: - Day by day

    /// Every day in the span, with the split and the money beside it.
    ///
    /// **The rows are days with work on them**, not every day in the span: the
    /// chart above is the one that has to keep its gaps to stay a calendar,
    /// and a table of empty rows is a table you have to read past.
    private func daily(_ summary: SpendSummary) -> some View {
        let rows = SpendSummary.sorted(summary.days.filter { $0.tokens > 0 }, by: sort, ascending: ascending)
        let pages = max((rows.count + pageSize - 1) / pageSize, 1)
        // Clamped rather than trusted: the span and the sort can both shorten
        // the table under a page that is already on screen.
        let current = min(max(page, 0), pages - 1)
        let shown = Array(rows.dropFirst(current * pageSize).prefix(pageSize))

        return SettingsGroup(String.localized("Day by day")) {
            VStack(spacing: 0) {
                Grid(alignment: .trailing, horizontalSpacing: 10, verticalSpacing: 0) {
                    GridRow {
                        ForEach(DayColumn.allCases) { column in
                            header(column)
                        }
                    }
                    .padding(.vertical, 8)

                    ForEach(shown) { day in
                        Divider().gridCellUnsizedAxes(.horizontal)
                        GridRow {
                            Text(Self.tableDate(day.date))
                                .frame(maxWidth: .infinity, alignment: .leading)
                            cell(day.tally.input)
                            cell(day.tally.output)
                            cell(day.tally.cacheRead)
                            cell(day.tally.cacheWrite)
                            cell(day.tokens)
                            Text(Self.money(day.cost))
                                .frame(maxWidth: .infinity, alignment: .trailing)
                        }
                        .font(.system(size: 11))
                        .monospacedDigit()
                        .padding(.vertical, 5)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)

                if rows.count > Self.pageSizes.first ?? 10 {
                    SettingsRowDivider()
                    pager(rows: rows.count, pages: pages, current: current)
                }
            }
        }
    }

    static let pageSizes = [10, 20, 30, 50]

    private func pager(rows: Int, pages: Int, current: Int) -> some View {
        HStack(spacing: 10) {
            Picker("", selection: $pageSize) {
                ForEach(Self.pageSizes, id: \.self) { size in
                    // Interpolated as a string: an `Int` in a key produces
                    // `%lld`, which will not match a `%@` entry.
                    Text(String.localized("\("\(size)") per page")).tag(size)
                }
            }
            .labelsHidden()
            .fixedSize()
            // A shorter page does not mean the same rows: going back to the
            // first one is the only answer that is the same every time.
            .onChange(of: pageSize) { _, _ in page = 0 }

            Spacer(minLength: 8)

            Text(String.localized("\("\(current * pageSize + 1)")–\("\(min((current + 1) * pageSize, rows))") of \("\(rows)")"))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .monospacedDigit()

            Button {
                page = max(current - 1, 0)
            } label: {
                Image(systemName: "chevron.left")
            }
            .disabled(current == 0)

            Button {
                page = min(current + 1, pages - 1)
            } label: {
                Image(systemName: "chevron.right")
            }
            .disabled(current >= pages - 1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    /// Clicking a column sorts by it; clicking the sorted one turns it around.
    private func header(_ column: DayColumn) -> some View {
        Button {
            page = 0
            if sort == column {
                ascending.toggle()
            } else {
                sort = column
                // A new column starts at the end people look at first: the
                // most recent day, or the largest figure.
                ascending = false
            }
        } label: {
            HStack(spacing: 2) {
                Text(column.title)
                if sort == column {
                    Image(systemName: ascending ? "chevron.up" : "chevron.down")
                        .font(.system(size: 7, weight: .bold))
                }
            }
            .font(.system(size: 10, weight: sort == column ? .semibold : .regular))
            .foregroundStyle(sort == column ? .primary : .secondary)
            .frame(maxWidth: .infinity, alignment: column == .date ? .leading : .trailing)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private func cell(_ tokens: Int) -> some View {
        Text(tokens > 0 ? TokenCount.short(tokens) : "—")
            .foregroundStyle(tokens > 0 ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
            .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private static func tableDate(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day().locale(LocalizationSource.locale))
    }

    // MARK: - When

    /// The hours of the day, as a profile.
    ///
    /// Read off the ledger's quarter-hour buckets, which are the only place
    /// the time of day survives — a day has already thrown it away.
    private func hourly(_ summary: SpendSummary) -> some View {
        SettingsGroup(String.localized("By hour")) {
            HourProfile(hours: summary.hours)
                .frame(height: 66)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
        }
    }

    /// Whole months, for the spans long enough to have more than one.
    private func monthly(_ summary: SpendSummary) -> some View {
        SettingsGroup(String.localized("By month")) {
            VStack(spacing: 0) {
                ForEach(Array(summary.months.reversed().enumerated()), id: \.element.id) { index, month in
                    if index > 0 { SettingsRowDivider() }
                    SettingsRow(
                        month.date.formatted(.dateTime.year().month(.wide).locale(LocalizationSource.locale)),
                        subtitle: String.localized("\(TokenCount.short(month.tokens)) tokens")
                    ) {
                        Text(Self.money(month.cost))
                            .font(.system(size: 12))
                            .monospacedDigit()
                    }
                }
            }
        }
    }

    // MARK: - The pattern

    /// Which days, rather than how much — and the habits that follow from it.
    ///
    /// The bar chart above answers "how heavy was each day"; this answers
    /// "which days, and how consistently". Same data, and the second question
    /// is not readable off the first: a run of light days and a run of gaps
    /// look alike in a bar chart and are opposites here.
    /// How consistently, and when.
    private func streaks(_ summary: SpendSummary) -> some View {
        SettingsGroup(String.localized("Pattern")) {
            HStack(spacing: 16) {
                caption(
                    String.localized("Current streak"),
                    String.localized("\("\(summary.currentStreak)") days")
                )
                caption(
                    String.localized("Longest streak"),
                    String.localized("\("\(summary.longestStreak)") days")
                )
                if let hour = summary.peakHour {
                    caption(String.localized("Peak hour"), Self.hour(hour))
                }
                if let model = summary.models.first {
                    caption(String.localized("Favourite model"), model.name)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
    }

    /// The hour, in the words each language actually uses for one.
    ///
    /// **Not `.dateTime.hour()`.** It is locale-aware and still wrong here: for
    /// Chinese it produces the written "10时" where an hour spoken aloud is
    /// "10 点". A key per language says it the way that language says it, and
    /// the number is interpolated as a string so the entry stays `%@`.
    static func hour(_ hour: Int) -> String {
        .localized("\("\(hour)") o'clock")
    }

    private func caption(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 12))
                .monospacedDigit()
        }
    }

    // MARK: - Where it went

    private var agents: some View {
        SettingsGroup(String.localized("By agent")) {
            ForEach(Array(summary.agents.enumerated()), id: \.element.id) { index, agent in
                if index > 0 { SettingsRowDivider() }

                // The whole row opens the agent, not a disclosure arrow at
                // the end of it: the row is what the reader is looking at, and
                // a target the width of a chevron is a target most people miss.
                Button {
                    focus = agent.agent
                } label: {
                    SettingsRow(
                        agent.agent.displayName,
                        subtitle: String.localized("\(TokenCount.short(agent.tokens)) tokens"),
                        icon: agent.agent.iconProvider
                    ) {
                        HStack(spacing: 10) {
                            ShareBar(share: summary.tokens > 0
                                ? Double(agent.tokens) / Double(summary.tokens)
                                : 0)
                                .frame(width: 64, height: 6)

                            Text(Self.money(agent.cost))
                                .font(.system(size: 12))
                                .monospacedDigit()
                                .frame(width: 76, alignment: .trailing)

                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    // A button's label does not take clicks where the row's
                    // own background is transparent, which is most of it.
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func models(_ summary: SpendSummary) -> some View {
        SettingsGroup(String.localized("By model")) {
            ForEach(Array(summary.models.prefix(Self.modelLimit).enumerated()), id: \.element.id) { index, model in
                if index > 0 { SettingsRowDivider() }

                SettingsRow(
                    model.name,
                    // Which agents sent work to it — one model can belong to
                    // two, and the row would otherwise look like it belongs to
                    // whichever is listed first above.
                    subtitle: model.agents.map(\.displayName).joined(separator: " · ")
                ) {
                    HStack(spacing: 10) {
                        ShareBar(share: model.share)
                            .frame(width: 64, height: 6)

                        Text(String.localized("\(TokenCount.short(model.tokens)) tokens"))
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .frame(width: 76, alignment: .trailing)
                    }
                }
            }
        }
    }

    // MARK: - Where the work happened

    /// One row a working directory.
    ///
    /// **Claude Code only.** It keeps a directory per project; Codex files sit
    /// under a date and carry no directory, so its sessions are counted in
    /// everything above and are simply not on this list — which the caption
    /// says, rather than leaving a reader to wonder where half the money went.
    private func projects(_ summary: SpendSummary) -> some View {
        let total = max(summary.projects.reduce(0) { $0 + $1.tokens }, 1)

        return SettingsGroup(String.localized("By project")) {
            VStack(spacing: 0) {
                ForEach(Array(summary.projects.prefix(Self.modelLimit).enumerated()), id: \.element.id) { index, project in
                    if index > 0 { SettingsRowDivider() }

                    SettingsRow(
                        project.name,
                        subtitle: String.localized("\("\(project.sessions)") sessions · last used \(Self.shortDate(project.lastUsed))")
                    ) {
                        HStack(spacing: 10) {
                            ShareBar(share: Double(project.tokens) / Double(total))
                                .frame(width: 64, height: 6)

                            Text(Self.money(project.cost))
                                .font(.system(size: 12))
                                .monospacedDigit()
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                        }
                    }
                }
            }
        }
    }

    /// One row a transcript, newest first.
    private func sessions(_ summary: SpendSummary) -> some View {
        let rows = summary.sessions
        let pages = max((rows.count + sessionPageSize - 1) / sessionPageSize, 1)
        let current = min(max(sessionPage, 0), pages - 1)
        let shown = Array(rows.dropFirst(current * sessionPageSize).prefix(sessionPageSize))

        return SettingsGroup(String.localized("By session")) {
            VStack(spacing: 0) {
                ForEach(Array(shown.enumerated()), id: \.element.id) { index, row in
                    if index > 0 { SettingsRowDivider() }

                    SettingsRow(
                        // What the conversation was called. The directory is
                        // the fallback and the file's own name the last
                        // resort — a uuid tells the reader nothing, but it is
                        // at least what the session is called.
                        row.session.title ?? row.session.project ?? row.session.name,
                        subtitle: Self.sessionSubtitle(row),
                        icon: row.agent.iconProvider
                    ) {
                        HStack(spacing: 10) {
                            Text(String.localized("\(TokenCount.short(row.session.tokens)) tokens"))
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)

                            Text(Self.money(row.session.cost))
                                .font(.system(size: 12))
                                .monospacedDigit()
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                        }
                    }
                }

                if rows.count > Self.pageSizes.first ?? 10 {
                    SettingsRowDivider()
                    HStack(spacing: 10) {
                        Picker("", selection: $sessionPageSize) {
                            ForEach(Self.pageSizes, id: \.self) { size in
                                Text(String.localized("\("\(size)") per page")).tag(size)
                            }
                        }
                        .labelsHidden()
                        .fixedSize()
                        .onChange(of: sessionPageSize) { _, _ in sessionPage = 0 }

                        Spacer(minLength: 8)

                        Text(String.localized("\("\(current * sessionPageSize + 1)")–\("\(min((current + 1) * sessionPageSize, rows.count))") of \("\(rows.count)")"))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()

                        Button {
                            sessionPage = max(current - 1, 0)
                        } label: {
                            Image(systemName: "chevron.left")
                        }
                        .disabled(current == 0)

                        Button {
                            sessionPage = min(current + 1, pages - 1)
                        } label: {
                            Image(systemName: "chevron.right")
                        }
                        .disabled(current >= pages - 1)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }
            }
        }
    }

    /// When it ran and for how long, and the file's own name where the row's
    /// title is already the directory.
    private static func sessionSubtitle(_ row: SpendSummary.Session) -> String {
        let when = row.session.end.formatted(
            .dateTime.month(.abbreviated).day().hour().minute().locale(LocalizationSource.locale)
        )
        // The directory belongs here once the title has taken the row's own
        // line — it is what tells two conversations about the same thing
        // apart.
        guard let project = row.session.project, row.session.title != nil else { return when }
        return "\(when) · \(project)"
    }

    // MARK: - What the figures are not

    private func footnote(_ summary: SpendSummary) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            // The same warning the card carries, and for the same reason: it
            // would be easy to read this as a bill, and it is not one.
            Text(localized: "Counted from this Mac's own logs and priced at the published API rates from models.dev. Your plans are subscriptions, so this is what the same work would cost through the API — not what you were charged. Work done on another machine is not here.")

            if !summary.unpricedModels.isEmpty {
                // **Counted, not listed.** Naming them was fine at two and is
                // a paragraph at thirty — and the names are the least useful
                // part of the sentence, which is that some tokens have no
                // price. The list stays a hover away.
                Text(String.localized("\("\(summary.unpricedModels.count)") models have no published price, so those tokens are counted but not costed."))
                    .help(summary.unpricedModels.joined(separator: ", "))
            }

            // The money is per day and the tokens are per model, so there is
            // no per-model cost to add up — and a day's blended rate applied
            // to one model would be a number nobody reported.
            Text(localized: "The model list is tokens only: the logs price a day's work, not each model's share of it.")
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 4)
    }

    // MARK: - Formatting

    private static func money(_ amount: Double) -> String {
        // models.dev publishes in dollars, so the figure is in dollars whatever
        // the reader's own currency is.
        amount.formatted(
            .currency(code: "USD")
                .precision(.fractionLength(amount >= 1000 ? 0 : 2))
                .locale(LocalizationSource.locale)
        )
    }

    private static func shortDate(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day().locale(LocalizationSource.locale))
    }
}

/// How far back the pane counts.
///
/// Not the card's fixed month: the question here is "where has it all gone",
/// which is asked over a week and over a year, and the answer changes shape at
/// each end.
enum SpendSpan: String, CaseIterable, Identifiable, Sendable {
    case today
    case week
    case month
    case quarter
    case all

    static let `default` = SpendSpan.month

    var id: String { rawValue }

    /// Nil counts everything the transcripts go back to.
    var days: Int? {
        switch self {
        // One day, which is the day in progress rather than the last
        // twenty-four hours: the ledger's rows are local midnights.
        case .today: 1
        case .week: 7
        case .month: 30
        case .quarter: 90
        case .all: nil
        }
    }

    var title: String {
        switch self {
        // Interpolate a string, never the integer: an `Int` in a localization
        // key produces `%lld`, which will not match a `%@` entry.
        case .today: .localized("Today")
        case .week: .localized("Last \("7") days")
        case .month: .localized("Last \("30") days")
        case .quarter: .localized("Last \("90") days")
        case .all: .localized("All time")
        }
    }
}

/// One agent's or one model's share of the whole, as a bar.
///
/// A bar rather than a percentage because the list is read by comparing rows,
/// and a column of percentages has to be compared digit by digit.
private struct ShareBar: View {
    let share: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule()
                    .fill(.tint)
                    // A share too small to see is still a share: anything at
                    // all keeps a visible stub, the same rule the ring follows.
                    .frame(width: max(proxy.size.width * min(max(share, 0), 1), share > 0 ? 3 : 0))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(Int((share * 100).rounded()))%")
    }
}

/// Tokens per day across every agent.
///
/// Its own view rather than the card's `DailyTokensChart`: that one takes
/// `LedgerDay`, which belongs to one provider, and this bar is several agents'
/// work on one day.
private struct SpendChart: View {
    let days: [SpendSummary.Day]

    /// **A bar is never wider than this.** Dividing the pane by the number of
    /// days and using the result is right at ninety bars and absurd at seven:
    /// a week filled the width with columns 160pt across and 64pt tall, which
    /// reads as a row of blocks rather than as a chart. Each day still gets an
    /// equal slot — that is what keeps the spacing even and the dates
    /// honest — and the bar sits in the middle of its own.
    private static let maxBarWidth: CGFloat = 22

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            GeometryReader { proxy in
                let peak = max(days.map(\.tokens).max() ?? 1, 1)
                let slot = proxy.size.width / CGFloat(max(days.count, 1))
                let width = max(min(slot * 0.72, Self.maxBarWidth), 1)

                HStack(alignment: .bottom, spacing: 0) {
                    ForEach(days) { day in
                        RoundedRectangle(cornerRadius: min(width, 5) / 2, style: .continuous)
                            .fill(day.tokens > 0 ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary))
                            // A day with any work at all keeps a visible stub,
                            // so a quiet day reads as quiet rather than as
                            // missing.
                            .frame(
                                width: width,
                                height: day.tokens > 0
                                    ? max((proxy.size.height - 1) * CGFloat(day.tokens) / CGFloat(peak), 3)
                                    : 2
                            )
                            .frame(width: slot, alignment: .center)
                            .help(Self.tooltip(day))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                // The line the bars stand on. Without it the short days float
                // and the whole thing reads as blocks rather than a chart.
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(.quaternary)
                        .frame(height: 1)
                }
            }

            // Only the ends. A label under every bar is unreadable at ninety
            // of them and unnecessary at seven — the tooltip has the rest.
            if let first = days.first, let last = days.last, days.count > 1 {
                HStack {
                    Text(Self.shortDate(first.date))
                    Spacer(minLength: 0)
                    Text(Self.shortDate(last.date))
                }
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .monospacedDigit()
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String.localized("Tokens per day"))
    }

    private static func shortDate(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day().locale(LocalizationSource.locale))
    }

    private static func tooltip(_ day: SpendSummary.Day) -> String {
        "\(shortDate(day.date)) · \(TokenCount.short(day.tokens))"
    }
}

/// The days, as a calendar of weeks.
///
/// One column a week, one row a weekday, shaded by how much went through —
/// the shape GitHub made legible and the one tokscale borrows. It answers a
/// different question from the bars above: not *how much* on each day, but
/// *which* days, and whether they run together.
///
/// **Bucketed into four shades rather than scaled continuously.** A linear
/// ramp against the busiest day makes every ordinary day the palest step and
/// the calendar reads as empty; the buckets are cut on quarters of the peak,
/// which keeps an ordinary week visible next to an exceptional one.

/// Tokens by hour of the local day.
///
/// Its own view because it is drawn in two places for two reasons: as the
/// whole shape of today, where a single daily bar says nothing, and as the
/// profile of a longer span, where it answers "when do I work" rather than
/// "how much did today hold".
private struct HourProfile: View {
    let hours: [Int: Int]

    var body: some View {
        let peak = max(hours.values.max() ?? 1, 1)

        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { proxy in
                HStack(alignment: .bottom, spacing: 2) {
                    ForEach(0..<24, id: \.self) { hour in
                        let tokens = hours[hour] ?? 0
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(tokens > 0 ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary))
                            // An hour with any work at all keeps a visible
                            // stub, so a quiet hour reads as quiet rather than
                            // as missing.
                            .frame(
                                maxWidth: .infinity,
                                maxHeight: tokens > 0
                                    ? max((proxy.size.height - 1) * CGFloat(tokens) / CGFloat(peak), 3)
                                    : 2
                            )
                            .help("\(Self.hour(hour)) · \(TokenCount.short(tokens))")
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(.quaternary)
                        .frame(height: 1)
                }
            }

            HStack {
                Text(Self.hour(0))
                Spacer(minLength: 0)
                Text(Self.hour(12))
                Spacer(minLength: 0)
                Text(Self.hour(23))
            }
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
            .monospacedDigit()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String.localized("Tokens per hour"))
    }

    private static func hour(_ hour: Int) -> String { TokenSpendView.hour(hour) }
}

/// The day table's columns, which are also what it can be sorted by.
enum DayColumn: String, CaseIterable, Identifiable, Sendable {
    case date
    case input
    case output
    case cacheRead
    case cacheWrite
    case total
    case cost

    var id: String { rawValue }

    var title: String {
        switch self {
        case .date: .localized("Date")
        case .input: .localized("Input")
        case .output: .localized("Output")
        // Short, because seven columns of Chinese headings in a settings pane
        // is a table that wraps.
        case .cacheRead: .localized("C. read")
        case .cacheWrite: .localized("C. write")
        case .total: .localized("Total")
        case .cost: .localized("Cost")
        }
    }
}
