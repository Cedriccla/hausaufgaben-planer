import SwiftUI

struct HomeworkGroup: Identifiable {
    let name: String
    let items: [Homework]
    let isLate: Bool
    var id: String { name }
}

enum TaskFilter: String, CaseIterable, Identifiable {
    case open = "Offen"
    case done = "Erledigt"
    case all = "Alle"
    var id: String { rawValue }
}

struct TaskListView: View {
    @EnvironmentObject var store: HomeworkStore
    @EnvironmentObject var untis: UntisSync
    @State private var filter: TaskFilter = .open
    @State private var editing: Homework? = nil
    @State private var showNew = false

    private var filtered: [Homework] {
        store.items
            .filter { hw in
                switch filter {
                case .open: return !hw.done
                case .done: return hw.done
                case .all: return true
                }
            }
            .sorted { a, b in
                if a.due.startOfDay != b.due.startOfDay { return a.due < b.due }
                return a.priority.rank < b.priority.rank
            }
    }

    private var groups: [HomeworkGroup] {
        let list = filtered
        let now = Date()
        func d(_ hw: Homework) -> Int { hw.due.days(from: now) }
        let defs: [(String, (Homework) -> Bool, Bool)] = [
            ("Überfällig", { d($0) < 0 && !$0.done }, true),
            ("Heute", { d($0) == 0 }, false),
            ("Morgen", { d($0) == 1 }, false),
            ("Diese Woche", { d($0) > 1 && d($0) <= 7 }, false),
            ("Später", { d($0) > 7 }, false),
            ("Früher", { d($0) < 0 && $0.done }, false)
        ]
        var result: [HomeworkGroup] = []
        for (name, test, late) in defs {
            let items = list.filter(test)
            if !items.isEmpty { result.append(HomeworkGroup(name: name, items: items, isLate: late)) }
        }
        return result
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    StatsRow()
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
                Section {
                    Picker("Anzeigen", selection: $filter) {
                        ForEach(TaskFilter.allCases) { f in Text(f.rawValue).tag(f) }
                    }
                    .pickerStyle(.segmented)
                }
                if groups.isEmpty {
                    Section {
                        VStack(spacing: 8) {
                            Text(filter == .done ? "Noch nichts erledigt." : "🎉 Keine offenen Aufgaben!")
                                .font(.headline)
                            if filter != .done {
                                Text("Tippe oben rechts auf +, um eine Hausaufgabe einzutragen.")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                    }
                }
                ForEach(groups) { group in
                    Section {
                        ForEach(group.items) { hw in
                            HomeworkRow(hw: hw)
                                .contentShape(Rectangle())
                                .onTapGesture { editing = hw }
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) { store.delete(hw) } label: {
                                        Label("Löschen", systemImage: "trash")
                                    }
                                }
                                .swipeActions(edge: .leading) {
                                    Button { store.toggle(hw) } label: {
                                        Label(hw.done ? "Offen" : "Erledigt", systemImage: "checkmark")
                                    }
                                    .tint(.green)
                                }
                        }
                    } header: {
                        Text("\(group.name) · \(group.items.count)")
                            .foregroundColor(group.isLate ? .red : .secondary)
                    }
                }
            }
            .refreshable {
                // Nach unten ziehen lädt neue Hausaufgaben aus Untis
                await untis.sync(store: store)
            }
            .navigationTitle("Hausaufgaben")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showNew = true } label: {
                        Label("Neue Aufgabe", systemImage: "plus.circle.fill")
                            .font(.title2)
                    }
                }
            }
            .sheet(isPresented: $showNew) {
                EditView(original: nil).environmentObject(store)
            }
            .sheet(item: $editing) { hw in
                EditView(original: hw).environmentObject(store)
            }
        }
    }
}

struct StatsRow: View {
    @EnvironmentObject var store: HomeworkStore

    var body: some View {
        HStack(spacing: 12) {
            StatBox(value: store.openItems.count, label: "offen", color: .purple)
            StatBox(value: store.dueTodayCount, label: "heute fällig", color: .red)
            StatBox(value: store.openMinutes, label: "Min. Arbeit", color: .orange)
        }
    }
}

struct StatBox: View {
    let value: Int
    let label: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(value)")
                .font(.system(.title, design: .rounded).bold())
                .foregroundColor(color)
            Text(label)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct HomeworkRow: View {
    @EnvironmentObject var store: HomeworkStore
    let hw: Homework

    var body: some View {
        HStack(spacing: 14) {
            Button { store.toggle(hw) } label: {
                Image(systemName: hw.done ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundColor(hw.done ? .green : .secondary)
            }
            .buttonStyle(.plain)

            Circle()
                .fill(store.color(for: hw.subject))
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 4) {
                Text(hw.title)
                    .font(.headline)
                    .strikethrough(hw.done)
                HStack(spacing: 10) {
                    Text(hw.subject).bold()
                    Label(hw.due.relativeText, systemImage: "calendar")
                    Label("\(hw.minutes) Min.", systemImage: "timer")
                    if hw.untisId != nil {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .accessibilityLabel("aus Untis")
                    }
                    Text(hw.priority.rawValue)
                        .font(.caption.bold())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(hw.priority.color.opacity(0.18))
                        .foregroundColor(hw.priority.color)
                        .clipShape(Capsule())
                }
                .font(.subheadline)
                .foregroundColor(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .opacity(hw.done ? 0.5 : 1)
    }
}

struct EditView: View {
    @EnvironmentObject var store: HomeworkStore
    @Environment(\.dismiss) private var dismiss

    let original: Homework?

    @State private var subject = ""
    @State private var title = ""
    @State private var due = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
    @State private var minutes = 30
    @State private var priority: Priority = .mittel
    @State private var loaded = false

    private var canSave: Bool {
        !subject.trimmingCharacters(in: .whitespaces).isEmpty &&
        !title.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Fach") {
                    TextField("z. B. Mathe", text: $subject)
                    if !store.subjects.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack {
                                ForEach(store.subjects, id: \.self) { s in
                                    Button(s) { subject = s }
                                        .buttonStyle(.bordered)
                                        .tint(store.color(for: s))
                                }
                            }
                        }
                    }
                }
                Section("Was ist zu tun?") {
                    TextField("z. B. S. 42, Nr. 3–5", text: $title, axis: .vertical)
                        .lineLimit(2...5)
                }
                Section {
                    DatePicker("Fällig am", selection: $due, displayedComponents: .date)
                        .environment(\.locale, germanLocale)
                    Stepper("Dauer: \(minutes) Min.", value: $minutes, in: 5...240, step: 5)
                    Picker("Wichtigkeit", selection: $priority) {
                        ForEach(Priority.allCases) { p in Text(p.label).tag(p) }
                    }
                }
                if let o = original {
                    Section {
                        Button("Aufgabe löschen", role: .destructive) {
                            store.delete(o)
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(original == nil ? "Neue Aufgabe" : "Aufgabe bearbeiten")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Speichern") { save() }
                        .disabled(!canSave)
                }
            }
            .onAppear {
                guard !loaded else { return }
                loaded = true
                if let o = original {
                    subject = o.subject
                    title = o.title
                    due = o.due
                    minutes = o.minutes
                    priority = o.priority
                }
            }
        }
    }

    private func save() {
        let s = subject.trimmingCharacters(in: .whitespaces)
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if var o = original {
            o.subject = s
            o.title = t
            o.due = due
            o.minutes = minutes
            o.priority = priority
            store.update(o)
        } else {
            store.add(Homework(subject: s, title: t, due: due, minutes: minutes, priority: priority))
        }
        dismiss()
    }
}
