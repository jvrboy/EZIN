import Foundation

/// Enhanced Skills Extension — skill templates, categories, import/export, marketplace
@MainActor
final class SkillsExtensionService: ObservableObject {
    static let shared = SkillsExtensionService()
    
    @Published var userSkills: [ExtendedSkill] = []
    @Published var importedSkills: [ExtendedSkill] = []
    @Published var skillCategories: [SkillCategory] = SkillCategory.allCases
    
    private let file = "extended_skills.json"
    
    private init() {
        load()
        if userSkills.isEmpty { seedDefaults() }
    }
    
    // MARK: - Models
    
    struct ExtendedSkill: Codable, Identifiable, Hashable {
        var id = UUID()
        var name: String
        var category: SkillCategory
        var description: String
        var promptTemplate: String
        var tools: [String]
        var executionScript: String?
        var parameters: [String: String]
        var version: String
        var isBuiltIn: Bool
        var createdAt: Date
        var lastUsed: Date?
        var useCount: Int
        
        func hash(into hasher: inout Hasher) { hasher.combine(id) }
        static func == (lhs: ExtendedSkill, rhs: ExtendedSkill) -> Bool { lhs.id == rhs.id }
    }
    
    enum SkillCategory: String, Codable, CaseIterable {
        case analysis = "Analysis"
        case trading = "Trading"
        case data = "Data"
        case code = "Code"
        case education = "Education"
        case utility = "Utility"
        case music = "Music"
        case custom = "Custom"
        
        var icon: String {
            switch self {
            case .analysis: return "chart.bar"
            case .trading: return "dollarsign.circle"
            case .data: return "tablecells"
            case .code: return "chevron.left.forwardslash.chevron.right"
            case .education: return "book"
            case .utility: return "wrench"
            case .music: return "music.note"
            case .custom: return "star"
            }
        }
    }
    
    // MARK: - Seed Default Skills
    
    private func seedDefaults() {
        let defaults: [ExtendedSkill] = [
            ExtendedSkill(
                name: "Market Scanner",
                category: .analysis,
                description: "Scans watchlist for high-probability setups using confluence analysis",
                promptTemplate: "Scan the market for the best trading opportunities right now.",
                tools: ["analyze", "symbol_scanner", "correlation_matrix"],
                executionScript: nil,
                parameters: ["timeframe": "m15", "minConfidence": "0.6"],
                version: "1.0",
                isBuiltIn: true,
                createdAt: Date(),
                useCount: 0
            ),
            ExtendedSkill(
                name: "Trade Planner",
                category: .trading,
                description: "Creates a complete trade plan with entry, stop, and targets",
                promptTemplate: "Create a detailed trading plan for {symbol} based on current market conditions.",
                tools: ["analyze", "risk_plan", "structure_confluence"],
                executionScript: nil,
                parameters: ["riskPercent": "1.0", "rewardRatio": "2.0"],
                version: "1.0",
                isBuiltIn: true,
                createdAt: Date(),
                useCount: 0
            ),
            ExtendedSkill(
                name: "Portfolio Optimizer",
                category: .trading,
                description: "Optimizes multi-asset portfolio allocation using modern portfolio theory",
                promptTemplate: "Optimize my portfolio allocation for maximum risk-adjusted returns.",
                tools: ["portfolio_analysis", "portfolio_rebalance", "portfolio_stress"],
                executionScript: nil,
                parameters: ["maxSymbols": "6"],
                version: "1.0",
                isBuiltIn: true,
                createdAt: Date(),
                useCount: 0
            ),
            ExtendedSkill(
                name: "News Analyst",
                category: .analysis,
                description: "Analyzes latest market news and identifies sentiment-driven opportunities",
                promptTemplate: "What's happening in the markets today? Analyze the news for trading opportunities.",
                tools: ["news_list", "news_sentiment", "news_by_symbol", "sentiment_score"],
                executionScript: nil,
                parameters: ["maxArticles": "10"],
                version: "1.0",
                isBuiltIn: true,
                createdAt: Date(),
                useCount: 0
            ),
            ExtendedSkill(
                name: "Journal Analyst",
                category: .data,
                description: "Analyzes trade journal for patterns, strengths, and areas for improvement",
                promptTemplate: "Analyze my trading journal and give me actionable insights to improve.",
                tools: ["journal_stats", "journal_search", "journal_lesson", "signal_performance"],
                executionScript: nil,
                parameters: ["includeSymbols": "true"],
                version: "1.0",
                isBuiltIn: true,
                createdAt: Date(),
                useCount: 0
            ),
            ExtendedSkill(
                name: "Risk Assessment",
                category: .trading,
                description: "Comprehensive risk assessment for current positions and portfolio",
                promptTemplate: "Assess my current risk exposure and give me recommendations.",
                tools: ["risk_plan", "deep_risk", "portfolio_analysis", "ultra_confirm"],
                executionScript: nil,
                parameters: ["includeVaR": "true", "includeStress": "true"],
                version: "1.0",
                isBuiltIn: true,
                createdAt: Date(),
                useCount: 0
            ),
            ExtendedSkill(
                name: "Data Exporter",
                category: .data,
                description: "Exports trading data in various formats for external analysis",
                promptTemplate: "Export my trading data so I can analyze it externally.",
                tools: ["export_signal_data", "create_file", "list_files"],
                executionScript: nil,
                parameters: ["format": "csv"],
                version: "1.0",
                isBuiltIn: true,
                createdAt: Date(),
                useCount: 0
            ),
            ExtendedSkill(
                name: "Sound Designer",
                category: .music,
                description: "Creates custom audio alerts and sounds for trading signals",
                promptTemplate: "Create a unique sound for my winning trades.",
                tools: ["create_tone", "create_song", "vinny_loop", "vinny_patch"],
                executionScript: nil,
                parameters: ["defaultFormat": "wav"],
                version: "1.0",
                isBuiltIn: true,
                createdAt: Date(),
                useCount: 0
            ),
            ExtendedSkill(
                name: "Code Helper",
                category: .code,
                description: "Helps write, debug, and explain trading-related code",
                promptTemplate: "Help me write a {language} script for {purpose}.",
                tools: ["create_file", "read_file", "web_scrape"],
                executionScript: nil,
                parameters: ["language": "python"],
                version: "1.0",
                isBuiltIn: true,
                createdAt: Date(),
                useCount: 0
            ),
            ExtendedSkill(
                name: "Education Tutor",
                category: .education,
                description: "Explains trading concepts, indicators, and strategies with examples",
                promptTemplate: "Teach me about {topic} with real examples.",
                tools: ["web_scrape", "memory_search"],
                executionScript: nil,
                parameters: ["difficulty": "intermediate"],
                version: "1.0",
                isBuiltIn: true,
                createdAt: Date(),
                useCount: 0
            ),
        ]
        userSkills = defaults
        save()
    }
    
    // MARK: - CRUD
    
    func createSkill(name: String, category: SkillCategory, description: String,
                     promptTemplate: String, tools: [String], parameters: [String: String] = [:]) -> ExtendedSkill {
        let skill = ExtendedSkill(
            name: name,
            category: category,
            description: description,
            promptTemplate: promptTemplate,
            tools: tools,
            executionScript: nil,
            parameters: parameters,
            version: "1.0",
            isBuiltIn: false,
            createdAt: Date(),
            useCount: 0
        )
        userSkills.append(skill)
        save()
        return skill
    }
    
    func deleteSkill(_ id: UUID) {
        userSkills.removeAll { $0.id == id }
        save()
    }
    
    func recordUsage(_ id: UUID) {
        guard let idx = userSkills.firstIndex(where: { $0.id == id }) else { return }
        userSkills[idx].useCount += 1
        userSkills[idx].lastUsed = Date()
        save()
    }
    
    func skillsByCategory(_ category: SkillCategory) -> [ExtendedSkill] {
        userSkills.filter { $0.category == category }
    }
    
    func skillsForTools(_ tools: [String]) -> [ExtendedSkill] {
        userSkills.filter { skill in
            !Set(skill.tools).intersection(tools).isEmpty
        }
    }
    
    // MARK: - Import/Export
    
    func exportSkill(_ id: UUID) -> String? {
        guard let skill = userSkills.first(where: { $0.id == id }) else { return nil }
        guard let data = try? JSONEncoder().encode(skill),
              let json = String(data: data, encoding: .utf8) else { return nil }
        return json
    }
    
    func importSkill(from json: String) -> String {
        guard let data = json.data(using: .utf8),
              let skill = try? JSONDecoder().decode(ExtendedSkill.self, from: data) else {
            return "Invalid skill JSON format."
        }
        if userSkills.contains(where: { $0.name == skill.name }) {
            return "A skill named '\(skill.name)' already exists."
        }
        userSkills.append(skill)
        save()
        return "Imported skill '\(skill.name)' successfully."
    }
    
    // MARK: - Catalog
    
    func catalog() -> String {
        var result = "## 🎯 Skills Catalog\n\n"
        for category in SkillCategory.allCases {
            let skills = skillsByCategory(category)
            guard !skills.isEmpty else { continue }
            result += "### \(category.rawValue)\n"
            for skill in skills {
                let usage = skill.useCount > 0 ? " · used \(skill.useCount)x" : ""
                result += "• **\(skill.name)**\(skill.isBuiltIn ? " (built-in)" : "")\(usage)\n  \(skill.description)\n"
            }
            result += "\n"
        }
        return result
    }
    
    // MARK: - Persistence
    
    private func load() {
        userSkills = FileStore.shared.read([ExtendedSkill].self, from: file, in: FileStore.shared.dataDir) ?? []
    }
    
    private func save() {
        FileStore.shared.write(userSkills, to: file, in: FileStore.shared.dataDir)
    }
}
