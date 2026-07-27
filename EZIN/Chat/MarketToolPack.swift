import Foundation

/// Market tool pack — exposes the full indicator library, divergence/spike engines,
/// price-level math (Fibonacci, pivots), streak statistics, risk/reward + Kelly sizing,
/// the session clock and watchlist management to the chat assistant.
extension ToolRegistry {

    // MARK: - Formatting helpers

    private func fmtPrice(_ p: Double) -> String {
        if p == 0 { return "0" }
        return abs(p) >= 100 ? String(format: "%.2f", p) : String(format: "%.5f", p)
    }
    private func fmt2(_ v: Double) -> String { String(format: "%.2f", v) }

    private func dbl(_ args: [String: Any], _ key: String) -> Double? {
        if let d = args[key] as? Double { return d }
        if let i = args[key] as? Int { return Double(i) }
        return Double(str(args, key))
    }

    private func intArg(_ args: [String: Any], _ key: String) -> Int? {
        if let i = args[key] as? Int { return i }
        if let d = args[key] as? Double { return Int(d) }
        return Int(str(args, key))
    }

    private func requireMarketData(_ args: [String: Any]) -> (MarketData, String)? {
        let symbol = resolveSymbol(str(args, "symbol"))
        let timeframe = resolveTF(str(args, "timeframe"))
        guard !symbol.isEmpty else { return nil }
        app.deriv.subscribeTicks(symbol)
        guard let md = marketData(for: symbol, timeframe: timeframe) else { return nil }
        return (md, DerivSymbols.display(symbol))
    }

    private var needCandlesMessage: String {
        "Need a symbol with at least 30 cached candles. Open it on the Chart tab (or run analyze first), then ask again."
    }

    // MARK: - indicator_values

    /// Snapshot of the latest values across the core indicator suite.
    func indicatorValues(_ args: [String: Any]) -> String {
        guard let (md, name) = requireMarketData(args) else { return needCandlesMessage }
        let c = md.closes, h = md.highs, l = md.lows, v = md.volumes
        let last = c.count - 1

        let rsi = Indicators.rsi(c).last ?? 50
        let (macdLine, macdSignal, macdHist) = Indicators.macd(c)
        let (adxArr, pDIArr, mDIArr) = Indicators.adx(h, l, c)
        let atr = Indicators.atr(h, l, c).last ?? 0
        let (bbUArr, bbMArr, bbLArr) = Indicators.bollinger(c)
        let (stKArr, stDArr) = Indicators.stochastic(h, l, c)
        let cci = Indicators.cci(h, l, c).last ?? 0
        let wr = Indicators.williamsR(h, l, c).last ?? -50
        let mfi = Indicators.mfi(h, l, c, v).last ?? 50
        let (stLineArr, stUpArr) = Indicators.supertrend(h, l, c)
        let vwap = Indicators.vwap(h, l, c, v).last ?? 0
        let ema20 = MA.ema(c, 20).last ?? 0
        let ema50 = MA.ema(c, 50).last ?? 0
        let sma200 = MA.sma(c, 200).last ?? 0
        let hv = Indicators.historicalVolatility(c).last ?? 0
        let cmf = Indicators.cmf(h, l, c, v).last ?? 0
        let roc = Indicators.roc(c).last ?? 0

        // Pre-compute scalars so no interpolation carries a heavy expression.
        let macdL = macdLine.last ?? 0
        let macdS = macdSignal.last ?? 0
        let macdH = macdHist.last ?? 0
        let adx = adxArr.last ?? 0
        let pDI = pDIArr.last ?? 0
        let mDI = mDIArr.last ?? 0
        let bbU = bbUArr.last ?? 0
        let bbM = bbMArr.last ?? 0
        let bbL = bbLArr.last ?? 0
        let stK = stKArr.last ?? 50
        let stD = stDArr.last ?? 50
        let stLine = stLineArr.last ?? 0
        let stUp = stUpArr.last ?? true
        let atrPct = md.currentPrice > 0 ? atr / md.currentPrice * 100 : 0
        let bbWidth = bbM > 0 ? (bbU - bbL) / bbM * 100 : 0
        let rsiRead = rsi > 70 ? "overbought" : (rsi < 30 ? "oversold" : "neutral")
        let stochRead = stK > 80 ? "overbought" : (stK < 20 ? "oversold" : "neutral")
        let cciRead = cci > 100 ? "strong up" : (cci < -100 ? "strong down" : "range")
        let wrRead = wr > -20 ? "overbought" : (wr < -80 ? "oversold" : "neutral")
        let emaRead = ema20 > ema50 ? "bullish" : (ema20 < ema50 ? "bearish" : "flat")

        var rows: [String] = ["| Indicator | Value | Read |", "|---|---|---|"]
        rows.append("| RSI(14) | \(fmt2(rsi)) | \(rsiRead) |")
        rows.append("| MACD | \(fmt2(macdL)) / sig \(fmt2(macdS)) | hist \(fmt2(macdH)) \(macdH > 0 ? "↑" : "↓") |")
        rows.append("| ADX(14) | \(fmt2(adx)) | +DI \(fmt2(pDI)) / −DI \(fmt2(mDI)) |")
        rows.append("| ATR(14) | \(fmtPrice(atr)) | \(fmt2(atrPct))% of price |")
        rows.append("| Bollinger | \(fmtPrice(bbL)) – \(fmtPrice(bbM)) – \(fmtPrice(bbU)) | width \(fmt2(bbWidth))% |")
        rows.append("| Stochastic | %K \(fmt2(stK)) / %D \(fmt2(stD)) | \(stochRead) |")
        rows.append("| CCI(20) | \(fmt2(cci)) | \(cciRead) |")
        rows.append("| Williams %R | \(fmt2(wr)) | \(wrRead) |")
        rows.append("| MFI(14) | \(fmt2(mfi)) | money flow \(mfi > 50 ? "positive" : "negative") |")
        rows.append("| Supertrend | \(fmtPrice(stLine)) | \(stUp ? "UP trend" : "DOWN trend") |")
        rows.append("| VWAP | \(fmtPrice(vwap)) | price \(md.currentPrice >= vwap ? "above" : "below") VWAP |")
        rows.append("| EMA 20/50 | \(fmtPrice(ema20)) / \(fmtPrice(ema50)) | \(emaRead) |")
        if last >= 199 { rows.append("| SMA 200 | \(fmtPrice(sma200)) | price \(md.currentPrice >= sma200 ? "above" : "below") |") }
        rows.append("| Hist. Vol(20) | \(fmt2(hv)) | log-return σ ×100 |")
        rows.append("| CMF(20) | \(String(format: "%.3f", cmf)) | \(cmf > 0 ? "accumulation" : "distribution") |")
        rows.append("| ROC(12) | \(fmt2(roc))% | momentum |")

        return """
        ## Indicator Snapshot — \(name) \(md.timeframe.rawValue)
        Price: `\(fmtPrice(md.currentPrice))` · Candles: \(md.candles.count)

        \(rows.joined(separator: "\n"))
        """
    }

    // MARK: - divergence_scan

    /// Detects regular + hidden divergences between price and RSI / MACD / OBV.
    func divergenceScan(_ args: [String: Any]) -> String {
        guard let (md, name) = requireMarketData(args) else { return needCandlesMessage }
        let c = md.closes
        let requested = str(args, "indicator").lowercased()

        var sources: [(String, [Double])] = []
        if requested.isEmpty || requested == "rsi" { sources.append(("RSI(14)", Indicators.rsi(c))) }
        if requested.isEmpty || requested == "macd" { sources.append(("MACD hist", Indicators.macd(c).histogram)) }
        if requested.isEmpty || requested == "obv" { sources.append(("OBV", Indicators.obv(c, md.volumes))) }
        guard !sources.isEmpty else { return "Supported indicators: rsi, macd, obv (or omit for all)." }

        var out = ["## Divergence Scan — \(name) \(md.timeframe.rawValue)"]
        var found = 0
        for (label, series) in sources {
            let divs = DivergenceEngine.detect(price: c, indicator: series)
            let recent = divs.filter { $0.at >= c.count - 40 }
            guard !recent.isEmpty else { continue }
            out.append("\n### \(label)")
            for d in recent.suffix(6) {
                let age = c.count - 1 - d.at
                let kind = d.type.isHidden ? "Hidden" : "Regular"
                let dir = d.type.isBullish ? "bullish 🟢" : "bearish 🔴"
                out.append("- \(kind) \(dir) at `\(fmtPrice(d.price))` (\(age) bars ago)")
                found += 1
            }
        }
        if found == 0 { out.append("\nNo divergences detected in the last 40 bars — price and momentum agree.") }
        else { out.append("\n*Regular divergences hint at reversal; hidden divergences hint at trend continuation.*") }
        return out.joined(separator: "\n")
    }

    // MARK: - spike_scan

    /// Price-spike and volatility-spike detection over recent bars.
    func spikeScan(_ args: [String: Any]) -> String {
        guard let (md, name) = requireMarketData(args) else { return needCandlesMessage }
        let o = md.opens, h = md.highs, l = md.lows, c = md.closes
        let priceSpikes = Spike.price(open: o, high: h, low: l, close: c)
        let volSpikes = Spike.volatility(high: h, low: l, close: c)

        let window = 30
        let start = max(0, c.count - window)
        var lines = ["## Spike Scan — \(name) \(md.timeframe.rawValue) (last \(c.count - start) bars)"]
        var hits = 0
        for i in start..<c.count {
            if priceSpikes[i].spike {
                lines.append("- Bar −\(c.count - 1 - i): **price spike** \(priceSpikes[i].up ? "up 🟢" : "down 🔴") — range \(fmt2(priceSpikes[i].strength))× average")
                hits += 1
            }
            if volSpikes[i].spike {
                lines.append("- Bar −\(c.count - 1 - i): **volatility spike** — ATR \(fmt2(volSpikes[i].ratio))× its 50-bar average")
                hits += 1
            }
        }
        if hits == 0 { lines.append("No price or volatility spikes in the window — conditions are calm.") }
        let latest = volSpikes.last
        lines.append("\nCurrent ATR ratio: \(fmt2(latest?.ratio ?? 0))× (spike threshold 2.0×).")
        return lines.joined(separator: "\n")
    }

    // MARK: - fib_levels

    /// Fibonacci retracements + extensions from the swing high/low of the recent window
    /// (or explicit high/low args).
    func fibLevels(_ args: [String: Any]) -> String {
        var high = dbl(args, "high") ?? 0
        var low = dbl(args, "low") ?? 0
        var name = "custom range"
        var isUpLeg = (str(args, "direction").lowercased() != "down")
        var priceNote = ""

        if high <= 0 || low <= 0 || high <= low {
            guard let (md, dispName) = requireMarketData(args) else {
                return "Provide high+low (and optional direction up|down), or a symbol with cached candles."
            }
            let lookback = min(max(intArg(args, "lookback") ?? 100, 10), md.candles.count)
            let slice = md.candles.suffix(lookback)
            guard let hi = slice.map({ $0.high }).max(), let lo = slice.map({ $0.low }).min(), hi > lo else {
                return "Could not derive a swing range from cached candles."
            }
            high = hi; low = lo; name = "\(dispName) \(md.timeframe.rawValue) (last \(lookback) bars)"
            let hiIdx = slice.lastIndex(where: { $0.high >= hi }) ?? slice.startIndex
            let loIdx = slice.lastIndex(where: { $0.low <= lo }) ?? slice.startIndex
            isUpLeg = loIdx < hiIdx
            priceNote = " · price `\(fmtPrice(md.currentPrice))`"
        }

        let fib = MarketMath.fibonacci(high: high, low: low, isUpLeg: isUpLeg)
        var rows = ["| Level | Price |", "|---|---|"]
        rows.append("| \(isUpLeg ? "Swing high (0%)" : "Swing low (0%)") | \(fmtPrice(isUpLeg ? high : low)) |")
        for r in fib.retracements { rows.append("| Retrace \(fmt2(r.ratio * 100))% | \(fmtPrice(r.price)) |") }
        rows.append("| \(isUpLeg ? "Swing low (100%)" : "Swing high (100%)") | \(fmtPrice(isUpLeg ? low : high)) |")
        for e in fib.extensions { rows.append("| Extension \(fmt2(e.ratio * 100))% | \(fmtPrice(e.price)) |") }
        return """
        ## Fibonacci Levels — \(name)
        Leg: **\(isUpLeg ? "UP" : "DOWN")** · High `\(fmtPrice(high))` · Low `\(fmtPrice(low))`\(priceNote)

        \(rows.joined(separator: "\n"))
        """
    }

    // MARK: - pivot_levels

    /// Classic, Woodie, or Camarilla pivots from the previous completed candle.
    func pivotLevels(_ args: [String: Any]) -> String {
        guard let (md, name) = requireMarketData(args) else { return needCandlesMessage }
        guard md.candles.count >= 2 else { return needCandlesMessage }
        let prev = md.candles[md.candles.count - 2]
        let method = str(args, "method").lowercased()

        let set: MarketMath.PivotSet
        let label: String
        switch method {
        case "woodie":    set = MarketMath.woodiePivots(high: prev.high, low: prev.low, close: prev.close); label = "Woodie"
        case "camarilla": set = MarketMath.camarillaPivots(high: prev.high, low: prev.low, close: prev.close); label = "Camarilla"
        default:          set = MarketMath.classicPivots(high: prev.high, low: prev.low, close: prev.close); label = "Classic"
        }

        let p = md.currentPrice
        func mark(_ level: Double) -> String { p >= level ? "below price" : "above price" }
        return """
        ## \(label) Pivots — \(name) \(md.timeframe.rawValue)
        Based on previous candle H `\(fmtPrice(prev.high))` / L `\(fmtPrice(prev.low))` / C `\(fmtPrice(prev.close))` · price `\(fmtPrice(p))`

        | Level | Price | Position |
        |---|---|---|
        | R3 | \(fmtPrice(set.r3)) | \(mark(set.r3)) |
        | R2 | \(fmtPrice(set.r2)) | \(mark(set.r2)) |
        | R1 | \(fmtPrice(set.r1)) | \(mark(set.r1)) |
        | **Pivot** | **\(fmtPrice(set.pivot))** | \(mark(set.pivot)) |
        | S1 | \(fmtPrice(set.s1)) | \(mark(set.s1)) |
        | S2 | \(fmtPrice(set.s2)) | \(mark(set.s2)) |
        | S3 | \(fmtPrice(set.s3)) | \(mark(set.s3)) |
        """
    }

    // MARK: - streak_stats

    /// Up/down streak statistics and continuation probabilities.
    func streakStats(_ args: [String: Any]) -> String {
        guard let (md, name) = requireMarketData(args) else { return needCandlesMessage }
        let s = MarketMath.streaks(closes: md.closes)
        let cur = s.currentStreak
        let curLabel = cur > 0 ? "\(cur) up bars 🟢" : cur < 0 ? "\(-cur) down bars 🔴" : "flat"
        let total = s.upBars + s.downBars
        let upPct = total > 0 ? Double(s.upBars) / Double(total) * 100 : 0
        return """
        ## Streak Statistics — \(name) \(md.timeframe.rawValue) (\(md.candles.count) candles)

        - **Current streak:** \(curLabel)
        - **Longest up streak:** \(s.maxUpStreak) bars · **Longest down streak:** \(s.maxDownStreak) bars
        - **Up-bar share:** \(fmt2(upPct))% (\(s.upBars) up / \(s.downBars) down)
        - **P(up | previous up):** \(fmt2(s.upAfterUp * 100))% — \(s.upAfterUp > 0.55 ? "momentum persists" : s.upAfterUp < 0.45 ? "mean-reverting" : "near random")
        - **P(up | previous down):** \(fmt2(s.upAfterDown * 100))%

        *Persistence > 55% favors trend-following; < 45% favors fading moves.*
        """
    }

    // MARK: - risk_reward

    /// R:R geometry check + optional position sizing from account size and risk %.
    func riskRewardTool(_ args: [String: Any]) -> String {
        guard let entry = dbl(args, "entry"), let stop = dbl(args, "stop"), let target = dbl(args, "target") else {
            return "Required: entry, stop, target. Optional: account_size, risk_percent."
        }
        guard let rr = MarketMath.riskReward(entry: entry, stop: stop, target: target) else {
            return "Invalid geometry: for a long, stop < entry < target; for a short, target < entry < stop."
        }
        var out = """
        ## Risk / Reward
        - **Direction:** \(rr.isLong ? "LONG 🟢" : "SHORT 🔴")
        - **Risk per unit:** `\(fmtPrice(rr.riskPerUnit))` · **Reward per unit:** `\(fmtPrice(rr.rewardPerUnit))`
        - **R:R ratio:** **1 : \(fmt2(rr.ratio))** \(rr.ratio >= 2 ? "✅ (≥ 1:2)" : rr.ratio >= 1 ? "⚠️ (thin edge)" : "❌ (risk exceeds reward)")
        - **Breakeven win rate:** \(fmt2(rr.breakevenWinRate * 100))%
        """
        if let acct = dbl(args, "account_size"), acct > 0 {
            let riskPct = min(max(dbl(args, "risk_percent") ?? 1.0, 0.1), 10)
            let riskAmount = acct * riskPct / 100
            let units = riskAmount / rr.riskPerUnit
            out += """

            - **Account:** \(fmt2(acct)) · risking \(fmt2(riskPct))% = **\(fmt2(riskAmount))**
            - **Position size:** \(String(format: "%.4f", units)) units · potential profit **\(fmt2(units * rr.rewardPerUnit))**
            """
        }
        return out
    }

    // MARK: - kelly_size

    /// Kelly criterion stake sizing from win rate and payoff ratio.
    func kellySize(_ args: [String: Any]) -> String {
        guard var winRate = dbl(args, "win_rate"), let payoff = dbl(args, "payoff"), payoff > 0 else {
            return "Required: win_rate (e.g. 55 or 0.55), payoff (avg win ÷ avg loss). Optional: account_size."
        }
        if winRate > 1 { winRate /= 100 }
        guard winRate > 0, winRate < 1 else { return "win_rate must be between 0 and 100% (exclusive)." }
        let kelly = MarketMath.kellyFraction(winRate: winRate, payoff: payoff)
        let expectancyR = MarketMath.expectancy(winRate: winRate, avgWin: payoff, avgLoss: 1)
        var out = """
        ## Kelly Sizing
        - **Win rate:** \(fmt2(winRate * 100))% · **Payoff ratio:** \(fmt2(payoff))
        - **Expectancy:** \(String(format: "%+.3f", expectancyR))R per trade \(expectancyR > 0 ? "🟢" : "🔴")
        - **Full Kelly:** \(fmt2(kelly * 100))% of bankroll
        - **Half Kelly (recommended):** \(fmt2(kelly * 50))% · **Quarter Kelly:** \(fmt2(kelly * 25))%
        """
        if kelly == 0 { out += "\n\n⚠️ **No positive edge at these parameters — Kelly says do not bet.**" }
        if let acct = dbl(args, "account_size"), acct > 0, kelly > 0 {
            out += "\n\nOn a \(fmt2(acct)) account: full \(fmt2(acct * kelly)) · half \(fmt2(acct * kelly / 2)) · quarter \(fmt2(acct * kelly / 4))."
        }
        return out
    }

    // MARK: - session_clock

    /// Current trading-session status and per-asset-class scan policy.
    func sessionClock() -> String {
        let now = Date()
        let hour = TradingSession.sastHour(now)
        let overnight = TradingSession.isAfterHours(now)
        var rows = ["| Asset class | Cadence | Min confidence | Base TF | Mode |", "|---|---|---|---|---|"]
        for asset in AssetClass.allCases {
            let p = TradingSession.policy(for: asset, date: now)
            rows.append("| \(asset.rawValue) | every \(p.scanSeconds)s | \(Int(p.minConfidence))% | \(p.baseTimeframe.rawValue) | \(p.aggressive ? "aggressive 🔥" : "selective") |")
        }
        let df = DateFormatter()
        df.dateFormat = "HH:mm"
        df.timeZone = TradingSession.sast
        return """
        ## Session Clock
        - **SAST time:** \(df.string(from: now)) (hour \(hour))
        - **Session:** \(TradingSession.label(now))
        - **Overnight window (23:00–05:00 SAST):** \(overnight ? "ACTIVE — FX/crypto scanned aggressively" : "inactive")

        \(rows.joined(separator: "\n"))
        """
    }

    // MARK: - Watchlist management

    func watchlistShow() -> String {
        let list = app.settings.watchlist
        guard !list.isEmpty else { return "Watchlist is empty. Use watchlist_add(symbols) to add instruments." }
        var rows = ["| Instrument | Symbol | Live price |", "|---|---|---|"]
        for sym in list {
            let p = app.deriv.prices[sym] ?? app.deriv.priceCache[sym]?.prices.last
            rows.append("| \(DerivSymbols.display(sym)) | `\(sym)` | \(p.map { fmtPrice($0) } ?? "—") |")
        }
        return "## Watchlist (\(list.count))\n\n" + rows.joined(separator: "\n")
    }

    func watchlistAdd(_ args: [String: Any]) -> String {
        let raw = str(args, "symbols").isEmpty ? str(args, "symbol") : str(args, "symbols")
        let requested = raw.split(separator: ",").map { resolveSymbol(String($0).trimmingCharacters(in: .whitespaces)) }
        let valid = requested.filter { DerivSymbols.all.contains($0) }
        guard !valid.isEmpty else { return "No valid symbols in '\(raw)'. Use instruments(query) to look up symbols." }
        var list = app.settings.watchlist
        let added = valid.filter { !list.contains($0) }
        list.append(contentsOf: added)
        app.settings.watchlist = list
        let skipped = requested.filter { !DerivSymbols.all.contains($0) }
        var msg = added.isEmpty ? "All requested symbols were already on the watchlist."
            : "Added: \(added.map { DerivSymbols.display($0) }.joined(separator: ", ")). Watchlist now has \(list.count) instruments."
        if !skipped.isEmpty { msg += " Unrecognized: \(skipped.joined(separator: ", "))." }
        return msg
    }

    func watchlistRemove(_ args: [String: Any]) -> String {
        let raw = str(args, "symbols").isEmpty ? str(args, "symbol") : str(args, "symbols")
        let requested = raw.split(separator: ",").map { resolveSymbol(String($0).trimmingCharacters(in: .whitespaces)) }
        guard !requested.isEmpty else { return "Specify symbols to remove, e.g. watchlist_remove(symbols:\"R_100,frxEURUSD\")." }
        var list = app.settings.watchlist
        let before = list.count
        list.removeAll { requested.contains($0) }
        app.settings.watchlist = list
        let removed = before - list.count
        return removed == 0 ? "None of those symbols were on the watchlist."
            : "Removed \(removed) instrument(s). Watchlist now has \(list.count)."
    }

    // MARK: - volatility_rank

    /// Ranks symbols (default: watchlist) by ATR% — helps pick the most active market.
    func volatilityRank(_ args: [String: Any]) -> String {
        let raw = str(args, "symbols")
        let symbols = raw.isEmpty
            ? app.settings.watchlist
            : raw.split(separator: ",").map { resolveSymbol(String($0).trimmingCharacters(in: .whitespaces)) }
        let timeframe = resolveTF(str(args, "timeframe"))

        var scored: [(String, Double, Double)] = []   // (symbol, atrPct, hv)
        for sym in symbols {
            guard let md = marketData(for: sym, timeframe: timeframe) else { continue }
            let atr = Indicators.atr(md.highs, md.lows, md.closes).last ?? 0
            let hv = Indicators.historicalVolatility(md.closes).last ?? 0
            guard md.currentPrice > 0 else { continue }
            scored.append((sym, atr / md.currentPrice * 100, hv))
        }
        guard !scored.isEmpty else {
            return "No cached candles for any of those symbols. Open charts (or run analyze) first, then retry."
        }
        scored.sort { $0.1 > $1.1 }
        var rows = ["| # | Instrument | ATR % | Hist. Vol |", "|---|---|---|---|"]
        for (i, s) in scored.enumerated() {
            rows.append("| \(i + 1) | \(DerivSymbols.display(s.0)) | \(String(format: "%.3f", s.1))% | \(fmt2(s.2)) |")
        }
        return """
        ## Volatility Ranking — \(timeframe.rawValue) (\(scored.count) of \(symbols.count) symbols cached)

        \(rows.joined(separator: "\n"))

        *Higher ATR% = larger average bar range relative to price — more movement to trade, and more risk.*
        """
    }

    // MARK: - candle_anatomy

    /// Table of the last N candles with body/wick breakdown — great for reading price action.
    func candleAnatomy(_ args: [String: Any]) -> String {
        guard let (md, name) = requireMarketData(args) else { return needCandlesMessage }
        let count = min(max(intArg(args, "count") ?? 10, 3), 30)
        let slice = md.candles.suffix(count)
        let df = DateFormatter()
        df.dateFormat = "HH:mm"
        var rows = ["| Time | O | H | L | C | Dir | Body % | Upper wick % | Lower wick % |", "|---|---|---|---|---|---|---|---|---|"]
        for candle in slice {
            let range = candle.range
            let bodyPct = range > 0 ? candle.body / range * 100 : 0
            let upperWick = range > 0 ? (candle.high - max(candle.open, candle.close)) / range * 100 : 0
            let lowerWick = range > 0 ? (min(candle.open, candle.close) - candle.low) / range * 100 : 0
            let dir = candle.isBullish ? "🟢" : (candle.isBearish ? "🔴" : "⚪️")
            let time = df.string(from: candle.timestamp)
            rows.append("| \(time) | \(fmtPrice(candle.open)) | \(fmtPrice(candle.high)) | \(fmtPrice(candle.low)) | \(fmtPrice(candle.close)) | \(dir) | \(fmt2(bodyPct)) | \(fmt2(upperWick)) | \(fmt2(lowerWick)) |")
        }
        let bulls = slice.filter { $0.isBullish }.count
        return """
        ## Candle Anatomy — \(name) \(md.timeframe.rawValue) (last \(slice.count) candles)

        \(rows.joined(separator: "\n"))

        Bullish \(bulls) / bearish \(slice.count - bulls). Small bodies + long wicks = indecision or rejection; big bodies = conviction.
        """
    }
}
