import SwiftData
import SwiftUI

@main
struct BinaryWatch: App {
    @State private var store: ModelContainer?
    @State private var attempted = false

    var body: some Scene {
        WindowGroup {
            if let store {
                WatchHabits().modelContainer(store)
            } else if attempted {
                ContentUnavailableView("Habits unavailable", systemImage: "icloud.slash")
            } else {
                ProgressView().task {
                    store = try? HabitStore.make(sync: true)
                    attempted = true
                }
            }
        }
    }
}

struct WatchHabits: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Habit.createdAt) private var habits: [Habit]
    @State private var failure: String?

    var body: some View {
        NavigationStack {
            let today = Date.now
            let instant = habits.filter { $0.minutes == 0 && $0.scheduled(today) }
            if instant.isEmpty {
                ContentUnavailableView("No instant habits today", systemImage: "circle.dotted")
                    .navigationTitle("Binary")
            } else {
                List(instant) { habit in
                    Button {
                        do { try habit.setCompleted(!habit.completed(today), date: today, in: context) }
                        catch { failure = error.localizedDescription }
                    } label: {
                        Label(habit.title, systemImage: habit.completed(today) ? "1.square.fill" : "0.square")
                    }
                }
                .navigationTitle("Binary")
            }
        }
        .alert("Couldn’t update habit",
               isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) {
            Button("OK") { failure = nil }
        } message: { Text(failure ?? "") }
    }
}
