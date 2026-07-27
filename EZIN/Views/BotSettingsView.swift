import SwiftUI

/// Full bot configuration. Paper mode is the safe default; live mode requires
/// explicit arming and respects the configured risk limits.
struct BotSettingsView: View {
    @EnvironmentObject var app: AppState
    @ObservedObject private var store = BotConfigStore.shared

    private var cfg: Binding<BotConfig> { $store.config }

    var body: some View {
        GlassScreen(title: "Trading Bot") {

            GlassSection(title: "How it trades") {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "bolt.fill").foregroundStyle(Glass.accent2)
                    Text("Paper-first multi-timeframe scanner. It evaluates the council and indicator stack while the app is active. Live orders require explicit arming and are never guaranteed to run while iOS suspends the app.")
                        .font(.caption).foregroundStyle(.white.opacity(0.6))
                }.padding(.vertical, 6)
            }

            GlassSection(title: "Execution safety") {
                Picker("Mode", selection: cfg.executionMode) {
                    ForEach(TradingExecutionMode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                Divider().overlay(Color.white.opacity(0.08))
                Stepper(value: cfg.dailyTradeLimit, in: 0...100) {
                    Text(store.config.dailyTradeLimit == 0 ? "Daily trade limit: Off" : "Daily trade limit: \(store.config.dailyTradeLimit)")
                        .font(.system(size: 13)).foregroundStyle(.white.opacity(0.82))
                }
                .tint(Glass.accent)

                Divider().overlay(Color.white.opacity(0.08))
                HStack {
                    Text("Daily loss limit").font(.system(size: 13)).foregroundStyle(.white.opacity(0.82))
                    Spacer()
                    TextField("0 = off", value: cfg.dailyLossLimit, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 90)
                        .foregroundStyle(.white)
                }

                GlassToggle(label: "Require live order arming", desc: "Live mode stays blocked until you explicitly arm it", isOn: cfg.requireOrderPreview)

                if store.config.executionMode == .paper {
                    Text("Paper mode is the default. It creates simulated positions and never sends orders to Deriv.")
                        .font(.caption2).foregroundStyle(Glass.accent2.opacity(0.9))
                } else {
                    Text("Live mode is dangerous. Verify demo credentials, stops, and daily limits before arming.")
                        .font(.caption2).foregroundStyle(Glass.sell.opacity(0.9))
                    Button(app.bot.liveTradingArmed ? "Live trading armed" : "Arm live trading") {
                        if app.bot.liveTradingArmed { app.bot.disarmLiveTrading() } else { app.bot.armLiveTrading() }
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(app.bot.liveTradingArmed ? Glass.sell : Glass.accent)
                }
            }

            GlassSection(title: "Fixed lot size (stake)") {
                Stepper(value: cfg.fixedLotSize, in: 0.35...1000, step: 0.5) {
                    Text("\(store.config.fixedLotSize, specifier: "%.2f") \(store.config.currency)")
                        .font(.system(size: 14, weight: .medium)).foregroundStyle(.white.opacity(0.9))
                }.tint(Glass.accent)
                Divider().overlay(Color.white.opacity(0.08))
                HStack {
                    Text("Multiplier").font(.system(size: 14)).foregroundStyle(.white.opacity(0.8))
                    Spacer()
                    Picker("", selection: cfg.multiplier) {
                        ForEach([30, 50, 100, 200, 400], id: \.self) { Text("x\($0)").tag($0) }
                    }.pickerStyle(.menu).tint(Glass.accent2)
                }
            }

            GlassSection(title: "Max open positions") {
                Stepper(value: cfg.maxOpenPositions, in: 1...20) {
                    Text("\(store.config.maxOpenPositions) at a time")
                        .font(.system(size: 14, weight: .medium)).foregroundStyle(.white.opacity(0.9))
                }.tint(Glass.accent)
            }

            GlassSection(title: "Stops") {
                Picker("", selection: cfg.stopMode) {
                    ForEach(StopMode.allCases) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented)

                if store.config.stopMode != .botChoice {
                    Divider().overlay(Color.white.opacity(0.08))
                    stopField("Stop loss", value: cfg.stopLossValue, unit: unitLabel)
                    Divider().overlay(Color.white.opacity(0.08))
                    stopField("Take profit", value: cfg.takeProfitValue, unit: unitLabel)
                } else {
                    Text("Bot derives stop-loss & take-profit from live ATR/volatility per trade.")
                        .font(.caption2).foregroundStyle(.white.opacity(0.45)).padding(.top, 6)
                }
            }

            InstrumentsPicker(selected: cfg.instruments)

            Text("Bot trades only the instruments you select above.")
                .font(.caption2).foregroundStyle(.white.opacity(0.4))
        }
    }

    private var unitLabel: String {
        switch store.config.stopMode {
        case .points: return "pts"; case .pips: return "pips"; case .profit: return store.config.currency; default: return ""
        }
    }

    private func stopField(_ label: String, value: Binding<Double>, unit: String) -> some View {
        HStack {
            Text(label).font(.system(size: 14)).foregroundStyle(.white.opacity(0.8))
            Spacer()
            TextField("0", value: value, format: .number)
                .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                .foregroundStyle(.white).frame(width: 80)
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.06)))
            Text(unit).font(.caption).foregroundStyle(.white.opacity(0.45)).frame(width: 34, alignment: .leading)
        }
    }
}

/// Grouped multi-select instrument picker.
struct InstrumentsPicker: View {
    @Binding var selected: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("INSTRUMENTS").font(.system(size: 11, weight: .semibold)).foregroundStyle(.white.opacity(0.5)).padding(.leading, 4)
            VStack(spacing: 14) {
                ForEach(DerivSymbols.groups, id: \.0) { group in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(group.0).font(.caption).foregroundStyle(.white.opacity(0.5))
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 90), spacing: 8)], alignment: .leading, spacing: 8) {
                            ForEach(group.1, id: \.self) { sym in
                                chip(sym)
                            }
                        }
                    }
                }
            }.padding(14).glassCard()
        }
    }

    private func chip(_ sym: String) -> some View {
        let on = selected.contains(sym)
        return Button {
            if on { selected.removeAll { $0 == sym } } else { selected.append(sym) }
        } label: {
            Text(DerivSymbols.display(sym))
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background((on ? Glass.accent : Color.white).opacity(on ? 0.28 : 0.05))
                .foregroundStyle(on ? Color.white : .white.opacity(0.6))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(on ? 0.4 : 0.12), lineWidth: 1))
        }.buttonStyle(.plain)
    }
}
