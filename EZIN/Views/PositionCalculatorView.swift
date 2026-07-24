import SwiftUI

/// Position Calculator — position sizing, pip values, P&L forecasting, and risk management.
struct PositionCalculatorView: View {
    @State private var tab: CalculatorTab = .position

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $tab) {
                Text("Position").tag(CalculatorTab.position)
                Text("P&L").tag(CalculatorTab.pnl)
                Text("Risk").tag(CalculatorTab.risk)
                Text("Pip").tag(CalculatorTab.pip)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            switch tab {
            case .position: PositionSizeView()
            case .pnl: PnLCalculatorView()
            case .risk: RiskProfileView()
            case .pip: PipValueView()
            }
        }
        .navigationTitle("Calculator")
        .navigationBarTitleDisplayMode(.inline)
    }

    enum CalculatorTab: String, CaseIterable {
        case position = "Position"
        case pnl = "P&L"
        case risk = "Risk"
        case pip = "Pip"
    }
}

// MARK: - Position Size Calculator

struct PositionSizeView: View {
    @State private var accountSize = "10000"
    @State private var riskPercent = "1.0"
    @State private var entryPrice = "0"
    @State private var stopLoss = "0"
    @State private var takeProfit = ""
    @State private var symbol = "R_100"
    @State private var direction: Direction = .bullish
    @State private var result: PositionSizeResult?

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Input section
                GlassSection(title: "Inputs") {
                    HStack(spacing: 12) {
                        Menu {
                            ForEach(DerivSymbols.shortList.prefix(40), id: \.self) { sym in
                                Button(DerivSymbols.display(sym)) { symbol = sym }
                            }
                        } label: {
                            HStack {
                                Text(DerivSymbols.display(symbol))
                                    .foregroundStyle(.white)
                                Image(systemName: "chevron.down").font(.caption)
                            }
                            .padding(10)
                            .background(Color.white.opacity(0.06))
                            .cornerRadius(8)
                        }

                        Picker("Dir", selection: $direction) {
                            Text("BUY").tag(Direction.bullish)
                            Text("SELL").tag(Direction.bearish)
                        }
                        .pickerStyle(.segmented)
                    }

                    CalcField(label: "Account Size", value: $accountSize, suffix: "USD")
                    CalcField(label: "Risk %", value: $riskPercent, suffix: "%")
                    CalcField(label: "Entry Price", value: $entryPrice)
                    CalcField(label: "Stop Loss", value: $stopLoss)
                    CalcField(label: "Take Profit (opt)", value: $takeProfit)
                }

                // Calculate Button
                Button(action: calculate) {
                    Label("Calculate Position", systemImage: "function")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Glass.accent)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
                .buttonStyle(.plain)
                .disabled(entryPrice.isEmpty || stopLoss.isEmpty)

                // Result section
                if let r = result {
                    GlassSection(title: "Results") {
                        CalcResultRow(label: "Risk Amount", value: fmt(r.riskAmount), color: Glass.sell)
                        CalcResultRow(label: "Stop Loss (pips)", value: fmt(r.stopLossPips))
                        CalcResultRow(label: "Recommended Stake", value: fmt(r.recommendedStake))
                        CalcResultRow(label: "Pip Value", value: fmt(r.pipValue))
                        CalcResultRow(label: "Margin Required", value: fmt(r.marginRequired))
                        CalcResultRow(label: "Leverage", value: "1:\(fmt(r.leverage))")
                        CalcResultRow(label: "Margin Level", value: "\(fmt(r.marginLevel))%")
                        if r.riskRewardRatio > 0 {
                            CalcResultRow(label: "Risk:Reward", value: "1:\(fmt(r.riskRewardRatio))", color: Glass.buy)
                            if let profit = r.potentialProfit {
                                CalcResultRow(label: "Potential Profit", value: fmt(profit), color: Glass.buy)
                            }
                        }
                    }
                }
            }
            .padding(16)
        }
    }

    private func calculate() {
        guard let account = Double(accountSize),
              let entry = Double(entryPrice),
              let stop = Double(stopLoss),
              account > 0, entry > 0, stop > 0, stop != entry else { return }

        let tp = Double(takeProfit)
        let risk = Double(riskPercent) ?? 1.0
        let isForex = symbol.contains("/")

        result = PositionCalculatorService.shared.calculatePositionSize(
            accountSize: account,
            riskPercent: risk,
            entryPrice: entry,
            stopLoss: stop,
            takeProfit: tp,
            isForex: isForex
        )
    }

    private func fmt(_ v: Double, _ p: Int = 2) -> String {
        String(format: "%.\(p)f", v)
    }
}

// MARK: - P&L Calculator

struct PnLCalculatorView: View {
    @State private var entryPrice = "0"
    @State private var exitPrice = "0"
    @State private var positionSize = "100"
    @State private var direction: Direction = .bullish
    @State private var symbol = "R_100"
    @State private var pnlResult: (pnl: Double, pnlPercent: Double, pips: Double)?

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                GlassSection(title: "Inputs") {
                    HStack(spacing: 12) {
                        Menu {
                            ForEach(DerivSymbols.shortList.prefix(20), id: \.self) { sym in
                                Button(DerivSymbols.display(sym)) { symbol = sym }
                            }
                        } label: {
                            HStack {
                                Text(DerivSymbols.display(symbol))
                                    .foregroundStyle(.white)
                                Image(systemName: "chevron.down").font(.caption)
                            }
                            .padding(10)
                            .background(Color.white.opacity(0.06))
                            .cornerRadius(8)
                        }

                        Picker("Dir", selection: $direction) {
                            Text("BUY").tag(Direction.bullish)
                            Text("SELL").tag(Direction.bearish)
                        }
                        .pickerStyle(.segmented)
                    }

                    CalcField(label: "Entry Price", value: $entryPrice)
                    CalcField(label: "Exit Price", value: $exitPrice)
                    CalcField(label: "Position Size", value: $positionSize)
                }

                Button(action: calculate) {
                    Label("Calculate P&L", systemImage: "chart.line.uptrend.xyaxis")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Glass.accent)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
                .buttonStyle(.plain)
                .disabled(entryPrice.isEmpty || exitPrice.isEmpty)

                if let r = pnlResult {
                    GlassSection(title: "Results") {
                        CalcResultRow(label: "P&L", value: "\(r.pnl >= 0 ? "+" : "")\(fmt(r.pnl))",
                                      color: r.pnl >= 0 ? Glass.buy : Glass.sell)
                        CalcResultRow(label: "Return", value: "\(r.pnlPercent >= 0 ? "+" : "")\(fmt(r.pnlPercent))%",
                                      color: r.pnl >= 0 ? Glass.buy : Glass.sell)
                        CalcResultRow(label: "Pips", value: "\(r.pips >= 0 ? "+" : "")\(fmt(r.pips))")
                    }
                }
            }
            .padding(16)
        }
    }

    private func calculate() {
        guard let entry = Double(entryPrice), let exit = Double(exitPrice),
              let size = Double(positionSize), entry > 0 else { return }
        let isForex = symbol.contains("/")
        pnlResult = PositionCalculatorService.shared.calculatePnL(
            entryPrice: entry, exitPrice: exit, positionSize: size,
            direction: direction, isForex: isForex
        )
    }

    private func fmt(_ v: Double, _ p: Int = 2) -> String {
        String(format: "%.\(p)f", v)
    }
}

// MARK: - Risk Profile View

struct RiskProfileView: View {
    @State private var accountSize = "10000"
    @State private var winRate = "0.5"
    @State private var avgRR = "1.5"
    @State private var metrics: RiskMetricsResult?

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                GlassSection(title: "Your Profile") {
                    CalcField(label: "Account Size", value: $accountSize, suffix: "USD")
                    CalcField(label: "Historical Win Rate", value: $winRate)
                    CalcField(label: "Avg Risk:Reward", value: $avgRR)
                }

                Button(action: calculate) {
                    Label("Analyze Risk Profile", systemImage: "shield.checkered")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Glass.accent)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
                .buttonStyle(.plain)

                if let m = metrics {
                    GlassSection(title: "Risk Profile") {
                        CalcResultRow(label: "Max Daily Loss (2%)", value: fmt(m.maxDailyLoss), color: .orange)
                        CalcResultRow(label: "Max Weekly Loss (5%)", value: fmt(m.maxWeeklyLoss), color: .red)
                        CalcResultRow(label: "Max Per Trade (1%)", value: fmt(m.maxPositionRisk))
                        CalcResultRow(label: "Half-Kelly Size", value: "\(fmt(m.halfKelly * 100))%", color: Glass.buy)
                        CalcResultRow(label: "Kelly Fraction", value: "\(fmt(m.kellyFraction * 100))%")
                        CalcResultRow(label: "95% VaR (daily)", value: fmt(m.var95))
                        CalcResultRow(label: "95% CVaR (daily)", value: fmt(m.cvar95), color: Glass.sell)
                        CalcResultRow(label: "Max Consec. Losses", value: "\(m.maxConsecutiveLosses)")
                        CalcResultRow(label: "Daily Loss Limit", value: fmt(m.dailyLossLimit), color: .red)
                        CalcResultRow(label: "Weekly Loss Limit", value: fmt(m.weeklyLossLimit), color: .red)
                    }

                    if m.kellyFraction > 0.25 {
                        Text("⚠️ High Kelly fraction. Consider using half-Kelly for safer sizing.")
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .padding(.horizontal)
                    }
                }
            }
            .padding(16)
        }
    }

    private func calculate() {
        guard let acct = Double(accountSize), let wr = Double(winRate), let rr = Double(avgRR) else { return }
        metrics = PositionCalculatorService.shared.calculateRiskMetrics(
            accountSize: acct, winRate: wr, avgRR: rr
        )
    }

    private func fmt(_ v: Double, _ p: Int = 2) -> String {
        String(format: "%.\(p)f", v)
    }
}

// MARK: - Pip Value View

struct PipValueView: View {
    @State private var symbol = "EUR/USD"
    @State private var positionSize = "1000"
    @State private var entryPrice = "1.1000"
    @State private var pipInfo: LotSizeInfo?

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                GlassSection(title: "Inputs") {
                    Menu {
                        ForEach(["EUR/USD", "GBP/USD", "USD/JPY", "USD/CAD", "AUD/USD", "R_100", "1HZ10V"], id: \.self) { sym in
                            Button(DerivSymbols.display(sym)) { symbol = sym }
                        }
                    } label: {
                        HStack {
                            Text(DerivSymbols.display(symbol))
                                .foregroundStyle(.white)
                            Image(systemName: "chevron.down").font(.caption)
                        }
                        .padding(10)
                        .background(Color.white.opacity(0.06))
                        .cornerRadius(8)
                    }

                    CalcField(label: "Position Size", value: $positionSize, suffix: "units")
                    CalcField(label: "Entry Price", value: $entryPrice)
                }

                Button(action: calculate) {
                    Label("Calculate Pip Value", systemImage: "drop.fill")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Glass.accent)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
                .buttonStyle(.plain)

                if let info = pipInfo {
                    GlassSection(title: "Lot & Pip Info") {
                        CalcResultRow(label: "Standard Lot", value: "\(fmt(info.standardLot)) units")
                        CalcResultRow(label: "Mini Lot", value: "\(fmt(info.miniLot)) units")
                        CalcResultRow(label: "Micro Lot", value: "\(fmt(info.microLot)) units")
                        CalcResultRow(label: "Current Size", value: "\(fmt(info.currentLotSize * 100, 3))% std lot")
                        CalcResultRow(label: "Contract Size", value: "\(fmt(info.contractSize))")
                        let pipVal = info.currentLotSize > 0 ? (Double(positionSize) ?? 0) * 0.01 : 0
                        CalcResultRow(label: "Pip Value (est.)", value: fmt(pipVal), color: Glass.accent2)
                    }
                }
            }
            .padding(16)
        }
    }

    private func calculate() {
        guard let size = Double(positionSize), let price = Double(entryPrice), size > 0 else { return }
        let isForex = symbol.contains("/")
        pipInfo = PositionCalculatorService.shared.calculatePipValue(
            symbol: symbol, positionSize: size, entryPrice: price, isForex: isForex
        )
    }

    private func fmt(_ v: Double, _ p: Int = 2) -> String {
        String(format: "%.\(p)f", v)
    }
}

// MARK: - Shared UI Components

struct CalcField: View {
    let label: String
    @Binding var value: String
    var suffix: String = ""

    var body: some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.6))
                .frame(width: 100, alignment: .leading)
            TextField("0", text: $value)
                .textFieldStyle(.plain)
                .keyboardType(.decimalPad)
                .foregroundStyle(.white)
                .padding(10)
                .background(Color.white.opacity(0.06))
                .cornerRadius(8)
            if !suffix.isEmpty {
                Text(suffix)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.4))
                    .frame(width: 40)
            }
        }
    }
}

struct CalcResultRow: View {
    let label: String
    let value: String
    var color: Color = .white

    var body: some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.6))
            Spacer()
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(color.opacity(0.9))
        }
        .padding(.vertical, 4)
    }
}

// DerivSymbols helper for calculator picker
private extension DerivSymbols {
    static var shortList: [String] {
        let synths = volatility.prefix(10)
        let forex = ["EUR/USD", "GBP/USD", "USD/JPY", "USD/CAD", "AUD/USD", "EUR/JPY", "GBP/JPY"]
        let crypto = ["BTC/USD", "ETH/USD"]
        return Array(synths) + forex + crypto
    }
}
