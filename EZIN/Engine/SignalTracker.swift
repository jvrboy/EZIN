import Foundation
import Combine

/// Real-time signal performance tracker that monitors signal accuracy and enables self-improvement
final class SignalTracker: ObservableObject {
    
    struct SignalPerformance: Codable, Identifiable {
        let id: UUID
        let signal: TradingSignal
        let entryPrice: Double
        let entryTime: Date
        var exitPrice: Double? = nil
        var exitTime: Date? = nil
        var profit: Double? = nil
        var profitPercent: Double? = nil
        var status: SignalStatus = .active
        var accuracy: Double? = nil  // 0-1, how close to target
        var timeToProfit: TimeInterval? = nil
        var notes: String = ""
        
        enum SignalStatus: String, Codable {
            case active, closed, expired, cancelled
        }
        
        var isWinning: Bool {
            guard let profit = profit else { return false }
            return profit > 0
        }
    }
    
    struct PerformanceMetrics: Codable {
        var totalSignals: Int = 0
        var winningSignals: Int = 0
        var losingSignals: Int = 0
        var winRate: Double { totalSignals > 0 ? Double(winningSignals) / Double(totalSignals) : 0 }
        var averageProfit: Double = 0
        var averageLoss: Double = 0
        var profitFactor: Double { averageLoss != 0 ? averageProfit / abs(averageLoss) : 0 }
        var totalProfit: Double = 0
        var bestTrade: Double = 0
        var worstTrade: Double = 0
        var averageTimeToProfit: TimeInterval = 0
        var lastUpdated: Date = Date()
    }
    
    @Published var activeSignals: [SignalPerformance] = []
    @Published var closedSignals: [SignalPerformance] = []
    @Published var metrics: PerformanceMetrics = PerformanceMetrics()
    
    private let storageKey = "signal_tracker.performance"
    private let metricsKey = "signal_tracker.metrics"
    private var updateTimer: Timer?
    
    init() {
        loadPerformanceData()
        startRealTimeUpdates()
    }
    
    deinit {
        stopRealTimeUpdates()
    }
    
    /// Track a new signal
    func trackSignal(_ signal: TradingSignal, currentPrice: Double) {
        let performance = SignalPerformance(
            id: UUID(),
            signal: signal,
            entryPrice: currentPrice,
            entryTime: Date()
        )
        
        activeSignals.append(performance)
        metrics.totalSignals += 1
        savePerformanceData()
    }
    
    /// Update signal with current market price (real-time)
    func updateSignalPrice(_ signalId: UUID, currentPrice: Double) {
        guard let index = activeSignals.firstIndex(where: { $0.id == signalId }) else { return }
        
        var performance = activeSignals[index]
        let pnl = performance.signal.type.direction.isBullish
            ? currentPrice - performance.entryPrice
            : performance.entryPrice - currentPrice
        
        performance.profit = pnl
        performance.profitPercent = (pnl / performance.entryPrice) * 100
        
        // Check if take profit or stop loss hit
        if performance.signal.type.direction.isBullish {
            if currentPrice >= performance.signal.takeProfit {
                closeSignal(signalId, exitPrice: currentPrice, status: .closed)
                return
            } else if currentPrice <= performance.signal.stopLoss {
                closeSignal(signalId, exitPrice: currentPrice, status: .closed)
                return
            }
        } else {
            if currentPrice <= performance.signal.takeProfit {
                closeSignal(signalId, exitPrice: currentPrice, status: .closed)
                return
            } else if currentPrice >= performance.signal.stopLoss {
                closeSignal(signalId, exitPrice: currentPrice, status: .closed)
                return
            }
        }
        
        // Check if signal expired
        if Date() > performance.signal.expiresAt {
            closeSignal(signalId, exitPrice: currentPrice, status: .expired)
            return
        }
        
        activeSignals[index] = performance
    }
    
    /// Close a signal with final price
    func closeSignal(_ signalId: UUID, exitPrice: Double, status: SignalPerformance.SignalStatus) {
        guard let index = activeSignals.firstIndex(where: { $0.id == signalId }) else { return }
        
        var performance = activeSignals[index]
        performance.exitPrice = exitPrice
        performance.exitTime = Date()
        performance.status = status
        
        let pnl = performance.signal.type.direction.isBullish
            ? exitPrice - performance.entryPrice
            : performance.entryPrice - exitPrice
        
        performance.profit = pnl
        performance.profitPercent = (pnl / performance.entryPrice) * 100
        
        if let exitTime = performance.exitTime {
            performance.timeToProfit = exitTime.timeIntervalSince(performance.entryTime)
        }
        
        // Calculate accuracy (how close to target)
        let distanceToTP = abs(performance.signal.takeProfit - exitPrice)
        let distanceToSL = abs(performance.signal.stopLoss - exitPrice)
        let totalDistance = abs(performance.signal.takeProfit - performance.signal.stopLoss)
        performance.accuracy = max(0, 1 - (min(distanceToTP, distanceToSL) / totalDistance))
        
        // Update metrics
        if performance.isWinning {
            metrics.winningSignals += 1
            metrics.averageProfit = ((metrics.averageProfit * Double(metrics.winningSignals - 1)) + pnl) / Double(metrics.winningSignals)
            metrics.bestTrade = max(metrics.bestTrade, pnl)
        } else {
            metrics.losingSignals += 1
            metrics.averageLoss = ((metrics.averageLoss * Double(metrics.losingSignals - 1)) + pnl) / Double(metrics.losingSignals)
            metrics.worstTrade = min(metrics.worstTrade, pnl)
        }
        
        metrics.totalProfit += pnl
        
        if let timeToProfit = performance.timeToProfit {
            let totalTime = metrics.averageTimeToProfit * TimeInterval(metrics.totalSignals - 1)
            metrics.averageTimeToProfit = (totalTime + timeToProfit) / TimeInterval(metrics.totalSignals)
        }
        
        metrics.lastUpdated = Date()
        
        // Move to closed signals
        activeSignals.remove(at: index)
        closedSignals.append(performance)
        savePerformanceData()
    }
    
    /// Get recommendations for signal improvement based on performance
    func getImprovementRecommendations() -> [String] {
        var recommendations: [String] = []
        
        guard metrics.totalSignals >= 10 else {
            recommendations.append("Need at least 10 signals for reliable recommendations")
            return recommendations
        }
        
        // Win rate analysis
        if metrics.winRate < 0.5 {
            recommendations.append("Win rate below 50%. Consider stricter entry filters or better confluence checks.")
        } else if metrics.winRate > 0.7 {
            recommendations.append("Excellent win rate. Consider increasing position size.")
        }
        
        // Profit factor analysis
        if metrics.profitFactor < 1.0 {
            recommendations.append("Profit factor below 1.0. Average losses exceed average profits. Review risk management.")
        } else if metrics.profitFactor > 2.0 {
            recommendations.append("Strong profit factor. Current strategy is working well.")
        }
        
        // Time to profit analysis
        if metrics.averageTimeToProfit > TimeInterval(30 * 60) {
            recommendations.append("Average time to profit is high. Consider shorter timeframe analysis.")
        }
        
        // Best/worst trade analysis
        let range = metrics.bestTrade - metrics.worstTrade
        if range > metrics.bestTrade * 2 {
            recommendations.append("High variance in trade outcomes. Improve entry consistency.")
        }
        
        // Accuracy analysis
        let avgAccuracy = closedSignals.compactMap { $0.accuracy }.reduce(0, +) / Double(max(1, closedSignals.count))
        if avgAccuracy < 0.5 {
            recommendations.append("Low accuracy to targets. Adjust stop loss and take profit levels.")
        }
        
        return recommendations
    }
    
    /// Export performance report
    func generatePerformanceReport() -> String {
        var report = "=== SIGNAL PERFORMANCE REPORT ===\n\n"
        report += "Generated: \(DateFormatter.localizedString(from: metrics.lastUpdated, dateStyle: .medium, timeStyle: .short))\n\n"
        
        report += "OVERALL METRICS\n"
        report += "Total Signals: \(metrics.totalSignals)\n"
        report += "Winning: \(metrics.winningSignals) (\(String(format: "%.1f", metrics.winRate * 100))%)\n"
        report += "Losing: \(metrics.losingSignals)\n"
        report += "Total Profit: \(String(format: "%.2f", metrics.totalProfit))\n\n"
        
        report += "PROFITABILITY\n"
        report += "Average Win: \(String(format: "%.2f", metrics.averageProfit))\n"
        report += "Average Loss: \(String(format: "%.2f", metrics.averageLoss))\n"
        report += "Profit Factor: \(String(format: "%.2f", metrics.profitFactor))\n"
        report += "Best Trade: \(String(format: "%.2f", metrics.bestTrade))\n"
        report += "Worst Trade: \(String(format: "%.2f", metrics.worstTrade))\n\n"
        
        report += "TIMING\n"
        let hours = metrics.averageTimeToProfit / 3600
        report += "Avg Time to Profit: \(String(format: "%.1f", hours)) hours\n\n"
        
        report += "RECOMMENDATIONS\n"
        for (index, rec) in getImprovementRecommendations().enumerated() {
            report += "\(index + 1). \(rec)\n"
        }
        
        return report
    }
    
    // MARK: - Real-time Updates
    
    private func startRealTimeUpdates() {
        updateTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            self?.updateActiveSignals()
        }
    }
    
    private func stopRealTimeUpdates() {
        updateTimer?.invalidate()
        updateTimer = nil
    }
    
    private func updateActiveSignals() {
        // This would be called by the main app loop to update signal prices
        // Implementation depends on real-time price feed integration
    }
    
    // MARK: - Persistence
    
    private func savePerformanceData() {
        let data = (activeSignals + closedSignals).map { $0.id.uuidString }
        UserDefaults.standard.set(data, forKey: storageKey)
        
        if let encoded = try? JSONEncoder().encode(metrics) {
            UserDefaults.standard.set(encoded, forKey: metricsKey)
        }
    }
    
    private func loadPerformanceData() {
        if let encoded = UserDefaults.standard.data(forKey: metricsKey),
           let decoded = try? JSONDecoder().decode(PerformanceMetrics.self, from: encoded) {
            metrics = decoded
        }
    }
}
