import Foundation

/// Advanced deterministic backend engines. These run on-device and feed the hidden
/// analysis layer: agents, pipelines and chat tools call them as confluence inputs.
/// They are computation engines, not order routers — outputs are advisory and auditable.
enum AdvancedBackend {

    // MARK: - Shared numerics

    static func returns(_ prices: [Double]) -> [Double] {
        zip(prices, prices.dropFirst()).compactMap { old, new in old > 0 && new > 0 ? log(new / old) : nil }
    }

    static func mean(_ xs: [Double]) -> Double { xs.isEmpty ? 0 : xs.reduce(0, +) / Double(xs.count) }

    static func sd(_ xs: [Double]) -> Double {
        guard xs.count > 1 else { return 0 }
        let m = mean(xs)
        return sqrt(xs.reduce(0) { $0 + pow($1 - m, 2) } / Double(xs.count - 1))
    }

    static func clamp(_ x: Double, _ lo: Double, _ hi: Double) -> Double { min(max(x, lo), hi) }

    static func fmt(_ x: Double, _ places: Int = 3) -> String { String(format: "%.\(places)f", x) }

    static func dir(_ d: Direction) -> String {
        switch d {
        case .strongBullish: return "Strong bullish"
        case .bullish: return "Bullish"
        case .neutral: return "Neutral"
        case .bearish: return "Bearish"
        case .strongBearish: return "Strong bearish"
        }
    }

    static func signed(_ d: Direction) -> Double { Double(d.rawValue) / 2.0 }

    // MARK: - Mathematical analysis

    struct RegressionResult { let slope: Double; let intercept: Double; let r2: Double; let forecast: Double }
    struct KalmanResult { let estimate: Double; let velocity: Double; let uncertainty: Double }
    struct FourierResult { let dominantPeriod: Int; let power: Double; let secondPeriod: Int }

    static func linearRegression(_ ys: [Double]) -> RegressionResult {
        let n = ys.count
        guard n > 3 else { return RegressionResult(slope: 0, intercept: ys.last ?? 0, r2: 0, forecast: ys.last ?? 0) }
        let xs = (0..<n).map(Double.init)
        let mx = mean(xs), my = mean(ys)
        var sxx = 0.0, sxy = 0.0, sst = 0.0, sse = 0.0
        let slopeDen = xs.reduce(0) { $0 + pow($1 - mx, 2) }
        let slope = slopeDen > 0 ? zip(xs, ys).reduce(0) { $0 + ($1.0 - mx) * ($1.1 - my) } / slopeDen : 0
        let intercept = my - slope * mx
        for (x, y) in zip(xs, ys) {
            let fit = intercept + slope * x
            sst += pow(y - my, 2)
            sse += pow(y - fit, 2)
        }
        sxx = slopeDen
        sxy = zip(xs, ys).reduce(0) { $0 + ($1.0 - mx) * ($1.1 - my) }
        let r2 = sst > 0 ? clamp(1 - sse / sst, 0, 1) : 0
        return RegressionResult(slope: slope, intercept: intercept, r2: r2, forecast: intercept + slope * Double(n))
    }

    /// AR(1)/ARIMA-lite one-step forecast with drift. Deterministic and fast for iOS.
    static func arimaLiteForecast(_ prices: [Double], steps: Int = 5) -> [Double] {
        let r = returns(prices)
        guard r.count > 10, let last = prices.last else { return [] }
        let mu = mean(r)
        let phi = autocorrelation(r, lag: 1)
        var out: [Double] = []
        var current = last
        var shock = r.last ?? 0
        for _ in 0..<max(1, steps) {
            shock = mu + phi * (shock - mu)
            current *= exp(shock)
            out.append(current)
        }
        return out
    }

    /// GARCH(1,1)-lite volatility forecast using long-run variance anchors.
    static func garchLiteVolatility(_ prices: [Double]) -> (current: Double, forecast: Double, regime: String) {
        let r = returns(prices)
        guard r.count > 20 else { return (0, 0, "insufficient data") }
        let recent = Array(r.suffix(20))
        let long = Array(r.suffix(min(120, r.count)))
        let omega = pow(sd(long), 2) * 0.08
        let alpha = 0.22
        let beta = 0.72
        var variance = pow(sd(long), 2)
        for x in recent { variance = omega + alpha * x * x + beta * variance }
        let forecast = sqrt(max(variance, 0))
        let current = sd(recent)
        let ratio = forecast > 0 ? current / forecast : 1
        let regime = ratio > 1.25 ? "volatility expansion" : ratio < 0.75 ? "volatility compression" : "balanced volatility"
        return (current, forecast, regime)
    }

    static func autocorrelation(_ xs: [Double], lag: Int) -> Double {
        guard xs.count > lag + 2 else { return 0 }
        let m = mean(xs)
        let num = zip(xs.dropFirst(lag), xs.dropLast(lag)).reduce(0) { $0 + ($1.0 - m) * ($1.1 - m) }
        let den = xs.reduce(0) { $0 + pow($1 - m, 2) }
        return den > 0 ? num / den : 0
    }

    /// Constant-velocity Kalman filter over log prices.
    static func kalman(_ prices: [Double]) -> KalmanResult {
        guard prices.count > 3 else { return KalmanResult(estimate: prices.last ?? 0, velocity: 0, uncertainty: 1) }
        var x = log(prices[0])
        var v = 0.0
        var p = 1.0
        let q = 0.00008
        let r = max(sd(returns(prices)) * 0.15, 0.00001)
        for price in prices.dropFirst() {
            // predict
            x += v
            p += q
            // update
            let z = log(price)
            let k = p / (p + r)
            let residual = z - x
            x += k * residual
            v = clamp(v + k * residual * 0.08, -0.02, 0.02)
            p = (1 - k) * p
        }
        return KalmanResult(estimate: exp(x), velocity: v, uncertainty: p)
    }

    /// Small DFT for dominant-cycle detection. Uses the last <=128 returns.
    static func fourier(_ prices: [Double]) -> FourierResult {
        let r = Array(returns(prices).suffix(128))
        guard r.count >= 32 else { return FourierResult(dominantPeriod: 0, power: 0, secondPeriod: 0) }
        let n = r.count
        let m = mean(r)
        let centered = r.map { $0 - m }
        var best: (period: Int, power: Double) = (0, 0)
        var second: (period: Int, power: Double) = (0, 0)
        for k in 2...(n / 2) {
            var re = 0.0, im = 0.0
            for (i, x) in centered.enumerated() {
                let angle = -2 * Double.pi * Double(k) * Double(i) / Double(n)
                re += x * cos(angle)
                im += x * sin(angle)
            }
            let power = re * re + im * im
            if power > best.power { second = best; best = (k, power) }
            else if power > second.power { second = (k, power) }
        }
        return FourierResult(dominantPeriod: best.period, power: best.power, secondPeriod: second.period)
    }

    static func mathematicalReport(for md: MarketData) -> String {
        let stats = BackendQuantEngine.statistics(md.closes)
        let reg = linearRegression(md.closes)
        let ar = arimaLiteForecast(md.closes)
        let garch = garchLiteVolatility(md.closes)
        let kal = kalman(md.closes)
        let fft = fourier(md.closes)
        return """
        ## Mathematical Analysis
        - Regression: slope \(fmt(reg.slope, 6)) · intercept \(fmt(reg.intercept, 5)) · R² \(fmt(reg.r2)) · next-bar projection \(fmt(reg.forecast, 5))
        - ARIMA-lite path: \(ar.isEmpty ? "insufficient returns" : ar.map { fmt($0, 5) }.joined(separator: " → "))
        - GARCH-lite: current σ \(fmt(garch.current, 6)) · forecast σ \(fmt(garch.forecast, 6)) · \(garch.regime)
        - Kalman state: fair value \(fmt(kal.estimate, 5)) · velocity \(fmt(kal.velocity, 6)) · uncertainty \(fmt(kal.uncertainty, 5))
        - Statistics: z \(fmt(stats.zScore)) · skew \(fmt(stats.skewness)) · kurtosis \(fmt(stats.kurtosis)) · ACF(1) \(fmt(stats.autocorrelation)) · Hurst \(fmt(stats.hurstExponent))
        - Cycles: dominant \(fft.dominantPeriod == 0 ? "none" : "\(fft.dominantPeriod) bars") · secondary \(fft.secondPeriod == 0 ? "none" : "\(fft.secondPeriod) bars")
        """
    }

    // MARK: - Forex math science

    static func forexMathReport(for md: MarketData, domesticRate: Double = 0.05, foreignRate: Double = 0.03, days: Double = 30) -> String {
        guard md.assetClass == .forex || md.assetClass == .commodity else {
            return "## Forex Math\nRun this on a `frx*` pair or metal. Interest-rate parity, PPP deviation, carry and pip velocity are FX-specific."
        }
        let spot = md.currentPrice > 0 ? md.currentPrice : (md.closes.last ?? 0)
        let forward = spot * pow((1 + domesticRate) / (1 + foreignRate), days / 365)
        let irpGap = spot > 0 ? (forward - spot) / spot : 0
        let stats = BackendQuantEngine.statistics(md.closes)
        let pppDeviation = clamp(stats.zScore / 3, -1, 1)
        let carry = domesticRate - foreignRate
        let atr = Indicators.atr(md.highs, md.lows, md.closes, 14).last ?? spot * 0.001
        let point = DerivSymbols.pointSize(md.symbol)
        let pipVelocity = point > 0 ? atr / point : 0
        let session = TradingSession.label()
        let strength = currencyStrength(md)
        return """
        ## Math-Science Forex Analysis
        - IRP fair forward (\(Int(days))d): \(fmt(forward, 5)) · gap \(fmt(irpGap * 100, 3))% · \(abs(irpGap) > 0.002 ? "parity deviation worth monitoring" : "near parity")
        - PPP deviation proxy: \(fmt(pppDeviation)) (−1 undervalued … +1 overvalued vs recent mean)
        - Carry advantage: \(fmt(carry * 100, 2))% annualized · \(carry > 0 ? "long higher-yield leg is paid" : "carry is not supportive")
        - Currency strength read: \(strength)
        - Pip velocity: \(fmt(pipVelocity, 1)) pips/ATR · session \(session)
        - COT/sentiment hook: use `inject_news` or `sentiment_score` to add positioning context; this engine keeps the math layer deterministic.
        """
    }

    static func currencyStrength(_ md: MarketData) -> String {
        let symbol = md.symbol
        guard symbol.hasPrefix("frx"), symbol.count >= 9 else { return "not a pair" }
        let s = String(symbol.dropFirst(3))
        guard s.count == 6 else { return "metal/CFD quote" }
        let base = String(s.prefix(3)), quote = String(s.suffix(3))
        let drift = mean(returns(md.closes).suffix(30))
        let score = clamp(drift * 250, -1, 1)
        if score > 0.2 { return "\(base) strengthening vs \(quote) (\(fmt(score)))" }
        if score < -0.2 { return "\(base) weakening vs \(quote) (\(fmt(score)))" }
        return "\(base)/\(quote) balanced (\(fmt(score)))"
    }

    // MARK: - Synthetics / RNG / Monte Carlo / Markov

    static func syntheticsReport(for md: MarketData) -> String {
        let prices = md.closes
        guard prices.count >= 50 else { return "## Synthetics Analysis\nNeed at least 50 cached candles/ticks." }
        let digits = prices.map { Int(abs($0) * 100) % 10 }
        var counts = Array(repeating: 0, count: 10)
        digits.forEach { counts[$0] += 1 }
        let expected = Double(digits.count) / 10
        let chi = counts.reduce(0) { $0 + pow(Double($1) - expected, 2) / max(expected, 1) }
        let rets = returns(prices)
        var upStreak = 0, downStreak = 0, maxUp = 0, maxDown = 0
        for r in rets {
            if r >= 0 { upStreak += 1; downStreak = 0 } else { downStreak += 1; upStreak = 0 }
            maxUp = max(maxUp, upStreak); maxDown = max(maxDown, downStreak)
        }
        let jumps = Microstructure.detectJumps(prices, mult: 3.0, lookback: min(180, prices.count))
        let spikeScore = clamp(Double(jumps.count) / Double(max(1, prices.count / 30)), 0, 1)
        let profile = syntheticProfile(md.symbol)
        return """
        ## Synthetics Analysis
        - Profile: \(profile)
        - Last-digit heat: \(counts.enumerated().map { "\($0.offset):\($0.element)" }.joined(separator: " ")) · χ² \(fmt(chi, 2)) \(chi > 16.9 ? "(digit bias flagged)" : "(no strong digit bias)")
        - Streaks: max up \(maxUp) · max down \(maxDown) · current \(upStreak > 0 ? "+\(upStreak)" : "-\(downStreak)")
        - Spike/jump model: \(jumps.count) events · spike risk \(fmt(spikeScore))
        - Boom/Crash note: for spike products, treat spikeScore above 0.55 as a reduce-size warning, not an entry by itself.
        """
    }

    static func syntheticProfile(_ symbol: String) -> String {
        if symbol.hasPrefix("BOOM") { return "Boom index — upside spikes punctuate a sell-biased drift; never chase a spike candle." }
        if symbol.hasPrefix("CRASH") { return "Crash index — downside spikes punctuate a buy-biased drift; never chase a dump candle." }
        if symbol.hasPrefix("JD") { return "Jump index — abrupt regime jumps; demand confirmation from volatility and order flow." }
        if symbol.hasPrefix("1HZ") { return "1-second volatility — microstructure dominates; use small size and fast invalidation." }
        if symbol.hasPrefix("R_") { return "Constant volatility index — regime, RNG and cycle tools carry the most weight." }
        if symbol.hasPrefix("stp") { return "Step index — fixed-step behavior; digit/streak tools are useful." }
        return "Synthetic/OTC instrument — validate with RNG, regime and anomaly scans."
    }

    static func monteCarlo(_ prices: [Double], simulations: Int = 300, horizon: Int = 20) -> (upProbability: Double, p05: Double, p50: Double, p95: Double) {
        let r = returns(prices)
        guard r.count > 20, let start = prices.last else { return (0.5, 0, 0, 0) }
        let mu = mean(r), sigma = max(sd(r), 0.000001)
        var finals: [Double] = []
        finals.reserveCapacity(simulations)
        for _ in 0..<max(50, simulations) {
            var x = start
            for _ in 0..<max(1, horizon) {
                let shock = mu + sigma * gaussian()
                x *= exp(shock)
            }
            finals.append(x)
        }
        finals.sort()
        let up = Double(finals.filter { $0 > start }.count) / Double(finals.count)
        let p05 = finals[Int(Double(finals.count) * 0.05)]
        let p50 = finals[Int(Double(finals.count) * 0.50)]
        let p95 = finals[min(finals.count - 1, Int(Double(finals.count) * 0.95))]
        return (up, p05, p50, p95)
    }

    static func gaussian() -> Double {
        let u1 = max(Double.random(in: 0...1), 0.000001)
        let u2 = Double.random(in: 0...1)
        return sqrt(-2 * log(u1)) * cos(2 * Double.pi * u2)
    }

    static func rngReport(for md: MarketData) -> String {
        let rng = BackendQuantEngine.randomness(md.closes)
        let mc = monteCarlo(md.closes)
        let stats = BackendQuantEngine.statistics(md.closes)
        return """
        ## RNG / Probability Analysis
        - Uniformity χ² \(fmt(rng.chiSquare)) · Shannon entropy \(fmt(rng.entropy))/1 · runs z \(fmt(rng.runsZScore))
        - Markov transitions: P(up|up) \(fmt(rng.transitionUpGivenUp)) · P(up|down) \(fmt(rng.transitionUpGivenDown))
        - Bias detector: \(rng.biasDetected ? "FLAGGED — validate out-of-sample before trusting any edge" : "no exploitable directional deviation at this sample size")
        - Monte Carlo (20 bars): P(up) \(fmt(mc.upProbability)) · 5% \(fmt(mc.p05, 5)) · median \(fmt(mc.p50, 5)) · 95% \(fmt(mc.p95, 5))
        - Entropy note: entropy near 1 with |runs z| < 2 means pattern-breaking attempts should stay defensive.
        """
    }

    // MARK: - On-device neural inference (real lightweight ML)

    struct NeuralResult { let probabilityUp: Double; let accuracy: Double; let samples: Int; let features: [String] }

    /// Logistic classifier trained on-device from cached candles. Features are normalized
    /// indicator/microstructure readings; label is next-bar direction. This is real ML
    /// inference/training, kept small enough for iOS background scans.
    static func neuralSignal(_ md: MarketData) -> NeuralResult {
        let closes = md.closes
        guard closes.count >= 80 else { return NeuralResult(probabilityUp: 0.5, accuracy: 0, samples: 0, features: []) }
        let ind = TechnicalAnalyzer().analyze(md)
        let r = returns(closes)
        var rows: [[Double]] = []
        var labels: [Double] = []
        for i in 30..<(closes.count - 1) {
            let window = Array(closes[(i - 30)...i])
            let wr = returns(window)
            let rsi = Indicators.rsi(window, 14).last ?? 50
            let mom = wr.suffix(5).reduce(0, +)
            let vol = sd(Array(wr.suffix(10)))
            let trend = (window.last ?? 0) - (window.first ?? 0)
            let y = closes[i + 1] > closes[i] ? 1.0 : 0.0
            rows.append([(rsi - 50) / 50, clamp(mom * 80, -1, 1), clamp(vol * 120, -1, 1), clamp(trend / max(window.last ?? 1, 1) * 100, -1, 1), 1])
            labels.append(y)
        }
        guard rows.count >= 30 else { return NeuralResult(probabilityUp: 0.5, accuracy: 0, samples: rows.count, features: []) }
        var w = Array(repeating: 0.0, count: rows[0].count)
        let lr = 0.08
        for _ in 0..<180 {
            for (x, y) in zip(rows, labels) {
                let z = zip(w, x).reduce(0) { $0 + $1.0 * $1.1 }
                let p = 1 / (1 + exp(-clamp(z, -30, 30)))
                for j in w.indices { w[j] += lr * (y - p) * x[j] / Double(rows.count) }
            }
        }
        var correct = 0
        for (x, y) in zip(rows, labels) {
            let z = zip(w, x).reduce(0) { $0 + $1.0 * $1.1 }
            let p = 1 / (1 + exp(-clamp(z, -30, 30)))
            if (p >= 0.5) == (y >= 0.5) { correct += 1 }
        }
        let latestR = returns(Array(closes.suffix(31)))
        // Broken into sub-expressions: a single nested literal here previously
        // blew the type-checker's time budget.
        let rsiFeature = (ind.rsi14 - 50) / 50
        let ret5Feature = clamp(latestR.suffix(5).reduce(0, +) * 80, -1, 1)
        let vol10Feature = clamp(sd(Array(latestR.suffix(10))) * 120, -1, 1)
        let driftBase = closes.dropLast(30).last ?? closes.last ?? 1
        let driftFeature = clamp(((closes.last ?? 0) - driftBase) / max(closes.last ?? 1, 1) * 100, -1, 1)
        let x: [Double] = [rsiFeature, ret5Feature, vol10Feature, driftFeature, 1]
        let z = zip(w, x).reduce(0) { $0 + $1.0 * $1.1 }
        let p = 1 / (1 + exp(-clamp(z, -30, 30)))
        return NeuralResult(probabilityUp: p, accuracy: Double(correct) / Double(rows.count), samples: rows.count,
                            features: ["RSI", "5-bar return", "10-bar volatility", "30-bar drift", "bias"])
    }

    static func neuralReport(for md: MarketData) -> String {
        let n = neuralSignal(md)
        guard n.samples > 0 else { return "## Neural Inference\nNeed at least 80 candles to train the on-device classifier." }
        let direction = n.probabilityUp > 0.56 ? "bullish edge" : n.probabilityUp < 0.44 ? "bearish edge" : "no stable edge"
        return """
        ## Neural Inference (On-Device)
        - Model: logistic signal head trained on \(n.samples) cached samples · features \(n.features.joined(separator: ", "))
        - P(next bar up): \(fmt(n.probabilityUp)) → \(direction)
        - In-sample accuracy: \(fmt(n.accuracy)) (diagnostic only — walk-forward/backtest before trusting)
        - Ensemble use: treat this as one vote beside systematic, structure, regime, order-flow and risk engines; never as a standalone entry.
        """
    }

    // MARK: - Chaos / quantum-inspired / Bayesian / fuzzy

    static func chaosReport(for md: MarketData) -> String {
        let prices = md.closes
        let stats = BackendQuantEngine.statistics(prices)
        let r = returns(prices)
        let lyap = approximateLyapunov(r)
        let fd = boxCountingDimension(prices)
        let regimeShift = clamp(abs(stats.autocorrelation) + abs(stats.zScore) / 3 + (stats.hurstExponent > 0.55 ? 0.15 : 0), 0, 1)
        return """
        ## Chaos Theory Analysis
        - Hurst exponent: \(fmt(stats.hurstExponent)) (\(stats.hurstExponent > 0.55 ? "persistent/trending" : stats.hurstExponent < 0.45 ? "anti-persistent/mean-reverting" : "near random walk"))
        - Largest Lyapunov proxy: \(fmt(lyap, 5)) (\(lyap > 0 ? "sensitive dependence — regimes can flip quickly" : "stable local dynamics"))
        - Fractal dimension proxy: \(fmt(fd)) · regime-change pressure \(fmt(regimeShift))
        - Read: \(regimeShift > 0.62 ? "do not extrapolate the current regime blindly; tighten invalidation." : "regime persistence is acceptable for structured setups.")
        """
    }

    static func approximateLyapunov(_ r: [Double]) -> Double {
        guard r.count > 30 else { return 0 }
        let eps = max(sd(r) * 0.1, 0.00001)
        var logs: [Double] = []
        for i in 0..<(r.count - 10) {
            var j = -1
            var best = Double.greatestFiniteMagnitude
            for k in (i + 5)..<r.count {
                let d = abs(r[i] - r[k])
                if d < best && d > eps { best = d; j = k }
            }
            if j > 0, j + 5 < r.count {
                let d0 = max(abs(r[i] - r[j]), eps)
                let d1 = abs(r[min(i + 5, r.count - 1)] - r[j + 5])
                if d1 > 0 { logs.append(log(d1 / d0) / 5) }
            }
        }
        return mean(logs)
    }

    static func boxCountingDimension(_ prices: [Double]) -> Double {
        guard prices.count > 20 else { return 1 }
        let minP = prices.min() ?? 0, maxP = prices.max() ?? 1
        let range = max(maxP - minP, 0.000001)
        func boxes(_ size: Double) -> Int {
            guard size > 0 else { return 0 }
            var set = Set<Int>()
            for (i, p) in prices.enumerated() {
                let t = i / max(1, Int(size))
                let b = Int((p - minP) / size)
                set.insert(t * 1_000_003 + b)
            }
            return max(set.count, 1)
        }
        let s1 = range / 8, s2 = range / 16
        let n1 = Double(boxes(s1)), n2 = Double(boxes(s2))
        return clamp(log(n2 / n1) / log(2), 1, 2)
    }

    static func quantumInspiredReport(for md: MarketData) -> String {
        let system = BackendQuantEngine.systematic(md)
        let neural = neuralSignal(md)
        let regime = BackendQuantEngine.regime(md)
        let bullEvidence = max(0, signed(system.direction)) + max(0, (neural.probabilityUp - 0.5) * 2) + (regime.state.contains("Trending up") ? 0.35 : 0)
        let bearEvidence = max(0, -signed(system.direction)) + max(0, (0.5 - neural.probabilityUp) * 2) + (regime.state.contains("Trending down") ? 0.35 : 0)
        let neutralEvidence = 0.35 + (regime.squeezeScore * 0.4)
        let expBull = exp(bullEvidence), expBear = exp(bearEvidence), expNeutral = exp(neutralEvidence)
        let total = expBull + expBear + expNeutral
        return """
        ## Quantum-Inspired Scenario Model
        - Scenario amplitudes: bullish \(fmt(expBull / total)) · bearish \(fmt(expBear / total)) · neutral/compressed \(fmt(expNeutral / total))
        - Superposition collapse rule: only act when one scenario exceeds 0.55 AND risk/session/anomaly checks agree.
        - Portfolio annealing note: with multiple cached instruments, `correlation_matrix` + `deep_risk` form the optimization constraints.
        """
    }

    static func bayesianReport(for md: MarketData) -> String {
        let system = BackendQuantEngine.systematic(md)
        let neural = neuralSignal(md)
        let structure = ConfluenceAnalysisEngine.analyze(md)
        var pUp = 0.5
        pUp = update(prior: pUp, likelihoodPositive: 0.5 + signed(system.direction) * 0.25, evidence: abs(signed(system.direction)))
        pUp = update(prior: pUp, likelihoodPositive: neural.probabilityUp, evidence: abs(neural.probabilityUp - 0.5) * 2)
        pUp = update(prior: pUp, likelihoodPositive: structure.direction == .neutral ? 0.5 : (structure.direction.isBullish ? 0.68 : 0.32), evidence: Double(structure.confidence) / 100)
        let conf = Int(clamp(abs(pUp - 0.5) * 2, 0, 1) * 100)
        return """
        ## Bayesian Inference
        - Prior P(up): 0.50 → Posterior P(up): \(fmt(pUp))
        - Evidence used: systematic \(dir(system.direction)), neural \(fmt(neural.probabilityUp)), structure \(dir(structure.direction))
        - Posterior confidence: \(conf)/100 · decision: \(pUp > 0.56 ? "bullish posterior" : pUp < 0.44 ? "bearish posterior" : "wait for more evidence")
        """
    }

    static func update(prior: Double, likelihoodPositive: Double, evidence: Double) -> Double {
        let strength = clamp(evidence, 0, 1)
        let pos = clamp(likelihoodPositive, 0.01, 0.99)
        let posterior = (prior * pos) / max(prior * pos + (1 - prior) * (1 - pos), 0.000001)
        return clamp(prior + (posterior - prior) * strength, 0.01, 0.99)
    }

    static func fuzzyReport(for md: MarketData) -> String {
        let ind = TechnicalAnalyzer().analyze(md)
        let trend = clamp(ind.trendStrength / 100, 0, 1)
        let momentum = clamp(abs(ind.macdHistogram) / max(abs(ind.macdLine), 0.0001), 0, 1)
        let vol = clamp(ind.atr14 / max(md.currentPrice, 0.000001) * 200, 0, 1)
        let strongBuy = min(trend, momentum, ind.supertrendUp ? 1 : 0)
        let weakBuy = min(trend * 0.6, ind.supertrendUp ? 1 : 0)
        let strongSell = min(trend, momentum, ind.supertrendUp ? 0 : 1)
        let neutral = max(1 - max(strongBuy, strongSell), vol < 0.2 ? 0.4 : 0)
        let label = strongBuy > 0.62 ? "STRONG BUY" : strongSell > 0.62 ? "STRONG SELL" : weakBuy > 0.45 ? "weak buy" : neutral > 0.5 ? "neutral / gray area" : "weak sell"
        return """
        ## Fuzzy Logic Confluence
        - Memberships: trend \(fmt(trend)) · momentum \(fmt(momentum)) · volatility \(fmt(vol))
        - Linguistic output: \(label) (strongBuy \(fmt(strongBuy)) · weakBuy \(fmt(weakBuy)) · strongSell \(fmt(strongSell)) · neutral \(fmt(neutral)))
        - Use: fuzzy labels are ideal for gray-area confluence where hard yes/no signals lose information.
        """
    }

    // MARK: - Order flow / harmonic / Elliott / astro

    static func orderFlowReport(for md: MarketData) -> String {
        let flow = Microstructure.orderFlow(open: md.opens, high: md.highs, low: md.lows, close: md.closes, volume: md.volumes, window: min(60, max(20, md.candles.count / 3)))
        let vp = Microstructure.volumeProfile(high: md.highs, low: md.lows, close: md.closes, volume: md.volumes, bins: 24)
        let imbalance = flow.tradeDirectionRatioProxy - 0.5
        return """
        ## Order Flow / Market Microstructure
        - Bias: \(dir(flow.bias)) · net aggressive volume proxy \(fmt(flow.netAggressiveVolumeProxy)) · buy-bar ratio \(fmt(flow.tradeDirectionRatioProxy))
        - Bid/ask imbalance proxy: \(fmt(imbalance)) (\(abs(imbalance) > 0.12 ? "aggressors are one-sided" : "two-sided flow"))
        - Volume profile: POC \(fmt(vp?.poc ?? 0, 5)) · value area \(fmt(vp?.valueAreaLow ?? 0, 5))–\(fmt(vp?.valueAreaHigh ?? 0, 5))
        - Iceberg/spoof note: on Deriv candle volume these are proxies; combine with anomaly_scan before calling manipulation.
        """
    }

    static func harmonicReport(for md: MarketData) -> String {
        let pivots = DivergenceEngine.findPivots(md.closes, leftBars: 3, rightBars: 3)
        let points = (pivots.highs.map { (idx: $0.index, price: $0.value, high: true) } + pivots.lows.map { (idx: $0.index, price: $0.value, high: false) }).sorted { $0.idx < $1.idx }
        guard points.count >= 5 else { return "## Harmonic Patterns\nNeed at least 5 swing pivots for XABCD scanning." }
        let last5 = Array(points.suffix(5))
        let xa = abs(last5[1].price - last5[0].price)
        let ab = abs(last5[2].price - last5[1].price)
        let bc = abs(last5[3].price - last5[2].price)
        let cd = abs(last5[4].price - last5[3].price)
        guard xa > 0, ab > 0, bc > 0 else { return "## Harmonic Patterns\nSwing legs are too flat to score." }
        let abXa = ab / xa, bcAb = bc / ab, cdBc = cd / bc
        func score(_ value: Double, _ target: Double, _ tol: Double) -> Double { clamp(1 - abs(value - target) / tol, 0, 1) }
        let gartley = (score(abXa, 0.618, 0.12) + score(bcAb, 0.382, 0.15) + score(cdBc, 1.272, 0.25)) / 3
        let bat = (score(abXa, 0.5, 0.12) + score(bcAb, 0.382, 0.15) + score(cdBc, 2.0, 0.35)) / 3
        let butterfly = (score(abXa, 0.786, 0.12) + score(bcAb, 0.382, 0.15) + score(cdBc, 1.618, 0.3)) / 3
        let best = [("Gartley", gartley), ("Bat", bat), ("Butterfly", butterfly)].max { $0.1 < $1.1 } ?? ("None", 0)
        let bullish = last5[4].high == false
        return """
        ## Harmonic & Geometric Patterns
        - Ratios: AB/XA \(fmt(abXa)) · BC/AB \(fmt(bcAb)) · CD/BC \(fmt(cdBc))
        - Best fit: \(best.0) score \(fmt(best.1)) · direction \(bullish ? "bullish completion" : "bearish completion")
        - Precision rule: score above 0.72 still requires structure/regime confirmation; harmonic completion is a zone, not a guarantee.
        """
    }

    static func elliottReport(for md: MarketData) -> String {
        let pivots = DivergenceEngine.findPivots(md.closes, leftBars: 4, rightBars: 4)
        let highs = pivots.highs.suffix(6), lows = pivots.lows.suffix(6)
        let impulseUp = highs.count >= 3 && lows.count >= 2 && zip(highs, highs.dropFirst()).allSatisfy { $0.value < $1.value } && zip(lows, lows.dropFirst()).allSatisfy { $0.value < $1.value }
        let impulseDown = highs.count >= 2 && lows.count >= 3 && zip(highs, highs.dropFirst()).allSatisfy { $0.value > $1.value } && zip(lows, lows.dropFirst()).allSatisfy { $0.value > $1.value }
        let lastHigh = pivots.highs.last?.value ?? md.highs.max() ?? 0
        let lastLow = pivots.lows.last?.value ?? md.lows.min() ?? 0
        return """
        ## Elliott Wave Auto-Counter
        - Read: \(impulseUp ? "5-wave upward impulse candidate" : impulseDown ? "5-wave downward impulse candidate" : "no clean impulse; assume corrective/ambiguous")
        - Rule checks: wave 2 must not break origin, wave 3 must not be shortest, wave 4 should not overlap wave 1 in cash markets.
        - Invalidation: bullish count fails below \(fmt(lastLow, 5)); bearish count fails above \(fmt(lastHigh, 5)).
        """
    }

    static func astroReport(for md: MarketData, date: Date = Date()) -> String {
        let lunar = lunarPhase(date)
        let price = md.currentPrice > 0 ? md.currentPrice : (md.closes.last ?? 0)
        let gann = gannLevels(price)
        return """
        ## Astro-Cyclical / Gann Layer
        - Lunar phase: \(lunar.name) (\(fmt(lunar.illumination * 100, 1))% illuminated) — fringe cycle input; use only as a tiny confidence modifier.
        - Gann 1×1 anchor: \(fmt(price, 5)) · 45° levels \(gann.map { fmt($0, 5) }.joined(separator: " · "))
        - Policy: astro/Gann can shift confidence by at most a few points; it never overrides structure, regime or risk.
        """
    }

    static func lunarPhase(_ date: Date) -> (name: String, illumination: Double) {
        let synodic = 29.53058867
        let knownNew = Date(timeIntervalSince1970: 947182440) // 2000-01-06 18:14 UTC
        let days = date.timeIntervalSince(knownNew) / 86400
        let age = days.truncatingRemainder(dividingBy: synodic)
        let illumination = (1 - cos(2 * Double.pi * age / synodic)) / 2
        let name: String
        switch age {
        case 0..<1.845: name = "New Moon"
        case 1.845..<5.536: name = "Waxing Crescent"
        case 5.536..<9.228: name = "First Quarter"
        case 9.228..<12.919: name = "Waxing Gibbous"
        case 12.919..<14.765: name = "Full Moon"
        case 14.765..<18.457: name = "Waning Gibbous"
        case 18.457..<22.148: name = "Last Quarter"
        case 22.148..<25.840: name = "Waning Crescent"
        default: name = "Dark Moon"
        }
        return (name, illumination)
    }

    static func gannLevels(_ price: Double) -> [Double] {
        guard price > 0 else { return [] }
        let root = sqrt(price)
        return [-2, -1, 1, 2].map { pow(root + Double($0) * 0.25, 2) }
    }

    // MARK: - Risk / backtesting / correlation / session / anomaly

    static func deepRiskReport(for md: MarketData, accountSize: Double = 0) -> String {
        let plan = BackendQuantEngine.riskPlan(md, accountSize: accountSize)
        let mc = monteCarlo(md.closes, simulations: 400, horizon: 30)
        let r = returns(md.closes).sorted()
        let tail = max(1, Int(Double(r.count) * 0.05))
        let cvar = abs(mean(Array(r.prefix(tail))))
        let stressLoss = cvar * sqrt(30) * accountSize
        return """
        ## Risk & Money Management
        - Stop distance \(fmt(plan.stopDistance, 5)) · target \(fmt(plan.targetDistance, 5)) · R:R \(fmt(plan.riskReward))
        - Kelly \(fmt(plan.kellyFraction * 100, 1))% · capped risk \(fmt(plan.cappedRiskFraction * 100, 2))% · 95% VaR \(fmt(plan.valueAtRisk, 2)) · CVaR \(fmt(plan.conditionalValueAtRisk, 2))
        - 30-bar Monte Carlo: median \(fmt(mc.p50, 5)) · 5% adverse \(fmt(mc.p05, 5)) · P(up) \(fmt(mc.upProbability))
        - Stress note: a tail-volatility month maps to ≈\(fmt(stressLoss, 2)) account-currency drawdown on current sizing assumptions.
        """
    }

    static func walkforwardReport(for md: MarketData) -> String {
        let prices = md.closes
        guard prices.count >= 160 else { return "## Walk-Forward\nNeed at least 160 candles for anchored walk-forward." }
        let segment = prices.count / 4
        var rows: [String] = []
        for i in 0..<3 {
            let train = Array(prices[0..<(segment * (i + 1))])
            let test = Array(prices[(segment * (i + 1))..<min(prices.count, segment * (i + 2))])
            let best = optimizeSMA(train, generations: 18, population: 18)
            let result = BackendQuantEngine.backtest(test, fast: best.fast, slow: best.slow)
            rows.append("Window \(i + 1): best SMA \(best.fast)/\(best.slow) → test \(result.trades) trades · \(fmt(result.netReturn * 100, 2))% net · \(fmt(result.maxDrawdown * 100, 2))% DD")
        }
        let mc = monteCarloTradeShuffle(prices)
        return "## Walk-Forward & Stress\n" + rows.joined(separator: "\n") + "\n- Trade-shuffle stress: median equity \(fmt(mc.median, 3)) · 5% adverse \(fmt(mc.p05, 3)) · 95% favorable \(fmt(mc.p95, 3))"
    }

    static func optimizeSMA(_ prices: [Double], generations: Int = 20, population: Int = 20) -> (fast: Int, slow: Int, score: Double) {
        var genes: [(fast: Int, slow: Int)] = (0..<population).map { _ in (Int.random(in: 3...20), Int.random(in: 21...90)) }
        var best: (fast: Int, slow: Int, score: Double) = (10, 30, -999)
        for _ in 0..<generations {
            let scored = genes.map { gene -> (fast: Int, slow: Int, score: Double) in
                let res = BackendQuantEngine.backtest(prices, fast: min(gene.fast, gene.slow - 1), slow: max(gene.slow, gene.fast + 1))
                let score = res.netReturn - res.maxDrawdown * 0.8 + (res.winRate - 0.5) * 0.15
                return (gene.fast, gene.slow, score)
            }.sorted { $0.score > $1.score }
            if let top = scored.first, top.score > best.score { best = top }
            let survivors = scored.prefix(max(4, population / 4))
            genes = survivors.map { $0.fast == $0.slow ? (3, 30) : ($0.fast, $0.slow) }
            while genes.count < population {
                let parent = survivors.randomElement() ?? (10, 30, 0)
                var fast = parent.fast + Int.random(in: -3...3)
                var slow = parent.slow + Int.random(in: -8...8)
                fast = clamp(Double(fast), 2, 40).roundedInt
                slow = max(fast + 2, clamp(Double(slow), 5, 160).roundedInt)
                genes.append((fast, slow))
            }
        }
        return best
    }

    static func monteCarloTradeShuffle(_ prices: [Double], simulations: Int = 200) -> (median: Double, p05: Double, p95: Double) {
        let base = BackendQuantEngine.backtest(prices)
        guard base.trades > 3 else { return (1, 1, 1) }
        let r = returns(prices)
        var equities: [Double] = []
        for _ in 0..<simulations {
            var equity = 1.0
            for _ in 0..<base.trades {
                let sample = r.randomElement() ?? 0
                equity *= max(0.2, 1 + sample * 8)
            }
            equities.append(equity)
        }
        equities.sort()
        return (equities[equities.count / 2], equities[Int(Double(equities.count) * 0.05)], equities[Int(Double(equities.count) * 0.95)])
    }

    static func correlationMatrix(series: [String: [Double]]) -> String {
        let keys = series.keys.sorted()
        guard keys.count >= 2 else { return "## Correlation Matrix\nNeed cached candles for at least two instruments." }
        var rows = ["| Instrument | " + keys.map { DerivSymbols.display($0) }.joined(separator: " | ") + " |", "|" + String(repeating: "---|", count: keys.count + 1)]
        for a in keys {
            var cells = [DerivSymbols.display(a)]
            for b in keys {
                cells.append(fmt(correlation(series[a] ?? [], series[b] ?? []), 2))
            }
            rows.append("| " + cells.joined(separator: " | ") + " |")
        }
        let avg = averageCorrelation(series)
        return "## Correlation & Divergence Matrix\n" + rows.joined(separator: "\n") + "\n\nAverage absolute correlation: \(fmt(avg)). Above 0.75 means treat signals as one exposure, not independent trades."
    }

    static func correlation(_ a: [Double], _ b: [Double]) -> Double {
        let ra = returns(a), rb = returns(b)
        let n = min(ra.count, rb.count)
        guard n > 5 else { return 0 }
        let x = Array(ra.suffix(n)), y = Array(rb.suffix(n))
        let mx = mean(x), my = mean(y)
        let num = zip(x, y).reduce(0) { $0 + ($1.0 - mx) * ($1.1 - my) }
        let den = sqrt(x.reduce(0) { $0 + pow($1 - mx, 2) } * y.reduce(0) { $0 + pow($1 - my, 2) })
        return den > 0 ? num / den : 0
    }

    static func averageCorrelation(_ series: [String: [Double]]) -> Double {
        let keys = series.keys.sorted()
        var vals: [Double] = []
        for i in 0..<keys.count { for j in (i + 1)..<keys.count { vals.append(abs(correlation(series[keys[i]] ?? [], series[keys[j]] ?? []))) } }
        return mean(vals)
    }

    static func sessionLiquidityReport(for md: MarketData) -> String {
        let label = TradingSession.label()
        let policy = TradingSession.policy(for: md.assetClass)
        let sweeps = liquiditySweeps(md)
        return """
        ## Session & Liquidity Analysis
        - Current session: \(label) · policy base TF \(policy.baseTimeframe.rawValue) · min confidence \(Int(policy.minConfidence))
        - Liquidity sweep scan: \(sweeps.isEmpty ? "no fresh sweep" : sweeps.joined(separator: " · "))
        - Killzone read: London/NY opens deserve faster invalidation; quiet hours favor mean-reversion only when regime is compressed.
        """
    }

    static func liquiditySweeps(_ md: MarketData) -> [String] {
        guard md.candles.count >= 40 else { return [] }
        var out: [String] = []
        let recent = Array(md.candles.suffix(12))
        let priorHigh = md.highs.dropLast(12).suffix(30).max() ?? 0
        let priorLow = md.lows.dropLast(12).suffix(30).min() ?? 0
        for c in recent.suffix(4) {
            if c.high > priorHigh && c.close < priorHigh { out.append("buy-side sweep at \(fmt(c.high, 5))") }
            if c.low < priorLow && c.close > priorLow { out.append("sell-side sweep at \(fmt(c.low, 5))") }
        }
        return out
    }

    static func anomalyReport(for md: MarketData) -> String {
        let r = returns(md.closes)
        guard r.count > 30 else { return "## Anomaly Scan\nNeed at least 30 returns." }
        let m = mean(r), s = max(sd(r), 0.000001)
        let latest = r.last ?? 0
        let z = (latest - m) / s
        let jumps = Microstructure.detectJumps(md.closes, mult: 3.0, lookback: min(180, md.closes.count))
        let volSpike = sd(Array(r.suffix(5))) > sd(Array(r.suffix(30))) * 2.2
        var flags: [String] = []
        if abs(z) > 3 { flags.append("latest return z-score \(fmt(z))") }
        if !jumps.isEmpty { flags.append("\(jumps.count) jump events") }
        if volSpike { flags.append("short-window volatility expansion") }
        return """
        ## Anomaly & Manipulation Detector
        - Status: \(flags.isEmpty ? "no material anomaly" : flags.joined(separator: " · "))
        - Latest z-score: \(fmt(z)) · jump events: \(jumps.count) · volatility spike: \(volSpike ? "yes" : "no")
        - Rule: anomaly flags reduce confidence and widen invalidation; they are not proof of broker manipulation.
        """
    }

    // MARK: - Master backend report

    static func fullBackendReport(for md: MarketData, accountSize: Double = 0) -> String {
        [
            BackendQuantEngine.report(for: md, accountSize: accountSize),
            mathematicalReport(for: md),
            neuralReport(for: md),
            chaosReport(for: md),
            bayesianReport(for: md),
            fuzzyReport(for: md),
            orderFlowReport(for: md),
            harmonicReport(for: md),
            elliottReport(for: md),
            sessionLiquidityReport(for: md),
            anomalyReport(for: md),
            deepRiskReport(for: md, accountSize: accountSize)
        ].joined(separator: "\n\n---\n\n")
    }
}

private extension Double {
    var roundedInt: Int { Int(self.rounded()) }
}
