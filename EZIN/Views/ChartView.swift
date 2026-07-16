import SwiftUI

/// Chart tab — candlestick chart with advanced indicators: Volume Profile, Heatmap, Jump Markers.
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
            HStack(spacing: 8) {
                timeframeRow
                Spacer()
                indicatorToggles
                drawingTools
            }
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

    private var indicatorToggles: some View {
        HStack(spacing: 6) {
            Button { vm.showVolumeProfile.toggle() } label: {
                Image(systemName: "chart.bar.xaxis")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(vm.showVolumeProfile ? Glass.accent : .white.opacity(0.45))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 8).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.08)))
            
            Button { vm.showHeatmap.toggle() } label: {
                Image(systemName: "square.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(vm.showHeatmap ? Glass.accent : .white.opacity(0.45))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 8).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.08)))
            
            Button { vm.showMarkers.toggle() } label: {
                Image(systemName: "triangle.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(vm.showMarkers ? Glass.accent : .white.opacity(0.45))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 8).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.08)))
        }
    }

    private var drawingTools: some View {
        HStack(spacing: 4) {
            drawingButton("minus", kind: .horizontalLine, label: "S/R")
            drawingButton("lineweight", kind: .verticalLine, label: "Time")
            drawingButton("rectangle.dashed", kind: .rectangle, label: "Zone")
            drawingButton("chart.line.uptrend.xyaxis", kind: .trendLine, label: "Trend")
            Button { vm.clearDrawings() } label: { Image(systemName: "trash").font(.system(size: 11)) }
                .buttonStyle(.plain).foregroundStyle(.white.opacity(0.55)).padding(6)
        }
        .glassCard(corner: 10)
    }

    private func drawingButton(_ icon: String, kind: ChartDrawing.Kind, label: String) -> some View {
        Button { vm.addDrawing(kind: kind, label: label) } label: {
            Image(systemName: icon).font(.system(size: 11, weight: .semibold)).padding(6)
        }
        .buttonStyle(.plain).foregroundStyle(Glass.accent)
        .accessibilityLabel(label)
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
    
    // Indicator toggles
    @Published var showVolumeProfile = true
    @Published var showHeatmap = true
    @Published var showMarkers = true
    
    // Computed indicator data
    @Published var volumeProfileData: Microstructure.VolumeProfile?
    @Published var liquidityLevels: [Microstructure.LiquidityLevel]?
    @Published var jumpEvents: [Microstructure.JumpEvent]?
    @Published var drawings: [ChartDrawing] = ChartDrawingStore.shared.drawings

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
            
            // Compute indicators
            let marketData = MarketData(candles: c)
            volumeProfileData = Microstructure.volumeProfile(
                high: marketData.highs, low: marketData.lows, close: marketData.closes,
                volume: marketData.volumes, bins: 24
            )
            liquidityLevels = Microstructure.liquidityLevels(
                high: marketData.highs, low: marketData.lows, close: marketData.closes,
                lookback: 120, maxLevels: 6
            )
            jumpEvents = Microstructure.detectJumps(marketData.closes, mult: 3.0, lookback: 120)
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

    func addDrawing(kind: ChartDrawing.Kind, label: String) {
        guard !candles.isEmpty else { return }
        let index = candles.count - 1
        let price = lastPrice ?? candles[index].close
        let span = max(1, min(20, candles.count / 8))
        let range = max((candles.suffix(14).map { $0.high }.max() ?? price) - (candles.suffix(14).map { $0.low }.min() ?? price), abs(price) * 0.001)
        let drawing: ChartDrawing
        switch kind {
        case .horizontalLine: drawing = ChartDrawing(kind: kind, startIndex: 0, endIndex: index, startPrice: price, endPrice: price, label: label)
        case .verticalLine: drawing = ChartDrawing(kind: kind, startIndex: index, endIndex: index, startPrice: price - range, endPrice: price + range, label: label)
        case .rectangle: drawing = ChartDrawing(kind: kind, startIndex: max(0, index - span), endIndex: index, startPrice: price - range * 0.35, endPrice: price + range * 0.35, label: label)
        case .trendLine, .ray: drawing = ChartDrawing(kind: kind, startIndex: max(0, index - span), endIndex: index, startPrice: price - range * 0.25, endPrice: price, label: label)
        }
        ChartDrawingStore.shared.add(drawing)
        drawings = ChartDrawingStore.shared.drawings
    }

    func clearDrawings() { ChartDrawingStore.shared.removeAll(); drawings = [] }
    func stop() { ticker?.cancel(); ticker = nil }
}

/// Canvas candlestick renderer with pan + pinch-zoom and indicator overlays.
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

        // Draw heatmap (liquidity levels) first (background layer)
        if vm.showHeatmap, let levels = vm.liquidityLevels {
            drawHeatmap(ctx: &ctx, levels: levels, lo: lo, hi: hi, plotW: plotW, y: y)
        }

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

        drawAnnotations(ctx: &ctx, drawings: vm.drawings, x: x, y: y, plotW: plotW)

        // Volume profile (right side)
        if vm.showVolumeProfile, let profile = vm.volumeProfileData {
            drawVolumeProfile(ctx: &ctx, profile: profile, lo: lo, hi: hi, plotW: plotW, y: y)
        }

        // Jump markers
        if vm.showMarkers, let jumps = vm.jumpEvents {
            drawJumpMarkers(ctx: &ctx, jumps: jumps, candles: candles, firstV: firstV, lastV: lastV, x: x, y: y)
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

    private func drawAnnotations(ctx: inout GraphicsContext, drawings: [ChartDrawing], x: (Int) -> CGFloat, y: (Double) -> CGFloat, plotW: CGFloat) {
        for drawing in drawings {
            let color = Color.orange.opacity(0.85)
            switch drawing.kind {
            case .horizontalLine:
                var path = Path(); path.move(to: CGPoint(x: 0, y: y(drawing.startPrice))); path.addLine(to: CGPoint(x: plotW, y: y(drawing.startPrice)))
                ctx.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            case .verticalLine:
                var path = Path(); path.move(to: CGPoint(x: x(drawing.startIndex), y: 0)); path.addLine(to: CGPoint(x: x(drawing.startIndex), y: y(drawing.endPrice)))
                ctx.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            case .rectangle:
                let rect = CGRect(x: min(x(drawing.startIndex), x(drawing.endIndex)), y: min(y(drawing.startPrice), y(drawing.endPrice)), width: abs(x(drawing.endIndex) - x(drawing.startIndex)), height: abs(y(drawing.endPrice) - y(drawing.startPrice)))
                ctx.fill(Path(rect), with: .color(color.opacity(0.14))); ctx.stroke(Path(rect), with: .color(color), lineWidth: 1)
            case .trendLine, .ray:
                var path = Path(); path.move(to: CGPoint(x: x(drawing.startIndex), y: y(drawing.startPrice))); path.addLine(to: CGPoint(x: drawing.kind == .ray ? plotW : x(drawing.endIndex), y: drawing.kind == .ray ? y(drawing.endPrice) : y(drawing.endPrice)))
                ctx.stroke(path, with: .color(color), lineWidth: 1.5)
            }
        }
    }

    private func drawVolumeProfile(ctx: inout GraphicsContext, profile: Microstructure.VolumeProfile,
                                   lo: Double, hi: Double, plotW: CGFloat, y: (Double) -> CGFloat) {
        let profileW: CGFloat = 40
        let maxBinVol = profile.bins.map { $0.volume }.max() ?? 1
        
        for (price, vol) in profile.bins {
            guard price >= lo && price <= hi else { continue }
            let yy = y(price)
            let barW = (vol / maxBinVol) * profileW
            let rect = CGRect(x: plotW, y: yy - 2, width: barW, height: 4)
            ctx.fill(Path(roundedRect: rect, cornerRadius: 1), with: .color(.white.opacity(0.3)))
        }
        
        // Highlight POC
        let pocY = y(profile.poc)
        var pocLine = Path(); pocLine.move(to: CGPoint(x: plotW, y: pocY)); pocLine.addLine(to: CGPoint(x: plotW + profileW, y: pocY))
        ctx.stroke(pocLine, with: .color(Color(red: 1, green: 0.84, blue: 0)), lineWidth: 2)
    }

    private func drawHeatmap(ctx: inout GraphicsContext, levels: [Microstructure.LiquidityLevel],
                             lo: Double, hi: Double, plotW: CGFloat, y: (Double) -> CGFloat) {
        for level in levels {
            guard level.price >= lo && level.price <= hi else { continue }
            let yy = y(level.price)
            let opacity = min(0.4, level.strength / 10.0)
            var line = Path(); line.move(to: CGPoint(x: 0, y: yy)); line.addLine(to: CGPoint(x: plotW, y: yy))
            ctx.stroke(line, with: .color(level.isResistance ? Color.red.opacity(opacity) : Color.green.opacity(opacity)), lineWidth: 1)
        }
    }

    private func drawJumpMarkers(ctx: inout GraphicsContext, jumps: [Microstructure.JumpEvent],
                                 candles: [Candle], firstV: Int, lastV: Int,
                                 x: (Int) -> CGFloat, y: (Double) -> CGFloat) {
        for jump in jumps {
            guard jump.index >= firstV && jump.index <= lastV else { continue }
            let xx = x(jump.index)
            let yy = y(candles[jump.index].close)
            let markerSize: CGFloat = 6
            let markerColor = jump.up ? Color(red: 0.20, green: 0.85, blue: 0.60) : Color(red: 0.98, green: 0.35, blue: 0.45)
            
            var marker = Path()
            if jump.up {
                marker.move(to: CGPoint(x: xx, y: yy - markerSize))
                marker.addLine(to: CGPoint(x: xx - markerSize / 2, y: yy))
                marker.addLine(to: CGPoint(x: xx + markerSize / 2, y: yy))
            } else {
                marker.move(to: CGPoint(x: xx, y: yy + markerSize))
                marker.addLine(to: CGPoint(x: xx - markerSize / 2, y: yy))
                marker.addLine(to: CGPoint(x: xx + markerSize / 2, y: yy))
            }
            ctx.fill(marker, with: .color(markerColor))
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
