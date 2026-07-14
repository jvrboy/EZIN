import SwiftUI

/// Appearance settings — theme, typography, text scale, and motion preferences.
struct AppearanceView: View {
    @ObservedObject private var theme = ThemeStore.shared
    private let themeColumns = [GridItem(.adaptive(minimum: 150), spacing: 12)]
    private let fontColumns = [GridItem(.adaptive(minimum: 138), spacing: 10)]

    var body: some View {
        GlassScreen(title: "Appearance") {
            GlassSection(title: "Theme") {
                LazyVGrid(columns: themeColumns, spacing: 12) {
                    ForEach(AppTheme.allCases) { item in
                        Button { withAnimation { theme.theme = item } } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(LinearGradient(colors: [item.blobA, item.blobB], startPoint: .topLeading, endPoint: .bottomTrailing))
                                    .frame(height: 54)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10)
                                            .stroke(theme.theme == item ? Color.white : .clear, lineWidth: 2)
                                    )
                                HStack {
                                    Text(item.title)
                                        .font(theme.typeface.font(size: 13, weight: .medium))
                                        .foregroundStyle(.white.opacity(0.85))
                                    Spacer()
                                    if theme.theme == item {
                                        Image(systemName: "checkmark.circle.fill").foregroundStyle(Glass.buy)
                                    }
                                }
                            }
                            .padding(10)
                            .glassCard()
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(item.title) theme")
                        .accessibilityAddTraits(theme.theme == item ? .isSelected : [])
                    }
                }
            }

            GlassSection(title: "Typography") {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Choose a typeface for the whole app. Changes apply immediately.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    LazyVGrid(columns: fontColumns, spacing: 10) {
                        ForEach(AppTypeface.allCases) { typeface in
                            Button { withAnimation(.easeInOut(duration: 0.18)) { theme.typeface = typeface } } label: {
                                VStack(alignment: .leading, spacing: 7) {
                                    Text("Aa 123")
                                        .font(typeface.previewFont)
                                        .foregroundStyle(.white)
                                    HStack(spacing: 5) {
                                        Text(typeface.title)
                                            .font(.caption.weight(.medium))
                                            .lineLimit(1)
                                        Spacer(minLength: 2)
                                        if theme.typeface == typeface {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundStyle(Glass.buy)
                                        }
                                    }
                                    .foregroundStyle(.white.opacity(0.8))
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(11)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(theme.typeface == typeface ? Glass.buy.opacity(0.13) : Color.white.opacity(0.045))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(theme.typeface == typeface ? Glass.buy.opacity(0.7) : Color.white.opacity(0.08), lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(theme.typeface == typeface ? .isSelected : [])
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Text size").font(.subheadline.weight(.semibold))
                        Picker("Text size", selection: $theme.textScale) {
                            ForEach(AppTextScale.allCases) { scale in
                                Text(scale.title).tag(scale)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    Text("Live market intelligence — RSI 58.4 · Trend Bullish")
                        .font(theme.typeface.previewFont)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))

                    Button("Reset typography") { withAnimation { theme.resetTypography() } }
                        .buttonStyle(.bordered)
                        .tint(.white.opacity(0.75))
                }
            }

            GlassSection(title: "Motion") {
                GlassToggle(label: "Animated background", desc: "Aurora blobs drift and pulse", isOn: $theme.motionEnabled)
            }
        }
    }
}
