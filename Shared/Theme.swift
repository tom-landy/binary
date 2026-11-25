import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

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

    /// The accent, slightly deeper on light backgrounds and slightly lifted on dark ones.
    var color: Color { Theme.accent(rgb) }
    /// Text or glyphs drawn on top of the accent.
    var onColor: Color { Theme.onAccent(rgb) }
    /// A pale wash of the accent for selected backgrounds.
    var soft: Color { color.opacity(0.12) }

    /// Violet is the primary icon; every other theme has an alternate.
    var icon: String? { self == .violet ? nil : "AppIcon-\(title)" }

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

    // MARK: Design tokens ("Paper"). Warm neutrals; the accent is used sparingly.

    static let background = dynamic(light: 0xF6F3EE, dark: 0x121014)
    static let surface = dynamic(light: 0xFFFFFF, dark: 0x1D1B21)
    static let text = dynamic(light: 0x1B1530, dark: 0xF3F0F7)
    static let secondary = dynamic(light: 0x7A7386, dark: 0x9C96A6)
    static let tertiary = dynamic(light: 0xB1AABD, dark: 0x5E5866)
    static let line = dynamic(light: 0xE9E4DC, dark: 0x26232B)
    /// Empty rings, unfilled dots and segmented-control wells.
    static let track = dynamic(light: 0xEEEAF2, dark: 0x2A2730)
    /// Completed days in the history dots. Neutral on purpose so the accent stays rare.
    static let mark = dynamic(light: 0x3A344A, dark: 0xCFC9D8)
    /// Primary buttons and selected chips.
    static let ink = dynamic(light: 0x1B1530, dark: 0xF3F0F7)
    static let onInk = dynamic(light: 0xFFFFFF, dark: 0x121014)
    static let shadow = dynamicColor(light: Color.black.opacity(0.06), dark: .clear)

    static func color(_ rgb: UInt32) -> Color {
        Color(red: Double(rgb >> 16) / 255, green: Double(rgb >> 8 & 255) / 255,
              blue: Double(rgb & 255) / 255)
    }

    private static func mix(_ rgb: UInt32, with target: Double, amount: Double) -> Color {
        func channel(_ value: UInt32) -> Double {
            let c = Double(value & 255) / 255
            return c + (target - c) * amount
        }
        return Color(red: channel(rgb >> 16), green: channel(rgb >> 8), blue: channel(rgb))
    }

    private static func luminance(_ rgb: UInt32) -> Double {
        0.2126 * Double(rgb >> 16) / 255 + 0.7152 * Double(rgb >> 8 & 255) / 255 + 0.0722 * Double(rgb & 255) / 255
    }

    static func accent(_ rgb: UInt32) -> Color {
        dynamicColor(light: mix(rgb, with: 0, amount: 0.1), dark: mix(rgb, with: 1, amount: 0.08))
    }

    static func onAccent(_ rgb: UInt32) -> Color {
        luminance(rgb) > 0.6 ? color(0x1B1530) : .white
    }

    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        dynamicColor(light: color(light), dark: color(dark))
    }

    private static func dynamicColor(light: Color, dark: Color) -> Color {
        #if os(iOS)
        Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light) })
        #else
        dark
        #endif
    }
}

/// How the app picks light or dark.
enum Appearance: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: Self { self }
    var title: String { rawValue.capitalized }
    var scheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

extension Text {
    /// Small bold section label.
    func label(_ color: Color = Theme.secondary) -> some View {
        self.font(.system(size: 13, weight: .heavy, design: .rounded))
            .foregroundStyle(color)
    }
}

extension View {
    /// The soft drop shadow used on Paper surfaces. Disappears in dark mode.
    func paperShadow() -> some View {
        shadow(color: Theme.shadow, radius: 10, x: 0, y: 4)
    }
}
