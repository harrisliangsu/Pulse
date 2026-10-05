// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import SwiftUI

// The numbered cards of a recap, one idea each. Shared by month and year; the
// cards that only make sense for one are in `RecapYearViews.swift`.

/// A thin rule across the card, in ink or in the paler grey.
struct RecapRule: View {
    var strong = false
    var body: some View {
        Rectangle()
            .fill(strong ? RecapColor.ink : RecapColor.rule)
            .frame(height: strong ? 2 : 1)
    }
}

/// The period's total, huge, on a lime bar: shared by the calendar cards.
struct RecapTotalHero: View {
    let deck: RecapDeck
    var numberSize: CGFloat = 270
    var unitSize: CGFloat = 130

    var body: some View {
        VStack(alignment: .leading, spacing: 38) {
            Text(deck.workedThroughLine)
                .font(.recap(34))
                .foregroundStyle(Color(recap: 0x55554F))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .bottom, spacing: 30) {
                RecapFigureText(figure: RecapFormat.tokens(deck.recap.tokens), numberSize: numberSize, unitSize: unitSize,
                                unitGap: 14, trimmed: true)
                    .background(alignment: .bottom) {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(RecapColor.lime)
                            .frame(height: numberSize * 0.37)
                            .padding(.bottom, numberSize * 0.0175)
                            .padding(.leading, -8)
                            .padding(.trailing, -14)
                    }
                Text(verbatim: "TOKENS")
                    .font(.recap(24, .regular, mono: true))
                    .tracking(1.9)
                    .foregroundStyle(Color(recap: 0x55554F))
                    .padding(.bottom, 6)
                Spacer(minLength: 0)
            }
        }
    }
}

// MARK: - Opener

/// The month number or the year, a line, and the agents that did the work.
struct RecapOpenerView: View {
    let deck: RecapDeck

    private var recap: Recap { deck.recap }

    var body: some View {
        RecapStoryPage(page: deck.page(of: .opener)) {
            big.padding(.top, 48)
            headline.padding(.top, 44)
            Spacer(minLength: 24)
            roster
        }
    }

    @ViewBuilder
    private var big: some View {
        switch recap.period {
        case .month(let year, let month):
            HStack(alignment: .bottom, spacing: 28) {
                Text(verbatim: String(format: "%02d", month))
                    .font(.recap(470, .bold))
                    .tracking(-470 * 0.07)
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.top, -470 * RecapFigureText.ascenderRoom)
                    .padding(.bottom, -470 * RecapFigureText.descenderRoom)
                VStack(alignment: .leading, spacing: 12) {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(RecapColor.lime)
                        .frame(width: 72, height: 72)
                    Text(verbatim: "\(year)")
                        .font(.recap(22, .regular, mono: true))
                        .foregroundStyle(Color(recap: 0x55554F))
                }
                .padding(.bottom, 4)
                Spacer(minLength: 0)
            }
        case .year(let year):
            HStack(alignment: .bottom, spacing: 28) {
                Text(verbatim: "\(year)")
                    .font(.recap(310, .bold))
                    .tracking(-310 * 0.07)
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.top, -310 * RecapFigureText.ascenderRoom)
                    .padding(.bottom, -310 * RecapFigureText.descenderRoom)
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(RecapColor.lime)
                    .frame(width: 72, height: 72)
                    .padding(.bottom, 4)
                Spacer(minLength: 0)
            }
        }
    }

    private var headline: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(String.localized("In \(deck.periodName),"))
            // The count is the roster below it, so the line says how many
            // rather than a negative ("didn't code alone") that read oddly in
            // Chinese. One tool gets its own sentence: no plural to agree.
            if recap.agents.count == 1 {
                Text(localized: "One AI tool coded with you.")
            } else {
                Text(String.localized("\("\(recap.agents.count)") AI tools coded with you."))
            }
        }
        .font(.recap(76, .black))
        .tracking(-0.76)
        .lineSpacing(6)
        .lineLimit(3)
        .minimumScaleFactor(0.5)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var roster: some View {
        let agents = Array(recap.agents.prefix(5))
        let top = max(agents.first?.share ?? 0, 0.0001)
        // Five rows fill the page; fewer leave a hole under the headline, so
        // each missing row's height is shared out between the ones there are.
        let room = CGFloat(max(0, 5 - agents.count)) * 16
        return VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(localized: "Worked beside you")
                    .font(.recap(22, .bold))
                Spacer()
                Text(localized: "Days used · token share")
                    .font(.recap(18))
                    .foregroundStyle(RecapColor.tertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .padding(.bottom, 12)
            ForEach(agents.indices, id: \.self) { index in
                let agent = agents[index]
                let first = index == 0
                RecapRule()
                VStack(spacing: 14) {
                    HStack(alignment: .firstTextBaseline, spacing: 0) {
                        Text(verbatim: agent.agent.displayName)
                            .font(.recap(first ? 64 : 48, first ? .bold : .medium))
                            .tracking(first ? -1.3 : -1)
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                        Spacer(minLength: 12)
                        Text(String.localized("\("\(agent.activeDays)") days"))
                            .font(.recap(22))
                            .foregroundStyle(Color(recap: 0x55554F))
                            .lineLimit(1)
                            .frame(width: 150, alignment: .trailing)
                        Text(verbatim: RecapFormat.percent(agent.share))
                            .font(.recap(20, .regular, mono: true))
                            .foregroundStyle(first ? RecapColor.ink : RecapColor.tertiary)
                            .padding(.horizontal, first ? 8 : 0)
                            .padding(.vertical, first ? 2 : 0)
                            .background(first ? RecapColor.lime : .clear)
                            .frame(width: 90, alignment: .trailing)
                    }
                    GeometryReader { proxy in
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(first ? RecapColor.lime : RecapColor.ink)
                            .frame(width: max(8, proxy.size.width * agent.share / top), height: first ? 12 : 8)
                    }
                    .frame(height: first ? 12 : 8)
                }
                .padding(.top, 26 + room)
                .padding(.bottom, 28 + room)
            }
            RecapRule(strong: true)
            HStack {
                Text(localized: "Turn the page to see what you made together")
                    .font(.recap(24))
                    .foregroundStyle(Color(recap: 0x55554F))
                    .lineLimit(2)
                Spacer(minLength: 16)
                Image(systemName: "arrow.right")
                    .font(.system(size: 34, weight: .regular))
            }
            .padding(.top, 24)
        }
    }
}

// MARK: - Calendar

/// The month, every day a cell. The total above it; the busiest day in ink.
struct RecapCalendarView: View {
    let deck: RecapDeck

    private var recap: Recap { deck.recap }

    var body: some View {
        let calendar = RecapFormat.calendar()
        let grid = RecapMonthGrid(monthStart: recap.start, days: recap.days, calendar: calendar)
        let maximum = recap.days.map(\.tokens).max() ?? 0
        let busiest = recap.busiestDay?.date
        let cellHeight: CGFloat = grid.rows > 5 ? 136 : 168
        RecapStoryPage(page: deck.page(of: .calendar)) {
            RecapTotalHero(deck: deck).padding(.top, 52)
            RecapRule(strong: true).padding(.top, 58)
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: RecapFormat.monthYear(recap.start))
                    .font(.recap(26, .bold))
                Spacer()
                Text(localized: "Darker days used more")
                    .font(.recap(18))
                    .foregroundStyle(RecapColor.tertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .padding(.top, 22)
            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    ForEach(Array(RecapFormat.weekdayHeadings().enumerated()), id: \.offset) { _, heading in
                        Text(heading)
                            .font(.recap(18))
                            .foregroundStyle(RecapColor.tertiary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .frame(maxWidth: .infinity)
                    }
                }
                ForEach(0..<grid.rows, id: \.self) { row in
                    HStack(spacing: 10) {
                        ForEach(0..<7, id: \.self) { column in
                            cell(grid.cells[row * 7 + column], maximum: maximum, busiest: busiest, height: cellHeight)
                        }
                    }
                }
            }
            .padding(.top, 14)
            Spacer(minLength: 20)
            RecapRule(strong: true)
            RecapDayCaption(deck: deck).padding(.top, 28)
        }
    }

    @ViewBuilder
    private func cell(_ day: Recap.Day?, maximum: Int, busiest busiestDate: Date?, height: CGFloat) -> some View {
        if let day {
            let number = recap.calendar.component(.day, from: day.date)
            let quiet = day.tokens == 0
            // Only the one day `Recap.busiestDay` names, not every tie.
            let busiest = !quiet && day.date == busiestDate
            let foreground = busiest ? RecapColor.paper : (quiet ? RecapColor.faint : RecapColor.ink)
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(busiest ? RecapColor.ink : (quiet ? Color.clear : RecapHeat.color(tokens: day.tokens, maximum: maximum)))
                if quiet {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color(recap: 0xCFCFC8), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                }
                VStack(alignment: .leading) {
                    Text(verbatim: "\(number)")
                        .font(.recap(22, .semibold))
                        .foregroundStyle(busiest ? RecapColor.lime : foreground)
                    Spacer(minLength: 0)
                    Group {
                        if quiet {
                            Text(localized: "Rest")
                        } else {
                            Text(verbatim: RecapFormat.tokens(day.tokens).text)
                        }
                    }
                    .font(.recap(14, .regular, mono: true))
                    .foregroundStyle(busiest ? RecapColor.lime : foreground.opacity(0.72))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                }
                .padding(EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 10))
            }
            .frame(maxWidth: .infinity)
            .frame(height: height)
        } else {
            Color.clear.frame(maxWidth: .infinity).frame(height: height)
        }
    }

}

// MARK: - Timetable

/// The hour you work hardest, and the day as 24 rows.
struct RecapTimetableView: View {
    let deck: RecapDeck

    private var recap: Recap { deck.recap }

    var body: some View {
        let hours = recap.hours ?? []
        let peak = recap.peakHour ?? 0
        let maximum = max(hours.max() ?? 1, 1)
        RecapStoryPage(page: deck.page(of: .timetable)) {
            HStack(alignment: .bottom) {
                RecapFigureText(figure: RecapFormat.hour(peak), numberSize: 260, unitSize: 110, unitGap: 10, trimmed: true)
                Spacer(minLength: 12)
                if let persona = recap.persona {
                    RecapPill(stroke: RecapColor.ink, horizontal: 16, vertical: 8) {
                        Text(persona.title)
                            .font(.recap(18, .medium))
                    }
                    .padding(.bottom, 10)
                }
            }
            .padding(.top, 56)
            Text(localized: "is your busiest hour of the day.")
                .font(.recap(44, .bold))
                .lineSpacing(6)
                .lineLimit(2)
                .minimumScaleFactor(0.6)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 30)
            RecapRule(strong: true).padding(.top, 40)
            VStack(spacing: 0) {
                ForEach(0..<min(24, hours.count), id: \.self) { hour in
                    row(hour, tokens: hours[hour], peak: hour == peak, maximum: maximum)
                }
            }
            .padding(.top, 12)
            Spacer(minLength: 16)
            RecapRule(strong: true)
            caption.padding(.top, 26)
        }
    }

    private func row(_ hour: Int, tokens: Int, peak: Bool, maximum: Int) -> some View {
        let late = RecapFormat.isLate(hour)
        let color = peak ? RecapColor.ink : (late ? RecapColor.lime : RecapColor.restBar)
        let fraction = max(CGFloat(tokens) / CGFloat(maximum), 0.025)
        return HStack(spacing: 0) {
            Text(verbatim: RecapFormat.hourLabel(hour))
                .font(.recap(19, peak ? .semibold : .regular, mono: true))
                .foregroundStyle(peak || late ? RecapColor.ink : RecapColor.restLabel)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(width: 104, alignment: .leading)
            GeometryReader { proxy in
                HStack(spacing: 14) {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(color)
                        .frame(width: max(6, proxy.size.width * 0.82 * fraction - (peak ? 80 : 0)), height: peak ? 28 : 20)
                    if peak {
                        RecapPill(fill: RecapColor.lime, horizontal: 10, vertical: 3) {
                            Text(localized: "Peak")
                                .font(.recap(15, .bold))
                        }
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxHeight: .infinity)
            }
        }
        .frame(height: 48)
    }

    private var caption: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let late = recap.lateShare {
                RecapRichText(
                    text: .localized("\(RecapEmphasis.mark(RecapFormat.percent(late))) of it came between 9 PM and 5 AM."),
                    size: 30, lineSpacing: 6
                )
            }
            if let latest = recap.latestMinute, recap.lateNights > 0 {
                RecapRichText(
                    text: .localized("Latest was \(RecapEmphasis.mark(RecapFormat.clockTime(minutes: latest))), and \(RecapEmphasis.mark("\(recap.lateNights)")) nights ran past midnight."),
                    size: 30, highlights: false, lineSpacing: 6
                )
            }
        }
    }
}

// MARK: - Payback

/// What the period cost at API prices against what the reader pays.
struct RecapPaybackView: View {
    let deck: RecapDeck

    private var recap: Recap { deck.recap }

    var body: some View {
        if let payback = deck.payback {
            RecapStoryPage(page: deck.page(of: .payback)) {
                content(payback)
            }
        }
    }

    private func money(_ amount: Double) -> String {
        RecapFormat.money(amount, currency: recap.currency)
    }

    @ViewBuilder
    private func content(_ payback: RecapPayback) -> some View {
        let kicker: String = .localized("On a plan of \(money(payback.monthlyPrice)) a month, you used")
        Text(kicker)
            .font(.recap(34))
            .foregroundStyle(Color(recap: 0x55554F))
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 60)
        Text(verbatim: money(payback.used))
            .font(.recap(250, .bold))
            .tracking(-250 * 0.06)
            .lineLimit(1)
            .minimumScaleFactor(0.45)
            .padding(.top, 40 - 250 * RecapFigureText.ascenderRoom)
            .padding(.bottom, -250 * RecapFigureText.descenderRoom)
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(localized: "Payback")
                .font(.recap(30, .bold))
            Text(verbatim: RecapFormat.multiple(payback.multiple) + "×")
                .font(.recap(96, .bold))
                .tracking(-96 * 0.04)
        }
        .padding(EdgeInsets(top: 10, leading: 22, bottom: 14, trailing: 22))
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(RecapColor.lime))
        .fixedSize()
        .padding(.top, 66)
        ruler(payback).padding(.top, 60)
        Spacer(minLength: 24)
        spendByModel
    }

    // The ruler.

    private func ruler(_ payback: RecapPayback) -> some View {
        let scale = RecapRulerScale(for: max(payback.used, payback.paid))
        let barArea: CGFloat = 640
        return VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 20) {
                rulerLabel(.localized("You paid"))
                HStack(spacing: 14) {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(RecapColor.ink, lineWidth: 2)
                        .frame(width: max(8, barArea * payback.paid / scale.maximum), height: 72)
                    Text(verbatim: money(payback.paid)).font(.recap(24, .semibold)).lineLimit(1)
                }
            }
            HStack(spacing: 20) {
                rulerLabel(.localized("You used"))
                HStack(spacing: 14) {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(RecapColor.ink)
                        .frame(width: max(8, barArea * payback.used / scale.maximum), height: 72)
                    Text(verbatim: money(payback.used)).font(.recap(24, .semibold)).lineLimit(1)
                }
            }
            HStack(alignment: .top, spacing: 20) {
                Color.clear.frame(width: 120, height: 1)
                axis(scale: scale, width: barArea)
            }
        }
    }

    private func rulerLabel(_ title: String) -> some View {
        Text(title)
            .font(.recap(22))
            .foregroundStyle(Color(recap: 0x55554F))
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .frame(width: 120, alignment: .leading)
    }

    private func axis(scale: RecapRulerScale, width: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            Rectangle().fill(RecapColor.ink).frame(width: width, height: 1.5)
            ForEach(0...scale.ticks, id: \.self) { index in
                let value = Double(index) * scale.step / Double(scale.subdivisions)
                let labelled = index % scale.subdivisions == 0
                let x = width * value / scale.maximum
                VStack(spacing: 6) {
                    Rectangle().fill(RecapColor.ink).frame(width: 1.5, height: labelled ? 14 : 8)
                    if labelled {
                        Text(verbatim: RecapFormat.axisMoney(value, step: scale.step, currency: recap.currency))
                            .font(.recap(14, .regular, mono: true))
                            .foregroundStyle(RecapColor.tertiary)
                            .fixedSize()
                    }
                }
                .position(x: x, y: labelled ? 30 : 4)
            }
        }
        .frame(width: width, height: 44, alignment: .topLeading)
    }

    // Spend by model, and the cache.

    private var spendByModel: some View {
        let priced = recap.models.filter { ($0.cost ?? 0) > 0 }.sorted { ($0.cost ?? 0) > ($1.cost ?? 0) }
        let rows = Array(priced.prefix(5))
        let top = max(rows.first?.cost ?? 1, 0.0001)
        return VStack(spacing: 0) {
            if !rows.isEmpty {
                HStack(alignment: .firstTextBaseline) {
                    Text(localized: "Where the money went")
                        .font(.recap(22, .bold))
                    Spacer()
                    Text(localized: "By model")
                        .font(.recap(18))
                        .foregroundStyle(RecapColor.tertiary)
                }
                .padding(.bottom, 10)
                ForEach(rows.indices, id: \.self) { index in
                    let first = index == 0
                    RecapRule()
                    VStack(spacing: 12) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(verbatim: rows[index].name)
                                .font(.recap(32, first ? .semibold : .regular))
                                .lineLimit(1)
                            Spacer(minLength: 12)
                            Text(verbatim: money(rows[index].cost ?? 0))
                                .font(.recap(32, first ? .semibold : .regular))
                                .lineLimit(1)
                        }
                        GeometryReader { proxy in
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(first ? RecapColor.lime : RecapColor.ink)
                                .frame(width: max(8, proxy.size.width * (rows[index].cost ?? 0) / top), height: 10)
                        }
                        .frame(height: 10)
                    }
                    .padding(.top, 22)
                    .padding(.bottom, 24)
                }
            }
            RecapRule(strong: true)
            if let saved = deck.cacheSavings {
                HStack(alignment: .firstTextBaseline) {
                    Text(localized: "The cache saved you")
                        .font(.recap(24))
                    Spacer(minLength: 12)
                    Text(verbatim: money(saved))
                        .font(.recap(34, .bold))
                        .padding(.horizontal, 8)
                        .background(RecapColor.lime)
                        .lineLimit(1)
                }
                .padding(.top, 22)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(localized: "Estimated at each model's published API price. The plan price is the one you typed in Pulse.")
                // A period still running: both figures stop today.
                if deck.payback?.isToDate == true {
                    Text(localized: "Figures are to date, and the plan price is prorated by the days so far.")
                }
                if deck.costIsFloor {
                    Text(localized: "Some work had no published price, so the money is a floor.")
                }
            }
            .font(.recap(16))
            .foregroundStyle(RecapColor.tertiary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 18)
        }
    }
}
