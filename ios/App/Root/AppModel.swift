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
            api = makeAPI(session, auth)
        } else {
            state = .signedOut
        }
    }

    func signedIn(_ session: Session) {
        guard let auth else { return }
        api = makeAPI(session, auth)
        state = .signedIn(session)
    }

    private func makeAPI(_ session: Session, _ auth: AuthClient) -> PlannerAPI {
        let api = PlannerAPI(session: session, auth: auth, cache: ResponseCache(userId: session.userId))
        api.onTwoStepRequired = { [weak self] in
            Task { @MainActor [weak self] in self?.needsTwoStep() }
        }
        return api
    }

    /// The service answered `mfa_required`: keep the code-only session and ask for the authenticator code.
    func needsTwoStep() {
        if case let .signedIn(session) = state { state = .twoStep(session) }
    }

    func signOut() async {
        api?.cache?.clear()
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
        } else if case APIError.twoStepRequired = error {
            needsTwoStep()
        }
    }
}
