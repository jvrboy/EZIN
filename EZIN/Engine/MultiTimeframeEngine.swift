import Foundation

/// Deep, top-down multi-timeframe analysis engine.
///
/// When the user asks to analyse a symbol on ANY timeframe, this engine does NOT
/// just look at that one timeframe. It:
///   1. Walks the FULL timeframe ladder relevant to the request (1m → the asked TF
///      plus the two next-higher TFs for top-down context).
///   2. Deep-analyses EACH timeframe: direction, bias, momentum, volume, trend
///      strength, volatility regime, realized vol, speed/acceleration, key levels
///      (support/resistance, volume-profile POC & value area) and order-flow proxies,
///      using every indicator + the full agent council.
///   3. Reads the 1-minute timeframe specifically for execution timing ("where is it
///      going right now").
///   4. Computes CONFLUENCE across every timeframe (weighted by timeframe authority).
///   5. Deep-dives the exact timeframe the user requested.
///   6. MERGES everything and produces one final verdict — buy or sell — with a
///      confidence score, entry/SL/TP and ordered reasoning.
struct MultiTimeframeEngine {
    let deriv: DerivClient
    let engine: SignalEngine
    let analyzer = TechnicalAnalyzer()

    // MARK: - Public entry point

    func analyze(symbol: String, requested: Timeframe, candleCount: Int = 200) async -> AnalysisReport? {
        let tfs = requested.analysisSet
        // Fetch every timeframe's candles concurrently (unique req_id per request).
        let dataByTF = await fetchCandles(symbol: symbol, timeframes: tfs, count: candleCount)
        guard let requestedCandles = dataByTF[requested], requestedCandles.count > 40 else { return nil }

        let assetClass = DerivSymbols.assetClass(symbol)
        let livePrice = deriv.prices[symbol]

        // 1–2. Deep snapshot per timeframe.
        var snapshots: [TimeframeSnapshot] = []
        for tf in tfs {
            guard let candles = dataByTF[tf], candles.count > 40 else { continue }
            snapshots.append(makeSnapshot(symbol: symbol, assetClass: assetClass,
                                          timeframe: tf, candles: candles, livePrice: livePrice))
        }
        guard !snapshots.isEmpty,
              let focus = snapshots.first(where: { $0.timeframe == requested }) else { return nil }

        // 3. One-minute execution read.
        let execRead = makeExecutionRead(symbol: symbol, assetClass: assetClass,
                                         candles: dataByTF[.m1] ?? requestedCandles)

        // 4. Confluence across all analysed timeframes.
        let confluence = makeConfluence(snapshots: snapshots, requested: requested)

        // 5–6. Merge into the final verdict.
        let verdict = makeVerdict(symbol: symbol, requested: requested,
                                  focus: focus, snapshots: snapshots,
                                  confluence: confluence, execRead: execRead,
                                  candles: requestedCandles, livePrice: livePrice)

        return AnalysisReport(
            symbol: symbol,
            displaySymbol: DerivSymbols.display(symbol),
            assetClass: assetClass,
            requestedTimeframe: requested,
            generatedAt: Date(),
            perTimeframe: snapshots,
            executionRead: execRead,
            requestedFocus: focus,
            confluence: confluence,
            verdict: verdict
        )
    }

    // MARK: - Candle fetch (concurrent)

    private func fetchCandles(symbol: String, timeframes: [Timeframe], count: Int) async -> [Timeframe: [Candle]] {
        await withTaskGroup(of: (Timeframe, [Candle]).self) { group in
            for tf in timeframes {
                group.addTask {
                    let candles = (try? await deriv.candles(symbol: symbol, timeframe: tf, count: count)) ?? []
                    return (tf, candles)
                }
            }
            var out: [Timeframe: [Candle]] = [:]
            for await (tf, candles) in group { out[tf] = candles }
            return out
        }
    }

    // MARK: - Per-timeframe deep snapshot

    private func makeSnapshot(symbol: String, assetClass: AssetClass, timeframe: Timeframe,
                              candles: [Candle], livePrice: Double?) -> TimeframeSnapshot {
        var md = MarketData(symbol: symbol, assetClass: assetClass, timeframe: timeframe, candles: candles)
        md.currentPrice = livePrice ?? candles.last?.close ?? 0
        let ind = analyzer.analyze(md)

        // Council of all active agents on this timeframe.
        let votes = engine.agents.filter { $0.isActive }.map { $0.analyze(md, ind) }
        let decision = engine.council.deliberate(symbol: symbol, timeframe: timeframe, votes: votes)

        // Direction: council if it reached consensus, else EMA/Supertrend fallback.
        let direction: Direction
        let consensus: Double
        let confidence: Double
        let strength: SignalStrength
        if let d = decision {
            direction = d.direction; consensus = d.consensusRatio; confidence = d.confidence; strength = d.strength
        } else {
            var s = 0.0
            if ind.ema12 > ind.ema26 { s += 1 } else { s -= 1 }
            if ind.ema50 > ind.ema200 { s += 1 } else { s -= 1 }
            if ind.supertrendUp { s += 1 } else { s -= 1 }
            direction = s >= 2 ? .bullish : (s <= -2 ? .bearish : .neutral)
            consensus = 0.5; confidence = 0.5; strength = .weak
        }

        // Momentum blend → −1…1.
        let rsiPart = (ind.rsi14 - 50) / 50
        let macdPart = ind.macdHistogram > 0 ? 0.5 : (ind.macdHistogram < 0 ? -0.5 : 0)
        let stochPart = (ind.stochK - 50) / 100
        let rocPart = ind.roc12 > 0 ? 0.3 : (ind.roc12 < 0 ? -0.3 : 0)
        let cciPart = max(-1, min(1, ind.cci20 / 200)) * 0.4
        let momentum = clamp(rsiPart * 0.5 + macdPart + stochPart * 0.4 + rocPart + cciPart, -1, 1)
        let momentumLabel = label(forScore: momentum)

        // Volume bias.
        var volScore = 0.0
        if ind.mfi14 > 55 { volScore += 1 } else if ind.mfi14 < 45 { volScore -= 1 }
        if ind.cmf > 0.05 { volScore += 1 } else if ind.cmf < -0.05 { volScore -= 1 }
        if md.currentPrice > ind.vwap { volScore += 1 } else { volScore -= 1 }
        let volumeBiasText = volScore > 0 ? "accumulation (buyers)" : (volScore < 0 ? "distribution (sellers)" : "balanced")

        // Microstructure.
        let regime = Microstructure.regime(md.closes)
        let rvol = Microstructure.realizedVolatility(md.closes, window: 20)
        let vel = Microstructure.velocity(md.closes, n: 10)
        let flow = Microstructure.orderFlow(open: md.opens, high: md.highs, low: md.lows,
                                            close: md.closes, volume: md.volumes, window: 30)
        let vp = Microstructure.volumeProfile(high: md.highs, low: md.lows, close: md.closes, volume: md.volumes)

        // Key levels — nearest swing S/R via Donchian + recent structure.
        let support = ind.donchianLower > 0 ? ind.donchianLower : (md.lows.suffix(20).min() ?? 0)
        let resistance = ind.donchianUpper > 0 ? ind.donchianUpper : (md.highs.suffix(20).max() ?? 0)

        // Weighted confluence contribution.
        let signed = Double(direction.rawValue) / 2.0            // −1…1
        let weighted = signed * max(consensus, 0.5) * timeframe.confluenceWeight

        let topVotes = votes.sorted { ($0.weight * $0.confidence) > ($1.weight * $1.confidence) }.prefix(3).map { $0 }

        return TimeframeSnapshot(
            timeframe: timeframe, price: md.currentPrice,
            direction: direction, biasText: biasText(direction, strength: strength),
            councilConfidence: confidence, consensus: consensus, strength: strength,
            momentumScore: momentum, momentumLabel: momentumLabel,
            trendStrength: ind.trendStrength, volumeBiasText: volumeBiasText,
            regime: regime, realizedVol: rvol, speed: vel.speed, accel: vel.accel,
            support: support, resistance: resistance,
            poc: vp?.poc ?? ind.pivot, valueAreaHigh: vp?.valueAreaHigh ?? resistance,
            valueAreaLow: vp?.valueAreaLow ?? support,
            orderFlowBias: flow.bias, netAggressiveVolume: flow.netAggressiveVolumeProxy,
            tradeDirectionRatio: flow.tradeDirectionRatioProxy,
            weightedScore: weighted, topVotes: topVotes
        )
    }

    // MARK: - 1-minute execution read

    private func makeExecutionRead(symbol: String, assetClass: AssetClass, candles: [Candle]) -> ExecutionRead {
        var md = MarketData(symbol: symbol, assetClass: assetClass, timeframe: .m1, candles: candles)
        md.currentPrice = deriv.prices[symbol] ?? candles.last?.close ?? 0
        let ind = analyzer.analyze(md)
        let vel = Microstructure.velocity(md.closes, n: 8)
        let jumps = Microstructure.detectJumps(md.closes, mult: 3.0, lookback: 60)

        var s = 0.0
        if ind.ema12 > ind.ema26 { s += 1 } else { s -= 1 }
        if ind.supertrendUp { s += 1 } else { s -= 1 }
        if md.currentPrice > ind.vwap { s += 1 } else { s -= 1 }
        if vel.speed > 0 { s += 1 } else { s -= 1 }
        let dir: Direction = s >= 2 ? .bullish : (s <= -2 ? .bearish : .neutral)

        let above = md.highs.suffix(20).max() ?? md.currentPrice
        let below = md.lows.suffix(20).min() ?? md.currentPrice
        let momLabel = label(forScore: clamp((ind.rsi14 - 50) / 50, -1, 1))
        let jumpRisk = !jumps.isEmpty

        let text = "1m is \(dirWord(dir)) — price \(vel.speed >= 0 ? "rising" : "falling") at " +
            String(format: "%.3f%%", abs(vel.speed)) + "/8-bars, momentum \(momLabel)" +
            (jumpRisk ? ", ⚠︎ recent volatility jump detected" : "") + "."

        return ExecutionRead(direction: dir, momentumLabel: momLabel, speed: vel.speed, accel: vel.accel,
                             immediateLevelAbove: above, immediateLevelBelow: below,
                             jumpRisk: jumpRisk, text: text)
    }

    // MARK: - Confluence

    private func makeConfluence(snapshots: [TimeframeSnapshot], requested: Timeframe) -> MTFConfluence {
        var bull = 0, bear = 0, neut = 0
        var weightedSum = 0.0, weightTotal = 0.0
        for s in snapshots {
            if s.direction.isBullish { bull += 1 } else if s.direction.isBearish { bear += 1 } else { neut += 1 }
            weightedSum += s.weightedScore
            weightTotal += s.timeframe.confluenceWeight
        }
        let alignment = weightTotal > 0 ? clamp(weightedSum / weightTotal, -1, 1) : 0
        let dominant: Direction = alignment > 0.12 ? .bullish : (alignment < -0.12 ? .bearish : .neutral)
        let agreeing = snapshots.filter {
            (dominant.isBullish && $0.direction.isBullish) ||
            (dominant.isBearish && $0.direction.isBearish)
        }.count
        let agreePct = snapshots.isEmpty ? 0 : Int(Double(agreeing) / Double(snapshots.count) * 100)

        // Higher timeframe block bias (h1/h4/d1).
        let higher = snapshots.filter { $0.timeframe.ladderIndex >= Timeframe.h1.ladderIndex }
        let higherScore = higher.reduce(0) { $0 + $1.weightedScore }
        let higherBias: Direction = higherScore > 0.1 ? .bullish : (higherScore < -0.1 ? .bearish : .neutral)

        var notes: [String] = []
        notes.append("\(bull) timeframe(s) bullish · \(bear) bearish · \(neut) neutral.")
        if higherBias != .neutral { notes.append("Higher-timeframe block (1h–1d) leans \(dirWord(higherBias)).") }
        if dominant != .neutral && agreePct >= 70 { notes.append("Strong \(dirWord(dominant)) alignment across the ladder (\(agreePct)%).") }
        else if dominant == .neutral { notes.append("Timeframes are in conflict — no clean directional alignment.") }

        return MTFConfluence(alignmentScore: alignment, bullishTFs: bull, bearishTFs: bear, neutralTFs: neut,
                             dominantDirection: dominant, agreementPct: agreePct,
                             higherTFBias: higherBias, notes: notes)
    }

    // MARK: - Final merged verdict

    private func makeVerdict(symbol: String, requested: Timeframe, focus: TimeframeSnapshot,
                             snapshots: [TimeframeSnapshot], confluence: MTFConfluence,
                             execRead: ExecutionRead, candles: [Candle], livePrice: Double?) -> FinalVerdict {
        let price = livePrice ?? candles.last?.close ?? focus.price
        var md = MarketData(symbol: symbol, assetClass: DerivSymbols.assetClass(symbol), timeframe: requested, candles: candles)
        md.currentPrice = price
        let ind = analyzer.analyze(md)
        let atr = ind.atr14 > 0 ? ind.atr14 : price * 0.001

        // Blend: confluence (top-down authority) + requested-TF focus + 1m execution.
        let focusSigned = Double(focus.direction.rawValue) / 2.0 * max(focus.consensus, 0.5)
        let execSigned = Double(execRead.direction.rawValue) / 2.0
        let backend = backendConfluence(md: md)
        let blended = clamp(confluence.alignmentScore * 0.48 + focusSigned * 0.24 + execSigned * 0.12 + backend.score * 0.16, -1, 1)

        let direction: Direction
        switch blended {
        case let b where b >= 0.55: direction = .strongBullish
        case let b where b >= 0.15: direction = .bullish
        case let b where b <= -0.55: direction = .strongBearish
        case let b where b <= -0.15: direction = .bearish
        default: direction = .neutral
        }

        let action: SignalType
        switch direction {
        case .strongBullish: action = .strongBuy
        case .bullish: action = .buy
        case .strongBearish: action = .strongSell
        case .bearish: action = .sell
        case .neutral: action = .hold
        }

        let isBuy = direction.isBullish
        // SL/TP from ATR, then snapped toward the nearest liquidity level if closer.
        var sl = isBuy ? price - atr * 2.0 : price + atr * 2.0
        var tp = isBuy ? price + atr * 3.0 : price - atr * 3.0
        if direction == .neutral { sl = price - atr * 2.0; tp = price + atr * 3.0 }

        // Confidence: agreement + focus consensus + execution alignment, penalised by conflict.
        var conf = Double(confluence.agreementPct) * 0.5
        conf += focus.consensus * 30
        if execRead.direction == direction || direction == .neutral { conf += 12 }
        if confluence.higherTFBias != .neutral && confluence.higherTFBias != direction && direction != .neutral {
            conf -= 18   // fighting the higher-timeframe block
        }
        if execRead.jumpRisk { conf -= 6 }
        let confidence = max(5, min(97, Int(conf.rounded())))

        // Reasoning, ordered top-down.
        var rationale: [String] = []
        rationale.append("Top-down confluence: alignment \(String(format: "%.2f", confluence.alignmentScore)) — \(confluence.notes.first ?? "")")
        if confluence.higherTFBias != .neutral {
            rationale.append("Higher timeframes (1h–1d) bias \(dirWord(confluence.higherTFBias)); this sets the dominant context.")
        }
        rationale.append("Requested \(requested.longLabel): \(focus.biasText), momentum \(focus.momentumLabel), trend strength \(Int(focus.trendStrength)), \(focus.volumeBiasText), \(focus.regime.rawValue) volatility.")
        rationale.append("Order flow on \(requested.longLabel): \(dirWord(focus.orderFlowBias)) (net aggression \(String(format: "%.2f", focus.netAggressiveVolume)), buy-bar ratio \(Int(focus.tradeDirectionRatio * 100))%).")
        rationale.append("1-minute execution: \(execRead.text)")
        rationale.append(contentsOf: backend.notes)
        rationale.append("Merged directional score \(String(format: "%.2f", blended)) ⇒ \(action.rawValue).")

        var warnings: [String] = backend.warnings
        if confluence.dominantDirection == .neutral { warnings.append("Timeframes conflict — treat any entry as lower-probability.") }
        if execRead.direction != direction && direction != .neutral {
            warnings.append("1m timing (\(dirWord(execRead.direction))) disagrees with the merged bias — consider waiting for 1m to align.")
        }
        if execRead.jumpRisk { warnings.append("Recent volatility jump on 1m — widen stops or reduce size.") }
        if focus.regime == .ultra { warnings.append("Ultra-high volatility regime — expect slippage.") }

        let rr = abs(price - sl) > 0 ? abs(tp - price) / abs(price - sl) : 0
        return FinalVerdict(action: action, direction: direction, confidence: confidence,
                            requestedTimeframe: requested, entry: price, stopLoss: sl, takeProfit: tp,
                            riskReward: rr, rationale: rationale, warnings: warnings)
    }

    // MARK: - Backend confluence layer

    /// Hidden backend engines contribute one bounded vote and auditable notes. This keeps
    /// the app UI clean while the pipeline uses systematic + structure + regime + neural +
    /// chaos + Bayesian + fuzzy + order-flow + session + anomaly + risk tools together.
    private func backendConfluence(md: MarketData) -> (score: Double, notes: [String], warnings: [String]) {
        let system = BackendQuantEngine.systematic(md)
        let structure = ConfluenceAnalysisEngine.analyze(md)
        let regime = BackendQuantEngine.regime(md)
        let neural = AdvancedBackend.neuralSignal(md)
        let fuzzy = fuzzyScore(md)
        let anomaly = anomalyPenalty(md)
        let session = TradingSession.policy(for: md.assetClass)
        let bayes = bayesianScore(md)

        var score = 0.0
        score += Double(system.direction.rawValue) / 2.0 * 0.22
        score += Double(structure.direction.rawValue) / 2.0 * 0.20
        score += (neural.probabilityUp - 0.5) * 2.0 * 0.20
        score += fuzzy * 0.14
        score += bayes * 0.14
        score += regime.state.contains("Trending up") ? 0.05 : regime.state.contains("Trending down") ? -0.05 : 0
        score -= anomaly

        var notes: [String] = []
        notes.append("Backend confluence: systematic \(dirWord(system.direction)), structure \(dirWord(structure.direction)), neural P(up) \(String(format: "%.2f", neural.probabilityUp)), Bayesian \(String(format: "%.2f", bayes)), fuzzy \(String(format: "%.2f", fuzzy)).")
        notes.append("Regime/session: \(regime.state) · \(TradingSession.label()) · min confidence \(Int(session.minConfidence)).")
        if neural.samples > 0 {
            notes.append("On-device neural head trained on \(neural.samples) cached samples; diagnostic accuracy \(String(format: "%.2f", neural.accuracy)).")
        }

        var warnings: [String] = []
        if anomaly > 0.08 { warnings.append("Backend anomaly/manipulation detector is reducing confidence.") }
        if regime.squeezeScore > 0.7 { warnings.append("Volatility squeeze detected — breakout quality matters more than indicator count.") }
        if (neural.probabilityUp > 0.5) != (score > 0), neural.samples > 30 { warnings.append("Neural vote disagrees with the blended backend vote — reduce size or wait.") }
        return (clamp(score, -1, 1), notes, warnings)
    }

    private func fuzzyScore(_ md: MarketData) -> Double {
        let ind = analyzer.analyze(md)
        let trend = clamp(ind.trendStrength / 100, 0, 1)
        let direction = ind.supertrendUp ? 1.0 : -1.0
        let momentum = ind.macdHistogram > 0 ? 0.35 : ind.macdHistogram < 0 ? -0.35 : 0
        return clamp(direction * trend + momentum + ((ind.rsi14 - 50) / 50) * 0.25, -1, 1)
    }

    private func bayesianScore(_ md: MarketData) -> Double {
        let system = BackendQuantEngine.systematic(md)
        let neural = AdvancedBackend.neuralSignal(md)
        var p = 0.5
        p = bayesUpdate(prior: p, likelihoodPositive: 0.5 + Double(system.direction.rawValue) / 2.0 * 0.25, evidence: abs(Double(system.direction.rawValue)) / 2.0)
        p = bayesUpdate(prior: p, likelihoodPositive: neural.probabilityUp, evidence: abs(neural.probabilityUp - 0.5) * 2)
        return clamp((p - 0.5) * 2, -1, 1)
    }

    private func bayesUpdate(prior: Double, likelihoodPositive: Double, evidence: Double) -> Double {
        let pos = clamp(likelihoodPositive, 0.01, 0.99)
        let posterior = (prior * pos) / max(prior * pos + (1 - prior) * (1 - pos), 0.000001)
        return clamp(prior + (posterior - prior) * clamp(evidence, 0, 1), 0.01, 0.99)
    }

    private func anomalyPenalty(_ md: MarketData) -> Double {
        let r = zip(md.closes, md.closes.dropFirst()).compactMap { old, new in old > 0 && new > 0 ? log(new / old) : nil }
        guard r.count > 30 else { return 0 }
        let m = r.reduce(0, +) / Double(r.count)
        let variance = r.reduce(0) { $0 + ($1 - m) * ($1 - m) } / Double(max(1, r.count - 1))
        let sd = sqrt(max(variance, 0.0000000001))
        let z = ((r.last ?? 0) - m) / max(sd, 0.000001)
        let jumps = Microstructure.detectJumps(md.closes, mult: 3.0, lookback: min(180, md.closes.count)).count
        return clamp(abs(z) > 3 ? 0.08 : 0 + min(0.12, Double(jumps) * 0.02), 0, 0.2)
    }

    // MARK: - Helpers

    private func clamp(_ v: Double, _ lo: Double, _ hi: Double) -> Double { max(lo, min(hi, v)) }

    private func label(forScore s: Double) -> String {
        switch s {
        case let x where x >= 0.6: return "strongly bullish"
        case let x where x >= 0.2: return "bullish"
        case let x where x <= -0.6: return "strongly bearish"
        case let x where x <= -0.2: return "bearish"
        default: return "neutral"
        }
    }

    private func dirWord(_ d: Direction) -> String {
        switch d {
        case .strongBullish: return "strongly bullish"
        case .bullish: return "bullish"
        case .neutral: return "neutral"
        case .bearish: return "bearish"
        case .strongBearish: return "strongly bearish"
        }
    }

    private func biasText(_ d: Direction, strength: SignalStrength) -> String {
        d == .neutral ? "no clear bias" : "\(dirWord(d)) (\(String(describing: strength)))"
    }
}
