import Foundation
import Security
import SwiftUI

// MARK: - Untis-Daten

struct UntisSchool: Identifiable, Codable, Hashable {
    var server: String       // z. B. "nessa.webuntis.com"
    var loginName: String    // interner Schulname für den Login
    var displayName: String
    var address: String
    var id: String { server + "/" + loginName }
}

struct UntisHomework {
    let id: Int
    let subject: String
    let text: String
    let due: Date
    let completed: Bool
}

struct UntisError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

// MARK: - Verbindung zu WebUntis
// Untis hat keine offizielle öffentliche Schnittstelle. Die App nutzt dieselbe
// Schnittstelle wie die Untis-Webseite (JSON-RPC + REST für Hausaufgaben).

enum UntisAPI {
    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        config.timeoutIntervalForRequest = 20
        return URLSession(configuration: config)
    }()

    private static func rpc(_ url: URL, method: String, params: Any, cookie: String? = nil) async throws -> Any {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let cookie = cookie { request.setValue(cookie, forHTTPHeaderField: "Cookie") }
        let body: [String: Any] = ["id": "1", "method": method, "params": params, "jsonrpc": "2.0"]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, _) = try await send(request)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw UntisError(message: "Untis hat unerwartet geantwortet.")
        }
        if let err = json["error"] as? [String: Any] {
            let code = err["code"] as? Int ?? 0
            switch code {
            case -6003: throw UntisError(message: "Zu viele Treffer. Bitte genauer suchen (z. B. Name + Ort).")
            case -8504: throw UntisError(message: "Benutzername oder Passwort ist falsch.")
            case -8509, -8998: throw UntisError(message: "Deine Schule erlaubt diesen Zugriff leider nicht.")
            default: throw UntisError(message: "Untis-Fehler: \(err["message"] as? String ?? "unbekannt")")
            }
        }
        return json["result"] ?? NSNull()
    }

    private static func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch {
            throw UntisError(message: "Keine Verbindung zu Untis. Bist du im Internet?")
        }
    }

    /// Schulen suchen (wie in der Untis-App)
    static func searchSchools(_ query: String) async throws -> [UntisSchool] {
        let url = URL(string: "https://mobile.webuntis.com/ms/schoolquery2")!
        let result = try await rpc(url, method: "searchSchool", params: [["search": query]])
        let schools = (result as? [String: Any])?["schools"] as? [[String: Any]] ?? []
        return schools.compactMap { s in
            guard let server = s["server"] as? String,
                  let login = s["loginName"] as? String else { return nil }
            return UntisSchool(server: server,
                               loginName: login,
                               displayName: s["displayName"] as? String ?? login,
                               address: s["address"] as? String ?? "")
        }
    }

    private static func makeCookie(sessionId: String, school: UntisSchool) -> String {
        let encoded = Data(school.loginName.utf8).base64EncodedString()
        return "JSESSIONID=\(sessionId); schoolname=\"_\(encoded)\""
    }

    private static func rpcURL(_ school: UntisSchool) -> URL {
        var c = URLComponents()
        c.scheme = "https"
        c.host = school.server
        c.path = "/WebUntis/jsonrpc.svc"
        c.queryItems = [URLQueryItem(name: "school", value: school.loginName)]
        return c.url!
    }

    /// Anmelden, Hausaufgaben laden, wieder abmelden
    static func fetchHomework(school: UntisSchool, user: String, password: String) async throws -> [UntisHomework] {
        let auth = try await rpc(rpcURL(school), method: "authenticate",
                                 params: ["user": user, "password": password, "client": "Hausaufgaben"])
        guard let sessionId = (auth as? [String: Any])?["sessionId"] as? String else {
            throw UntisError(message: "Anmeldung bei Untis fehlgeschlagen.")
        }
        let sessionCookie = makeCookie(sessionId: sessionId, school: school)
        let logoutURL = rpcURL(school)
        defer {
            Task { _ = try? await UntisAPI.rpc(logoutURL, method: "logout", params: [String: Any](), cookie: sessionCookie) }
        }

        let today = Date()
        let start = Calendar.current.date(byAdding: .day, value: -14, to: today) ?? today
        let end = Calendar.current.date(byAdding: .day, value: 45, to: today) ?? today

        var c = URLComponents()
        c.scheme = "https"
        c.host = school.server
        c.path = "/WebUntis/api/homeworks/lessons"
        c.queryItems = [URLQueryItem(name: "startDate", value: untisDate(start)),
                        URLQueryItem(name: "endDate", value: untisDate(end))]
        var request = URLRequest(url: c.url!)
        request.setValue(sessionCookie, forHTTPHeaderField: "Cookie")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await send(request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw UntisError(message: "Hausaufgaben konnten nicht geladen werden (Fehler \(http.statusCode)). Vielleicht hat deine Schule die Hausaufgaben in Untis nicht freigeschaltet.")
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let payload = json["data"] as? [String: Any] else {
            throw UntisError(message: "Untis hat unerwartet geantwortet.")
        }

        var subjectByLesson: [Int: String] = [:]
        for lesson in payload["lessons"] as? [[String: Any]] ?? [] {
            if let id = lesson["id"] as? Int {
                subjectByLesson[id] = lesson["subject"] as? String ?? ""
            }
        }

        return (payload["homeworks"] as? [[String: Any]] ?? []).compactMap { hw in
            guard let id = hw["id"] as? Int,
                  let dueInt = hw["dueDate"] as? Int,
                  let due = dateFromUntis(dueInt) else { return nil }
            let lessonId = hw["lessonId"] as? Int ?? -1
            var subject = (subjectByLesson[lessonId] ?? "").trimmingCharacters(in: .whitespaces)
            if subject.isEmpty { subject = "Untis" }
            var text = (hw["text"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if text.isEmpty { text = "Hausaufgabe" }
            return UntisHomework(id: id, subject: subject, text: text, due: due,
                                 completed: hw["completed"] as? Bool ?? false)
        }
    }

    private static func untisDate(_ d: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: d)
        return String(format: "%04d%02d%02d", c.year ?? 2000, c.month ?? 1, c.day ?? 1)
    }

    private static func dateFromUntis(_ value: Int) -> Date? {
        var c = DateComponents()
        c.year = value / 10000
        c.month = (value / 100) % 100
        c.day = value % 100
        c.hour = 12
        return Calendar.current.date(from: c)
    }
}

// MARK: - Passwort sicher im Schlüsselbund speichern

enum Keychain {
    private static let service = "de.schule.hausaufgabenplaner.untis"

    private static func base(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    static func set(_ value: String, for account: String) {
        SecItemDelete(base(account) as CFDictionary)
        var add = base(account)
        add[kSecValueData as String] = Data(value.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }

    static func get(_ account: String) -> String? {
        var query = base(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(_ account: String) {
        SecItemDelete(base(account) as CFDictionary)
    }
}

// MARK: - Untis-Konto und automatischer Abgleich

final class UntisSync: ObservableObject {
    @Published var school: UntisSchool? = nil
    @Published var username: String = ""
    @Published var lastSync: Date? = nil
    @Published var status = ""
    @Published var isBusy = false

    private let defaults = UserDefaults.standard

    init() {
        if let data = defaults.data(forKey: "untis.school") {
            school = try? JSONDecoder().decode(UntisSchool.self, from: data)
        }
        username = defaults.string(forKey: "untis.user") ?? ""
        lastSync = defaults.object(forKey: "untis.lastSync") as? Date
    }

    var isLoggedIn: Bool {
        school != nil && !username.isEmpty && Keychain.get("password") != nil
    }

    /// Erstes Anmelden: Daten nur speichern, wenn der Login klappt
    @MainActor
    func login(school: UntisSchool, user: String, password: String, store: HomeworkStore) async {
        isBusy = true
        status = "Melde an …"
        defer { isBusy = false }
        do {
            let list = try await UntisAPI.fetchHomework(school: school, user: user, password: password)
            self.school = school
            self.username = user
            defaults.set(try? JSONEncoder().encode(school), forKey: "untis.school")
            defaults.set(user, forKey: "untis.user")
            Keychain.set(password, for: "password")
            finish(list, store: store)
        } catch {
            status = error.localizedDescription
        }
    }

    @MainActor
    func sync(store: HomeworkStore) async {
        guard let school = school, let password = Keychain.get("password"), !isBusy else { return }
        isBusy = true
        status = "Lade Hausaufgaben …"
        defer { isBusy = false }
        do {
            let list = try await UntisAPI.fetchHomework(school: school, user: username, password: password)
            finish(list, store: store)
        } catch {
            status = error.localizedDescription
        }
    }

    /// Beim Öffnen der App: höchstens alle 15 Minuten neu laden
    @MainActor
    func autoSync(store: HomeworkStore) async {
        guard isLoggedIn else { return }
        if let last = lastSync, Date().timeIntervalSince(last) < 15 * 60 { return }
        await sync(store: store)
    }

    @MainActor
    private func finish(_ list: [UntisHomework], store: HomeworkStore) {
        let added = store.mergeUntis(list)
        lastSync = Date()
        defaults.set(lastSync, forKey: "untis.lastSync")
        switch added {
        case 0: status = "Alles aktuell. Keine neuen Hausaufgaben."
        case 1: status = "1 neue Hausaufgabe aus Untis übernommen."
        default: status = "\(added) neue Hausaufgaben aus Untis übernommen."
        }
    }

    func logout() {
        Keychain.delete("password")
        defaults.removeObject(forKey: "untis.school")
        defaults.removeObject(forKey: "untis.user")
        defaults.removeObject(forKey: "untis.lastSync")
        school = nil
        username = ""
        lastSync = nil
        status = "Abgemeldet. Deine Aufgaben bleiben in der App."
    }
}
