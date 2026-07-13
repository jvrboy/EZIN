import SwiftUI

/// Appearance settings — theme picker + motion preference.
struct AppearanceView: View {
    @ObservedObject private var theme = ThemeStore.shared
    private let cols = [GridItem(.adaptive(minimum: 150), spacing: 12)]

    var body: some View {
        GlassScreen(title: "Appearance") {
            GlassSection(title: "Theme") {
                LazyVGrid(columns: cols, spacing: 12) {
                    ForEach(AppTheme.allCases) { t in
                        Button { withAnimation { theme.theme = t } } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(LinearGradient(colors: [t.blobA, t.blobB],
                                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                                    .frame(height: 54)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10)
                                            .stroke(theme.theme == t ? Color.white : .clear, lineWidth: 2)
                                    )
                                HStack {
                                    Text(t.title).font(.system(size: 13, weight: .medium)).foregroundStyle(.white.opacity(0.85))
                                    Spacer()
                                    if theme.theme == t { Image(systemName: "checkmark.circle.fill").foregroundStyle(Glass.buy) }
                                }
                            }
                            .padding(10)
                            .glassCard()
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            GlassSection(title: "Motion") {
                GlassToggle(label: "Animated background", desc: "Aurora blobs drift and pulse", isOn: $theme.motionEnabled)
            }
        }
    }
}
