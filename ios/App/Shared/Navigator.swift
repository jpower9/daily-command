import DailyCommandCore
import Observation
import SwiftUI

enum AppTab: Hashable { case day, week, quarter, goals, journal }

/// Which tab is showing, and a one-shot "go to this date on this tab" request that search uses.
@MainActor @Observable
final class Navigator {
    var tab: AppTab = .day
    private(set) var jumpTab: AppTab?
    private(set) var jumpDate: String?
    private(set) var jumpId = 0

    func open(_ hit: SearchHit) {
        let t: AppTab = switch hit.kind {
        case .task, .event, .note: .day
        case .week, .rock: .week
        case .quarter, .quarterRock: .quarter
        case .goal: .goals
        }
        jumpTab = t
        jumpDate = hit.date
        jumpId += 1
        tab = t
    }

    /// The pending date for `tab`, consumed once.
    func take(_ t: AppTab) -> String? {
        guard jumpTab == t, let d = jumpDate else { return nil }
        jumpTab = nil
        jumpDate = nil
        return d
    }
}

/// Search across tasks, calendar, daily notes and planning records (client-api §22.7).
/// Journal and notebook entries never appear.
struct SearchSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(Navigator.self) private var nav
    @Environment(\.dismiss) private var dismiss
    @State private var q = ""
    @State private var hits: [SearchHit] = []
    @State private var searched = false
    @State private var error: String?
    @State private var seq = 0

    var body: some View {
        NavigationStack {
            List {
                if let error { Text(error).foregroundStyle(DC.red) }
                if searched, hits.isEmpty, error == nil {
                    Text("Nothing matches “\(q.trimmingCharacters(in: .whitespaces))”.").foregroundStyle(DC.muted)
                }
                ForEach(hits) { h in
                    Button {
                        nav.open(h)
                        dismiss()
                    } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text(h.kind.label.uppercased()).font(DC.Font.kicker).tracking(1.4).foregroundStyle(DC.goldText).frame(width: 64, alignment: .leading)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(h.title.isEmpty ? "Untitled" : h.title).foregroundStyle(DC.text).lineLimit(2)
                                if let extra = h.extra { Text(extra).font(DC.Font.small).foregroundStyle(DC.muted) }
                            }
                            Spacer()
                            Text(dateText(h)).font(DC.Font.small).foregroundStyle(DC.muted)
                        }
                    }
                    .listRowBackground(DC.card)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(DC.bg)
            .searchable(text: $q, placement: .navigationBarDrawer(displayMode: .always), prompt: "Tasks, calendar, notes, weeks, rocks, goals")
            .onChange(of: q) { _, v in Task { await run(v) } }
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.large])
    }

    private func dateText(_ h: SearchHit) -> String {
        switch h.kind {
        case .goal: String(h.date.prefix(4))
        case .quarter, .quarterRock: Planning.quarterTitle(Planning.quarterOf(h.date))
        case .week, .rock: "wk \(DateText.short(h.date))"
        default: DateText.short(h.date)
        }
    }

    private func run(_ term: String) async {
        let t = term.trimmingCharacters(in: .whitespaces)
        seq += 1
        let n = seq
        guard t.count >= 2, let api = app.api else { hits = []; searched = false; return }
        try? await Task.sleep(for: .milliseconds(300))
        guard n == seq else { return }
        do {
            let r = try await api.search(t)
            guard n == seq else { return }
            hits = r; searched = true; error = nil
        } catch { app.handle(error)
            guard n == seq else { return }
            self.error = error.localizedDescription; hits = []; searched = true
        }
    }
}

/// The magnifier in a tab's toolbar.
struct SearchButton: View {
    @State private var open = false
    var body: some View {
        Button { open = true } label: { Image(systemName: "magnifyingglass") }
            .accessibilityLabel("Search")
            .sheet(isPresented: $open) { SearchSheet() }
    }
}
