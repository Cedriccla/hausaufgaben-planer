import SwiftUI
import UserNotifications

// MARK: - Datenmodell

enum Priority: String, Codable, CaseIterable, Identifiable {
    case hoch, mittel, niedrig

    var id: String { rawValue }

    var label: String {
        switch self {
        case .hoch: return "Hoch – Test / Abgabe"
        case .mittel: return "Mittel"
        case .niedrig: return "Niedrig"
        }
    }

    var rank: Int {
        switch self {
        case .hoch: return 0
        case .mittel: return 1
        case .niedrig: return 2
        }
    }

    var color: Color {
        switch self {
        case .hoch: return .red
        case .mittel: return .orange
        case .niedrig: return .green
        }
    }
}

struct Homework: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var subject: String
    var title: String
    var due: Date
    var minutes: Int
    var priority: Priority
    var done: Bool = false
    var untisId: Int? = nil   // gesetzt, wenn die Aufgabe aus Untis kommt
}

// MARK: - Datum-Hilfen

let germanLocale = Locale(identifier: "de_DE")

extension Date {
    var startOfDay: Date { Calendar.current.startOfDay(for: self) }

    /// Anzahl Tage von `other` bis zu diesem Datum (heute = 0, morgen = 1, gestern = -1)
    func days(from other: Date) -> Int {
        Calendar.current.dateComponents([.day], from: other.startOfDay, to: startOfDay).day ?? 0
    }

    func german(_ pattern: String) -> String {
        let f = DateFormatter()
        f.locale = germanLocale
        f.dateFormat = pattern
        return f.string(from: self)
    }

    var relativeText: String {
        switch days(from: Date()) {
        case 0: return "heute"
        case 1: return "morgen"
        case -1: return "gestern"
        default: return german("EE, d. MMM")
        }
    }

    var dayKey: String { german("yyyy-MM-dd") }
}

// MARK: - Speicher (JSON-Datei auf dem iPad)

final class HomeworkStore: ObservableObject {
    @Published var items: [Homework] = [] { didSet { save() } }
    @Published var focusSessions: [String: Int] = [:] { didSet { save() } }

    private struct SaveData: Codable {
        var items: [Homework]
        var focusSessions: [String: Int]
    }

    private let fileURL: URL = FileManager.default
        .urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("hausaufgaben.json")

    private var loading = false

    init() { load() }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let saved = try? JSONDecoder().decode(SaveData.self, from: data) else { return }
        loading = true
        items = saved.items
        focusSessions = saved.focusSessions
        loading = false
    }

    private func save() {
        guard !loading else { return }
        let data = SaveData(items: items, focusSessions: focusSessions)
        if let encoded = try? JSONEncoder().encode(data) {
            try? encoded.write(to: fileURL, options: .atomic)
        }
    }

    // Aufgaben bearbeiten
    func add(_ hw: Homework) {
        items.append(hw)
        Notifier.scheduleReminder(for: hw)
    }

    func update(_ hw: Homework) {
        guard let i = items.firstIndex(where: { $0.id == hw.id }) else { return }
        items[i] = hw
        Notifier.scheduleReminder(for: hw)
    }

    func toggle(_ hw: Homework) {
        guard let i = items.firstIndex(where: { $0.id == hw.id }) else { return }
        items[i].done.toggle()
        Notifier.scheduleReminder(for: items[i])
    }

    func delete(_ hw: Homework) {
        items.removeAll { $0.id == hw.id }
        Notifier.cancelReminder(for: hw)
    }

    /// Hausaufgaben aus Untis übernehmen. Gibt zurück, wie viele neu sind.
    /// Bereits übernommene werden aktualisiert, ohne Dauer, Wichtigkeit oder Abhaken zu verlieren.
    func mergeUntis(_ list: [UntisHomework]) -> Int {
        var copy = items
        var added = 0
        var changed: [Homework] = []
        for u in list {
            if let i = copy.firstIndex(where: { $0.untisId == u.id }) {
                copy[i].subject = u.subject
                copy[i].title = u.text
                copy[i].due = u.due
                if u.completed { copy[i].done = true }
                changed.append(copy[i])
            } else {
                let hw = Homework(subject: u.subject, title: u.text, due: u.due,
                                  minutes: 30, priority: .mittel, done: u.completed, untisId: u.id)
                copy.append(hw)
                changed.append(hw)
                added += 1
            }
        }
        items = copy
        for hw in changed { Notifier.scheduleReminder(for: hw) }
        return added
    }

    // Fokus-Runden
    var sessionsToday: Int { focusSessions[Date().dayKey] ?? 0 }

    func addSession() {
        focusSessions[Date().dayKey, default: 0] += 1
    }

    // Statistiken
    var openItems: [Homework] { items.filter { !$0.done } }
    var dueTodayCount: Int { openItems.filter { $0.due.days(from: Date()) <= 0 }.count }
    var openMinutes: Int { openItems.reduce(0) { $0 + $1.minutes } }

    // Fächer und Farben
    var subjects: [String] {
        var seen = Set<String>()
        var result: [String] = []
        for hw in items {
            let key = hw.subject.lowercased()
            if !seen.contains(key) {
                seen.insert(key)
                result.append(hw.subject)
            }
        }
        return result
    }

    private let palette: [Color] = [
        Color(red: 0.36, green: 0.25, blue: 0.82),
        .red, .green, .orange, .teal, .pink,
        Color(red: 0.48, green: 0.55, blue: 0.07),
        .brown
    ]

    func color(for subject: String) -> Color {
        let list = subjects
        let index = list.firstIndex { $0.lowercased() == subject.lowercased() } ?? list.count
        return palette[index % palette.count]
    }
}

// MARK: - Mitteilungen

enum Notifier {
    static func requestPermission() {
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    /// Erinnerung am Tag vor der Abgabe um 16 Uhr
    static func scheduleReminder(for hw: Homework) {
        cancelReminder(for: hw)
        guard !hw.done,
              let dayBefore = Calendar.current.date(byAdding: .day, value: -1, to: hw.due) else { return }
        var comps = Calendar.current.dateComponents([.year, .month, .day], from: dayBefore)
        comps.hour = 16
        comps.minute = 0
        guard let fireDate = Calendar.current.date(from: comps), fireDate > Date() else { return }

        let content = UNMutableNotificationContent()
        content.title = "Hausaufgabe für morgen"
        content.body = "\(hw.subject): \(hw.title)"
        content.sound = .default

        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        UNUserNotificationCenter.current()
            .add(UNNotificationRequest(identifier: hw.id.uuidString, content: content, trigger: trigger))
    }

    static func cancelReminder(for hw: Homework) {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [hw.id.uuidString])
    }

    /// Meldung, wenn der Fokus-Timer abgelaufen ist (auch wenn die App im Hintergrund ist)
    static func scheduleTimerEnd(in seconds: Int, isBreak: Bool) {
        cancelTimer()
        guard seconds > 0 else { return }
        let content = UNMutableNotificationContent()
        content.title = isBreak ? "Pause vorbei" : "Fokus-Runde geschafft!"
        content.body = isBreak ? "Weiter geht's mit der nächsten Runde." : "Zeit für 5 Minuten Pause."
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(seconds), repeats: false)
        UNUserNotificationCenter.current()
            .add(UNNotificationRequest(identifier: "focus-timer", content: content, trigger: trigger))
    }

    static func cancelTimer() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: ["focus-timer"])
    }
}
