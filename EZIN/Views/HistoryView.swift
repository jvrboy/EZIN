import SwiftUI

struct HistoryView: View {
    @EnvironmentObject var app: AppState

    private var wins: Int { app.history.filter { $0.win }.count }
    private var winRate: Int { app.history.isEmpty ? 0 : Int(Double(wins) / Double(app.history.count) * 100) }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                HStack(spacing: 12) {
                    StatCard(value: "\(winRate)%", label: "Win rate", color: .white)
                    StatCard(value: "\(wins)", label: "Wins", color: Glass.buy)
                    StatCard(value: "\(app.history.count - wins)", label: "Losses", color: Glass.sell)
                }

                VStack(spacing: 0) {
                    ForEach(Array(app.history.enumerated()), id: \.element.id) { idx, h in
                        HStack {
                            Circle().fill(h.win ? Glass.buy : Glass.sell).frame(width: 8, height: 8)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(h.displayPair).font(.system(size: 14, weight: .medium)).foregroundStyle(.white.opacity(0.88))
                                Text("\(dateStr(h.closedAt)) · \(h.isBuy ? "BUY" : "SELL")")
                                    .font(.caption2).foregroundStyle(.white.opacity(0.4))
                            }
                            Spacer()
                            Text("\(h.pips > 0 ? "+" : "")\(Int(h.pips)) pips")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(h.pips > 0 ? Glass.buy : Glass.sell)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 12)
                        if idx < app.history.count - 1 {
                            Divider().overlay(Color.white.opacity(0.08))
                        }
                    }
                }
                .glassCard()
            }
            .padding(.horizontal, 16).padding(.bottom, 24)
        }
    }

    private func dateStr(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "MMM d"; return f.string(from: d)
    }
}

struct StatCard: View {
    let value: String; let label: String; let color: Color
    var body: some View {
        VStack(spacing: 4) {
            Text(value).font(.system(size: 22, weight: .semibold)).foregroundStyle(color.opacity(0.95))
            Text(label).font(.caption2).foregroundStyle(.white.opacity(0.45))
        }
        .frame(maxWidth: .infinity).padding(.vertical, 16)
        .glassCard()
    }
}
