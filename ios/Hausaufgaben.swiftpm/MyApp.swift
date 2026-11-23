import SwiftUI

@main
struct HausaufgabenApp: App {
    @StateObject private var store = HomeworkStore()
    @StateObject private var untis = UntisSync()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environmentObject(untis)
                .onAppear { Notifier.requestPermission() }
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var store: HomeworkStore
    @EnvironmentObject var untis: UntisSync
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView {
            TaskListView()
                .tabItem { Label("Aufgaben", systemImage: "checklist") }
            WeekView()
                .tabItem { Label("Woche", systemImage: "calendar") }
            FocusView()
                .tabItem { Label("Fokus", systemImage: "timer") }
            UntisView()
                .tabItem { Label("Untis", systemImage: "arrow.triangle.2.circlepath") }
        }
        .tint(.purple)
        .task { await untis.autoSync(store: store) }
        .onChange(of: scenePhase) { phase in
            if phase == .active {
                Task { await untis.autoSync(store: store) }
            }
        }
    }
}
