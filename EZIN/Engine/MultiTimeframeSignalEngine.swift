import Foundation

/// Enhanced signal engine that analyzes across all timeframes and uses all available indicators
/// and tools to generate high-accuracy, multi-confluence signals.
final class MultiTimeframeSignalEngine {
    let baseEngine = SignalEngine()
    let analyzer = TechnicalAnalyzer()
    
    struct TimeframeAnalysis {
        let timeframe: Timeframe
        let signal: TradingSignal?
        let confidence: Double
        let indicators: IndicatorSnapshot
        let microstructure: MicrostructureSnapshot
    }
    
    struct IndicatorSnapshot {
        let rsi: Double
        let macd: (macd: Double, signal: Double, histogram: Double)
        let atr: Double
        let bollingerBands: (upper: Double, middle: Double, lower: Double)
        let adx: Double
        let supertrend: (line: Double, up: Bool)
        let ichimoku: (tenkan: Double, kijun: Double, senkouA: Double, senkouB: Double)
        let volumeProfile: Microstructure.VolumeProfile?
        let orderFlow: Microstructure.OrderFlow
    }
    
    struct MicrostructureSnapshot {
        let volatilityRegime: Microstructure.VolatilityRegime
        let liquidityLevels: [Microstructure.LiquidityLevel]
        let jumpEvents: [Microstructure.JumpEvent]
        let velocity: (speed: Double, accel: Double)
    }
    
    struct MultiTimeframeSignal {
        let symbol: String
        let displayPair: String
        let direction: Direction
        let confidence: Double
        let timeframeAnalyses: [TimeframeAnalysis]
        let confluenceScore: Double  // 0-1, how many timeframes agree
        let recommendedEntry: Double
        let stopLoss: Double
        let takeProfit: Double
        let createdAt: Date
        let expiresAt: Date
        let reasoning: String
    }
    
    /// Generate a comprehensive multi-timeframe signal using all tools and indicators
    func generateMultiTimeframeSignal(
        for md: MarketData,
        timeframes: [Timeframe] = Timeframe.allCases,
        strategyName: String = "Multi-Timeframe Consensus"
    ) -> MultiTimeframeSignal? {
        var analyses: [TimeframeAnalysis] = []
        var directionVotes: [Direction] = []
        var confidenceScores: [Double] = []
        
        // Analyze each timeframe
        for tf in timeframes {
            guard let tfData = fetchMarketDataForTimeframe(md.symbol, tf) else { continue }
            
            let analysis = analyzeTimeframe(tfData, timeframe: tf)
            analyses.append(analysis)
            
            if let signal = analysis.signal {
                directionVotes.append(signal.type.direction)
                confidenceScores.append(analysis.confidence)
            }
        }
        
        guard !directionVotes.isEmpty else { return nil }
        
        // Determine consensus direction
        let consensusDirection = determineConsensusDirection(directionVotes)
        guard consensusDirection != .neutral else { return nil }
        
        // Calculate confluence score (how many timeframes agree)
        let confluenceScore = Double(directionVotes.filter { $0 == consensusDirection }.count) / Double(directionVotes.count)
        guard confluenceScore >= 0.5 else { return nil }  // At least 50% agreement
        
        // Calculate average confidence
        let avgConfidence = confidenceScores.isEmpty ? 0 : confidenceScores.reduce(0, +) / Double(confidenceScores.count)
        
        // Generate entry, SL, TP based on all timeframes
        let price = md.currentPrice > 0 ? md.currentPrice : (md.latest?.close ?? 0)
        guard price > 0 else { return nil }
        
        let (entry, sl, tp) = calculateLevels(
            price: price,
            direction: consensusDirection,
            analyses: analyses,
            marketData: md
        )
        
        let reasoning = buildReasoningString(
            direction: consensusDirection,
            confluenceScore: confluenceScore,
            analyses: analyses,
            timeframes: timeframes
        )
        
        return MultiTimeframeSignal(
            symbol: md.symbol,
            displayPair: DerivSymbols.display(md.symbol),
            direction: consensusDirection,
            confidence: (avgConfidence * confluenceScore * 100).rounded(),
            timeframeAnalyses: analyses,
            confluenceScore: confluenceScore,
            recommendedEntry: entry,
            stopLoss: sl,
            takeProfit: tp,
            createdAt: Date(),
            expiresAt: Date().addingTimeInterval(TimeInterval(30 * 60)),  // 30-minute expiry
            reasoning: reasoning
        )
    }
    
    // MARK: - Private Helpers
    
    private func analyzeTimeframe(_ md: MarketData, timeframe: Timeframe) -> TimeframeAnalysis {
        let indicators = computeIndicators(md)
        let microstructure = computeMicrostructure(md)
        
        // Generate base signal
        let baseSignal = baseEngine.generate(for: md, strategyName: "Timeframe: \(timeframe.rawValue)")
        
        // Calculate confidence based on indicator alignment
        let confidence = calculateConfidence(indicators: indicators, microstructure: microstructure)
        
        return TimeframeAnalysis(
            timeframe: timeframe,
            signal: baseSignal,
            confidence: confidence,
            indicators: indicators,
            microstructure: microstructure
        )
    }
    
    private func computeIndicators(_ md: MarketData) -> IndicatorSnapshot {
        let ind = analyzer.analyze(md)
        let rsi = Indicators.rsi(md.closes, 14).last ?? 50
        let macd = Indicators.macd(md.closes, fast: 12, slow: 26, signal: 9)
        let atr = Indicators.atr(md.highs, md.lows, md.closes, 14).last ?? 0
        let bb = Indicators.bollinger(md.closes, len: 20, mult: 2)
        let adx = Indicators.adx(md.highs, md.lows, md.closes, 14)
        let st = Indicators.supertrend(md.highs, md.lows, md.closes, len: 10, mult: 3)
        let ichi = Indicators.ichimoku(md.highs, md.lows, md.closes, conv: 9, base: 26, spanB: 52)
        let vp = Microstructure.volumeProfile(high: md.highs, low: md.lows, close: md.closes, volume: md.volumes, bins: 24)
        let of = Microstructure.orderFlow(open: md.opens, high: md.highs, low: md.lows, close: md.closes, volume: md.volumes, window: 30)
        
        return IndicatorSnapshot(
            rsi: rsi,
            macd: (macd.macd.last ?? 0, macd.signal.last ?? 0, macd.histogram.last ?? 0),
            atr: atr,
            bollingerBands: (bb.upper.last ?? 0, bb.middle.last ?? 0, bb.lower.last ?? 0),
            adx: adx.adx.last ?? 0,
            supertrend: (st.line.last ?? 0, st.up.last ?? true),
            ichimoku: (ichi.tenkan.last ?? 0, ichi.kijun.last ?? 0, ichi.senkouA.last ?? 0, ichi.senkouB.last ?? 0),
            volumeProfile: vp,
            orderFlow: of
        )
    }
    
    private func computeMicrostructure(_ md: MarketData) -> MicrostructureSnapshot {
        let regime = Microstructure.regime(md.closes)
        let liquidity = Microstructure.liquidityLevels(high: md.highs, low: md.lows, close: md.closes, lookback: 120, maxLevels: 6)
        let jumps = Microstructure.detectJumps(md.closes, mult: 3.0, lookback: 120)
        let vel = Microstructure.velocity(md.closes, n: 10)
        
        return MicrostructureSnapshot(
            volatilityRegime: regime,
            liquidityLevels: liquidity,
            jumpEvents: jumps,
            velocity: vel
        )
    }
    
    private func calculateConfidence(indicators: IndicatorSnapshot, microstructure: MicrostructureSnapshot) -> Double {
        var score = 0.0
        var count = 0
        
        // RSI alignment
        if (indicators.rsi > 70 || indicators.rsi < 30) { score += 0.15; count += 1 }
        
        // MACD histogram alignment
        if (indicators.macd.histogram > 0) { score += 0.15; count += 1 }
        
        // ADX strength
        if (indicators.adx > 25) { score += 0.15; count += 1 }
        
        // Supertrend alignment
        if (indicators.supertrend.up) { score += 0.15; count += 1 }
        
        // Order flow bias
        if (microstructure.velocity.accel > 0) { score += 0.15; count += 1 }
        
        // Volatility regime
        if (microstructure.volatilityRegime != .calm) { score += 0.15; count += 1 }
        
        return count > 0 ? score / Double(count) : 0.5
    }
    
    private func determineConsensusDirection(_ votes: [Direction]) -> Direction {
        let bullishCount = votes.filter { $0.isBullish }.count
        let bearishCount = votes.filter { $0.isBearish }.count
        
        if bullishCount > bearishCount { return .bullish }
        if bearishCount > bullishCount { return .bearish }
        return .neutral
    }
    
    private func calculateLevels(
        price: Double,
        direction: Direction,
        analyses: [TimeframeAnalysis],
        marketData: MarketData
    ) -> (entry: Double, sl: Double, tp: Double) {
        // Use ATR from the highest timeframe for stop loss/take profit
        let atrValues = analyses.map { $0.indicators.atr }.filter { $0 > 0 }
        let avgAtr = atrValues.isEmpty ? price * 0.01 : atrValues.reduce(0, +) / Double(atrValues.count)
        
        let entry = price
        let sl = direction.isBullish ? price - (avgAtr * 2) : price + (avgAtr * 2)
        let tp = direction.isBullish ? price + (avgAtr * 3) : price - (avgAtr * 3)
        
        return (entry, sl, tp)
    }
    
    private func buildReasoningString(
        direction: Direction,
        confluenceScore: Double,
        analyses: [TimeframeAnalysis],
        timeframes: [Timeframe]
    ) -> String {
        var reasoning = "Multi-timeframe \(direction.isBullish ? "BULLISH" : "BEARISH") signal with \(Int(confluenceScore * 100))% confluence.\n"
        reasoning += "Timeframe Agreement: "
        
        let agreedTimeframes = analyses
            .filter { $0.signal?.type.direction == direction }
            .map { $0.timeframe.rawValue }
        
        reasoning += agreedTimeframes.joined(separator: ", ")
        reasoning += "\n"
        
        // Add key indicator insights
        if let strongest = analyses.max(by: { $0.confidence < $1.confidence }) {
            reasoning += "Strongest signal on \(strongest.timeframe.rawValue) with \(Int(strongest.confidence * 100))% confidence."
        }
        
        return reasoning
    }
    
    private func fetchMarketDataForTimeframe(_ symbol: String, _ timeframe: Timeframe) -> MarketData? {
        // This would fetch historical data for the specific timeframe
        // For now, returning nil as a placeholder
        return nil
    }
}
