import DailyCommandCore
import SwiftUI

@MainActor @Observable
final class DayModel {
    var date: String
    var payload: DayPayload?
    var loading = false
    var error: String?
    var newTask = ""

    init(date: String = Planning.today()) { self.date = date }

    var day: Day { payload?.day ?? .empty(date) }
    var isToday: Bool { date == (payload?.today ?? Planning.today()) }
    var events: [CalendarEvent] { Planning.events(payload?.events ?? [], on: date) }
    var top3: [PlannerTask] { (payload?.tasks ?? []).filter(\.isTop3).sorted { ($0.top3Position ?? 9) < ($1.top3Position ?? 9) } }
    var tasks: [PlannerTask] { Planning.sort((payload?.tasks ?? []).filter { !$0.isTop3 }, by: .priority) }

    func load(_ api: PlannerAPI) async {
        loading = payload == nil
        defer { loading = false }
        do {
            payload = try await api.day(date)
            error = nil
        } catch { self.error = error.localizedDescription }
    }

    func shift(_ n: Int, _ api: PlannerAPI) async {
        date = Planning.addDays(date, n)
        payload = nil
        await load(api)
    }

    func saveDay(_ patch: sending [String: Any], _ api: PlannerAPI) async {
        do {
            try await api.saveDay(date, patch: patch)
            await load(api)
        } catch { self.error = error.localizedDescription }
    }

    func addTask(_ api: PlannerAPI) async {
        let p = Planning.parseTask(newTask)
        guard !p.title.isEmpty else { return }
        newTask = ""
        var patch: [String: Any] = ["title": p.title, "priority": p.priority, "for_date": date]
        if let tag = p.tag { patch["tag"] = tag }
        do {
            try await api.saveTask(id: nil, patch: patch)
            await load(api)
        } catch { self.error = error.localizedDescription }
    }

    func toggle(_ t: PlannerTask, _ api: PlannerAPI) async {
        do {
            try await api.saveTask(id: t.id, patch: ["status": t.status == .done ? "open" : "done"])
            await load(api)
        } catch { self.error = error.localizedDescription }
    }

    func setTop3(_ t: PlannerTask, _ on: Bool, _ api: PlannerAPI) async {
        if on, top3.count >= 3 { error = "Top 3 is full. Take one off first."; return }
        let pos = on ? ((1...3).first { p in !top3.contains { $0.top3Position == p } } ?? 3) : nil
        do {
            try await api.saveTask(id: t.id, patch: ["is_top3": on, "top3_position": orNull(pos)])
            await load(api)
        } catch { self.error = error.localizedDescription }
    }

    func drop(_ t: PlannerTask, _ api: PlannerAPI) async {
        do {
            try await api.saveTask(id: t.id, patch: ["status": "dropped"])
            await load(api)
        } catch { self.error = error.localizedDescription }
    }

    func carry(_ api: PlannerAPI) async {
        do {
            let n = try await api.carryTasks(from: date)
            await load(api)
            if n == 0 { error = "Nothing open to carry." }
        } catch { self.error = error.localizedDescription }
    }
}

struct DayView: View {
    @Environment(AppModel.self) private var app
    @State private var m = DayModel()

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                header
                if let error = m.error { ErrorBanner(message: error).onTapGesture { m.error = nil } }
                if m.loading {
                    ProgressView().frame(maxWidth: .infinity).padding(40)
                } else if let api = app.api {
                    CalendarCard(m: m, api: api)
                    Top3Card(m: m, api: api)
                    TasksCard(m: m, api: api)
                    CheckInCard(m: m, api: api)
                    GratitudeCard(m: m, api: api)
                    CloseOutCard(m: m, api: api)
                }
            }
            .padding(16)
        }
        .background(DC.bg)
        .navigationTitle("Day")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink { SettingsView() } label: { Image(systemName: "person.crop.circle") }
            }
        }
        .task { if let api = app.api { await m.load(api) } }
        .refreshable { if let api = app.api { await m.load(api) } }
    }

    private var header: some View {
        HStack {
            Button { Task { if let api = app.api { await m.shift(-1, api) } } } label: { Image(systemName: "chevron.left") }
            Spacer()
            VStack(spacing: 2) {
                Text(DateText.long(m.date)).font(DC.Font.headline).foregroundStyle(DC.text)
                if !m.isToday {
                    Button("Today") { Task { if let api = app.api { m.date = Planning.today(); m.payload = nil; await m.load(api) } } }
                        .font(DC.Font.small)
                }
            }
            Spacer()
            Button { Task { if let api = app.api { await m.shift(1, api) } } } label: { Image(systemName: "chevron.right") }
        }
        .padding(.horizontal, 4)
    }
}

// MARK: Cards

struct CalendarCard: View {
    @Bindable var m: DayModel
    let api: PlannerAPI
    @State private var adding = false

    var body: some View {
        Card("Calendar") {
            if m.payload?.accounts.isEmpty ?? true {
                Text("Connect Microsoft 365 in Settings to see your meetings here.").font(DC.Font.small).foregroundStyle(DC.muted)
            } else if m.events.isEmpty {
                Text("Nothing on the calendar.").font(DC.Font.small).foregroundStyle(DC.muted)
            } else {
                ForEach(m.events) { ev in
                    HStack(alignment: .top, spacing: 10) {
                        Text(ev.isAllDay ? "All day" : DateText.time(ev.startAt))
                            .font(DC.Font.small.monospacedDigit()).foregroundStyle(DC.goldText).frame(width: 64, alignment: .leading)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(ev.title).foregroundStyle(DC.text)
                            if let loc = ev.location { Text(loc).font(DC.Font.small).foregroundStyle(DC.muted) }
                            if ev.isPending { Text("Saving to Microsoft 365…").font(DC.Font.small).foregroundStyle(DC.dim) }
                        }
                        Spacer()
                    }
                    .contextMenu {
                        Button("Delete event", role: .destructive) { Task { try? await api.deleteEvent(ev.id); await m.load(api) } }
                    }
                }
            }
        }
        .trailing {
            if !(m.payload?.accounts.isEmpty ?? true) {
                Button { adding = true } label: { Image(systemName: "plus") }
            }
        }
        .sheet(isPresented: $adding) {
            if let acct = m.payload?.accounts.first(where: { $0.status == "active" }) {
                NewEventSheet(date: m.date, accountId: acct.id, api: api) { Task { await m.load(api) } }
            }
        }
    }
}

struct Top3Card: View {
    @Bindable var m: DayModel
    let api: PlannerAPI

    var body: some View {
        Card("Top 3") {
            if m.top3.isEmpty {
                Text("Star up to three tasks that would make today a win.").font(DC.Font.small).foregroundStyle(DC.muted)
            }
            ForEach(m.top3) { t in TaskRow(task: t, m: m, api: api) }
        }
    }
}

struct TasksCard: View {
    @Bindable var m: DayModel
    let api: PlannerAPI

    var body: some View {
        Card("Tasks") {
            HStack {
                TextField("Add a task  (!1 urgent, #tag)", text: $m.newTask)
                    .submitLabel(.done)
                    .onSubmit { Task { await m.addTask(api) } }
                    .field()
                Button { Task { await m.addTask(api) } } label: { Image(systemName: "plus.circle.fill").font(.title2) }
                    .disabled(m.newTask.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            ForEach(m.tasks) { t in TaskRow(task: t, m: m, api: api) }
            if m.tasks.isEmpty, m.top3.isEmpty {
                Text("Nothing here yet.").font(DC.Font.small).foregroundStyle(DC.muted)
            }
        }
        .trailing {
            Button("Carry open →") { Task { await m.carry(api) } }.font(DC.Font.small)
        }
    }
}

struct TaskRow: View {
    let task: PlannerTask
    @Bindable var m: DayModel
    let api: PlannerAPI

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Button { Task { await m.toggle(task, api) } } label: {
                Image(systemName: task.status == .done ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(task.status == .done ? DC.green : DC.muted)
            }
            .buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .foregroundStyle(task.status == .done ? DC.muted : DC.text)
                    .strikethrough(task.status == .done)
                HStack(spacing: 8) {
                    if task.priority == 1 { Text("!1").foregroundStyle(DC.red) }
                    if task.priority == 3 { Text("!3").foregroundStyle(DC.dim) }
                    if let tag = task.tag { Text("#\(tag)").foregroundStyle(DC.blue) }
                    if task.carriedCount > 0 { Text("carried ×\(task.carriedCount)").foregroundStyle(DC.orange) }
                    if task.isFromReminders { Text(task.externalList ?? "Reminders").foregroundStyle(DC.dim) }
                }
                .font(DC.Font.small)
            }
            Spacer()
            if !task.isFromReminders {
                Button { Task { await m.setTop3(task, !task.isTop3, api) } } label: {
                    Image(systemName: task.isTop3 ? "star.fill" : "star").foregroundStyle(task.isTop3 ? DC.gold : DC.dim)
                }
                .buttonStyle(.plain)
            }
        }
        .contextMenu {
            if !task.isFromReminders {
                Button("Drop task", role: .destructive) { Task { await m.drop(task, api) } }
            }
        }
    }
}

struct CheckInCard: View {
    @Bindable var m: DayModel
    let api: PlannerAPI
    @State private var phase: Phase = Planning.phase()

    var body: some View {
        Card("Check-in") {
            Picker("Phase", selection: $phase) {
                ForEach(Phase.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            ForEach(Metric.allCases, id: \.self) { metric in
                let cmp = Planning.compare(day: m.payload?.day, previousDay: m.payload?.previousDay, phase: phase, metric: metric)
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(metric.rawValue.capitalized).font(DC.Font.small).foregroundStyle(DC.text2)
                        Spacer()
                        if let v = cmp.value { Text("\(cmp.label): \(v)").font(DC.Font.small).foregroundStyle(DC.dim) }
                    }
                    Scale(value: m.day.metric(metric, phase)) { v in
                        Task { await m.saveDay([metric.column(phase): orNull(v), "\(phase.rawValue)_checked_at": ServerDate.iso(Date())], api) }
                    }
                }
            }
            if phase == .am {
                HStack {
                    Text("Sleep").font(DC.Font.small).foregroundStyle(DC.text2)
                    Spacer()
                    Stepper(value: Binding(get: { m.day.sleepMinutes ?? 0 }, set: { v in Task { await m.saveDay(["sleep_minutes": v], api) } }),
                            in: 0...1440, step: 15) {
                        Text(sleepText(m.day.sleepMinutes)).font(DC.Font.small.monospacedDigit())
                    }
                }
                Toggle("Workout planned", isOn: Binding(get: { m.day.workoutPlanned }, set: { v in Task { await m.saveDay(["workout_planned": v], api) } }))
                    .font(DC.Font.small)
                EditRow(label: "Intention for the day", value: m.day.intention) { v in await m.saveDay(["intention": orNull(v.isEmpty ? nil : v)], api) }
            }
        }
    }

    private func sleepText(_ min: Int?) -> String {
        guard let min else { return "—" }
        return "\(min / 60)h \(String(format: "%02d", min % 60))m"
    }
}

struct GratitudeCard: View {
    @Bindable var m: DayModel
    let api: PlannerAPI

    var body: some View {
        Card("Grateful for") {
            ForEach(0..<3, id: \.self) { i in
                let items = m.day.gratitude
                NavigationLink {
                    TextEditorScreen(title: "Grateful for", text: i < items.count ? items[i] : "") { v in
                        var next = items
                        while next.count <= i { next.append("") }
                        next[i] = v
                        while next.last == "" { next.removeLast() }
                        await m.saveDay(["gratitude": next], api)
                    }
                } label: {
                    HStack {
                        Text("\(i + 1).").foregroundStyle(DC.goldText)
                        Text(i < items.count && !items[i].isEmpty ? items[i] : "Add one").foregroundStyle(i < items.count && !items[i].isEmpty ? DC.text : DC.dim)
                        Spacer()
                    }
                }
            }
        }
    }
}

struct CloseOutCard: View {
    @Bindable var m: DayModel
    let api: PlannerAPI

    var body: some View {
        Card("Close out") {
            EditRow(label: "Win", value: m.day.win) { v in await m.saveDay(["win": orNull(v.isEmpty ? nil : v)], api) }
            EditRow(label: "Lesson", value: m.day.lesson) { v in await m.saveDay(["lesson": orNull(v.isEmpty ? nil : v)], api) }
            EditRow(label: "One thing for tomorrow", value: m.day.tomorrowOne) { v in await m.saveDay(["tomorrow_one": orNull(v.isEmpty ? nil : v)], api) }
            VStack(alignment: .leading, spacing: 6) {
                Text("Day rating").font(DC.Font.small).foregroundStyle(DC.text2)
                Scale(value: m.day.dayRating) { v in Task { await m.saveDay(["day_rating": orNull(v)], api) } }
            }
            Toggle("Workout done", isOn: Binding(get: { m.day.workoutDone }, set: { v in Task { await m.saveDay(["workout_done": v], api) } }))
                .font(DC.Font.small)
            if let closed = m.day.closedAt {
                Text("Closed \(closed.formatted(date: .omitted, time: .shortened))").font(DC.Font.small).foregroundStyle(DC.green)
            } else {
                Button {
                    Task {
                        await m.saveDay(["closed_at": ServerDate.iso(Date())], api)
                        await m.carry(api)
                    }
                } label: { Text("Close the day and carry open tasks").frame(maxWidth: .infinity) }
                    .buttonStyle(.borderedProminent)
            }
        }
    }
}

/// A labeled value that opens a full-screen editor.
struct EditRow: View {
    let label: String
    let value: String?
    let save: (String) async -> Void

    var body: some View {
        NavigationLink {
            TextEditorScreen(title: label, text: value ?? "", save: save)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(DC.Font.small).foregroundStyle(DC.text2)
                Text(value?.isEmpty == false ? value! : "Tap to write")
                    .foregroundStyle(value?.isEmpty == false ? DC.text : DC.dim)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Full-screen text entry that saves on Done.
struct TextEditorScreen: View {
    let title: String
    @State var text: String
    let save: (String) async -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        TextEditor(text: $text)
            .scrollContentBackground(.hidden)
            .padding(12)
            .background(DC.bg)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { Task { await save(text.trimmingCharacters(in: .whitespacesAndNewlines)); dismiss() } }
                }
            }
    }
}

struct NewEventSheet: View {
    let date: String
    let accountId: String
    let api: PlannerAPI
    let done: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var start: Date
    @State private var end: Date
    @State private var allDay = false
    @State private var location = ""
    @State private var error: String?

    init(date: String, accountId: String, api: PlannerAPI, done: @escaping () -> Void) {
        self.date = date; self.accountId = accountId; self.api = api; self.done = done
        let day = Planning.date(date).map { Calendar.current.startOfDay(for: Date(timeIntervalSince1970: $0.timeIntervalSince1970 + 12 * 3600)) } ?? Calendar.current.startOfDay(for: Date())
        let s = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: day) ?? day
        _start = State(initialValue: s)
        _end = State(initialValue: s.addingTimeInterval(3600))
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Title", text: $title)
                Toggle("All day", isOn: $allDay)
                DatePicker("Starts", selection: $start, displayedComponents: allDay ? [.date] : [.date, .hourAndMinute])
                DatePicker("Ends", selection: $end, in: start..., displayedComponents: allDay ? [.date] : [.date, .hourAndMinute])
                TextField("Location", text: $location)
                if let error { Text(error).foregroundStyle(DC.red) }
            }
            .navigationTitle("New event")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        Task {
                            do {
                                _ = try await api.saveEvent(id: nil, accountId: accountId, title: title, startAt: start, endAt: end,
                                                            isAllDay: allDay, location: location.isEmpty ? nil : location, attendees: [])
                                done(); dismiss()
                            } catch { self.error = error.localizedDescription }
                        }
                    }
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}
