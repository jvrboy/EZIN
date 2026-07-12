import SwiftUI

/// Bot tab — a window into the backend runtime (agents/council run hidden, this is read-only status).
struct BotView: View {
    @EnvironmentObject var app: AppState
    @State private var descriptors: [BotDescriptor] = []
    private let timer = Timer.publish(every: 3, on: .main, in: .common).autoconnect()

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                statusCard

                HStack {
                    Text("Council Agents").font(.headline).foregroundStyle(.white.opacity(0.9))
                    Spacer()
                    Text("hidden backend").font(.caption2).foregroundStyle(.white.opacity(0.4))
                }

                ForEach(descriptors) { d in AgentRow(descriptor: d) }

                pipelinesCard
            }
            .padding(.horizontal, 16).padding(.bottom, 24)
        }
        .onAppear(perform: refresh)
        .onReceive(timer) { _ in refresh() }
    }

    private func refresh() {
        descriptors = app.engine.botDescriptors(lastVotes: app.botRuntime.lastVotes)
    }

    private var statusCard: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(LinearGradient(colors: [Glass.accent, Glass.accent2], startPoint: .top, endPoint: .bottom))
                    .frame(width: 52, height: 52).opacity(0.25)
                Image(systemName: "cpu").font(.system(size: 22, weight: .semibold)).foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("Engine \(app.botRuntime.running ? "running" : "idle")")
                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(.white.opacity(0.9))
                Text("\(descriptors.count) agents · consensus council · \(app.connectionState.label)")
                    .font(.caption2).foregroundStyle(.white.opacity(0.5))
            }
            Spacer()
            Circle().fill(app.botRuntime.running ? Glass.buy : Glass.sell).frame(width: 10, height: 10)
        }
        .padding(16).glassCard(strong: true)
    }

    private var pipelinesCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Active Pipelines").font(.subheadline).foregroundStyle(.white.opacity(0.7))
            ForEach(app.pipelines.pipelines.filter { $0.enabled }) { p in
                HStack {
                    Image(systemName: "point.3.connected.trianglepath.dotted")
                        .foregroundStyle(Glass.accent2)
                    Text(p.name).font(.system(size: 13)).foregroundStyle(.white.opacity(0.85))
                    Spacer()
                    Text("\(p.stages.count) stages").font(.caption2).foregroundStyle(.white.opacity(0.4))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16).glassCard()
    }
}

struct AgentRow: View {
    let descriptor: BotDescriptor
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "brain.head.profile").foregroundStyle(Glass.accent).frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(descriptor.name).font(.system(size: 14, weight: .medium)).foregroundStyle(.white.opacity(0.88))
                Text(descriptor.role).font(.caption2).foregroundStyle(.white.opacity(0.45))
            }
            Spacer()
            Text(descriptor.lastVote)
                .font(.system(size: 10, weight: .bold))
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(color.opacity(0.18)).foregroundStyle(color).clipShape(Capsule())
        }
        .padding(12).glassCard()
    }
    private var color: Color {
        switch descriptor.lastVote {
        case "BULL": return Glass.buy
        case "BEAR": return Glass.sell
        default: return .white.opacity(0.5)
        }
    }
}
