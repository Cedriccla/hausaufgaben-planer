import SwiftUI

enum UntisLoginMode: String, CaseIterable, Identifiable {
    case password = "Untis-Passwort"
    case secret = "Schulaccount"
    var id: String { rawValue }
}

struct UntisView: View {
    @EnvironmentObject var store: HomeworkStore
    @EnvironmentObject var untis: UntisSync

    @State private var query = ""
    @State private var results: [UntisSchool] = []
    @State private var picked: UntisSchool? = nil
    @State private var user = ""
    @State private var password = ""
    @State private var searching = false
    @State private var searchMessage = ""
    @State private var mode: UntisLoginMode = .secret
    @State private var qrLink = ""

    var body: some View {
        NavigationStack {
            Form {
                if untis.isLoggedIn, let school = untis.school {
                    connectedSection(school)
                } else {
                    loginSections
                }
                if !untis.status.isEmpty {
                    Section {
                        Text(untis.status)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Untis")
        }
    }

    // MARK: Verbunden

    @ViewBuilder
    private func connectedSection(_ school: UntisSchool) -> some View {
        Section("Verbunden mit Untis") {
            LabeledContent("Schule", value: school.displayName)
            LabeledContent("Benutzer", value: untis.username)
            if let last = untis.lastSync {
                LabeledContent("Zuletzt geladen", value: last.german("d. MMM, HH:mm 'Uhr'"))
            }
        }
        Section {
            Button {
                Task { await untis.sync(store: store) }
            } label: {
                HStack {
                    Label("Jetzt Hausaufgaben laden", systemImage: "arrow.clockwise")
                    if untis.isBusy { Spacer(); ProgressView() }
                }
            }
            .disabled(untis.isBusy)
            Button("Abmelden", role: .destructive) { untis.logout() }
        } footer: {
            Text("Neue Hausaufgaben aus Untis kommen automatisch in deine Liste, wenn du die App öffnest. Was du abhakst, bleibt abgehakt.")
        }
    }

    // MARK: Anmelden

    @ViewBuilder
    private var loginSections: some View {
        Section {
            Picker("Anmeldung", selection: $mode) {
                ForEach(UntisLoginMode.allCases) { m in Text(m.rawValue).tag(m) }
            }
            .pickerStyle(.segmented)
        } header: {
            Text("Wie meldest du dich bei Untis an?")
        } footer: {
            Text(mode == .secret
                 ? "Für Schulen, bei denen du dich mit einem Schulaccount anmeldest. Du brauchst den Schlüssel aus WebUntis: Profil → Freigaben → Zugriff über Untis Mobile → Anzeigen."
                 : "Wenn du für Untis einen eigenen Benutzernamen und ein Passwort hast.")
        }

        if mode == .secret {
            Section {
                TextField("untis://setschool?…", text: $qrLink, axis: .vertical)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .lineLimit(1...4)
                if let qr = UntisQRData(link: qrLink) {
                    LabeledContent("Schule", value: qr.school.loginName)
                    LabeledContent("Benutzer", value: qr.user)
                    Button {
                        Task {
                            await untis.login(school: qr.school, user: qr.user,
                                              credential: .secret(qr.key), store: store)
                            if untis.isLoggedIn { qrLink = "" }
                        }
                    } label: {
                        HStack {
                            Text("Anmelden und Hausaufgaben laden")
                            if untis.isBusy { Spacer(); ProgressView() }
                        }
                    }
                    .disabled(untis.isBusy)
                } else if !qrLink.isEmpty {
                    Text("Das ist kein gültiger Untis-Link.").foregroundColor(.red)
                }
            } header: {
                Text("Weg A: Link aus dem QR-Code einfügen")
            } footer: {
                Text("Wenn du den Link aus dem QR-Code kopieren kannst, füge ihn hier ein. Sonst nimm Weg B darunter.")
            }
        }

        if mode == .password || UntisQRData(link: qrLink) == nil {
            schoolSearchSection
        }
    }

    @ViewBuilder
    private var schoolSearchSection: some View {
        Section {
            HStack {
                TextField("Name oder Ort der Schule", text: $query)
                    .autocorrectionDisabled()
                    .onSubmit { search() }
                if searching {
                    ProgressView()
                } else {
                    Button("Suchen") { search() }
                        .disabled(query.trimmingCharacters(in: .whitespaces).count < 3)
                }
            }
            if !searchMessage.isEmpty {
                Text(searchMessage).font(.subheadline).foregroundColor(.secondary)
            }
            ForEach(results) { school in
                Button {
                    picked = school
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(school.displayName).foregroundColor(.primary)
                            if !school.address.isEmpty {
                                Text(school.address).font(.caption).foregroundColor(.secondary)
                            }
                        }
                        Spacer()
                        if picked == school {
                            Image(systemName: "checkmark").foregroundColor(.purple)
                        }
                    }
                }
            }
        } header: {
            Text(mode == .secret ? "Weg B: 1. Schule suchen" : "1. Schule suchen")
        }

        if let school = picked {
            Section {
                TextField("Benutzername", text: $user)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField(mode == .secret ? "Schlüssel (aus WebUntis)" : "Passwort", text: $password)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button {
                    Task {
                        let cleaned = user.trimmingCharacters(in: .whitespaces)
                        let credential: UntisCredential = mode == .secret
                            ? .secret(password.replacingOccurrences(of: " ", with: ""))
                            : .password(password)
                        await untis.login(school: school, user: cleaned,
                                          credential: credential, store: store)
                        if untis.isLoggedIn { password = "" }
                    }
                } label: {
                    HStack {
                        Text("Anmelden und Hausaufgaben laden")
                        if untis.isBusy { Spacer(); ProgressView() }
                    }
                }
                .disabled(user.isEmpty || password.isEmpty || untis.isBusy)
            } header: {
                Text("2. Bei \(school.displayName) anmelden")
            } footer: {
                Text(mode == .secret
                     ? "Benutzername und Schlüssel stehen in WebUntis unter Profil → Freigaben → Anzeigen. Der Schlüssel bleibt sicher im Schlüsselbund deines iPads."
                     : "Das sind dieselben Daten wie in der Untis-App. Dein Passwort bleibt sicher im Schlüsselbund deines iPads.")
            }
        }
    }

    private func search() {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard q.count >= 3, !searching else { return }
        searching = true
        searchMessage = ""
        picked = nil
        Task {
            do {
                let found = try await UntisAPI.searchSchools(q)
                await MainActor.run {
                    results = found
                    searchMessage = found.isEmpty ? "Keine Schule gefunden." : ""
                    searching = false
                }
            } catch {
                await MainActor.run {
                    results = []
                    searchMessage = error.localizedDescription
                    searching = false
                }
            }
        }
    }
}
