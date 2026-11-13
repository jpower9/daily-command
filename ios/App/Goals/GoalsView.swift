import DailyCommandCore
import SwiftUI

@MainActor @Observable
final class GoalsModel {
    var year = Calendar.current.component(.year, from: Date())
    var payload: GoalsPayload?
    var loading = false
    var error: String?

    func load(_ api: PlannerAPI) async {
        loading = payload == nil
        defer { loading = false }
        do { payload = try await api.goals(year: year); error = nil } catch { model.handle(error); self.error = error.localizedDescription }
    }

    func run(_ api: PlannerAPI, _ work: () async throws -> Void) async {
        do { try await work(); await load(api) } catch { model.handle(error); self.error = error.localizedDescription }
    }
}

struct GoalsView: View {
    @Environment(AppModel.self) private var app
    @Environment(Navigator.self) private var nav
    @State private var m = GoalsModel()

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                HStack {
                    Button { m.year -= 1; m.payload = nil; Task { if let api = app.api { await m.load(api) } } } label: { Image(systemName: "chevron.left") }
                    Spacer()
                    Text("Goals \(String(m.year))").font(DC.Font.headline).foregroundStyle(DC.text)
                    Spacer()
                    Button { m.year += 1; m.payload = nil; Task { if let api = app.api { await m.load(api) } } } label: { Image(systemName: "chevron.right") }
                }
                .padding(.horizontal, 4)
                if let error = m.error { ErrorBanner(message: error).onTapGesture { m.error = nil } }
                if m.loading {
                    ProgressView().frame(maxWidth: .infinity).padding(40)
                } else if let api = app.api, let p = m.payload {
                    let active = p.goals.filter { $0.status != .dropped }
                    if active.isEmpty {
                        Card("Wildly important goals") {
                            Text("Three to five goals for the year, each with a from → to → by. Quarter rocks link up to these.")
                                .font(DC.Font.small).foregroundStyle(DC.muted)
                        }
                    }
                    ForEach(active) { g in
                        NavigationLink { GoalDetail(goalId: g.id, m: m, api: api) } label: {
                            GoalCard(goal: g, rocks: p.quarterRocks.filter { $0.goalId == g.id })
                        }
                        .buttonStyle(.plain)
                    }
                    Button {
                        Task { await m.run(api) { try await api.saveGoal(id: nil, patch: ["year": m.year, "title": "New goal", "sort_order": active.count + 1]) } }
                    } label: { Label("Add goal", systemImage: "plus").frame(maxWidth: .infinity) }
                        .buttonStyle(.bordered)
                }
            }
            .padding(16)
        }
        .background(DC.bg)
        .navigationTitle("Goals")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarLeading) { SearchButton() } }
        .task { if let d = nav.take(.goals) { m.year = Int(d.prefix(4)) ?? m.year }; if let api = app.api { await m.load(api) } }
        .refreshable { if let api = app.api { await m.load(api) } }
        .onChange(of: nav.jumpId) { _, _ in
            if let d = nav.take(.goals), let api = app.api { m.year = Int(d.prefix(4)) ?? m.year; m.payload = nil; Task { await m.load(api) } }
        }
    }
}

struct GoalCard: View {
    let goal: Goal
    let rocks: [QuarterRock]

    var body: some View {
        Card(goal.area ?? "Goal") {
            Text(goal.title.isEmpty ? "Untitled goal" : goal.title).font(DC.Font.headline).foregroundStyle(DC.text)
            if goal.fromValue != nil || goal.toValue != nil || goal.byDate != nil {
                Text("\(goal.fromValue ?? "…") → \(goal.toValue ?? "…")\(goal.byDate.map { " by \(DateText.short($0))" } ?? "")")
                    .font(DC.Font.small).foregroundStyle(DC.text2)
            }
            if let pct = Planning.progress(start: goal.startValue, current: goal.currentValue, target: goal.targetValue) {
                ProgressView(value: Double(pct), total: 100).tint(DC.gold)
                Text("\(pct)%\(goal.unit.map { " · \(fmt(goal.currentValue)) \($0)" } ?? "")").font(DC.Font.small).foregroundStyle(DC.muted)
            }
            if !rocks.isEmpty {
                Text("\(rocks.filter { $0.status == .done }.count)/\(rocks.count) quarter rocks").font(DC.Font.small).foregroundStyle(DC.muted)
            }
        }
        .trailing {
            Text(goal.status.rawValue).font(DC.Font.small).foregroundStyle(goal.status == .done ? DC.green : DC.dim)
        }
    }

    private func fmt(_ v: Double?) -> String {
        guard let v else { return "—" }
        return v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v)
    }
}

struct GoalDetail: View {
    let goalId: String
    @Bindable var m: GoalsModel
    let api: PlannerAPI
    @State private var value = ""
    @State private var note = ""

    // Read live from the model so edits show without leaving the screen.
    private var goal: Goal { m.payload?.goals.first { $0.id == goalId } ?? Goal(.object(["id": .string(goalId)])) }
    private var updates: [GoalUpdate] { (m.payload?.updates ?? []).filter { $0.goalId == goalId } }
    private var rocks: [QuarterRock] { (m.payload?.quarterRocks ?? []).filter { $0.goalId == goalId } }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                Card("Goal") {
                    EditRow(label: "Title", value: goal.title) { v in await m.run(api) { try await api.saveGoal(id: goal.id, patch: ["title": v]) } }
                    EditRow(label: "Area", value: goal.area) { v in await m.run(api) { try await api.saveGoal(id: goal.id, patch: ["area": orNull(v.isEmpty ? nil : v)]) } }
                    EditRow(label: "From", value: goal.fromValue) { v in await m.run(api) { try await api.saveGoal(id: goal.id, patch: ["from_value": orNull(v.isEmpty ? nil : v)]) } }
                    EditRow(label: "To", value: goal.toValue) { v in await m.run(api) { try await api.saveGoal(id: goal.id, patch: ["to_value": orNull(v.isEmpty ? nil : v)]) } }
                    EditRow(label: "By (yyyy-mm-dd)", value: goal.byDate) { v in await m.run(api) { try await api.saveGoal(id: goal.id, patch: ["by_date": orNull(v.isEmpty ? nil : v)]) } }
                    EditRow(label: "Why", value: goal.why) { v in await m.run(api) { try await api.saveGoal(id: goal.id, patch: ["why": orNull(v.isEmpty ? nil : v)]) } }
                }
                Card("Measure") {
                    numberRow("Start", goal.startValue, "start_value")
                    numberRow("Target", goal.targetValue, "target_value")
                    EditRow(label: "Unit", value: goal.unit) { v in await m.run(api) { try await api.saveGoal(id: goal.id, patch: ["unit": orNull(v.isEmpty ? nil : v)]) } }
                    Divider().overlay(DC.line)
                    Text("Log progress").font(DC.Font.small).foregroundStyle(DC.text2)
                    HStack {
                        TextField("Value", text: $value).keyboardType(.decimalPad).field().frame(maxWidth: 120)
                        TextField("Note", text: $note).field()
                        Button("Log") {
                            let v = Double(value.replacingOccurrences(of: ",", with: "."))
                            let n = note.trimmingCharacters(in: .whitespaces)
                            value = ""; note = ""
                            Task { await m.run(api) { try await api.updateGoal(goal.id, value: v, note: n.isEmpty ? nil : n) } }
                        }
                        .disabled(value.isEmpty && note.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    ForEach(updates.prefix(20)) { u in
                        HStack {
                            Text(DateText.short(u.onDate)).foregroundStyle(DC.muted).frame(width: 64, alignment: .leading)
                            if let v = u.value { Text(v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v)).foregroundStyle(DC.goldText) }
                            if let n = u.note { Text(n).foregroundStyle(DC.text2) }
                            Spacer()
                        }
                        .font(DC.Font.small)
                    }
                }
                if !rocks.isEmpty {
                    Card("Quarter rocks") {
                        ForEach(rocks) { r in
                            HStack {
                                Image(systemName: r.status == .done ? "checkmark.circle.fill" : "circle").foregroundStyle(r.status == .done ? DC.green : DC.muted)
                                Text(r.title).foregroundStyle(DC.text)
                                Spacer()
                                Text(Planning.quarterTitle(r.quarter)).font(DC.Font.small).foregroundStyle(DC.muted)
                            }
                        }
                    }
                }
                Card("Status") {
                    Picker("Status", selection: Binding(get: { goal.status }, set: { s in Task { await m.run(api) { try await api.saveGoal(id: goal.id, patch: ["status": s.rawValue]) } } })) {
                        ForEach(GoalStatus.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
            }
            .padding(16)
        }
        .background(DC.bg)
        .navigationTitle(goal.title.isEmpty ? "Goal" : goal.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func numberRow(_ label: String, _ value: Double?, _ key: String) -> some View {
        EditRow(label: label, value: value.map { $0 == $0.rounded() ? String(Int($0)) : String($0) }) { v in
            let d = Double(v.replacingOccurrences(of: ",", with: "."))
            await m.run(api) { try await api.saveGoal(id: goal.id, patch: [key: orNull(d)]) }
        }
    }
}
