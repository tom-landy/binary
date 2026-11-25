import ActivityKit
import AppIntents
import SwiftData
import SwiftUI
import WidgetKit

// MARK: Habit widget

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
        let next = Calendar.current.startOfDay(for: current.date)
        let boundary = Calendar.current.date(byAdding: .day, value: 1, to: next)
            ?? current.date.addingTimeInterval(3600)
        return Timeline(entries: [current], policy: .after(boundary))
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
                        Text(entry.done ? "1" : "0")
                            .font(.system(.title, design: .monospaced).bold())
                            .widgetAccentable()
                    case .accessoryRectangular:
                        Label(habit.title, systemImage: entry.done ? "1.square.fill" : "0.square")
                            .font(.headline)
                            .lineLimit(2)
                    default:
                        VStack(alignment: .leading, spacing: 0) {
                            Text(entry.done ? "1" : "0")
                                .font(.system(size: 30, weight: .bold, design: .monospaced))
                                .foregroundStyle(entry.done ? Color.black : tint)
                                .frame(width: 58, height: 58)
                                .background(tint.opacity(entry.done ? 1 : 0.14),
                                            in: RoundedRectangle(cornerRadius: 16))
                            Spacer(minLength: 0)
                            Text(habit.title)
                                .font(.system(.headline, design: .rounded))
                                .lineLimit(2)
                            Text(entry.done ? "Done today" : "Tap to log")
                                .font(.system(.caption, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(habit.title), \(entry.done ? "complete" : "incomplete")")
            } else {
                Label("No instant habit today", systemImage: "square.dashed")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .containerBackground(Theme.background, for: .widget)
    }
}

struct HabitWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "Habit", intent: HabitWidgetConfiguration.self,
                               provider: HabitProvider()) { HabitWidgetView(entry: $0) }
            .configurationDisplayName("Binary Habit")
            .description("Log a scheduled instant habit with one tap.")
            .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryRectangular])
    }
}

// MARK: Focus widget

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
        Group {
            switch family {
            case .accessoryCircular:
                Button(intent: ToggleFocus()) {
                    VStack(spacing: 0) {
                        Image(systemName: running ? "pause.fill" : "play.fill").font(.caption)
                        time(session).font(.system(.caption, design: .monospaced).bold())
                    }
                }
                .buttonStyle(.plain)
            case .accessoryRectangular:
                Button(intent: ToggleFocus()) {
                    VStack(alignment: .leading) {
                        Label(session.phase.rawValue, systemImage: running ? "pause.fill" : "play.fill")
                            .font(.headline)
                        time(session).font(.system(.title3, design: .monospaced))
                    }
                }
                .buttonStyle(.plain)
            default:
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(session.phase.rawValue.uppercased())
                            .font(.system(.caption2, design: .monospaced).weight(.semibold))
                            .tracking(2)
                            .foregroundStyle(tint)
                        Spacer()
                        Button(intent: ToggleFocus()) {
                            Image(systemName: running ? "pause.fill" : "play.fill")
                                .font(.headline)
                                .foregroundStyle(.black)
                                .frame(width: 40, height: 40)
                                .background(tint, in: Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(running ? "Pause" : "Start")
                    }
                    Spacer(minLength: 0)
                    time(session)
                        .font(.system(size: 34, weight: .medium, design: .monospaced))
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                    Text(session.habitTitle ?? "\(session.work)/\(session.rest) focus")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .containerBackground(Theme.background, for: .widget)
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
}

struct FocusWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "Focus", provider: FocusProvider()) { FocusWidgetView(entry: $0) }
            .configurationDisplayName("Binary Focus")
            .description("See the current interval and start or pause it.")
            .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryRectangular])
    }
}

// MARK: Live Activity

struct FocusLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FocusActivity.self) { context in
            let tint = Theme.color(context.attributes.tint)
            HStack(spacing: 14) {
                Text(context.state.phase == "Work" ? "1" : "0")
                    .font(.system(.title2, design: .monospaced).bold())
                    .foregroundStyle(.black)
                    .frame(width: 44, height: 44)
                    .background(tint, in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 2) {
                    Text(context.isStale ? "\(context.state.phase) complete" : context.state.phase)
                        .font(.system(.headline, design: .rounded))
                    Text(context.isStale ? "Open Binary to log it" : subtitle(context.attributes.habit))
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                if !context.isStale {
                    clock(context.state)
                        .font(.system(.title, design: .monospaced).weight(.medium))
                        .frame(maxWidth: 100, alignment: .trailing)
                    control(context.state, tint: tint)
                }
            }
            .padding()
            .activityBackgroundTint(Theme.background)
            .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            let tint = Theme.color(context.attributes.tint)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(context.state.phase, systemImage: context.state.phase == "Work" ? "circle.fill" : "circle")
                        .foregroundStyle(tint)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if !context.isStale { control(context.state, tint: tint) }
                }
                DynamicIslandExpandedRegion(.center) {
                    if context.isStale {
                        Text("\(context.state.phase) complete")
                    } else {
                        clock(context.state)
                            .font(.system(.title2, design: .monospaced))
                            .frame(maxWidth: 110)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if !context.attributes.habit.isEmpty { Text(context.attributes.habit) }
                }
            } compactLeading: {
                Image(systemName: context.state.phase == "Work" ? "circle.fill" : "circle").foregroundStyle(tint)
            } compactTrailing: {
                if context.isStale {
                    Image(systemName: "checkmark").foregroundStyle(tint)
                } else {
                    clock(context.state).frame(width: 48).foregroundStyle(tint)
                }
            } minimal: {
                Image(systemName: "timer").foregroundStyle(tint)
            }
        }
    }

    private func subtitle(_ habit: String) -> String {
        habit.isEmpty ? "Binary Focus" : habit
    }

    private func clock(_ state: FocusActivity.ContentState) -> some View {
        Group {
            if let end = state.end {
                let start = end.addingTimeInterval(-Double(max(1, state.seconds)))
                Text(timerInterval: start...end, countsDown: true, showsHours: false)
            } else {
                Text(String(format: "%02d:%02d", state.seconds / 60, state.seconds % 60))
            }
        }.monospacedDigit()
    }

    private func control(_ state: FocusActivity.ContentState, tint: Color) -> some View {
        Button(intent: ToggleFocus()) {
            Image(systemName: state.end == nil ? "play.fill" : "pause.fill")
                .foregroundStyle(.black)
                .frame(width: 40, height: 40)
                .background(tint, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(state.end == nil ? "Resume" : "Pause")
    }
}

@main
struct BinaryWidgetBundle: WidgetBundle {
    var body: some Widget {
        HabitWidget()
        FocusWidget()
        FocusLiveActivity()
    }
}
