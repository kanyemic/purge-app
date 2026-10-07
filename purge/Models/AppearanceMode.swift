import AppKit
import SwiftUI

enum AppearanceMode: String, CaseIterable {
    case system
    case light
    case dark

    static let userDefaultsKey = "appearance.mode"

    /// The mode currently persisted in user defaults (defaults to `.system`).
    static var current: AppearanceMode {
        let raw = UserDefaults.standard.string(forKey: userDefaultsKey)
        return raw.flatMap(AppearanceMode.init(rawValue:)) ?? .system
    }

    var displayName: String {
        switch self {
        case .system: return "跟随系统"
        case .light: return "浅色"
        case .dark: return "深色"
        }
    }

    var thumbnailAssetName: String {
        switch self {
        case .system: return "appearance-auto"
        case .light: return "appearance-light"
        case .dark: return "appearance-dark"
        }
    }

    /// `nil` means follow the system appearance.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    /// Concrete scheme for SwiftUI, including the current system look in Auto.
    var resolvedColorScheme: ColorScheme {
        switch self {
        case .light: return .light
        case .dark: return .dark
        case .system: return Self.systemResolvedColorScheme()
        }
    }

    /// Reads the live system appearance without touching `NSApp`, which is still
    /// nil while `PurgeApp`'s `@State` properties are being initialized.
    private static func systemResolvedColorScheme() -> ColorScheme {
        let appearance = NSApplication.shared.effectiveAppearance
        return appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .dark : .light
    }

    /// AppKit appearance for explicit light/dark overrides. `nil` follows system.
    var nsAppearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }
}

/// Applies appearance to AppKit and every window so SwiftUI semantic colors,
/// `Color(light:dark:)` assets, and AppKit-backed controls repaint together.
@MainActor
enum AppAppearance {
    private static let systemThemeChanged = Notification.Name("AppleInterfaceThemeChangedNotification")

    static func apply(_ mode: AppearanceMode) {
        let appearance = mode.nsAppearance
        NSApp.appearance = appearance

        for window in NSApp.windows {
            window.appearance = appearance
            window.contentView?.needsLayout = true
            window.contentView?.needsDisplay = true
            window.displayIfNeeded()
        }
    }

    static func addSystemThemeObserver(handler: @escaping () -> Void) -> NSObjectProtocol {
        DistributedNotificationCenter.default().addObserver(
            forName: systemThemeChanged,
            object: nil,
            queue: .main
        ) { _ in
            handler()
        }
    }
}
