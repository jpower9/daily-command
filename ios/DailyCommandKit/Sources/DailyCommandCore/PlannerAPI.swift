import Foundation

/// The client for ExecClone's planner actions on `mobile-bootstrap`
/// (execclone-apps `contract/client-api.md` §22). Every call is one POST with
/// an `action`, authorized by the signed-in user's token; the server scopes
/// every row to that user. The app never reads a database table directly.
public final class PlannerAPI: @unchecked Sendable {
    public let auth: AuthClient
    private let transport: HTTPTransport
    private let lock = NSLock()
    private var _session: Session

    public init(session: Session, auth: AuthClient, transport: HTTPTransport = URLSessionTransport()) {
        _session = session
        self.auth = auth
        self.transport = transport
    }

    public var session: Session { lock.withLock { _session } }
    public var userId: String { session.userId }

    // MARK: Transport

    @discardableResult
    public func call(_ action: String, _ params: [String: Any] = [:]) async throws -> JSON {
        var payload = params
        payload["action"] = action
        return try await perform(payload: payload, retried: false)
    }

    private func perform(payload: [String: Any], retried: Bool) async throws -> JSON {
        let current = session
        var request = URLRequest(url: auth.environment.appAPIURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(current.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(auth.environment.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        let (data, status) = try await transport.send(request)
        let body = (try? JSON(data: data)) ?? .null
        if status == 401, !retried {
            let refreshed = try await TokenRefresher.shared.refresh(current: current, auth: auth)
            lock.withLock { _session = refreshed }
            return try await perform(payload: payload, retried: true)
        }
        guard status == 200 else {
            throw APIError.server(status: status, message: body["error"].nonEmptyString ?? "")
        }
        return body
    }

    // MARK: Day

    public func day(_ date: String? = nil) async throws -> DayPayload {
        var p: [String: Any] = [:]
        if let date { p["date"] = date }
        return DayPayload(try await call("plannerDay", p))
    }

    public func saveDay(_ date: String, patch: [String: Any]) async throws {
        try await call("plannerSaveDay", ["date": date, "patch": patch])
    }

    /// Creates (id nil) or updates a task. Returns the task id.
    @discardableResult
    public func saveTask(id: String?, patch: [String: Any]) async throws -> String {
        var p: [String: Any] = ["patch": patch]
        if let id { p["id"] = id }
        let r = try await call("plannerTaskSave", p)
        return r["id"].string ?? id ?? ""
    }

    /// Moves everything still open on `date` to the next day. Returns how many moved.
    @discardableResult
    public func carryTasks(from date: String) async throws -> Int {
        try await call("plannerTaskCarry", ["date": date])["carried"].int ?? 0
    }

    // MARK: Calendar

    public func saveEvent(id: String?, accountId: String?, title: String, startAt: Date, endAt: Date,
                          isAllDay: Bool, location: String?, attendees: [String]) async throws -> String {
        var p: [String: Any] = ["title": title, "startAt": ServerDate.iso(startAt), "endAt": ServerDate.iso(endAt),
                                "isAllDay": isAllDay, "attendees": attendees]
        if let id { p["id"] = id }
        if let accountId { p["accountId"] = accountId }
        if let location { p["location"] = location }
        return try await call("plannerEventSave", p)["id"].string ?? id ?? ""
    }

    public func deleteEvent(_ id: String) async throws {
        try await call("plannerEventDelete", ["id": id])
    }

    public func syncNow() async throws {
        try await call("plannerSyncNow")
    }

    /// Asks the server for a one-time Microsoft sign-in URL; the app opens it in a web view and the
    /// browser returns to `returnTo` with `?calendar=connected|denied|error`.
    public func calendarConnectURL(returnTo: String) async throws -> URL? {
        try await call("plannerCalendarConnectStart", ["returnTo": returnTo])["url"].string.flatMap(URL.init)
    }

    public func disconnectCalendar(_ accountId: String) async throws {
        try await call("plannerCalendarDisconnect", ["accountId": accountId])
    }

    // MARK: Reminders (Apple, via the server's CalDAV sync)

    public func reminders() async throws -> RemindersStatus {
        RemindersStatus(try await call("plannerReminders"))
    }

    /// A one-time URL the app posts the Apple ID + app-specific password to. The credentials go
    /// straight to ExecClone's reminders function over TLS and are stored encrypted per user; the
    /// app never keeps them.
    public func remindersConnectURL(returnTo: String) async throws -> URL? {
        try await call("plannerRemindersConnectStart", ["returnTo": returnTo])["url"].string.flatMap(URL.init)
    }

    public func setReminderLists(_ lists: [String]) async throws {
        try await call("plannerRemindersSetLists", ["lists": lists])
    }

    public func disconnectReminders() async throws {
        try await call("plannerRemindersDisconnect")
    }

    // MARK: Week

    public func week(_ weekStart: String? = nil) async throws -> WeekPayload {
        var p: [String: Any] = [:]
        if let weekStart { p["weekStart"] = weekStart }
        return WeekPayload(try await call("plannerWeek", p))
    }

    public func saveWeek(_ weekStart: String, patch: [String: Any]) async throws {
        try await call("plannerWeekSave", ["weekStart": weekStart, "patch": patch])
    }

    @discardableResult
    public func saveRole(id: String?, patch: [String: Any]) async throws -> String {
        var p: [String: Any] = ["patch": patch]
        if let id { p["id"] = id }
        return try await call("plannerRoleSave", p)["id"].string ?? id ?? ""
    }

    @discardableResult
    public func saveRock(id: String?, patch: [String: Any]) async throws -> String {
        var p: [String: Any] = ["patch": patch]
        if let id { p["id"] = id }
        return try await call("plannerRockSave", p)["id"].string ?? id ?? ""
    }

    /// Toggles a rock onto `date` as a task (removes it when already scheduled there).
    public func scheduleRock(_ rockId: String, on date: String, top3Position: Int? = nil) async throws {
        var p: [String: Any] = ["rockId": rockId, "date": date]
        if let top3Position { p["top3Position"] = top3Position }
        try await call("plannerRockSchedule", p)
    }

    @discardableResult
    public func carryRocks(from weekStart: String) async throws -> Int {
        try await call("plannerRockCarry", ["weekStart": weekStart])["carried"].int ?? 0
    }

    // MARK: Quarter

    public func quarter(_ quarter: String? = nil) async throws -> QuarterPayload {
        var p: [String: Any] = [:]
        if let quarter { p["quarter"] = quarter }
        return QuarterPayload(try await call("plannerQuarter", p))
    }

    public func saveQuarter(_ quarter: String, patch: [String: Any]) async throws {
        try await call("plannerQuarterSave", ["quarter": quarter, "patch": patch])
    }

    @discardableResult
    public func saveQuarterRock(id: String?, patch: [String: Any]) async throws -> String {
        var p: [String: Any] = ["patch": patch]
        if let id { p["id"] = id }
        return try await call("plannerQuarterRockSave", p)["id"].string ?? id ?? ""
    }

    // MARK: Goals

    public func goals(year: Int? = nil) async throws -> GoalsPayload {
        var p: [String: Any] = [:]
        if let year { p["year"] = year }
        return GoalsPayload(try await call("plannerGoals", p))
    }

    @discardableResult
    public func saveGoal(id: String?, patch: [String: Any]) async throws -> String {
        var p: [String: Any] = ["patch": patch]
        if let id { p["id"] = id }
        return try await call("plannerGoalSave", p)["id"].string ?? id ?? ""
    }

    public func updateGoal(_ goalId: String, value: Double?, note: String?, date: String? = nil) async throws {
        var p: [String: Any] = ["goalId": goalId]
        if let value { p["value"] = value }
        if let note { p["note"] = note }
        if let date { p["date"] = date }
        try await call("plannerGoalUpdate", p)
    }

    // MARK: Journal

    public func journal() async throws -> JournalPayload {
        JournalPayload(try await call("plannerJournal"))
    }

    @discardableResult
    public func saveNotebook(id: String?, patch: [String: Any]) async throws -> String {
        var p: [String: Any] = ["patch": patch]
        if let id { p["id"] = id }
        return try await call("plannerNotebookSave", p)["id"].string ?? id ?? ""
    }

    public func archiveNotebook(_ id: String) async throws {
        try await call("plannerNotebookArchive", ["id": id])
    }

    @discardableResult
    public func saveNote(id: String?, patch: [String: Any]) async throws -> String {
        var p: [String: Any] = ["patch": patch]
        if let id { p["id"] = id }
        return try await call("plannerNoteSave", p)["id"].string ?? id ?? ""
    }
}

extension ServerDate {
    /// ISO-8601 UTC with milliseconds, the form the server validates and stores.
    public static func iso(_ date: Date) -> String {
        date.formatted(Date.ISO8601FormatStyle(includingFractionalSeconds: true, timeZone: TimeZone(identifier: "UTC")!))
    }
}
