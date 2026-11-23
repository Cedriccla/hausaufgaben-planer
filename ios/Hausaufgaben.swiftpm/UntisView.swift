import SwiftUI

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
            Text("1. Schule suchen")
        }

        if let school = picked {
            Section {
                TextField("Benutzername", text: $user)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField("Passwort", text: $password)
                Button {
                    Task {
                        await untis.login(school: school, user: user.trimmingCharacters(in: .whitespaces),
                                          password: password, store: store)
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
                Text("Das sind dieselben Daten wie in der Untis-App. Dein Passwort bleibt sicher im Schlüsselbund deines iPads.")
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
