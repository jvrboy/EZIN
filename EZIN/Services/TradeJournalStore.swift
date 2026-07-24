import Foundation
import UIKit

// MARK: - Trade Journal Models

/// Emotional state when the trade was taken — helps identify psychological patterns.
enum TradeEmotion: String, Codable, CaseIterable, Identifiable {
    case calm = "Calm"
    case confident = "Confident"
    case excited = "Excited"
    case anxious = "Anxious"
    case fearful = "Fearful"
    case greedy = "Greedy"
    case impatient = "Impatient"
    case hesitant = "Hesitant"
    case frustrated = "Frustrated"
    case revenge = "Revenge"
    case bored = "Bored"
    case hopeful = "Hopeful"

    var id: String { rawValue }
    var icon: String {
        switch self {
        case .calm: return "zzz"
        case .confident: return "face.smiling"
        case .excited: return "star.fill"
        case .anxious: return "face.anxious"
        case .fearful: return "hand.raised"
        case .greedy: return "dollarsign"
        case .impatient: return "timer"
        case .hesitant: return "questionmark"
        case .frustrated: return "exclamationmark.triangle"
        case .revenge: return "flame"
        case .bored: return "eye.slash"
        case .hopeful: return "sparkles"
        }
    }
    var isNegative: Bool {
        [.anxious, .fearful, .greedy, .impatient, .hesitant, .frustrated, .revenge, .bored].contains(self)
    }
}

/// Outcome category for a journaled trade.
enum JournalOutcome: String, Codable, CaseIterable, Identifiable {
    case win = "Win"
    case loss = "Loss"
    case breakeven = "Breakeven"
    case open = "Open"

    var id: String { rawValue }
    var icon: String {
        switch self {
        case .win: return "checkmark.circle.fill"
        case .loss: return "xmark.circle.fill"
        case .breakeven: return "minus.circle.fill"
        case .open: return "circle.dotted"
        }
    }
}

/// Setup type — how the trade was identified.
enum TradeSetupType: String, Codable, CaseIterable, Identifiable {
    case signal = "Signal Engine"
    case chartPattern = "Chart Pattern"
    case supportResistance = "S/R Level"
    case trendLine = "Trend Line Break"
    case indicator = "Indicator"
    case news = "News Event"
    case manual = "Manual Analysis"
    case bot = "Auto Bot"
    case apex = "APEX Analysis"

    var id: String { rawValue }
}

/// A single trade journal entry.
struct JournalEntry: Codable, Identifiable, Hashable {
    var id = UUID()
    var symbol: String
    var direction: Direction           // bullish/bearish
    var entryPrice: Double
    var exitPrice: Double?
    var stopLoss: Double?
    var takeProfit: Double?
    var quantity: Double               // position size / stake
    var outcome: JournalOutcome = .open
    var pnl: Double?                   // realized P&L
    var rr: Double?                    // risk/reward ratio achieved

    // Metadata
    var entryDate: Date
    var exitDate: Date?
    var setupType: TradeSetupType = .manual
    var timeframe: Timeframe = .m15
    var emotion: TradeEmotion?         // how you felt entering
    var emotionExit: TradeEmotion?     // how you felt closing

    // Notes & tags
    var notes: String = ""
    var tags: [String] = []
    var mistakes: [String] = []        // what went wrong
    var lessons: [String] = []         // what to learn

    // Screenshots (file paths relative to journal directory)
    var screenshotPaths: [String] = []

    // Self-rating (1-5 stars)
    var rating: Int = 3

    var displayPair: String { DerivSymbols.display(symbol) }

    var profitDisplay: String {
        guard let p = pnl else { return "—" }
        return "\(p >= 0 ? "+" : "")\(String(format: "%.2f", p))"
    }

    var barsHeld: Int? {
        guard let exit = exitDate else { return nil }
        return Int(exit.timeIntervalSince(entryDate) / 60)
    }

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: JournalEntry, rhs: JournalEntry) -> Bool { lhs.id == rhs.id }
}

// MARK: - Journal Statistics

struct JournalStatistics {
    let totalTrades: Int
    let wins: Int
    let losses: Int
    let breakeven: Int
    let winRate: Double
    let totalPnL: Double
    let averageRR: Double
    let bestTrade: Double
    let worstTrade: Double
    let mostCommonEmotion: TradeEmotion?
    let mostCommonMistake: String?
    let consecutiveWins: Int
    let consecutiveLosses: Int
    let averageHoldingMinutes: Double
    let profitFactor: Double

    var isEmpty: Bool { totalTrades == 0 }
}

// MARK: - Trade Journal Store

/// Persistent store for the trade journal.
@MainActor
final class TradeJournalStore: ObservableObject {
    static let shared = TradeJournalStore()

    @Published var entries: [JournalEntry] = []

    private let fileName = "trade_journal.json"

    private init() {
        load()
    }

    // MARK: - CRUD

    func add(_ entry: JournalEntry) {
        entries.insert(entry, at: 0)
        save()
    }

    func update(_ entry: JournalEntry) {
        if let idx = entries.firstIndex(where: { $0.id == entry.id }) {
            entries[idx] = entry
            save()
        }
    }

    func remove(_ entry: JournalEntry) {
        entries.removeAll { $0.id == entry.id }
        // Clean up screenshots
        for path in entry.screenshotPaths {
            let url = journalDir.appendingPathComponent(path)
            try? FileManager.default.removeItem(at: url)
        }
        save()
    }

    func closeTrade(id: UUID, exitPrice: Double, exitDate: Date = Date(), outcome: JournalOutcome, pnl: Double, exitEmotion: TradeEmotion? = nil) {
        guard let idx = entries.firstIndex(where: { $0.id == id }) else { return }
        var entry = entries[idx]
        entry.exitPrice = exitPrice
        entry.exitDate = exitDate
        entry.outcome = outcome
        entry.pnl = pnl
        entry.emotionExit = exitEmotion

        // Calculate achieved R:R
        if let sl = entry.stopLoss, let tp = entry.takeProfit, sl != entry.entryPrice {
            let risk = abs(entry.entryPrice - sl)
            let reward = abs(exitPrice - entry.entryPrice)
            let direction = entry.direction
            let intendedRR = abs(tp - entry.entryPrice) / risk
            entry.rr = reward / risk
        }

        entries[idx] = entry
        save()
    }

    func addScreenshot(to entryID: UUID, imageData: Data) -> String? {
        guard let idx = entries.firstIndex(where: { $0.id == entryID }) else { return nil }
        let fileName = "screenshot-\(UUID().uuidString.prefix(8)).png"
        let url = journalDir.appendingPathComponent(fileName)
        do {
            try FileManager.default.createDirectory(at: journalDir, withIntermediateDirectories: true)
            try imageData.write(to: url)
            entries[idx].screenshotPaths.append(fileName)
            save()
            return fileName
        } catch {
            return nil
        }
    }

    func clear() {
        entries.removeAll()
        // Clean up screenshots directory
        try? FileManager.default.removeItem(at: journalDir)
        save()
    }

    // MARK: - Queries

    func entries(for symbol: String) -> [JournalEntry] {
        entries.filter { $0.symbol == symbol }
    }

    func entries(for outcome: JournalOutcome) -> [JournalEntry] {
        entries.filter { $0.outcome == outcome }
    }

    var openEntries: [JournalEntry] { entries.filter { $0.outcome == .open } }
    var closedEntries: [JournalEntry] { entries.filter { $0.outcome != .open } }

    func search(_ query: String) -> [JournalEntry] {
        let q = query.lowercased()
        return entries.filter {
            $0.displayPair.lowercased().contains(q) ||
            $0.notes.lowercased().contains(q) ||
            $0.tags.contains { $0.lowercased().contains(q) } ||
            $0.lessons.contains { $0.lowercased().contains(q) } ||
            $0.mistakes.contains { $0.lowercased().contains(q) }
        }
    }

    // MARK: - Statistics

    var statistics: JournalStatistics {
        let closed = closedEntries
        let wins = closed.filter { $0.outcome == .win }
        let losses = closed.filter { $0.outcome == .loss }
        let breakevens = closed.filter { $0.outcome == .breakeven }
        let total = closed.count
        let winRate = total > 0 ? Double(wins.count) / Double(total) : 0
        let totalPnL = closed.compactMap { $0.pnl }.reduce(0, +)
        let avgRR = wins.isEmpty ? 0 : wins.compactMap { $0.rr }.reduce(0, +) / Double(wins.count)

        // Most common emotion
        let emotions = entries.compactMap { $0.emotion }
        let mostCommonEmotion = Dictionary(grouping: emotions, by: { $0 }).max { $0.value.count < $1.value.count }?.key

        // Most common mistake
        let allMistakes = entries.flatMap { $0.mistakes }
        let mostCommonMistake = Dictionary(grouping: allMistakes, by: { $0 }).max { $0.value.count < $1.value.count }?.key

        // Consecutive wins/losses
        var maxConsecWins = 0, currentWins = 0
        var maxConsecLosses = 0, currentLosses = 0
        for entry in closed {
            if entry.outcome == .win {
                currentWins += 1; currentLosses = 0
                maxConsecWins = max(maxConsecWins, currentWins)
            } else if entry.outcome == .loss {
                currentLosses += 1; currentWins = 0
                maxConsecLosses = max(maxConsecLosses, currentLosses)
            }
        }

        // Average holding time
        let holdingTimes = closed.compactMap { entry -> Double? in
            guard let exit = entry.exitDate else { return nil }
            return exit.timeIntervalSince(entry.entryDate) / 60
        }
        let avgHolding = holdingTimes.isEmpty ? 0 : holdingTimes.reduce(0, +) / Double(holdingTimes.count)

        // Profit factor
        let grossProfit = wins.compactMap { $0.pnl }.filter { $0 > 0 }.reduce(0, +)
        let grossLoss = abs(losses.compactMap { $0.pnl }.filter { $0 < 0 }.reduce(0, +))
        let pf = grossLoss > 0 ? grossProfit / grossLoss : (grossProfit > 0 ? Double.infinity : 0)

        return JournalStatistics(
            totalTrades: total,
            wins: wins.count,
            losses: losses.count,
            breakeven: breakevens.count,
            winRate: winRate,
            totalPnL: totalPnL,
            averageRR: avgRR,
            bestTrade: wins.compactMap { $0.pnl }.max() ?? 0,
            worstTrade: losses.compactMap { $0.pnl }.min() ?? 0,
            mostCommonEmotion: mostCommonEmotion,
            mostCommonMistake: mostCommonMistake,
            consecutiveWins: maxConsecWins,
            consecutiveLosses: maxConsecLosses,
            averageHoldingMinutes: avgHolding,
            profitFactor: pf
        )
    }

    // MARK: - Persistence

    private var journalDir: URL {
        FileStore.shared.dataDir.appendingPathComponent("TradeJournal", isDirectory: true)
    }

    private func save() {
        let url = journalDir.appendingPathComponent(fileName)
        try? FileManager.default.createDirectory(at: journalDir, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(entries) {
            try? data.write(to: url)
        }
    }

    private func load() {
        let url = journalDir.appendingPathComponent(fileName)
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([JournalEntry].self, from: data) else { return }
        entries = decoded
    }
}

// MARK: - Chat Tools for Trade Journal

extension ToolRegistry {
    /// Log a new trade in the journal from chat.
    func journalAdd(args: [String: Any]) -> String {
        let symbol = resolveSymbol(str(args, "symbol"))
        let rawDirection = str(args, "direction").lowercased()
        let entryPrice = (args["entry"] as? Double) ?? Double(str(args, "entry")) ?? 0
        let stopLoss = (args["stop_loss"] as? Double) ?? Double(str(args, "stop_loss"))
        let takeProfit = (args["take_profit"] as? Double) ?? Double(str(args, "take_profit"))
        let quantity = (args["quantity"] as? Double) ?? Double(str(args, "quantity")) ?? 1.0
        let notes = str(args, "notes")
        let tagsRaw = str(args, "tags")
        let rawSetup = str(args, "setup").lowercased()
        let rawEmotion = str(args, "emotion").lowercased()

        guard DerivSymbols.all.contains(symbol) else { return "Unknown symbol: '\(str(args, "symbol"))'." }
        guard entryPrice > 0 else { return "Entry price must be positive." }

        let direction: Direction = rawDirection.contains("buy") || rawDirection.contains("long") || rawDirection.contains("bullish") ? .bullish : .bearish

        let setup: TradeSetupType
        switch rawSetup {
        case "signal", "engine": setup = .signal
        case "pattern", "chart": setup = .chartPattern
        case "sr", "support", "resistance": setup = .supportResistance
        case "trendline", "trend": setup = .trendLine
        case "indicator", "ind": setup = .indicator
        case "news", "event": setup = .news
        case "bot", "auto": setup = .bot
        case "apex": setup = .apex
        default: setup = .manual
        }

        let emotion: TradeEmotion? = TradeEmotion.allCases.first { $0.rawValue.lowercased() == rawEmotion }

        let tags = tagsRaw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }

        let entry = JournalEntry(
            symbol: symbol,
            direction: direction,
            entryPrice: entryPrice,
            exitPrice: nil,
            stopLoss: stopLoss,
            takeProfit: takeProfit,
            quantity: quantity,
            outcome: .open,
            pnl: nil,
            entryDate: Date(),
            setupType: setup,
            emotion: emotion,
            notes: notes,
            tags: tags
        )

        TradeJournalStore.shared.add(entry)
        return """
        ✅ Trade logged: **\(direction.isBullish ? "BUY" : "SELL")** \(DerivSymbols.display(symbol)) @ \(fmt(entryPrice))
        📋 Journal ID: `\(entry.id.uuidString.prefix(8))...`
        - Stop Loss: \(stopLoss.map { fmt($0) } ?? "not set")
        - Take Profit: \(takeProfit.map { fmt($0) } ?? "not set")
        - Setup: \(setup.rawValue)
        - Emotion: \(emotion?.rawValue ?? "not recorded")

        Use `journal_list` to view all entries, `journal_close(id:, exit:, pnl:)` to close a trade.
        """
    }

    /// List journal entries with optional filters.
    func journalList(args: [String: Any]) -> String {
        let store = TradeJournalStore.shared
        let filterSymbol = str(args, "symbol")
        let filterOutcome = str(args, "outcome").lowercased()
        let limit = Int((args["limit"] as? Double) ?? Double(str(args, "limit")) ?? 20)

        var filtered = store.entries

        if !filterSymbol.isEmpty {
            let sym = resolveSymbol(filterSymbol)
            filtered = filtered.filter { $0.symbol == sym }
        }

        switch filterOutcome {
        case "win", "wins": filtered = filtered.filter { $0.outcome == .win }
        case "loss", "losses": filtered = filtered.filter { $0.outcome == .loss }
        case "open", "active": filtered = filtered.filter { $0.outcome == .open }
        case "closed": filtered = filtered.filter { $0.outcome != .open }
        default: break
        }

        let display = filtered.prefix(max(limit, 1))

        guard !display.isEmpty else {
            return "## Trade Journal\n\nNo entries match your filters. Log your first trade with `journal_add`."
        }

        let stats = store.statistics
        var report = "## Trade Journal (\(display.count) shown / \(store.entries.count) total)\n\n"

        if !stats.isEmpty {
            report += "**Overall:** \(stats.wins)W / \(stats.losses)L · \(Int(stats.winRate * 100))% win rate · \(stats.totalPnL >= 0 ? "+" : "")\(String(format: "%.2f", stats.totalPnL)) P&L\n\n"
        }

        for entry in display {
            let dir = entry.direction.isBullish ? "🟢 BUY" : "🔴 SELL"
            let outcomeIcon: String
            switch entry.outcome {
            case .win: outcomeIcon = "✅"
            case .loss: outcomeIcon = "❌"
            case .breakeven: outcomeIcon = "➖"
            case .open: outcomeIcon = "🔄"
            }
            report += "\(outcomeIcon) **\(entry.displayPair)** \(dir) @ \(fmt(entry.entryPrice))"
            if let pnl = entry.pnl { report += " · P&L: \(pnl >= 0 ? "+" : "")\(String(format: "%.2f", pnl))" }
            if let emotion = entry.emotion { report += " · \(emotion.rawValue)" }
            report += "\n  ID: `\(entry.id.uuidString.prefix(8))...` · \(entry.entryDate.formatted(date: .abbreviated, time: .shortened))\n"
            if !entry.tags.isEmpty { report += "  Tags: \(entry.tags.joined(separator: ", "))\n" }
            if entry.rating != 3 { report += "  Rating: \(String(repeating: "⭐", count: entry.rating))\n" }
        }

        return report
    }

    /// Close an open trade journal entry.
    func journalClose(args: [String: Any]) -> String {
        let rawID = str(args, "id").lowercased()
        let exitPrice = (args["exit"] as? Double) ?? Double(str(args, "exit_price")) ?? Double(str(args, "exit")) ?? 0
        let rawOutcome = str(args, "outcome").lowercased()
        let pnl = (args["pnl"] as? Double) ?? Double(str(args, "pnl")) ?? Double(str(args, "profit")) ?? 0
        let notes = str(args, "notes")
        let rawEmotion = str(args, "emotion").lowercased()

        guard exitPrice > 0 else { return "Exit price must be positive. Use `exit:` parameter." }

        let store = TradeJournalStore.shared
        let matches = store.openEntries.filter {
            $0.id.uuidString.lowercased().contains(rawID)
        }

        guard !matches.isEmpty else { return "No open entry matching '\(rawID)'. Use `journal_list` to find the ID." }
        let entry = matches[0]

        let outcome: JournalOutcome
        if rawOutcome.contains("win") || pnl > 0 { outcome = .win }
        else if rawOutcome.contains("loss") || pnl < 0 { outcome = .loss }
        else { outcome = .breakeven }

        let emotion: TradeEmotion? = TradeEmotion.allCases.first { $0.rawValue.lowercased() == rawEmotion }

        store.closeTrade(id: entry.id, exitPrice: exitPrice, outcome: outcome, pnl: pnl, exitEmotion: emotion)

        var result = "✅ Closed trade: **\(entry.displayPair)** @ \(fmt(exitPrice)) · \(outcome.rawValue) · P&L: \(pnl >= 0 ? "+" : "")\(String(format: "%.2f", pnl))\n"
        if !notes.isEmpty { result += "📝 Notes: \(notes)\n" }
        if let e = emotion { result += "😌 Exit emotion: \(e.rawValue)\n" }

        // Update entry notes if provided
        if !notes.isEmpty {
            var updated = entry
            updated.notes = notes
            store.update(updated)
        }

        return result
    }

    /// Search the trade journal.
    func journalSearch(args: [String: Any]) -> String {
        let query = str(args, "query").isEmpty ? str(args, "q") : str(args, "query")
        guard !query.isEmpty else { return "Provide a search 'query'." }

        let results = TradeJournalStore.shared.search(query)
        guard !results.isEmpty else { return "No journal entries matching '\(query)'." }

        var report = "## Journal Search: \"\(query)\" (\(results.count) matches)\n\n"
        for entry in results.prefix(15) {
            let dir = entry.direction.isBullish ? "BUY" : "SELL"
            report += "• **\(entry.displayPair)** \(dir) @ \(fmt(entry.entryPrice)) · \(entry.outcome.rawValue)"
            if let pnl = entry.pnl { report += " (\(pnl >= 0 ? "+" : "")\(String(format: "%.2f", pnl)))" }
            report += "\n  \(entry.entryDate.formatted(date: .abbreviated, time: .shortened))\n"
        }
        return report
    }

    /// Get journal statistics.
    func journalStats(args: [String: Any]) -> String {
        let stats = TradeJournalStore.shared.statistics
        guard !stats.isEmpty else { return "No journal entries yet. Log a trade with `journal_add` to see statistics." }

        var report = "## 📊 Trade Journal Statistics\n\n"
        report += "| Metric | Value |\n|---|---|\n"
        report += "| Total Trades | \(stats.totalTrades) |\n"
        report += "| Wins / Losses / Breakeven | \(stats.wins) / \(stats.losses) / \(stats.breakeven) |\n"
        report += "| Win Rate | \(Int(stats.winRate * 100))% |\n"
        report += "| Total P&L | \(stats.totalPnL >= 0 ? "+" : "")\(String(format: "%.2f", stats.totalPnL)) |\n"
        report += "| Avg R:R (wins) | \(String(format: "%.2f", stats.averageRR)) |\n"
        report += "| Profit Factor | \(stats.profitFactor.isFinite ? String(format: "%.2f", stats.profitFactor) : "∞") |\n"
        report += "| Best Trade | \(String(format: "%.2f", stats.bestTrade)) |\n"
        report += "| Worst Trade | \(String(format: "%.2f", stats.worstTrade)) |\n"
        report += "| Consecutive Wins | \(stats.consecutiveWins) |\n"
        report += "| Consecutive Losses | \(stats.consecutiveLosses) |\n"
        report += "| Avg Hold Time | \(Int(stats.averageHoldingMinutes)) min |\n"

        if let emotion = stats.mostCommonEmotion {
            report += "| Most Common Emotion | \(emotion.rawValue) |\n"
        }
        if let mistake = stats.mostCommonMistake {
            report += "| Most Common Mistake | \(mistake) |\n"
        }

        return report
    }

    /// Record a lesson or mistake from a trade.
    func journalLesson(args: [String: Any]) -> String {
        let rawID = str(args, "id")
        let lesson = str(args, "lesson").isEmpty ? str(args, "text") : str(args, "lesson")
        let mistake = str(args, "mistake")

        guard !rawID.isEmpty else { return "Specify a journal entry 'id'." }
        guard !lesson.isEmpty || !mistake.isEmpty else { return "Provide a 'lesson' or 'mistake' to record." }

        let store = TradeJournalStore.shared
        guard let idx = store.entries.firstIndex(where: { $0.id.uuidString.lowercased().contains(rawID.lowercased()) }) else {
            return "No entry matching '\(rawID)'."
        }

        var entry = store.entries[idx]
        if !lesson.isEmpty { entry.lessons.append(lesson) }
        if !mistake.isEmpty { entry.mistakes.append(mistake) }
        store.update(entry)

        var result = "✅ Updated journal entry \(entry.displayPair):\n"
        if !lesson.isEmpty { result += "📖 Lesson recorded: \(lesson)\n" }
        if !mistake.isEmpty { result += "⚠️ Mistake recorded: \(mistake)\n" }
        return result
    }

    private func fmt(_ x: Double, _ places: Int = 4) -> String {
        String(format: "%.\(places)f", x)
    }
}
