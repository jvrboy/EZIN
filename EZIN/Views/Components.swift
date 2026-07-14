import SwiftUI

struct GlassSection<Content: View>: View {
    let title: String
    @ObservedObject private var theme = ThemeStore.shared
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(theme.typeface.font(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.5))
                .padding(.leading, 4)
            VStack(spacing: 0) { content }
                .padding(14).glassCard()
        }
    }
}

struct GlassToggle: View {
    let label: String
    var desc: String? = nil
    @Binding var isOn: Bool
    @ObservedObject private var theme = ThemeStore.shared
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(theme.typeface.font(size: 14, weight: .medium)).foregroundStyle(.white.opacity(0.88))
                if let desc = desc { Text(desc).font(.caption2).foregroundStyle(.white.opacity(0.4)) }
            }
            Spacer()
            Toggle("", isOn: $isOn).labelsHidden().tint(Glass.accent)
        }
        .padding(.vertical, 8)
    }
}

struct GlassNavRow: View {
    let icon: String; let title: String; var value: String? = nil
    @ObservedObject private var theme = ThemeStore.shared
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon).foregroundStyle(Glass.accent2).frame(width: 24)
            Text(title).font(theme.typeface.font(size: 14, weight: .medium)).foregroundStyle(.white.opacity(0.9))
            Spacer()
            if let value = value { Text(value).font(.caption).foregroundStyle(.white.opacity(0.45)) }
            Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(.white.opacity(0.3))
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}

struct GlassField: View {
    let placeholder: String
    @Binding var text: String
    var secure: Bool = false
    @ObservedObject private var theme = ThemeStore.shared
    var body: some View {
        Group {
            if secure { SecureField(placeholder, text: $text) }
            else { TextField(placeholder, text: $text) }
        }
        .font(theme.typeface.font(size: 15))
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .foregroundStyle(.white)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.12), lineWidth: 1))
    }
}

/// Reusable screen scaffold with aurora background + scrollable glass content.
struct GlassScreen<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content
    var body: some View {
        ZStack {
            AuroraBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) { content }
                    .padding(16).padding(.bottom, 24)
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
