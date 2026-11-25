import ActivityKit
import AppIntents
import Foundation
import SwiftData
import WidgetKit

struct HabitChoice: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Habit"
    static let defaultQuery = HabitChoices()
    var id: UUID
    var title: String
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(title)") }
}

struct HabitChoices: EntityQuery {
    @MainActor
    func entities(for identifiers: [UUID]) async throws -> [HabitChoice] {
        try await suggestedEntities().filter { identifiers.contains($0.id) }
    }

    @MainActor
    func suggestedEntities() async throws -> [HabitChoice] {
        let container = try HabitStore.make(sync: false)
        let context = container.mainContext
        return try context.fetch(FetchDescriptor<Habit>(sortBy: [SortDescriptor(\.title)]))
            .filter { $0.minutes == 0 }
            .map { HabitChoice(id: $0.id, title: $0.title) }
    }
}

struct LogHabit: AppIntent {
    static let title: LocalizedStringResource = "Log Habit in Binary"

    @Parameter(title: "Habit") var habit: HabitChoice

    @Parameter(title: "Toggle Existing Completion", default: false) var toggle: Bool

    init() {}
    init(habit: HabitChoice) {
        self.habit = habit
        self.toggle = true
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        let container = try HabitStore.make(sync: false)
        let context = container.mainContext
        let id = habit.id
        let descriptor = FetchDescriptor<Habit>(predicate: #Predicate { $0.id == id })
        let today = Date.now
        if let record = try context.fetch(descriptor).first, record.minutes == 0, record.scheduled(today) {
            try record.setCompleted(!toggle || !record.completed(today), date: today, in: context)
        }
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

struct StartFocus: LiveActivityIntent {
    static let title: LocalizedStringResource = "Start Binary Focus"
    static let description = IntentDescription("Resumes a paused session, or starts the current Work interval.")

    @MainActor
    func perform() async throws -> some IntentResult {
        let focus = FocusEngine.shared
        focus.reload()
        // Already running: nothing to do. Otherwise resume, or finish an expired interval and start the next.
        if let end = focus.session.end, end > .now { return .result() }
        _ = try await ToggleFocus().perform()
        return .result()
    }
}

struct ToggleFocus: LiveActivityIntent {
    static let title: LocalizedStringResource = "Pause or Resume Binary Focus"

    @MainActor
    func perform() async throws -> some IntentResult {
        let focus = FocusEngine.shared
        focus.reload()
        if let end = focus.session.end, end <= .now {
            // The interval finished while Binary wasn't running. Log it, then start the next one.
            if focus.session.phase == .work, let id = focus.session.habitID {
                let container = try HabitStore.make(sync: false)
                let context = container.mainContext
                let descriptor = FetchDescriptor<Habit>(predicate: #Predicate { $0.id == id })
                try context.fetch(descriptor).first?.setCompleted(true, date: end, in: context)
            }
            focus.advance(autoStart: true)
            await focus.publishActivity()
            WidgetCenter.shared.reloadAllTimelines()
            return .result()
        }
        focus.toggle()
        if focus.session.end != nil, Activity<FocusActivity>.activities.isEmpty {
            try? startActivity(for: focus)
        } else {
            await focus.publishActivity()
        }
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

@MainActor
func startActivity(for focus: FocusEngine) throws {
    guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
    let session = focus.session
    let state = FocusActivity.ContentState(phase: session.phase.rawValue, end: session.end,
                                         seconds: Int(ceil(session.remaining())))
    _ = try Activity<FocusActivity>.request(
        attributes: FocusActivity(habit: session.habitTitle ?? "", tint: Theme.current.rgb),
        content: ActivityContent(state: state, staleDate: session.end),
        pushType: nil
    )
}

struct BinaryShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: StartFocus(), phrases: ["Start focus in \(.applicationName)"],
                    shortTitle: "Start Focus", systemImageName: "timer")
        AppShortcut(intent: LogHabit(), phrases: ["Log a habit in \(.applicationName)"],
                    shortTitle: "Log Habit", systemImageName: "checkmark.circle")
    }
}

struct BinaryFocusFilter: SetFocusFilterIntent {
    static let title: LocalizedStringResource = "Binary Focus Preset"

    @Parameter(title: "Work Minutes", default: 25, inclusiveRange: (1, 180))
    var minutes: Int

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(minutes)-minute Work block")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        let focus = FocusEngine.shared
        focus.reload()
        if focus.session.end == nil && focus.session.habitID == nil {
            focus.configure(work: minutes, rest: focus.session.rest)
        }
        return .result()
    }
}
