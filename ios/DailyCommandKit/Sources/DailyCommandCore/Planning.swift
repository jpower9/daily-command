import Foundation

// Date math on `yyyy-MM-dd` strings, check-in phases, task parsing and the quarter scorecard.
// Mirrors execclone-apps `web/src/lib/planner.ts` so both apps agree on every number.

public enum Phase: String, Sendable, CaseIterable {
    case am, md, pm

    public var title: String {
        switch self {
        case .am: "Morning"
        case .md: "Midday"
        case .pm: "Evening"
        }
    }
}

public enum Metric: String, Sendable, CaseIterable {
    case energy, focus, mood, stress

    /// The database column for a metric in a phase (`energy`, `md_energy`, `pm_energy`).
    public func column(_ phase: Phase) -> String { phase == .am ? rawValue : "\(phase.rawValue)_\(rawValue)" }
}

public enum Planning {
    nonisolated(unsafe) static let utc: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        c.firstWeekday = 2
        return c
    }()

    /// Parses `yyyy-MM-dd` as midnight UTC (dates are opaque labels; UTC keeps arithmetic exact).
    public static func date(_ ymd: String) -> Date? {
        let parts = ymd.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return utc.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    public static func ymd(_ date: Date, calendar: Calendar = utc) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// Today in the device's zone.
    public static func today(_ now: Date = Date(), calendar: Calendar = .current) -> String { ymd(now, calendar: calendar) }

    public static func addDays(_ ymd: String, _ n: Int) -> String {
        guard let d = date(ymd), let r = utc.date(byAdding: .day, value: n, to: d) else { return ymd }
        return self.ymd(r)
    }

    public static func daysBetween(_ a: String, _ b: String) -> Int {
        guard let da = date(a), let db = date(b) else { return 0 }
        return utc.dateComponents([.day], from: da, to: db).day ?? 0
    }

    /// The Monday on or before `ymd`.
    public static func monday(_ ymd: String) -> String {
        guard let d = date(ymd) else { return ymd }
        let dow = (utc.component(.weekday, from: d) + 5) % 7 // Mon 0 … Sun 6
        return addDays(ymd, -dow)
    }

    public static func weekDays(_ weekStart: String) -> [String] { (0..<7).map { addDays(weekStart, $0) } }

    /// `2026-Q4`
    public static func quarterOf(_ ymd: String) -> String {
        let y = ymd.prefix(4), m = Int(ymd.dropFirst(5).prefix(2)) ?? 1
        return "\(y)-Q\((m - 1) / 3 + 1)"
    }

    public static func quarterRange(_ q: String) -> (start: String, end: String) {
        let y = Int(q.prefix(4)) ?? 2000, n = Int(q.suffix(1)) ?? 1
        let sm = (n - 1) * 3 + 1
        let start = String(format: "%04d-%02d-01", y, sm)
        let end = utc.date(from: DateComponents(year: y, month: sm + 3, day: 0)).map(ymd) ?? start
        return (start, end)
    }

    public static func shiftQuarter(_ q: String, by n: Int) -> String {
        let y = Int(q.prefix(4)) ?? 2000, i = (Int(q.suffix(1)) ?? 1) - 1 + n
        let yy = y + Int((Double(i) / 4).rounded(.down))
        return "\(yy)-Q\(((i % 4) + 4) % 4 + 1)"
    }

    public static func quarterTitle(_ q: String) -> String { "Q\(q.suffix(1)) \(q.prefix(4))" }

    // MARK: Phases

    /// AM before 13:00, midday until 18:00, then evening.
    public static func phase(hour: Int) -> Phase { hour < 13 ? .am : hour < 18 ? .md : .pm }

    public static func phase(at now: Date = Date(), calendar: Calendar = .current) -> Phase {
        phase(hour: calendar.component(.hour, from: now))
    }

    /// The reading to compare against: the previous phase today, or yesterday's evening for the morning.
    public static func compare(day: Day?, previousDay: Day?, phase: Phase, metric: Metric) -> (value: Int?, label: String) {
        switch phase {
        case .am: return (previousDay?.metric(metric, .pm), "yesterday's PM")
        case .md: return (day?.metric(metric, .am), "this morning")
        case .pm: return (day?.metric(metric, .md) ?? day?.metric(metric, .am), day?.metric(metric, .md) != nil ? "this afternoon" : "this morning")
        }
    }

    // MARK: Events

    /// Events that overlap the local day `ymd` in `zone` (the server sends a 48 h window).
    public static func events(_ events: [CalendarEvent], on ymd: String, zone: TimeZone = .current) -> [CalendarEvent] {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zone
        let parts = ymd.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, let start = cal.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])),
              let end = cal.date(byAdding: .day, value: 1, to: start) else { return [] }
        return events.filter { ev in
            if ev.isAllDay {
                // All-day events are stored at UTC midnight; compare by calendar date.
                return Planning.ymd(ev.startAt) <= ymd && ymd < Planning.ymd(ev.endAt)
            }
            return ev.startAt < end && ev.endAt > start
        }.sorted { ($0.isAllDay ? 0 : 1, $0.startAt) < ($1.isAllDay ? 0 : 1, $1.startAt) }
    }

    // MARK: Tasks

    public struct ParsedTask: Equatable, Sendable {
        public var title: String
        public var priority: Int
        public var tag: String?
    }

    /// `"!1 Call bank #money"` → priority 1, tag `money`, title `Call bank`.
    public static func parseTask(_ raw: String) -> ParsedTask {
        var priority = 2
        var tag: String?
        var words: [String] = []
        for w in raw.split(whereSeparator: \.isWhitespace) {
            if w.count == 2, w.first == "!", let p = Int(w.dropFirst()), (1...3).contains(p) { priority = p; continue }
            if w.first == "#", w.count > 1, w.count <= 61, w.dropFirst().allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" }) {
                tag = w.dropFirst().lowercased(); continue
            }
            words.append(String(w))
        }
        return ParsedTask(title: words.joined(separator: " "), priority: priority, tag: tag)
    }

    public enum TaskSort: String, CaseIterable, Sendable {
        case priority, carried, created, title, due
        public var label: String {
            switch self {
            case .priority: "Priority"
            case .carried: "Carried longest"
            case .created: "Newest"
            case .title: "A–Z"
            case .due: "Due date"
            }
        }
    }

    public static func sort(_ tasks: [PlannerTask], by: TaskSort) -> [PlannerTask] {
        tasks.sorted { a, b in
            let oa = a.status == .done ? 1 : 0, ob = b.status == .done ? 1 : 0
            if oa != ob { return oa < ob }
            switch by {
            case .priority: return a.priority != b.priority ? a.priority < b.priority : a.sortOrder < b.sortOrder
            case .carried: return a.carriedCount > b.carriedCount
            case .created: return a.createdAt > b.createdAt
            case .title: return a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
            case .due: return (a.dueDate ?? "9999") < (b.dueDate ?? "9999")
            }
        }
    }

    // MARK: Scorecard

    public struct Scorecard: Equatable, Sendable {
        public var daysClosed: Int
        public var daysSoFar: Int
        public var top3Pct: Int?
        public var tasksDone: Int
        public var rocksDone: Int
        public var rocksSet: Int
        public var avgEnergy: Double?
        public var avgMood: Double?
        public var workouts: Int
    }

    public static func scorecard(_ p: QuarterPayload) -> Scorecard {
        let endSoFar = p.today < p.end ? p.today : p.end
        let daysSoFar = p.today < p.start ? 0 : daysBetween(p.start, endSoFar) + 1
        let top3 = p.tasks.filter(\.isTop3)
        let top3Pct: Int? = top3.isEmpty ? nil : Int((Double(top3.filter { $0.status == .done }.count) / Double(top3.count) * 100).rounded())
        func avg(_ xs: [Int?]) -> Double? {
            let v = xs.compactMap { $0 }
            return v.isEmpty ? nil : (Double(v.reduce(0, +)) / Double(v.count) * 10).rounded() / 10
        }
        return Scorecard(
            daysClosed: p.days.filter { $0.closedAt != nil }.count,
            daysSoFar: daysSoFar,
            top3Pct: top3Pct,
            tasksDone: p.tasks.filter { $0.status == .done }.count,
            rocksDone: p.weekRocks.filter { $0.status == .done }.count,
            rocksSet: p.weekRocks.count,
            avgEnergy: avg(p.days.flatMap { [$0.energy, $0.pmEnergy] }),
            avgMood: avg(p.days.flatMap { [$0.mood, $0.pmMood] }),
            workouts: p.days.filter(\.workoutDone).count)
    }

    /// 0–100, or nil when the goal has no numeric start/target/current.
    public static func progress(start: Double?, current: Double?, target: Double?) -> Int? {
        guard let start, let current, let target, target != start else { return nil }
        return max(0, min(100, Int(((current - start) / (target - start) * 100).rounded())))
    }
}
