import Foundation
import Testing
@testable import DailyCommandCore

struct PlanningTests {
    @Test func dateMath() {
        #expect(Planning.monday("2026-11-09") == "2026-11-09")   // a Monday
        #expect(Planning.monday("2026-11-15") == "2026-11-09")   // Sunday → previous Monday
        #expect(Planning.monday("2026-11-10") == "2026-11-09")
        #expect(Planning.addDays("2026-12-31", 1) == "2027-01-01")
        #expect(Planning.addDays("2026-03-01", -1) == "2026-02-28")
        #expect(Planning.daysBetween("2026-10-01", "2026-12-31") == 91)
        #expect(Planning.weekDays("2026-11-09").last == "2026-11-15")
    }

    @Test func quarters() {
        #expect(Planning.quarterOf("2026-11-09") == "2026-Q4")
        #expect(Planning.quarterOf("2026-01-31") == "2026-Q1")
        let r = Planning.quarterRange("2026-Q4")
        #expect(r.start == "2026-10-01" && r.end == "2026-12-31")
        #expect(Planning.quarterRange("2028-Q1").end == "2028-03-31")
        #expect(Planning.shiftQuarter("2026-Q4", by: 1) == "2027-Q1")
        #expect(Planning.shiftQuarter("2026-Q1", by: -1) == "2025-Q4")
        #expect(Planning.shiftQuarter("2026-Q2", by: -6) == "2024-Q4")
        #expect(Planning.quarterTitle("2026-Q4") == "Q4 2026")
    }

    @Test func phases() {
        #expect(Planning.phase(hour: 0) == .am)
        #expect(Planning.phase(hour: 12) == .am)
        #expect(Planning.phase(hour: 13) == .md)
        #expect(Planning.phase(hour: 17) == .md)
        #expect(Planning.phase(hour: 18) == .pm)
        #expect(Metric.energy.column(.am) == "energy")
        #expect(Metric.stress.column(.pm) == "pm_stress")
    }

    @Test func compareUsesYesterdayEveningInTheMorning() throws {
        let prev = Day(try JSON(data: Data(#"{"for_date":"2026-11-08","pm_energy":4}"#.utf8)))
        let day = Day(try JSON(data: Data(#"{"for_date":"2026-11-09","energy":2}"#.utf8)))
        let am = Planning.compare(day: day, previousDay: prev, phase: .am, metric: .energy)
        #expect(am.value == 4 && am.label == "yesterday's PM")
        let md = Planning.compare(day: day, previousDay: prev, phase: .md, metric: .energy)
        #expect(md.value == 2 && md.label == "this morning")
        let pm = Planning.compare(day: day, previousDay: prev, phase: .pm, metric: .energy)
        #expect(pm.value == 2 && pm.label == "this morning")   // no midday reading yet
    }

    @Test func parsesTaskShorthand() {
        let t = Planning.parseTask("!1 Call bank #money")
        #expect(t == .init(title: "Call bank", priority: 1, tag: "money"))
        #expect(Planning.parseTask("Just a task").priority == 2)
        #expect(Planning.parseTask("Ship #Release-2 now !3") == .init(title: "Ship now", priority: 3, tag: "release-2"))
        #expect(Planning.parseTask("#").title == "#")        // a bare hash is text
        #expect(Planning.parseTask("!9 x").title == "!9 x")  // priority must be 1–3
    }

    @Test func sortsOpenFirstThenByChoice() throws {
        let rows = try JSON(data: Data(#"""
        [{"id":"a","title":"b","status":"done","priority":1,"carried_count":0,"sort_order":0,"created_at":"2026-11-01T00:00:00Z"},
         {"id":"b","title":"a","status":"open","priority":2,"carried_count":3,"sort_order":0,"created_at":"2026-11-02T00:00:00Z"},
         {"id":"c","title":"c","status":"open","priority":1,"carried_count":0,"sort_order":0,"created_at":"2026-11-03T00:00:00Z"}]
        """#.utf8)).array.map(PlannerTask.init)
        #expect(Planning.sort(rows, by: .priority).map(\.id) == ["c", "b", "a"])
        #expect(Planning.sort(rows, by: .carried).map(\.id) == ["b", "c", "a"])
        #expect(Planning.sort(rows, by: .created).map(\.id) == ["c", "b", "a"])
        #expect(Planning.sort(rows, by: .title).map(\.id) == ["b", "c", "a"])
    }

    @Test func scorecardMatchesTheWebApp() throws {
        let payload = QuarterPayload(try JSON(data: Data(#"""
        {"quarter":"2026-Q4","today":"2026-11-09","start":"2026-10-01","end":"2026-12-31",
         "days":[{"for_date":"2026-11-08","closed_at":"2026-11-08T23:00:00Z","energy":3,"pm_energy":5,"mood":4,"workout_done":true},
                 {"for_date":"2026-11-09","energy":4}],
         "tasks":[{"for_date":"2026-11-08","status":"done","is_top3":true},{"for_date":"2026-11-08","status":"open","is_top3":true},
                  {"for_date":"2026-11-09","status":"done","is_top3":false}],
         "weekRocks":[{"status":"done","week_start":"2026-11-02"},{"status":"open","week_start":"2026-11-09"}]}
        """#.utf8)))
        let s = Planning.scorecard(payload)
        #expect(s.daysSoFar == 40)
        #expect(s.daysClosed == 1)
        #expect(s.top3Pct == 50)
        #expect(s.tasksDone == 2)
        #expect(s.rocksDone == 1 && s.rocksSet == 2)
        #expect(s.avgEnergy == 4.0)
        #expect(s.avgMood == 4.0)
        #expect(s.workouts == 1)
    }

    @Test func goalProgressClampsAndNils() {
        #expect(Planning.progress(start: 0, current: 50, target: 100) == 50)
        #expect(Planning.progress(start: 100, current: 120, target: 50) == 0)
        #expect(Planning.progress(start: 0, current: 150, target: 100) == 100)
        #expect(Planning.progress(start: 5, current: 5, target: 5) == nil)
        #expect(Planning.progress(start: nil, current: 1, target: 2) == nil)
    }

    @Test func eventsOverlapTheLocalDay() throws {
        let zone = TimeZone(identifier: "America/Chicago")!
        let rows = try JSON(data: Data(#"""
        [{"id":"late","title":"late","start_at":"2026-11-10T03:30:00Z","end_at":"2026-11-10T04:00:00Z"},
         {"id":"next","title":"next","start_at":"2026-11-10T15:00:00Z","end_at":"2026-11-10T16:00:00Z"},
         {"id":"allday","title":"all","is_all_day":true,"start_at":"2026-11-09T00:00:00Z","end_at":"2026-11-10T00:00:00Z"}]
        """#.utf8)).array.map(CalendarEvent.init)
        // 03:30Z on Nov 10 is 21:30 on Nov 9 in Chicago.
        #expect(Planning.events(rows, on: "2026-11-09", zone: zone).map(\.id) == ["allday", "late"])
        #expect(Planning.events(rows, on: "2026-11-10", zone: zone).map(\.id) == ["next"])
    }
}
