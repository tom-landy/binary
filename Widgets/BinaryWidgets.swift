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

/// The 0/1 square used across widgets.
struct WidgetBit: View {
    let done: Bool
    let tint: Color
    var size: CGFloat = 24
    var glyph = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.27)
        ZStack {
            if done {
                shape.fill(tint)
            } else {
                shape.strokeBorder(tint, lineWidth: max(1.5, size / 26))
            }
            if glyph {
                Text(done ? "1" : "0")
                    .font(.system(size: size * 0.46, weight: .semibold, design: .monospaced))
                    .foregroundStyle(done ? Theme.ink : tint)
            }
        }
        .frame(width: size, height: size)
    }
}

struct HabitWidgetView: View {
    let entry: HabitEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        let tint = Theme.color(entry.tint)
        Group {
            if let habit = entry.habit {
                Button(intent: LogHabit(habit: habit)) {
                    switch family {
                    case .accessoryCircular:
                        ZStack {
                            AccessoryWidgetBackground()
                            WidgetBit(done: entry.done, tint: .white, size: 30, glyph: true)
                                .widgetAccentable()
                        }
                    case .accessoryRectangular:
                        HStack(spacing: 10) {
                            WidgetBit(done: entry.done, tint: .white, size: 22)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(habit.title).font(.system(size: 14, weight: .semibold)).lineLimit(2)
                                Text(entry.done ? "1 · Done" : "0 · Tap to log")
                                    .font(.system(size: 11, design: .monospaced))
                                    .textCase(.uppercase)
                                    .opacity(0.7)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    default:
                        VStack(alignment: .leading, spacing: 0) {
                            WidgetBit(done: entry.done, tint: tint, size: 52, glyph: true)
                            Spacer(minLength: 0)
                            Text(habit.title)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Theme.text)
                                .lineLimit(2)
                            Text(entry.done ? "Done today" : "Tap to log")
                                .font(.system(size: 12))
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
                    .font(.system(size: 13))
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
        let tint = Theme.color(entry.tint)
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Today").label()
                Spacer(minLength: 0)
                (Text("\(entry.done)").foregroundStyle(Theme.text)
                 + Text("/\(entry.total)").foregroundStyle(Theme.tertiary))
                    .font(.system(size: 40, weight: .light, design: .monospaced))
                    .tracking(-1.5)
                HStack(spacing: 3) {
                    ForEach(0..<max(entry.total, 1), id: \.self) { index in
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(index < entry.done ? tint : Theme.raised)
                            .frame(height: 5)
                    }
                }
                .padding(.top, 8)
            }
            .frame(width: 110)

            VStack(alignment: .leading, spacing: 10) {
                if entry.items.isEmpty {
                    Text("No instant habits today")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.secondary)
                } else {
                    ForEach(entry.items) { item in
                        Button(intent: LogHabit(habit: item.habit)) {
                            HStack(spacing: 10) {
                                WidgetBit(done: item.done, tint: tint, size: 24)
                                Text(item.habit.title)
                                    .font(.system(size: 14, weight: .semibold))
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
            .frame(maxHeight: .infinity, alignment: .center)
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
        let tint = Theme.color(entry.tint)
        let session = entry.session
        let phase = session.phase == .work ? "1 Work" : "0 Rest"
        Group {
            switch family {
            case .accessoryCircular:
                Button(intent: ToggleFocus()) {
                    ZStack {
                        AccessoryWidgetBackground()
                        VStack(spacing: 1) {
                            Text(session.phase.rawValue)
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .textCase(.uppercase)
                            time(session).font(.system(size: 14, weight: .semibold, design: .monospaced))
                        }
                    }
                }
                .buttonStyle(.plain)
            case .accessoryRectangular:
                Button(intent: ToggleFocus()) {
                    VStack(alignment: .leading, spacing: 2) {
                        Label(phase, systemImage: running ? "pause.fill" : "play.fill")
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .textCase(.uppercase)
                        time(session).font(.system(size: 26, weight: .light, design: .monospaced))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
            default:
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text(phase).label(tint)
                        Spacer()
                        Button(intent: ToggleFocus()) {
                            Image(systemName: running ? "pause.fill" : "play.fill")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(Theme.ink)
                                .frame(width: 34, height: 34)
                                .background(tint, in: Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(running ? "Pause" : "Start")
                    }
                    Spacer(minLength: 0)
                    time(session)
                        .font(.system(size: 34, weight: .light, design: .monospaced))
                        .tracking(-1.5)
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                        .foregroundStyle(Theme.text)
                    progress(session, tint: tint)
                        .padding(.top, 8)
                    Text(session.habitTitle ?? "\(session.work)/\(session.rest) focus")
                        .font(.system(size: 12))
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
        }
    }

    @ViewBuilder private func progress(_ session: FocusSession, tint: Color) -> some View {
        let total = Double((session.phase == .work ? session.work : session.rest) * 60)
        if let end = session.end, end > .now {
            let start = end.addingTimeInterval(-total)
            ProgressView(timerInterval: start...end, countsDown: true) { EmptyView() } currentValueLabel: { EmptyView() }
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
            let tint = Theme.color(context.attributes.tint)
            let phase = context.state.phase == "Work" ? "1 Work" : "0 Rest"
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(context.isStale ? "\(phase) · complete" : phase).label(tint)
                        Text(context.isStale ? "Open Binary to log it" : title(context.attributes.habit))
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Theme.text)
                            .lineLimit(1)
                    }
                    Spacer()
                    if !context.isStale {
                        clock(context.state)
                            .font(.system(size: 38, weight: .light, design: .monospaced))
                            .tracking(-1.5)
                            .foregroundStyle(Theme.text)
                            .frame(maxWidth: 130, alignment: .trailing)
                        control(context.state, tint: tint)
                    }
                }
                if !context.isStale { progress(context.state, tint: tint) }
            }
            .padding(16)
            .activityBackgroundTint(Theme.background)
            .activitySystemActionForegroundColor(Theme.text)
        } dynamicIsland: { context in
            let tint = Theme.color(context.attributes.tint)
            let phase = context.state.phase == "Work" ? "1 Work" : "0 Rest"
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text(phase).label(tint).padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if !context.isStale { control(context.state, tint: tint) }
                }
                DynamicIslandExpandedRegion(.center) {
                    if context.isStale {
                        Text("Complete").font(.system(size: 16, weight: .semibold))
                    } else {
                        clock(context.state)
                            .font(.system(size: 28, weight: .light, design: .monospaced))
                            .frame(maxWidth: 120)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 8) {
                        if !context.attributes.habit.isEmpty {
                            Text(context.attributes.habit).font(.system(size: 14)).foregroundStyle(Theme.secondary)
                        }
                        if !context.isStale { progress(context.state, tint: tint) }
                    }
                }
            } compactLeading: {
                Text(context.state.phase == "Work" ? "1" : "0")
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundStyle(tint)
            } compactTrailing: {
                if context.isStale {
                    Image(systemName: "checkmark").foregroundStyle(tint)
                } else {
                    clock(context.state)
                        .font(.system(size: 14, weight: .medium, design: .monospaced))
                        .frame(width: 48)
                        .foregroundStyle(tint)
                }
            } minimal: {
                Text(context.state.phase == "Work" ? "1" : "0")
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundStyle(tint)
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
            let start = end.addingTimeInterval(-total)
            ProgressView(timerInterval: start...end, countsDown: true) { EmptyView() } currentValueLabel: { EmptyView() }
                .progressViewStyle(.linear)
                .tint(tint)
        } else {
            ProgressView(value: min(1, Double(state.seconds) / total))
                .progressViewStyle(.linear)
                .tint(tint)
        }
    }

    private func control(_ state: FocusActivity.ContentState, tint: Color) -> some View {
        Button(intent: ToggleFocus()) {
            Image(systemName: state.end == nil ? "play.fill" : "pause.fill")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Theme.ink)
                .frame(width: 42, height: 42)
                .background(tint, in: Circle())
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
