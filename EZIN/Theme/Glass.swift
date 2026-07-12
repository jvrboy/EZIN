import SwiftUI

/// Glassmorphism design system — iOS 15+ compatible (uses .ultraThinMaterial + custom overlays).
enum Glass {
    static let corner: CGFloat = 20
    static let cornerSmall: CGFloat = 14

    // Aurora background palette
    static let bgTop = Color(red: 0.05, green: 0.06, blue: 0.12)
    static let bgBottom = Color(red: 0.02, green: 0.02, blue: 0.05)
    static let accent = Color(red: 0.40, green: 0.47, blue: 0.98)      // indigo
    static let accent2 = Color(red: 0.35, green: 0.83, blue: 0.94)     // cyan
    static let buy = Color(red: 0.20, green: 0.85, blue: 0.60)
    static let sell = Color(red: 0.98, green: 0.35, blue: 0.45)
}

/// Frosted glass card modifier.
struct GlassCard: ViewModifier {
    var strong = false
    var corner: CGFloat = Glass.corner
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: corner, style: .continuous)
                            .fill(Color.white.opacity(strong ? 0.10 : 0.04))
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [.white.opacity(0.25), .white.opacity(0.05)],
                            startPoint: .topLeading, endPoint: .bottomTrailing),
                        lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.35), radius: 18, x: 0, y: 10)
    }
}

extension View {
    func glassCard(strong: Bool = false, corner: CGFloat = Glass.corner) -> some View {
        modifier(GlassCard(strong: strong, corner: corner))
    }
}

/// Animated aurora mesh background used app-wide.
struct AuroraBackground: View {
    @State private var animate = false
    var body: some View {
        ZStack {
            LinearGradient(colors: [Glass.bgTop, Glass.bgBottom],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            Circle()
                .fill(Glass.accent.opacity(0.35))
                .frame(width: 320, height: 320)
                .blur(radius: 90)
                .offset(x: animate ? -120 : -60, y: animate ? -220 : -160)

            Circle()
                .fill(Glass.accent2.opacity(0.28))
                .frame(width: 280, height: 280)
                .blur(radius: 90)
                .offset(x: animate ? 140 : 90, y: animate ? 260 : 200)
        }
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.easeInOut(duration: 8).repeatForever(autoreverses: true)) {
                animate.toggle()
            }
        }
    }
}
