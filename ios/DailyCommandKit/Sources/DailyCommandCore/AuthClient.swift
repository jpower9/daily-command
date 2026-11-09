import Foundation

/// Email one-time-code sign-in with self-signup.
///
/// Daily Command is open to anyone (canon D-020), but the shared Supabase
/// project keeps public signups off so ExecClone client accounts stay
/// team-provisioned. Requesting a code therefore goes through ExecClone's
/// `dc-auth` function, which creates a planner-only account when the email is
/// new (marked server-side as a planner-only role) and then sends the
/// code. Verifying the code is the standard GoTrue exchange.
public struct AuthClient: Sendable {
    public let environment: ServiceEnvironment
    public let store: SessionStore
    let transport: HTTPTransport

    public init(environment: ServiceEnvironment, store: SessionStore, transport: HTTPTransport = URLSessionTransport(timeout: 60)) {
        self.environment = environment
        self.store = store
        self.transport = transport
    }

    public static func normalize(email: String) -> String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    public static func isValid(email: String) -> Bool {
        let e = normalize(email: email)
        guard e.count <= 254, let at = e.firstIndex(of: "@"), at != e.startIndex else { return false }
        let domain = e[e.index(after: at)...]
        return domain.contains(".") && !domain.hasPrefix(".") && !domain.hasSuffix(".") && !e.contains(" ")
    }

    var startURL: URL { environment.baseURL.appendingPathComponent("functions/v1/dc-auth/start") }

    /// Sends a sign-in code, creating the account first when it does not exist.
    public func requestCode(email: String) async throws {
        let email = Self.normalize(email: email)
        guard Self.isValid(email: email) else { throw APIError.server(status: 400, message: "Enter a valid email address.") }
        let (status, body) = try await post(startURL, ["email": email])
        guard status == 200 else {
            throw APIError.server(status: status, message: Self.errorMessage(body) ?? "Could not send code")
        }
    }

    /// Exchanges the email code and stores the session.
    @discardableResult
    public func verifyCode(email: String, code: String) async throws -> Session {
        let session = try await exchangeCode(email: email, code: code)
        store.save(session)
        return session
    }

    /// Exchanges the email code for a session without storing it.
    public func exchangeCode(email: String, code: String) async throws -> Session {
        let email = Self.normalize(email: email)
        let code = code.filter(\.isNumber)
        let (status, body) = try await post(environment.authURL("verify"), ["type": "email", "email": email, "token": code])
        guard status == 200,
              let access = body["access_token"].nonEmptyString,
              let refresh = body["refresh_token"].nonEmptyString,
              let userId = body["user"]["id"].nonEmptyString
        else {
            throw APIError.server(status: status, message: Self.errorMessage(body) ?? "Invalid code")
        }
        return Session(accessToken: access, refreshToken: refresh, userId: userId,
                       email: body["user"]["email"].nonEmptyString ?? email)
    }

    public func signOut() async {
        if let current = store.load() {
            var request = URLRequest(url: environment.authURL("logout"))
            request.httpMethod = "POST"
            request.setValue(environment.publishableKey, forHTTPHeaderField: "apikey")
            request.setValue("Bearer \(current.accessToken)", forHTTPHeaderField: "Authorization")
            _ = try? await transport.send(request)
        }
        store.clear()
    }

    func refreshPOST(_ refreshToken: String) async throws -> (Int, JSON) {
        try await post(environment.authURL("token?grant_type=refresh_token"), ["refresh_token": refreshToken])
    }

    func post(_ url: URL, _ payload: [String: Any]) async throws -> (Int, JSON) {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(environment.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        let (data, status) = try await transport.send(request)
        return (status, (try? JSON(data: data)) ?? .null)
    }

    static func errorMessage(_ body: JSON) -> String? {
        body["msg"].nonEmptyString ?? body["error_description"].nonEmptyString ?? body["error"].nonEmptyString ?? body["message"].nonEmptyString
    }
}

/// Refresh tokens are single-use, so every part of the app refreshes through
/// this one actor. A caller that queued behind another refresh adopts the
/// session that refresh saved instead of spending a dead token (which would
/// sign the user out).
public actor TokenRefresher {
    public static let shared = TokenRefresher()

    public func refresh(current: Session, auth: AuthClient) async throws -> Session {
        if let stored = auth.store.load(), stored.accessToken != current.accessToken { return stored }
        let (status, body) = try await auth.refreshPOST(current.refreshToken)
        if status == 200, let access = body["access_token"].nonEmptyString, let refresh = body["refresh_token"].nonEmptyString {
            var updated = current
            updated.accessToken = access
            updated.refreshToken = refresh
            auth.store.save(updated)
            return updated
        }
        if let stored = auth.store.load(), stored.accessToken != current.accessToken { return stored }
        // Only a refused token means signed out; an outage must not sign anyone out.
        if (400...403).contains(status) { throw APIError.notSignedIn }
        throw APIError.server(status: status, message: AuthClient.errorMessage(body) ?? "")
    }
}
