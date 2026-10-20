import AppKit
import SwiftUI

@main
struct TokenCalendarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = HistoryStore()

    var body: some Scene {
        Window(L.t("Claude Token-Kalender"), id: "calendar") {
            CalendarView()
                .environmentObject(store)
                .frame(minWidth: 760, minHeight: 540)
        }
        .defaultSize(width: 940, height: 660)

        // Menu bar item with today's tokens, like the macOS usage tracker.
        MenuBarExtra {
            MenuContent().environmentObject(store)
        } label: {
            MenuBarLabel().environmentObject(store)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // A bare SwiftPM executable starts as a background process; make it a
        // regular app so the window comes to the front and gets a Dock icon.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false   // keep the menu bar item alive
    }
}

@MainActor
final class HistoryStore: ObservableObject {
    @Published private(set) var result: TokenHistoryResult?
    @Published private(set) var loading = false
    private var timer: Timer?

    init() {
        reload()
        // New Claude Code activity shows up without pressing refresh.
        timer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.reload() }
        }
    }

    func reload() {
        guard !loading else { return }
        loading = true
        Task.detached(priority: .userInitiated) {
            let loaded = TokenHistory.load()
            await MainActor.run {
                self.result = loaded
                self.loading = false
            }
        }
    }

    func usage(on day: Date) -> DayUsage? {
        result?.days[Calendar.current.startOfDay(for: day)]
    }
}

struct MenuBarLabel: View {
    @EnvironmentObject private var store: HistoryStore

    var body: some View {
        let today = store.usage(on: Date())?.total(includeCacheReads: true) ?? 0
        HStack(spacing: 4) {
            Image(systemName: "calendar")
            Text(TokenFormat.short(today))
        }
    }
}

struct MenuContent: View {
    @EnvironmentObject private var store: HistoryStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let today = store.usage(on: Date())
        Text(L.t("Heute: ") + TokenFormat.short(today?.total(includeCacheReads: true) ?? 0) + L.t(" Tokens"))
        Text(L.t("Ohne Cache-Lesen: ") + TokenFormat.short(today?.total(includeCacheReads: false) ?? 0))
        Divider()
        Button(L.t("Kalender öffnen")) {
            openWindow(id: "calendar")
            NSApp.activate(ignoringOtherApps: true)
        }
        .keyboardShortcut("k")
        Button(L.t("Neu einlesen")) { store.reload() }
            .keyboardShortcut("r")
        Divider()
        Button(L.t("Beenden")) { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}

/// Minimal localization: source strings are German, English for every other language.
enum L {
    private static let german = (Locale.preferredLanguages.first ?? "").hasPrefix("de")

    private static let en: [String: String] = [
        "Claude Token-Kalender": "Claude Token Calendar",
        "Heute": "Today",
        "Heute: ": "Today: ",
        " Tokens": " tokens",
        "Ohne Cache-Lesen: ": "Excl. cache reads: ",
        "Kalender öffnen": "Open calendar",
        "Neu einlesen": "Rescan",
        "Beenden": "Quit",
        "Alle Tokens": "All tokens",
        "Ohne Cache-Lesen": "Excl. cache reads",
        "Lese Claude-Code-Verläufe …": "Reading Claude Code transcripts …",
        "Keine Claude-Code-Verläufe gefunden in ~/.claude/projects": "No Claude Code transcripts found in ~/.claude/projects",
        "%@ Tokens im Monat  ·  %d aktive Tage  ·  Ø %@ pro aktivem Tag": "%@ tokens this month  ·  %d active days  ·  avg %@ per active day",
        "Weniger": "Less",
        "Mehr": "More",
        "Lade …": "Loading …",
        "An diesem Tag keine Nutzung.": "No usage on this day.",
        "Tokens gesamt": "Total tokens",
        "Tokens ohne Cache-Lesen": "Tokens excl. cache reads",
        "Input": "Input",
        "Output": "Output",
        "Cache schreiben": "Cache writes",
        "Cache lesen": "Cache reads",
        "Antworten": "Responses",
        "Nach Modell": "By model",
        "Vorheriger Monat": "Previous month",
        "Nächster Monat": "Next month",
        " Mrd.": " B",
    ]

    static func t(_ german: String) -> String {
        if Self.german { return german }
        return en[german] ?? german
    }
}

enum TokenFormat {
    static func short(_ v: Int) -> String {
        let d = Double(v)
        let f = NumberFormatter()
        f.locale = Locale.current
        f.numberStyle = .decimal
        if v >= 1_000_000_000 {
            f.maximumFractionDigits = 2
            return (f.string(from: NSNumber(value: d / 1e9)) ?? "") + L.t(" Mrd.")
        }
        if v >= 1_000_000 {
            f.maximumFractionDigits = v >= 100_000_000 ? 0 : 1
            return (f.string(from: NSNumber(value: d / 1e6)) ?? "") + " M"
        }
        if v >= 1_000 {
            f.maximumFractionDigits = 0
            return (f.string(from: NSNumber(value: d / 1e3)) ?? "") + " K"
        }
        return String(v)
    }

    static func full(_ v: Int) -> String {
        v.formatted(.number)
    }
}
