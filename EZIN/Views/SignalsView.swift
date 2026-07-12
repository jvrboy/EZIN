import SwiftUI

struct SignalsView: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                HStack {
                    Text("Live Signals").font(.headline).foregroundStyle(.white.opacity(0.9))
                    Spacer()
                    Text("\(app.signals.count) active").font(.caption).foregroundStyle(.white.opacity(0.5))
                }

                if app.signals.isEmpty {
                    EmptyState(icon: "waveform.path.ecg",
                               title: "Scanning markets…",
                               subtitle: "The council is deliberating. Signals appear when consensus is reached.")
                } else {
                    ForEach(app.signals) { s in SignalCard(signal: s) }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
    }
}

struct SignalCard: View {
    let signal: TradingSignal
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.08))
                Text(String(signal.displayPair.prefix(3)))
                    .font(.system(size: 12, weight: .bold)).foregroundStyle(.white.opacity(0.85))
            }
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 3) {
                Text(signal.displayPair).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white.opacity(0.92))
                Text("\(signal.strategy) · \(signal.timeframe.rawValue)")
                    .font(.caption2).foregroundStyle(.white.opacity(0.45))
                Text("Entry \(fmt(signal.entry)) · SL \(fmt(signal.stopLoss)) · TP \(fmt(signal.takeProfit))")
                    .font(.system(size: 10)).foregroundStyle(.white.opacity(0.4))
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                DirBadge(isBuy: signal.isBuy)
                Text("\(Int(signal.confidence))%").font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
                ConfidenceBar(value: signal.confidence)
            }
        }
        .padding(14)
        .glassCard()
    }

    private func fmt(_ v: Double) -> String {
        v > 100 ? String(format: "%.1f", v) : String(format: "%.4f", v)
    }
}

struct DirBadge: View {
    let isBuy: Bool
    var body: some View {
        Text(isBuy ? "BUY" : "SELL")
            .font(.system(size: 11, weight: .bold))
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background((isBuy ? Glass.buy : Glass.sell).opacity(0.18))
            .foregroundStyle(isBuy ? Glass.buy : Glass.sell)
            .clipShape(Capsule())
            .overlay(Capsule().stroke((isBuy ? Glass.buy : Glass.sell).opacity(0.4), lineWidth: 1))
    }
}

struct ConfidenceBar: View {
    let value: Double
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.1))
                Capsule()
                    .fill(LinearGradient(colors: [Glass.accent, Glass.accent2],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: geo.size.width * CGFloat(value / 100))
            }
        }
        .frame(width: 64, height: 5)
    }
}

struct EmptyState: View {
    let icon: String; let title: String; let subtitle: String
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 34)).foregroundStyle(.white.opacity(0.4))
            Text(title).font(.headline).foregroundStyle(.white.opacity(0.8))
            Text(subtitle).font(.caption).multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.45))
        }
        .frame(maxWidth: .infinity).padding(.vertical, 50).padding(.horizontal, 20)
        .glassCard()
    }
}
