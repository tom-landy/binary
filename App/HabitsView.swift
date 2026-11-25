import SwiftData
import SwiftUI
import WidgetKit

struct HabitsView: View {
    let habits: [Habit]
    let theme: Theme
    let toggle: (Habit) -> Void
    let focus: (Habit) -> Void

    @AppStorage("historyDays") private var historyDays = 14
    @State private var editor: HabitEditor.Draft?
    @State private var now = Date.now

    private var today: [Habit] { habits.filter { $0.scheduled(now) } }
    private var completed: Int { today.filter { $0.completed(now) }.count }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Today").font(.title2.bold())
                        Text(now, format: .dateTime.weekday(.wide).month(.abbreviated).day())
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("\(completed) / \(today.count)").font(.system(.title2, design: .monospaced).bold())
                        .foregroundStyle(theme.color)
                        .accessibilityLabel("\(completed) of \(today.count) habits complete")
                    Button { editor = HabitEditor.Draft() } label: {
                        Image(systemName: "plus").frame(width: 44, height: 44)
                            .background(theme.color.opacity(0.12), in: Circle())
                    }.accessibilityLabel("New habit")
                }
                if habits.isEmpty {
                    ContentUnavailableView("Your habits go here", systemImage: "circle.grid.2x2",
                                           description: Text("Add an instant or timed habit to get started."))
                        .frame(minHeight: 220)
                }
                ForEach(habits) { habit in row(habit) }
            }
            .padding(22)
        }
        .task {
            while !Task.isCancelled {
                now = .now
                try? await Task.sleep(for: .seconds(30))
            }
        }
        .sheet(item: $editor) { HabitEditor(draft: $0) }
    }

    private func row(_ habit: Habit) -> some View {
        let done = habit.completed(now)
        let scheduled = habit.scheduled(now)
        return VStack(alignment: .leading, spacing: 15) {
            HStack {
                Button {
                    if scheduled {
                        if habit.minutes > 0 { focus(habit) } else { toggle(habit) }
                    }
                } label: {
                    HStack(spacing: 12) {
                        Text(done ? "1" : "0")
                            .font(.system(.title3, design: .monospaced).bold())
                            .frame(width: 41, height: 41)
                            .foregroundStyle(done ? Color.black : theme.color)
                            .background(theme.color.opacity(done ? 1 : 0.12), in: RoundedRectangle(cornerRadius: 12))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(habit.title).font(.headline).foregroundStyle(.primary)
                            Text(scheduled ? (habit.minutes > 0 ? "\(habit.minutes) min focus" : "Instant") : "Off schedule")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!scheduled)
                .accessibilityHint(habit.minutes > 0 ? "Opens Focus" : "Toggles completion")
                .contextMenu {
                    if scheduled && habit.minutes > 0 {
                        Button(done ? "Mark incomplete" : "Mark complete") { toggle(habit) }
                    }
                    Button("Edit habit", systemImage: "pencil") { editor = HabitEditor.Draft(habit) }
                }
                Button { editor = HabitEditor.Draft(habit) } label: {
                    Image(systemName: "ellipsis").frame(width: 44, height: 44)
                }.accessibilityLabel("Edit \(habit.title)")
            }
            matrix(habit)
        }
        .padding(15)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 21))
    }

    private func matrix(_ habit: Habit) -> some View {
        let dates = (0..<historyDays).reversed().compactMap {
            Calendar.current.date(byAdding: .day, value: -$0, to: now)
        }
        return HStack(spacing: historyDays == 30 ? 3 : 7) {
            ForEach(dates, id: \.self) { date in
                let done = habit.completed(date)
                let off = !habit.scheduled(date) ||
                    Calendar.current.startOfDay(for: date) < Calendar.current.startOfDay(for: habit.createdAt)
                Group {
                    if done {
                        Circle().fill(theme.color).shadow(color: theme.color.opacity(0.6), radius: 4)
                    } else if off {
                        Capsule().fill(.secondary.opacity(0.35)).frame(height: 2)
                    } else {
                        Circle().strokeBorder(theme.color.opacity(0.33), lineWidth: 1)
                    }
                }
                .frame(maxWidth: 13, maxHeight: 13)
                .aspectRatio(1, contentMode: .fit)
                .accessibilityLabel("\(date.formatted(date: .abbreviated, time: .omitted)), \(done ? "done" : off ? "off schedule" : "incomplete")")
            }
        }
        .frame(height: 15)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Last \(historyDays) days")
    }
}

struct HabitEditor: View {
    struct Draft: Identifiable {
        let id = UUID()
        var habit: Habit?
        var title = ""
        var timed = false
        var minutes = 25
        var days = 127

        init(_ habit: Habit? = nil) {
            self.habit = habit
            if let habit {
                title = habit.title
                timed = habit.minutes > 0
                minutes = timed ? habit.minutes : 25
                days = habit.weekdays
            }
        }
    }

    @State var draft: Draft
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var confirmDelete = false
    @State private var failure: String?
    private var title: String { draft.title.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Habit name", text: $draft.title)
                Toggle("Timed habit", isOn: $draft.timed)
                if draft.timed { Stepper("\(draft.minutes) minutes", value: $draft.minutes, in: 1...180) }
                Section("Schedule") {
                    Picker("Repeat", selection: $draft.days) {
                        Text("Daily").tag(127)
                        Text("Weekdays").tag(62)
                        Text("Weekends").tag(65)
                        if ![127, 62, 65].contains(draft.days) {
                            Text("Custom").tag(draft.days)
                        }
                    }
                    ForEach(Array(Calendar.current.weekdaySymbols.enumerated()), id: \.offset) { day, name in
                        let bit = 1 << day
                        Toggle(name, isOn: Binding(
                            get: { draft.days & bit != 0 },
                            set: { if $0 { draft.days |= bit } else { draft.days &= ~bit } }
                        ))
                    }
                }
                if draft.habit != nil {
                    Button("Delete habit", role: .destructive) { confirmDelete = true }
                }
            }
            .navigationTitle(draft.habit == nil ? "New Habit" : "Edit Habit")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).disabled(title.isEmpty || draft.days == 0)
                }
            }
            .confirmationDialog("Delete this habit and its history?", isPresented: $confirmDelete) {
                Button("Delete habit", role: .destructive) {
                    if let habit = draft.habit { context.delete(habit) }
                    persist()
                }
            }
            .alert("Couldn’t save", isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) {
                Button("OK") { failure = nil }
            } message: { Text(failure ?? "") }
        }
    }

    private func save() {
        let minutes = draft.timed ? draft.minutes : 0
        if let habit = draft.habit {
            habit.title = title
            habit.minutes = minutes
            habit.weekdays = draft.days
        } else {
            context.insert(Habit(title: title, minutes: minutes, weekdays: draft.days))
        }
        persist()
    }

    private func persist() {
        do {
            try context.save()
            WidgetCenter.shared.reloadAllTimelines()
            dismiss()
        } catch {
            context.rollback()
            failure = error.localizedDescription
        }
    }
}
