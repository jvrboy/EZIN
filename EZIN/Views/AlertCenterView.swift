import SwiftUI

/// User-facing alert center. Alerts can be created by Chat or a future chart-level
/// gesture, but their live evaluation and event history are visible here.
struct AlertCenterView: View {
    @ObservedObject private var store = AlertStore.shared

    var body: some View {
        GlassScreen(title: "Alert Center") {
            GlassSection(title: "How to create alerts") {
                Text("Ask Chat to create one, for example: “Create a critical price-above alert for Volatility 100 at 250.” Alerts are evaluated against live Deriv prices and candles when available.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.62))
            }

            GlassSection(title: "Configured (\(store.configurations.count))") {
                if store.configurations.isEmpty {
                    Text("No alerts configured yet.")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.5))
                        .padding(.vertical, 8)
                } else {
                    ForEach(store.configurations) { alert in
                        HStack(spacing: 10) {
                            Image(systemName: alert.conditionType.icon)
                                .foregroundStyle(alert.enabled ? Glass.accent2 : .white.opacity(0.3))
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(alert.name)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.9))
                                Text("\(DerivSymbols.display(alert.symbol)) · \(alert.conditionType.rawValue) · \(alert.conditionValue, specifier: "%.4f")")
                                    .font(.caption2)
                                    .foregroundStyle(.white.opacity(0.45))
                            }
                            Spacer()
                            Toggle("", isOn: Binding(
                                get: { alert.enabled },
                                set: { _ in store.toggle(alert) }
                            ))
                            .labelsHidden()
                            .tint(Glass.accent)
                        }
                        .padding(.vertical, 7)
                        if alert.id != store.configurations.last?.id {
                            Divider().overlay(Color.white.opacity(0.08))
                        }
                    }
                }
            }

            GlassSection(title: "Recent events") {
                if store.recentEvents.isEmpty {
                    Text("No alert events yet.")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.5))
                        .padding(.vertical, 8)
                } else {
                    ForEach(Array(store.recentEvents.prefix(20))) { event in
                        HStack(alignment: .top, spacing: 9) {
                            Image(systemName: event.acknowledged ? "checkmark.circle" : "bell.badge.fill")
                                .foregroundStyle(event.acknowledged ? .white.opacity(0.3) : Glass.accent2)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(event.name)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(.white.opacity(0.86))
                                Text(event.message)
                                    .font(.caption2)
                                    .foregroundStyle(.white.opacity(0.55))
                                Text(event.timestamp, style: .relative)
                                    .font(.caption2)
                                    .foregroundStyle(.white.opacity(0.3))
                            }
                            Spacer()
                            if !event.acknowledged {
                                Button("Ack") { store.acknowledgeEvent(event) }
                                    .font(.caption2)
                                    .foregroundStyle(Glass.accent)
                            }
                        }
                        .padding(.vertical, 7)
                    }
                    Button("Acknowledge all") { store.acknowledgeAll() }
                        .font(.caption)
                        .foregroundStyle(Glass.accent2)
                        .padding(.top, 5)
                }
            }
        }
    }
}
