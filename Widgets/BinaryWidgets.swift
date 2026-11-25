import ActivityKit
import AppIntents
import SwiftData
import SwiftUI
import WidgetKit

/// Seconds until the next midnight, when habit widgets need fresh data.
private func nextMidnight(after date: Date) -> Date {
    let start = Calendar.current.startOfDay(for: date)
    return Calendar.current.date(byAdding: .day, value: 1, to: start) ?? date.addingTimeInterval(3600)
}

// MARK: - Single habit widget

struct HabitEntry: TimelineEntry, Sendable {
    var date: Date
    var habit: HabitChoice?
    var done = false
    var tint: UInt32 = Theme.violet.rgb
}

struct HabitWidgetConfiguration: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Choose a Habit"
    @Parameter(title: "Habit") var habit: HabitChoice?
}

struct HabitProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> HabitEntry {
        HabitEntry(date: .now, habit: HabitChoice(id: UUID(), title: "Read"))
    }

    func snapshot(for configuration: HabitWidgetConfiguration, in context: Context) async -> HabitEntry {
        if context.isPreview { return placeholder(in: context) }
        return await entry(choice: configuration.habit)
    }

    func timeline(for configuration: HabitWidgetConfiguration, in context: Context) async -> Timeline<HabitEntry> {
        let current = await entry(choice: configuration.habit)
        return Timeline(entries: [current], policy: .after(nextMidnight(after: current.date)))
    }

    @MainActor
    private func entry(choice: HabitChoice?) -> HabitEntry {
        let now = Date.now
        let tint = Theme.current.rgb
        do {
            let container = try HabitStore.make(sync: false)
            let descriptor = FetchDescriptor<Habit>(sortBy: [SortDescriptor(\.createdAt)])
            let habits = try container.mainContext.fetch(descriptor).filter {
                $0.minutes == 0 && $0.scheduled(now)
            }
            let selected = choice.map { choice in habits.first { $0.id == choice.id } } ?? habits.first
            guard let habit = selected else { return HabitEntry(date: now, tint: tint) }
            return HabitEntry(date: now, habit: HabitChoice(id: habit.id, title: habit.title),
                              done: habit.completed(now), tint: tint)
        } catch {
            return HabitEntry(date: now, tint: tint)
        }
    }
}

/// The 0/1 circle used across widgets: an empty ring with a 0, or a filled accent circle with a 1.
struct WidgetToggle: View {
    let done: Bool
    let tint: Color
    var onTint: Color = .white
    var size: CGFloat = 26
    /// Lock Screen widgets render in a single tint, so draw them with plain white.
    var monochrome = false

    var body: some View {
        ZStack {
            if done {
                Circle().fill(monochrome ? Color.white : tint)
            } else {
                Circle().strokeBorder(monochrome ? Color.white : Theme.track, lineWidth: max(2, size / 15))
            }
            Text(done ? "1" : "0")
                .font(.system(size: size * 0.42, weight: .heavy, design: .rounded))
                .foregroundStyle(done ? (monochrome ? Color.black : onTint) : (monochrome ? Color.white : Theme.tertiary))
        }
        .frame(width: size, height: size)
    }
}

struct HabitWidgetView: View {
    let entry: HabitEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        let tint = Theme.accent(entry.tint)
        let onTint = Theme.onAccent(entry.tint)
        Group {
            if let habit = entry.habit {
                Button(intent: LogHabit(habit: habit)) {
                    switch family {
                    case .accessoryCircular:
                        ZStack {
                            AccessoryWidgetBackground()
                            WidgetToggle(done: entry.done, tint: tint, size: 32, monochrome: true)
                                .widgetAccentable()
                        }
                    case .accessoryRectangular:
                        HStack(spacing: 10) {
                            WidgetToggle(done: entry.done, tint: tint, size: 24, monochrome: true)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(habit.title).font(.system(size: 14, weight: .heavy, design: .rounded)).lineLimit(2)
                                Text(entry.done ? "Done" : "Tap to log")
                                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                                    .opacity(0.7)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    default:
                        VStack(alignment: .leading, spacing: 0) {
                            WidgetToggle(done: entry.done, tint: tint, onTint: onTint, size: 50)
                            Spacer(minLength: 0)
                            Text(habit.title)
                                .font(.system(size: 15, weight: .heavy, design: .rounded))
                                .foregroundStyle(Theme.text)
                                .lineLimit(2)
                            Text(entry.done ? "Done today" : "Tap to log")
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundStyle(Theme.secondary)
                                .padding(.top, 3)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(habit.title), \(entry.done ? "done" : "not done")")
            } else {
                Text("No instant habit today")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.secondary)
            }
        }
        .containerBackground(Theme.surface, for: .widget)
    }
}

struct HabitWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "Habit", intent: HabitWidgetConfiguration.self,
                               provider: HabitProvider()) { HabitWidgetView(entry: $0) }
            .configurationDisplayName("Binary Habit")
            .description("Log one instant habit with a tap.")
            .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryRectangular])
    }
}

// MARK: - Today widget

struct TodayEntry: TimelineEntry, Sendable {
    struct Item: Sendable, Identifiable {
        var habit: HabitChoice
        var done: Bool
        var id: UUID { habit.id }
    }

    var date: Date
    var done = 0
    var total = 0
    var items: [Item] = []
    var tint: UInt32 = Theme.violet.rgb
}

struct TodayProvider: TimelineProvider {
    func placeholder(in context: Context) -> TodayEntry {
        TodayEntry(date: .now, done: 2, total: 4, items: [
            .init(habit: HabitChoice(id: UUID(), title: "Read"), done: true),
            .init(habit: HabitChoice(id: UUID(), title: "Stretch"), done: true),
            .init(habit: HabitChoice(id: UUID(), title: "No phone in bed"), done: false),
        ])
    }

    func getSnapshot(in context: Context, completion: @escaping @Sendable (TodayEntry) -> Void) {
        if context.isPreview { return completion(placeholder(in: context)) }
        Task { @MainActor in completion(Self.current()) }
    }

    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<TodayEntry>) -> Void) {
        Task { @MainActor in
            let entry = Self.current()
            completion(Timeline(entries: [entry], policy: .after(nextMidnight(after: entry.date))))
        }
    }

    @MainActor
    private static func current() -> TodayEntry {
        let now = Date.now
        let tint = Theme.current.rgb
        guard let container = try? HabitStore.make(sync: false),
              let habits = try? container.mainContext.fetch(FetchDescriptor<Habit>(sortBy: [SortDescriptor(\.createdAt)]))
        else { return TodayEntry(date: now, tint: tint) }
        let due = habits.filter { $0.scheduled(now) }
        let items = due.filter { $0.minutes == 0 }.prefix(3).map {
            TodayEntry.Item(habit: HabitChoice(id: $0.id, title: $0.title), done: $0.completed(now))
        }
        return TodayEntry(date: now, done: due.filter { $0.completed(now) }.count, total: due.count,
                          items: Array(items), tint: tint)
    }
}

struct TodayWidgetView: View {
    let entry: TodayEntry

    var body: some View {
        let tint = Theme.accent(entry.tint)
        let onTint = Theme.onAccent(entry.tint)
        let progress = entry.total == 0 ? 0 : Double(entry.done) / Double(entry.total)
        HStack(spacing: 16) {
            ZStack {
                Circle().inset(by: 4.5).stroke(Theme.track, lineWidth: 9)
                Circle().inset(by: 4.5)
                    .trim(from: 0, to: max(0.001, progress))
                    .stroke(tint, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Text("\(entry.done)/\(entry.total)")
                        .font(.system(size: 22, weight: .black, design: .rounded))
                        .foregroundStyle(Theme.text)
                    Text("today")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.secondary)
                }
            }
            .frame(width: 96, height: 96)

            VStack(alignment: .leading, spacing: 10) {
                if entry.items.isEmpty {
                    Text("No instant habits today")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.secondary)
                } else {
                    ForEach(entry.items) { item in
                        Button(intent: LogHabit(habit: item.habit)) {
                            HStack(spacing: 10) {
                                WidgetToggle(done: item.done, tint: tint, onTint: onTint, size: 26)
                                Text(item.habit.title)
                                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                                    .foregroundStyle(item.done ? Theme.secondary : Theme.text)
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(item.habit.title), \(item.done ? "done" : "not done")")
                    }
                }
            }
        }
        .containerBackground(Theme.surface, for: .widget)
    }
}

struct TodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "Today", provider: TodayProvider()) { TodayWidgetView(entry: $0) }
            .configurationDisplayName("Binary Today")
            .description("Today's progress, with your instant habits one tap away.")
            .supportedFamilies([.systemMedium])
    }
}

// MARK: - Focus widget

struct FocusEntry: TimelineEntry, Sendable {
    var date: Date
    var session: FocusSession
    var tint: UInt32
}

struct FocusProvider: TimelineProvider {
    /// Read straight from the app group so the provider needs no main-actor engine.
    private func current() -> FocusEntry {
        let defaults = UserDefaults(suiteName: HabitStore.groupID) ?? .standard
        let session = defaults.data(forKey: "focusSession")
            .flatMap { try? JSONDecoder().decode(FocusSession.self, from: $0) } ?? FocusSession()
        return FocusEntry(date: .now, session: session, tint: Theme.current.rgb)
    }

    func placeholder(in context: Context) -> FocusEntry {
        FocusEntry(date: .now, session: FocusSession(), tint: Theme.violet.rgb)
    }

    func getSnapshot(in context: Context, completion: @escaping @Sendable (FocusEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : current())
    }

    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<FocusEntry>) -> Void) {
        let entry = current()
        // Refresh when a running interval ends; otherwise wait for the app to reload us.
        let policy: TimelineReloadPolicy = entry.session.end.map { .after($0) } ?? .never
        completion(Timeline(entries: [entry], policy: policy))
    }
}

struct FocusWidgetView: View {
    let entry: FocusEntry
    @Environment(\.widgetFamily) private var family

    private var running: Bool {
        if let end = entry.session.end { return end > .now }
        return false
    }

    var body: some View {
        let tint = Theme.accent(entry.tint)
        let session = entry.session
        Group {
            switch family {
            case .accessoryCircular:
                Button(intent: ToggleFocus()) {
                    ZStack {
                        AccessoryWidgetBackground()
                        VStack(spacing: 1) {
                            Text(session.phase.rawValue.uppercased())
                                .font(.system(size: 9, weight: .heavy, design: .rounded))
                            time(session).font(.system(size: 15, weight: .black, design: .rounded))
                        }
                    }
                }
                .buttonStyle(.plain)
            case .accessoryRectangular:
                Button(intent: ToggleFocus()) {
                    VStack(alignment: .leading, spacing: 1) {
                        Label(session.phase.rawValue, systemImage: running ? "pause.fill" : "play.fill")
                            .font(.system(size: 13, weight: .heavy, design: .rounded))
                        time(session).font(.system(size: 26, weight: .black, design: .rounded))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
            default:
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text(session.phase.rawValue)
                            .font(.system(size: 12, weight: .heavy, design: .rounded))
                            .foregroundStyle(Theme.secondary)
                        Spacer()
                        Button(intent: ToggleFocus()) {
                            Image(systemName: running ? "pause.fill" : "play.fill")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(Theme.onInk)
                                .frame(width: 34, height: 34)
                                .background(Theme.ink, in: Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(running ? "Pause" : "Start")
                    }
                    Spacer(minLength: 0)
                    time(session)
                        .font(.system(size: 34, weight: .black, design: .rounded))
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                        .foregroundStyle(Theme.text)
                    progress(session, tint: tint)
                        .padding(.top, 8)
                    Text(session.habitTitle ?? "\(session.work) / \(session.rest) focus")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.secondary)
                        .lineLimit(1)
                        .padding(.top, 6)
                }
            }
        }
        .containerBackground(Theme.surface, for: .widget)
    }

    @ViewBuilder private func time(_ session: FocusSession) -> some View {
        if let end = session.end, end > .now {
            Text(timerInterval: Date.now...end, countsDown: true, showsHours: false)
                .monospacedDigit()
        } else {
            let seconds = Int(ceil(session.remaining()))
            Text(String(format: "%02d:%02d", seconds / 60, seconds % 60))
                .monospacedDigit()
        }
    }

    @ViewBuilder private func progress(_ session: FocusSession, tint: Color) -> some View {
        let total = Double(session.total)
        if let end = session.end, end > .now {
            ProgressView(timerInterval: end.addingTimeInterval(-total)...end, countsDown: true) {
                EmptyView()
            } currentValueLabel: { EmptyView() }
                .progressViewStyle(.linear)
                .tint(tint)
        } else {
            ProgressView(value: min(1, session.remaining() / max(total, 1)))
                .progressViewStyle(.linear)
                .tint(tint)
        }
    }
}

struct FocusWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "Focus", provider: FocusProvider()) { FocusWidgetView(entry: $0) }
            .configurationDisplayName("Binary Focus")
            .description("See the current interval and start or pause it.")
            .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryRectangular])
    }
}

// MARK: - Live Activity

struct FocusLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FocusActivity.self) { context in
            let tint = Theme.accent(context.attributes.tint)
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.isStale ? "\(context.state.phase) complete" : context.state.phase)
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.secondary)
                        Text(context.isStale ? "Open Binary to log it" : title(context.attributes.habit))
                            .font(.system(size: 17, weight: .heavy, design: .rounded))
                            .foregroundStyle(Theme.text)
                            .lineLimit(1)
                    }
                    Spacer()
                    if !context.isStale {
                        clock(context.state)
                            .font(.system(size: 32, weight: .black, design: .rounded))
                            .foregroundStyle(Theme.text)
                            .frame(maxWidth: 120, alignment: .trailing)
                        control(context.state)
                    }
                }
                if !context.isStale { progress(context.state, tint: tint) }
            }
            .padding(16)
            .activityBackgroundTint(Theme.surface)
            .activitySystemActionForegroundColor(Theme.text)
        } dynamicIsland: { context in
            let tint = Theme.accent(context.attributes.tint)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text(context.state.phase)
                        .font(.system(size: 14, weight: .heavy, design: .rounded))
                        .foregroundStyle(tint)
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if !context.isStale { control(context.state, dark: true) }
                }
                DynamicIslandExpandedRegion(.center) {
                    if context.isStale {
                        Text("Complete").font(.system(size: 16, weight: .heavy, design: .rounded))
                    } else {
                        clock(context.state)
                            .font(.system(size: 28, weight: .black, design: .rounded))
                            .frame(maxWidth: 120)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 8) {
                        if !context.attributes.habit.isEmpty {
                            Text(context.attributes.habit)
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                        if !context.isStale { progress(context.state, tint: tint) }
                    }
                }
            } compactLeading: {
                Image(systemName: context.state.phase == "Work" ? "circle.fill" : "circle")
                    .foregroundStyle(tint)
            } compactTrailing: {
                if context.isStale {
                    Image(systemName: "checkmark").foregroundStyle(tint)
                } else {
                    clock(context.state)
                        .font(.system(size: 14, weight: .heavy, design: .rounded))
                        .frame(width: 48)
                }
            } minimal: {
                Image(systemName: "timer").foregroundStyle(tint)
            }
        }
    }

    private func title(_ habit: String) -> String {
        habit.isEmpty ? "Focus session" : habit
    }

    private func clock(_ state: FocusActivity.ContentState) -> some View {
        Group {
            if let end = state.end {
                let start = end.addingTimeInterval(-Double(max(1, state.seconds)))
                Text(timerInterval: start...end, countsDown: true, showsHours: false)
            } else {
                Text(String(format: "%02d:%02d", state.seconds / 60, state.seconds % 60))
            }
        }
        .monospacedDigit()
    }

    /// A live bar for the whole interval, so it keeps moving between updates.
    @ViewBuilder
    private func progress(_ state: FocusActivity.ContentState, tint: Color) -> some View {
        let total = Double(max(1, state.total))
        if let end = state.end {
            ProgressView(timerInterval: end.addingTimeInterval(-total)...end, countsDown: true) {
                EmptyView()
            } currentValueLabel: { EmptyView() }
                .progressViewStyle(.linear)
                .tint(tint)
        } else {
            ProgressView(value: min(1, Double(state.seconds) / total))
                .progressViewStyle(.linear)
                .tint(tint)
        }
    }

    /// Ink button on the Lock Screen; white on the always-dark Dynamic Island.
    private func control(_ state: FocusActivity.ContentState, dark: Bool = false) -> some View {
        Button(intent: ToggleFocus()) {
            Image(systemName: state.end == nil ? "play.fill" : "pause.fill")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(dark ? Color.black : Theme.onInk)
                .frame(width: 42, height: 42)
                .background(dark ? Color.white : Theme.ink, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(state.end == nil ? "Resume" : "Pause")
    }
}

@main
struct BinaryWidgetBundle: WidgetBundle {
    var body: some Widget {
        TodayWidget()
        HabitWidget()
        FocusWidget()
        FocusLiveActivity()
    }
}
