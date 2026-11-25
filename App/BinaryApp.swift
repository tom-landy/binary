import ActivityKit
import AudioToolbox
import SwiftData
import SwiftUI
import UIKit
import WidgetKit

@main
struct BinaryApp: App {
    @State private var store: ModelContainer?
    @State private var syncAvailable = true
    @State private var loadError: String?

    init() {
        Theme.migrate()
        // Match navigation titles to the rounded type used everywhere else.
        let bar = UINavigationBar.appearance()
        bar.largeTitleTextAttributes = [.font: Self.rounded(size: 34, weight: .bold)]
        bar.titleTextAttributes = [.font: Self.rounded(size: 17, weight: .semibold)]
    }

    private static func rounded(size: CGFloat, weight: UIFont.Weight) -> UIFont {
        let base = UIFont.systemFont(ofSize: size, weight: weight)
        guard let descriptor = base.fontDescriptor.withDesign(.rounded) else { return base }
        return UIFont(descriptor: descriptor, size: size)
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if let store {
                    Workspace(syncAvailable: syncAvailable).modelContainer(store)
                } else if let loadError {
                    ContentUnavailableView {
                        Label("Habits unavailable", systemImage: "externaldrive.badge.exclamationmark")
                    } description: {
                        Text(loadError)
                    } actions: {
                        Button("Retry", action: openStore)
                    }
                } else {
                    ProgressView().task { openStore() }
                }
            }
            .preferredColorScheme(.dark)
        }
    }

    private func openStore() {
        do {
            store = try HabitStore.make(sync: true)
            syncAvailable = true
        } catch {
            do {
                store = try HabitStore.make(sync: false)
                syncAvailable = false
            } catch {
                loadError = error.localizedDescription
            }
        }
    }
}

struct Workspace: View {
    enum Page: Hashable {
        case habits, focus
    }

    /// A change to the timer that would throw away a session in progress.
    enum Replacement: Identifiable {
        case habit(Habit)
        case intervals(work: Int, rest: Int)
        case reset

        var id: String {
            switch self {
            case .habit(let habit): "habit-\(habit.id)"
            case .intervals(let work, let rest): "intervals-\(work)-\(rest)"
            case .reset: "reset"
            }
        }
    }

    let syncAvailable: Bool
    @Environment(\.scenePhase) private var scene
    @Environment(\.modelContext) private var context
    @Environment(\.horizontalSizeClass) private var size
    @Query(sort: \Habit.createdAt) private var habits: [Habit]
    @AppStorage(Theme.key, store: Theme.defaults) private var theme = Theme.violet
    @AppStorage("autoTransition") private var autoTransition = false
    @AppStorage("keepAwake") private var keepAwake = false
    @AppStorage("haptics") private var haptics = "Soft"
    @AppStorage("chime", store: UserDefaults(suiteName: HabitStore.groupID)) private var chime = "Soft"
    @State private var page = Page.habits
    @State private var engine = FocusEngine.shared
    @State private var settings = false
    @State private var replacement: Replacement?
    @State private var failure: String?
    @State private var failedDeadline: Date?

    var body: some View {
        Group {
            if size == .regular {
                NavigationStack {
                    HStack(spacing: 0) {
                        habitPane.frame(maxWidth: .infinity)
                        Divider()
                        focusPane.frame(maxWidth: .infinity)
                    }
                    .background(Theme.background.ignoresSafeArea())
                    .navigationTitle("Binary")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar { settingsButton }
                    .toolbarBackground(Theme.background, for: .navigationBar)
                }
            } else {
                TabView(selection: $page) {
                    Tab("Today", systemImage: "square.grid.3x3.square", value: Page.habits) {
                        NavigationStack {
                            habitPane
                                .background(Theme.background.ignoresSafeArea())
                                .navigationTitle("Today")
                                .toolbar { settingsButton }
                                .toolbarBackground(Theme.background, for: .navigationBar)
                        }
                    }
                    Tab("Focus", systemImage: "timer", value: Page.focus) {
                        NavigationStack {
                            focusPane
                                .background(Theme.background.ignoresSafeArea())
                                .navigationTitle("Focus")
                                .toolbar { settingsButton }
                                .toolbarBackground(Theme.background, for: .navigationBar)
                        }
                    }
                }
                .toolbarBackground(Theme.background, for: .tabBar)
                .toolbarBackground(.visible, for: .tabBar)
            }
        }
        .fontDesign(.rounded)
        .tint(theme.color)
        .sheet(isPresented: $settings) { SettingsView(syncAvailable: syncAvailable) }
        .confirmationDialog(replacementTitle, isPresented: Binding(
            get: { replacement != nil }, set: { if !$0 { replacement = nil } }
        ), titleVisibility: .visible, presenting: replacement) { change in
            Button(replacementAction(change), role: .destructive) { apply(change) }
        } message: { _ in
            Text("The current \(engine.session.phase.rawValue.lowercased()) interval will be lost.")
        }
        .alert("Binary", isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) {
            Button("OK") { failure = nil }
        } message: { Text(failure ?? "") }
        .task(id: scene) {
            guard scene == .active else {
                UIApplication.shared.isIdleTimerDisabled = false
                return
            }
            failedDeadline = nil
            while !Task.isCancelled {
                engine.reload()
                await reconcile()
                try? await Task.sleep(for: .milliseconds(400))
            }
        }
        .onChange(of: keepAwake, initial: true) { updateIdleTimer() }
        .onChange(of: engine.session.end) { updateIdleTimer() }
        .onChange(of: theme) { WidgetCenter.shared.reloadAllTimelines() }
    }

    private var settingsButton: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button("Settings", systemImage: "gearshape") { settings = true }
        }
    }

    private var habitPane: some View {
        HabitsView(habits: habits, theme: theme, toggle: toggleHabit, focus: activateHabit)
    }

    private var focusPane: some View {
        FocusView(engine: engine, theme: theme, play: play,
                  reset: { request(.reset) },
                  skip: {
                      engine.advance()
                      Task { await refreshSurfaces() }
                  },
                  configure: { work, rest in request(.intervals(work: work, rest: rest)) })
    }

    // MARK: Session changes

    /// A session counts as in progress once it is running or has been paused part way.
    private var sessionInProgress: Bool {
        let session = engine.session
        let full = Double((session.phase == .work ? session.work : session.rest) * 60)
        return session.end != nil || session.seconds < full
    }

    private var replacementTitle: String {
        switch replacement {
        case .reset: "Reset this session?"
        default: "Replace this session?"
        }
    }

    private func replacementAction(_ change: Replacement) -> String {
        switch change {
        case .habit(let habit): "Start \(habit.title)"
        case .intervals(let work, let rest): "Switch to \(work) / \(rest)"
        case .reset: "Reset"
        }
    }

    private func request(_ change: Replacement) {
        if sessionInProgress { replacement = change } else { apply(change) }
    }

    private func apply(_ change: Replacement) {
        switch change {
        case .habit(let habit):
            engine.configure(work: habit.minutes, rest: engine.session.rest, habit: habit)
        case .intervals(let work, let rest):
            engine.configure(work: work, rest: rest)
        case .reset:
            engine.reset()
        }
        replacement = nil
        Task {
            await engine.endActivity()
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    private func activateHabit(_ habit: Habit) {
        page = .focus
        guard engine.session.habitID != habit.id else { return }
        request(.habit(habit))
    }

    // MARK: Habits

    private func toggleHabit(_ habit: Habit) {
        let today = Date.now
        do {
            try habit.setCompleted(!habit.completed(today), date: today, in: context)
            feedback()
            WidgetCenter.shared.reloadAllTimelines()
        } catch { failure = error.localizedDescription }
    }

    private func feedback() {
        if haptics != "Off" {
            UIImpactFeedbackGenerator(style: haptics == "Firm" ? .rigid : .soft).impactOccurred()
        }
    }

    // MARK: Timer

    private func updateIdleTimer() {
        UIApplication.shared.isIdleTimerDisabled = scene == .active && keepAwake && engine.session.end != nil
    }

    private func play() {
        if let end = engine.session.end, end <= .now {
            failedDeadline = nil
            Task { await reconcile() }
            return
        }
        engine.toggle()
        feedback()
        Task { await refreshSurfaces() }
    }

    private func refreshSurfaces() async {
        if Activity<FocusActivity>.activities.isEmpty, engine.session.end != nil {
            try? startActivity(for: engine)
        } else {
            await engine.publishActivity()
        }
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func reconcile() async {
        guard let end = engine.session.end, end <= .now, end != failedDeadline else { return }
        if engine.session.phase == .work,
           let habit = habits.first(where: { $0.id == engine.session.habitID }) {
            do {
                try habit.setCompleted(true, date: end, in: context)
            } catch {
                failedDeadline = end
                failure = "Couldn’t log the completed habit. Tap the timer control to retry. \(error.localizedDescription)"
                return
            }
        }
        engine.advance(autoStart: autoTransition)
        feedback()
        if chime != "Off" { AudioServicesPlaySystemSound(chime == "Bright" ? 1025 : 1057) }
        await refreshSurfaces()
    }
}
