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
            GlassSection(title: "App ID") {
                GlassToggle(label: "Use custom App ID",
                            desc: "Off = default public app id (1089)",
                            isOn: $settings.useCustomDeriv)
                if settings.useCustomDeriv {
                    Divider().overlay(Color.white.opacity(0.08))
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Custom App ID").font(.caption).foregroundStyle(.white.opacity(0.5))
                        GlassField(placeholder: "e.g. 1089", text: $appIDText)
                    }.padding(.top, 4)
                }
            }

            // PAT is available in BOTH modes — public app id + your token is valid.
            GlassSection(title: "Personal Access Token (PAT)") {
                VStack(alignment: .leading, spacing: 8) {
                    GlassField(placeholder: "Paste your Deriv API token", text: $token, secure: true)
                    Text("Required for live trading, balance & real trade history. Create one at app.deriv.com → API token.")
                        .font(.caption2).foregroundStyle(.white.opacity(0.4))
                    HStack(spacing: 6) {
                        Image(systemName: app.deriv.authorized ? "checkmark.seal.fill" : "seal")
                            .foregroundStyle(app.deriv.authorized ? Glass.buy : .white.opacity(0.3))
                        Text(app.deriv.authorized ? "Authorized" : "Not authorized")
                            .font(.caption).foregroundStyle(.white.opacity(0.6))
                    }.padding(.top, 4)
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
        if settings.useCustomDeriv, let id = Int(appIDText.trimmingCharacters(in: .whitespaces)), id > 0 {
            settings.derivAppID = id
        } else if !settings.useCustomDeriv {
            settings.derivAppID = DerivClient.defaultAppID
        }
        let trimmed = token.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { creds.remove(.derivToken) } else { creds.set(trimmed, for: .derivToken) }
        app.restartBackend()
        withAnimation { saved = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { saved = false }
    }
}
