import SwiftUI
import AVFoundation

// MARK: - Module: TempoShift (rhythmic time-warp FX)

struct VinnyTempoShiftView: View {
    @ObservedObject var session: VinnySession
    @State private var gatePattern: [Bool] = Array(repeating: true, count: 16)
    @State private var swing = 0.0

    var body: some View {
        VinnySection(title: "Speed Warping", icon: "clock.arrow.2.circlepath") {
            HStack(spacing: 8) {
                VinnyAction(title: "½ Speed", icon: "tortoise") { warp(0.5, "half-speed") }
                VinnyAction(title: "¼ Speed", icon: "tortoise.fill", tint: .purple) { warp(0.25, "quarter-speed") }
                VinnyAction(title: "2× Speed", icon: "hare") { warp(2.0, "double-speed") }
            }
            HStack(spacing: 8) {
                VinnyAction(title: "Reverse", icon: "backward") { process({ VinnyDSP.reverse($0) }, "reversed") }
                VinnyAction(title: "Tape Stop", icon: "stop.circle", tint: .orange) { process({ VinnyDSP.tapeStop($0) }, "tape stop") }
                VinnyAction(title: "Stretch 2×", icon: "arrow.left.and.right", tint: .mint) { process({ VinnyDSP.timeStretch($0, factor: 2.0, sampleRate: VinnyDSP.defaultSampleRate) }, "time-stretched (pitch locked)") }
            }
        }

        VinnySection(title: "Multiband Time-Warp", icon: "square.split.3x1") {
            HStack(spacing: 8) {
                VinnyAction(title: "Slow Bass ½", icon: "arrow.down") { multiband(lowHalf: true) }
                VinnyAction(title: "Slow Highs ½", icon: "arrow.up", tint: .purple) { multiband(lowHalf: false) }
            }
            Text("Warps one band at its own speed while the other stays locked — the multiband trick.")
                .font(.system(size: 10)).foregroundStyle(.white.opacity(0.4))
        }

        VinnySection(title: "Rhythmic Gate Sequencer", icon: "square.grid.4x4.fill") {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 8), spacing: 6) {
                ForEach(0..<16, id: \.self) { i in
                    Button { gatePattern[i].toggle() } label: {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(gatePattern[i] ? Glass.accent.opacity(0.7) : Color.white.opacity(0.08))
                            .frame(height: 34)
                            .overlay(Text("\(i + 1)").font(.system(size: 9, weight: .bold)).foregroundStyle(.white.opacity(0.7)))
                    }
                    .buttonStyle(.plain)
                }
            }
            HStack(spacing: 8) {
                VinnyAction(title: "Apply Gate", icon: "scissors") { applyGate() }
                VinnyAction(title: "Stutter Fill", icon: "bolt", tint: .orange) {
                    gatePattern = [true,false,true,false, true,true,false,false, true,false,true,false, true,true,true,false]
                    applyGate()
                }
            }
        }

        VinnySection(title: "Groove & Swing", icon: "metronome") {
            VinnySlider(label: "Swing: \(Int(swing * 100))%", value: $swing)
            VinnyAction(title: "Re-Groove Last Loop", icon: "metronome.fill") {
                guard let loop = session.lastLoop else { session.status = "Render a loop first (Brain → Loop)."; return }
                session.busy = true
                let p = session.patch
                Task.detached(priority: .userInitiated) {
                    let regrooved = LoopFactory.regroove(loop, swing: swing, patch: p)
                    await MainActor.run {
                        session.lastLoop = regrooved
                        session.renderedWAV = regrooved.wav
                        session.player.load(data: regrooved.wav, name: "Re-grooved loop · swing \(Int(swing * 100))%")
                        session.player.play()
                        session.busy = false
                        session.status = "Re-grooved with \(Int(swing * 100))% swing."
                    }
                }
            }
        }
    }

    private func warp(_ factor: Double, _ label: String) {
        process({ VinnyDSP.speedWarp($0, factor: factor) }, label)
    }

    private func process(_ f: @escaping ([Float]) -> [Float], _ label: String) {
        guard let wav = session.renderedWAV, let pcm = VinnyDSP.readWAV(wav) else {
            session.status = "Render or play something first — TempoShift warps your last render."
            return
        }
        session.busy = true
        Task.detached(priority: .userInitiated) {
            let out = f(pcm.mono)
            let data = VinnyDSP.writeWAV(VinnyDSP.normalize(out, target: 0.9), sampleRate: pcm.sampleRate)
            await MainActor.run {
                session.renderedWAV = data
                session.player.load(data: data, name: "TempoShift — \(label)")
                session.player.play()
                session.busy = false
                session.status = "Applied \(label)."
            }
        }
    }

    private func multiband(lowHalf: Bool) {
        guard let wav = session.renderedWAV, let pcm = VinnyDSP.readWAV(wav) else {
            session.status = "Render something first."
            return
        }
        session.busy = true
        Task.detached(priority: .userInitiated) {
            let x = pcm.mono
            let low = VinnyDSP.Biquad.apply(.lowpass, to: x, cutoff: 250, q: 0.7, sampleRate: pcm.sampleRate)
            var high = [Float](repeating: 0, count: x.count)
            for i in 0..<x.count { high[i] = x[i] - low[i] }
            let warpedLow = VinnyDSP.speedWarp(low, factor: lowHalf ? 0.5 : 1.0)
            let warpedHigh = VinnyDSP.speedWarp(high, factor: lowHalf ? 1.0 : 0.5)
            var out = VinnyDSP.mix(warpedLow, warpedHigh, gainA: 1, gainB: 1)
            out = VinnyDSP.normalize(out, target: 0.88)
            let data = VinnyDSP.writeWAV(out, sampleRate: pcm.sampleRate)
            await MainActor.run {
                session.renderedWAV = data
                session.player.load(data: data, name: "Multiband warp — \(lowHalf ? "bass ½" : "highs ½")")
                session.player.play()
                session.busy = false
                session.status = "Multiband warp applied."
            }
        }
    }

    private func applyGate() {
        guard let wav = session.renderedWAV, let pcm = VinnyDSP.readWAV(wav) else {
            session.status = "Render something first."
            return
        }
        let out = VinnyDSP.gate(pcm.mono, pattern: gatePattern, bpm: session.patch.bpm, sampleRate: pcm.sampleRate)
        let data = VinnyDSP.writeWAV(out, sampleRate: pcm.sampleRate)
        session.renderedWAV = data
        session.player.load(data: data, name: "Gate sequencer")
        session.player.play()
        session.status = "Gate applied — \(gatePattern.filter { $0 }.count)/16 steps passing."
    }
}

// MARK: - Module: Earprint (audio identifier & fingerprint engine)

struct VinnyEarprintView: View {
    @ObservedObject var session: VinnySession
    @State private var showImporter = false
    @State private var analysis: [String] = []
    @State private var matches: [(name: String, distance: Double)] = []
    @State private var vector: [Double]?
    @State private var recording = false
    @State private var recorder: AVAudioRecorder?
    @State private var pendingAnalysisData: Data?

    var body: some View {
        VinnySection(title: "Identify Any Audio", icon: "ear.fill") {
            Text("Import a file or record with the mic — VINNY reads its BPM, key, brightness, groove and sonic DNA.")
                .font(.caption).foregroundStyle(.white.opacity(0.55))
            HStack(spacing: 10) {
                VinnyAction(title: "Import Audio", icon: "square.and.arrow.down") { showImporter = true }
                VinnyAction(title: recording ? "Stop & Analyze" : "Record 4s", icon: recording ? "stop.fill" : "mic.fill", tint: recording ? Glass.sell : .purple) {
                    recording ? stopRecording() : startRecording()
                }
            }
        }
        .sheet(isPresented: $showImporter) {
            DocumentPicker { urls in
                guard let url = urls.first, let data = try? Data(contentsOf: url) else { return }
                analyze(data: data, label: url.lastPathComponent)
            }
        }

        if !analysis.isEmpty {
            VinnySection(title: "Analysis", icon: "chart.bar.doc.horizontal") {
                ForEach(analysis, id: \.self) { line in
                    Text(line).font(.system(size: 12)).foregroundStyle(.white.opacity(0.8))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                HStack(spacing: 10) {
                    VinnyAction(title: "Save Fingerprint", icon: "bookmark") {
                        if let v = vector {
                            session.store.saveFingerprint(name: "Earprint \(Date().formatted(date: .omitted, time: .shortened))", vector: v)
                            session.status = "Fingerprint saved to the Sonic Library."
                        }
                    }
                    VinnyAction(title: "Build Similar Loop", icon: "wand.and.rays", tint: Glass.accent2) { buildSimilar() }
                }
            }
        }

        if !matches.isEmpty {
            VinnySection(title: "Preset Match — “sounds like…”", icon: "point.3.filled.connected.trianglepath.dotted") {
                ForEach(matches, id: \.name) { m in
                    HStack {
                        Image(systemName: "waveform").foregroundStyle(Glass.accent2)
                        Text(m.name).font(.system(size: 12)).foregroundStyle(.white.opacity(0.85))
                        Spacer()
                        Text("\(Int((1 - m.distance) * 100))% match").font(.system(size: 10)).foregroundStyle(.white.opacity(0.5))
                    }
                }
            }
        }
    }

    private func analyze(data: Data, label: String) {
        guard let pcm = VinnyDSP.readWAV(data) else {
            session.status = "Earprint reads 16-bit PCM WAV files (convert m4a/mp3 first)."
            return
        }
        pendingAnalysisData = data
        session.busy = true
        Task.detached(priority: .userInitiated) {
            let x = pcm.mono
            let bpm = VinnyDSP.estimateBPM(x, sampleRate: pcm.sampleRate)
            let key = VinnyDSP.detectKey(x, sampleRate: pcm.sampleRate)
            let centroid = VinnyDSP.spectralCentroid(x, sampleRate: pcm.sampleRate)
            let loud = VinnyDSP.loudnessDB(x)
            let bands = VinnyDSP.bandEnergies(x, sampleRate: pcm.sampleRate)
            let v = VinnyDSP.fingerprint(x, sampleRate: pcm.sampleRate)
            let secs = Double(x.count) / Double(pcm.sampleRate)
            await MainActor.run {
                self.analysis = [
                    "Source: \(label) · \(String(format: "%.1f", secs))s",
                    "Tempo: \(String(format: "%.1f", bpm)) BPM",
                    "Key: \(key.key) \(key.scale) (\(Int(key.confidence * 100))% confidence)",
                    "Brightness (spectral centroid): \(Int(centroid)) Hz",
                    "Loudness: \(String(format: "%.1f", loud)) dB RMS",
                    "Band split — low \(Int(bands.0 * 100))% · mid \(Int(bands.1 * 100))% · high \(Int(bands.2 * 100))%"
                ]
                self.vector = v
                self.matches = session.store.closest(to: v)
                session.busy = false
                session.status = "Earprint analysis complete."
            }
        }
    }

    private func buildSimilar() {
        guard let wav = pendingAnalysisData else { session.status = "Analyze audio first."; return }
        session.busy = true
        session.status = "Reverse-engineering the reference into a patch…"
        Task.detached(priority: .userInitiated) {
            let p = GenesisEngine.patch(fromAudio: wav)
            await MainActor.run {
                if let p {
                    session.setPatch(p)
                    session.store.savePreset(p)
                    session.renderLoop()
                    session.status = "Rebuilt the reference as an editable patch and generated a similar loop."
                } else {
                    session.busy = false
                    session.status = "Couldn't reverse-engineer that file — needs to be a 16-bit PCM WAV."
                }
            }
        }
    }

    private func startRecording() {
        let sessionAV = AVAudioSession.sharedInstance()
        if sessionAV.recordPermission == .denied {
            session.status = "Microphone access is off — enable it in iOS Settings → EZIN."
            return
        }
        sessionAV.requestRecordPermission { granted in
            guard granted else { return }
            Task { @MainActor in self.recordFourSeconds() }
        }
    }

    private func recordFourSeconds() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playAndRecord, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
            let url = FileStore.shared.fm.temporaryDirectory.appendingPathComponent("earprint-rec.wav")
            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatLinearPCM),
                AVSampleRateKey: 44100,
                AVNumberOfChannelsKey: 1,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsFloatKey: false
            ]
            let rec = try AVAudioRecorder(url: url, settings: settings)
            recorder = rec
            rec.record(forDuration: 4.0)
            recording = true
            session.status = "Recording 4 seconds…"
            DispatchQueue.main.asyncAfter(deadline: .now() + 4.2) {
                self.stopRecording()
            }
        } catch {
            session.status = "Recorder failed: \(error.localizedDescription)"
        }
    }

    private func stopRecording() {
        guard recording, let rec = recorder else { return }
        rec.stop()
        recording = false
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        if let data = try? Data(contentsOf: rec.url) {
            pendingAnalysisData = data
            analyze(data: data, label: "mic recording")
        }
        recorder = nil
    }
}

// MARK: - Module: FlowState (modulation & movement studio)

struct VinnyFlowStateView: View {
    @ObservedObject var session: VinnySession
    @State private var shape: VinnyDSP.LFOShape = .sine
    @State private var rate = 1.0
    @State private var depth = 0.5
    @State private var target = 0   // 0 cutoff · 1 pitch · 2 amp
    @State private var drawn: [CGFloat] = Array(repeating: 0.5, count: 32)

    var body: some View {
        VinnySection(title: "Modulators — LFO · Physics · Chaos", icon: "scribble.variable") {
            Picker("Shape", selection: $shape) {
                ForEach(VinnyDSP.LFOShape.allCases) { s in Text(s.rawValue).tag(s) }
            }
            .pickerStyle(.menu).tint(Glass.accent2)
            VinnySlider(label: "Rate: \(String(format: "%.2f", rate)) Hz", value: $rate, range: 0.05...12)
            VinnySlider(label: "Depth", value: $depth)
            Picker("Target", selection: $target) {
                Text("→ Filter cutoff").tag(0); Text("→ Pitch").tag(1); Text("→ Amplitude").tag(2)
            }
            .pickerStyle(.segmented)
            VinnyAction(title: "Preview Modulation", icon: "play.fill") { previewMod() }
        }

        VinnySection(title: "Visual Sound Sculptor — draw your own curve", icon: "pencil.and.scribble") {
            Canvas { context, size in
                let step = size.width / CGFloat(drawn.count - 1)
                var path = Path()
                for (i, v) in drawn.enumerated() {
                    let x = CGFloat(i) * step
                    let y = size.height * (1 - v)
                    if i == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
                }
                context.stroke(path, with: .color(Glass.accent2), lineWidth: 2)
            }
            .frame(height: 90)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.05)))
            .gesture(DragGesture(minimumDistance: 0).onChanged { g in
                let w = max(g.location.x, 0)
                let idx = min(Int(w / 12), drawn.count - 1)
                if idx >= 0 { drawn[idx] = min(max(1 - g.location.y / 90, 0), 1) }
            })
            VinnyAction(title: "Apply Drawn Curve to Cutoff", icon: "checkmark") {
                previewCustomCurve()
            }
        }

        VinnySection(title: "Randomizer Dice", icon: "dice") {
            HStack(spacing: 8) {
                VinnyAction(title: "Dice: Engine", icon: "dice.fill") { dice(engine: true) }
                VinnyAction(title: "Dice: FX", icon: "dice", tint: .orange) { dice(engine: false) }
            }
        }
    }

    private func previewMod() {
        let p = session.patch
        session.busy = true
        let t = target, r = rate, d = depth, sh = shape
        Task.detached(priority: .userInitiated) {
            let beat = 60.0 / p.bpm
            var notes: [VinnyDSP.VinnyNote] = []
            for i in 0..<8 {
                let midi = TheoryEngine.degreeToMidi([0, 2, 4, 7][i % 4], octave: 4, key: p.key, scale: p.scale)
                notes.append(VinnyDSP.VinnyNote(midi: midi, start: Double(i) * beat * 0.5, duration: beat * 0.48, velocity: 0.8, lane: 0))
            }
            var pcm = VinnyRenderer.render(patch: p, notes: notes, durationSec: beat * 4.4)
            let sr = VinnyDSP.defaultSampleRate
            // Apply the modulator across time on the chosen target (rendered result).
            switch t {
            case 0:
                // True per-sample moving filter: one-pole lowpass with a time-varying
                // coefficient — click-free, the modulator sweeps it continuously.
                var out = [Float](repeating: 0, count: pcm.count)
                var y = 0.0
                for i in 0..<pcm.count {
                    let phase = Double(i) / Double(sr)
                    let m = VinnyDSP.modulator(sh, phase: phase, rateHz: r, seed: 7, step: i / 441)
                    let cutoff = 150 + m * d * 7000
                    let a = 1 - exp(-2 * .pi * cutoff / Double(sr))
                    y += a * (Double(pcm[i]) - y)
                    out[i] = Float(y)
                }
                pcm = out
            case 1:
                var out = [Float](repeating: 0, count: pcm.count)
                for i in 0..<pcm.count {
                    let phase = Double(i) / Double(sr)
                    let m = VinnyDSP.modulator(sh, phase: phase, rateHz: r, seed: 7, step: i / 441)
                    let shift = 1 + (m - 0.5) * d * 0.06
                    let readPos = min(Double(i) * shift, Double(pcm.count - 1))
                    out[i] = pcm[Int(readPos)]
                }
                pcm = out
            default:
                for i in 0..<pcm.count {
                    let phase = Double(i) / Double(sr)
                    let m = VinnyDSP.modulator(sh, phase: phase, rateHz: r, seed: 7, step: i / 441)
                    pcm[i] *= Float(1 - d + m * d)
                }
            }
            let wav = VinnyDSP.writeWAV(VinnyDSP.normalize(pcm, target: 0.88))
            await MainActor.run {
                session.renderedWAV = wav
                session.player.load(data: wav, name: "FlowState — \(sh.rawValue) @ \(String(format: "%.1f", r)) Hz")
                session.player.play()
                session.busy = false
                session.status = "Modulation preview rendered."
            }
        }
    }

    private func previewCustomCurve() {
        var p = session.patch
        session.busy = true
        let curve = drawn.map { Double($0) }
        Task.detached(priority: .userInitiated) {
            let beat = 60.0 / p.bpm
            var notes: [VinnyDSP.VinnyNote] = []
            for i in 0..<8 {
                let midi = TheoryEngine.degreeToMidi([0, 2, 4, 7][i % 4], octave: 4, key: p.key, scale: p.scale)
                notes.append(VinnyDSP.VinnyNote(midi: midi, start: Double(i) * beat * 0.5, duration: beat * 0.48, velocity: 0.8, lane: 0))
            }
            var pcm = VinnyRenderer.render(patch: p, notes: notes, durationSec: beat * 4.4)
            for i in 0..<pcm.count {
                let pos = Double(i) / Double(pcm.count) * Double(curve.count - 1)
                let m = curve[min(Int(pos), curve.count - 1)]
                pcm[i] *= Float(0.25 + m * 0.75)
            }
            let wav = VinnyDSP.writeWAV(VinnyDSP.normalize(pcm, target: 0.88))
            await MainActor.run {
                session.renderedWAV = wav
                session.player.load(data: wav, name: "FlowState — drawn curve")
                session.player.play()
                session.busy = false
                session.status = "Your hand-drawn curve is driving the sound."
            }
        }
    }

    private func dice(engine: Bool) {
        var rng = SeededRNG(UInt64(Date().timeIntervalSince1970))
        var p = session.patch
        if engine {
            p.filterCutoff = 300 + rng.next01() * 9000
            p.fmAmount = rng.next01() * 0.7
            p.rmAmount = rng.next01() * 0.4
            p.unisonVoices = rng.nextInt(1...10)
            p.osc[0].harmonics = (0..<6).map { _ in Float(rng.next01()) }
        } else {
            p.fx = (0..<rng.nextInt(1...3)).map { _ in
                FXSlot(kind: FXKind.allCases[rng.nextInt(0..<FXKind.allCases.count)], mix: 0.2 + rng.next01() * 0.4, p1: rng.next01(), p2: rng.next01(), p3: rng.next01())
            }
        }
        session.setPatch(p)
        session.renderPreview()
    }
}

// MARK: - Module: Spaceship (FX & spatial rack)

struct VinnySpaceshipView: View {
    @ObservedObject var session: VinnySession
    @State private var addKind: FXKind = .reverb

    var body: some View {
        VinnySection(title: "Modular FX Rack (\(session.patch.fx.count)/24)", icon: "sparkles") {
            HStack {
                Picker("FX", selection: $addKind) {
                    ForEach(FXKind.allCases) { k in Label(k.label, systemImage: k.icon).tag(k) }
                }
                .pickerStyle(.menu).tint(Glass.accent2)
                Spacer()
                VinnyAction(title: "Add", icon: "plus") {
                    guard session.patch.fx.count < 24 else { session.status = "Rack is full (24 slots)."; return }
                    session.patch.fx.append(FXSlot(kind: addKind, mix: 0.35))
                }
                .frame(width: 90)
            }
        }

        ForEach(Array(session.patch.fx.enumerated()), id: \.element.id) { index, slot in
            VinnySection(title: "\(index + 1). \(slot.kind.label)", icon: slot.kind.icon) {
                HStack {
                    Toggle("", isOn: $session.patch.fx[index].enabled).labelsHidden().tint(Glass.accent2)
                    Spacer()
                    Button { if index > 0 { session.patch.fx.swapAt(index, index - 1) } } label: {
                        Image(systemName: "arrow.up").foregroundStyle(.white.opacity(0.6))
                    }.buttonStyle(.plain)
                    Button { if index < session.patch.fx.count - 1 { session.patch.fx.swapAt(index, index + 1) } } label: {
                        Image(systemName: "arrow.down").foregroundStyle(.white.opacity(0.6))
                    }.buttonStyle(.plain)
                    Button { session.patch.fx.remove(at: index) } label: {
                        Image(systemName: "trash").foregroundStyle(Glass.sell.opacity(0.8))
                    }.buttonStyle(.plain)
                }
                let labels = slot.kind.paramLabels
                VinnySlider(label: labels.0, value: $session.patch.fx[index].p1)
                if labels.1 != "—" { VinnySlider(label: labels.1, value: $session.patch.fx[index].p2) }
                if labels.2 != "—" { VinnySlider(label: labels.2, value: $session.patch.fx[index].p3) }
                if slot.kind != .eq { VinnySlider(label: "Mix", value: $session.patch.fx[index].mix) }
            }
        }

        VinnySection(title: "Render Through the Rack", icon: "play.circle") {
            VinnyAction(title: "Render with FX", icon: "play.fill") { session.renderPreview() }
        }
    }
}

// MARK: - Module: Hybridizer (cross-module fusion lab)

struct VinnyHybridizerView: View {
    @ObservedObject var session: VinnySession
    @State private var fusionAmount = 0.5
    @State private var genreTarget = "Techno"
    @State private var genreAmount = 0.5
    @State private var partnerName: String?

    var body: some View {
        VinnySection(title: "Spectral Sound Fusion", icon: "atom") {
            Text("Blend your current render with another preset's render — true STFT spectral fusion, not layering.")
                .font(.caption).foregroundStyle(.white.opacity(0.55))
            Picker("Partner preset", selection: $partnerName) {
                Text("Choose…").tag(String?.none)
                ForEach(session.store.presets) { p in Text(p.name).tag(String?.some(p.name)) }
            }
            .pickerStyle(.menu).tint(Glass.accent2)
            VinnySlider(label: "Fusion: \(Int(fusionAmount * 100))% partner", value: $fusionAmount)
            VinnyAction(title: "Fuse Sounds", icon: "bolt.circle") { fuse() }
        }

        VinnySection(title: "Rhythm & Timbre Transfer", icon: "arrow.left.arrow.right") {
            HStack(spacing: 8) {
                VinnyAction(title: "Rhythm Transfer", icon: "metronome") { transfer(rhythm: true) }
                VinnyAction(title: "Timbre Transfer", icon: "waveform.path", tint: .purple) { transfer(rhythm: false) }
            }
            Text("Rhythm: your partner's groove re-shapes your render. Timbre: your render takes on the partner's tone.")
                .font(.system(size: 10)).foregroundStyle(.white.opacity(0.4))
        }

        VinnySection(title: "Genre Migrator", icon: "map") {
            Picker("Target genre", selection: $genreTarget) {
                ForEach(["Lo-Fi", "Techno", "Trap", "Orchestral"], id: \.self) { Text($0).tag($0) }
            }
            .pickerStyle(.segmented)
            VinnySlider(label: "Migration: \(Int(genreAmount * 100))%", value: $genreAmount)
            VinnyAction(title: "Migrate Genre", icon: "airplane.departure", tint: .mint) {
                let p = GenesisEngine.morph(session.patch, towardGenre: genreTarget, amount: genreAmount)
                session.setPatch(p)
                session.store.savePreset(p)
                session.renderPreview()
                session.status = "Migrated \(Int(genreAmount * 100))% toward \(genreTarget)."
            }
        }

        VinnySection(title: "Sound Breeding", icon: "pawprint") {
            Picker("Breed with", selection: $partnerName) {
                Text("Choose…").tag(String?.none)
                ForEach(session.store.presets) { p in Text(p.name).tag(String?.some(p.name)) }
            }
            .pickerStyle(.menu).tint(Glass.accent2)
            VinnyAction(title: "Breed Presets", icon: "heart.circle", tint: .pink) { breed() }
        }

        VinnySection(title: "Sound DNA Injection", icon: "doc.on.clipboard") {
            VinnyAction(title: "Inject Captured DNA Into New Patch", icon: "syringe") { injectDNA() }
            Text("Takes the current patch's Sound DNA (capture it in Brain → Export) and grows a fresh patch around that character.")
                .font(.system(size: 10)).foregroundStyle(.white.opacity(0.4))
        }
    }

    private func partnerPatch() -> VinnyPatch? {
        session.store.presets.first { $0.name == partnerName }
    }

    private func renderPartner(_ p: VinnyPatch) -> [Float]? {
        let beat = 60.0 / p.bpm
        var notes: [VinnyDSP.VinnyNote] = []
        for (i, deg) in [0, 2, 4, 7].enumerated() {
            notes.append(VinnyDSP.VinnyNote(midi: TheoryEngine.degreeToMidi(deg, octave: 4, key: p.key, scale: p.scale), start: Double(i) * beat * 0.5, duration: beat * 0.48, velocity: 0.8, lane: 0))
        }
        return VinnyRenderer.render(patch: p, notes: notes, durationSec: beat * 2.4)
    }

    private func fuse() {
        guard let partner = partnerPatch() else { session.status = "Choose a partner preset first."; return }
        guard let wav = session.renderedWAV, let pcmA = VinnyDSP.readWAV(wav) else { session.status = "Render your patch first (Brain → Preview)."; return }
        guard let pcmB = renderPartner(partner) else { return }
        session.busy = true
        let amount = fusionAmount
        Task.detached(priority: .userInitiated) {
            let fused = VinnyDSP.spectralFuse(pcmA.mono, pcmB, amount: amount, sampleRate: pcmA.sampleRate)
            let out = VinnyDSP.writeWAV(fused, sampleRate: pcmA.sampleRate)
            await MainActor.run {
                session.renderedWAV = out
                session.player.load(data: out, name: "Fusion: \(session.patch.name) × \(partner.name)")
                session.player.play()
                session.busy = false
                session.status = "Spectral fusion complete — \(Int(amount * 100))% \(partner.name)."
            }
        }
    }

    private func transfer(rhythm: Bool) {
        guard let partner = partnerPatch() else { session.status = "Choose a partner preset first."; return }
        guard let wav = session.renderedWAV, let pcmA = VinnyDSP.readWAV(wav) else { session.status = "Render your patch first."; return }
        guard let pcmB = renderPartner(partner) else { return }
        session.busy = true
        Task.detached(priority: .userInitiated) {
            let out = rhythm
                ? VinnyDSP.rhythmTransfer(src: pcmB, dst: pcmA.mono, sampleRate: pcmA.sampleRate)
                : VinnyDSP.timbreTransfer(src: pcmB, dst: pcmA.mono, sampleRate: pcmA.sampleRate)
            let data = VinnyDSP.writeWAV(VinnyDSP.normalize(out, target: 0.88), sampleRate: pcmA.sampleRate)
            await MainActor.run {
                session.renderedWAV = data
                session.player.load(data: data, name: rhythm ? "Rhythm transfer" : "Timbre transfer")
                session.player.play()
                session.busy = false
                session.status = rhythm ? "Partner's groove transferred onto your render." : "Partner's timbre transferred onto your render."
            }
        }
    }

    private func breed() {
        guard let partner = partnerPatch() else { session.status = "Choose a preset to breed with."; return }
        let child = GenesisEngine.breed(session.patch, partner, seed: UInt64(Date().timeIntervalSince1970))
        session.setPatch(child)
        session.store.savePreset(child)
        session.renderPreview()
        session.status = "Born: \"\(child.name)\" — traits inherited from both parents."
    }

    private func injectDNA() {
        let dna = session.patch.dna
        guard !dna.isEmpty else { session.status = "No DNA on this patch yet — Brain → Export → Capture Sound DNA first."; return }
        var p = GenesisEngine.patch(fromText: "hybrid organic digital texture", seed: UInt64(dna.count * 31 + 7))
        // DNA steers the newborn: brightness → cutoff, low energy → sub, BPM → tempo.
        if dna.count >= 6 {
            p.filterCutoff = min(max(dna[0] * 9000 + 500, 300), 16000)
            p.subLevel = min(dna[3] * 1.2, 1)
            p.bpm = min(max(dna[6] * 180, 60), 200)
        }
        p.dna = dna
        p.name = "\(session.patch.name) DNA+"
        session.setPatch(p)
        session.store.savePreset(p)
        session.renderPreview()
        session.status = "Sound DNA injected into a new patch."
    }
}

// MARK: - Module: Stage (live performance mode)

struct VinnyStageView: View {
    @ObservedObject var session: VinnySession
    @State private var arpOn = false
    @State private var arpRate = 2.0
    @State private var morphA = 0
    @State private var morphB = 1
    @State private var morphT = 0.0

    private var pads: [Int] {
        (0..<16).map { TheoryEngine.degreeToMidi($0, octave: 4 + $0 / 8, key: session.patch.key, scale: session.patch.scale) }
    }

    var body: some View {
        VinnySection(title: "Performance Pads — Scale-Locked to \(session.patch.key) \(session.patch.scale)", icon: "music.mic") {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
                ForEach(0..<16, id: \.self) { i in
                    Button { playPad(i) } label: {
                        VStack(spacing: 2) {
                            Text(noteName(pads[i])).font(.system(size: 13, weight: .bold))
                            Text("pad \(i + 1)").font(.system(size: 8)).foregroundStyle(.white.opacity(0.45))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Glass.accent.opacity(i % 8 == 0 ? 0.55 : 0.28)))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.14), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            Text("Universal Scale Guardian: pads physically cannot play out of key.")
                .font(.system(size: 10)).foregroundStyle(.white.opacity(0.4))
        }

        VinnySection(title: "Arpeggiator", icon: "arrow.up.right") {
            HStack {
                Toggle("Arp", isOn: $arpOn).tint(Glass.accent2).foregroundStyle(.white.opacity(0.8))
                Spacer()
                Text("\(Int(arpRate))× /beat").font(.system(size: 11)).foregroundStyle(.white.opacity(0.6))
            }
            VinnySlider(label: "Rate", value: $arpRate, range: 1...4, format: "%.0f")
            VinnyAction(title: "Play Arp Pattern", icon: "play.fill") { playArp() }
        }

        VinnySection(title: "Scene Snapshots (16)", icon: "camera") {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 8), spacing: 6) {
                ForEach(0..<16, id: \.self) { i in
                    Button {
                        if let scene = session.store.scenes[i] {
                            session.setPatch(scene)
                            session.status = "Scene \(i + 1) loaded: \(scene.name)."
                        } else {
                            session.store.saveScene(session.patch, at: i)
                            session.status = "Scene \(i + 1) saved."
                        }
                    } label: {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(session.store.scenes[i] != nil ? Glass.accent2.opacity(0.5) : Color.white.opacity(0.07))
                            .frame(height: 34)
                            .overlay(Text("\(i + 1)").font(.system(size: 10, weight: .bold)).foregroundStyle(.white))
                    }
                    .buttonStyle(.plain)
                    .onLongPressGesture {
                        session.store.saveScene(nil, at: i)
                        session.status = "Scene \(i + 1) cleared."
                    }
                }
            }
            Text("Tap: load filled / save empty. Long-press: clear.")
                .font(.system(size: 10)).foregroundStyle(.white.opacity(0.4))
        }

        VinnySection(title: "Scene Morph Fader", icon: "slider.horizontal.2.square") {
            HStack {
                Picker("A", selection: $morphA) { ForEach(0..<16, id: \.self) { Text("S\($0 + 1)").tag($0) } }.pickerStyle(.menu).tint(Glass.accent2)
                Picker("B", selection: $morphB) { ForEach(0..<16, id: \.self) { Text("S\($0 + 1)").tag($0) } }.pickerStyle(.menu).tint(Glass.accent2)
            }
            VinnySlider(label: "Morph A ↔ B", value: $morphT)
            VinnyAction(title: "Morph Scenes", icon: "arrow.left.and.right") { morphScenes() }
        }
    }

    private func noteName(_ midi: Int) -> String {
        "\(TheoryEngine.noteNames[midi % 12])\(midi / 12 - 1)"
    }

    private func playPad(_ i: Int) {
        let midi = TheoryEngine.quantize(pads[i], key: session.patch.key, scale: session.patch.scale)
        let p = session.patch
        Task.detached(priority: .userInitiated) {
            let note = VinnyDSP.VinnyNote(midi: midi, start: 0, duration: 0.7, velocity: 0.85, lane: 0)
            let wav = VinnyRenderer.renderWAV(patch: p, notes: [note], durationSec: 0.9)
            await MainActor.run {
                session.player.load(data: wav, name: "Pad \(noteName(midi))")
                session.player.play()
            }
        }
    }

    private func playArp() {
        guard arpOn else { session.status = "Flip the Arp toggle on first."; return }
        let p = session.patch
        let rate = arpRate
        Task.detached(priority: .userInitiated) {
            let beat = 60.0 / p.bpm
            var notes: [VinnyDSP.VinnyNote] = []
            let pattern = [0, 2, 4, 7, 9, 7, 4, 2]
            for rep in 0..<2 {
                for (i, deg) in pattern.enumerated() {
                    let midi = TheoryEngine.degreeToMidi(deg, octave: 5, key: p.key, scale: p.scale)
                    notes.append(VinnyDSP.VinnyNote(midi: midi, start: Double(rep * pattern.count + i) * beat / rate, duration: beat / rate * 0.9, velocity: 0.75, lane: 0))
                }
            }
            let wav = VinnyRenderer.renderWAV(patch: p, notes: notes, durationSec: beat / rate * Double(pattern.count * 2) + 0.3)
            await MainActor.run {
                session.player.load(data: wav, name: "Arp \(Int(rate))× — \(p.key) \(p.scale)")
                session.player.play()
                session.status = "Arpeggiator playing."
            }
        }
    }

    private func morphScenes() {
        guard let a = session.store.scenes[morphA], let b = session.store.scenes[morphB] else {
            session.status = "Save scenes into both slots first."
            return
        }
        let child = GenesisEngine.breed(a, b, seed: UInt64(morphT * 1000 + 3))
        // Morph amount steers which parent dominates the numeric traits.
        var p = child
        p.filterCutoff = a.filterCutoff * (1 - morphT) + b.filterCutoff * morphT
        p.bpm = a.bpm * (1 - morphT) + b.bpm * morphT
        p.stereoWidth = a.stereoWidth * (1 - morphT) + b.stereoWidth * morphT
        p.name = "Morph \(Int(morphT * 100))%"
        session.setPatch(p)
        session.renderPreview()
    }
}

// MARK: - Module: Vault (preset cloud & community — local + offline)

struct VinnyVaultView: View {
    @ObservedObject var session: VinnySession
    @State private var query = ""
    @State private var showImporter = false

    var body: some View {
        VinnySection(title: "Smart Preset Browser", icon: "archivebox") {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.white.opacity(0.4))
                TextField("Search by mood, genre, tag, key…", text: $query)
                    .foregroundStyle(.white)
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.06)))
            HStack(spacing: 8) {
                VinnyAction(title: "Save Current", icon: "square.and.arrow.down") {
                    session.store.savePreset(session.patch)
                    session.status = "Saved \"\(session.patch.name)\" to the Vault (v\(session.patch.version))."
                }
                VinnyAction(title: "Import Patch", icon: "square.and.arrow.up", tint: .purple) { showImporter = true }
            }
        }

        VinnySection(title: "Presets (\(session.store.search(query).count))", icon: "list.bullet") {
            ForEach(session.store.search(query)) { p in
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(p.name).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                        Text("\(p.genre) · \(p.key) \(p.scale) · \(Int(p.bpm)) BPM · v\(p.version)")
                            .font(.system(size: 10)).foregroundStyle(.white.opacity(0.5))
                        if !p.tags.isEmpty {
                            Text(p.tags.prefix(5).map { "#\($0)" }.joined(separator: " "))
                                .font(.system(size: 9)).foregroundStyle(Glass.accent2.opacity(0.8)).lineLimit(1)
                        }
                    }
                    Spacer()
                    Button { session.setPatch(p); session.renderPreview() } label: {
                        Image(systemName: "play.fill").foregroundStyle(Glass.accent2)
                    }.buttonStyle(.plain)
                    Button { session.store.deletePreset(p) } label: {
                        Image(systemName: "trash").foregroundStyle(Glass.sell.opacity(0.7))
                    }.buttonStyle(.plain)
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.05)))
            }
        }

        VinnySection(title: "Time Machine — every state, recoverable", icon: "clock.arrow.circlepath") {
            let items = Array(session.store.timeMachine.prefix(10))
            if items.isEmpty {
                Text("Snapshots appear here whenever you save a preset or take a snapshot in Brain.")
                    .font(.caption).foregroundStyle(.white.opacity(0.5))
            }
            ForEach(items) { p in
                Button {
                    session.setPatch(p)
                    session.status = "Time-traveled to \"\(p.name)\" v\(p.version)."
                } label: {
                    HStack {
                        Image(systemName: "clock").foregroundStyle(.white.opacity(0.4))
                        Text("\(p.name) · v\(p.version)").font(.system(size: 11)).foregroundStyle(.white.opacity(0.75))
                        Spacer()
                        Text(p.createdAt.formatted(date: .omitted, time: .shortened)).font(.system(size: 9)).foregroundStyle(.white.opacity(0.4))
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .sheet(isPresented: $showImporter) {
            DocumentPicker { urls in
                guard let url = urls.first, let data = try? Data(contentsOf: url) else { return }
                if let p = try? JSONDecoder().decode(VinnyPatch.self, from: data) {
                    let clean = p.normalized()
                    session.setPatch(clean)
                    session.store.savePreset(clean)
                    session.status = "Imported shared patch \"\(clean.name)\" — collaboration complete."
                } else {
                    session.status = "Not a VINNY patch file (.vinnypatch.json)."
                }
            }
        }
    }
}

// MARK: - Module: Vinny AI (coach, commands, color, learning path, notation)

struct VinnyAIView: View {
    @ObservedObject var session: VinnySession
    @State private var command = ""
    @State private var chat: [(String, Bool)] = [("Hey — I'm Vinny, your sound-design coach. Tell me things like \"make it darker, add grit, slow it down\". I can also teach synthesis, paint sound from color, and read your patch for tips.", false)]

    private let lessons: [(String, String)] = [
        ("1 · Subtractive basics", "Oscillators make raw tone; the filter carves it. Try saw + low-pass at 1.2 kHz — that's the classic analog voice."),
        ("2 · Envelopes shape time", "Attack = how fast sound speaks, release = how it dies. Plucks: fast attack, short release. Pads: slow everything."),
        ("3 · FM for metal & bells", "FM lets one oscillator wobble another's pitch. Small amounts = growl; large = metallic bells."),
        ("4 · Unison = size", "Stacking detuned copies of a voice fattens it. 5 voices at 40% spread is the supersaw recipe."),
        ("5 · Space with reverb", "Room size sets the hall, damping sets the wall material. Mix under 40% keeps clarity."),
        ("6 · Sound DNA thinking", "Every sound is brightness + body + motion. Capture DNA, inject it elsewhere — that's how pros reuse character.")
    ]

    var body: some View {
        VinnySection(title: "Voice-Command Sound Design", icon: "bubble.left.and.text.bubble.right") {
            ForEach(Array(chat.enumerated()), id: \.offset) { _, msg in
                Text(msg.0)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(msg.1 ? 0.95 : 0.7))
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: msg.1 ? .trailing : .leading)
                    .background(RoundedRectangle(cornerRadius: 12).fill(msg.1 ? Glass.accent.opacity(0.35) : Color.white.opacity(0.06)))
            }
            HStack {
                TextField("make it darker, add grit…", text: $command)
                    .foregroundStyle(.white)
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.06)))
                    .onSubmit(runCommand)
                Button(action: runCommand) {
                    Image(systemName: "arrow.up.circle.fill").font(.system(size: 26)).foregroundStyle(Glass.accent)
                }.buttonStyle(.plain)
            }
        }

        VinnySection(title: "Coach Suggestions", icon: "lightbulb") {
            ForEach(VinnyAssistant.suggest(for: session.patch), id: \.self) { tip in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "sparkle").font(.system(size: 10)).foregroundStyle(Glass.accent2)
                    Text(tip).font(.system(size: 11)).foregroundStyle(.white.opacity(0.7))
                }
            }
        }

        VinnySection(title: "Color-to-Sound Synesthesia", icon: "paintpalette") {
            Text("Paint with color — each hue grows a patch from its emotional character.")
                .font(.caption).foregroundStyle(.white.opacity(0.55))
            HStack(spacing: 10) {
                colorButton(.red, "crimson tension, dark, gritty, tense")
                colorButton(.blue, "cold blue calm, soft pad, gentle, reverb")
                colorButton(.green, "organic forest, warm, natural, calm")
                colorButton(.yellow, "bright golden sparkle, happy, major, pluck")
                colorButton(.purple, "deep purple space, dark, wide, ambient, reverb")
            }
        }

        VinnySection(title: "Notation View — what you played", icon: "music.quarternote.3") {
            if session.notes.isEmpty {
                Text("Render a preview or loop to see its piano roll.")
                    .font(.caption).foregroundStyle(.white.opacity(0.5))
            } else {
                PianoRoll(notes: session.notes)
                    .frame(height: 110)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.04)))
            }
        }

        VinnySection(title: "Learning Path", icon: "graduationcap") {
            ForEach(lessons, id: \.0) { lesson in
                VStack(alignment: .leading, spacing: 3) {
                    Text(lesson.0).font(.system(size: 12, weight: .bold)).foregroundStyle(Glass.accent2)
                    Text(lesson.1).font(.system(size: 11)).foregroundStyle(.white.opacity(0.65))
                }
                .padding(.vertical, 4)
            }
        }
    }

    private func colorButton(_ color: Color, _ prompt: String) -> some View {
        Button {
            let p = GenesisEngine.patch(fromText: prompt, seed: UInt64(abs(prompt.hashValue)))
            session.setPatch(p)
            session.store.savePreset(p)
            session.renderPreview()
            chat.append(("🎨 Painted \(prompt.components(separatedBy: ",").first ?? "a color") → \"\(p.name)\"", false))
        } label: {
            Circle().fill(color).frame(width: 40, height: 40)
                .overlay(Circle().stroke(Color.white.opacity(0.3), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func runCommand() {
        let c = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !c.isEmpty else { return }
        chat.append((c, true))
        let (newPatch, reply) = VinnyAssistant.apply(command: c, to: session.patch)
        session.setPatch(newPatch)
        session.renderPreview()
        chat.append((reply, false))
        command = ""
    }
}

// MARK: - Piano roll (notation view)

struct PianoRoll: View {
    let notes: [VinnyDSP.VinnyNote]
    var body: some View {
        Canvas { context, size in
            guard !notes.isEmpty else { return }
            let midis = notes.map { $0.midi }
            let lo = (midis.min() ?? 60) - 2
            let hi = (midis.max() ?? 72) + 2
            let end = notes.map { $0.start + $0.duration }.max() ?? 1
            for n in notes {
                let x = CGFloat(n.start / end) * size.width
                let w = max(CGFloat(n.duration / end) * size.width, 2)
                let y = CGFloat(1 - Double(n.midi - lo) / Double(max(hi - lo, 1))) * size.height
                let rect = CGRect(x: x, y: y - 3, width: w, height: 6)
                let color: Color = n.lane == 9 ? .orange : n.lane == 1 ? Glass.buy : n.lane == 2 ? Glass.accent : Glass.accent2
                context.fill(Path(roundedRect: rect, cornerRadius: 2), with: .color(color.opacity(0.85)))
            }
        }
    }
}
