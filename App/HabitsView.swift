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

    private var calendar: Calendar { .current }
    private var today: [Habit] { habits.filter { $0.scheduled(now) } }
    private var offToday: [Habit] { habits.filter { !$0.scheduled(now) } }
    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 12)]

    /// The last seven days, oldest first, ending today.
    private var week: [Date] {
        let start = calendar.startOfDay(for: now)
        return (0..<7).reversed().compactMap { calendar.date(byAdding: .day, value: -$0, to: start) }
    }

    private var greeting: String {
        switch calendar.component(.hour, from: now) {
        case 5..<12: "Good morning"
        case 12..<17: "Good afternoon"
        default: "Good evening"
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                if habits.isEmpty {
                    empty
                } else {
                    summaryChips
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(today) { tile($0) }
                        newHabitTile
                    }
                    if !offToday.isEmpty {
                        Text("Not today").label()
                            .padding(.top, 26)
                            .padding(.bottom, 10)
                            .padding(.leading, 2)
                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(offToday) { tile($0).opacity(0.5) }
                        }
                    }
                    Text("Hold a habit to edit it.")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.tertiary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 22)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 32)
            .frame(maxWidth: 680)
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

    // MARK: Header

    private var header: some View {
        let due = today
        let done = due.filter { $0.completed(now) }.count
        return VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(greeting)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Theme.secondary)
                Spacer()
                HStack(spacing: 8) {
                    CircleIconButton(systemImage: "plus", label: "New habit") { editor = HabitEditor.Draft() }
                    CircleIconButton(systemImage: "gearshape", label: "Settings", action: openSettings)
                }
            }
            .frame(height: 44)
            HStack {
                Text(now, format: .dateTime.weekday(.wide))
                    .font(.system(size: 34, weight: .black))
                    .tracking(-0.5)
                    .foregroundStyle(Theme.text)
                Spacer()
                if !due.isEmpty {
                    ProgressRing(value: Double(done) / Double(due.count), color: theme.color, lineWidth: 6) {
                        Text("\(done)/\(due.count)")
                            .font(.system(size: 15, weight: .black))
                            .foregroundStyle(Theme.text)
                    }
                    .frame(width: 60, height: 60)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(done) of \(due.count) done today")
                }
            }
        }
    }

    private var summaryChips: some View {
        let due = today
        let left = due.filter { !$0.completed(now) }.count
        let streak = Habit.perfectStreak(habits, today: now)
        return HStack(spacing: 8) {
            if streak > 0 {
                InfoChip(systemImage: "flame.fill", text: "\(streak)-day streak", emphasis: true)
            }
            if !due.isEmpty {
                InfoChip(systemImage: left == 0 ? "checkmark" : nil,
                         text: left == 0 ? "All done today" : "\(left) left today", emphasis: left == 0)
            }
        }
        .padding(.top, 14)
        .padding(.bottom, 16)
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                ToggleCircle(done: true, theme: theme, size: 38)
                ToggleCircle(done: false, theme: theme, size: 38)
                ToggleCircle(done: true, theme: theme, size: 38)
            }
            .padding(.bottom, 6)
            Text("Every habit is a 1 or a 0.")
                .font(.system(size: 24, weight: .black))
                .foregroundStyle(Theme.text)
            Text("Instant habits take one tap. Timed habits run a focus session and log themselves when it ends.")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.secondary)
            PrimaryButton(title: "Add your first habit", systemImage: "plus", action: { editor = HabitEditor.Draft() })
                .padding(.top, 12)
        }
        .padding(.top, 36)
    }

    // MARK: Tiles

    private func tile(_ habit: Habit) -> some View {
        let logged = habit.loggedDays()
        let timed = habit.minutes > 0
        let scheduled = habit.scheduled(now)
        let done = logged.contains(calendar.startOfDay(for: now))
        let meta = scheduled
            ? (timed ? "\(habit.minutes) min" : "Instant")
            : Habit.scheduleText(habit.weekdays)
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                Button { toggle(habit) } label: {
                    ToggleCircle(done: done, theme: theme, size: 38)
                        .frame(width: 44, height: 44, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!scheduled)
                .accessibilityLabel("\(habit.title), \(done ? "done" : "not done")")
                .accessibilityHint("Toggles today")
                Spacer()
                if timed && scheduled && !done {
                    Button { focus(habit) } label: {
                        Image(systemName: "play.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Theme.text)
                            .frame(width: 32, height: 32)
                            .background(Theme.background, in: Circle())
                            .frame(width: 44, height: 44, alignment: .trailing)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Start \(habit.title)")
                }
            }
            Spacer(minLength: 10)
            Text(habit.title)
                .font(.system(size: 17, weight: .heavy))
                .foregroundStyle(Theme.text)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            Text(meta)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.secondary)
                .padding(.top, 2)
            WeekDots(habit: habit, week: week, logged: logged)
                .padding(.top, 10)
        }
        .padding(15)
        .frame(maxWidth: .infinity, minHeight: 150, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 22))
        .paperShadow()
        .contentShape(RoundedRectangle(cornerRadius: 22))
        .onTapGesture {
            guard scheduled else { return }
            if timed { focus(habit) } else { toggle(habit) }
        }
        .contextMenu {
            if scheduled {
                Button(done ? "Mark as not done" : "Mark as done",
                       systemImage: done ? "circle" : "checkmark.circle") { toggle(habit) }
            }
            if timed && scheduled {
                Button("Start focus", systemImage: "play") { focus(habit) }
            }
            Button("Edit habit", systemImage: "pencil") { editor = HabitEditor.Draft(habit) }
        }
    }

    private var newHabitTile: some View {
        Button { editor = HabitEditor.Draft() } label: {
            VStack(spacing: 4) {
                Image(systemName: "plus").font(.system(size: 22, weight: .bold))
                Text("New habit").font(.system(size: 15, weight: .heavy))
            }
            .foregroundStyle(Theme.secondary)
            .frame(maxWidth: .infinity, minHeight: 150)
            .overlay {
                RoundedRectangle(cornerRadius: 22)
                    .strokeBorder(Theme.track, style: StrokeStyle(lineWidth: 2, dash: [6, 5]))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Shared pieces

/// The 0/1 toggle: an empty ring with a 0, or a filled accent circle with a 1.
struct ToggleCircle: View {
    let done: Bool
    let theme: Theme
    var size: CGFloat = 38

    var body: some View {
        ZStack {
            if done {
                Circle().fill(theme.color)
            } else {
                Circle().strokeBorder(Theme.track, lineWidth: max(2, size / 15))
            }
            Text(done ? "1" : "0")
                .font(.system(size: size * 0.42, weight: .heavy))
                .foregroundStyle(done ? theme.onColor : Theme.tertiary)
        }
        .frame(width: size, height: size)
        .animation(.spring(duration: 0.3), value: done)
    }
}

/// Seven small dots for the last week. Neutral marks for done days; an outline when nothing was due.
struct WeekDots: View {
    let habit: Habit
    let week: [Date]
    let logged: Set<Date>

    var body: some View {
        HStack(spacing: 4) {
            ForEach(week, id: \.self) { day in
                Group {
                    if logged.contains(day) {
                        Circle().fill(Theme.mark)
                    } else if habit.due(on: day) {
                        Circle().fill(Theme.track)
                    } else {
                        Circle().strokeBorder(Theme.track, lineWidth: 1.5)
                    }
                }
                .frame(width: 8, height: 8)
            }
        }
        .accessibilityHidden(true)
    }
}

struct ProgressRing<Content: View>: View {
    let value: Double
    let color: Color
    var lineWidth: CGFloat = 6
    @ViewBuilder var label: Content

    var body: some View {
        ZStack {
            Circle().inset(by: lineWidth / 2).stroke(Theme.track, lineWidth: lineWidth)
            Circle().inset(by: lineWidth / 2)
                .trim(from: 0, to: max(0.001, min(1, value)))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.spring(duration: 0.5), value: value)
            label
        }
    }
}

struct InfoChip: View {
    var systemImage: String?
    let text: String
    var emphasis = false

    var body: some View {
        HStack(spacing: 6) {
            if let systemImage { Image(systemName: systemImage).font(.system(size: 11, weight: .bold)) }
            Text(text)
        }
        .font(.system(size: 13, weight: .bold))
        .foregroundStyle(emphasis ? Theme.text : Theme.secondary)
        .padding(.horizontal, 13)
        .frame(height: 32)
        .background(Theme.surface, in: Capsule())
        .paperShadow()
    }
}

struct CircleIconButton: View {
    let systemImage: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Theme.text)
                .frame(width: 36, height: 36)
                .background(Theme.surface, in: Circle())
                .paperShadow()
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// Dark ink capsule used for the main action on a screen.
struct PrimaryButton: View {
    let title: String
    var systemImage: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if let systemImage { Image(systemName: systemImage) }
                Text(title)
            }
            .font(.system(size: 17, weight: .heavy))
            .foregroundStyle(Theme.onInk)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(Theme.ink, in: Capsule())
            .contentShape(Capsule())
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
    private var canSave: Bool { !title.isEmpty && draft.days != 0 }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Cancel") { dismiss() }
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Theme.secondary)
                Spacer()
                Text(draft.habit == nil ? "New habit" : "Edit habit")
                    .font(.system(size: 16, weight: .heavy))
                Spacer()
                Button("Cancel") {}.font(.system(size: 16, weight: .bold)).hidden()
            }
            .frame(height: 44)
            .padding(.horizontal, 20)
            .padding(.top, 12)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    TextField("Habit name", text: $draft.title)
                        .font(.system(size: 24, weight: .heavy))
                        .focused($nameFocused)
                        .submitLabel(.done)
                        .padding(.horizontal, 18)
                        .frame(height: 62)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18))
                        .paperShadow()
                        .padding(.top, 14)

                    section("Type") {
                        HStack(spacing: 10) {
                            typeOption(timed: false, title: "Instant", detail: "One tap a day")
                            typeOption(timed: true, title: "Timed", detail: "Runs a focus session")
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
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.red)
                            .padding(.top, 30)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .safeAreaInset(edge: .bottom) {
            PrimaryButton(title: draft.habit == nil ? "Save habit" : "Save changes", action: save)
                .disabled(!canSave)
                .opacity(canSave ? 1 : 0.35)
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
        }
        .foregroundStyle(Theme.text)
        .fontDesign(.rounded)
        .tint(theme.color)
        .presentationBackground(Theme.background)
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
            Text(name).label().padding(.leading, 2)
            VStack(alignment: .leading, spacing: 0, content: content)
        }
        .padding(.top, 22)
    }

    private func typeOption(timed: Bool, title: String, detail: String) -> some View {
        let selected = draft.timed == timed
        return Button { draft.timed = timed } label: {
            VStack(alignment: .leading, spacing: 2) {
                Group {
                    if timed {
                        Image(systemName: "timer").font(.system(size: 15, weight: .bold))
                    } else {
                        Text("1").font(.system(size: 15, weight: .black))
                    }
                }
                .foregroundStyle(selected ? theme.color : Theme.secondary)
                .frame(width: 32, height: 32)
                .background(selected ? theme.soft : Theme.track, in: Circle())
                .padding(.bottom, 10)
                Text(title).font(.system(size: 16, weight: .heavy))
                Text(detail).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18))
            .overlay {
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(selected ? theme.color : .clear, lineWidth: 2)
            }
            .paperShadow()
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var durationPicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                ForEach(Self.durations, id: \.self) { value in
                    pill("\(value)", selected: !customDuration && draft.minutes == value) {
                        customDuration = false
                        draft.minutes = value
                    }
                    .accessibilityLabel("\(value) minutes")
                }
                pill(customDuration ? "\(draft.minutes)" : "•••", selected: customDuration) {
                    customDuration = true
                }
                .accessibilityLabel("Custom duration")
            }
            if customDuration {
                Stepper("\(draft.minutes) minutes", value: $draft.minutes, in: 1...180)
                    .font(.system(size: 15, weight: .bold))
            }
        }
    }

    /// Round chip: ink when selected, white otherwise.
    private func pill(_ text: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(selected ? Theme.onInk : Theme.secondary)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(selected ? Theme.ink : Theme.surface, in: Capsule())
                .paperShadow()
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func dayChip(_ day: Int) -> some View {
        let bit = 1 << day
        let on = draft.days & bit != 0
        return pill(Calendar.current.veryShortWeekdaySymbols[day], selected: on) {
            if on { draft.days &= ~bit } else { draft.days |= bit }
        }
        .accessibilityLabel(Calendar.current.weekdaySymbols[day])
    }

    private func presetPill(_ title: String, _ days: Int) -> some View {
        let selected = draft.days == days
        return Button(title) { draft.days = days }
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(selected ? theme.color : Theme.secondary)
            .padding(.horizontal, 14)
            .frame(height: 32)
            .background(selected ? theme.soft : Theme.track, in: Capsule())
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
