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
    static let title: LocalizedStringResource = "Start 25-Minute Focus Session"

    @MainActor
    func perform() async throws -> some IntentResult {
        let focus = FocusEngine.shared
        focus.reload()
        if focus.session.end == nil {
            focus.configure(work: 25, rest: 5)
            focus.toggle()
            await focus.endActivity()
            try? startActivity(for: focus)
        }
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

struct ToggleFocus: LiveActivityIntent {
    static let title: LocalizedStringResource = "Pause or Resume Binary Focus"

    @MainActor
    func perform() async throws -> some IntentResult {
        let focus = FocusEngine.shared
        focus.reload()
        if let end = focus.session.end, end <= .now { return .result() }
        focus.toggle()
        await focus.publishActivity()
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
        attributes: FocusActivity(habit: session.habitTitle ?? ""),
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
