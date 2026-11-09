import Foundation

// Planner rows as the client API returns them (contract/client-api.md §22). Read through `JSON`
// so one odd field never drops a whole list; dates stay as `yyyy-MM-dd` strings because the
// planner is organized by the user's local calendar day, not by instants.

public enum TaskStatus: String, Sendable, CaseIterable { case open, done, dropped }
public enum GoalStatus: String, Sendable, CaseIterable { case active, done, paused, dropped }
public enum NotebookKind: String, Sendable, CaseIterable { case journal, note }

public struct Day: Sendable, Equatable {
    public var forDate: String
    public var energy, focus, mood, stress: Int?
    public var mdEnergy, mdFocus, mdMood, mdStress: Int?
    public var pmEnergy, pmFocus, pmMood, pmStress: Int?
    public var amCheckedAt, mdCheckedAt, pmCheckedAt: Date?
    public var sleepMinutes: Int?
    public var workoutPlanned, workoutDone: Bool
    public var gratitude: [String]
    public var intention, win, lesson, tomorrowOne, notes: String?
    public var dayRating: Int?
    public var closedAt: Date?

    public init(_ j: JSON) {
        forDate = j["for_date"].string ?? ""
        energy = j["energy"].int; focus = j["focus"].int; mood = j["mood"].int; stress = j["stress"].int
        mdEnergy = j["md_energy"].int; mdFocus = j["md_focus"].int; mdMood = j["md_mood"].int; mdStress = j["md_stress"].int
        pmEnergy = j["pm_energy"].int; pmFocus = j["pm_focus"].int; pmMood = j["pm_mood"].int; pmStress = j["pm_stress"].int
        amCheckedAt = ServerDate.parse(j["am_checked_at"].string)
        mdCheckedAt = ServerDate.parse(j["md_checked_at"].string)
        pmCheckedAt = ServerDate.parse(j["pm_checked_at"].string)
        sleepMinutes = j["sleep_minutes"].int
        workoutPlanned = j["workout_planned"].bool ?? false
        workoutDone = j["workout_done"].bool ?? false
        gratitude = j["gratitude"].array.compactMap(\.string)
        intention = j["intention"].nonEmptyString; win = j["win"].nonEmptyString; lesson = j["lesson"].nonEmptyString
        tomorrowOne = j["tomorrow_one"].nonEmptyString; notes = j["notes"].nonEmptyString
        dayRating = j["day_rating"].int
        closedAt = ServerDate.parse(j["closed_at"].string)
    }

    public static func empty(_ date: String) -> Day { Day(.object(["for_date": .string(date)])) }

    /// Reads a check-in metric for a phase (`energy`, `md_energy`, `pm_energy`…).
    public func metric(_ m: Metric, _ phase: Phase) -> Int? {
        switch (phase, m) {
        case (.am, .energy): energy
        case (.am, .focus): focus
        case (.am, .mood): mood
        case (.am, .stress): stress
        case (.md, .energy): mdEnergy
        case (.md, .focus): mdFocus
        case (.md, .mood): mdMood
        case (.md, .stress): mdStress
        case (.pm, .energy): pmEnergy
        case (.pm, .focus): pmFocus
        case (.pm, .mood): pmMood
        case (.pm, .stress): pmStress
        }
    }

    public func checkedAt(_ phase: Phase) -> Date? {
        switch phase {
        case .am: amCheckedAt
        case .md: mdCheckedAt
        case .pm: pmCheckedAt
        }
    }
}

public struct PlannerTask: Sendable, Equatable, Identifiable {
    public var id: String
    public var title: String
    public var notes: String?
    public var status: TaskStatus
    public var priority: Int
    public var tag: String?
    public var forDate: String
    public var originDate: String
    public var dueDate: String?
    public var carriedCount: Int
    public var isTop3: Bool
    public var top3Position: Int?
    public var sortOrder: Int
    public var scheduledAt, completedAt: Date?
    public var source: String
    public var externalList: String?
    public var rockId: String?
    public var createdAt: Date

    public init(_ j: JSON) {
        id = j["id"].idString ?? ""
        title = j["title"].string ?? ""
        notes = j["notes"].nonEmptyString
        status = TaskStatus(rawValue: j["status"].string ?? "") ?? .open
        priority = j["priority"].int ?? 2
        tag = j["tag"].nonEmptyString
        forDate = j["for_date"].string ?? ""
        originDate = j["origin_date"].string ?? forDate
        dueDate = j["due_date"].nonEmptyString
        carriedCount = j["carried_count"].int ?? 0
        isTop3 = j["is_top3"].bool ?? false
        top3Position = j["top3_position"].int
        sortOrder = j["sort_order"].int ?? 0
        scheduledAt = ServerDate.parse(j["scheduled_at"].string)
        completedAt = ServerDate.parse(j["completed_at"].string)
        source = j["source"].string ?? "dashboard"
        externalList = j["external_list"].nonEmptyString
        rockId = j["rock_id"].nonEmptyString
        createdAt = ServerDate.parse(j["created_at"].string) ?? .distantPast
    }

    /// Reminders that came from Apple are shown but not edited here; Apple stays their source of truth.
    public var isFromReminders: Bool { source == "reminders" }
}

public struct CalendarAccount: Sendable, Equatable, Identifiable {
    public var id: String
    public var provider: String
    public var email: String?
    public var displayName: String?
    public var color: String?
    public var status: String
    public var lastSyncAt: Date?
    public var lastError: String?

    public init(_ j: JSON) {
        id = j["id"].idString ?? ""
        provider = j["provider"].string ?? "microsoft"
        email = j["email"].nonEmptyString
        displayName = j["display_name"].nonEmptyString
        color = j["color"].nonEmptyString
        status = j["status"].string ?? "active"
        lastSyncAt = ServerDate.parse(j["last_sync_at"].string)
        lastError = j["last_error"].nonEmptyString
    }
}

public struct CalendarEvent: Sendable, Equatable, Identifiable {
    public var id: String
    public var accountId: String
    public var externalId: String
    public var title: String
    public var startAt, endAt: Date
    public var isAllDay: Bool
    public var location: String?
    public var bodyPreview: String?
    public var showAs: String?
    public var webLink: URL?
    public var organizerEmail: String?
    public var isCancelled: Bool
    public var attendees: [Attendee]

    public struct Attendee: Sendable, Equatable {
        public var email: String
        public var name: String
        public var type: String
        public init(email: String, name: String, type: String) { self.email = email; self.name = name; self.type = type }
    }

    public init(_ j: JSON) {
        id = j["id"].idString ?? ""
        accountId = j["account_id"].idString ?? ""
        externalId = j["external_id"].string ?? ""
        title = j["title"].string ?? ""
        startAt = ServerDate.parse(j["start_at"].string) ?? .distantPast
        endAt = ServerDate.parse(j["end_at"].string) ?? startAt
        isAllDay = j["is_all_day"].bool ?? false
        location = j["location"].nonEmptyString
        bodyPreview = j["body_preview"].nonEmptyString
        showAs = j["show_as"].nonEmptyString
        webLink = j["web_link"].nonEmptyString.flatMap(URL.init)
        organizerEmail = j["organizer_email"].nonEmptyString
        isCancelled = j["is_cancelled"].bool ?? false
        attendees = j["attendees"].array.map {
            let email = $0["email"].string ?? ""
            return Attendee(email: email, name: $0["name"].string ?? email, type: $0["type"].string ?? "required")
        }
    }

    /// Still waiting for the server to create it in Microsoft 365.
    public var isPending: Bool { externalId.hasPrefix("pending:") }
}

public struct DayPayload: Sendable, Equatable {
    public var date: String
    public var today: String
    public var timeZone: String
    public var day: Day?
    public var previousDay: Day?
    public var tasks: [PlannerTask]
    public var accounts: [CalendarAccount]
    public var events: [CalendarEvent]

    public init(_ j: JSON) {
        date = j["date"].string ?? ""
        today = j["today"].string ?? date
        timeZone = j["timeZone"].string ?? TimeZone.current.identifier
        day = j["day"].isNull ? nil : Day(j["day"])
        previousDay = j["previousDay"].isNull ? nil : Day(j["previousDay"])
        tasks = j["tasks"].array.map(PlannerTask.init)
        accounts = j["accounts"].array.map(CalendarAccount.init)
        events = j["events"].array.map(CalendarEvent.init)
    }
}

public struct RemindersStatus: Sendable, Equatable {
    public struct Account: Sendable, Equatable {
        public var id: String
        public var provider: String
        public var lists: [String]
        public var status: String
        public var lastSyncAt: Date?
        public var lastError: String?
    }
    public var account: Account?
    public var available: [String]

    public init(_ j: JSON) {
        let a = j["account"]
        account = a.isNull ? nil : Account(id: a["id"].idString ?? "", provider: a["provider"].string ?? "apple",
                                           lists: a["lists"].array.compactMap(\.string), status: a["status"].string ?? "active",
                                           lastSyncAt: ServerDate.parse(a["lastSyncAt"].string), lastError: a["lastError"].nonEmptyString)
        available = j["available"].array.compactMap(\.string)
    }
}

// MARK: Week

public struct Week: Sendable, Equatable {
    public var weekStart: String
    public var theme, wins, risk, carryForward: String?
    public var closedAt: Date?

    public init(_ j: JSON) {
        weekStart = j["week_start"].string ?? ""
        theme = j["theme"].nonEmptyString; wins = j["wins"].nonEmptyString
        risk = j["risk"].nonEmptyString; carryForward = j["carry_forward"].nonEmptyString
        closedAt = ServerDate.parse(j["closed_at"].string)
    }
}

public struct Role: Sendable, Equatable, Identifiable {
    public var id: String
    public var name: String
    public var note: String?
    public var sortOrder: Int

    public init(_ j: JSON) {
        id = j["id"].idString ?? ""
        name = j["name"].string ?? ""
        note = j["note"].nonEmptyString
        sortOrder = j["sort_order"].int ?? 0
    }
}

public struct Rock: Sendable, Equatable, Identifiable {
    public var id: String
    public var roleId: String
    public var weekStart: String
    public var title: String
    public var status: TaskStatus
    public var sortOrder: Int
    public var completedAt: Date?
    public var quarterRockId: String?

    public init(_ j: JSON) {
        id = j["id"].idString ?? ""
        roleId = j["role_id"].idString ?? ""
        weekStart = j["week_start"].string ?? ""
        title = j["title"].string ?? ""
        status = TaskStatus(rawValue: j["status"].string ?? "") ?? .open
        sortOrder = j["sort_order"].int ?? 0
        completedAt = ServerDate.parse(j["completed_at"].string)
        quarterRockId = j["quarter_rock_id"].nonEmptyString
    }
}

public struct DaySummary: Sendable, Equatable {
    public var forDate: String
    public var energy, mood, pmEnergy, pmMood, dayRating: Int?
    public var closedAt: Date?
    public var workoutDone: Bool
    public var sleepMinutes: Int?
    public var intention: String?

    public init(_ j: JSON) {
        forDate = j["for_date"].string ?? ""
        energy = j["energy"].int; mood = j["mood"].int
        pmEnergy = j["pm_energy"].int; pmMood = j["pm_mood"].int
        dayRating = j["day_rating"].int
        closedAt = ServerDate.parse(j["closed_at"].string)
        workoutDone = j["workout_done"].bool ?? false
        sleepMinutes = j["sleep_minutes"].int
        intention = j["intention"].nonEmptyString
    }
}

public struct QuarterRock: Sendable, Equatable, Identifiable {
    public var id: String
    public var quarter: String
    public var goalId: String?
    public var title: String
    public var status: TaskStatus
    public var milestones: [Milestone]
    public var sortOrder: Int

    public struct Milestone: Sendable, Equatable {
        public var title: String
        public var done: Bool
        public init(title: String, done: Bool) { self.title = title; self.done = done }
        public var json: [String: Any] { ["title": title, "done": done] }
    }

    public init(_ j: JSON) {
        id = j["id"].idString ?? ""
        quarter = j["quarter"].string ?? ""
        goalId = j["goal_id"].nonEmptyString
        title = j["title"].string ?? ""
        status = TaskStatus(rawValue: j["status"].string ?? "") ?? .open
        milestones = j["milestones"].array.map { Milestone(title: $0["title"].string ?? "", done: $0["done"].bool ?? false) }
        sortOrder = j["sort_order"].int ?? 0
    }
}

public struct WeekPayload: Sendable, Equatable {
    public var weekStart: String
    public var today: String
    public var week: Week?
    public var roles: [Role]
    public var rocks: [Rock]
    public var tasks: [PlannerTask]
    public var days: [DaySummary]
    public var quarterRocks: [QuarterRock]

    public init(_ j: JSON) {
        weekStart = j["weekStart"].string ?? ""
        today = j["today"].string ?? weekStart
        week = j["week"].isNull ? nil : Week(j["week"])
        roles = j["roles"].array.map(Role.init)
        rocks = j["rocks"].array.map(Rock.init)
        tasks = j["tasks"].array.map(PlannerTask.init)
        days = j["days"].array.map(DaySummary.init)
        quarterRocks = j["quarterRocks"].array.map(QuarterRock.init)
    }
}

// MARK: Quarter and goals

public struct Quarter: Sendable, Equatable {
    public var quarter: String
    public var theme, stopDoing, review: String?
    public var closedAt: Date?

    public init(_ j: JSON) {
        quarter = j["quarter"].string ?? ""
        theme = j["theme"].nonEmptyString; stopDoing = j["stop_doing"].nonEmptyString; review = j["review"].nonEmptyString
        closedAt = ServerDate.parse(j["closed_at"].string)
    }
}

public struct Goal: Sendable, Equatable, Identifiable {
    public var id: String
    public var year: Int
    public var area: String?
    public var title: String
    public var fromValue, toValue: String?
    public var byDate: String?
    public var startValue, currentValue, targetValue: Double?
    public var unit: String?
    public var leadMeasures: [String]
    public var why: String?
    public var status: GoalStatus
    public var sortOrder: Int

    public init(_ j: JSON) {
        id = j["id"].idString ?? ""
        year = j["year"].int ?? 0
        area = j["area"].nonEmptyString
        title = j["title"].string ?? ""
        fromValue = j["from_value"].nonEmptyString; toValue = j["to_value"].nonEmptyString
        byDate = j["by_date"].nonEmptyString
        startValue = j["start_value"].double; currentValue = j["current_value"].double; targetValue = j["target_value"].double
        unit = j["unit"].nonEmptyString
        leadMeasures = j["lead_measures"].array.compactMap { $0.string ?? $0["title"].string }
        why = j["why"].nonEmptyString
        status = GoalStatus(rawValue: j["status"].string ?? "") ?? .active
        sortOrder = j["sort_order"].int ?? 0
    }
}

public struct GoalUpdate: Sendable, Equatable, Identifiable {
    public var id: String
    public var goalId: String
    public var onDate: String
    public var value: Double?
    public var note: String?

    public init(_ j: JSON) {
        id = j["id"].idString ?? ""
        goalId = j["goal_id"].idString ?? ""
        onDate = j["on_date"].string ?? ""
        value = j["value"].double
        note = j["note"].nonEmptyString
    }
}

public struct TaskStub: Sendable, Equatable {
    public var forDate: String
    public var status: TaskStatus
    public var isTop3: Bool
    public init(_ j: JSON) {
        forDate = j["for_date"].string ?? ""
        status = TaskStatus(rawValue: j["status"].string ?? "") ?? .open
        isTop3 = j["is_top3"].bool ?? false
    }
    public init(forDate: String, status: TaskStatus, isTop3: Bool) { self.forDate = forDate; self.status = status; self.isTop3 = isTop3 }
}

public struct RockStub: Sendable, Equatable {
    public var quarterRockId: String?
    public var status: TaskStatus
    public var weekStart: String
    public init(_ j: JSON) {
        quarterRockId = j["quarter_rock_id"].nonEmptyString
        status = TaskStatus(rawValue: j["status"].string ?? "") ?? .open
        weekStart = j["week_start"].string ?? ""
    }
    public init(quarterRockId: String?, status: TaskStatus, weekStart: String) { self.quarterRockId = quarterRockId; self.status = status; self.weekStart = weekStart }
}

public struct QuarterPayload: Sendable, Equatable {
    public var quarter: String
    public var today: String
    public var start, end: String
    public var record: Quarter?
    public var rocks: [QuarterRock]
    public var goals: [Goal]
    public var days: [DaySummary]
    public var tasks: [TaskStub]
    public var weekRocks: [RockStub]

    public init(_ j: JSON) {
        quarter = j["quarter"].string ?? ""
        today = j["today"].string ?? ""
        start = j["start"].string ?? ""; end = j["end"].string ?? ""
        record = j["record"].isNull ? nil : Quarter(j["record"])
        rocks = j["rocks"].array.map(QuarterRock.init)
        goals = j["goals"].array.map(Goal.init)
        days = j["days"].array.map(DaySummary.init)
        tasks = j["tasks"].array.map(TaskStub.init)
        weekRocks = j["weekRocks"].array.map(RockStub.init)
    }
}

public struct GoalsPayload: Sendable, Equatable {
    public var year: Int
    public var today: String
    public var goals: [Goal]
    public var updates: [GoalUpdate]
    public var quarterRocks: [QuarterRock]

    public init(_ j: JSON) {
        year = j["year"].int ?? 0
        today = j["today"].string ?? ""
        goals = j["goals"].array.map(Goal.init)
        updates = j["updates"].array.map(GoalUpdate.init)
        quarterRocks = j["quarterRocks"].array.map(QuarterRock.init)
    }
}

// MARK: Journal

public struct Notebook: Sendable, Equatable, Identifiable {
    public var id: String
    public var name: String
    public var kind: NotebookKind
    public var sortOrder: Int
    public var locked: Bool
    public var kdf: JournalCrypto.Kdf?

    public init(_ j: JSON) {
        id = j["id"].idString ?? ""
        name = j["name"].string ?? ""
        kind = NotebookKind(rawValue: j["kind"].string ?? "") ?? .note
        sortOrder = j["sort_order"].int ?? 0
        locked = j["locked"].bool ?? false
        kdf = JournalCrypto.Kdf(j["kdf"])
    }
}

public struct Note: Sendable, Equatable, Identifiable {
    public var id: String
    public var kind: NotebookKind
    public var onDate: String
    /// Ciphertext (`enc:v1:…`) when `encrypted`; the view model holds the decrypted copy.
    public var title: String
    public var body: String
    public var tags: [String]
    public var pinned: Bool
    public var notebookId: String?
    public var encrypted: Bool
    public var updatedAt: Date

    public init(_ j: JSON) {
        id = j["id"].idString ?? ""
        kind = NotebookKind(rawValue: j["kind"].string ?? "") ?? .note
        onDate = j["on_date"].string ?? ""
        title = j["title"].string ?? ""
        body = j["body"].string ?? ""
        tags = j["tags"].array.compactMap(\.string)
        pinned = j["pinned"].bool ?? false
        notebookId = j["notebook_id"].nonEmptyString
        encrypted = j["encrypted"].bool ?? false
        updatedAt = ServerDate.parse(j["updated_at"].string) ?? .distantPast
    }
}

public struct JournalPayload: Sendable, Equatable {
    public var today: String
    public var notebooks: [Notebook]
    public var notes: [Note]

    public init(_ j: JSON) {
        today = j["today"].string ?? ""
        notebooks = j["notebooks"].array.map(Notebook.init)
        notes = j["notes"].array.map(Note.init)
    }
}
