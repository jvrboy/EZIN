import Foundation

// MARK: - News Item Model

struct NewsItem: Codable, Identifiable, Hashable {
    var id = UUID()
    let title: String
    let summary: String
    let source: String
    let category: NewsCategory
    let sentiment: Sentiment
    let impact: ImpactLevel
    let symbols: [String]
    let publishedAt: Date
    let url: String

    enum NewsCategory: String, Codable, CaseIterable {
        case macroeconomy = "Macro"
        case earnings = "Earnings"
        case centralBank = "Central Bank"
        case geopolitics = "Geopolitics"
        case commodities = "Commodities"
        case crypto = "Crypto"
        case forex = "Forex"
        case technology = "Technology"
        case regulation = "Regulation"
        case marketAnalysis = "Market Analysis"
    }

    enum Sentiment: String, Codable, CaseIterable {
        case bullish = "Bullish"
        case bearish = "Bearish"
        case neutral = "Neutral"
        case veryBullish = "Very Bullish"
        case veryBearish = "Very Bearish"

        var score: Double {
            switch self {
            case .veryBullish: return 1.0
            case .bullish: return 0.5
            case .neutral: return 0.0
            case .bearish: return -0.5
            case .veryBearish: return -1.0
            }
        }

        var color: String {
            switch self {
            case .veryBullish, .bullish: return "green"
            case .neutral: return "yellow"
            case .veryBearish, .bearish: return "red"
            }
        }
    }

    enum ImpactLevel: String, Codable, CaseIterable {
        case low = "Low"
        case medium = "Medium"
        case high = "High"
        case critical = "Critical"

        var weight: Int {
            switch self {
            case .low: return 1
            case .medium: return 2
            case .high: return 3
            case .critical: return 5
            }
        }
    }
}

// MARK: - News Feed Service

@MainActor
final class NewsFeedService: ObservableObject {
    static let shared = NewsFeedService()

    @Published var newsItems: [NewsItem] = []
    @Published var isLoading = false
    @Published var selectedCategory: NewsItem.NewsCategory?
    @Published var searchQuery = ""
    @Published var bookmarkedIDs: Set<UUID> = []

    private let file = "news_feed.json"
    private let bookmarkFile = "news_bookmarks.json"

    private init() {
        load()
        if newsItems.isEmpty {
            generateInitialNews()
        }
    }

    // MARK: - Filtering

    var filteredNews: [NewsItem] {
        var items = newsItems
        if let category = selectedCategory {
            items = items.filter { $0.category == category }
        }
        if !searchQuery.isEmpty {
            let q = searchQuery.lowercased()
            items = items.filter {
                $0.title.lowercased().contains(q) ||
                $0.summary.lowercased().contains(q) ||
                $0.symbols.contains { $0.lowercased().contains(q) }
            }
        }
        return items.sorted { $0.publishedAt > $1.publishedAt }
    }

    var bookmarkedNews: [NewsItem] {
        newsItems.filter { bookmarkedIDs.contains($0.id) }
            .sorted { $0.publishedAt > $1.publishedAt }
    }

    /// News relevant to a specific symbol
    func news(for symbol: String) -> [NewsItem] {
        newsItems.filter { $0.symbols.contains(symbol.uppercased()) }
            .sorted { $0.publishedAt > $1.publishedAt }
    }

    // MARK: - CRUD

    func addNews(_ item: NewsItem) {
        newsItems.insert(item, at: 0)
        save()
    }

    func addBatch(_ items: [NewsItem]) {
        newsItems.insert(contentsOf: items, at: 0)
        save()
    }

    func removeNews(_ id: UUID) {
        newsItems.removeAll { $0.id == id }
        save()
    }

    func toggleBookmark(_ id: UUID) {
        if bookmarkedIDs.contains(id) {
            bookmarkedIDs.remove(id)
        } else {
            bookmarkedIDs.insert(id)
        }
        saveBookmarks()
    }

    func clearAll() {
        newsItems.removeAll()
        save()
    }

    // MARK: - Sentiment Analysis

    /// Analyze sentiment of a text using keyword matching (on-device, no API needed)
    static func analyzeSentiment(of text: String) -> NewsItem.Sentiment {
        let lower = text.lowercased()
        let bullishWords: Set<String> = ["beat", "beats", "surge", "surges", "rally", "rallies",
            "growth", "strong", "upgrade", "record", "profit", "dovish", "stimulus",
            "approval", "bullish", "soar", "soars", "boom", "expansion", "positive",
            "outperform", "breakthrough", "momentum", "recovery", "rebound", "gains"]
        let bearishWords: Set<String> = ["miss", "misses", "crash", "crashes", "selloff",
            "sell-off", "weak", "downgrade", "loss", "losses", "hawkish", "ban",
            "lawsuit", "fraud", "bearish", "fear", "default", "war", "conflict",
            "recession", "inflation", "slowdown", "decline", "plunge", "slump",
            "downturn", "volatility", "uncertainty", "sanctions", "crisis"]

        let words = lower.components(separatedBy: CharacterSet.alphanumerics.inverted)
        let pos = words.filter { bullishWords.contains($0) }.count
        let neg = words.filter { bearishWords.contains($0) }.count

        if pos - neg >= 4 { return .veryBullish }
        if pos - neg >= 1 { return .bullish }
        if neg - pos >= 4 { return .veryBearish }
        if neg - pos >= 1 { return .bearish }
        return .neutral
    }

    // MARK: - Generator

    /// Generate a realistic-looking initial set of market news
    private func generateInitialNews() {
        let now = Date()
        let news: [NewsItem] = [
            // Macro / Central Bank
            NewsItem(title: "Fed Holds Rates Steady at 5.50%, Signals Possible September Cut",
                     summary: "The Federal Reserve maintained its benchmark interest rate at 5.50% for the eighth consecutive meeting. Chair Powell indicated that progress on inflation could pave the way for a rate cut as early as September, citing improving CPI data and cooling labor market conditions.",
                     source: "Reuters", category: .centralBank, sentiment: .bullish,
                     impact: .critical, symbols: ["USD", "SPX500", "NASDAQ"], publishedAt: now.addingTimeInterval(-3600), url: ""),

            NewsItem(title: "ECB Cuts Rates by 25bps to 3.75% — Third Reduction This Year",
                     summary: "The European Central Bank cut its key interest rate by 25 basis points to 3.75%, marking the third cut of the current easing cycle. Lagarde cited weakening growth forecasts and inflation returning toward target as key drivers for the decision.",
                     source: "Bloomberg", category: .centralBank, sentiment: .bearish,
                     impact: .critical, symbols: ["EUR", "EURUSD"], publishedAt: now.addingTimeInterval(-7200), url: ""),

            NewsItem(title: "Bank of Japan Unexpectedly Holds Rates, Yen Drops 1.5%",
                     summary: "The Bank of Japan surprised markets by holding its policy rate steady at 0.25%, defying expectations of a hike. Governor Ueda cited the need to assess the economic impact of recent yen volatility before further normalization.",
                     source: "Nikkei", category: .centralBank, sentiment: .bearish,
                     impact: .high, symbols: ["JPY", "USDJPY"], publishedAt: now.addingTimeInterval(-10800), url: ""),

            // Earnings
            NewsItem(title: "Nvidia Reports Record $35B Quarterly Revenue, AI Demand Surges 200%",
                     summary: "Nvidia shattered expectations with Q2 revenue of $35 billion, driven by insatiable demand for its H100 and next-gen Blackwell AI chips. Data center revenue alone hit $30.5 billion, up 217% year-over-year.",
                     source: "Financial Times", category: .earnings, sentiment: .veryBullish,
                     impact: .high, symbols: ["NASDAQ"], publishedAt: now.addingTimeInterval(-1800), url: ""),

            NewsItem(title: "Tesla Deliveries Miss Estimates — Stock Drops 4% in After-Hours",
                     summary: "Tesla reported quarterly deliveries of 435,000 vehicles, missing analyst estimates of 462,000. The company cited production bottlenecks and softening EV demand in key markets. Margins also came under pressure.",
                     source: "CNBC", category: .earnings, sentiment: .bearish,
                     impact: .high, symbols: ["NASDAQ"], publishedAt: now.addingTimeInterval(-36000), url: ""),

            // Geo-politics
            NewsItem(title: "US-China Trade Talks Resume — Tariff Reduction Expected on Consumer Goods",
                     summary: "Trade negotiations between the US and China have resumed after a three-month hiatus. Sources indicate both sides are close to an agreement that would reduce tariffs on consumer goods by up to 50%, potentially boosting global trade sentiment.",
                     source: "Bloomberg", category: .geopolitics, sentiment: .bullish,
                     impact: .high, symbols: ["USD", "CNY", "SPX500"], publishedAt: now.addingTimeInterval(-86400), url: ""),

            // Commodities
            NewsItem(title: "Gold Hits New All-Time High at $2,580 — Safe Haven Demand Intensifies",
                     summary: "Gold prices surged to a new record of $2,580 per ounce, driven by escalating geopolitical tensions, rate cut expectations, and strong central bank buying. Analysts see a path to $3,000 within 12 months.",
                     source: "Reuters", category: .commodities, sentiment: .bullish,
                     impact: .high, symbols: ["Gold"], publishedAt: now.addingTimeInterval(-5400), url: ""),

            NewsItem(title: "Crude Oil Drops 3% on OPEC+ Surplus Output — Brent Under $78",
                     summary: "Crude oil prices tumbled after OPEC+ data revealed surplus production exceeding quotas by 400,000 bpd. Saudi Arabia signaled willingness to tolerate lower prices to maintain market share, sending Brent crude below $78.",
                     source: "S&P Global", category: .commodities, sentiment: .bearish,
                     impact: .high, symbols: ["Oil"], publishedAt: now.addingTimeInterval(-21600), url: ""),

            // Crypto
            NewsItem(title: "Bitcoin Consolidates Above $68K — ETF Inflows Hit $1.2B Weekly",
                     summary: "Bitcoin held support above $68,000 as spot ETF inflows accelerated to a record $1.2 billion in the past week. Institutional adoption continues to grow with major asset managers increasing crypto allocations.",
                     source: "CoinDesk", category: .crypto, sentiment: .bullish,
                     impact: .high, symbols: ["BTC"], publishedAt: now.addingTimeInterval(-14400), url: ""),

            NewsItem(title: "Ethereum Layer-2 Volume Surpasses Ethereum Mainnet for First Time",
                     summary: "Combined transaction volume across Ethereum Layer-2 networks (Arbitrum, Optimism, Base, zkSync) exceeded Ethereum mainnet for the first time, processing $3.8B in daily volume. The milestone signals mainstream L2 adoption.",
                     source: "The Block", category: .crypto, sentiment: .bullish,
                     impact: .medium, symbols: ["ETH"], publishedAt: now.addingTimeInterval(-28800), url: ""),

            // Forex
            NewsItem(title: "GBP/USD Breaks Above 1.3200 — UK Services PMI Unexpectedly Rises",
                     summary: "Sterling surged past 1.3200 against the dollar for the first time since March 2024 after UK Services PMI came in at 54.2, well above the expected 52.0. The data suggests the UK economy is gaining momentum.",
                     source: "ForexLive", category: .forex, sentiment: .bullish,
                     impact: .medium, symbols: ["GBP", "GBPUSD"], publishedAt: now.addingTimeInterval(-25200), url: ""),

            NewsItem(title: "USD/JPY Spikes to 152.50 After BoJ Hold — Carry Trade Demand Returns",
                     summary: "The yen weakened sharply after the Bank of Japan's decision to hold rates, pushing USD/JPY to 152.50. The wide interest rate differential continues to fuel carry trade demand, with speculators adding to short yen positions.",
                     source: "DailyFX", category: .forex, sentiment: .bearish,
                     impact: .high, symbols: ["JPY", "USDJPY"], publishedAt: now.addingTimeInterval(-32400), url: ""),

            // Technology
            NewsItem(title: "Apple Launches AI-Powered Trading Platform — Integrates Real-Time Derivatives",
                     summary: "Apple announced a new AI-powered trading platform integrated with real-time derivatives data, creating a direct threat to traditional brokerages. The platform leverages the company's on-device AI chips for low-latency analysis.",
                     source: "TechCrunch", category: .technology, sentiment: .neutral,
                     impact: .medium, symbols: ["NASDAQ"], publishedAt: now.addingTimeInterval(-43200), url: ""),

            // Regulation
            NewsItem(title: "EU Approves Comprehensive Crypto Regulation Framework — MiCA Takes Full Effect",
                     summary: "The European Union's Markets in Crypto-Assets (MiCA) regulation has taken full effect, providing a comprehensive legal framework for cryptocurrency exchanges, custodians, and stablecoin issuers across all 27 member states.",
                     source: "Reuters", category: .regulation, sentiment: .bullish,
                     impact: .medium, symbols: ["BTC", "ETH"], publishedAt: now.addingTimeInterval(-64800), url: ""),

            // Market Analysis
            NewsItem(title: "VIX Falls Below 12 — Market Calm Raises Caution Among Contrarian Traders",
                     summary: "The VIX volatility index has fallen below 12, indicating extremely low market fear. Contrarian analysts warn that extended periods of low volatility often precede sharp reversals, advising caution on leveraged positions.",
                     source: "Seeking Alpha", category: .marketAnalysis, sentiment: .neutral,
                     impact: .medium, symbols: ["SPX500", "VIX"], publishedAt: now.addingTimeInterval(-50400), url: ""),

            NewsItem(title: "S&P 500 Q2 Earnings Beat Rate Hits 82% — Above 5-Year Average",
                     summary: "With 92% of S&P 500 companies having reported Q2 earnings, the beat rate of 82% exceeds both the 5-year average of 77% and the 10-year average of 74%. Technology and healthcare sectors led the upside surprises.",
                     source: "FactSet", category: .earnings, sentiment: .bullish,
                     impact: .medium, symbols: ["SPX500", "NASDAQ"], publishedAt: now.addingTimeInterval(-93600), url: ""),

            // Geopolitics / Energy
            NewsItem(title: "China Announces $580B Infrastructure Stimulus — Metals Prices Rally",
                     summary: "China unveiled a massive $580 billion infrastructure stimulus package focused on renewable energy, high-speed rail, and urban development. Industrial metals including copper, aluminum, and steel futures surged on the news.",
                     source: "Reuters", category: .geopolitics, sentiment: .bullish,
                     impact: .high, symbols: ["CNY", "Copper"], publishedAt: now.addingTimeInterval(-75600), url: ""),

        ]
        newsItems = news
        save()
    }

    /// Generate a fresh news item from a headline (used by chat tool)
    static func generateFromHeadline(_ headline: String, source: String = "AI Feed") -> NewsItem {
        let sentiment = analyzeSentiment(of: headline)
        let lower = headline.lowercased()

        // Determine category
        let category: NewsItem.NewsCategory
        if lower.contains("fed") || lower.contains("ecb") || lower.contains("boj") || lower.contains("rate") || lower.contains("central bank") || lower.contains("monetary") {
            category = .centralBank
        } else if lower.contains("earnings") || lower.contains("revenue") || lower.contains("profit") || lower.contains("quarter") || lower.contains("dividend") {
            category = .earnings
        } else if lower.contains("bitcoin") || lower.contains("crypto") || lower.contains("ethereum") || lower.contains("blockchain") || lower.contains("defi") {
            category = .crypto
        } else if lower.contains("eur") || lower.contains("gbp") || lower.contains("jpy") || lower.contains("forex") || lower.contains("currency") || lower.contains("dollar") {
            category = .forex
        } else if lower.contains("oil") || lower.contains("gold") || lower.contains("copper") || lower.contains("commodity") || lower.contains("silver") {
            category = .commodities
        } else if lower.contains("war") || lower.contains("sanction") || lower.contains("trade") || lower.contains("china") || lower.contains("russia") {
            category = .geopolitics
        } else if lower.contains("sec") || lower.contains("regulation") || lower.contains("compliance") || lower.contains("legal") {
            category = .regulation
        } else if lower.contains("ai") || lower.contains("apple") || lower.contains("tech") || lower.contains("nvidia") || lower.contains("software") {
            category = .technology
        } else {
            category = .marketAnalysis
        }

        // Determine impact
        let impact: NewsItem.ImpactLevel
        if sentiment == .veryBullish || sentiment == .veryBearish {
            impact = .high
        } else {
            impact = .medium
        }

        return NewsItem(
            title: headline,
            summary: "AI-generated market commentary based on the latest trading data and news feeds.",
            source: source,
            category: category,
            sentiment: sentiment,
            impact: impact,
            symbols: [],
            publishedAt: Date(),
            url: ""
        )
    }

    // MARK: - Persistence

    private func load() {
        newsItems = FileStore.shared.read([NewsItem].self, from: file, in: FileStore.shared.dataDir) ?? []
        bookmarkedIDs = FileStore.shared.read(Set<UUID>.self, from: bookmarkFile, in: FileStore.shared.dataDir) ?? []
    }

    private func save() {
        FileStore.shared.write(newsItems, to: file, in: FileStore.shared.dataDir)
    }

    private func saveBookmarks() {
        FileStore.shared.write(bookmarkedIDs, to: bookmarkFile, in: FileStore.shared.dataDir)
    }
}
