import AuthenticationServices
import DailyCommandCore
import SwiftUI

/// Account, calendar and Reminders connections. Credentials for Microsoft go through Microsoft's
/// own sign-in page; Apple app-specific passwords are posted once to ExecClone's reminders
/// function over TLS and stored encrypted there. The app keeps neither.
struct SettingsView: View {
    @Environment(AppModel.self) private var app
    @State private var day: DayPayload?
    @State private var reminders: RemindersStatus?
    @State private var error: String?
    @State private var connectingReminders = false
    @State private var session: ASWebAuthenticationSession?

    /// Where the connect flows land. The page lives in Executive OS and is a universal link into
    /// this app (apple-app-site-association on app.execclone.com; see docs/CONNECT-RETURN.md).
    static let returnTo = "https://app.execclone.com/dc/connected"

    var body: some View {
        List {
            Section("Account") {
                if case let .signedIn(s) = app.state {
                    LabeledContent("Email", value: s.email)
                }
                Button("Sign out", role: .destructive) { Task { await app.signOut() } }
            }

            Section {
                if let accounts = day?.accounts, !accounts.isEmpty {
                    ForEach(accounts) { a in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(a.email ?? a.displayName ?? "Microsoft 365").foregroundStyle(DC.text)
                            Text(statusLine(a.status, a.lastSyncAt, a.lastError)).font(DC.Font.small).foregroundStyle(a.lastError == nil ? DC.muted : DC.red)
                        }
                        .swipeActions {
                            Button("Disconnect", role: .destructive) { Task { await run { try await app.api?.disconnectCalendar(a.id) } } }
                        }
                    }
                    Button("Sync now") { Task { await run { try await app.api?.syncNow() } } }
                }
                Button(day?.accounts.isEmpty ?? true ? "Connect Microsoft 365" : "Connect another account") { Task { await connectCalendar() } }
            } header: { Text("Calendar") } footer: {
                Text("Meetings show on the Day tab; events you add here are created in Microsoft 365.")
            }

            Section {
                if let acct = reminders?.account {
                    Text(statusLine(acct.status, acct.lastSyncAt, acct.lastError)).font(DC.Font.small).foregroundStyle(acct.lastError == nil ? DC.muted : DC.red)
                    NavigationLink("Lists: \(acct.lists.isEmpty ? "all" : acct.lists.joined(separator: ", "))") {
                        ListsPicker(available: reminders?.available ?? [], selected: acct.lists) { lists in
                            await run { try await app.api?.setReminderLists(lists) }
                        }
                    }
                    Button("Disconnect Reminders", role: .destructive) { Task { await run { try await app.api?.disconnectReminders() } } }
                } else {
                    Button("Connect Apple Reminders") { connectingReminders = true }
                }
            } header: { Text("Reminders") } footer: {
                Text("Reminders from the lists you choose appear as tasks. Apple stays the source of truth; completing one here completes it in Reminders.")
            }

            Section("About") {
                Link("Privacy policy", destination: DailyCommandLinks.privacyPolicy)
                Link("Terms", destination: DailyCommandLinks.terms)
                Link("Support", destination: DailyCommandLinks.support)
                LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")
            }

            if let error { Section { ErrorBanner(message: error) } }
        }
        .scrollContentBackground(.hidden)
        .background(DC.bg)
        .navigationTitle("Settings")
        .task { await load() }
        .sheet(isPresented: $connectingReminders) {
            if let api = app.api { RemindersConnectSheet(api: api) { Task { await load() } } }
        }
    }

    private func statusLine(_ status: String, _ at: Date?, _ err: String?) -> String {
        if let err { return "Error: \(err)" }
        let when = at.map { "synced \($0.formatted(.relative(presentation: .named)))" } ?? "not synced yet"
        return "\(status.capitalized) · \(when)"
    }

    private func load() async {
        guard let api = app.api else { return }
        do {
            async let d = api.day()
            async let r = api.reminders()
            day = try await d
            reminders = try await r
            error = nil
        } catch { model.handle(error); self.error = error.localizedDescription }
    }

    private func run(_ work: () async throws -> Void) async {
        do { try await work(); await load() } catch { model.handle(error); self.error = error.localizedDescription }
    }

    private func connectCalendar() async {
        guard let api = app.api else { return }
        do {
            guard let url = try await api.calendarConnectURL(returnTo: Self.returnTo) else { throw APIError.emptyResponse }
            let s = ASWebAuthenticationSession(url: url, callback: .https(host: "app.execclone.com", path: "/dc/connected")) { _, _ in
                Task { @MainActor in await load() }
            }
            s.prefersEphemeralWebBrowserSession = false
            s.presentationContextProvider = Presenter.shared
            session = s
            s.start()
        } catch { model.handle(error); self.error = error.localizedDescription }
    }
}

/// Picks the current window for the web sign-in sheet.
final class Presenter: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = Presenter()
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first ?? ASPresentationAnchor()
        }
    }
}

struct ListsPicker: View {
    let available: [String]
    @State var selected: [String]
    let save: ([String]) async -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            ForEach(available, id: \.self) { name in
                Button {
                    if let i = selected.firstIndex(of: name) { selected.remove(at: i) } else { selected.append(name) }
                } label: {
                    HStack {
                        Text(name).foregroundStyle(DC.text)
                        Spacer()
                        if selected.contains(name) { Image(systemName: "checkmark").foregroundStyle(DC.gold) }
                    }
                }
            }
            if available.isEmpty { Text("No lists found yet. Pull to refresh after the first sync.").foregroundStyle(DC.muted) }
        }
        .navigationTitle("Reminder lists")
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { Task { await save(selected); dismiss() } } } }
    }
}

/// Posts the Apple ID and an app-specific password to the one-time URL the server issued. The
/// request goes directly from the phone to ExecClone's reminders function; nothing is stored here.
struct RemindersConnectSheet: View {
    let api: PlannerAPI
    let done: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var appleId = ""
    @State private var appPassword = ""
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Apple ID email", text: $appleId).textContentType(.username).keyboardType(.emailAddress).textInputAutocapitalization(.never)
                    SecureField("App-specific password", text: $appPassword).textContentType(.password)
                } footer: {
                    Text("Create an app-specific password at account.apple.com → Sign-In and Security. It only allows Reminders sync and you can revoke it any time. It is encrypted on ExecClone's servers and never kept on this phone.")
                }
                if let error { Text(error).foregroundStyle(DC.red) }
            }
            .navigationTitle("Connect Reminders")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(busy ? "Checking…" : "Connect") { Task { await connect() } }
                        .disabled(busy || appleId.isEmpty || appPassword.count < 16)
                }
            }
        }
    }

    private func connect() async {
        busy = true; error = nil
        defer { busy = false }
        do {
            guard let url = try await api.remindersConnectURL(returnTo: SettingsView.returnTo),
                  url.host == api.auth.environment.baseURL.host else { throw APIError.emptyResponse }
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: ["username": appleId.trimmingCharacters(in: .whitespaces), "app_password": appPassword])
            let (data, response) = try await URLSession.shared.data(for: req)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard status == 200 else {
                let body = (try? JSON(data: data)) ?? .null
                throw APIError.server(status: status, message: body["error"].nonEmptyString ?? "Apple did not accept those details.")
            }
            appPassword = ""
            done(); dismiss()
        } catch { model.handle(error); self.error = error.localizedDescription }
    }
}
