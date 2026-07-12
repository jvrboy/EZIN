import SwiftUI

struct DerivConfigView: View {
    @EnvironmentObject var app: AppState
    @ObservedObject private var settings = SettingsStore.shared
    @ObservedObject private var creds = CredentialStore.shared
    @State private var appIDText = ""
    @State private var token = ""
    @State private var saved = false

    var body: some View {
        GlassScreen(title: "Deriv API") {
            GlassSection(title: "Connection") {
                GlassToggle(label: "Use custom Deriv API",
                            desc: "Off = default public app id (1089)",
                            isOn: $settings.useCustomDeriv)
            }

            if settings.useCustomDeriv {
                GlassSection(title: "Custom credentials") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("App ID").font(.caption).foregroundStyle(.white.opacity(0.5))
                        GlassField(placeholder: "e.g. 1089", text: $appIDText)
                        Text("API Token (optional)").font(.caption).foregroundStyle(.white.opacity(0.5))
                        GlassField(placeholder: "Deriv API token", text: $token, secure: true)
                    }
                }
            } else {
                GlassSection(title: "Public API") {
                    HStack {
                        Image(systemName: "checkmark.seal.fill").foregroundStyle(Glass.buy)
                        Text("Using default public app id 1089 — no setup needed.")
                            .font(.caption).foregroundStyle(.white.opacity(0.7))
                    }.padding(.vertical, 6)
                }
            }

            Button(action: save) {
                Text(saved ? "Saved ✓" : "Save & Reconnect")
                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity).padding(.vertical, 14)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Glass.accent.opacity(0.7)))
            }.buttonStyle(.plain)
        }
        .onAppear {
            appIDText = String(settings.derivAppID)
            token = creds.value(for: .derivToken) ?? ""
        }
    }

    private func save() {
        if settings.useCustomDeriv {
            if let id = Int(appIDText.trimmingCharacters(in: .whitespaces)), id > 0 { settings.derivAppID = id }
            if !token.isEmpty { creds.set(token, for: .derivToken) }
        } else {
            settings.derivAppID = DerivClient.defaultAppID
        }
        app.restartBackend()
        withAnimation { saved = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { saved = false }
    }
}
