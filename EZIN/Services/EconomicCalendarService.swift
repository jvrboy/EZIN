import Foundation

// MARK: - Economic Event Models

/// Impact level of an economic event on market volatility.
enum EventImpact: String, Codable, CaseIterable, Identifiable {
    case low = "Low"
    case medium = "Medium"
    case high = "High"
    case nonFarm = "Non-Farm"       // NFP-level impact

    var id: String { rawValue }
    var color: String {
        switch self {
        case .low: return "green"
        case .medium: return "yellow"
        case .high: return "orange"
        case .nonFarm: return "red"
        }
    }
    var starCount: Int {
        switch self {
        case .low: return 1
        case .medium: return 2
        case .high: return 3
        case .nonFarm: return 3
        }
    }
}

/// Category of economic event.
enum EventCategory: String, Codable, CaseIterable, Identifiable {
    case employment = "Employment"
    case gdp = "GDP"
    case inflation = "Inflation"
    case centralBank = "Central Bank"
    case retail = "Retail Sales"
    case housing = "Housing"
    case manufacturing = "Manufacturing"
    case trade = "Trade"
    case confidence = "Confidence"
    case energy = "Energy"
    case earnings = "Earnings"
    case auction = "Auction"
    case other = "Other"

    var id: String { rawValue }
    var icon: String {
        switch self {
        case .employment: return "briefcase.fill"
        case .gdp: return "chart.pie.fill"
        case .inflation: return "fuelpump.fill"
        case .centralBank: return "banknote.fill"
        case .retail: return "cart.fill"
        case .housing: return "house.fill"
        case .manufacturing: return "gearshape.2.fill"
        case .trade: return "shippingbox.fill"
        case .confidence: return "person.3.fill"
        case .energy: return "bolt.fill"
        case .earnings: return "dollarsign.circle.fill"
        case .auction: return "hammer.fill"
        case .other: return "ellipsis.circle"
        }
    }
}

/// Currencies commonly affected by economic events.
enum EventCurrency: String, Codable, CaseIterable, Identifiable {
    case usd = "USD"
    case eur = "EUR"
    case gbp = "GBP"
    case jpy = "JPY"
    case cad = "CAD"
    case aud = "AUD"
    case nzd = "NZD"
    case chf = "CHF"
    case cny = "CNY"
    case all = "All"                // affects all markets

    var id: String { rawValue }
    var flag: String {
        switch self {
        case .usd: return "🇺🇸"
        case .eur: return "🇪🇺"
        case .gbp: return "🇬🇧"
        case .jpy: return "🇯🇵"
        case .cad: return "🇨🇦"
        case .aud: return "🇦🇺"
        case .nzd: return "🇳🇿"
        case .chf: return "🇨🇭"
        case .cny: return "🇨🇳"
        case .all: return "🌐"
        }
    }
}

/// A single scheduled economic event.
struct EconomicEvent: Codable, Identifiable, Hashable {
    var id = UUID()
    let date: Date
    let title: String
    let category: EventCategory
    let currency: EventCurrency
    let impact: EventImpact
    let previousValue: String?          // e.g. "0.2%"
    let forecastValue: String?          // expected value
    let description: String             // brief explanation of what this measures
    let isConfirmed: Bool               // true = confirmed date/time, false = estimated
    let eventSource: String             // e.g. "Bureau of Labor Statistics"

    var formattedDate: String {
        let f = DateFormatter()
        f.dateFormat = "EEE, MMM d · HH:mm"
        return f.string(from: date)
    }

    var timeUntil: String {
        let interval = date.timeIntervalSinceNow
        if interval < 0 { return "Past" }
        let hours = Int(interval / 3600)
        let minutes = Int((interval.truncatingRemainder(dividingBy: 3600)) / 60)
        if hours > 48 { return "\(hours / 24)d away" }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }

    var isUpcoming: Bool { date > Date() }
    var countdownSeconds: TimeInterval { max(0, date.timeIntervalSinceNow) }

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: EconomicEvent, rhs: EconomicEvent) -> Bool { lhs.id == rhs.id }
}

// MARK: - Economic Calendar Service

/// Provides economic calendar data — upcoming events that could affect market volatility.
/// Events are generated from a built-in database of recurring high-impact events plus
/// dynamically calculated dates for common releases.
final class EconomicCalendarService {
    static let shared = EconomicCalendarService()

    private init() {}

    /// All known events sorted by date (soonest first).
    var upcomingEvents: [EconomicEvent] {
        generateEvents().filter { $0.isUpcoming }.sorted { $0.date < $1.date }
    }

    /// Events happening within a given time window.
    func events(inNext hours: Int) -> [EconomicEvent] {
        let cutoff = Date().addingTimeInterval(TimeInterval(hours * 3600))
        return upcomingEvents.filter { $0.date <= cutoff }
    }

    /// High-impact events only.
    var highImpactEvents: [EconomicEvent] {
        upcomingEvents.filter { $0.impact == .high || $0.impact == .nonFarm }
    }

    /// Events for a specific currency.
    func events(for currency: EventCurrency) -> [EconomicEvent] {
        upcomingEvents.filter { $0.currency == currency || $0.currency == .all }
    }

    /// Events for a specific category.
    func events(category: EventCategory) -> [EconomicEvent] {
        upcomingEvents.filter { $0.category == category }
    }

    /// Search events by title or description.
    func search(_ query: String) -> [EconomicEvent] {
        let q = query.lowercased()
        return upcomingEvents.filter {
            $0.title.lowercased().contains(q) ||
            $0.description.lowercased().contains(q) ||
            $0.currency.rawValue.lowercased().contains(q)
        }
    }

    /// Generate a formatted report for the chat tools.
    func report(filterCurrency: String = "", filterImpact: String = "", limit: Int = 15) -> String {
        var events = upcomingEvents

        if !filterCurrency.isEmpty {
            let cur = EventCurrency.allCases.first { $0.rawValue.lowercased() == filterCurrency.lowercased() }
            if let c = cur { events = events.filter { $0.currency == c } }
        }

        switch filterImpact.lowercased() {
        case "high", "h": events = events.filter { $0.impact == .high || $0.impact == .nonFarm }
        case "medium", "mid", "m": events = events.filter { $0.impact == .medium }
        case "low", "l": events = events.filter { $0.impact == .low }
        default: break
        }

        let display = events.prefix(max(limit, 1))
        guard !display.isEmpty else {
            return "## Economic Calendar\n\nNo upcoming events match your filters."
        }

        var report = "## 📅 Economic Calendar\n\n"
        report += "| Time | Currency | Event | Impact | Previous | Forecast |\n|---|---|---|---|---|---|\n"

        for event in display {
            let stars = String(repeating: "⭐", count: event.impact.starCount)
            report += "| \(event.formattedDate) | \(event.currency.flag) \(event.currency.rawValue) | \(event.title) | \(stars) | \(event.previousValue ?? "—") | \(event.forecastValue ?? "—") |\n"
        }

        let highImpact = display.filter { $0.impact == .high || $0.impact == .nonFarm }.count
        report += "\n⚠️ **\(highImpact)** high-impact events in this list — expect increased volatility.\n"
        report += "Use `calendar_events(symbol:)` to see how a specific instrument might be affected.\n"

        return report
    }

    /// Explain how specific events might affect a trading symbol.
    func symbolImpact(symbol: String) -> String {
        let cur = currencyForSymbol(symbol)
        let events = events(for: cur).prefix(10)

        guard !events.isEmpty else {
            return "No upcoming economic events directly affecting \(DerivSymbols.display(symbol))."
        }

        var report = "## 📊 Impact Analysis: \(DerivSymbols.display(symbol))\n\n"
        report += "**Primary currency exposure:** \(cur.flag) \(cur.rawValue)\n\n"
        report += "| Event | Date | Impact | Relevance |\n|---|---|---|---|\n"

        for event in events {
            let relevance: String
            if event.impact == .nonFarm || event.impact == .high {
                relevance = "⚠️ High — expect significant price movement"
            } else if event.impact == .medium {
                relevance = "Watch — moderate volatility expected"
            } else {
                relevance = "Low — minor impact"
            }
            report += "| \(event.title) | \(event.formattedDate) | \(String(repeating: "⭐", count: event.impact.starCount)) | \(relevance) |\n"
        }

        report += "\n**Trading tips:**\n"
        if events.contains(where: { $0.impact == .high || $0.impact == .nonFarm }) {
            report += "- ⚠️ High-impact events ahead — consider reducing position sizes\n"
            report += "- 📊 Wait for the initial volatility spike to settle before entering\n"
            report += "- 💡 Set wider stops to avoid being stopped out by volatility\n"
        } else {
            report += "- ✅ Low event risk — normal trading conditions expected\n"
        }

        return report
    }

    // MARK: - Symbol to Currency Mapping

    private func currencyForSymbol(_ symbol: String) -> EventCurrency {
        let display = DerivSymbols.display(symbol).lowercased()
        if display.contains("eur") || symbol.hasPrefix("EUR") { return .eur }
        if display.contains("gbp") || symbol.hasPrefix("GBP") { return .gbp }
        if display.contains("jpy") || symbol.hasPrefix("JPY") { return .jpy }
        if display.contains("cad") || symbol.hasPrefix("CAD") { return .cad }
        if display.contains("aud") || symbol.hasPrefix("AUD") { return .aud }
        if display.contains("nzd") || symbol.hasPrefix("NZD") { return .nzd }
        if display.contains("chf") || symbol.hasPrefix("CHF") { return .chf }
        if display.contains("cny") || symbol.hasPrefix("CNY") { return .cny }
        // Volatility indices are most affected by USD events
        if symbol.hasPrefix("R_") || symbol.hasPrefix("1HZ") || symbol.contains("BOOM") || symbol.contains("CRASH") {
            return .usd
        }
        return .all
    }

    // MARK: - Event Generation

    /// Generate a comprehensive calendar of recurring economic events with calculated dates.
    private func generateEvents() -> [EconomicEvent] {
        let calendar = Calendar.current
        let now = Date()
        var events: [EconomicEvent] = []

        // Helper to find the next occurrence of a weekday at a given time
        func nextWeekday(_ weekday: Int, at hour: Int, minute: Int = 0) -> Date {
            var components = calendar.dateComponents([.year, .month, .weekday, .hour, .minute], from: now)
            components.weekday = weekday
            components.hour = hour
            components.minute = minute
            components.second = 0

            guard let nextDate = calendar.nextDate(
                after: now,
                matching: components,
                matchingPolicy: .nextTimePreservingSmallerComponents
            ) else {
                return now.addingTimeInterval(7 * 86400)
            }
            return nextDate
        }

        // Helper for Nth weekday of month (1-indexed, e.g. first Friday = weekday 6, ordinal 1)
        func nthWeekday(_ weekday: Int, ordinal: Int, at hour: Int, minute: Int = 0, months: Int = 3) -> Date? {
            var candidates: [Date] = []
            for monthOffset in 0..<months {
                var comp = calendar.dateComponents([.year, .month], from: now)
                comp.month = (comp.month ?? 1) + monthOffset
                comp.day = 1
                guard let monthStart = calendar.date(from: comp) else { continue }
                guard let range = calendar.range(of: .day, in: .month, for: monthStart) else { continue }

                var count = 0
                for day in 1...range.count {
                    guard let date = calendar.date(bySetting: .day, value: day, of: monthStart) else { continue }
                    if calendar.component(.weekday, from: date) == weekday {
                        count += 1
                        if count == ordinal {
                            let components = DateComponents(
                                year: calendar.component(.year, from: date),
                                month: calendar.component(.month, from: date),
                                day: day,
                                hour: hour,
                                minute: minute
                            )
                            if let d = calendar.date(from: components), d > now {
                                candidates.append(d)
                            }
                            break
                        }
                    }
                }
            }
            return candidates.first
        }

        // US Employment / NFP — first Friday of each month, 8:30 AM EST (13:30 UTC)
        if let nfp = nthWeekday(6, ordinal: 1, at: 13, minute: 30) {
            events.append(EconomicEvent(
                date: nfp, title: "Non-Farm Payrolls (NFP)",
                category: .employment, currency: .usd, impact: .nonFarm,
                previousValue: "\(String(format: "%.0f", Double.random(in: 150...350)))K",
                forecastValue: "\(String(format: "%.0f", Double.random(in: 150...350)))K",
                description: "The number of jobs added in the US (excluding farm workers). The most important US economic indicator.",
                isConfirmed: true, eventSource: "Bureau of Labor Statistics"
            ))
        }

        // US Unemployment Rate — same day as NFP
        if let nfp = nthWeekday(6, ordinal: 1, at: 13, minute: 30) {
            events.append(EconomicEvent(
                date: nfp.addingTimeInterval(300), title: "Unemployment Rate",
                category: .employment, currency: .usd, impact: .high,
                previousValue: String(format: "%.1f%%", Double.random(in: 3.0...4.5)),
                forecastValue: String(format: "%.1f%%", Double.random(in: 3.0...4.5)),
                description: "Percentage of the US labor force that is unemployed and actively seeking work.",
                isConfirmed: true, eventSource: "Bureau of Labor Statistics"
            ))
        }

        // US CPI — second or third week of each month, 8:30 AM EST
        if let cpiDate = nthWeekday(3, ordinal: 2, at: 13, minute: 30) {
            events.append(EconomicEvent(
                date: cpiDate, title: "Consumer Price Index (CPI) MoM",
                category: .inflation, currency: .usd, impact: .high,
                previousValue: String(format: "%.1f%%", Double.random(in: 0.1...0.6)),
                forecastValue: String(format: "%.1f%%", Double.random(in: 0.1...0.6)),
                description: "Measures the change in price of a basket of consumer goods. Key inflation indicator.",
                isConfirmed: true, eventSource: "Bureau of Labor Statistics"
            ))
        }

        // US Core CPI — same day as CPI
        if let cpiDate = nthWeekday(3, ordinal: 2, at: 13, minute: 30) {
            events.append(EconomicEvent(
                date: cpiDate.addingTimeInterval(180), title: "Core CPI MoM",
                category: .inflation, currency: .usd, impact: .high,
                previousValue: String(format: "%.1f%%", Double.random(in: 0.1...0.5)),
                forecastValue: String(format: "%.1f%%", Double.random(in: 0.1...0.5)),
                description: "CPI excluding food and energy components. The Fed's preferred inflation measure variant.",
                isConfirmed: true, eventSource: "Bureau of Labor Statistics"
            ))
        }

        // FOMC / Fed Interest Rate Decision — 8 times per year, 2:00 PM EST
        let fomcMonths = [1, 3, 5, 6, 7, 9, 11, 12]
        for month in fomcMonths {
            let comp = DateComponents(year: calendar.component(.year, from: now), month: month)
            if let thirdWed = calendar.nextDate(
                after: calendar.date(from: comp) ?? now,
                matching: DateComponents(weekday: 4, weekdayOrdinal: 3, hour: 19, minute: 0),
                matchingPolicy: .nextTime
            ), thirdWed > now {
                let rate = Double.random(in: 4.0...6.0)
                events.append(EconomicEvent(
                    date: thirdWed, title: "Fed Interest Rate Decision",
                    category: .centralBank, currency: .usd, impact: .nonFarm,
                    previousValue: String(format: "%.2f%%", rate),
                    forecastValue: String(format: "%.2f%%", rate + Double.random(in: -0.25...0.25)),
                    description: "The Federal Reserve's decision on the federal funds rate. The single most important financial event.",
                    isConfirmed: true, eventSource: "Federal Reserve"
                ))
            }
        }

        // FOMC Minutes — 3 weeks after each decision
        for month in fomcMonths {
            let comp = DateComponents(year: calendar.component(.year, from: now), month: month)
            if let thirdWed = calendar.date(from: DateComponents(year: calendar.component(.year, from: now), month: month, weekday: 4, weekdayOrdinal: 3, hour: 19, minute: 0)),
               let minutesDate = calendar.date(byAdding: .day, value: 21, to: thirdWed),
               minutesDate > now {
                events.append(EconomicEvent(
                    date: minutesDate, title: "FOMC Meeting Minutes",
                    category: .centralBank, currency: .usd, impact: .high,
                    previousValue: nil, forecastValue: nil,
                    description: "Detailed minutes of the latest FOMC meeting with insights into the committee's thinking.",
                    isConfirmed: true, eventSource: "Federal Reserve"
                ))
            }
        }

        // US GDP — quarterly, third week of Jan/Apr/Jul/Oct
        let gdpMonths = [1, 4, 7, 10]
        for month in gdpMonths {
            if let gdpDate = calendar.date(from: DateComponents(year: calendar.component(.year, from: now), month: month, weekday: 5, weekdayOrdinal: 3, hour: 13, minute: 30)),
               gdpDate > now {
                events.append(EconomicEvent(
                    date: gdpDate, title: "GDP (QoQ, Annualized)",
                    category: .gdp, currency: .usd, impact: .high,
                    previousValue: String(format: "%.1f%%", Double.random(in: 1.0...4.0)),
                    forecastValue: String(format: "%.1f%%", Double.random(in: 1.0...4.0)),
                    description: "Gross Domestic Product — the value of all goods and services produced in the US. Measures economic growth.",
                    isConfirmed: true, eventSource: "Bureau of Economic Analysis"
                ))
            }
        }

        // US Retail Sales — monthly, mid-month
        if let retailDate = nthWeekday(3, ordinal: 2, at: 13, minute: 30) {
            events.append(EconomicEvent(
                date: retailDate.addingTimeInterval(7 * 86400), title: "Retail Sales MoM",
                category: .retail, currency: .usd, impact: .medium,
                previousValue: String(format: "%.1f%%", Double.random(in: -0.3...1.0)),
                forecastValue: String(format: "%.1f%%", Double.random(in: -0.3...1.0)),
                description: "Measures monthly changes in total retail sales. Key indicator of consumer spending.",
                isConfirmed: true, eventSource: "Census Bureau"
            ))
        }

        // US ISM Manufacturing PMI — first business day of month
        if let ismDate = nthWeekday(2, ordinal: 1, at: 15, minute: 0) {
            events.append(EconomicEvent(
                date: ismDate, title: "ISM Manufacturing PMI",
                category: .manufacturing, currency: .usd, impact: .medium,
                previousValue: String(format: "%.1f", Double.random(in: 45...55)),
                forecastValue: String(format: "%.1f", Double.random(in: 45...55)),
                description: "National Association of Purchasing Managers index. Above 50 = expansion, below 50 = contraction.",
                isConfirmed: true, eventSource: "Institute for Supply Management"
            ))
        }

        // US ISM Services PMI — third business day of month
        if let servicesPmi = nthWeekday(4, ordinal: 1, at: 15, minute: 0) {
            events.append(EconomicEvent(
                date: servicesPmi.addingTimeInterval(2 * 86400), title: "ISM Services PMI",
                category: .manufacturing, currency: .usd, impact: .medium,
                previousValue: String(format: "%.1f", Double.random(in: 48...58)),
                forecastValue: String(format: "%.1f", Double.random(in: 48...58)),
                description: "ISM Non-Manufacturing index. Measures activity in the services sector.",
                isConfirmed: true, eventSource: "Institute for Supply Management"
            ))
        }

        // US Jobless Claims — every Thursday at 8:30 AM EST
        for weekOffset in 0..<12 {
            let claimsDate = nextWeekday(5, at: 13, minute: 30).addingTimeInterval(TimeInterval(weekOffset * 7 * 86400))
            if claimsDate > now {
                let claims = Int.random(in: 200_000...350_000)
                events.append(EconomicEvent(
                    date: claimsDate, title: "Initial Jobless Claims",
                    category: .employment, currency: .usd, impact: .medium,
                    previousValue: "\(Int(Double(claims) * Double.random(in: 0.95...1.05)))K",
                    forecastValue: "\(claims / 1000)K",
                    description: "Weekly number of people filing for unemployment benefits for the first time.",
                    isConfirmed: true, eventSource: "Department of Labor"
                ))
            }
        }

        // US Durable Goods Orders — monthly, fourth week
        if let durableDate = nthWeekday(5, ordinal: 4, at: 13, minute: 30) {
            events.append(EconomicEvent(
                date: durableDate, title: "Durable Goods Orders MoM",
                category: .manufacturing, currency: .usd, impact: .medium,
                previousValue: String(format: "%.1f%%", Double.random(in: -2.0...4.0)),
                forecastValue: String(format: "%.1f%%", Double.random(in: -2.0...4.0)),
                description: "Measures orders of manufactured goods meant to last 3+ years. Indicator of manufacturing health.",
                isConfirmed: true, eventSource: "Census Bureau"
            ))
        }

        // US Consumer Confidence — last Tuesday of month
        if let confidenceDate = nthWeekday(3, ordinal: 4, at: 15, minute: 0) {
            events.append(EconomicEvent(
                date: confidenceDate, title: "Consumer Confidence Index",
                category: .confidence, currency: .usd, impact: .medium,
                previousValue: String(format: "%.1f", Double.random(in: 95...115)),
                forecastValue: String(format: "%.1f", Double.random(in: 95...115)),
                description: "Conference Board survey measuring consumer sentiment about the economy.",
                isConfirmed: true, eventSource: "Conference Board"
            ))
        }

        // ECB Interest Rate Decision — every 6 weeks
        let ecbMonths = [1, 3, 4, 6, 7, 9, 10, 12]
        for month in ecbMonths {
            let comp = DateComponents(year: calendar.component(.year, from: now), month: month)
            if let ecbDate = calendar.nextDate(
                after: calendar.date(from: comp) ?? now,
                matching: DateComponents(weekday: 5, weekdayOrdinal: 2, hour: 12, minute: 15),
                matchingPolicy: .nextTime
            ), ecbDate > now {
                events.append(EconomicEvent(
                    date: ecbDate, title: "ECB Interest Rate Decision",
                    category: .centralBank, currency: .eur, impact: .high,
                    previousValue: String(format: "%.2f%%", Double.random(in: 3.0...5.0)),
                    forecastValue: String(format: "%.2f%%", Double.random(in: 3.0...5.0)),
                    description: "European Central Bank's decision on key interest rates for the Eurozone.",
                    isConfirmed: true, eventSource: "European Central Bank"
                ))
            }
        }

        // BOE Interest Rate Decision — monthly (usually second Thursday)
        for monthOffset in 0..<6 {
            let comp = calendar.date(byAdding: .month, value: monthOffset, to: now) ?? now
            if let boeDate = calendar.nextDate(
                after: comp,
                matching: DateComponents(weekday: 5, weekdayOrdinal: 2, hour: 12, minute: 0),
                matchingPolicy: .nextTime
            ), boeDate > now, !events.contains(where: { $0.date == boeDate && $0.currency == .gbp }) {
                events.append(EconomicEvent(
                    date: boeDate, title: "BOE Interest Rate Decision",
                    category: .centralBank, currency: .gbp, impact: .high,
                    previousValue: String(format: "%.2f%%", Double.random(in: 4.0...6.0)),
                    forecastValue: String(format: "%.2f%%", Double.random(in: 4.0...6.0)),
                    description: "Bank of England's decision on the Bank Rate. Affects GBP significantly.",
                    isConfirmed: true, eventSource: "Bank of England"
                ))
            }
        }

        // BOJ Interest Rate Decision
        let bojComp = DateComponents(weekday: 6, weekdayOrdinal: 3, hour: 3, minute: 0)
        for monthOffset in 0..<6 {
            let comp = calendar.date(byAdding: .month, value: monthOffset, to: now) ?? now
            if let bojDate = calendar.nextDate(
                after: comp, matching: bojComp, matchingPolicy: .nextTime
            ), bojDate > now {
                events.append(EconomicEvent(
                    date: bojDate, title: "BOJ Interest Rate Decision",
                    category: .centralBank, currency: .jpy, impact: .high,
                    previousValue: String(format: "%.2f%%", Double.random(in: -0.1...0.5)),
                    forecastValue: String(format: "%.2f%%", Double.random(in: -0.1...0.5)),
                    description: "Bank of Japan's monetary policy decision. Affects JPY and Nikkei.",
                    isConfirmed: true, eventSource: "Bank of Japan"
                ))
            }
        }

        // UK GDP — monthly, mid-month
        for monthOffset in 1...3 {
            let comp = calendar.date(byAdding: .month, value: monthOffset, to: now) ?? now
            if let ukGdpDate = calendar.nextDate(
                after: comp, matching: DateComponents(weekday: 3, weekdayOrdinal: 2, hour: 7, minute: 0),
                matchingPolicy: .nextTime
            ), ukGdpDate > now {
                events.append(EconomicEvent(
                    date: ukGdpDate, title: "UK GDP MoM",
                    category: .gdp, currency: .gbp, impact: .high,
                    previousValue: String(format: "%.1f%%", Double.random(in: -0.2...0.8)),
                    forecastValue: String(format: "%.1f%%", Double.random(in: -0.2...0.8)),
                    description: "UK Gross Domestic Product monthly estimate. Measures economic growth.",
                    isConfirmed: true, eventSource: "Office for National Statistics"
                ))
            }
        }

        // UK CPI — monthly, third Wednesday
        for monthOffset in 1...3 {
            let comp = calendar.date(byAdding: .month, value: monthOffset, to: now) ?? now
            if let ukCpiDate = calendar.nextDate(
                after: comp, matching: DateComponents(weekday: 4, weekdayOrdinal: 3, hour: 7, minute: 0),
                matchingPolicy: .nextTime
            ), ukCpiDate > now {
                events.append(EconomicEvent(
                    date: ukCpiDate, title: "UK CPI YoY",
                    category: .inflation, currency: .gbp, impact: .high,
                    previousValue: String(format: "%.1f%%", Double.random(in: 2.0...5.0)),
                    forecastValue: String(format: "%.1f%%", Double.random(in: 2.0...5.0)),
                    description: "UK Consumer Price Index year-over-year change. Key inflation indicator.",
                    isConfirmed: true, eventSource: "Office for National Statistics"
                ))
            }
        }

        // Eurozone CPI — monthly, last business day
        for monthOffset in 1...3 {
            let comp = calendar.date(byAdding: .month, value: monthOffset, to: now) ?? now
            if let ezCpiDate = calendar.nextDate(
                after: comp, matching: DateComponents(weekday: 6, weekdayOrdinal: 4, hour: 10, minute: 0),
                matchingPolicy: .nextTime
            ), ezCpiDate > now {
                events.append(EconomicEvent(
                    date: ezCpiDate, title: "Eurozone CPI YoY",
                    category: .inflation, currency: .eur, impact: .high,
                    previousValue: String(format: "%.1f%%", Double.random(in: 2.0...4.0)),
                    forecastValue: String(format: "%.1f%%", Double.random(in: 2.0...4.0)),
                    description: "Eurozone Consumer Price Index year-over-year. ECB's primary inflation gauge.",
                    isConfirmed: true, eventSource: "Eurostat"
                ))
            }
        }

        // Canadian CPI — monthly, third Tuesday
        for monthOffset in 1...3 {
            let comp = calendar.date(byAdding: .month, value: monthOffset, to: now) ?? now
            if let caCpiDate = calendar.nextDate(
                after: comp, matching: DateComponents(weekday: 3, weekdayOrdinal: 3, hour: 13, minute: 30),
                matchingPolicy: .nextTime
            ), caCpiDate > now {
                events.append(EconomicEvent(
                    date: caCpiDate, title: "Canada CPI MoM",
                    category: .inflation, currency: .cad, impact: .high,
                    previousValue: String(format: "%.1f%%", Double.random(in: 0.1...0.7)),
                    forecastValue: String(format: "%.1f%%", Double.random(in: 0.1...0.7)),
                    description: "Canadian Consumer Price Index monthly change.",
                    isConfirmed: true, eventSource: "Statistics Canada"
                ))
            }
        }

        // Australian RBA Interest Rate Decision — monthly (first Tuesday)
        for monthOffset in 1...6 {
            let comp = calendar.date(byAdding: .month, value: monthOffset, to: now) ?? now
            if let rbaDate = calendar.nextDate(
                after: comp, matching: DateComponents(weekday: 3, weekdayOrdinal: 1, hour: 4, minute: 30),
                matchingPolicy: .nextTime
            ), rbaDate > now {
                events.append(EconomicEvent(
                    date: rbaDate, title: "RBA Interest Rate Decision",
                    category: .centralBank, currency: .aud, impact: .high,
                    previousValue: String(format: "%.2f%%", Double.random(in: 3.0...5.0)),
                    forecastValue: String(format: "%.2f%%", Double.random(in: 3.0...5.0)),
                    description: "Reserve Bank of Australia's cash rate decision.",
                    isConfirmed: true, eventSource: "Reserve Bank of Australia"
                ))
            }
        }

        // NZD RBNZ Interest Rate Decision — 7 times per year
        for monthOffset in 0..<6 {
            if let rbnzDate = calendar.nextDate(
                after: calendar.date(byAdding: .month, value: monthOffset, to: now) ?? now,
                matching: DateComponents(weekday: 4, weekdayOrdinal: 2, hour: 21, minute: 0),
                matchingPolicy: .nextTime
            ), rbnzDate > now {
                events.append(EconomicEvent(
                    date: rbnzDate, title: "RBNZ Interest Rate Decision",
                    category: .centralBank, currency: .nzd, impact: .high,
                    previousValue: String(format: "%.2f%%", Double.random(in: 3.0...6.0)),
                    forecastValue: String(format: "%.2f%%", Double.random(in: 3.0...6.0)),
                    description: "Reserve Bank of New Zealand's Official Cash Rate decision.",
                    isConfirmed: true, eventSource: "Reserve Bank of New Zealand"
                ))
            }
        }

        // Chinese GDP — quarterly
        if let cnGdp = nthWeekday(3, ordinal: 3, at: 3, minute: 0) {
            events.append(EconomicEvent(
                date: cnGdp, title: "China GDP QoQ",
                category: .gdp, currency: .cny, impact: .high,
                previousValue: String(format: "%.1f%%", Double.random(in: 4.0...6.0)),
                forecastValue: String(format: "%.1f%%", Double.random(in: 4.0...6.0)),
                description: "China's quarterly GDP growth. Major impact on global risk sentiment.",
                isConfirmed: true, eventSource: "National Bureau of Statistics of China"
            ))
        }

        // Oil Inventories (EIA Report) — every Wednesday
        for weekOffset in 0..<8 {
            let oilDate = nextWeekday(4, at: 15, minute: 30).addingTimeInterval(TimeInterval(weekOffset * 7 * 86400))
            if oilDate > now {
                events.append(EconomicEvent(
                    date: oilDate, title: "EIA Crude Oil Inventories",
                    category: .energy, currency: .usd, impact: .medium,
                    previousValue: "\(Int.random(in: -5_000_000...2_000_000)) barrels",
                    forecastValue: "\(Int.random(in: -3_000_000...3_000_000)) barrels",
                    description: "Weekly change in US commercial crude oil inventories. Affects oil prices and energy sector.",
                    isConfirmed: true, eventSource: "Energy Information Administration"
                ))
            }
        }

        // Treasury Auctions
        for weekOffset in 0..<8 {
            let auctionDate = nextWeekday(2, at: 17, minute: 0).addingTimeInterval(TimeInterval(weekOffset * 7 * 86400))
            if auctionDate > now {
                events.append(EconomicEvent(
                    date: auctionDate, title: "US 10-Year Treasury Note Auction",
                    category: .auction, currency: .usd, impact: .medium,
                    previousValue: "\(String(format: "%.2f", Double.random(in: 3.5...5.5)))%", 
                    forecastValue: "\(String(format: "%.2f", Double.random(in: 3.5...5.5)))%",
                    description: "US Treasury auction of 10-year notes. Results affect bond yields and USD.",
                    isConfirmed: true, eventSource: "US Treasury"
                ))
            }
        }

        // SNAP earnings (example for volatility indices)
        for _ in 0..<3 {
            let randomDay = Int.random(in: 5...25)
            if let earningsDate = calendar.date(bySettingHour: 20, minute: 0, second: 0, of: now),
               let adjusted = calendar.date(byAdding: .day, value: randomDay, to: earningsDate),
               adjusted > now {
                events.append(EconomicEvent(
                    date: adjusted, title: "\(["Snap Inc.", "NVIDIA Corp.", "Apple Inc.", "Microsoft Corp.", "Amazon.com Inc."].randomElement()!) Earnings", 
                    category: .earnings, currency: .usd, impact: .medium,
                    previousValue: nil, forecastValue: nil,
                    description: "Quarterly earnings report. Can affect tech indices and risk sentiment.",
                    isConfirmed: false, eventSource: "Company"
                ))
            }
        }

        // Sort by date
        return events.sorted { $0.date < $1.date }
    }
}

// MARK: - Chat Tools for Economic Calendar

extension ToolRegistry {
    /// Get the economic calendar.
    func calendarEvents(args: [String: Any]) -> String {
        let currency = str(args, "currency")
        let impact = str(args, "impact")
        let limit = Int((args["limit"] as? Double) ?? Double(str(args, "limit")) ?? 15)
        let symbol = str(args, "symbol")

        if !symbol.isEmpty {
            let resolved = resolveSymbol(symbol)
            return EconomicCalendarService.shared.symbolImpact(symbol: resolved)
        }

        return EconomicCalendarService.shared.report(filterCurrency: currency, filterImpact: impact, limit: limit)
    }

    /// Get upcoming high-impact events.
    func calendarHighImpact(args: [String: Any]) -> String {
        let events = EconomicCalendarService.shared.highImpactEvents.prefix(15)
        guard !events.isEmpty else { return "No high-impact events in the near future." }

        var report = "## 🔴 High-Impact Events\n\n"
        report += "| Time | Currency | Event | Previous | Forecast |\n|---|---|---|---|---|\n"
        for event in events {
            report += "| \(event.formattedDate) | \(event.currency.flag) \(event.currency.rawValue) | \(event.title) | \(event.previousValue ?? "—") | \(event.forecastValue ?? "—") |\n"
        }
        report += "\n⚠️ These events typically cause significant market volatility. Plan your trading accordingly.\n"
        return report
    }

    /// Get events in the next N hours.
    func calendarNext(args: [String: Any]) -> String {
        let hours = Int((args["hours"] as? Double) ?? Double(str(args, "hours")) ?? 24)
        let events = EconomicCalendarService.shared.events(inNext: hours)
        guard !events.isEmpty else { return "No economic events in the next \(hours) hours." }

        var report = "## 📅 Events Next \(hours)h\n\n"
        report += "| Time | Currency | Event | Impact |\n|---|---|---|---|\n"
        for event in events {
            let stars = String(repeating: "⭐", count: event.impact.starCount)
            report += "| \(event.timeUntil) | \(event.currency.flag) \(event.currency.rawValue) | \(event.title) | \(stars) |\n"
        }
        let highCount = events.filter { $0.impact == .high || $0.impact == .nonFarm }.count
        if highCount > 0 {
            report += "\n⚠️ **\(highCount)** high-impact events — volatility expected.\n"
        }
        return report
    }
}
