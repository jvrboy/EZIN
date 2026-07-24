import SwiftUI

/// Economic Calendar — displays upcoming economic events with impact ratings, countdowns, and filters.
struct EconomicCalendarView: View {
    @StateObject private var service = EconomicCalendarService.shared
    @State private var filterCurrency: String = "all"
    @State private var filterImpact: String = "all"
    @State private var searchText = ""

    private let currencies: [(String, String)] = [
        ("all", "🌐 All"), ("usd", "🇺🇸 USD"), ("eur", "🇪🇺 EUR"),
        ("gbp", "🇬🇧 GBP"), ("jpy", "🇯🇵 JPY"), ("cad", "🇨🇦 CAD"),
        ("aud", "🇦🇺 AUD"), ("nzd", "🇳🇿 NZD"), ("chf", "🇨🇭 CHF")
    ]

    private let impacts: [(String, String)] = [
        ("all", "All"), ("high", "🔴 High"), ("medium", "🟡 Medium"), ("low", "🟢 Low")
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Filter bar
            filterSection

            // Event list
            if filteredEvents.isEmpty {
                emptyState
            } else {
                eventsList
            }
        }
        .navigationTitle("Economic Calendar")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var filteredEvents: [EconomicEvent] {
        var events = service.upcomingEvents
        if filterCurrency != "all" {
            let cur = EventCurrency.allCases.first { $0.rawValue.lowercased() == filterCurrency }
            if let c = cur { events = events.filter { $0.currency == c } }
        }
        switch filterImpact {
        case "high": events = events.filter { $0.impact == EventImpact.high || $0.impact == EventImpact.nonFarm }
        case "medium": events = events.filter { $0.impact == .medium }
        case "low": events = events.filter { $0.impact == .low }
        default: break
        }
        if !searchText.isEmpty {
            events = events.filter {
                $0.title.localizedCaseInsensitiveContains(searchText) ||
                $0.description.localizedCaseInsensitiveContains(searchText) ||
                $0.currency.rawValue.localizedCaseInsensitiveContains(searchText)
            }
        }
        return events
    }

    private var filterSection: some View {
        VStack(spacing: 8) {
            // Search
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.white.opacity(0.4))
                TextField("Search events...", text: $searchText)
                    .textFieldStyle(.plain)
                    .foregroundStyle(.white)
            }
            .padding(10)
            .background(Color.white.opacity(0.06))
            .cornerRadius(10)
            .padding(.horizontal, 16)
            .padding(.top, 8)

            // Currency & Impact filters
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(currencies, id: \.0) { (key, label) in
                        FilterChip(title: label, isSelected: filterCurrency == key) {
                            filterCurrency = key
                        }
                    }
                    Divider()
                        .frame(height: 20)
                        .foregroundStyle(.white.opacity(0.2))
                    ForEach(impacts, id: \.0) { (key, label) in
                        FilterChip(title: label, isSelected: filterImpact == key) {
                            filterImpact = key
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }
        }
    }

    private var eventsList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(filteredEvents) { event in
                    NavigationLink(destination: EventDetailView(event: event)) {
                        EventCard(event: event)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(16)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.system(size: 50))
                .foregroundStyle(Glass.accent2.opacity(0.5))
            Text("No events match your filters")
                .font(.headline)
                .foregroundStyle(.white.opacity(0.7))
            Text("Try adjusting the currency or impact filters.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.4))
            Spacer()
        }
    }
}

// MARK: - Event Card

struct EventCard: View {
    let event: EconomicEvent
    @State private var timeRemaining: String = ""

    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 12) {
            // Time column
            VStack(spacing: 4) {
                Text(timeUntilString)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(event.impact == EventImpact.nonFarm ? .red : .white.opacity(0.6))
                Text(formattedTime)
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.4))
            }
            .frame(width: 65)

            // Currency flag
            Text(event.currency.flag)
                .font(.title2)

            // Event info
            VStack(alignment: .leading, spacing: 3) {
                Text(event.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(1)
                Text(event.category.rawValue)
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.4))
                if let prev = event.previousValue, let fore = event.forecastValue {
                    Text("Prev: \(prev) · Fcast: \(fore)")
                        .font(.system(size: 9))
                        .foregroundStyle(.white.opacity(0.35))
                }
            }

            Spacer()

            // Impact stars
            VStack(spacing: 2) {
                Text(String(repeating: "⭐", count: event.impact.starCount))
                    .font(.system(size: 8))
                Text(event.impact.rawValue)
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(impactColor)
            }
            .frame(width: 50)
        }
        .padding(12)
        .glassCard()
        .onReceive(timer) { _ in
            // Re-trigger view update
        }
    }

    private var timeUntilString: String {
        let interval = event.date.timeIntervalSinceNow
        if interval < 0 { return "NOW" }
        let hours = Int(interval) / 3600
        let minutes = Int(interval) / 60 % 60
        if hours > 24 { return "\(hours / 24)d" }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }

    private var formattedTime: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: event.date)
    }

    private var impactColor: Color {
        switch event.impact {
        case .low: return .green
        case .medium: return .yellow
        case .high: return .orange
        case .nonFarm: return .red
        }
    }
}

// MARK: - Event Detail View

struct EventDetailView: View {
    let event: EconomicEvent
    @State private var timeRemaining: String = ""

    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Header
                VStack(spacing: 8) {
                    Text(event.currency.flag)
                        .font(.system(size: 60))
                    Text(event.title)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                    Text(event.category.rawValue)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.5))
                }
                .padding()
                .glassCard()

                // Countdown
                VStack(spacing: 8) {
                    Text(event.isUpcoming ? "Time until release" : "Released")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.5))
                    Text(timeUntilString)
                        .font(.system(size: 36, weight: .bold, design: .monospaced))
                        .foregroundStyle(event.impact == EventImpact.nonFarm ? .red : Glass.accent2)
                }
                .padding()
                .glassCard()

                // Details
                VStack(alignment: .leading, spacing: 12) {
                    Text("DETAILS")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.5))

                    DetailRow(label: "Date", value: event.formattedDate)
                    DetailRow(label: "Currency", value: "\(event.currency.flag) \(event.currency.rawValue)")
                    DetailRow(label: "Impact", value: event.impact.rawValue)
                    DetailRow(label: "Previous", value: event.previousValue ?? "—")
                    DetailRow(label: "Forecast", value: event.forecastValue ?? "—")
                    DetailRow(label: "Source", value: event.eventSource)
                    DetailRow(label: "Schedule", value: event.isConfirmed ? "Confirmed" : "Estimated")
                }
                .padding()
                .glassCard()

                // Description
                VStack(alignment: .leading, spacing: 8) {
                    Text("WHAT THIS MEASURES")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.5))
                    Text(event.description)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.7))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding()
                .glassCard()

                // Trading tips
                if event.impact == EventImpact.high || event.impact == EventImpact.nonFarm {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("⚡ TRADING TIPS")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.orange)

                        Text("""
                        • This is a high-impact event that can cause significant market volatility
                        • Consider reducing position sizes 15 minutes before the release
                        • Wait for the initial volatility spike (5-10 min) before entering
                        • Set wider stops to avoid being stopped out by erratic movements
                        • Both outcomes (beat/miss) can produce sharp moves in either direction
                        """)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                    }
                    .padding()
                    .glassCard()
                }
            }
            .padding(16)
        }
        .navigationTitle("Event Details")
        .navigationBarTitleDisplayMode(.inline)
        .onReceive(timer) { _ in
            let interval = event.date.timeIntervalSinceNow
            if interval < 0 {
                timeRemaining = "NOW"
            } else {
                let hours = Int(interval) / 3600
                let minutes = (Int(interval) / 60) % 60
                let seconds = Int(interval) % 60
                timeRemaining = String(format: "%02d:%02d:%02d", hours, minutes, seconds)
            }
        }
    }

    private var timeUntilString: String {
        let interval = event.date.timeIntervalSinceNow
        if interval < 0 { return "RELEASED" }
        let days = Int(interval) / 86400
        let hours = (Int(interval) / 3600) % 24
        let minutes = (Int(interval) / 60) % 60
        let seconds = Int(interval) % 60
        if days > 0 { return "\(days)d \(hours)h \(minutes)m" }
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }
}
