import SwiftUI

/// Real-time signals tracker view showing active signals, performance metrics, and recommendations
struct SignalsTrackerView: View {
    @EnvironmentObject var app: AppState
    @StateObject private var tracker = SignalTracker()
    @State private var selectedTab: TrackerTab = .active
    @State private var showRecommendations = false
    
    enum TrackerTab: String, CaseIterable {
        case active = "Active"
        case closed = "Closed"
        case metrics = "Metrics"
        case recommendations = "Tips"
    }
    
    var body: some View {
        VStack(spacing: 12) {
            // Tab selector
            HStack(spacing: 6) {
                ForEach(TrackerTab.allCases, id: \.self) { tab in
                    Button {
                        selectedTab = tab
                    } label: {
                        Text(tab.rawValue)
                            .font(.system(size: 13, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .foregroundStyle(selectedTab == tab ? .white : .white.opacity(0.5))
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(selectedTab == tab ? Color.white.opacity(0.14) : .clear)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            
            // Content
            Group {
                switch selectedTab {
                case .active:
                    activeSignalsView
                case .closed:
                    closedSignalsView
                case .metrics:
                    metricsView
                case .recommendations:
                    recommendationsView
                }
            }
            
            Spacer()
        }
        .padding(.top, 12)
    }
    
    private var activeSignalsView: some View {
        ScrollView {
            VStack(spacing: 10) {
                if tracker.activeSignals.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "chart.line.uptrend.xyaxis")
                            .font(.system(size: 32, weight: .light))
                            .foregroundStyle(.white.opacity(0.3))
                        Text("No Active Signals")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                } else {
                    ForEach(tracker.activeSignals) { performance in
                        activeSignalCard(performance)
                    }
                }
            }
            .padding(.horizontal, 12)
        }
    }
    
    private func activeSignalCard(_ performance: SignalTracker.SignalPerformance) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(performance.signal.displayPair)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                    Text(performance.signal.type.rawValue.uppercased())
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(performance.signal.type.isBullish ? Glass.buy : Glass.sell)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    if let profit = performance.profit {
                        Text(String(format: "%.2f", profit))
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .foregroundStyle(profit >= 0 ? Glass.buy : Glass.sell)
                    }
                    if let profitPct = performance.profitPercent {
                        Text(String(format: "%.1f%%", profitPct))
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(profitPct >= 0 ? Glass.buy : Glass.sell)
                    }
                }
            }
            
            Divider().background(Color.white.opacity(0.1))
            
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Entry").font(.system(size: 10, weight: .semibold)).foregroundStyle(.white.opacity(0.5))
                    Text(String(format: "%.5f", performance.entryPrice))
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white)
                }
                
                VStack(alignment: .leading, spacing: 3) {
                    Text("SL").font(.system(size: 10, weight: .semibold)).foregroundStyle(.white.opacity(0.5))
                    Text(String(format: "%.5f", performance.signal.stopLoss))
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Glass.sell)
                }
                
                VStack(alignment: .leading, spacing: 3) {
                    Text("TP").font(.system(size: 10, weight: .semibold)).foregroundStyle(.white.opacity(0.5))
                    Text(String(format: "%.5f", performance.signal.takeProfit))
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Glass.buy)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 3) {
                    Text("Confidence").font(.system(size: 10, weight: .semibold)).foregroundStyle(.white.opacity(0.5))
                    Text(String(format: "%.0f%%", performance.signal.confidence))
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Glass.accent)
                }
            }
            
            HStack(spacing: 8) {
                Text("Opened: \(performance.entryTime.formatted(date: .omitted, time: .shortened))")
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.4))
                Spacer()
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.06)))
    }
    
    private var closedSignalsView: some View {
        ScrollView {
            VStack(spacing: 10) {
                if tracker.closedSignals.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "checkmark.circle")
                            .font(.system(size: 32, weight: .light))
                            .foregroundStyle(.white.opacity(0.3))
                        Text("No Closed Signals")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                } else {
                    ForEach(tracker.closedSignals.sorted { $0.exitTime ?? Date() > $1.exitTime ?? Date() }) { performance in
                        closedSignalCard(performance)
                    }
                }
            }
            .padding(.horizontal, 12)
        }
    }
    
    private func closedSignalCard(_ performance: SignalTracker.SignalPerformance) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(performance.signal.displayPair)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                    Text(performance.status.rawValue.uppercased())
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.5))
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    if let profit = performance.profit {
                        Text(String(format: "%.2f", profit))
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .foregroundStyle(performance.isWinning ? Glass.buy : Glass.sell)
                    }
                    if let profitPct = performance.profitPercent {
                        Text(String(format: "%.1f%%", profitPct))
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(performance.isWinning ? Glass.buy : Glass.sell)
                    }
                }
            }
            
            HStack(spacing: 12) {
                if let accuracy = performance.accuracy {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Accuracy").font(.system(size: 10, weight: .semibold)).foregroundStyle(.white.opacity(0.5))
                        Text(String(format: "%.0f%%", accuracy * 100))
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Glass.accent)
                    }
                }
                
                if let timeToProfit = performance.timeToProfit {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Duration").font(.system(size: 10, weight: .semibold)).foregroundStyle(.white.opacity(0.5))
                        Text(formatDuration(timeToProfit))
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.white)
                    }
                }
                
                Spacer()
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.06)))
    }
    
    private var metricsView: some View {
        ScrollView {
            VStack(spacing: 12) {
                metricsCard(title: "Win Rate", value: String(format: "%.1f%%", tracker.metrics.winRate * 100), color: Glass.buy)
                metricsCard(title: "Profit Factor", value: String(format: "%.2f", tracker.metrics.profitFactor), color: Glass.accent)
                metricsCard(title: "Total Profit", value: String(format: "%.2f", tracker.metrics.totalProfit), color: tracker.metrics.totalProfit >= 0 ? Glass.buy : Glass.sell)
                metricsCard(title: "Avg Win", value: String(format: "%.2f", tracker.metrics.averageProfit), color: Glass.buy)
                metricsCard(title: "Avg Loss", value: String(format: "%.2f", tracker.metrics.averageLoss), color: Glass.sell)
                metricsCard(title: "Best Trade", value: String(format: "%.2f", tracker.metrics.bestTrade), color: Glass.buy)
                metricsCard(title: "Worst Trade", value: String(format: "%.2f", tracker.metrics.worstTrade), color: Glass.sell)
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Signal Counts")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.7))
                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Total").font(.system(size: 10, weight: .semibold)).foregroundStyle(.white.opacity(0.5))
                            Text("\(tracker.metrics.totalSignals)")
                                .font(.system(size: 14, weight: .bold, design: .monospaced))
                                .foregroundStyle(.white)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Winning").font(.system(size: 10, weight: .semibold)).foregroundStyle(.white.opacity(0.5))
                            Text("\(tracker.metrics.winningSignals)")
                                .font(.system(size: 14, weight: .bold, design: .monospaced))
                                .foregroundStyle(Glass.buy)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Losing").font(.system(size: 10, weight: .semibold)).foregroundStyle(.white.opacity(0.5))
                            Text("\(tracker.metrics.losingSignals)")
                                .font(.system(size: 14, weight: .bold, design: .monospaced))
                                .foregroundStyle(Glass.sell)
                        }
                        Spacer()
                    }
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.06)))
            }
            .padding(.horizontal, 12)
        }
    }
    
    private func metricsCard(title: String, value: String, color: Color) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.6))
            }
            Spacer()
            Text(value)
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.06)))
    }
    
    private var recommendationsView: some View {
        ScrollView {
            VStack(spacing: 10) {
                let recommendations = tracker.getImprovementRecommendations()
                if recommendations.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "star.fill")
                            .font(.system(size: 32, weight: .light))
                            .foregroundStyle(Glass.accent)
                        Text("No Recommendations")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                        Text("Your strategy is performing well!")
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                } else {
                    ForEach(recommendations.indices, id: \.self) { index in
                        recommendationCard(index + 1, recommendations[index])
                    }
                }
            }
            .padding(.horizontal, 12)
        }
    }
    
    private func recommendationCard(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .center) {
                Text("\(number)")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(Glass.accent))
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(text)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(.white)
                    .lineLimit(nil)
            }
            
            Spacer()
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.06)))
    }
    
    private func formatDuration(_ interval: TimeInterval) -> String {
        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
}

#Preview {
    SignalsTrackerView()
        .environmentObject(AppState())
}
