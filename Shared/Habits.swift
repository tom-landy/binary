import Foundation
import SwiftData

@Model
final class Habit {
    var id = UUID()
    var title = ""
    var minutes = 0
    var weekdays = 127
    var createdAt = Date.now
    @Relationship(deleteRule: .cascade, inverse: \HabitLog.habit)
    var logs: [HabitLog]?

    init(title: String, minutes: Int, weekdays: Int) {
        self.title = title
        self.minutes = minutes
        self.weekdays = weekdays
    }

    func scheduled(_ date: Date) -> Bool {
        let day = Calendar.current.component(.weekday, from: date)
        return weekdays & (1 << (day - 1)) != 0
    }

    /// A short description of a weekday bitmask (bit 0 = Sunday).
    static func scheduleText(_ weekdays: Int, calendar: Calendar = .current) -> String {
        switch weekdays {
        case 127: return "Daily"
        case 62: return "Weekdays"
        case 65: return "Weekends"
        default:
            return calendar.orderedWeekdays
                .filter { weekdays & (1 << $0) != 0 }
                .map { calendar.shortWeekdaySymbols[$0] }
                .joined(separator: ", ")
        }
    }

    func completed(_ date: Date) -> Bool {
        (logs ?? []).contains { Calendar.current.isDate($0.date, inSameDayAs: date) }
    }

    func setCompleted(_ value: Bool, date: Date, in context: ModelContext) throws {
        let matches = (logs ?? []).filter { Calendar.current.isDate($0.date, inSameDayAs: date) }
        if value {
            if matches.isEmpty {
                context.insert(HabitLog(date: date, habit: self))
            }
        } else {
            for log in matches { context.delete(log) }
        }
        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }
}

@Model
final class HabitLog {
    var date = Date.now
    var habit: Habit?

    init(date: Date, habit: Habit) {
        self.date = date
        self.habit = habit
    }
}

@MainActor
enum HabitStore {
    nonisolated static let cloudID = "iCloud.com.warhound.binary"
    nonisolated static let groupID = "group.com.warhound.binary"
    static let schema = Schema([Habit.self, HabitLog.self])

    static func make(sync: Bool) throws -> ModelContainer {
        #if os(watchOS)
        let group: ModelConfiguration.GroupContainer = .none
        #else
        let group: ModelConfiguration.GroupContainer = .identifier(groupID)
        #endif
        let configuration = ModelConfiguration(
            schema: schema,
            groupContainer: group,
            cloudKitDatabase: sync ? .private(cloudID) : .none
        )
        return try ModelContainer(for: schema, configurations: configuration)
    }
}

extension Calendar {
    /// Weekday indexes (0 = Sunday) in the order the user's locale starts the week.
    var orderedWeekdays: [Int] {
        (0..<7).map { (firstWeekday - 1 + $0) % 7 }
    }
}
