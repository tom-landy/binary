import SwiftData
import SwiftUI
import WidgetKit

// MARK: - Today

struct HabitsView: View {
    let habits: [Habit]
    let theme: Theme
    let toggle: (Habit) -> Void
    let focus: (Habit) -> Void
    let openSettings: () -> Void

    @State private var editor: HabitEditor.Draft?
    @State private var now = Date.now

    /// Width of each past-day column and of today's wider, tappable column.
    static let dayColumn: CGFloat = 26
    static let todayColumn: CGFloat = 40
    static let columnSpacing: CGFloat = 2
    static let rowHeight: CGFloat = 60

    private var calendar: Calendar { .current }
    private var today: [Habit] { habits.filter { $0.scheduled(now) } }
    private var offToday: [Habit] { habits.filter { !$0.scheduled(now) } }

    /// The last seven days, oldest first, ending today.
    private var week: [Date] {
        let start = calendar.startOfDay(for: now)
        return (0..<7).reversed().compactMap { calendar.date(byAdding: .day, value: -$0, to: start) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                if habits.isEmpty {
                    empty
                } else {
                    summary
                    matrix
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 32)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .background(Theme.background)
        .task {
            while !Task.isCancelled {
                now = .now
                try? await Task.sleep(for: .seconds(30))
            }
        }
        .sheet(item: $editor) { HabitEditor(draft: $0) }
    }

    // MARK: Header and summary

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(now, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated)).label()
                Spacer()
                HStack(spacing: 10) {
                    CircleIconButton(systemImage: "plus", label: "New habit") { editor = HabitEditor.Draft() }
                    CircleIconButton(systemImage: "gearshape", label: "Settings", action: openSettings)
                }
            }
            .frame(height: 44)
            Text("Today")
                .font(.system(size: 34, weight: .bold))
                .tracking(-0.8)
                .foregroundStyle(Theme.text)
        }
    }

    private var summary: some View {
        let bits = today.map { $0.completed(now) }
        let done = bits.filter { $0 }.count
        let streak = Habit.perfectStreak(habits, today: now)
        return VStack(spacing: 16) {
            HStack(alignment: .lastTextBaseline) {
                (Text("\(done)").foregroundStyle(Theme.text)
                 + Text("/\(bits.count)").foregroundStyle(Theme.tertiary))
                    .font(.system(size: 56, weight: .light, design: .monospaced))
                    .tracking(-2)
                    .accessibilityLabel("\(done) of \(bits.count) done today")
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text("Perfect days").label()
                    Text(streak == 1 ? "1 day" : "\(streak) in a row")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(streak > 0 ? Theme.text : Theme.secondary)
                }
                .accessibilityElement(children: .combine)
            }
            if !bits.isEmpty {
                HStack(spacing: 4) {
                    ForEach(Array(bits.enumerated()), id: \.offset) { _, bit in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(bit ? theme.color : Theme.raised)
                            .frame(height: 6)
                    }
                }
                .accessibilityHidden(true)
            }
        }
        .padding(.top, 22)
        .padding(.bottom, 26)
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 4) {
                ForEach(0..<7, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 5)
                        .fill(index.isMultiple(of: 3) ? theme.color : Theme.raised)
                        .frame(width: 22, height: 22)
                }
            }
            .padding(.bottom, 6)
            Text("Track anything as a 1 or a 0.")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Theme.text)
            Text("Instant habits are a single tap. Timed habits run a Focus session and log themselves when it ends.")
                .font(.subheadline)
                .foregroundStyle(Theme.secondary)
            PrimaryButton(title: "Add your first habit", systemImage: "plus", theme: theme) {
                editor = HabitEditor.Draft()
            }
            .padding(.top, 10)
        }
        .padding(.top, 40)
    }

    // MARK: Matrix

    private var matrix: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(spacing: 0) {
                dayHeader
                ForEach(today) { habit in row(habit) }
            }
            .background(alignment: .trailing) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(theme.color.opacity(0.14))
                    .frame(width: Self.todayColumn)
            }
            if !offToday.isEmpty {
                Text("Not today").label()
                    .frame(height: 40, alignment: .bottom)
                    .padding(.bottom, 8)
                ForEach(offToday) { habit in row(habit).opacity(0.45) }
            }
            Text("Hold a habit to edit it.")
                .font(.footnote)
                .foregroundStyle(Theme.tertiary)
                .padding(.top, 18)
        }
    }

    private var dayHeader: some View {
        let week = self.week
        return HStack(spacing: Self.columnSpacing) {
            Spacer(minLength: 0)
            ForEach(week, id: \.self) { day in
                let isToday = day == week.last
                Text(calendar.veryShortWeekdaySymbols[calendar.component(.weekday, from: day) - 1])
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(isToday ? theme.color : Theme.tertiary)
                    .frame(width: isToday ? Self.todayColumn : Self.dayColumn, height: 28)
            }
        }
        .accessibilityHidden(true)
    }

    private func row(_ habit: Habit) -> some View {
        let week = self.week
        let logged = habit.loggedDays()
        let timed = habit.minutes > 0
        let doneToday = logged.contains(week.last ?? now)
        let scheduled = habit.scheduled(now)
        return HStack(spacing: Self.columnSpacing) {
            Button {
                if timed { focus(habit) } else { toggle(habit) }
            } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text(habit.title)
                        .font(.system(size: 16, weight: .semibold))
                        .tracking(-0.2)
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                    meta(habit, scheduled: scheduled, done: doneToday)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!scheduled)
            .accessibilityHint(timed ? "Starts a Focus session" : "Toggles today")

            ForEach(week, id: \.self) { day in
                let isToday = day == week.last
                if isToday {
                    Button { toggle(habit) } label: {
                        BitCell(state: cellState(habit, day: day, logged: logged), theme: theme, size: 26, today: true)
                            .frame(width: Self.todayColumn, height: Self.rowHeight)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!scheduled)
                    .accessibilityLabel("\(habit.title) today, \(doneToday ? "done" : "not done")")
                } else {
                    BitCell(state: cellState(habit, day: day, logged: logged), theme: theme, size: 20, today: false)
                        .frame(width: Self.dayColumn, height: Self.rowHeight)
                        .accessibilityHidden(true)
                }
            }
        }
        .frame(height: Self.rowHeight)
        .overlay(alignment: .top) { Rectangle().fill(Theme.line).frame(height: 0.5) }
        .contentShape(Rectangle())
        .contextMenu {
            if scheduled {
                Button(doneToday ? "Mark as not done" : "Mark as done",
                       systemImage: doneToday ? "0.square" : "1.square") { toggle(habit) }
            }
            if timed && scheduled {
                Button("Start focus", systemImage: "play") { focus(habit) }
            }
            Button("Edit habit", systemImage: "pencil") { editor = HabitEditor.Draft(habit) }
        }
    }

    @ViewBuilder
    private func meta(_ habit: Habit, scheduled: Bool, done: Bool) -> some View {
        let kind = habit.minutes > 0 ? "\(habit.minutes) min" : "Instant"
        if !scheduled {
            Text(Habit.scheduleText(habit.weekdays))
                .font(.system(size: 13))
                .foregroundStyle(Theme.secondary)
        } else if habit.minutes > 0 && !done {
            HStack(spacing: 6) {
                Text(kind).foregroundStyle(Theme.secondary)
                Text("·").foregroundStyle(Theme.tertiary)
                Label("Start", systemImage: "play.fill")
                    .labelStyle(.titleAndIcon)
                    .font(.system(size: 13, weight: .semibold))
                    .imageScale(.small)
                    .foregroundStyle(theme.color)
            }
            .font(.system(size: 13))
        } else {
            Text(kind)
                .font(.system(size: 13))
                .foregroundStyle(Theme.secondary)
        }
    }

    private func cellState(_ habit: Habit, day: Date, logged: Set<Date>) -> BitCell.Fill {
        if logged.contains(day) { return .on }
        return habit.due(on: day) ? .off : .notDue
    }
}

// MARK: - Shared pieces

struct BitCell: View {
    enum Fill { case on, off, notDue }
    let state: Fill
    let theme: Theme
    var size: CGFloat = 20
    var today = false

    var body: some View {
        let radius = size * 0.26
        switch state {
        case .on:
            RoundedRectangle(cornerRadius: radius).fill(theme.color)
                .frame(width: size, height: size)
        case .off:
            RoundedRectangle(cornerRadius: radius)
                .strokeBorder(today ? theme.color : Theme.faint, lineWidth: 1.5)
                .frame(width: size, height: size)
        case .notDue:
            Capsule().fill(Theme.faint).frame(width: 8, height: 2)
        }
    }
}

struct CircleIconButton: View {
    let systemImage: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.text)
                .frame(width: 36, height: 36)
                .background(Theme.surface, in: Circle())
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

struct PrimaryButton: View {
    let title: String
    var systemImage: String?
    let theme: Theme
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if let systemImage { Image(systemName: systemImage) }
                Text(title)
            }
            .font(.system(size: 17, weight: .bold))
            .foregroundStyle(Theme.ink)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(theme.color, in: RoundedRectangle(cornerRadius: 16))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Editor

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

    static let durations = [10, 15, 25, 45, 60]

    @State var draft: Draft
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @AppStorage(Theme.key, store: Theme.defaults) private var theme = Theme.violet
    @FocusState private var nameFocused: Bool
    @State private var customDuration = false
    @State private var confirmDelete = false
    @State private var failure: String?
    private var title: String { draft.title.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Cancel") { dismiss() }
                    .foregroundStyle(Theme.secondary)
                Spacer()
                Text(draft.habit == nil ? "New habit" : "Edit habit")
                    .font(.system(size: 16, weight: .semibold))
                Spacer()
                Button("Cancel") {}.hidden()
            }
            .font(.system(size: 16))
            .frame(height: 44)
            .padding(.horizontal, 20)
            .padding(.top, 10)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    section("Name") {
                        TextField("Habit name", text: $draft.title)
                            .font(.system(size: 28, weight: .bold))
                            .tracking(-0.6)
                            .focused($nameFocused)
                            .submitLabel(.done)
                            .padding(.vertical, 8)
                        Rectangle().fill(Theme.line).frame(height: 1)
                    }
                    section("Type") {
                        HStack(spacing: 10) {
                            typeOption(timed: false, title: "Instant", detail: "One tap a day")
                            typeOption(timed: true, title: "Timed", detail: "Runs a Focus session")
                        }
                    }
                    if draft.timed {
                        section("Duration") { durationPicker }
                    }
                    section("Repeat") {
                        HStack(spacing: 6) {
                            ForEach(Calendar.current.orderedWeekdays, id: \.self) { dayChip($0) }
                        }
                        HStack(spacing: 8) {
                            presetPill("Every day", 127)
                            presetPill("Weekdays", 62)
                            presetPill("Weekends", 65)
                        }
                        .padding(.top, 10)
                    }
                    if draft.habit != nil {
                        Button("Delete habit", role: .destructive) { confirmDelete = true }
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.red)
                            .padding(.top, 32)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .safeAreaInset(edge: .bottom) {
            PrimaryButton(title: draft.habit == nil ? "Save habit" : "Save changes", theme: theme, action: save)
                .disabled(title.isEmpty || draft.days == 0)
                .opacity(title.isEmpty || draft.days == 0 ? 0.4 : 1)
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
        }
        .foregroundStyle(Theme.text)
        .tint(theme.color)
        .presentationBackground(Theme.surface)
        .presentationDragIndicator(.visible)
        .onAppear {
            customDuration = !Self.durations.contains(draft.minutes)
            if draft.habit == nil { nameFocused = true }
        }
        .confirmationDialog("Delete this habit and its history?", isPresented: $confirmDelete,
                            titleVisibility: .visible) {
            Button("Delete habit", role: .destructive) {
                if let habit = draft.habit { context.delete(habit) }
                persist()
            }
        }
        .alert("Couldn’t save", isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) {
            Button("OK") { failure = nil }
        } message: { Text(failure ?? "") }
    }

    private func section<Content: View>(_ name: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(name).label()
            VStack(alignment: .leading, spacing: 0, content: content)
        }
        .padding(.top, 24)
    }

    private func typeOption(timed: Bool, title: String, detail: String) -> some View {
        let selected = draft.timed == timed
        return Button { draft.timed = timed } label: {
            VStack(alignment: .leading, spacing: 2) {
                Group {
                    if timed {
                        Image(systemName: "timer").font(.system(size: 15, weight: .bold))
                    } else {
                        Text("1").font(.system(size: 15, weight: .bold, design: .monospaced))
                    }
                }
                .foregroundStyle(selected ? Theme.ink : theme.color)
                .frame(width: 30, height: 30)
                .background(selected ? theme.color : theme.color.opacity(0.14), in: RoundedRectangle(cornerRadius: 8))
                .padding(.bottom, 10)
                Text(title).font(.system(size: 16, weight: .semibold))
                Text(detail).font(.system(size: 13)).foregroundStyle(Theme.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(selected ? theme.color.opacity(0.10) : Theme.raised, in: RoundedRectangle(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(selected ? theme.color : .clear, lineWidth: 1.5)
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var durationPicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                ForEach(Self.durations, id: \.self) { value in
                    chip("\(value)", selected: !customDuration && draft.minutes == value) {
                        customDuration = false
                        draft.minutes = value
                    }
                    .accessibilityLabel("\(value) minutes")
                }
                chip(customDuration ? "\(draft.minutes)" : "•••", selected: customDuration) {
                    customDuration = true
                }
                .accessibilityLabel("Custom duration")
            }
            if customDuration {
                Stepper("\(draft.minutes) minutes", value: $draft.minutes, in: 1...180)
                    .font(.system(size: 15))
            }
        }
    }

    private func chip(_ text: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text)
                .font(.system(size: 15, weight: selected ? .bold : .regular, design: .monospaced))
                .foregroundStyle(selected ? Theme.ink : Theme.secondary)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(selected ? theme.color : Theme.raised, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func dayChip(_ day: Int) -> some View {
        let bit = 1 << day
        let on = draft.days & bit != 0
        return Button {
            if on { draft.days &= ~bit } else { draft.days |= bit }
        } label: {
            Text(Calendar.current.veryShortWeekdaySymbols[day])
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(on ? Theme.ink : Theme.secondary)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(on ? theme.color : .clear, in: RoundedRectangle(cornerRadius: 10))
                .overlay {
                    RoundedRectangle(cornerRadius: 10).strokeBorder(on ? .clear : Theme.faint, lineWidth: 1.5)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Calendar.current.weekdaySymbols[day])
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func presetPill(_ title: String, _ days: Int) -> some View {
        let selected = draft.days == days
        return Button(title) { draft.days = days }
            .font(.system(size: 13, weight: selected ? .semibold : .regular))
            .foregroundStyle(selected ? theme.color : Theme.secondary)
            .padding(.horizontal, 14)
            .frame(height: 32)
            .background(selected ? theme.color.opacity(0.14) : Theme.raised, in: Capsule())
            .buttonStyle(.plain)
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
