import DailyCommandCore
import SwiftUI

/// Email + one-time code. A new email becomes an account on the first code (D-020), so there
/// is no separate sign-up screen.
struct SignInView: View {
    @Environment(AppModel.self) private var model
    @State private var email = ""
    @State private var code = ""
    @State private var codeSent = false
    @State private var busy = false
    @State private var error: String?
    @FocusState private var focus: Field?

    enum Field { case email, code }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Kicker("Daily Command")
                    Text("Plan the day. Keep the week. Hit the quarter.").font(DC.Font.display).foregroundStyle(DC.text)
                    Text("by ExecClone").font(DC.Font.small).foregroundStyle(DC.muted)
                }
                .padding(.top, 48)

                Card(codeSent ? "Check your email" : "Sign in or create an account") {
                    if !codeSent {
                        TextField("Email", text: $email)
                            .textContentType(.emailAddress)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .focused($focus, equals: .email)
                            .submitLabel(.send)
                            .onSubmit { Task { await sendCode() } }
                            .field()
                        Button { Task { await sendCode() } } label: {
                            Text(busy ? "Sending…" : "Email me a code").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(busy || !AuthClient.isValid(email: email))
                        Text("We'll create your account if this is your first time. No password to remember.")
                            .font(DC.Font.small).foregroundStyle(DC.muted)
                    } else {
                        Text("We sent a 6-digit code to \(AuthClient.normalize(email: email)).").foregroundStyle(DC.text2)
                        TextField("Code", text: $code)
                            .textContentType(.oneTimeCode)
                            .keyboardType(.numberPad)
                            .focused($focus, equals: .code)
                            .field()
                            .onChange(of: code) { _, v in if v.filter(\.isNumber).count >= 6 { Task { await verify() } } }
                        Button { Task { await verify() } } label: {
                            Text(busy ? "Signing in…" : "Continue").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(busy || code.filter(\.isNumber).count < 6)
                        Button("Use a different email") { codeSent = false; code = ""; error = nil; focus = .email }
                            .font(DC.Font.small)
                    }
                    if let error { ErrorBanner(message: error) }
                }

                HStack(spacing: 16) {
                    Link("Privacy", destination: DailyCommandLinks.privacyPolicy)
                    Link("Terms", destination: DailyCommandLinks.terms)
                }
                .font(DC.Font.small).foregroundStyle(DC.muted)
            }
            .padding(20)
        }
        .background(DC.bg)
        .onAppear { focus = .email }
    }

    private func sendCode() async {
        guard let auth = model.auth, !busy else { return }
        busy = true; error = nil
        defer { busy = false }
        do {
            try await auth.requestCode(email: email)
            codeSent = true
            focus = .code
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func verify() async {
        guard let auth = model.auth, !busy else { return }
        busy = true; error = nil
        defer { busy = false }
        do {
            let session = try await auth.verifyCode(email: email, code: code)
            model.signedIn(session)
        } catch {
            self.error = error.localizedDescription
            code = ""
        }
    }
}

extension View {
    func field() -> some View {
        padding(12)
            .background(DC.cardHi, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(DC.line))
    }
}
