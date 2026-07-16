import SwiftUI

/// Performance Analytics View - Exposes snapshot and export features outside chat
struct PerformanceAnalyticsView: View {
    @StateObject private var store = SignalPerformanceStore.shared
    @State private var selectedSymbol: String?
    @State private var selectedTimeframe: Timeframe?
    @State private var showingExport = false
    @State private var showingSnapshot = false
    @State private var exportedCSV: String = ""
    @State private var showingShareSheet = false
    @State private var snapshotMarkdown: String = ""

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    headerSection
                    quickStatsSection
                    actionsSection
                    if showingSnapshot {
                        snapshotSection
                    }
                    recentPerformanceSection
                }
                .padding()
            }
            .navigationTitle("Performance Analytics")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button(action: { Task { await refreshData() } }) {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }
                        Button(action: { showingExport = true }) {
                            Label("Export CSV", systemImage: "square.and.arrow.up")
                        }
                        Button(action: { showingSnapshot.toggle() }) {
                            Label(showingSnapshot ? "Hide Snapshot" : "Show Snapshot", systemImage: "doc.text")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .sheet(isPresented: $showingExport) {
                ExportView(
                    csv: store.exportTrackedSignalsCSV(symbol: selectedSymbol, timeframe: selectedTimeframe),
                    onDismiss: { showingExport = false }
                )
            }
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading) {
                    Text("Signal Performance")
                        .font(.title2)
                        .fontWeight(.bold)
                    Text("Track win rates, expectancy, and export data")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.title)
                    .foregroundColor(.accentColor)
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
        }
    }

    private var quickStatsSection: some View {
        let snapshot = store.snapshot(symbol: selectedSymbol, timeframe: selectedTimeframe)

        return VStack(alignment: .leading, spacing: 12) {
            Text("Quick Stats")
                .font(.headline)

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                StatCard(
                    title: "Win Rate",
                    value: String(format: "%.1f%%", snapshot.winRate * 100),
                    icon: "chart.pie",
                    color: snapshot.winRate >= 0.55 ? .green : (snapshot.winRate >= 0.45 ? .orange : .red)
                )

                StatCard(
                    title: "Expectancy",
                    value: String(format: "%.4f", snapshot.expectancy),
                    icon: "plusminus",
                    color: snapshot.expectancy >= 0 ? .green : .red
                )

                StatCard(
                    title: "Sample Size",
                    value: "\(snapshot.resolvedCount)",
                    icon: "number",
                    color: .blue
                )

                StatCard(
                    title: "Active",
                    value: "\(snapshot.activeCount)",
                    icon: "clock",
                    color: .purple
                )

                StatCard(
                    title: "Avg Hold Time",
                    value: String(format: "%.1f min", snapshot.averageHoldMinutes),
                    icon: "timer",
                    color: .teal
                )

                StatCard(
                    title: "Streak",
                    value: streakText(snapshot.recentStreak),
                    icon: snapshot.recentStreak >= 0 ? "flame" : "snowflake",
                    color: snapshot.recentStreak >= 0 ? .orange : .blue
                )
            }

            if let best = snapshot.bestSymbol {
                HStack {
                    Image(systemName: "star.fill")
                        .foregroundColor(.yellow)
                    Text("Best Symbol: \(best)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }

            if let worst = snapshot.worstSymbol {
                HStack {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundColor(.orange)
                    Text("Weakest: \(worst)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    private var actionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Actions")
                .font(.headline)

            HStack(spacing: 12) {
                Button(action: {
                    snapshotMarkdown = store.formattedSnapshot(symbol: selectedSymbol, timeframe: selectedTimeframe)
                    showingSnapshot = true
                }) {
                    HStack {
                        Image(systemName: "doc.text")
                        Text("Generate Snapshot")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.accentColor)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }

                Button(action: {
                    exportedCSV = store.exportTrackedSignalsCSV(symbol: selectedSymbol, timeframe: selectedTimeframe)
                    showingShareSheet = true
                }) {
                    HStack {
                        Image(systemName: "square.and.arrow.up")
                        Text("Export CSV")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color(.systemGray5))
                    .foregroundColor(.primary)
                    .cornerRadius(10)
                }
            }

            // Symbol/Timeframe Filter
            VStack(alignment: .leading, spacing: 8) {
                Text("Filter By")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                HStack {
                    Picker("Symbol", selection: $selectedSymbol) {
                        Text("All Symbols").tag(nil as String?)
                        ForEach(DerivSymbols.synthetic + DerivSymbols.forex, id: \.self) { sym in
                            Text(DerivSymbols.display(sym)).tag(sym as String?)
                        }
                    }
                    .pickerStyle(.menu)

                    Picker("Timeframe", selection: $selectedTimeframe) {
                        Text("All").tag(nil as Timeframe?)
                        ForEach(Timeframe.allCases, id: \.self) { tf in
                            Text(tf.rawValue).tag(tf as Timeframe?)
                        }
                    }
                    .pickerStyle(.menu)
                }
            }
            .padding(.top, 8)
        }
    }

    @ViewBuilder
    private var snapshotSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Performance Snapshot")
                    .font(.headline)
                Spacer()
                Button(action: {
                    UIPasteboard.general.string = snapshotMarkdown
                }) {
                    Image(systemName: "doc.on.doc")
                        .foregroundColor(.accentColor)
                }
            }

            Text(snapshotMarkdown)
                .font(.system(.caption, design: .monospaced))
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(8)
                .textSelection(.enabled)
        }
        .padding()
        .background(Color(.systemGray5))
        .cornerRadius(12)
    }

    private var recentPerformanceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent Signals")
                .font(.headline)

            let recentSignals = Array(store.trackedSignals
                .sorted { $0.signal.createdAt > $1.signal.createdAt }
                .prefix(10))

            if recentSignals.isEmpty {
                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "tray")
                            .font(.largeTitle)
                            .foregroundColor(.secondary)
                        Text("No signals tracked yet")
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 40)
                    Spacer()
                }
            } else {
                ForEach(recentSignals, id: \.id) { tracked in
                    TrackedSignalRow(tracked: tracked)
                }
            }
        }
    }

    private func streakText(_ streak: Int) -> String {
        if streak > 0 {
            return "+\(streak)"
        } else if streak < 0 {
            return "\(streak)"
        } else {
            return "0"
        }
    }

    private func refreshData() async {
        // Refresh data from store; the @StateObject store drives view updates.
        await MainActor.run { store.objectWillChange.send() }
    }
}

// MARK: - Supporting Views

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                Spacer()
            }
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(10)
    }
}

struct TrackedSignalRow: View {
    let tracked: TrackedSignal

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(tracked.signal.displayPair)
                        .fontWeight(.semibold)
                    Text(tracked.signal.timeframe.rawValue)
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.gray.opacity(0.2))
                        .cornerRadius(4)
                }
                HStack {
                    Text(tracked.signal.type.rawValue)
                        .font(.caption)
                        .foregroundColor(tracked.signal.isBuy ? .green : .red)
                    Text("@\(String(format: "%.5f", tracked.signal.entry))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(tracked.status.rawValue.uppercased())
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(tracked.isWin ? .green : .red)
                Text(String(format: "%.2f%%", tracked.floatingPnL * 100))
                    .font(.caption)
                    .foregroundColor(tracked.floatingPnL >= 0 ? .green : .red)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }
}

struct ExportView: View {
    let csv: String
    let onDismiss: () -> Void
    @State private var showingShareSheet = false

    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Image(systemName: "doc.text")
                    .font(.system(size: 60))
                    .foregroundColor(.accentColor)

                Text("CSV Export Ready")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("Your signal data has been exported to CSV format.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                Spacer()

                VStack(spacing: 12) {
                    Button(action: {
                        showingShareSheet = true
                    }) {
                        HStack {
                            Image(systemName: "square.and.arrow.up")
                            Text("Share CSV")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.accentColor)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                    }

                    Button(action: {
                        UIPasteboard.general.string = csv
                    }) {
                        HStack {
                            Image(systemName: "doc.on.doc")
                            Text("Copy to Clipboard")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color(.systemGray5))
                        .foregroundColor(.primary)
                        .cornerRadius(10)
                    }
                }
                .padding()
            }
            .navigationTitle("Export")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        onDismiss()
                    }
                }
            }
            .sheet(isPresented: $showingShareSheet) {
                ShareSheet(items: [csv])
            }
        }
    }
}

// MARK: - Navigation Extension

extension View {
    func analyticsTab() -> some View {
        self.tabItem {
            Image(systemName: "chart.bar.doc.horizontal")
            Text("Analytics")
        }
    }
}
