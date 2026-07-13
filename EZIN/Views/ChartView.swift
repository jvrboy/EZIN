import SwiftUI

/// Chart tab — a clean candlestick chart. Chart only: price & time axes, a timeframe
/// selector and an instrument picker. Scrollable, zoomable, with unlimited history backfill.
struct ChartView: View {
    @EnvironmentObject var app: AppState
    @StateObject private var vm = ChartViewModel()

    var body: some View {
        VStack(spacing: 10) {
            selectorBar
            CandleChart(vm: vm)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .glassCard()
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
        }
        .task { await vm.attach(app.deriv) }
        .onDisappear { vm.stop() }
    }

    private var selectorBar: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                instrumentMenu
                Spacer()
                if let p = vm.lastPrice {
                    Text(fmt(p))
                        .font(.system(size: 16, weight: .bold, design: .monospaced))
                        .foregroundStyle(vm.up ? Glass.buy : Glass.sell)
                }
            }
            timeframeRow
        }
        .padding(.horizontal, 16)
    }

    private var instrumentMenu: some View {
        Menu {
            ForEach(DerivSymbols.groups, id: \.0) { group in
                Section(group.0) {
                    ForEach(group.1, id: \.self) { sym in
                        Button(DerivSymbols.display(sym)) { vm.setSymbol(sym) }
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(DerivSymbols.display(vm.symbol)).font(.system(size: 15, weight: .semibold))
                Image(systemName: "chevron.down").font(.system(size: 11, weight: .bold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14).padding(.vertical, 8)
            .glassCard(corner: 12)
        }
    }

    private var timeframeRow: some View {
        HStack(spacing: 6) {
            ForEach(Timeframe.allCases, id: \.self) { tf in
                Button {
                    vm.setTimeframe(tf)
                } label: {
                    Text(tf.rawValue)
                        .font(.system(size: 12, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .foregroundStyle(vm.timeframe == tf ? .white : .white.opacity(0.45))
                        .background(
                            RoundedRectangle(cornerRadius: 9)
                                .fill(vm.timeframe == tf ? Color.white.opacity(0.14) : .clear)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .glassCard(strong: true)
    }

    private func fmt(_ v: Double) -> String {
        v > 100 ? String(format: "%.2f", v) : String(format: "%.4f", v)
    }
}

/// Chart data + gesture state. Streams live ticks and pages history on demand.
@MainActor
final class ChartViewModel: ObservableObject {
    @Published var symbol = "R_100"
    @Published var timeframe: Timeframe = .m1
    @Published var candles: [Candle] = []
    @Published var lastPrice: Double?
    @Published var up = true
    @Published var scale: CGFloat = 1
    @Published var offset: CGFloat = 0

    // Gesture bases (not published — avoid redraw storms)
    var dragBase: CGFloat = 0
    var scaleBase: CGFloat = 1
    var needsBackfill = false

    private weak var deriv: DerivClient?
    private var ticker: Task<Void, Never>?
    private var loading = false
    private var backfilling = false

    func attach(_ deriv: DerivClient) async {
        self.deriv = deriv
        deriv.subscribeTicks(symbol)
        await reload()
        startTicker()
    }

    func setSymbol(_ s: String) {
        guard s != symbol else { return }
        symbol = s; offset = 0; scale = 1; dragBase = 0; scaleBase = 1
        deriv?.subscribeTicks(s)
        Task { await reload() }
    }

    func setTimeframe(_ tf: Timeframe) {
        guard tf != timeframe else { return }
        timeframe = tf; offset = 0; scale = 1; dragBase = 0; scaleBase = 1
        Task { await reload() }
    }

    func reload() async {
        guard let deriv = deriv, !loading else { return }
        loading = true; defer { loading = false }
        if let c = try? await deriv.candles(symbol: symbol, timeframe: timeframe, count: 500) {
            candles = c
            lastPrice = c.last?.close
        }
    }

    /// Page older candles when the user scrolls to the oldest loaded bar (unlimited history).
    func backfill() async {
        guard let deriv = deriv, !backfilling, let oldest = candles.first else { return }
        backfilling = true; defer { backfilling = false }
        let end = Int(oldest.timestamp.timeIntervalSince1970) - 1
        if let older = try? await deriv.candles(symbol: symbol, timeframe: timeframe, count: 500, endEpoch: end),
           !older.isEmpty {
            candles = older + candles
        }
    }

    private func startTicker() {
        ticker?.cancel()
        ticker = Task { [weak self] in
            var counter = 0
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard let self = self else { return }
                await self.tick()
                counter += 1
                if counter % 15 == 0 { await self.reload() }
            }
        }
    }

    private func tick() {
        guard let p = deriv?.prices[symbol], p > 0 else { return }
        let prev = lastPrice ?? p
        up = p >= prev
        lastPrice = p
        if let last = candles.last {
            let updated = Candle(timestamp: last.timestamp, open: last.open,
                                 high: max(last.high, p), low: min(last.low, p),
                                 close: p, volume: last.volume)
            candles[candles.count - 1] = updated
        }
    }

    func stop() { ticker?.cancel(); ticker = nil }
}

/// Canvas candlestick renderer with pan + pinch-zoom.
struct CandleChart: View {
    @ObservedObject var vm: ChartViewModel

    var body: some View {
        GeometryReader { _ in
            Canvas { ctx, size in render(&ctx, size) }
                .contentShape(Rectangle())
                .gesture(dragGesture)
                .gesture(zoomGesture)
        }
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { v in
                let spacing = max(2, 6 * vm.scale)
                let maxOff = max(0, CGFloat(vm.candles.count) * spacing)
                vm.offset = min(max(vm.dragBase + v.translation.width, -80), maxOff)
            }
            .onEnded { _ in
                vm.dragBase = vm.offset
                if vm.needsBackfill { Task { await vm.backfill() } }
            }
    }

    private var zoomGesture: some Gesture {
        MagnificationGesture()
            .onChanged { v in vm.scale = min(max(vm.scaleBase * v, 0.3), 6) }
            .onEnded { _ in vm.scaleBase = vm.scale }
    }

    private func render(_ ctx: inout GraphicsContext, _ size: CGSize) {
        let candles = vm.candles
        guard candles.count > 1 else { return }
        let spacing = max(2, 6 * vm.scale)
        let n = candles.count
        let rightPad: CGFloat = 58
        let bottomPad: CGFloat = 22
        let plotW = size.width - rightPad
        let plotH = size.height - bottomPad
        guard plotW > 0, plotH > 0 else { return }

        func x(_ i: Int) -> CGFloat { plotW - CGFloat(n - 1 - i) * spacing + vm.offset }

        var firstV = 0, lastV = n - 1
        var foundFirst = false
        for i in 0..<n {
            let xi = x(i)
            if xi >= -spacing && xi <= plotW + spacing {
                if !foundFirst { firstV = i; foundFirst = true }
                lastV = i
            }
        }
        guard foundFirst else { return }
        vm.needsBackfill = (firstV <= 1)

        var lo = Double.greatestFiniteMagnitude, hi = -Double.greatestFiniteMagnitude
        for i in firstV...lastV { lo = min(lo, candles[i].low); hi = max(hi, candles[i].high) }
        guard hi > lo else { return }
        let pad = (hi - lo) * 0.08; lo -= pad; hi += pad
        func y(_ p: Double) -> CGFloat { plotH - CGFloat((p - lo) / (hi - lo)) * plotH }

        // Grid + price labels
        let steps = 5
        for s in 0...steps {
            let price = lo + (hi - lo) * Double(s) / Double(steps)
            let yy = y(price)
            var line = Path(); line.move(to: CGPoint(x: 0, y: yy)); line.addLine(to: CGPoint(x: plotW, y: yy))
            ctx.stroke(line, with: .color(.white.opacity(0.06)), lineWidth: 1)
            ctx.draw(Text(priceLabel(price)).font(.system(size: 9, design: .monospaced)).foregroundColor(.white.opacity(0.5)),
                     at: CGPoint(x: plotW + 4, y: yy), anchor: .leading)
        }

        // Candles
        let upColor = Color(red: 0.20, green: 0.85, blue: 0.60)
        let downColor = Color(red: 0.98, green: 0.35, blue: 0.45)
        for i in firstV...lastV {
            let c = candles[i]
            let cx = x(i)
            let isUp = c.close >= c.open
            let col = isUp ? upColor : downColor
            var wick = Path(); wick.move(to: CGPoint(x: cx, y: y(c.high))); wick.addLine(to: CGPoint(x: cx, y: y(c.low)))
            ctx.stroke(wick, with: .color(col.opacity(0.85)), lineWidth: 1)
            let bodyW = max(1, spacing * 0.7)
            let yOpen = y(c.open), yClose = y(c.close)
            let top = min(yOpen, yClose), h = max(1, abs(yOpen - yClose))
            let rect = CGRect(x: cx - bodyW / 2, y: top, width: bodyW, height: h)
            ctx.fill(Path(roundedRect: rect, cornerRadius: 1), with: .color(col))
        }

        // Last price line
        if let last = candles.last {
            let yy = y(last.close)
            var line = Path(); line.move(to: CGPoint(x: 0, y: yy)); line.addLine(to: CGPoint(x: plotW, y: yy))
            ctx.stroke(line, with: .color(.white.opacity(0.3)), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
        }

        // Time labels
        let labelCount = 4
        if lastV > firstV {
            for k in 0...labelCount {
                let i = firstV + (lastV - firstV) * k / labelCount
                ctx.draw(Text(timeLabel(candles[i].timestamp)).font(.system(size: 9)).foregroundColor(.white.opacity(0.45)),
                         at: CGPoint(x: x(i), y: plotH + 11), anchor: .center)
            }
        }
    }

    private func priceLabel(_ p: Double) -> String {
        p > 100 ? String(format: "%.2f", p) : String(format: "%.4f", p)
    }

    private func timeLabel(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = vm.timeframe.granularity >= 86400 ? "MMM d" : "HH:mm"
        return f.string(from: d)
    }
}
