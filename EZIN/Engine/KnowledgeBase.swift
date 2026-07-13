import Foundation

/// On-device knowledge base. Loads the bundled trading "brain" JSON modules
/// (multi-timeframe confluence, price action, spike detection, risk, etc.) and
/// exposes their rules to the analysis engine and the chat assistant — so EZIN
/// reasons from a real methodology instead of ad-hoc single-timeframe reads.
///
/// All modules live in the app bundle (Resources/Knowledge). Loading is lazy and
/// fully defensive: a missing or malformed file simply yields no facts.
final class KnowledgeBase {
    static let shared = KnowledgeBase()

    /// Module file (without extension) -> parsed JSON object.
    private(set) var modules: [String: [String: Any]] = [:]
    private var loaded = false

    /// Every knowledge module bundled with the app.
    private let moduleNames = [
        "brain-core", "multi-timeframe-confluence", "technical-analysis",
        "candlestick-patterns", "spike-detection", "deriv-synthetics",
        "perpetual-scalping", "advanced-price-action", "signal-engine",
        "risk-management", "strategies", "self-learning", "realtime-data",
        "tools-usage", "conversation", "forex-analysis-brain", "prometheus-brain"
    ]

    private init() {}

    func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        for name in moduleNames {
            guard let url = Bundle.main.url(forResource: name, withExtension: "json"),
                  let data = try? Data(contentsOf: url),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { continue }
            modules[name] = obj
        }
    }

    var isLoaded: Bool { loadIfNeeded(); return !modules.isEmpty }

    /// Core principles the whole system must obey (from brain-core.json).
    func corePrinciples() -> [String] {
        loadIfNeeded()
        return (modules["brain-core"]?["corePrinciples"] as? [String]) ?? [
            "Analyse ALL timeframes before giving any signal (M1, M5, M15, H1, H4, D1).",
            "Confirm bias first: higher-timeframe trend defines bias, lower timeframe gives entry.",
            "Require a minimum of 3 independent confluences before a signal is valid.",
            "Classify every setup as TREND or COUNTER-TREND and weight trend setups higher."
        ]
    }

    /// Human-readable role for a timeframe, from the multi-timeframe module.
    func role(for tf: Timeframe) -> String {
        loadIfNeeded()
        let key: String
        switch tf {
        case .d1: key = "D1"; case .h4: key = "H4"; case .h1: key = "H1"
        case .m30: key = "M15"; case .m15: key = "M15"; case .m5: key = "M5"; case .m1: key = "M1"
        }
        if let roles = modules["multi-timeframe-confluence"]?["timeframeRoles"] as? [String: Any],
           let entry = roles[key] as? [String: Any], let role = entry["role"] as? String {
            return role
        }
        switch tf {
        case .d1: return "macro bias"; case .h4: return "swing bias"; case .h1: return "operational trend"
        case .m30, .m15: return "setup timeframe"; case .m5: return "refinement"; case .m1: return "execution"
        }
    }

    /// A compact knowledge summary injected into the chat system prompt.
    func systemContext() -> String {
        loadIfNeeded()
        guard isLoaded else { return "" }
        let principles = corePrinciples().prefix(6).map { "- \($0)" }.joined(separator: "\n")
        return """
        You have an on-device trading knowledge base (\(modules.count) modules: multi-timeframe \
        confluence, ICT/SMC price action, candlestick patterns, spike detection for Boom/Crash, \
        Deriv synthetics, risk management, and more). Reason from these principles:
        \(principles)
        When asked to analyse an instrument, ALWAYS call the `analyze` tool — it runs the full \
        top-down multi-timeframe engine — and present its report; never answer an analysis request \
        from a single timeframe or from memory alone.
        """
    }
}
