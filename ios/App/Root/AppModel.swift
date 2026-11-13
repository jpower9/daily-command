import DailyCommandCore
import Foundation
import Observation

/// Sign-in state for the whole app. The session lives in the Keychain; the API client is rebuilt
/// from it on launch. Nothing here holds a secret beyond the user's own tokens.
@MainActor @Observable
final class AppModel {
    enum State: Equatable {
        case notConfigured
        case signedOut
        case signedIn(Session)
        /// Signed in with the email code, but the account has an authenticator app enrolled.
        case twoStep(Session)
    }

    private(set) var state: State
    let environment: ServiceEnvironment?
    let auth: AuthClient?
    private(set) var api: PlannerAPI?

    init(environment: ServiceEnvironment? = ServiceEnvironment.fromBundle(), store: SessionStore = KeychainSessionStore.shared()) {
        self.environment = environment
        guard let environment else {
            auth = nil
            state = .notConfigured
            return
        }
        let auth = AuthClient(environment: environment, store: store)
        self.auth = auth
        if let session = store.load() {
            state = .signedIn(session)
            api = PlannerAPI(session: session, auth: auth)
        } else {
            state = .signedOut
        }
    }

    func signedIn(_ session: Session) {
        guard let auth else { return }
        api = PlannerAPI(session: session, auth: auth)
        state = .signedIn(session)
    }

    func signOut() async {
        await auth?.signOut()
        api = nil
        state = .signedOut
    }

    /// Called when an API call reports the session is gone for good, or needs its second step.
    func handle(_ error: Error) {
        if case APIError.notSignedIn = error {
            auth?.store.clear()
            api = nil
            state = .signedOut
        } else if case APIError.twoStepRequired = error, case let .signedIn(session) = state {
            state = .twoStep(session)
        }
    }
}
