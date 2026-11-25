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
    private var offToday: [Habit] { habits.filter { !$0.scheduled(now) } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                summary
                if habits.isEmpty {
                    ContentUnavailableView {
                        Label("No habits yet", systemImage: "square.grid.3x3.square")
                    } description: {
                        Text("Instant habits are a single tap. Timed habits run a Focus session.")
                    } actions: {
                        Button("Add a habit") { editor = HabitEditor.Draft() }
                            .buttonStyle(.borderedProminent)
                            .foregroundStyle(.black)
                    }
                    .frame(minHeight: 260)
                }
                ForEach(today) { habit in row(habit) }
                if !offToday.isEmpty {
                    Text("Not today")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.top, 10)
                        .padding(.leading, 4)
                    ForEach(offToday) { habit in row(habit) }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("New habit", systemImage: "plus") { editor = HabitEditor.Draft() }
            }
        }
        .task {
            while !Task.isCancelled {
                now = .now
                try? await Task.sleep(for: .seconds(30))
            }
        }
        .sheet(item: $editor) { HabitEditor(draft: $0) }
    }

    /// Today's scheduled habits written out as bits, one per habit.
    @ViewBuilder private var summary: some View {
        let bits = today.map { $0.completed(now) }
        let done = bits.filter { $0 }.count
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(now, format: .dateTime.weekday(.wide).day().month(.wide))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                if !bits.isEmpty {
                    Text("\(done) of \(bits.count)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(done == bits.count ? theme.color : .secondary)
                }
            }
            if !bits.isEmpty {
                bits.reduce(Text(verbatim: "")) { line, bit in
                    line + Text(verbatim: bit ? "1" : "0")
                        .foregroundStyle(bit ? theme.color : Color.secondary.opacity(0.45))
                }
                .tracking(8)
                .lineLimit(1)
                .minimumScaleFactor(0.4)
                .font(.system(size: 34, weight: .semibold, design: .monospaced))
                .shadow(color: theme.color.opacity(0.35), radius: 10)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(done) of \(bits.count) habits complete today")
            }
        }
        .padding(.bottom, 6)
    }

    private func row(_ habit: Habit) -> some View {
        let done = habit.completed(now)
        let scheduled = habit.scheduled(now)
        let timed = habit.minutes > 0
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                // The bit tile always toggles completion, for instant and timed habits alike.
                Button { toggle(habit) } label: {
                    Text(done ? "1" : "0")
                        .font(.system(.title3, design: .monospaced).bold())
                        .frame(width: 44, height: 44)
                        .foregroundStyle(done ? Color.black : theme.color)
                        .background(theme.color.opacity(done ? 1 : 0.12), in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .disabled(!scheduled)
                .accessibilityLabel("\(habit.title), \(done ? "complete" : "incomplete")")
                .accessibilityHint("Toggles completion")

                Button {
                    if timed { focus(habit) } else { toggle(habit) }
                } label: {
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(habit.title).font(.headline).foregroundStyle(.primary)
                            Text(subtitle(habit, scheduled: scheduled))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        if timed && scheduled {
                            Image(systemName: "play.circle.fill")
                                .font(.title2)
                                .foregroundStyle(theme.color)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!scheduled)
                .accessibilityHint(timed ? "Opens Focus" : "Toggles completion")

                Button { editor = HabitEditor.Draft(habit) } label: {
                    Image(systemName: "ellipsis")
                        .foregroundStyle(.secondary)
                        .frame(width: 32, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Edit \(habit.title)")
            }
            history(habit)
        }
        .padding(14)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 20))
        .opacity(scheduled ? 1 : 0.55)
        .contextMenu {
            if scheduled {
                Button(done ? "Mark incomplete" : "Mark complete",
                       systemImage: done ? "0.square" : "1.square") { toggle(habit) }
            }
            Button("Edit habit", systemImage: "pencil") { editor = HabitEditor.Draft(habit) }
        }
    }

    private func subtitle(_ habit: Habit, scheduled: Bool) -> String {
        let kind = habit.minutes > 0 ? "\(habit.minutes) min focus" : "Instant"
        return scheduled ? kind : "\(kind) · \(Habit.scheduleText(habit.weekdays))"
    }

    /// Recent days as a row of bits: filled for done, outlined for missed, a dash when not scheduled.
    private func history(_ habit: Habit) -> some View {
        let calendar = Calendar.current
        let logged = Set((habit.logs ?? []).map { calendar.startOfDay(for: $0.date) })
        let created = calendar.startOfDay(for: habit.createdAt)
        let start = calendar.startOfDay(for: now)
        let dates = (0..<historyDays).reversed().compactMap {
            calendar.date(byAdding: .day, value: -$0, to: start)
        }
        return HStack(spacing: historyDays == 30 ? 2 : 5) {
            ForEach(dates, id: \.self) { date in
                let done = logged.contains(date)
                let off = !habit.scheduled(date) || date < created
                Group {
                    if done {
                        RoundedRectangle(cornerRadius: 3).fill(theme.color)
                    } else if off {
                        Capsule().fill(.secondary.opacity(0.3)).frame(height: 2)
                    } else {
                        RoundedRectangle(cornerRadius: 3)
                            .strokeBorder(theme.color.opacity(date == start ? 0.7 : 0.3), lineWidth: 1)
                    }
                }
                .frame(maxWidth: 16, maxHeight: 16)
                .aspectRatio(1, contentMode: .fit)
                .accessibilityLabel("\(date.formatted(date: .abbreviated, time: .omitted)), \(done ? "done" : off ? "not scheduled" : "missed")")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 16)
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
    @AppStorage(Theme.key, store: Theme.defaults) private var theme = Theme.violet
    @State private var confirmDelete = false
    @State private var failure: String?
    private var title: String { draft.title.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Habit name", text: $draft.title)
                        .font(.headline)
                    Picker("Type", selection: $draft.timed) {
                        Text("Instant").tag(false)
                        Text("Timed").tag(true)
                    }
                    .pickerStyle(.segmented)
                    if draft.timed {
                        Stepper("\(draft.minutes) min focus", value: $draft.minutes, in: 1...180, step: 5)
                    }
                } footer: {
                    Text(draft.timed
                         ? "Starting this habit runs a Focus session. It logs itself when the Work interval ends."
                         : "Tap once to log it for the day.")
                }
                Section("Repeat") {
                    HStack(spacing: 6) {
                        ForEach(Calendar.current.orderedWeekdays, id: \.self) { day in
                            dayChip(day)
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
                    HStack {
                        presetButton("Daily", 127)
                        presetButton("Weekdays", 62)
                        presetButton("Weekends", 65)
                    }
                    .buttonStyle(.borderless)
                    .font(.subheadline)
                }
                if draft.habit != nil {
                    Section {
                        Button("Delete habit", role: .destructive) { confirmDelete = true }
                    }
                }
            }
            .navigationTitle(draft.habit == nil ? "New Habit" : "Edit Habit")
            .navigationBarTitleDisplayMode(.inline)
            .tint(theme.color)
            .fontDesign(.rounded)
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

    private func dayChip(_ day: Int) -> some View {
        let bit = 1 << day
        let on = draft.days & bit != 0
        return Button {
            if on { draft.days &= ~bit } else { draft.days |= bit }
        } label: {
            Text(Calendar.current.veryShortWeekdaySymbols[day])
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 38)
                .foregroundStyle(on ? Color.black : .secondary)
                .background(on ? AnyShapeStyle(.tint) : AnyShapeStyle(Color.secondary.opacity(0.15)),
                            in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Calendar.current.weekdaySymbols[day])
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func presetButton(_ title: String, _ days: Int) -> some View {
        Button(title) { draft.days = days }
            .frame(maxWidth: .infinity)
            .foregroundStyle(draft.days == days ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
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
