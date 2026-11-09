import DailyCommandCore
import SwiftUI

@MainActor @Observable
final class WeekModel {
    var weekStart = Planning.monday(Planning.today())
    var payload: WeekPayload?
    var loading = false
    var error: String?

    func load(_ api: PlannerAPI) async {
        loading = payload == nil
        defer { loading = false }
        do { payload = try await api.week(weekStart); error = nil } catch { self.error = error.localizedDescription }
    }

    func shift(_ n: Int, _ api: PlannerAPI) async {
        weekStart = Planning.addDays(weekStart, 7 * n)
        payload = nil
        await load(api)
    }

    func run(_ api: PlannerAPI, _ work: () async throws -> Void) async {
        do { try await work(); await load(api) } catch { self.error = error.localizedDescription }
    }

    func rocks(for role: Role) -> [Rock] { (payload?.rocks ?? []).filter { $0.roleId == role.id } }
    func tasks(on day: String) -> [PlannerTask] { (payload?.tasks ?? []).filter { $0.forDate == day } }
    func summary(on day: String) -> DaySummary? { payload?.days.first { $0.forDate == day } }
}

struct WeekView: View {
    @Environment(AppModel.self) private var app
    @State private var m = WeekModel()
    @State private var addingRole = false
    @State private var newRole = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                header
                if let error = m.error { ErrorBanner(message: error).onTapGesture { m.error = nil } }
                if m.loading {
                    ProgressView().frame(maxWidth: .infinity).padding(40)
                } else if let api = app.api, let p = m.payload {
                    Card("Theme") {
                        EditRow(label: "This week's theme", value: p.week?.theme) { v in await m.run(api) { try await api.saveWeek(m.weekStart, patch: ["theme": v.isEmpty ? NSNull() : v]) } }
                    }
                    daysStrip(p)
                    Card("Roles and rocks") {
                        if p.roles.isEmpty {
                            Text("Name the roles you play (Leader, Parent, Athlete…) and set one or two rocks per role each week.")
                                .font(DC.Font.small).foregroundStyle(DC.muted)
                        }
                        ForEach(p.roles) { role in RoleSection(role: role, m: m, api: api) }
                        if addingRole {
                            HStack {
                                TextField("Role name", text: $newRole).field().submitLabel(.done)
                                    .onSubmit { addRole(api) }
                                Button("Add") { addRole(api) }.disabled(newRole.trimmingCharacters(in: .whitespaces).isEmpty)
                            }
                        }
                    }
                    .trailing {
                        Button { addingRole.toggle() } label: { Image(systemName: addingRole ? "xmark" : "plus") }
                    }
                    Card("Review") {
                        EditRow(label: "Wins", value: p.week?.wins) { v in await m.run(api) { try await api.saveWeek(m.weekStart, patch: ["wins": v.isEmpty ? NSNull() : v]) } }
                        EditRow(label: "Biggest risk next week", value: p.week?.risk) { v in await m.run(api) { try await api.saveWeek(m.weekStart, patch: ["risk": v.isEmpty ? NSNull() : v]) } }
                        EditRow(label: "Carry forward", value: p.week?.carryForward) { v in await m.run(api) { try await api.saveWeek(m.weekStart, patch: ["carry_forward": v.isEmpty ? NSNull() : v]) } }
                        if p.week?.closedAt == nil {
                            Button {
                                Task { await m.run(api) {
                                    try await api.saveWeek(m.weekStart, patch: ["closed_at": ServerDate.iso(Date())])
                                    _ = try await api.carryRocks(from: m.weekStart)
                                } }
                            } label: { Text("Close the week and carry open rocks").frame(maxWidth: .infinity) }
                                .buttonStyle(.borderedProminent)
                        } else {
                            Text("Week closed").font(DC.Font.small).foregroundStyle(DC.green)
                        }
                    }
                }
            }
            .padding(16)
        }
        .background(DC.bg)
        .navigationTitle("Week")
        .navigationBarTitleDisplayMode(.inline)
        .task { if let api = app.api { await m.load(api) } }
        .refreshable { if let api = app.api { await m.load(api) } }
    }

    private func addRole(_ api: PlannerAPI) {
        let name = newRole.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        newRole = ""; addingRole = false
        Task { await m.run(api) { try await api.saveRole(id: nil, patch: ["name": name, "sort_order": (m.payload?.roles.count ?? 0) + 1]) } }
    }

    private var header: some View {
        HStack {
            Button { Task { if let api = app.api { await m.shift(-1, api) } } } label: { Image(systemName: "chevron.left") }
            Spacer()
            Text("Week of \(DateText.long(m.weekStart))").font(DC.Font.headline).foregroundStyle(DC.text)
            Spacer()
            Button { Task { if let api = app.api { await m.shift(1, api) } } } label: { Image(systemName: "chevron.right") }
        }
        .padding(.horizontal, 4)
    }

    private func daysStrip(_ p: WeekPayload) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Planning.weekDays(m.weekStart), id: \.self) { day in
                    let tasks = m.tasks(on: day)
                    let done = tasks.filter { $0.status == .done }.count
                    let s = m.summary(on: day)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(DateText.short(day)).font(DC.Font.small.weight(.semibold)).foregroundStyle(day == p.today ? DC.goldText : DC.text2)
                        Text(tasks.isEmpty ? "—" : "\(done)/\(tasks.count)").font(DC.Font.headline).foregroundStyle(DC.text)
                        HStack(spacing: 4) {
                            if let e = s?.energy ?? s?.pmEnergy { Text("E\(e)") }
                            if let r = s?.dayRating { Text("★\(r)") }
                            if s?.closedAt != nil { Image(systemName: "checkmark.seal.fill").foregroundStyle(DC.green) }
                        }
                        .font(DC.Font.small).foregroundStyle(DC.muted)
                    }
                    .padding(10)
                    .frame(width: 96, alignment: .leading)
                    .background(day == p.today ? DC.goldSoft : DC.card, in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(DC.line))
                }
            }
        }
    }
}

struct RoleSection: View {
    let role: Role
    @Bindable var m: WeekModel
    let api: PlannerAPI
    @State private var newRock = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(role.name).font(DC.Font.headline).foregroundStyle(DC.text)
                Spacer()
                Menu {
                    Button("Archive role", role: .destructive) {
                        Task { await m.run(api) { try await api.saveRole(id: role.id, patch: ["archived": true]) } }
                    }
                } label: { Image(systemName: "ellipsis").foregroundStyle(DC.dim) }
            }
            ForEach(m.rocks(for: role)) { rock in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Button {
                        Task { await m.run(api) { try await api.saveRock(id: rock.id, patch: ["status": rock.status == .done ? "open" : "done"]) } }
                    } label: {
                        Image(systemName: rock.status == .done ? "checkmark.circle.fill" : "circle").foregroundStyle(rock.status == .done ? DC.green : DC.muted)
                    }
                    .buttonStyle(.plain)
                    Text(rock.title).foregroundStyle(rock.status == .done ? DC.muted : DC.text).strikethrough(rock.status == .done)
                    Spacer()
                    Menu {
                        ForEach(Planning.weekDays(m.weekStart), id: \.self) { day in
                            Button("Schedule \(DateText.short(day))") { Task { await m.run(api) { try await api.scheduleRock(rock.id, on: day) } } }
                        }
                        Divider()
                        Button("Drop rock", role: .destructive) { Task { await m.run(api) { try await api.saveRock(id: rock.id, patch: ["status": "dropped"]) } } }
                    } label: { Image(systemName: "calendar.badge.plus").foregroundStyle(DC.dim) }
                }
            }
            if m.rocks(for: role).count < 2 {
                TextField("Add a rock", text: $newRock)
                    .field()
                    .submitLabel(.done)
                    .onSubmit {
                        let t = newRock.trimmingCharacters(in: .whitespaces)
                        guard !t.isEmpty else { return }
                        newRock = ""
                        Task { await m.run(api) { try await api.saveRock(id: nil, patch: ["role_id": role.id, "week_start": m.weekStart, "title": t]) } }
                    }
            }
        }
        .padding(.vertical, 4)
    }
}
