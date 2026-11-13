import DailyCommandCore
import SwiftUI

/// Second sign-in step for accounts with an authenticator app (client-api §13). Shown when the
/// service answers `mfa_required`; the verified session replaces the code-only one.
struct TwoStepView: View {
    @Environment(AppModel.self) private var model
    let session: Session
    @State private var code = ""
    @State private var busy = false
    @State private var error: String?
    @FocusState private var focused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Kicker("Daily Command")
                    Text("One more step.").font(DC.Font.display).foregroundStyle(DC.text)
                }
                .padding(.top, 48)
                Card("Authenticator code") {
                    Text("\(session.email) uses an authenticator app. Enter the current 6-digit code.")
                        .foregroundStyle(DC.text2)
                    TextField("Code", text: $code)
                        .textContentType(.oneTimeCode)
                        .keyboardType(.numberPad)
                        .focused($focused)
                        .field()
                        .onChange(of: code) { _, v in if v.filter(\.isNumber).count >= 6 { Task { await verify() } } }
                    Button { Task { await verify() } } label: {
                        Text(busy ? "Checking…" : "Continue").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(busy || code.filter(\.isNumber).count < 6)
                    Button("Sign out") { Task { await model.signOut() } }.font(DC.Font.small)
                    if let error { ErrorBanner(message: error) }
                }
            }
            .padding(20)
        }
        .background(DC.bg)
        .onAppear { focused = true }
    }

    private func verify() async {
        guard let auth = model.auth, !busy else { return }
        busy = true; error = nil
        defer { busy = false }
        do {
            let upgraded = try await auth.completeTwoStep(session: session, code: code)
            model.signedIn(upgraded)
        } catch {
            self.error = error.localizedDescription
            code = ""
        }
    }
}
