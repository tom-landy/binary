import ActivityKit
import AppIntents
import SwiftData
import SwiftUI
import WidgetKit

struct HabitEntry: TimelineEntry, Sendable {
    var date: Date
    var habit: HabitChoice?
    var done = false
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
        do {
            let container = try HabitStore.make(sync: false)
            let descriptor = FetchDescriptor<Habit>(sortBy: [SortDescriptor(\.createdAt)])
            let habits = try container.mainContext.fetch(descriptor).filter {
                $0.minutes == 0 && $0.scheduled(now)
            }
            let selected = choice.map { choice in habits.first { $0.id == choice.id } } ?? habits.first
            guard let habit = selected else { return HabitEntry(date: now) }
            return HabitEntry(date: now, habit: HabitChoice(id: habit.id, title: habit.title),
                              done: habit.completed(now))
        } catch {
            return HabitEntry(date: now)
        }
    }
}

struct FocusProvider: TimelineProvider {
    func placeholder(in context: Context) -> HabitEntry { HabitEntry(date: .now) }

    func getSnapshot(in context: Context, completion: @escaping @Sendable (HabitEntry) -> Void) {
        completion(placeholder(in: context))
    }

    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<HabitEntry>) -> Void) {
        completion(Timeline(entries: [placeholder(in: context)], policy: .never))
    }
}

struct HabitWidgetView: View {
    let entry: HabitEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            if let habit = entry.habit {
                Button(intent: LogHabit(habit: habit)) {
                    if family == .accessoryCircular {
                        Text(entry.done ? "1" : "0").font(.title2.monospaced())
                    } else {
                        Label(habit.title, systemImage: entry.done ? "1.circle.fill" : "0.circle")
                            .font(.headline)
                            .lineLimit(2)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(habit.title), \(entry.done ? "complete" : "incomplete")")
            } else {
                Label("No instant habit today", systemImage: "circle.dotted")
                    .font(.caption)
            }
        }
        .containerBackground(.black, for: .widget)
    }
}

struct HabitWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "Habit", intent: HabitWidgetConfiguration.self,
                               provider: HabitProvider()) { HabitWidgetView(entry: $0) }
            .configurationDisplayName("Binary Habit")
            .description("Toggle a scheduled instant habit.")
            .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryRectangular])
    }
}

struct FocusWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "Focus", provider: FocusProvider()) { _ in
            Button(intent: StartFocus()) {
                Label("25 min focus", systemImage: "timer")
            }
            .buttonStyle(.plain)
            .containerBackground(.black, for: .widget)
        }
        .configurationDisplayName("Binary Focus")
        .description("Start a 25-minute Work interval.")
        .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryRectangular])
    }
}

struct FocusLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FocusActivity.self) { context in
            HStack(spacing: 14) {
                Image(systemName: context.state.phase == "Work" ? "circle.fill" : "circle")
                    .foregroundStyle(.purple)
                VStack(alignment: .leading) {
                    Text(context.state.phase).font(.headline)
                    if !context.attributes.habit.isEmpty {
                        Text(context.attributes.habit).font(.caption).lineLimit(1)
                    }
                }
                Spacer()
                clock(context.state).frame(maxWidth: 85)
                control(context.state)
            }
            .padding()
            .activityBackgroundTint(.black)
            .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(context.state.phase, systemImage: context.state.phase == "Work" ? "circle.fill" : "circle")
                }
                DynamicIslandExpandedRegion(.trailing) { control(context.state) }
                DynamicIslandExpandedRegion(.center) {
                    clock(context.state).frame(maxWidth: 100)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if !context.attributes.habit.isEmpty { Text(context.attributes.habit) }
                }
            } compactLeading: {
                Image(systemName: context.state.phase == "Work" ? "circle.fill" : "circle").foregroundStyle(.purple)
            } compactTrailing: {
                clock(context.state).frame(width: 48)
            } minimal: {
                Image(systemName: "timer").foregroundStyle(.purple)
            }
        }
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

    private func control(_ state: FocusActivity.ContentState) -> some View {
        Button(intent: ToggleFocus()) {
            Image(systemName: state.end == nil ? "play.fill" : "pause.fill")
        }.accessibilityLabel(state.end == nil ? "Resume" : "Pause")
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
