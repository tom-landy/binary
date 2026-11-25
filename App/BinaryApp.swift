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

enum Theme: String, CaseIterable, Identifiable {
    case violet, orange, ember, gold, lime, mint, teal, blue, pink, silver
    var id: Self { self }
    var title: String { rawValue.capitalized }
    var rgb: UInt32 {
        switch self {
        case .violet: 0x9E6BFA
        case .orange: 0xFA7A2E
        case .ember: 0xEB4742
        case .gold: 0xF5BD38
        case .lime: 0x8FD93D
        case .mint: 0x3DD69E
        case .teal: 0x2EB8D1
        case .blue: 0x3D85FA
        case .pink: 0xF25794
        case .silver: 0xC7CCD6
        }
    }
    var color: Color {
        Color(red: Double(rgb >> 16) / 255, green: Double(rgb >> 8 & 255) / 255,
              blue: Double(rgb & 255) / 255)
    }
    var icon: String? { self == .violet ? nil : "AppIcon-\(title)" }

    static let background = Color(red: 13/255, green: 14/255, blue: 18/255)
    static let panel = Color(red: 22/255, green: 24/255, blue: 31/255)
}

struct Workspace: View {
    enum Page: String, CaseIterable {
        case habits = "Habits"
        case focus = "Focus"
    }

    let syncAvailable: Bool
    @Environment(\.scenePhase) private var scene
    @Environment(\.modelContext) private var context
    @Environment(\.horizontalSizeClass) private var size
    @Query(sort: \Habit.createdAt) private var habits: [Habit]
    @AppStorage("theme") private var theme = Theme.violet
    @AppStorage("autoTransition") private var autoTransition = false
    @AppStorage("keepAwake") private var keepAwake = false
    @AppStorage("haptics") private var haptics = "Soft"
    @AppStorage("chime", store: UserDefaults(suiteName: HabitStore.groupID)) private var chime = "Soft"
    @State private var page = Page.habits
    @State private var engine = FocusEngine.shared
    @State private var settings = false
    @State private var failure: String?
    @State private var failedDeadline: Date?

    var body: some View {
        VStack(spacing: 0) {
            header
            if size == .regular {
                HStack(spacing: 0) {
                    habitPane.frame(maxWidth: .infinity)
                    Divider()
                    focusPane.frame(maxWidth: .infinity)
                }
            } else {
                Picker("Workspace", selection: $page) {
                    ForEach(Page.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 22)
                .padding(.bottom, 12)
                if page == .habits { habitPane } else { focusPane }
            }
        }
        .background(Theme.background.ignoresSafeArea())
        .fontDesign(.rounded)
        .tint(theme.color)
        .sheet(isPresented: $settings) { SettingsView(syncAvailable: syncAvailable) }
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
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("Binary").font(.largeTitle.bold())
                Text("WARHOUND").font(.system(.caption2, design: .monospaced).weight(.semibold))
                    .tracking(3).foregroundStyle(.secondary)
            }.accessibilityElement(children: .combine)
            Spacer()
            Button { settings = true } label: {
                Image(systemName: "gearshape").font(.title3)
                    .frame(width: 46, height: 46)
                    .background(Theme.panel, in: Circle())
            }
            .accessibilityLabel("Settings")
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
    }

    private var habitPane: some View {
        HabitsView(habits: habits, theme: theme, toggle: toggleHabit, focus: activateHabit)
    }

    private var focusPane: some View {
        FocusView(engine: engine, theme: theme, play: play,
                  reset: {
                      engine.reset()
                      Task { await engine.endActivity() }
                  },
                  skip: {
                      engine.advance()
                      Task { await engine.publishActivity() }
                  },
                  configure: { work, rest in
                      engine.configure(work: work, rest: rest)
                      Task { await engine.endActivity() }
                  })
    }

    private func updateIdleTimer() {
        UIApplication.shared.isIdleTimerDisabled = scene == .active && keepAwake && engine.session.end != nil
    }

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

    private func activateHabit(_ habit: Habit) {
        page = .focus
        guard engine.session.habitID != habit.id else { return }
        engine.configure(work: habit.minutes, rest: engine.session.rest, habit: habit)
        Task { await engine.endActivity() }
    }

    private func play() {
        if let end = engine.session.end, end <= .now {
            failedDeadline = nil
            Task { await reconcile() }
            return
        }
        engine.toggle()
        feedback()
        Task {
            if Activity<FocusActivity>.activities.isEmpty, engine.session.end != nil {
                try? startActivity(for: engine)
            } else {
                await engine.publishActivity()
            }
            WidgetCenter.shared.reloadAllTimelines()
        }
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
        await engine.publishActivity()
        WidgetCenter.shared.reloadAllTimelines()
    }
}
