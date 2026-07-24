import SwiftUI
import PhotosUI

/// Trade Journal — log, review, and analyze your trades with notes, screenshots, and emotion tracking.
struct TradeJournalView: View {
    @ObservedObject private var store = TradeJournalStore.shared
    @State private var showingAdd = false
    @State private var filterOutcome: String = "all"
    @State private var searchText = ""

    var body: some View {
        VStack(spacing: 0) {
            // Stats summary bar
            statsBar

            // Filter bar
            filterBar

            // Entries list
            if filteredEntries.isEmpty {
                emptyState
            } else {
                entriesList
            }
        }
        .navigationTitle("Trade Journal")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { showingAdd = true } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAdd) {
            AddJournalEntryView()
        }
    }

    private var filteredEntries: [JournalEntry] {
        var entries = store.entries
        if !searchText.isEmpty {
            entries = entries.filter {
                $0.displayPair.localizedCaseInsensitiveContains(searchText) ||
                $0.notes.localizedCaseInsensitiveContains(searchText) ||
                $0.tags.contains { $0.localizedCaseInsensitiveContains(searchText) }
            }
        }
        switch filterOutcome {
        case "win": entries = entries.filter { $0.outcome == .win }
        case "loss": entries = entries.filter { $0.outcome == .loss }
        case "open": entries = entries.filter { $0.outcome == .open }
        default: break
        }
        return entries
    }

    private var statsBar: some View {
        let stats = store.statistics
        return HStack(spacing: 8) {
            StatBadge(value: "\(store.entries.count)", label: "Total", color: .white)
            StatBadge(value: "\(Int(stats.winRate * 100))%", label: "Win Rate", color: stats.winRate >= 0.5 ? Glass.buy : Glass.sell)
            StatBadge(value: stats.totalPnL >= 0 ? "+\(String(format: "%.0f", stats.totalPnL))" : "\(String(format: "%.0f", stats.totalPnL))",
                      label: "P&L", color: stats.totalPnL >= 0 ? Glass.buy : Glass.sell)
            StatBadge(value: "\(stats.consecutiveWins)", label: "🔥 Streak", color: .orange)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .glassCard(corner: 0)
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                FilterChip(title: "All", isSelected: filterOutcome == "all") { filterOutcome = "all" }
                FilterChip(title: "Wins", isSelected: filterOutcome == "win") { filterOutcome = "win" }
                FilterChip(title: "Losses", isSelected: filterOutcome == "loss") { filterOutcome = "loss" }
                FilterChip(title: "Open", isSelected: filterOutcome == "open") { filterOutcome = "open" }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }

    private var entriesList: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(filteredEntries) { entry in
                    NavigationLink(destination: JournalEntryDetailView(entry: entry)) {
                        JournalEntryCard(entry: entry)
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
            Image(systemName: "book.fill")
                .font(.system(size: 50))
                .foregroundStyle(Glass.accent2.opacity(0.5))
            Text("Your Trade Journal is empty")
                .font(.headline)
                .foregroundStyle(.white.opacity(0.7))
            Text("Log your first trade to start building\na record of your trading decisions.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.4))
                .multilineTextAlignment(.center)
            Button { showingAdd = true } label: {
                Label("Log a Trade", systemImage: "plus")
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(Glass.accent)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
            .buttonStyle(.plain)
            Spacer()
        }
    }
}

// MARK: - Journal Entry Card

struct JournalEntryCard: View {
    let entry: JournalEntry

    var body: some View {
        HStack(spacing: 12) {
            // Direction & outcome badge
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(bgColor.opacity(0.2))
                Text(entry.direction.isBullish ? "B" : "S")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(bgColor)
            }
            .frame(width: 40, height: 40)

            // Info
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(entry.displayPair)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                    if let emotion = entry.emotion {
                        Text(emotion.rawValue)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(emotion.isNegative ? Color.red.opacity(0.2) : Color.green.opacity(0.2))
                            .cornerRadius(4)
                            .foregroundStyle(emotion.isNegative ? Glass.sell : Glass.buy)
                    }
                }
                HStack(spacing: 6) {
                    Text("@ \(fmt(entry.entryPrice))")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.5))
                    if let exit = entry.exitPrice {
                        Text("→ \(fmt(exit))")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    if let pnl = entry.pnl {
                        Text("\(pnl >= 0 ? "+" : "")\(fmt(pnl))")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(pnl >= 0 ? Glass.buy : Glass.sell)
                    }
                }
            }

            Spacer()

            // Outcome indicator
            Text(entry.outcome.rawValue)
                .font(.system(size: 11, weight: .medium))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(outcomeColor.opacity(0.2))
                .cornerRadius(6)
                .foregroundStyle(outcomeColor)
        }
        .padding(12)
        .glassCard()
    }

    private var bgColor: Color {
        entry.direction.isBullish ? Glass.buy : Glass.sell
    }

    private var outcomeColor: Color {
        switch entry.outcome {
        case .win: return Glass.buy
        case .loss: return Glass.sell
        case .breakeven: return .orange
        case .open: return .yellow
        }
    }

    private func fmt(_ v: Double) -> String {
        v > 100 ? String(format: "%.1f", v) : String(format: "%.4f", v)
    }
}

// MARK: - Journal Entry Detail

struct JournalEntryDetailView: View {
    @ObservedObject private var store = TradeJournalStore.shared
    @State var entry: JournalEntry
    @State private var showingClose = false
    @State private var showingPhotoPicker = false
    @State private var photoItem: PhotosPickerItem?
    @State private var exitPrice = ""
    @State private var pnlAmount = ""
    @State private var selectedOutcome: JournalOutcome = .win
    @State private var exitEmotion: TradeEmotion?
    @State private var newLesson = ""
    @State private var newMistake = ""
    @State private var showingDeleteAlert = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Header card
                headerCard

                // Trade details
                detailsCard

                // Notes
                notesCard

                // Emotions
                emotionsCard

                // Lessons & Mistakes
                lessonsCard

                // Tags
                tagsCard

                // Screenshots
                screenshotsCard

                // Close trade button (if open)
                if entry.outcome == .open {
                    Button { showingClose = true } label: {
                        Label("Close Trade", systemImage: "flag.fill")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Glass.accent)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                    }
                    .buttonStyle(.plain)
                }

                // Delete
                Button(role: .destructive) { showingDeleteAlert = true } label: {
                    Label("Delete Entry", systemImage: "trash")
                        .foregroundStyle(Glass.sell)
                }
                .buttonStyle(.plain)
            }
            .padding(16)
        }
        .navigationTitle("Trade Details")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingClose) {
            closeTradeSheet
        }
        .alert("Delete Entry", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                store.remove(entry)
            }
        } message: {
            Text("Are you sure you want to delete this journal entry? Screenshots will also be removed.")
        }
        .photosPicker(isPresented: $showingPhotoPicker, selection: $photoItem, matching: .images)
        .onChange(of: photoItem) { newItem in
            guard let item = newItem else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    _ = store.addScreenshot(to: entry.id, imageData: data)
                    if let idx = store.entries.firstIndex(where: { $0.id == entry.id }) {
                        entry = store.entries[idx]
                    }
                }
            }
        }
    }

    private var headerCard: some View {
        VStack(spacing: 12) {
            HStack {
                Text(entry.displayPair)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
                Spacer()
                Text(entry.outcome.rawValue)
                    .font(.headline)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(outcomeColor.opacity(0.2))
                    .cornerRadius(8)
                    .foregroundStyle(outcomeColor)
            }
            HStack(spacing: 20) {
                Label(entry.direction.isBullish ? "BUY" : "SELL", systemImage: entry.direction.isBullish ? "arrow.up" : "arrow.down")
                    .foregroundStyle(entry.direction.isBullish ? Glass.buy : Glass.sell)
                Text(entry.setupType.rawValue)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.6))
            }
            if let pnl = entry.pnl {
                Text("\(pnl >= 0 ? "+" : "")\(fmt(pnl))")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(pnl >= 0 ? Glass.buy : Glass.sell)
            }
        }
        .padding()
        .glassCard()
    }

    private var detailsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("TRADE DETAILS")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.5))

            DetailRow(label: "Entry", value: fmt(entry.entryPrice))
            DetailRow(label: "Exit", value: entry.exitPrice.map { fmt($0) } ?? "—")
            DetailRow(label: "Stop Loss", value: entry.stopLoss.map { fmt($0) } ?? "—")
            DetailRow(label: "Take Profit", value: entry.takeProfit.map { fmt($0) } ?? "—")
            DetailRow(label: "Quantity", value: fmt(entry.quantity))
            DetailRow(label: "R:R", value: entry.rr.map { String(format: "%.2f", $0) } ?? "—")
            DetailRow(label: "Timeframe", value: entry.timeframe.rawValue)
            DetailRow(label: "Entry Date", value: entry.entryDate.formatted(date: .abbreviated, time: .shortened))
            if let exit = entry.exitDate {
                DetailRow(label: "Exit Date", value: exit.formatted(date: .abbreviated, time: .shortened))
            }
            if let held = entry.barsHeld {
                DetailRow(label: "Held", value: "\(held) min")
            }
        }
        .padding()
        .glassCard()
    }

    private var notesCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("NOTES")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.5))

            if entry.notes.isEmpty {
                Text("No notes recorded.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.4))
                    .padding(.vertical, 8)
            } else {
                Text(entry.notes)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.75))
            }
        }
        .padding()
        .glassCard()
    }

    private var emotionsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("EMOTIONS")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.5))

            HStack(spacing: 16) {
                VStack(spacing: 4) {
                    Text("Entry")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.4))
                    Text(entry.emotion?.rawValue ?? "—")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(entry.emotion?.isNegative == true ? Glass.sell : Glass.buy)
                }
                VStack(spacing: 4) {
                    Text("Exit")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.4))
                    Text(entry.emotionExit?.rawValue ?? "—")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(entry.emotionExit?.isNegative == true ? Glass.sell : Glass.buy)
                }
            }
        }
        .padding()
        .glassCard()
    }

    private var lessonsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("LESSONS & MISTAKES")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.5))

            if !entry.lessons.isEmpty {
                ForEach(entry.lessons, id: \.self) { lesson in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "lightbulb.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.yellow)
                        Text(lesson)
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
            }

            if !entry.mistakes.isEmpty {
                ForEach(entry.mistakes, id: \.self) { mistake in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(Glass.sell)
                        Text(mistake)
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
            }

            HStack(spacing: 8) {
                TextField("Add a lesson...", text: $newLesson)
                    .textFieldStyle(.plain)
                    .foregroundStyle(.white)
                    .padding(10)
                    .background(Color.white.opacity(0.06))
                    .cornerRadius(8)
                Button("Add") {
                    guard !newLesson.isEmpty else { return }
                    entry.lessons.append(newLesson)
                    store.update(entry)
                    newLesson = ""
                }
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Glass.accent)
                .foregroundColor(.white)
                .cornerRadius(8)
                .buttonStyle(.plain)
            }

            HStack(spacing: 8) {
                TextField("Add a mistake...", text: $newMistake)
                    .textFieldStyle(.plain)
                    .foregroundStyle(.white)
                    .padding(10)
                    .background(Color.white.opacity(0.06))
                    .cornerRadius(8)
                Button("Add") {
                    guard !newMistake.isEmpty else { return }
                    entry.mistakes.append(newMistake)
                    store.update(entry)
                    newMistake = ""
                }
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Glass.accent)
                .foregroundColor(.white)
                .cornerRadius(8)
                .buttonStyle(.plain)
            }
        }
        .padding()
        .glassCard()
    }

    private var tagsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("TAGS")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.5))

            if entry.tags.isEmpty {
                Text("No tags.")
                    .foregroundStyle(.white.opacity(0.4))
            } else {
                FlowLayout(spacing: 6) {
                    ForEach(entry.tags, id: \.self) { tag in
                        Text("#\(tag)")
                            .font(.caption)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Glass.accent2.opacity(0.2))
                            .cornerRadius(6)
                            .foregroundStyle(Glass.accent2)
                    }
                }
            }
        }
        .padding()
        .glassCard()
    }

    private var screenshotsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("SCREENSHOTS")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.5))
                Spacer()
                Button { showingPhotoPicker = true } label: {
                    Image(systemName: "camera.fill")
                        .foregroundStyle(Glass.accent2)
                }
                .buttonStyle(.plain)
            }

            if entry.screenshotPaths.isEmpty {
                Text("No screenshots.")
                    .foregroundStyle(.white.opacity(0.4))
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(entry.screenshotPaths, id: \.self) { path in
                            let url = FileStore.shared.dataDir.appendingPathComponent("TradeJournal").appendingPathComponent(path)
                            if let image = UIImage(contentsOfFile: url.path) {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 120, height: 120)
                                    .cornerRadius(8)
                            }
                        }
                    }
                }
            }
        }
        .padding()
        .glassCard()
    }

    private var closeTradeSheet: some View {
        NavigationView {
            Form {
                Section("Exit Details") {
                    TextField("Exit Price", text: $exitPrice)
                        .keyboardType(.decimalPad)
                    TextField("P&L Amount", text: $pnlAmount)
                        .keyboardType(.decimalPad)
                    Picker("Outcome", selection: $selectedOutcome) {
                        ForEach([JournalOutcome.win, .loss, .breakeven], id: \.self) { o in
                            Text(o.rawValue).tag(o)
                        }
                    }
                    Picker("Exit Emotion", selection: $exitEmotion) {
                        Text("None").tag(nil as TradeEmotion?)
                        ForEach(TradeEmotion.allCases) { e in
                            Text(e.rawValue).tag(e as TradeEmotion?)
                        }
                    }
                }
            }
            .navigationTitle("Close Trade")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showingClose = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Close") {
                        guard let exit = Double(exitPrice) else { return }
                        let pnl = Double(pnlAmount) ?? 0
                        store.closeTrade(id: entry.id, exitPrice: exit, outcome: selectedOutcome, pnl: pnl, exitEmotion: exitEmotion)
                        if let idx = store.entries.firstIndex(where: { $0.id == entry.id }) {
                            entry = store.entries[idx]
                        }
                        showingClose = false
                    }
                    .disabled(exitPrice.isEmpty)
                }
            }
        }
    }

    private var outcomeColor: Color {
        switch entry.outcome {
        case .win: return Glass.buy
        case .loss: return Glass.sell
        case .breakeven: return .orange
        case .open: return .yellow
        }
    }

    private func fmt(_ v: Double) -> String {
        v > 100 ? String(format: "%.1f", v) : String(format: "%.4f", v)
    }
}

// MARK: - Add Journal Entry View

struct AddJournalEntryView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = TradeJournalStore.shared

    @State private var symbol = "R_100"
    @State private var direction: Direction = .bullish
    @State private var entryPrice = ""
    @State private var stopLoss = ""
    @State private var takeProfit = ""
    @State private var quantity = "1.0"
    @State private var setupType: TradeSetupType = .manual
    @State private var emotion: TradeEmotion?
    @State private var notes = ""
    @State private var tags = ""
    @State private var rating = 3

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {
                    // Instrument & Direction
                    GlassSection(title: "Trade") {
                        HStack(spacing: 12) {
                            Menu {
                                ForEach(DerivSymbols.shortList.prefix(40), id: \.self) { sym in
                                    Button(DerivSymbols.display(sym)) { symbol = sym }
                                }
                            } label: {
                                HStack {
                                    Text(DerivSymbols.display(symbol))
                                        .foregroundStyle(.white)
                                    Image(systemName: "chevron.down")
                                        .font(.caption)
                                        .foregroundStyle(.white.opacity(0.5))
                                }
                                .padding(10)
                                .background(Color.white.opacity(0.06))
                                .cornerRadius(8)
                            }

                            Picker("Direction", selection: $direction) {
                                Text("BUY").tag(Direction.bullish)
                                Text("SELL").tag(Direction.bearish)
                            }
                            .pickerStyle(.segmented)
                        }

                        GlassField(placeholder: "Entry Price", text: $entryPrice)
                        GlassField(placeholder: "Stop Loss (optional)", text: $stopLoss)
                        GlassField(placeholder: "Take Profit (optional)", text: $takeProfit)
                        GlassField(placeholder: "Quantity / Stake", text: $quantity)
                    }

                    // Setup Type
                    GlassSection(title: "Setup") {
                        Picker("Type", selection: $setupType) {
                            ForEach(TradeSetupType.allCases) { t in
                                Text(t.rawValue).tag(t)
                            }
                        }
                    }

                    // Emotion
                    GlassSection(title: "Emotion at Entry") {
                        Picker("Emotion", selection: $emotion) {
                            Text("None").tag(nil as TradeEmotion?)
                            ForEach(TradeEmotion.allCases) { e in
                                HStack {
                                    Image(systemName: e.icon)
                                    Text(e.rawValue)
                                }.tag(e as TradeEmotion?)
                            }
                        }
                    }

                    // Notes
                    GlassSection(title: "Notes") {
                        TextEditor(text: $notes)
                            .frame(minHeight: 80)
                            .foregroundStyle(.white)
                            .scrollContentBackground(.hidden)
                            .background(Color.white.opacity(0.06))
                            .cornerRadius(8)
                    }

                    // Tags
                    GlassSection(title: "Tags") {
                        GlassField(placeholder: "comma-separated tags", text: $tags)
                    }

                    // Rating
                    GlassSection(title: "Rating") {
                        HStack(spacing: 8) {
                            ForEach(1...5, id: \.self) { star in
                                Button {
                                    rating = star
                                } label: {
                                    Image(systemName: star <= rating ? "star.fill" : "star")
                                        .foregroundStyle(.yellow)
                                        .font(.title3)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(16)
            }
            .navigationTitle("New Journal Entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard let price = Double(entryPrice), price > 0 else { return }
                        let entry = JournalEntry(
                            symbol: symbol,
                            direction: direction,
                            entryPrice: price,
                            exitPrice: nil,
                            stopLoss: Double(stopLoss),
                            takeProfit: Double(takeProfit),
                            quantity: Double(quantity) ?? 1.0,
                            outcome: .open,
                            pnl: nil,
                            entryDate: Date(),
                            setupType: setupType,
                            emotion: emotion,
                            notes: notes,
                            tags: tags.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty },
                            rating: rating
                        )
                        store.add(entry)
                        dismiss()
                    }
                    .disabled(entryPrice.isEmpty)
                }
            }
        }
    }
}

// MARK: - Supporting Views

struct StatBadge: View {
    let value: String
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity)
    }
}

struct FilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(isSelected ? Glass.accent : Color.white.opacity(0.08))
                .foregroundColor(isSelected ? .white : .white.opacity(0.6))
                .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
}

struct DetailRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.5))
            Spacer()
            Text(value)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white.opacity(0.85))
        }
    }
}

/// Simple flow layout for tags
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        var width: CGFloat = 0
        var height: CGFloat = 0
        var x: CGFloat = 0
        var y: CGFloat = 0
        var maxHeight: CGFloat = 0

        for size in sizes {
            if x + size.width > (proposal.width ?? .infinity) {
                x = 0
                y += maxHeight + spacing
                maxHeight = 0
            }
            x += size.width + spacing
            maxHeight = max(maxHeight, size.height)
            width = max(width, x)
            height = y + maxHeight
        }
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        var x = bounds.minX
        var y = bounds.minY
        var maxHeight: CGFloat = 0

        for (index, subview) in subviews.enumerated() {
            let size = sizes[index]
            if x + size.width > bounds.maxX {
                x = bounds.minX
                y += maxHeight + spacing
                maxHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            maxHeight = max(maxHeight, size.height)
        }
    }
}

// DerivSymbols helper for journal picker
private extension DerivSymbols {
    static var shortList: [String] {
        let synths = volatility.prefix(10)
        let forex = ["EUR/USD", "GBP/USD", "USD/JPY", "USD/CAD", "AUD/USD", "EUR/JPY", "GBP/JPY"]
        let crypto = ["BTC/USD", "ETH/USD"]
        return Array(synths) + forex + crypto
    }
}
