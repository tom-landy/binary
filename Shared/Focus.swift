import ActivityKit
import Foundation
import Observation
import UserNotifications

enum FocusPhase: String, Codable, Sendable {
    case work = "Work"
    case rest = "Rest"
}

struct FocusActivity: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var phase: String
        var end: Date?
        var seconds: Int
    }

    var habit: String
}

struct FocusSession: Codable, Equatable {
    var phase = FocusPhase.work
    var work = 25
    var rest = 5
    var seconds: Double = 1500
    var end: Date?
    var habitID: UUID?
    var habitTitle: String?

    func remaining(at date: Date = .now) -> Double {
        max(0, end?.timeIntervalSince(date) ?? seconds)
    }

    mutating func advance(at date: Date, autoStart: Bool) {
        phase = phase == .work ? .rest : .work
        seconds = Double((phase == .work ? work : rest) * 60)
        end = autoStart ? date.addingTimeInterval(seconds) : nil
    }
}

@MainActor
@Observable
final class FocusEngine {
    static let shared = FocusEngine()
    private let defaults = UserDefaults(suiteName: HabitStore.groupID) ?? .standard
    private let key = "focusSession"
    private(set) var session = FocusSession()

    init() { reload() }

    func reload() {
        if let data = defaults.data(forKey: key),
           let saved = try? JSONDecoder().decode(FocusSession.self, from: data) {
            if saved != session { session = saved }
        }
    }

    func configure(work: Int, rest: Int, habit: Habit? = nil) {
        session = FocusSession(work: work, rest: rest, seconds: Double(work * 60),
                               habitID: habit?.id, habitTitle: habit?.title)
        persist()
    }

    func reset() {
        session.phase = .work
        session.seconds = Double(session.work * 60)
        session.end = nil
        persist()
    }

    func toggle() {
        if session.end != nil {
            session.seconds = session.remaining()
            session.end = nil
        } else {
            session.end = Date.now.addingTimeInterval(session.seconds)
        }
        persist()
    }

    func advance(at date: Date = .now, autoStart: Bool = false) {
        session.advance(at: date, autoStart: autoStart)
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(session) {
            defaults.set(data, forKey: key)
        }
        refreshReminder()
    }

    func refreshReminder() {
        let center = UNUserNotificationCenter.current()
        let identifier = "binary.focus.end"
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        guard defaults.bool(forKey: "focusReminders"),
              let end = session.end, end > .now else { return }

        let content = UNMutableNotificationContent()
        content.title = "\(session.phase.rawValue) complete"
        content.body = session.habitTitle ?? "Open Binary for the next interval."
        if defaults.string(forKey: "chime") != "Off" { content.sound = .default }
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, end.timeIntervalSinceNow),
                                                         repeats: false)
        center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
    }

    func publishActivity() async {
        let state = FocusActivity.ContentState(phase: session.phase.rawValue, end: session.end,
                                             seconds: Int(ceil(session.remaining())))
        let content = ActivityContent(state: state, staleDate: session.end)
        for activity in Activity<FocusActivity>.activities {
            if activity.attributes.habit == (session.habitTitle ?? "") {
                await activity.update(content)
            } else {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
    }

    func endActivity() async {
        for activity in Activity<FocusActivity>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }
}
