import Foundation
import Testing
@testable import DailyCommandCore

/// Records requests and replays canned responses.
final class FakeTransport: HTTPTransport, @unchecked Sendable {
    struct Call { var url: URL; var headers: [String: String]; var body: [String: Any] }
    private let lock = NSLock()
    private var _calls: [Call] = []
    private var responses: [(Data, Int)]

    init(_ responses: [(String, Int)]) { self.responses = responses.map { (Data($0.0.utf8), $0.1) } }

    var calls: [Call] { lock.withLock { _calls } }

    func send(_ request: URLRequest) async throws -> (Data, Int) {
        let body = request.httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
        lock.withLock {
            _calls.append(Call(url: request.url!, headers: request.allHTTPHeaderFields ?? [:], body: body))
        }
        return lock.withLock { responses.isEmpty ? (Data(), 500) : responses.removeFirst() }
    }
}

let env = ServiceEnvironment(baseURL: URL(string: "https://example.supabase.co")!, publishableKey: "sb_publishable_test")

struct AuthClientTests {
    @Test func startGoesThroughTheSignupFunction() async throws {
        let t = FakeTransport([(#"{"ok":true}"#, 200)])
        let auth = AuthClient(environment: env, store: MemorySessionStore(), transport: t)
        try await auth.requestCode(email: "  Joe@Example.COM ")
        let call = try #require(t.calls.first)
        #expect(call.url.absoluteString == "https://example.supabase.co/functions/v1/dc-auth/start")
        #expect(call.body["email"] as? String == "joe@example.com")
        #expect(call.headers["apikey"] == "sb_publishable_test")
        #expect(call.headers["Authorization"] == nil)
    }

    @Test func rejectsBadEmailsWithoutANetworkCall() async {
        let t = FakeTransport([])
        let auth = AuthClient(environment: env, store: MemorySessionStore(), transport: t)
        await #expect(throws: APIError.self) { try await auth.requestCode(email: "nope") }
        #expect(t.calls.isEmpty)
        #expect(AuthClient.isValid(email: "a@b.co"))
        #expect(!AuthClient.isValid(email: "a@b"))
        #expect(!AuthClient.isValid(email: "a b@c.d"))
    }

    @Test func verifyStoresTheSession() async throws {
        let t = FakeTransport([(#"{"access_token":"A","refresh_token":"R","user":{"id":"u1","email":"joe@example.com"}}"#, 200)])
        let store = MemorySessionStore()
        let auth = AuthClient(environment: env, store: store, transport: t)
        let s = try await auth.verifyCode(email: "joe@example.com", code: "123 456")
        #expect(s == Session(accessToken: "A", refreshToken: "R", userId: "u1", email: "joe@example.com"))
        #expect(store.load() == s)
        #expect(t.calls.first?.url.absoluteString == "https://example.supabase.co/auth/v1/verify")
        #expect(t.calls.first?.body["token"] as? String == "123456")
    }

    @Test func serverMessageSurfaces() async {
        let t = FakeTransport([(#"{"error":"Too many codes. Try again in a minute."}"#, 429)])
        let auth = AuthClient(environment: env, store: MemorySessionStore(), transport: t)
        await #expect(throws: APIError.server(status: 429, message: "Too many codes. Try again in a minute.")) {
            try await auth.requestCode(email: "joe@example.com")
        }
    }
}

struct PlannerAPITests {
    func api(_ t: FakeTransport, store: MemorySessionStore = MemorySessionStore()) -> PlannerAPI {
        let session = Session(accessToken: "A", refreshToken: "R", userId: "u1", email: "joe@example.com")
        store.save(session)
        return PlannerAPI(session: session, auth: AuthClient(environment: env, store: store, transport: t), transport: t)
    }

    @Test func callsMobileBootstrapWithActionAndBearer() async throws {
        let t = FakeTransport([(#"{"date":"2026-11-09","today":"2026-11-09","timeZone":"America/Chicago","day":null,"tasks":[{"id":"t1","title":"x","status":"open","priority":1,"for_date":"2026-11-09"}],"accounts":[],"events":[]}"#, 200)])
        let p = try await api(t).day("2026-11-09")
        let call = try #require(t.calls.first)
        #expect(call.url == env.appAPIURL)
        #expect(call.body["action"] as? String == "plannerDay")
        #expect(call.body["date"] as? String == "2026-11-09")
        #expect(call.headers["Authorization"] == "Bearer A")
        #expect(p.tasks.first?.title == "x")
        #expect(p.day == nil)
    }

    @Test func refreshesOnceOn401() async throws {
        let t = FakeTransport([
            (#"{"error":"Unauthorized"}"#, 401),
            (#"{"access_token":"A2","refresh_token":"R2"}"#, 200),
            (#"{"ok":true,"id":"n1"}"#, 200),
        ])
        let store = MemorySessionStore()
        let api = api(t, store: store)
        let id = try await api.saveTask(id: nil, patch: ["title": "Call bank"])
        #expect(id == "n1")
        #expect(t.calls.count == 3)
        #expect(t.calls[1].url.absoluteString.hasSuffix("/auth/v1/token?grant_type=refresh_token"))
        #expect(t.calls[2].headers["Authorization"] == "Bearer A2")
        #expect(store.load()?.refreshToken == "R2")
    }

    @Test func refusedRefreshSignsOut() async {
        let t = FakeTransport([(#"{"error":"Unauthorized"}"#, 401), (#"{"error":"invalid_grant"}"#, 400)])
        await #expect(throws: APIError.notSignedIn) { try await api(t).syncNow() }
    }

    @Test func serverErrorsCarryTheMessage() async {
        let t = FakeTransport([(#"{"error":"title is required"}"#, 400)])
        await #expect(throws: APIError.server(status: 400, message: "title is required")) {
            try await api(t).saveTask(id: nil, patch: [:])
        }
    }

    @Test func rockScheduleSendsTheServerFieldNames() async throws {
        let t = FakeTransport([(#"{"ok":true}"#, 200)])
        try await api(t).scheduleRock("r1", on: "2026-11-10", top3Position: 2)
        let b = try #require(t.calls.first?.body)
        #expect(b["action"] as? String == "plannerRockSchedule")
        #expect(b["rockId"] as? String == "r1" && b["date"] as? String == "2026-11-10" && b["top3Position"] as? Int == 2)
    }
}

struct SearchTests {
    @Test func parsesHitsAndSendsTheTerm() async throws {
        let t = FakeTransport([(#"{"q":"leads","results":[{"kind":"task","id":"t1","title":"Leads list","date":"2026-11-03","extra":"open"},{"kind":"quarterRock","id":"r1","title":"Build the engine","date":"2026-10-01","extra":"2026-Q4"},{"kind":"mystery","id":"x","title":"?","date":"2026-01-01","extra":null}]}"#, 200)])
        let hits = try await PlannerAPITests().api(t).search("leads")
        #expect(t.calls.first?.body["action"] as? String == "plannerSearch")
        #expect(t.calls.first?.body["q"] as? String == "leads")
        #expect(hits.count == 3)
        #expect(hits[0].kind == .task && hits[0].extra == "open")
        #expect(hits[1].kind == .quarterRock && hits[1].kind.label == "Q rock")
        #expect(hits[2].kind == .task)   // unknown kinds fall back rather than drop the list
        #expect(hits[2].extra == nil)
    }
}

struct EnvironmentTests {
    @Test func jsonNullBecomesNSNullEverywhere() async throws {
        let t = FakeTransport([(#"{"ok":true}"#, 200)])
        let api = PlannerAPITests().api(t)
        let none: String? = nil
        try await api.saveTask(id: "t1", patch: ["due_date": orNull(none), "title": "x", "nested": ["a": JSONNull.null]])
        let patch = try #require(t.calls.first?.body["patch"] as? [String: Any])
        #expect(patch["due_date"] is NSNull)
        #expect(patch["title"] as? String == "x")
        #expect((patch["nested"] as? [String: Any])?["a"] is NSNull)
    }

    @Test func isoTimestampsAreUTCWithMillis() {
        let d = Date(timeIntervalSince1970: 1_762_700_000.5)
        #expect(ServerDate.iso(d) == "2025-11-09T14:53:20.500Z")
    }

    @Test func urls() {
        #expect(env.appAPIURL.absoluteString == "https://example.supabase.co/functions/v1/mobile-bootstrap")
        #expect(env.authURL("token?grant_type=refresh_token").absoluteString == "https://example.supabase.co/auth/v1/token?grant_type=refresh_token")
    }
}
