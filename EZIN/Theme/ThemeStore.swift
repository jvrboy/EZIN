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

enum AppTypeface: String, CaseIterable, Identifiable {
    case system, rounded, serif, monospaced, avenirNext, futura, georgia
    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "System"
        case .rounded: return "Rounded"
        case .serif: return "New York"
        case .monospaced: return "Monospaced"
        case .avenirNext: return "Avenir Next"
        case .futura: return "Futura"
        case .georgia: return "Georgia"
        }
    }

    var previewFont: Font {
        switch self {
        case .system: return .system(size: 18)
        case .rounded: return .system(size: 18, design: .rounded)
        case .serif: return .system(size: 18, design: .serif)
        case .monospaced: return .system(size: 18, design: .monospaced)
        case .avenirNext: return .custom("Avenir Next", size: 18)
        case .futura: return .custom("Futura", size: 18)
        case .georgia: return .custom("Georgia", size: 18)
        }
    }

    var appFont: Font { font(size: 17) }

    /// Builds a weighted font for explicit UI labels that would otherwise override the app-wide
    /// environment font. Numeric/code surfaces can request monospacing regardless of preference.
    func font(size: CGFloat, weight: Font.Weight = .regular, monospaced: Bool = false) -> Font {
        if monospaced { return .system(size: size, weight: weight, design: .monospaced) }
        switch self {
        case .system: return .system(size: size, weight: weight)
        case .rounded: return .system(size: size, weight: weight, design: .rounded)
        case .serif: return .system(size: size, weight: weight, design: .serif)
        case .monospaced: return .system(size: size, weight: weight, design: .monospaced)
        case .avenirNext: return .custom("Avenir Next", size: size, relativeTo: .body).weight(weight)
        case .futura: return .custom("Futura", size: size, relativeTo: .body).weight(weight)
        case .georgia: return .custom("Georgia", size: size, relativeTo: .body).weight(weight)
        }
    }
}

enum AppTextScale: String, CaseIterable, Identifiable {
    case compact, standard, comfortable, accessibility
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var dynamicTypeSize: DynamicTypeSize {
        switch self {
        case .compact: return .medium
        case .standard: return .large
        case .comfortable: return .xLarge
        case .accessibility: return .xxxLarge
        }
    }
}

final class ThemeStore: ObservableObject {
    static let shared = ThemeStore()
    @Published var theme: AppTheme { didSet { UserDefaults.standard.set(theme.rawValue, forKey: "app.theme") } }
    @Published var motionEnabled: Bool { didSet { UserDefaults.standard.set(motionEnabled, forKey: "app.motion") } }
    @Published var typeface: AppTypeface { didSet { UserDefaults.standard.set(typeface.rawValue, forKey: "app.typeface") } }
    @Published var textScale: AppTextScale { didSet { UserDefaults.standard.set(textScale.rawValue, forKey: "app.textScale") } }

    private init() {
        theme = AppTheme(rawValue: UserDefaults.standard.string(forKey: "app.theme") ?? "aurora") ?? .aurora
        motionEnabled = (UserDefaults.standard.object(forKey: "app.motion") as? Bool) ?? true
        typeface = AppTypeface(rawValue: UserDefaults.standard.string(forKey: "app.typeface") ?? "system") ?? .system
        textScale = AppTextScale(rawValue: UserDefaults.standard.string(forKey: "app.textScale") ?? "standard") ?? .standard
    }

    func resetTypography() {
        typeface = .system
        textScale = .standard
    }
}
