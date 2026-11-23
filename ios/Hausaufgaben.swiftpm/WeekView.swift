import SwiftUI

struct WeekView: View {
    @EnvironmentObject var store: HomeworkStore

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("So verteilt sich deine Arbeit auf die nächsten 7 Tage. Aufgaben erscheinen am Tag, bevor sie fällig sind. Ein roter Balken heißt: mehr als 90 Minuten – lieber etwas vorziehen!")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 12)], spacing: 12) {
                        ForEach(0..<7, id: \.self) { offset in
                            DayCard(offset: offset)
                        }
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Woche")
        }
    }
}

struct DayCard: View {
    @EnvironmentObject var store: HomeworkStore
    let offset: Int

    private var day: Date { Calendar.current.date(byAdding: .day, value: offset, to: Date()) ?? Date() }

    /// Arbeit für diesen Tag = Aufgaben, die am nächsten Tag fällig sind (heute auch alles Überfällige)
    private var work: [Homework] {
        store.openItems.filter { hw in
            let d = hw.due.days(from: Date())
            return offset == 0 ? d <= 1 : d == offset + 1
        }
    }

    private var minutes: Int { work.reduce(0) { $0 + $1.minutes } }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(offset == 0 ? "Heute" : day.german("EE, d.M."))
                .font(.headline)
            Text("\(minutes) Min. zu tun")
                .font(.caption)
                .foregroundColor(.secondary)
            ProgressView(value: min(1.0, Double(minutes) / 120.0))
                .tint(minutes > 90 ? .red : .purple)
            ForEach(work) { hw in
                HStack(alignment: .top, spacing: 6) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(store.color(for: hw.subject))
                        .frame(width: 4)
                    Text("\(hw.subject): \(hw.title)")
                        .font(.caption)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.tertiarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(offset == 0 ? Color.purple : Color.clear, lineWidth: 2)
        )
    }
}
