import DailyCommandCore
import SwiftUI

@MainActor @Observable
final class QuarterModel {
    var quarter = Planning.quarterOf(Planning.today())
    var payload: QuarterPayload?
    var loading = false
    var error: String?
    var newRock = ""

    func load(_ api: PlannerAPI) async {
        loading = payload == nil
        defer { loading = false }
        do { payload = try await api.quarter(quarter); error = nil } catch { self.error = error.localizedDescription }
    }

    func shift(_ n: Int, _ api: PlannerAPI) async {
        quarter = Planning.shiftQuarter(quarter, by: n)
        payload = nil
        await load(api)
    }

    func run(_ api: PlannerAPI, _ work: () async throws -> Void) async {
        do { try await work(); await load(api) } catch { self.error = error.localizedDescription }
    }
}

struct QuarterView: View {
    @Environment(AppModel.self) private var app
    @State private var m = QuarterModel()

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                header
                if let error = m.error { ErrorBanner(message: error).onTapGesture { m.error = nil } }
                if m.loading {
                    ProgressView().frame(maxWidth: .infinity).padding(40)
                } else if let api = app.api, let p = m.payload {
                    scorecard(Planning.scorecard(p))
                    Card("Theme") {
                        EditRow(label: "Quarter theme", value: p.record?.theme) { v in await m.run(api) { try await api.saveQuarter(m.quarter, patch: ["theme": v.isEmpty ? NSNull() : v]) } }
                        EditRow(label: "Stop doing", value: p.record?.stopDoing) { v in await m.run(api) { try await api.saveQuarter(m.quarter, patch: ["stop_doing": v.isEmpty ? NSNull() : v]) } }
                    }
                    Card("Quarter rocks") {
                        if p.rocks.isEmpty {
                            Text("Three to five outcomes that define this quarter. Link each to a yearly goal.").font(DC.Font.small).foregroundStyle(DC.muted)
                        }
                        ForEach(p.rocks) { rock in QuarterRockRow(rock: rock, goals: p.goals, weekRocks: p.weekRocks, m: m, api: api) }
                        HStack {
                            TextField("Add a quarter rock", text: $m.newRock).field().submitLabel(.done).onSubmit { add(api) }
                            Button { add(api) } label: { Image(systemName: "plus.circle.fill").font(.title2) }
                                .disabled(m.newRock.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    }
                    Card("Review") {
                        EditRow(label: "Quarter review", value: p.record?.review) { v in await m.run(api) { try await api.saveQuarter(m.quarter, patch: ["review": v.isEmpty ? NSNull() : v]) } }
                        if p.record?.closedAt == nil {
                            Button { Task { await m.run(api) { try await api.saveQuarter(m.quarter, patch: ["closed_at": ServerDate.iso(Date())]) } } } label: {
                                Text("Close the quarter").frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                        } else {
                            Text("Quarter closed").font(DC.Font.small).foregroundStyle(DC.green)
                        }
                    }
                }
            }
            .padding(16)
        }
        .background(DC.bg)
        .navigationTitle("Quarter")
        .navigationBarTitleDisplayMode(.inline)
        .task { if let api = app.api { await m.load(api) } }
        .refreshable { if let api = app.api { await m.load(api) } }
    }

    private func add(_ api: PlannerAPI) {
        let t = m.newRock.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        m.newRock = ""
        Task { await m.run(api) { try await api.saveQuarterRock(id: nil, patch: ["quarter": m.quarter, "title": t, "milestones": [], "sort_order": (m.payload?.rocks.count ?? 0) + 1]) } }
    }

    private var header: some View {
        HStack {
            Button { Task { if let api = app.api { await m.shift(-1, api) } } } label: { Image(systemName: "chevron.left") }
            Spacer()
            Text(Planning.quarterTitle(m.quarter)).font(DC.Font.headline).foregroundStyle(DC.text)
            Spacer()
            Button { Task { if let api = app.api { await m.shift(1, api) } } } label: { Image(systemName: "chevron.right") }
        }
        .padding(.horizontal, 4)
    }

    private func scorecard(_ s: Planning.Scorecard) -> some View {
        Card("Scorecard") {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                stat("Days closed", "\(s.daysClosed)/\(s.daysSoFar)")
                stat("Top 3 hit", s.top3Pct.map { "\($0)%" } ?? "—")
                stat("Tasks done", "\(s.tasksDone)")
                stat("Rocks", "\(s.rocksDone)/\(s.rocksSet)")
                stat("Avg energy", s.avgEnergy.map { String(format: "%.1f", $0) } ?? "—")
                stat("Workouts", "\(s.workouts)")
            }
        }
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(DC.Font.title).foregroundStyle(DC.text).monospacedDigit()
            Text(label).font(DC.Font.small).foregroundStyle(DC.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct QuarterRockRow: View {
    let rock: QuarterRock
    let goals: [Goal]
    let weekRocks: [RockStub]
    @Bindable var m: QuarterModel
    let api: PlannerAPI

    var body: some View {
        let linked = weekRocks.filter { $0.quarterRockId == rock.id }
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Button {
                    Task { await m.run(api) { try await api.saveQuarterRock(id: rock.id, patch: ["status": rock.status == .done ? "open" : "done"]) } }
                } label: {
                    Image(systemName: rock.status == .done ? "checkmark.circle.fill" : "circle").foregroundStyle(rock.status == .done ? DC.green : DC.muted)
                }
                .buttonStyle(.plain)
                Text(rock.title).foregroundStyle(rock.status == .done ? DC.muted : DC.text).strikethrough(rock.status == .done)
                Spacer()
                Menu {
                    Menu("Link to goal") {
                        ForEach(goals) { g in
                            Button(g.title.isEmpty ? "Untitled goal" : g.title) { Task { await m.run(api) { try await api.saveQuarterRock(id: rock.id, patch: ["goal_id": g.id]) } } }
                        }
                        Button("No goal") { Task { await m.run(api) { try await api.saveQuarterRock(id: rock.id, patch: ["goal_id": NSNull()]) } } }
                    }
                    Button("Drop rock", role: .destructive) { Task { await m.run(api) { try await api.saveQuarterRock(id: rock.id, patch: ["status": "dropped"]) } } }
                } label: { Image(systemName: "ellipsis").foregroundStyle(DC.dim) }
            }
            HStack(spacing: 10) {
                if let g = goals.first(where: { $0.id == rock.goalId }) { Text("→ \(g.title)").foregroundStyle(DC.goldText) }
                if !linked.isEmpty { Text("\(linked.filter { $0.status == .done }.count)/\(linked.count) weekly rocks").foregroundStyle(DC.muted) }
            }
            .font(DC.Font.small)
            .padding(.leading, 30)
        }
        .padding(.vertical, 2)
    }
}
