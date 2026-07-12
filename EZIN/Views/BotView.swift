import SwiftUI

/// Bot tab — just the bot: a large liquid-glass Start/Stop button with live animation.
/// All configuration lives in Settings → Trading Bot.
struct BotView: View {
    @EnvironmentObject var app: AppState
    @State private var pulse = false
    @State private var rotate = false

    private var running: Bool { app.bot.running }

    var body: some View {
        VStack {
            Spacer()

            // Animated bot orb
            ZStack {
                ForEach(0..<3) { i in
                    Circle()
                        .stroke(
                            LinearGradient(colors: [Glass.accent, Glass.accent2],
                                           startPoint: .top, endPoint: .bottom).opacity(running ? 0.5 : 0.15),
                            lineWidth: 2)
                        .frame(width: 150 + CGFloat(i) * 55, height: 150 + CGFloat(i) * 55)
                        .scaleEffect(pulse && running ? 1.08 : 1.0)
                        .opacity(running ? (pulse ? 0.2 : 0.6) : 0.25)
                        .animation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true).delay(Double(i) * 0.25), value: pulse)
                }

                Circle()
                    .fill(LinearGradient(colors: [Glass.accent.opacity(0.35), Glass.accent2.opacity(0.2)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 140, height: 140)
                    .overlay(Circle().stroke(Color.white.opacity(0.25), lineWidth: 1))
                    .blur(radius: 0.5)

                Image(systemName: "cpu")
                    .font(.system(size: 52, weight: .semibold))
                    .foregroundStyle(.white)
                    .rotationEffect(.degrees(rotate && running ? 360 : 0))
                    .animation(running ? .linear(duration: 8).repeatForever(autoreverses: false) : .default, value: rotate)
            }
            .frame(height: 300)

            Text(running ? "Bot is trading" : "Bot is idle")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
                .padding(.top, 4)

            // Compact live readout (real account data)
            if app.deriv.authorized {
                HStack(spacing: 22) {
                    liveStat("Balance", String(format: "%@ %.2f", app.deriv.currency, app.deriv.balance))
                    liveStat("Open", "\(app.deriv.openPositionCount)")
                    liveStat("P&L", String(format: "%+.2f", app.deriv.totalOpenProfit))
                }
                .padding(.top, 10)
            } else {
                Text("Add your Deriv API token in Settings to enable live trading")
                    .font(.caption2).foregroundStyle(.white.opacity(0.45))
                    .multilineTextAlignment(.center).padding(.horizontal, 40).padding(.top, 8)
            }

            Spacer()

            // Liquid glass Start / Stop button
            Button {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                    if running { app.bot.stopBot() } else { app.bot.startBot() }
                    pulse.toggle(); rotate.toggle()
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: running ? "stop.fill" : "play.fill").font(.system(size: 22, weight: .bold))
                    Text(running ? "STOP BOT" : "START BOT").font(.system(size: 20, weight: .bold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 72)
                .background(
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 26, style: .continuous)
                                .fill(LinearGradient(
                                    colors: running ? [Glass.sell.opacity(0.5), Glass.sell.opacity(0.25)]
                                                    : [Glass.accent.opacity(0.55), Glass.accent2.opacity(0.35)],
                                    startPoint: .topLeading, endPoint: .bottomTrailing))
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .stroke(Color.white.opacity(0.3), lineWidth: 1)
                )
                .shadow(color: (running ? Glass.sell : Glass.accent).opacity(0.4), radius: 24, x: 0, y: 10)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { pulse = true; rotate = true }
    }

    private func liveStat(_ label: String, _ value: String) -> some View {
        VStack(spacing: 3) {
            Text(value).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white.opacity(0.9))
            Text(label).font(.caption2).foregroundStyle(.white.opacity(0.45))
        }
    }
}
