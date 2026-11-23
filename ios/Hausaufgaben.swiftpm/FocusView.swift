import SwiftUI

struct TimerPreset: Identifiable {
    let label: String
    let minutes: Int
    let isBreak: Bool
    var id: String { label }
}

struct FocusView: View {
    @EnvironmentObject var store: HomeworkStore

    @State private var total = 25 * 60
    @State private var remaining = 25 * 60
    @State private var endDate: Date? = nil
    @State private var isBreak = false
    @State private var showDone = false
    @State private var finishedBreak = false

    private let tick = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    private let presets = [
        TimerPreset(label: "25 Min. Fokus", minutes: 25, isBreak: false),
        TimerPreset(label: "15 Min.", minutes: 15, isBreak: false),
        TimerPreset(label: "45 Min.", minutes: 45, isBreak: false),
        TimerPreset(label: "5 Min. Pause", minutes: 5, isBreak: true)
    ]

    private var timeString: String {
        String(format: "%02d:%02d", remaining / 60, remaining % 60)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    HStack {
                        ForEach(presets) { p in
                            Button(p.label) { select(p) }
                                .buttonStyle(.bordered)
                                .tint(total == p.minutes * 60 && isBreak == p.isBreak ? .purple : .gray)
                        }
                    }

                    ZStack {
                        Circle()
                            .stroke(Color.gray.opacity(0.2), lineWidth: 16)
                        Circle()
                            .trim(from: 0, to: CGFloat(remaining) / CGFloat(max(total, 1)))
                            .stroke(isBreak ? Color.green : Color.purple,
                                    style: StrokeStyle(lineWidth: 16, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .animation(.linear(duration: 0.5), value: remaining)
                        VStack(spacing: 4) {
                            Text(timeString)
                                .font(.system(size: 64, weight: .bold, design: .rounded))
                                .monospacedDigit()
                            Text(isBreak ? "Pause" : "Fokus-Zeit")
                                .foregroundColor(.secondary)
                        }
                    }
                    .frame(width: 280, height: 280)

                    HStack(spacing: 12) {
                        Button(endDate == nil ? "Start" : "Pause") { startOrPause() }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                        Button("Zurücksetzen") { reset() }
                            .buttonStyle(.bordered)
                            .controlSize(.large)
                    }

                    Text("Heute geschafft: \(store.sessionsToday) Fokus-Runde(n)")
                        .foregroundColor(.secondary)

                    GroupBox("So klappt's") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("1. Handy weg, nur das Nötige auf dem Tisch.")
                            Text("2. Eine Aufgabe auswählen – nur an der arbeitest du.")
                            Text("3. 25 Minuten konzentriert arbeiten.")
                            Text("4. 5 Minuten Pause: aufstehen, trinken, bewegen.")
                            Text("5. Nach 4 Runden eine längere Pause (15–30 Min.).")
                        }
                        .font(.subheadline)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxWidth: 520)
                }
                .padding()
                .frame(maxWidth: .infinity)
            }
            .navigationTitle("Fokus")
            .onReceive(tick) { _ in update() }
            .alert(finishedBreak ? "Pause vorbei – weiter geht's!" : "Super! Fokus-Runde geschafft. Zeit für eine Pause.",
                   isPresented: $showDone) {
                Button("OK", role: .cancel) {}
            }
        }
    }

    private func select(_ p: TimerPreset) {
        stop()
        total = p.minutes * 60
        remaining = total
        isBreak = p.isBreak
    }

    private func startOrPause() {
        if endDate != nil {
            stop()
        } else {
            endDate = Date().addingTimeInterval(TimeInterval(remaining))
            Notifier.scheduleTimerEnd(in: remaining, isBreak: isBreak)
        }
    }

    private func stop() {
        endDate = nil
        Notifier.cancelTimer()
    }

    private func reset() {
        stop()
        remaining = total
    }

    private func update() {
        guard let end = endDate else { return }
        remaining = max(0, Int(end.timeIntervalSinceNow.rounded()))
        if remaining == 0 {
            endDate = nil
            finishedBreak = isBreak
            if !isBreak { store.addSession() }
            remaining = total
            showDone = true
        }
    }
}
