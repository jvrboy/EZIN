import Foundation

struct ChatAgent: Identifiable { let id = UUID(); let name: String; let role: String }
struct ChatPipeline: Identifiable { let id = UUID(); let name: String; let steps: [String] }

/// The hidden multi-agent + pipeline catalog that powers the Chat tab's backend.
enum AgentRegistry {
    static let agents: [ChatAgent] = [
        .init(name: "Orchestrator", role: "routes tasks to the right specialist and tools"),
        .init(name: "MarketAnalyst", role: "synthesizes full technical analysis"),
        .init(name: "TrendSpecialist", role: "EMA stack, Supertrend, ADX trend calls"),
        .init(name: "MeanReversionSpecialist", role: "ranges, Bollinger, reversals"),
        .init(name: "VolatilitySpecialist", role: "ATR, regime, spike detection"),
        .init(name: "VolumeSpecialist", role: "OBV, MFI, CMF money flow"),
        .init(name: "DivergenceSpecialist", role: "RSI/MACD divergences"),
        .init(name: "IchimokuSpecialist", role: "Kumo cloud and TK cross"),
        .init(name: "BreakoutSpecialist", role: "Keltner/Donchian channel breaks"),
        .init(name: "RiskManager", role: "position sizing and protective stops"),
        .init(name: "TradeExecutor", role: "places and manages Deriv trades"),
        .init(name: "SyntheticsExpert", role: "Boom/Crash/Volatility/Jump behavior"),
        .init(name: "ForexExpert", role: "FX pairs and trading sessions"),
        .init(name: "CryptoExpert", role: "crypto market structure"),
        .init(name: "CommoditiesExpert", role: "metals and energy"),
        .init(name: "IndicesExpert", role: "global stock indices"),
        .init(name: "NewsAnalyst", role: "macro and news context"),
        .init(name: "SentimentAnalyst", role: "crowd sentiment reading"),
        .init(name: "BacktestAnalyst", role: "evaluates strategy performance"),
        .init(name: "PortfolioManager", role: "exposure and correlation"),
        .init(name: "SignalReviewer", role: "validates council signals"),
        .init(name: "PatternRecognizer", role: "chart pattern detection"),
        .init(name: "CandlestickReader", role: "candlestick pattern reading"),
        .init(name: "SupportResistanceMapper", role: "key price levels"),
        .init(name: "ElliottWaveAnalyst", role: "wave counts"),
        .init(name: "FibonacciAnalyst", role: "retracements and extensions"),
        .init(name: "MoneyFlowAnalyst", role: "CMF/MFI/OBV flow"),
        .init(name: "CorrelationAnalyst", role: "inter-market correlation"),
        .init(name: "SessionTimingAgent", role: "optimal entry timing"),
        .init(name: "MT5Bridge", role: "talks to MetaTrader 5 via MCP"),
        .init(name: "TradingViewBridge", role: "TradingView data via MCP"),
        .init(name: "WebResearcher", role: "web scraping and automation via MCP"),
        .init(name: "CodeRunner", role: "runs code/scripts via an MCP executor"),
        .init(name: "DataWrangler", role: "transforms and summarizes datasets"),
        .init(name: "Explainer", role: "teaches trading concepts"),
        .init(name: "GeneralAssistant", role: "handles anything outside trading")
    ]

    static let pipelines: [ChatPipeline] = [
        .init(name: "Full Technical Analysis", steps: ["fetch", "indicators", "agents", "council", "summary"]),
        .init(name: "Quick Signal", steps: ["fetch", "council", "emit"]),
        .init(name: "Multi-Timeframe Scan", steps: ["m1", "m5", "m15", "align"]),
        .init(name: "Trend Confluence", steps: ["ema", "supertrend", "adx", "score"]),
        .init(name: "Reversal Hunter", steps: ["bollinger", "stoch", "divergence", "score"]),
        .init(name: "Breakout Detector", steps: ["donchian", "keltner", "volume", "confirm"]),
        .init(name: "Volatility Regime", steps: ["atr", "histvol", "regime"]),
        .init(name: "Money Flow Check", steps: ["obv", "mfi", "cmf", "score"]),
        .init(name: "Ichimoku Read", steps: ["cloud", "tk", "chikou"]),
        .init(name: "Divergence Sweep", steps: ["rsi", "macd", "detect"]),
        .init(name: "Risk Sizing", steps: ["balance", "atr", "size"]),
        .init(name: "Trade Placement", steps: ["proposal", "confirm", "buy", "track"]),
        .init(name: "Position Review", steps: ["open", "pnl", "manage"]),
        .init(name: "History Report", steps: ["profit_table", "stats"]),
        .init(name: "Synthetics Screener", steps: ["volatility", "boomcrash", "rank"]),
        .init(name: "Forex Session Plan", steps: ["session", "pairs", "bias"]),
        .init(name: "Crypto Momentum", steps: ["roc", "rsi", "rank"]),
        .init(name: "Index Overview", steps: ["indices", "trend", "summary"]),
        .init(name: "News Impact", steps: ["fetch_news", "classify", "impact"]),
        .init(name: "Sentiment Pulse", steps: ["scrape", "score"]),
        .init(name: "Correlation Matrix", steps: ["returns", "corr", "cluster"]),
        .init(name: "Pattern Scan", steps: ["candles", "patterns", "flag"]),
        .init(name: "Support/Resistance Map", steps: ["pivots", "levels"]),
        .init(name: "Fibonacci Plan", steps: ["swing", "retrace", "targets"]),
        .init(name: "Elliott Count", steps: ["waves", "label"]),
        .init(name: "Backtest Strategy", steps: ["rules", "replay", "metrics"]),
        .init(name: "Portfolio Exposure", steps: ["positions", "exposure", "warn"]),
        .init(name: "Watchlist Build", steps: ["filter", "rank", "save"]),
        .init(name: "Alert Setup", steps: ["condition", "watch", "notify"]),
        .init(name: "MT5 Sync", steps: ["mcp_connect", "account", "positions"]),
        .init(name: "MT5 Place Order", steps: ["mcp_connect", "order", "confirm"]),
        .init(name: "TradingView Snapshot", steps: ["mcp_connect", "chart", "analyze"]),
        .init(name: "TradingView Screener", steps: ["mcp_connect", "screen", "rank"]),
        .init(name: "Web Research", steps: ["mcp_scrape", "extract", "summarize"]),
        .init(name: "Web Automation", steps: ["mcp_navigate", "act", "report"]),
        .init(name: "Code Execute", steps: ["mcp_run", "capture", "return"]),
        .init(name: "Data Transform", steps: ["parse", "transform", "summarize"]),
        .init(name: "Report Builder", steps: ["gather", "format", "deliver"]),
        .init(name: "Concept Explainer", steps: ["question", "teach", "example"]),
        .init(name: "Strategy Designer", steps: ["goal", "rules", "validate"]),
        .init(name: "Scalp Plan", steps: ["m1", "fast_ind", "entries"]),
        .init(name: "Swing Plan", steps: ["h4", "trend", "levels"]),
        .init(name: "Session Timing", steps: ["clock", "liquidity", "windows"]),
        .init(name: "Anomaly Detector", steps: ["zscore", "spike", "flag"]),
        .init(name: "Confidence Calibrator", steps: ["votes", "weight", "score"]),
        .init(name: "Trade Journal", steps: ["log", "tag", "review"]),
        .init(name: "Performance Review", steps: ["trades", "stats", "insights"]),
        .init(name: "Regime Switch", steps: ["detect", "adapt", "reconfigure"]),
        .init(name: "News + Technicals Fusion", steps: ["news", "technicals", "decide"]),
        .init(name: "General QA", steps: ["understand", "answer"])
    ]

    static func systemContext() -> String {
        "You are backed by \(agents.count) specialist agents and \(pipelines.count) analysis pipelines. " +
        "Route each request internally to the best specialist(s). Key specialists include: " +
        agents.prefix(14).map { $0.name }.joined(separator: ", ") + ", and more."
    }
}
