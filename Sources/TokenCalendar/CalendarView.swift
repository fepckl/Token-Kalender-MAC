import SwiftUI

extension Calendar {
    func startOfMonth(for date: Date) -> Date {
        self.date(from: dateComponents([.year, .month], from: date)) ?? startOfDay(for: date)
    }
}

/// Fixed palette per appearance so blended heat colors are computed in plain RGB.
struct RGB {
    var r: Double, g: Double, b: Double

    init(_ r: Double, _ g: Double, _ b: Double) { self.r = r / 255; self.g = g / 255; self.b = b / 255 }
    private init(raw r: Double, _ g: Double, _ b: Double) { self.r = r; self.g = g; self.b = b }

    var color: Color { Color(.sRGB, red: r, green: g, blue: b) }

    /// `t` is the weight of `a`.
    static func mix(_ a: RGB, _ b: RGB, _ t: Double) -> RGB {
        let t = min(max(t, 0), 1)
        return RGB(raw: a.r * t + b.r * (1 - t), a.g * t + b.g * (1 - t), a.b * t + b.b * (1 - t))
    }
}

struct Theme {
    let surface: RGB
    let border: RGB
    let track: RGB
    static let accent = RGB(217, 119, 87)     // Claude orange
    static let deep = RGB(170, 70, 35)

    static func of(_ scheme: ColorScheme) -> Theme {
        scheme == .dark
            ? Theme(surface: RGB(44, 44, 46), border: RGB(70, 70, 72), track: RGB(62, 62, 64))
            : Theme(surface: RGB(255, 255, 255), border: RGB(215, 215, 215), track: RGB(226, 226, 226))
    }

    func heat(_ t: Double) -> RGB {
        // From a pale tint of Claude orange up to a deep burnt orange.
        guard t > 0 else { return surface }
        return RGB.mix(Theme.deep, RGB.mix(Theme.accent, surface, 0.8), t)
    }
}

struct CalendarView: View {
    @EnvironmentObject private var store: HistoryStore
    @Environment(\.colorScheme) private var scheme
    @State private var month = Calendar.current.startOfMonth(for: Date())
    @State private var selected = Calendar.current.startOfDay(for: Date())
    @State private var includeCacheReads = true
    @FocusState private var focused: Bool

    private let cal = Calendar.current
    private var theme: Theme { Theme.of(scheme) }

    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            VStack(alignment: .leading, spacing: 12) {
                header
                Text(summary).foregroundStyle(.secondary)
                weekdayHeader
                grid
                legend
            }
            DetailPanel(day: selected,
                        usage: store.usage(on: selected),
                        includeCacheReads: includeCacheReads,
                        loading: store.loading,
                        theme: theme)
                .frame(width: 270)
                .frame(maxHeight: .infinity, alignment: .top)
        }
        .padding(20)
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .onAppear { focused = true }
        .onKeyPress(.leftArrow) { move(days: -1); return .handled }
        .onKeyPress(.rightArrow) { move(days: 1); return .handled }
        .onKeyPress(.upArrow) { move(days: -7); return .handled }
        .onKeyPress(.downArrow) { move(days: 7); return .handled }
        .onKeyPress(.pageUp) { shiftMonth(-1); return .handled }
        .onKeyPress(.pageDown) { shiftMonth(1); return .handled }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 10) {
            Button { shiftMonth(-1) } label: { Image(systemName: "chevron.left") }
                .help(L.t("Vorheriger Monat"))
            Text(month, format: .dateTime.month(.wide).year())
                .font(.title.weight(.semibold))
                .frame(minWidth: 190, alignment: .leading)
            Button { shiftMonth(1) } label: { Image(systemName: "chevron.right") }
                .help(L.t("Nächster Monat"))
            Button(L.t("Heute")) {
                selected = cal.startOfDay(for: Date())
                month = cal.startOfMonth(for: selected)
            }
            Spacer()
            Picker("", selection: $includeCacheReads) {
                Text(L.t("Alle Tokens")).tag(true)
                Text(L.t("Ohne Cache-Lesen")).tag(false)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 260)
            Button { store.reload() } label: {
                Image(systemName: "arrow.clockwise")
            }
            .keyboardShortcut("r")
            .disabled(store.loading)
        }
    }

    private var summary: String {
        if store.loading && store.result == nil { return L.t("Lese Claude-Code-Verläufe …") }
        guard let result = store.result, !result.days.isEmpty else {
            return L.t("Keine Claude-Code-Verläufe gefunden in ~/.claude/projects")
        }
        let values = daysOfMonth.map(value)
        let total = values.reduce(0, +)
        let active = values.filter { $0 > 0 }.count
        return String(format: L.t("%@ Tokens im Monat  ·  %d aktive Tage  ·  Ø %@ pro aktivem Tag"),
                      TokenFormat.short(total), active, TokenFormat.short(active == 0 ? 0 : total / active))
    }

    // MARK: Grid

    private var weekdayHeader: some View {
        let symbols = cal.shortWeekdaySymbols
        let first = cal.firstWeekday - 1
        return HStack(spacing: 6) {
            ForEach(0..<7, id: \.self) { i in
                Text(symbols[(first + i) % 7])
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 4)
            }
        }
    }

    private var grid: some View {
        let start = gridStart
        let maxValue = daysOfMonth.map(value).max() ?? 0
        return VStack(spacing: 6) {
            ForEach(0..<6, id: \.self) { row in
                HStack(spacing: 6) {
                    ForEach(0..<7, id: \.self) { col in
                        let day = cal.date(byAdding: .day, value: row * 7 + col, to: start) ?? start
                        DayCell(day: day,
                                value: value(day),
                                maxValue: maxValue,
                                inMonth: cal.isDate(day, equalTo: month, toGranularity: .month),
                                isSelected: cal.isDate(day, inSameDayAs: selected),
                                isToday: cal.isDateInToday(day),
                                theme: theme)
                            .onTapGesture { select(day) }
                    }
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    private var legend: some View {
        HStack(spacing: 4) {
            Text(L.t("Weniger")).font(.caption).foregroundStyle(.secondary)
            ForEach(0..<5, id: \.self) { i in
                RoundedRectangle(cornerRadius: 3)
                    .fill(theme.heat(Double(i) / 4).color)
                    .overlay(RoundedRectangle(cornerRadius: 3).stroke(theme.border.color, lineWidth: i == 0 ? 1 : 0))
                    .frame(width: 16, height: 14)
            }
            Text(L.t("Mehr")).font(.caption).foregroundStyle(.secondary)
        }
    }

    // MARK: Data helpers

    private var gridStart: Date {
        let weekday = cal.component(.weekday, from: month)
        let offset = (weekday - cal.firstWeekday + 7) % 7
        return cal.date(byAdding: .day, value: -offset, to: month) ?? month
    }

    private var daysOfMonth: [Date] {
        let count = cal.range(of: .day, in: .month, for: month)?.count ?? 30
        return (0..<count).compactMap { cal.date(byAdding: .day, value: $0, to: month) }
    }

    private func value(_ day: Date) -> Int {
        store.usage(on: day)?.total(includeCacheReads: includeCacheReads) ?? 0
    }

    private func select(_ day: Date) {
        selected = cal.startOfDay(for: day)
        month = cal.startOfMonth(for: selected)
    }

    private func move(days: Int) {
        if let d = cal.date(byAdding: .day, value: days, to: selected) { select(d) }
    }

    private func shiftMonth(_ delta: Int) {
        guard let m = cal.date(byAdding: .month, value: delta, to: month) else { return }
        month = m
        let dayCount = cal.range(of: .day, in: .month, for: m)?.count ?? 28
        let day = min(cal.component(.day, from: selected), dayCount)
        selected = cal.date(byAdding: .day, value: day - 1, to: m) ?? m
    }
}

struct DayCell: View {
    let day: Date
    let value: Int
    let maxValue: Int
    let inMonth: Bool
    let isSelected: Bool
    let isToday: Bool
    let theme: Theme

    var body: some View {
        // sqrt scale: one huge day would otherwise wash every other day out.
        let intensity = maxValue > 0 && value > 0 ? (Double(value) / Double(maxValue)).squareRoot() : 0
        let base = value > 0 ? theme.heat(0.15 + 0.85 * intensity) : theme.surface
        let fill = inMonth ? base : RGB.mix(base, theme.surface, 0.4)
        let darkFill = intensity > 0.55
        let foreground: Color = darkFill ? .white : (inMonth ? .primary : .secondary)
        let borderColor: Color = isSelected ? .primary : (isToday ? Theme.accent.color : theme.border.color)

        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 7).fill(fill.color)
            RoundedRectangle(cornerRadius: 7)
                .strokeBorder(borderColor, lineWidth: isSelected || isToday ? 2 : 1)
            Text("\(Calendar.current.component(.day, from: day))")
                .font(.caption)
                .foregroundStyle(foreground)
                .padding(6)
            if value > 0 {
                Text(TokenFormat.short(value))
                    .font(.callout.weight(.medium))
                    .foregroundStyle(foreground)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(6)
            }
        }
        .opacity(inMonth ? 1 : 0.55)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
    }
}

struct DetailPanel: View {
    let day: Date
    let usage: DayUsage?
    let includeCacheReads: Bool
    let loading: Bool
    let theme: Theme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(day, format: .dateTime.weekday(.wide).day().month(.wide).year())
                .font(.headline)

            if let u = usage {
                Text(TokenFormat.short(u.total(includeCacheReads: includeCacheReads)))
                    .font(.system(size: 30, weight: .semibold))
                Text(includeCacheReads ? L.t("Tokens gesamt") : L.t("Tokens ohne Cache-Lesen"))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Divider().padding(.vertical, 4)
                row(L.t("Input"), TokenFormat.short(u.input))
                row(L.t("Output"), TokenFormat.short(u.output))
                row(L.t("Cache schreiben"), TokenFormat.short(u.cacheWrite))
                row(L.t("Cache lesen"), TokenFormat.short(u.cacheRead))
                row(L.t("Antworten"), TokenFormat.full(u.messages))

                Text(L.t("Nach Modell"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
                let total = max(1, u.byModel.values.reduce(0, +))
                ForEach(u.byModel.sorted { $0.value > $1.value }, id: \.key) { model, tokens in
                    let share = Double(tokens) / Double(total)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(model.replacingOccurrences(of: "claude-", with: "")).font(.caption)
                            Spacer()
                            Text("\(Int((share * 100).rounded())) %").font(.caption).foregroundStyle(.secondary)
                        }
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(theme.track.color)
                                Capsule().fill(Theme.accent.color).frame(width: geo.size.width * share)
                            }
                        }
                        .frame(height: 5)
                    }
                }
            } else {
                Text(loading ? L.t("Lade …") : L.t("An diesem Tag keine Nutzung."))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 10).fill(theme.surface.color))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(theme.border.color))
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).monospacedDigit()
        }
    }
}
