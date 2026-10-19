import SwiftUI
import AppKit

enum AppearanceMode: String, CaseIterable, Identifiable {
    case system = "System", light = "Light", dark = "Dark"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max.fill"
        case .dark: return "moon.fill"
        }
    }
}

/// User preferences (UserDefaults). Views read them reactively with `@AppStorage(Prefs.…Key)`.
enum Prefs {
    static let appearanceKey = "appearance"
    static let accentKey = "accentSeed"
    static let artworkColorsKey = "artworkColors"
    static let reduceMotionKey = "reduceMotion"
    static let crashAlertsKey = "crashAlerts"
    static let hotkeyKey = "globalHotkey"
    static let finderTagsKey = "statusAsFinderTags"
    static let autoUpdateKey = "checkForUpdates"

    static let accents: [(name: String, seed: OKLCH)] = [
        ("Strata", OKLCH(l: 0.63, c: 0.21, h: 33)),     // the icon's red-orange
        ("Violet", OKLCH(l: 0.55, c: 0.19, h: 292)),
        ("Ocean", OKLCH(l: 0.55, c: 0.16, h: 250)),
        ("Lagoon", OKLCH(l: 0.6, c: 0.12, h: 195)),
        ("Leaf", OKLCH(l: 0.6, c: 0.15, h: 145)),
        ("Rose", OKLCH(l: 0.58, c: 0.19, h: 5)),
    ]

    static func register() {
        UserDefaults.standard.register(defaults: [
            appearanceKey: AppearanceMode.system.rawValue,
            accentKey: 0,
            artworkColorsKey: true,
            reduceMotionKey: false,
            crashAlertsKey: true,
            hotkeyKey: true,
            autoUpdateKey: true,
        ])
    }

    static var crashAlerts: Bool { UserDefaults.standard.bool(forKey: crashAlertsKey) }

    static func accent(_ index: Int) -> OKLCH { accents[min(max(index, 0), accents.count - 1)].seed }

    /// Light / dark / follow the system, for every window including the menu bar panel.
    static func applyAppearance(_ raw: String) {
        switch AppearanceMode(rawValue: raw) ?? .system {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }
}
