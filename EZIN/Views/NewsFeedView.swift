import SwiftUI

struct NewsFeedView: View {
    @StateObject private var feed = NewsFeedService.shared
    @State private var showBookmarks = false
    @State private var searchText = ""

    var body: some View {
        ZStack {
            AuroraBackground()
            VStack(spacing: 0) {
                // Category Filter Pills
                categoryScroll

                // News List
                if showBookmarks {
                    bookmarksList
                } else {
                    newsList
                }
            }
        }
        .navigationTitle(showBookmarks ? "Bookmarked News" : "Market News")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        showBookmarks.toggle()
                    }
                } label: {
                    Image(systemName: showBookmarks ? "bookmark.fill" : "bookmark")
                        .foregroundStyle(showBookmarks ? Glass.accent2 : .white.opacity(0.6))
                        .font(.system(size: 15, weight: .semibold))
                }
            }
        }
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search news, symbols...")
        .onChange(of: searchText) { newValue in
            feed.searchQuery = newValue
        }
    }

    // MARK: - Category Scroll

    private var categoryScroll: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // All
                CategoryPill(title: "All", icon: "newspaper", isSelected: feed.selectedCategory == nil) {
                    withAnimation { feed.selectedCategory = nil }
                }
                ForEach(NewsItem.NewsCategory.allCases, id: \.self) { cat in
                    CategoryPill(title: cat.rawValue, icon: categoryIcon(cat),
                                 isSelected: feed.selectedCategory == cat) {
                        withAnimation { feed.selectedCategory = cat }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    private func categoryIcon(_ cat: NewsItem.NewsCategory) -> String {
        switch cat {
        case .宏观经济: return "globe"
        case .earnings: return "chart.bar.fill"
        case .centralBank: return "banknote.fill"
        case .geopolitics: return "flag.fill"
        case .commodities: return "drop.fill"
        case .crypto: return "bitcoinsign.circle.fill"
        case .forex: return "dollarsign.circle.fill"
        case .technology: return "cpu.fill"
        case .regulation: return "gavel.fill"
        case .marketAnalysis: return "magnifyingglass"
        }
    }

    // MARK: - News List

    private var newsList: some View {
        let items = feed.filteredNews
        return Group {
            if items.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        // Stats bar
                        HStack {
                            HStack(spacing: 4) {
                                Circle().fill(Glass.buy).frame(width: 6, height: 6)
                                Text("\(items.filter { $0.sentiment.score > 0 }.count) bullish")
                                    .font(.caption2).foregroundStyle(.white.opacity(0.5))
                            }
                            HStack(spacing: 4) {
                                Circle().fill(Glass.sell).frame(width: 6, height: 6)
                                Text("\(items.filter { $0.sentiment.score < 0 }.count) bearish")
                                    .font(.caption2).foregroundStyle(.white.opacity(0.5))
                            }
                            Spacer()
                            Text("\(items.count) articles")
                                .font(.caption2).foregroundStyle(.white.opacity(0.35))
                        }
                        .padding(.horizontal, 4)
                        .padding(.bottom, 4)

                        ForEach(items) { item in
                            NewsCard(item: item, isBookmarked: feed.bookmarkedIDs.contains(item.id)) {
                                feed.toggleBookmark(item.id)
                            }
                            .transition(.opacity.combined(with: .scale(scale: 0.95)))
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                }
                .refreshable {
                    // Simulate a refresh — add a fresh generated item
                    let headlines = [
                        "Breaking: Major Economic Data Released — Markets React",
                        "Central Bank Governor Signals Policy Shift Ahead",
                        "Tech Stocks Rally on AI Earnings Optimism",
                        "Currency Volatility Spikes After Surprise Rate Decision",
                    ]
                    let headline = headlines.randomElement() ?? "Market Update"
                    let item = NewsFeedService.generateFromHeadline(headline)
                    feed.addNews(item)
                }
            }
        }
    }

    // MARK: - Bookmarks List

    private var bookmarksList: some View {
        let items = feed.bookmarkedNews
        return Group {
            if items.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "bookmark.slash.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(.white.opacity(0.2))
                    Text("No bookmarked articles")
                        .font(.headline).foregroundStyle(.white.opacity(0.5))
                    Text("Tap the bookmark icon on any news card to save it here")
                        .font(.caption).foregroundStyle(.white.opacity(0.3))
                        .multilineTextAlignment(.center)
                }
                .frame(maxHeight: .infinity)
                .padding(40)
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(items) { item in
                            NewsCard(item: item, isBookmarked: true) {
                                feed.toggleBookmark(item.id)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "newspaper")
                .font(.system(size: 40))
                .foregroundStyle(.white.opacity(0.2))
            Text("No articles match your filter")
                .font(.headline).foregroundStyle(.white.opacity(0.5))
            Button("Clear Filter") {
                withAnimation { feed.selectedCategory = nil }
            }
            .font(.caption).foregroundStyle(Glass.accent2)
        }
        .frame(maxHeight: .infinity)
        .padding(40)
    }
}

// MARK: - Category Pill

struct CategoryPill: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                Text(title)
                    .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
            }
            .foregroundStyle(isSelected ? .white : .white.opacity(0.6))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                Capsule()
                    .fill(isSelected ? Glass.accent.opacity(0.35) : .white.opacity(0.06))
            )
            .overlay(
                Capsule()
                    .stroke(isSelected ? Glass.accent.opacity(0.5) : .white.opacity(0.1), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - News Card

struct NewsCard: View {
    let item: NewsItem
    let isBookmarked: Bool
    let onBookmark: () -> Void

    @State private var showShare = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header: Source + Time + Bookmark
            HStack {
                // Source badge
                Text(item.source)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Glass.accent2.opacity(0.8))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Glass.accent2.opacity(0.12))
                    .clipShape(Capsule())

                Spacer()

                // Relative time
                Text(item.publishedAt, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.4))

                // Bookmark
                Button(action: onBookmark) {
                    Image(systemName: isBookmarked ? "bookmark.fill" : "bookmark")
                        .font(.system(size: 12))
                        .foregroundStyle(isBookmarked ? Glass.accent2 : .white.opacity(0.3))
                }
                .buttonStyle(.plain)
            }

            // Title
            Text(item.title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white.opacity(0.92))
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)

            // Summary
            Text(item.summary)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.55))
                .lineLimit(2)

            // Footer: Sentiment + Impact + Category
            HStack {
                // Sentiment badge
                HStack(spacing: 3) {
                    Circle()
                        .fill(sentimentColor)
                        .frame(width: 6, height: 6)
                    Text(item.sentiment.rawValue)
                        .font(.system(size: 10, weight: .medium))
                }
                .foregroundStyle(sentimentColor)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(sentimentColor.opacity(0.12))
                .clipShape(Capsule())

                // Impact badge
                Text(item.impact.rawValue.uppercased())
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(impactColor)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(impactColor.opacity(0.12))
                    .clipShape(Capsule())

                Spacer()

                // Category
                Text(item.category.rawValue)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.35))

                // Share button
                Button {
                    showShare = true
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.35))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .glassCard(corner: 16)
        .sheet(isPresented: $showShare) {
            let text = "\(item.title)\n\n\(item.summary)\n\n— EZIN News Feed"
            ShareSheet(activityItems: [text])
        }
    }

    private var sentimentColor: Color {
        switch item.sentiment {
        case .veryBullish, .bullish: return Glass.buy
        case .neutral: return .yellow
        case .veryBearish, .bearish: return Glass.sell
        }
    }

    private var impactColor: Color {
        switch item.impact {
        case .low: return .white.opacity(0.4)
        case .medium: return .yellow
        case .high: return .orange
        case .critical: return Glass.sell
        }
    }
}

// MARK: - ShareSheet (UIKit bridge)

struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
