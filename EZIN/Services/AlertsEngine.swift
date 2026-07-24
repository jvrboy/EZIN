import Foundation
import Combine

// MARK: - Alert Types & Data Models

/// The type of alert condition to evaluate.
enum AlertConditionType: String, Codable, CaseIterable, Identifiable {
    case priceAbove = "Price Above"
    case priceBelow = "Price Below"
    case rsiAbove = "RSI Above"
    case rsiBelow = "RSI Below"
    case macdCrossAbove = "MACD Cross Above Signal"
    case macdCrossBelow = "MACD Cross Below Signal"
    case volatilityAbove = "Volatility Above (ATR-based)"
    case signalGenerated = "Signal Generated"
    case timeBased = "Time-Based"

    var id: String { rawValue }
    var icon: String {
        switch self {
        case .priceAbove: return "arrow.up.to.line"
        case .priceBelow: return "arrow.down.to.line"
        case .rsiAbove: return "arrow.up.circle"
        case .rsiBelow: return "arrow.down.circle"
        case .macdCrossAbove: return "arrow.up.forward"
        case .macdCrossBelow: return "arrow.down.forward"
        case .volatilityAbove: return "bolt"
        case .signalGenerated: return "waveform.path.ecg"
        case .timeBased: return "clock"
        }
    }
}

/// Severity level for an alert.
enum AlertSeverity: String, Codable, CaseIterable, Identifiable {
    case info = "Info"
    case warning = "Warning"
    case critical = "Critical"

    var id: String { rawValue }
    var color: String {
        switch self {
        case .info: return "blue"
        case .warning: return "orange"
        case .critical: return "red"
        }
    }
}

/// A user-defined alert configuration.
struct AlertConfiguration: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var symbol: String
    var conditionType: AlertConditionType
    var conditionValue: Double      // threshold for price/RSI/volatility
    var timeframe: Timeframe = .m15
    var severity: AlertSeverity = .warning
    var enabled: Bool = true
    var repeats: Bool = false       // whether to re-fire after being triggered
    var lastTriggeredAt: Date? = nil
    var createdAt: Date = Date()
    var notes: String = ""

    /// How long to wait before re-triggering this alert (if repeats is true).
    var cooldownMinutes: Int = 60
}

/// A triggered alert event (fired when condition is met).
struct AlertEvent: Codable, Identifiable, Equatable {
    var id = UUID()
    let configID: UUID
    let name: String
    let symbol: String
    let conditionType: AlertConditionType
    let message: String
    let value: Double               // the actual value that triggered it
    let threshold: Double           // the configured threshold
    let timestamp: Date
    let severity: AlertSeverity
    var acknowledged: Bool = false
}

/// Alert evaluation result for a single check.
struct AlertEvaluationResult {
    let alert: AlertConfiguration
    let triggered: Bool
    let currentValue: Double
    let message: String?
}

// MARK: - Alert Store

/// Persistent store for user-defined alerts and their event history.
final class AlertStore: ObservableObject {
    static let shared = AlertStore()

    @Published var configurations: [AlertConfiguration] = []
    @Published var events: [AlertEvent] = []

    private let configsFile = "alert_configs.json"
    private let eventsFile = "alert_events.json"

    private init() {
        load()
    }

    // MARK: - CRUD

    func add(_ config: AlertConfiguration) {
        configurations.append(config)
        save()
    }

    func update(_ config: AlertConfiguration) {
        if let idx = configurations.firstIndex(where: { $0.id == config.id }) {
            configurations[idx] = config
            save()
        }
    }

    func remove(_ config: AlertConfiguration) {
        configurations.removeAll { $0.id == config.id }
        events.removeAll { $0.configID == config.id }
        save()
    }

    func toggle(_ config: AlertConfiguration) {
        var updated = config
        updated.enabled.toggle()
        update(updated)
    }

    func acknowledgeEvent(_ event: AlertEvent) {
        if let idx = events.firstIndex(where: { $0.id == event.id }) {
            var updated = event
            updated.acknowledged = true
            events[idx] = updated
            save()
        }
    }

    func acknowledgeAll() {
        for i in events.indices {
            events[i].acknowledged = true
        }
        save()
    }

    func clearOldEvents(before days: Int = 7) {
        let cutoff = Date().addingTimeInterval(-TimeInterval(days * 86400))
        events.removeAll { $0.timestamp < cutoff }
        save()
    }

    // MARK: - Queries

    var enabledAlerts: [AlertConfiguration] { configurations.filter { $0.enabled } }

    func alerts(for symbol: String) -> [AlertConfiguration] {
        configurations.filter { $0.symbol == symbol }
    }

    var unacknowledgedEvents: [AlertEvent] {
        events.filter { !$0.acknowledged }.sorted { $0.timestamp > $1.timestamp }
    }

    var recentEvents: [AlertEvent] {
        events.sorted { $0.timestamp > $1.timestamp }
    }

    // MARK: - Persistence

    private func save() {
        FileStore.shared.write(configurations, to: configsFile, in: FileStore.shared.dataDir)
        FileStore.shared.write(events, to: eventsFile, in: FileStore.shared.dataDir)
    }

    private func load() {
        configurations = FileStore.shared.read([AlertConfiguration].self, from: configsFile, in: FileStore.shared.dataDir) ?? []
        events = FileStore.shared.read([AlertEvent].self, from: eventsFile, in: FileStore.shared.dataDir) ?? []
    }
}

// MARK: - Alert Evaluation Engine

/// Evaluates all enabled alerts against current market data and fires triggered events.
@MainActor
final class AlertEvaluator: ObservableObject {
    static let shared = AlertEvaluator()

    private let store = AlertStore.shared
    private let deriv: DerivClient?

    private var evaluationTimer: Timer?
    private var cancellables = Set<AnyCancellable>()

    private init(deriv: DerivClient? = nil) {
        self.deriv = deriv
    }

    /// Start periodic evaluation (every 30 seconds).
    func start(evaluateEvery seconds: TimeInterval = 30) {
        stop()
        evaluationTimer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: true) { [weak self] _ in
            Task { [weak self] in
                await self?.evaluateAll()
            }
        }
    }

    /// Stop periodic evaluation.
    func stop() {
        evaluationTimer?.invalidate()
        evaluationTimer = nil
    }

    /// Evaluate all enabled alerts and fire triggered ones.
    func evaluateAll() async {
        let alerts = store.enabledAlerts
        guard !alerts.isEmpty else { return }

        for alert in alerts {
            let result = await evaluate(alert)

            if result.triggered {
                // Check cooldown
                if let lastTriggered = alert.lastTriggeredAt {
                    let cooldown = TimeInterval(alert.cooldownMinutes * 60)
                    if Date().timeIntervalSince(lastTriggered) < cooldown && !alert.repeats {
                        continue
                    }
                }

                let event = AlertEvent(
                    configID: alert.id,
                    name: alert.name,
                    symbol: alert.symbol,
                    conditionType: alert.conditionType,
                    message: result.message ?? "Alert triggered",
                    value: result.currentValue,
                    threshold: alert.conditionValue,
                    timestamp: Date(),
                    severity: alert.severity
                )

                await MainActor.run {
                    store.events.insert(event, at: 0)

                    // Update last triggered time
                    var updated = alert
                    updated.lastTriggeredAt = Date()
                    store.update(updated)

                    // Push notification for critical alerts
                    if alert.severity == .critical {
                        PushNotificationManager.shared.notifyAlertTriggered(event)
                    }
                }
            }
        }
    }

    /// Evaluate a single alert against current market data.
    private func evaluate(_ alert: AlertConfiguration) async -> AlertEvaluationResult {
        // Get current market data
        let data = await fetchMarketData(symbol: alert.symbol, timeframe: alert.timeframe)

        switch alert.conditionType {
        case .priceAbove:
            guard let price = data.currentPrice else {
                return AlertEvaluationResult(alert: alert, triggered: false, currentValue: 0, message: nil)
            }
            let triggered = price > alert.conditionValue
            return AlertEvaluationResult(
                alert: alert, triggered: triggered, currentValue: price,
                message: triggered ? "\(DerivSymbols.display(alert.symbol)) at \(fmt(price)) — above \(fmt(alert.conditionValue))" : nil
            )

        case .priceBelow:
            guard let price = data.currentPrice else {
                return AlertEvaluationResult(alert: alert, triggered: false, currentValue: 0, message: nil)
            }
            let triggered = price < alert.conditionValue
            return AlertEvaluationResult(
                alert: alert, triggered: triggered, currentValue: price,
                message: triggered ? "\(DerivSymbols.display(alert.symbol)) at \(fmt(price)) — below \(fmt(alert.conditionValue))" : nil
            )

        case .rsiAbove:
            guard let candles = data.candles, candles.count >= 14 else {
                return AlertEvaluationResult(alert: alert, triggered: false, currentValue: 0, message: nil)
            }
            let closes = candles.map { $0.close }
            let rsiValues = Indicators.rsi(closes, 14)
            guard let currentRSI = rsiValues.last else {
                return AlertEvaluationResult(alert: alert, triggered: false, currentValue: 0, message: nil)
            }
            let triggered = currentRSI > alert.conditionValue
            return AlertEvaluationResult(
                alert: alert, triggered: triggered, currentValue: currentRSI,
                message: triggered ? "\(DerivSymbols.display(alert.symbol)) RSI at \(fmt(currentRSI)) — above \(fmt(alert.conditionValue))" : nil
            )

        case .rsiBelow:
            guard let candles = data.candles, candles.count >= 14 else {
                return AlertEvaluationResult(alert: alert, triggered: false, currentValue: 0, message: nil)
            }
            let closes = candles.map { $0.close }
            let rsiValues = Indicators.rsi(closes, 14)
            guard let currentRSI = rsiValues.last else {
                return AlertEvaluationResult(alert: alert, triggered: false, currentValue: 0, message: nil)
            }
            let triggered = currentRSI < alert.conditionValue
            return AlertEvaluationResult(
                alert: alert, triggered: triggered, currentValue: currentRSI,
                message: triggered ? "\(DerivSymbols.display(alert.symbol)) RSI at \(fmt(currentRSI)) — below \(fmt(alert.conditionValue))" : nil
            )

        case .macdCrossAbove:
            guard let candles = data.candles, candles.count >= 26 else {
                return AlertEvaluationResult(alert: alert, triggered: false, currentValue: 0, message: nil)
            }
            let closes = candles.map { $0.close }
            let macdResult = Indicators.macd(closes, fast: 12, slow: 26, signal: 9)
            guard macdResult.macd.count >= 2 else {
                return AlertEvaluationResult(alert: alert, triggered: false, currentValue: 0, message: nil)
            }
            let prevMACD = macdResult.macd[macdResult.macd.count - 2]
            let prevSignal = macdResult.signal[macdResult.signal.count - 2]
            let currMACD = macdResult.macd.last!
            let currSignal = macdResult.signal.last!
            let triggered = prevMACD <= prevSignal && currMACD > currSignal
            let diff = currMACD - currSignal
            return AlertEvaluationResult(
                alert: alert, triggered: triggered, currentValue: diff,
                message: triggered ? "\(DerivSymbols.display(alert.symbol)) MACD crossed above signal line" : nil
            )

        case .macdCrossBelow:
            guard let candles = data.candles, candles.count >= 26 else {
                return AlertEvaluationResult(alert: alert, triggered: false, currentValue: 0, message: nil)
            }
            let closes = candles.map { $0.close }
            let macdResult = Indicators.macd(closes, fast: 12, slow: 26, signal: 9)
            guard macdResult.macd.count >= 2 else {
                return AlertEvaluationResult(alert: alert, triggered: false, currentValue: 0, message: nil)
            }
            let prevMACD = macdResult.macd[macdResult.macd.count - 2]
            let prevSignal = macdResult.signal[macdResult.signal.count - 2]
            let currMACD = macdResult.macd.last!
            let currSignal = macdResult.signal.last!
            let triggered = prevMACD >= prevSignal && currMACD < currSignal
            let diff = currMACD - currSignal
            return AlertEvaluationResult(
                alert: alert, triggered: triggered, currentValue: diff,
                message: triggered ? "\(DerivSymbols.display(alert.symbol)) MACD crossed below signal line" : nil
            )

        case .volatilityAbove:
            guard let candles = data.candles, candles.count >= 14 else {
                return AlertEvaluationResult(alert: alert, triggered: false, currentValue: 0, message: nil)
            }
            let highs = candles.map { $0.high }
            let lows = candles.map { $0.low }
            let closes = candles.map { $0.close }
            let atrValues = Indicators.atr(highs, lows, closes, 14)
            guard let currentATR = atrValues.last, let price = data.currentPrice, price > 0 else {
                return AlertEvaluationResult(alert: alert, triggered: false, currentValue: 0, message: nil)
            }
            let atrPercent = currentATR / price
            let triggered = atrPercent * 100 > alert.conditionValue
            return AlertEvaluationResult(
                alert: alert, triggered: triggered, currentValue: atrPercent * 100,
                message: triggered ? "\(DerivSymbols.display(alert.symbol)) volatility at \(fmt(atrPercent * 100))% — above \(fmt(alert.conditionValue))%" : nil
            )

        case .signalGenerated:
            // Signal-based alerts are triggered externally when a signal is generated
            return AlertEvaluationResult(alert: alert, triggered: false, currentValue: 0, message: nil)

        case .timeBased:
            // Time-based alerts fire at specific times (evaluated separately)
            let calendar = Calendar.current
            let hour = calendar.component(.hour, from: Date())
            let minute = calendar.component(.minute, from: Date())
            let currentMinutes = Double(hour * 60 + minute)
            let triggered = abs(currentMinutes - alert.conditionValue) <= 2  // within 2 minutes
            return AlertEvaluationResult(
                alert: alert, triggered: triggered, currentValue: currentMinutes,
                message: triggered ? "Time-based alert: \(alert.name)" : nil
            )
        }
    }

    /// Signal a new signal generated (for signal-based alerts).
    func notifySignalGenerated(symbol: String, type: SignalType, confidence: Double) {
        let signalAlerts = store.enabledAlerts.filter {
            $0.conditionType == .signalGenerated && $0.symbol == symbol
        }
        for alert in signalAlerts {
            let event = AlertEvent(
                configID: alert.id,
                name: alert.name,
                symbol: alert.symbol,
                conditionType: .signalGenerated,
                message: "\(type.rawValue) signal generated for \(DerivSymbols.display(symbol)) at \(Int(confidence))% confidence",
                value: confidence,
                threshold: 50,
                timestamp: Date(),
                severity: alert.severity
            )
            store.events.insert(event, at: 0)
            if alert.severity == .critical {
                PushNotificationManager.shared.notifyAlertTriggered(event)
            }
        }
    }

    // MARK: - Market Data Fetch

    private struct AlertMarketData {
        let currentPrice: Double?
        let candles: [Candle]?
    }

    private func fetchMarketData(symbol: String, timeframe: Timeframe) async -> AlertMarketData {
        let price = await MainActor.run { [weak deriv] in
            return deriv?.prices[symbol]
        }

        // Try to get candles from cache or fetch them
        let candles: [Candle]? = nil  // In production, fetch from DerivClient

        return AlertMarketData(currentPrice: price, candles: candles)
    }

    // MARK: - Helpers

    private func fmt(_ x: Double, _ places: Int = 4) -> String {
        String(format: "%%.\(places)f", x)
    }
}

// MARK: - Push Notification Support for Alerts

extension PushNotificationManager {
    func notifyAlertTriggered(_ event: AlertEvent) {
        let body: String
        switch event.conditionType {
        case .priceAbove, .priceBelow:
            body = "\(DerivSymbols.display(event.symbol)): \(event.message)"
        case .rsiAbove, .rsiBelow:
            body = "RSI alert: \(event.message)"
        case .macdCrossAbove, .macdCrossBelow:
            body = "MACD cross: \(event.message)"
        case .volatilityAbove:
            body = "Volatility spike: \(event.message)"
        case .signalGenerated:
            body = "Signal: \(event.message)"
        case .timeBased:
            body = "⏰ \(event.name)"
        }
        // Use existing push notification infrastructure
        scheduleLocalNotification(title: "EZIN Alert: \(event.severity.rawValue)", body: body)
    }

    private func scheduleLocalNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil  // Deliver immediately
        )

        UNUserNotificationCenter.current().add(request)
    }
}

// MARK: - Alert Tools for the Chat Assistant

extension ToolRegistry {
    /// Create a new alert configuration from the chat.
    mutating func alertCreate(args: [String: Any]) -> String {
        let name = str(args, "name")
        let rawSymbol = str(args, "symbol")
        let symbol = resolveSymbol(rawSymbol)
        let rawCondition = str(args, "condition").lowercased()
        let value = (args["value"] as? Double) ?? Double(str(args, "value")) ?? 0
        let rawTimeframe = str(args, "timeframe")
        let timeframe = rawTimeframe.isEmpty ? Timeframe.m15 : resolveTF(rawTimeframe)
        let rawSeverity = str(args, "severity").lowercased()

        guard !name.isEmpty else { return "alert_create needs a 'name'." }
        guard DerivSymbols.all.contains(symbol) else { return "Unknown symbol: '\(rawSymbol)'. Use instruments() to see available symbols." }
        guard value > 0 else { return "alert_create needs a positive 'value' (price/R indicator threshold)." }

        let conditionType: AlertConditionType
        switch rawCondition {
        case "price_above", "price above", "above": conditionType = .priceAbove
        case "price_below", "price below", "below": conditionType = .priceBelow
        case "rsi_above", "rsi above": conditionType = .rsiAbove
        case "rsi_below", "rsi below": conditionType = .rsiBelow
        case "macd_cross_above", "macd cross above": conditionType = .macdCrossAbove
        case "macd_cross_below", "macd cross below": conditionType = .macdCrossBelow
        case "volatility_above", "volatility above", "vol": conditionType = .volatilityAbove
        case "signal", "signal_generated": conditionType = .signalGenerated
        default: return "Unknown condition type: '\(rawCondition)'. Supported: price_above, price_below, rsi_above, rsi_below, macd_cross_above, macd_cross_below, volatility_above, signal."
        }

        let severity: AlertSeverity
        switch rawSeverity {
        case "critical": severity = .critical
        case "warning", "warn": severity = .warning
        default: severity = .info
        }

        let config = AlertConfiguration(
            name: name,
            symbol: symbol,
            conditionType: conditionType,
            conditionValue: value,
            timeframe: timeframe,
            severity: severity,
            enabled: true
        )

        AlertStore.shared.add(config)

        return """
        ✅ Alert created: **\(name)**
        - Condition: \(conditionType.rawValue) \(fmt(value)) on \(DerivSymbols.display(symbol))
        - Timeframe: \(timeframe.rawValue)
        - Severity: \(severity.rawValue)
        - ID: `\(config.id.uuidString.prefix(8))...`

        The alert evaluator will check conditions every 30 seconds. Use `alert_list` to see all alerts, `alert_delete` to remove.
        """
    }

    /// List all alert configurations and recent events.
    func alertList(args: [String: Any]) -> String {
        let store = AlertStore.shared
        let showEvents = str(args, "events").lowercased() == "true" || str(args, "show_events").lowercased() == "true"

        var report = "## Alert System\n\n"

        let configs = store.configurations
        if configs.isEmpty {
            report += "No alerts configured. Create one with `alert_create`.\n\n"
        } else {
            let enabled = configs.filter { $0.enabled }.count
            let disabled = configs.count - enabled
            report += "**\(configs.count)** alerts · \(enabled) enabled · \(disabled) disabled\n\n"
            report += "| Name | Symbol | Condition | Value | Status |\n|---|---|---|---|---|\n"
            for config in configs.sorted(by: { $0.createdAt > $1.createdAt }) {
                let status = config.enabled ? "🟢 Active" : "🔴 Disabled"
                report += "| \(config.name) | \(DerivSymbols.display(config.symbol)) | \(config.conditionType.rawValue) | \(fmt(config.conditionValue)) | \(status) |\n"
            }
        }

        if showEvents {
            let events = store.recentEvents.prefix(10)
            if !events.isEmpty {
                report += "\n### Recent Events\n\n"
                report += "| Time | Alert | Message |\n|---|---|---|\n"
                for event in events {
                    let time = event.timestamp.formatted(date: .omitted, time: .shortened)
                    report += "| \(time) | \(event.name) | \(event.message.prefix(60)) |\n"
                }
            }
        }

        let unacknowledged = store.unacknowledgedEvents.count
        if unacknowledged > 0 {
            report += "\n⚠️ **\(unacknowledged)** unacknowledged alert event(s). Use `alert_acknowledge(all:)` to clear.\n"
        }

        return report
    }

    /// Delete an alert by name or ID.
    func alertDelete(args: [String: Any]) -> String {
        let query = str(args, "name").isEmpty ? str(args, "id") : str(args, "name")
        guard !query.isEmpty else { return "alert_delete needs a 'name' or 'id'." }

        let store = AlertStore.shared
        let matches = store.configurations.filter {
            $0.name.lowercased().contains(query.lowercased()) || $0.id.uuidString.lowercased().contains(query.lowercased())
        }

        guard !matches.isEmpty else { return "No alert matching '\(query)'." }

        if matches.count == 1 {
            store.remove(matches[0])
            return "Deleted alert '\(matches[0].name)'."
        }

        // Multiple matches — delete all
        for match in matches { store.remove(match) }
        return "Deleted \(matches.count) alerts matching '\(query)'."
    }

    /// Acknowledge alert events.
    func alertAcknowledge(args: [String: Any]) -> String {
        let all = str(args, "all").lowercased() == "true"
        if all {
            AlertStore.shared.acknowledgeAll()
            return "Acknowledged all alert events."
        }

        let query = str(args, "id").isEmpty ? str(args, "name") : str(args, "id")
        guard !query.isEmpty else { return "Specify an event 'id' or use 'all: true'." }

        let store = AlertStore.shared
        let matches = store.events.filter {
            $0.id.uuidString.lowercased().contains(query.lowercased()) || $0.name.lowercased().contains(query.lowercased())
        }

        guard !matches.isEmpty else { return "No events matching '\(query)'." }
        for match in matches { store.acknowledgeEvent(match) }
        return "Acknowledged \(matches.count) event(s)."
    }

    private func fmt(_ x: Double, _ places: Int = 4) -> String {
        String(format: "%%.\(places)f", x)
    }
}
