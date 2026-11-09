import CryptoKit
import DailyCommandCore
import SwiftUI

/// Notebooks and entries. Locked notebooks are decrypted on the device with a key derived from
/// the passphrase; keys stay in memory and are dropped after 15 idle minutes or when the app
/// goes to the background. The server only ever holds ciphertext.
@MainActor @Observable
final class JournalModel {
    var payload: JournalPayload?
    var loading = false
    var error: String?
    var selectedNotebookId: String?
    /// Unlocked notebook keys by notebook id.
    var keys: [String: SymmetricKey] = [:]
    var lastActivity = Date()

    func load(_ api: PlannerAPI) async {
        loading = payload == nil
        defer { loading = false }
        do {
            payload = try await api.journal()
            error = nil
            if selectedNotebookId == nil { selectedNotebookId = payload?.notebooks.first?.id }
        } catch { self.error = error.localizedDescription }
    }

    func run(_ api: PlannerAPI, _ work: () async throws -> Void) async {
        do { try await work(); await load(api) } catch { self.error = error.localizedDescription }
    }

    var notebooks: [Notebook] { payload?.notebooks ?? [] }
    var selected: Notebook? { notebooks.first { $0.id == selectedNotebookId } }
    var notes: [Note] { (payload?.notes ?? []).filter { $0.notebookId == selectedNotebookId } }
    func isUnlocked(_ nb: Notebook) -> Bool { !nb.locked || keys[nb.id] != nil }

    func touch() { lastActivity = Date() }

    func relockIfIdle() {
        if Date().timeIntervalSince(lastActivity) > JournalCrypto.relockAfter { keys.removeAll() }
    }

    func unlock(_ nb: Notebook, passphrase: String) -> Bool {
        guard let kdf = nb.kdf, let key = JournalCrypto.unlock(passphrase: passphrase, kdf: kdf) else { return false }
        keys[nb.id] = key
        touch()
        return true
    }

    /// Plain text for display; nil when the notebook is locked or the entry cannot be decrypted.
    func plain(_ note: Note) -> (title: String, body: String)? {
        guard note.encrypted else { return (note.title, RichText.plain(note.body)) }
        guard let id = note.notebookId, let key = keys[id] else { return nil }
        guard let t = try? JournalCrypto.decrypt(note.title, key: key), let b = try? JournalCrypto.decrypt(note.body, key: key) else { return nil }
        return (t, RichText.plain(b))
    }

    /// The patch for saving an entry, encrypting when the notebook is locked.
    func patch(title: String, body: String, in nb: Notebook) throws -> [String: Any] {
        let html = RichText.html(body)
        guard nb.locked else { return ["title": title, "body": html, "encrypted": false] }
        guard let key = keys[nb.id] else { throw APIError.server(status: 423, message: "Unlock the notebook first.") }
        return ["title": try JournalCrypto.encrypt(title, key: key), "body": try JournalCrypto.encrypt(html, key: key), "encrypted": true]
    }
}

/// The web app stores entries as sanitized HTML. The phone edits plain text and keeps simple
/// paragraphs, so an entry written here reads the same on the web.
enum RichText {
    static func plain(_ html: String) -> String {
        guard html.contains("<") else { return html }
        var s = html
        for (pat, rep) in [("(?i)<br\\s*/?>", "\n"), ("(?i)</(p|div|li|h[1-6]|blockquote)>", "\n"), ("(?i)<li[^>]*>", "• "), ("<[^>]+>", "")] {
            s = s.replacingOccurrences(of: pat, with: rep, options: .regularExpression)
        }
        for (ent, ch) in [("&nbsp;", " "), ("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&#39;", "'")] {
            s = s.replacingOccurrences(of: ent, with: ch)
        }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func html(_ text: String) -> String {
        text.split(separator: "\n", omittingEmptySubsequences: false).map { line in
            let esc = line.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
            return esc.isEmpty ? "<p><br></p>" : "<p>\(esc)</p>"
        }.joined()
    }
}

struct JournalView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.scenePhase) private var scenePhase
    @State private var m = JournalModel()
    @State private var newNotebook = false
    @State private var unlocking: Notebook?

    var body: some View {
        VStack(spacing: 0) {
            if let error = m.error { ErrorBanner(message: error).padding([.horizontal, .top]).onTapGesture { m.error = nil } }
            notebookStrip
            Divider().overlay(DC.line)
            if m.loading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let api = app.api, let nb = m.selected {
                if m.isUnlocked(nb) {
                    entries(nb, api)
                } else {
                    lockedPrompt(nb)
                }
            } else {
                VStack(spacing: 12) {
                    Text("Create a journal (private, encrypted) or a notebook (plain notes).").font(DC.Font.small).foregroundStyle(DC.muted)
                    Button("New notebook") { newNotebook = true }.buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(DC.bg)
        .navigationTitle("Journal")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("New notebook or journal") { newNotebook = true }
                    if let nb = m.selected {
                        if nb.locked, m.keys[nb.id] != nil { Button("Lock now") { m.keys[nb.id] = nil } }
                        Button("Archive \(nb.name)", role: .destructive) {
                            Task { if let api = app.api { await m.run(api) { try await api.archiveNotebook(nb.id) }; m.selectedNotebookId = m.notebooks.first?.id } }
                        }
                    }
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }
        .sheet(isPresented: $newNotebook) { if let api = app.api { NewNotebookSheet(api: api, m: m) } }
        .sheet(item: $unlocking) { nb in UnlockSheet(notebook: nb, m: m) }
        .task { if let api = app.api { await m.load(api) } }
        .refreshable { if let api = app.api { await m.load(api) } }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { m.keys.removeAll() } else if phase == .active { m.relockIfIdle() }
        }
    }

    private var notebookStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(m.notebooks) { nb in
                    Button { m.selectedNotebookId = nb.id } label: {
                        HStack(spacing: 6) {
                            Image(systemName: nb.kind == .journal ? (m.isUnlocked(nb) ? "lock.open" : "lock") : "note.text")
                            Text(nb.name)
                        }
                        .font(DC.Font.small.weight(.semibold))
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(nb.id == m.selectedNotebookId ? DC.goldSoft : DC.card, in: Capsule())
                        .overlay(Capsule().stroke(nb.id == m.selectedNotebookId ? DC.gold : DC.line))
                        .foregroundStyle(nb.id == m.selectedNotebookId ? DC.goldText : DC.text2)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(12)
        }
    }

    private func lockedPrompt(_ nb: Notebook) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "lock.fill").font(.largeTitle).foregroundStyle(DC.gold)
            Text("\(nb.name) is locked").font(DC.Font.headline).foregroundStyle(DC.text)
            Text("Entries are encrypted on your device. Only your passphrase opens them — not ExecClone, not anyone.")
                .font(DC.Font.small).foregroundStyle(DC.muted).multilineTextAlignment(.center)
            Button("Unlock") { unlocking = nb }.buttonStyle(.borderedProminent)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func entries(_ nb: Notebook, _ api: PlannerAPI) -> some View {
        List {
            ForEach(m.notes) { note in
                NavigationLink { EntryEditor(noteId: note.id, notebook: nb, m: m, api: api) } label: {
                    let p = m.plain(note)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(p?.title.isEmpty == false ? p!.title : (p == nil ? "(cannot decrypt)" : "Untitled"))
                                .foregroundStyle(p == nil ? DC.red : DC.text).lineLimit(1)
                            Spacer()
                            if note.pinned { Image(systemName: "pin.fill").font(.caption).foregroundStyle(DC.gold) }
                            Text(DateText.short(note.onDate)).font(DC.Font.small).foregroundStyle(DC.muted)
                        }
                        if let p, !p.body.isEmpty { Text(p.body).font(DC.Font.small).foregroundStyle(DC.muted).lineLimit(2) }
                    }
                }
                .listRowBackground(DC.card)
                .swipeActions {
                    Button("Archive", role: .destructive) { Task { await m.run(api) { try await api.saveNote(id: note.id, patch: ["archived": true]) } } }
                    Button(note.pinned ? "Unpin" : "Pin") { Task { await m.run(api) { try await api.saveNote(id: note.id, patch: ["pinned": !note.pinned]) } } }.tint(DC.gold)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .overlay(alignment: .bottomTrailing) {
            NavigationLink { EntryEditor(noteId: nil, notebook: nb, m: m, api: api) } label: {
                Image(systemName: "square.and.pencil").font(.title2).padding(16)
                    .background(DC.gold, in: Circle()).foregroundStyle(DC.bg)
            }
            .padding(20)
        }
    }
}

struct EntryEditor: View {
    let noteId: String?
    let notebook: Notebook
    @Bindable var m: JournalModel
    let api: PlannerAPI
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var body_ = ""
    @State private var loaded = false
    @State private var saving = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            TextField("Title", text: $title).font(DC.Font.title).padding(.horizontal, 16).padding(.top, 12)
            TextEditor(text: $body_)
                .focused($focused)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 12)
        }
        .background(DC.bg)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(saving ? "Saving…" : "Done") { Task { await save() } }.disabled(saving)
            }
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            if let noteId, let note = m.payload?.notes.first(where: { $0.id == noteId }), let p = m.plain(note) {
                title = p.title; body_ = p.body
            } else if noteId == nil {
                focused = true
            }
            m.touch()
        }
    }

    private func save() async {
        saving = true
        defer { saving = false }
        let t = title.trimmingCharacters(in: .whitespaces), b = body_.trimmingCharacters(in: .whitespacesAndNewlines)
        if noteId == nil, t.isEmpty, b.isEmpty { dismiss(); return }
        do {
            var patch = try m.patch(title: t, body: b, in: notebook)
            if noteId == nil {
                patch["notebook_id"] = notebook.id
                patch["kind"] = notebook.kind.rawValue
                patch["on_date"] = Planning.today()
            }
            try await api.saveNote(id: noteId, patch: patch)
            await m.load(api)
            m.touch()
            dismiss()
        } catch { m.error = error.localizedDescription }
    }
}

struct UnlockSheet: View {
    let notebook: Notebook
    @Bindable var m: JournalModel
    @Environment(\.dismiss) private var dismiss
    @State private var passphrase = ""
    @State private var wrong = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("Passphrase", text: $passphrase).textContentType(.password).submitLabel(.go).onSubmit(unlock)
                    if wrong { Text("That passphrase doesn't open this notebook.").foregroundStyle(DC.red) }
                } footer: {
                    Text("Checked on this device only. A forgotten passphrase cannot be recovered.")
                }
            }
            .navigationTitle("Unlock \(notebook.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Unlock", action: unlock).disabled(passphrase.isEmpty) }
            }
        }
        .presentationDetents([.medium])
    }

    private func unlock() {
        if m.unlock(notebook, passphrase: passphrase) { dismiss() } else { wrong = true; passphrase = "" }
    }
}

struct NewNotebookSheet: View {
    let api: PlannerAPI
    @Bindable var m: JournalModel
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var kind: NotebookKind = .journal
    @State private var pass1 = ""
    @State private var pass2 = ""
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name)
                Picker("Type", selection: $kind) {
                    Text("Journal (locked)").tag(NotebookKind.journal)
                    Text("Notebook (notes)").tag(NotebookKind.note)
                }
                .pickerStyle(.segmented)
                if kind == .journal {
                    Section {
                        SecureField("Passphrase", text: $pass1).textContentType(.newPassword)
                        SecureField("Confirm passphrase", text: $pass2).textContentType(.newPassword)
                    } footer: {
                        Text("Entries are encrypted with this passphrase before they leave your phone. Nobody can reset it — write it down somewhere safe.")
                    }
                }
                if let error { Text(error).foregroundStyle(DC.red) }
            }
            .navigationTitle("New \(kind == .journal ? "journal" : "notebook")")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Create") { Task { await create() } }.disabled(!valid) }
            }
        }
    }

    private var valid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && (kind == .note || (pass1.count >= 8 && pass1 == pass2))
    }

    private func create() async {
        do {
            var patch: [String: Any] = ["name": name.trimmingCharacters(in: .whitespaces), "kind": kind.rawValue, "sort_order": m.notebooks.count + 1]
            var key: SymmetricKey?
            if kind == .journal {
                let made = try JournalCrypto.makeKdf(passphrase: pass1)
                patch["locked"] = true
                patch["kdf"] = made.kdf.json
                key = made.key
            }
            let id = try await api.saveNotebook(id: nil, patch: patch)
            if let key { m.keys[id] = key }
            await m.load(api)
            m.selectedNotebookId = id
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}
