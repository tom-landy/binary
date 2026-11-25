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
                    let done = habit.completed(today)
                    Button {
                        do { try habit.setCompleted(!done, date: today, in: context) }
                        catch { failure = error.localizedDescription }
                    } label: {
                        HStack(spacing: 10) {
                            ZStack {
                                if done {
                                    Circle().fill(Theme.violet.color)
                                } else {
                                    Circle().strokeBorder(Theme.track, lineWidth: 2)
                                }
                                Text(done ? "1" : "0")
                                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                                    .foregroundStyle(done ? Theme.violet.onColor : Theme.tertiary)
                            }
                            .frame(width: 24, height: 24)
                            Text(habit.title).lineLimit(2)
                        }
                    }
                    .accessibilityLabel("\(habit.title), \(done ? "done" : "not done")")
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
