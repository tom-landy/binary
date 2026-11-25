import SwiftUI

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
    var color: Color { Theme.color(rgb) }
    var icon: String { "AppIcon-\(title)" }

    static func color(_ rgb: UInt32) -> Color {
        Color(red: Double(rgb >> 16) / 255, green: Double(rgb >> 8 & 255) / 255,
              blue: Double(rgb & 255) / 255)
    }

    /// The theme is shared with the widget extension through the app group.
    static let key = "theme"
    static var defaults: UserDefaults { UserDefaults(suiteName: HabitStore.groupID) ?? .standard }
    static var current: Theme { Theme(rawValue: defaults.string(forKey: key) ?? "") ?? .violet }

    /// Earlier builds stored the theme in standard defaults. Copy it across once.
    static func migrate() {
        let group = defaults
        guard group.string(forKey: key) == nil,
              let old = UserDefaults.standard.string(forKey: key) else { return }
        group.set(old, forKey: key)
    }

    static let background = Color(red: 13/255, green: 14/255, blue: 18/255)
    static let panel = Color(red: 22/255, green: 24/255, blue: 31/255)
}
