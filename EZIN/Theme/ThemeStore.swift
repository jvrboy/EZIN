import SwiftUI
import Combine

/// Selectable app themes (background gradients + aurora blob colors) and motion preference.
enum AppTheme: String, CaseIterable, Identifiable {
    case aurora, liquidGlass, midnight, sunset, ocean, forest, mono, neon
    var id: String { rawValue }

    var title: String {
        switch self {
        case .aurora: return "Aurora"
        case .liquidGlass: return "Liquid Glass"
        case .midnight: return "Midnight"
        case .sunset: return "Sunset"
        case .ocean: return "Ocean"
        case .forest: return "Forest"
        case .mono: return "Mono"
        case .neon: return "Neon"
        }
    }

    var gradientTop: Color {
        switch self {
        case .aurora: return Color(red: 0.05, green: 0.06, blue: 0.12)
        case .liquidGlass: return Color(red: 0.10, green: 0.11, blue: 0.14)
        case .midnight: return Color(red: 0.02, green: 0.03, blue: 0.08)
        case .sunset: return Color(red: 0.12, green: 0.05, blue: 0.10)
        case .ocean: return Color(red: 0.02, green: 0.08, blue: 0.12)
        case .forest: return Color(red: 0.03, green: 0.10, blue: 0.07)
        case .mono: return Color(red: 0.08, green: 0.08, blue: 0.09)
        case .neon: return Color(red: 0.05, green: 0.03, blue: 0.12)
        }
    }

    var gradientBottom: Color {
        switch self {
        case .aurora: return Color(red: 0.02, green: 0.02, blue: 0.05)
        case .liquidGlass: return Color(red: 0.03, green: 0.03, blue: 0.05)
        case .midnight: return Color(red: 0.00, green: 0.00, blue: 0.02)
        case .sunset: return Color(red: 0.05, green: 0.02, blue: 0.04)
        case .ocean: return Color(red: 0.00, green: 0.03, blue: 0.06)
        case .forest: return Color(red: 0.01, green: 0.04, blue: 0.03)
        case .mono: return Color(red: 0.02, green: 0.02, blue: 0.02)
        case .neon: return Color(red: 0.02, green: 0.01, blue: 0.05)
        }
    }

    var blobA: Color {
        switch self {
        case .aurora: return Color(red: 0.40, green: 0.47, blue: 0.98)
        case .liquidGlass: return Color(red: 0.60, green: 0.70, blue: 0.92)
        case .midnight: return Color(red: 0.15, green: 0.20, blue: 0.55)
        case .sunset: return Color(red: 0.98, green: 0.45, blue: 0.35)
        case .ocean: return Color(red: 0.20, green: 0.60, blue: 0.92)
        case .forest: return Color(red: 0.20, green: 0.75, blue: 0.50)
        case .mono: return Color(red: 0.55, green: 0.55, blue: 0.60)
        case .neon: return Color(red: 0.85, green: 0.20, blue: 0.95)
        }
    }

    var blobB: Color {
        switch self {
        case .aurora: return Color(red: 0.35, green: 0.83, blue: 0.94)
        case .liquidGlass: return Color(red: 0.80, green: 0.85, blue: 0.95)
        case .midnight: return Color(red: 0.10, green: 0.30, blue: 0.55)
        case .sunset: return Color(red: 0.95, green: 0.30, blue: 0.55)
        case .ocean: return Color(red: 0.10, green: 0.82, blue: 0.75)
        case .forest: return Color(red: 0.55, green: 0.85, blue: 0.35)
        case .mono: return Color(red: 0.72, green: 0.72, blue: 0.78)
        case .neon: return Color(red: 0.20, green: 0.92, blue: 0.95)
        }
    }
}

/// App-wide typography choices. Uses system font designs so no bundled font files
/// are required and startup remains safe on every iOS 15+ device.
enum AppFontStyle: String, CaseIterable, Identifiable {
    case rounded, defaultSystem, serif, monospaced, condensed, heavy, elegant, traderMono, neonDisplay, compact
    var id: String { rawValue }

    var title: String {
        switch self {
        case .rounded: return "Rounded"
        case .defaultSystem: return "System"
        case .serif: return "Serif"
        case .monospaced: return "Mono"
        case .condensed: return "Condensed"
        case .heavy: return "Heavy"
        case .elegant: return "Elegant"
        case .traderMono: return "Trader Mono"
        case .neonDisplay: return "Neon Display"
        case .compact: return "Compact"
        }
    }

    var font: Font {
        switch self {
        case .rounded: return .system(.body, design: .rounded)
        case .defaultSystem: return .system(.body, design: .default)
        case .serif: return .system(.body, design: .serif)
        case .monospaced, .traderMono: return .system(.body, design: .monospaced)
        case .condensed, .compact: return .system(size: 15, weight: .regular, design: .default)
        case .heavy, .neonDisplay: return .system(.body, design: .rounded).weight(.semibold)
        case .elegant: return .system(.body, design: .serif).weight(.medium)
        }
    }
}

final class ThemeStore: ObservableObject {
    static let shared = ThemeStore()
    @Published var theme: AppTheme { didSet { UserDefaults.standard.set(theme.rawValue, forKey: "app.theme") } }
    @Published var motionEnabled: Bool { didSet { UserDefaults.standard.set(motionEnabled, forKey: "app.motion") } }
    @Published var fontStyle: AppFontStyle { didSet { UserDefaults.standard.set(fontStyle.rawValue, forKey: "app.fontStyle") } }

    private init() {
        theme = AppTheme(rawValue: UserDefaults.standard.string(forKey: "app.theme") ?? "aurora") ?? .aurora
        motionEnabled = (UserDefaults.standard.object(forKey: "app.motion") as? Bool) ?? true
        fontStyle = AppFontStyle(rawValue: UserDefaults.standard.string(forKey: "app.fontStyle") ?? "rounded") ?? .rounded
    }
}
