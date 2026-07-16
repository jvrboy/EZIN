import SwiftUI
import AVFoundation
import UniformTypeIdentifiers

// MARK: - VINNY player (playback with skip/rewind, shared by every module)

final class VinnyPlayer: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published var isPlaying = false
    @Published var currentTime: Double = 0
    @Published var duration: Double = 0
    @Published var loadedName = ""

    private var player: AVAudioPlayer?
    private var timer: Timer?

    override init() {
        super.init()
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    func load(data: Data, name: String) {
        stop()
        player = try? AVAudioPlayer(data: data)
        player?.delegate = self
        player?.prepareToPlay()
        duration = player?.duration ?? 0
        loadedName = name
        currentTime = 0
    }

    func play() {
        guard let player else { return }
        player.play()
        isPlaying = true
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self, let p = self.player else { return }
            Task { @MainActor in self.currentTime = p.currentTime }
        }
    }

    func pause() {
        player?.pause()
        isPlaying = false
        timer?.invalidate()
    }

    func stop() {
        player?.stop()
        player?.currentTime = 0
        isPlaying = false
        timer?.invalidate()
        currentTime = 0
    }

    func skip(by seconds: Double) {
        guard let player else { return }
        player.currentTime = min(max(player.currentTime + seconds, 0), player.duration)
        currentTime = player.currentTime
    }

    func seek(to seconds: Double) {
        guard let player else { return }
        player.currentTime = min(max(seconds, 0), player.duration)
        currentTime = player.currentTime
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.isPlaying = false
            self.currentTime = 0
            self.timer?.invalidate()
        }
    }
}

// MARK: - VINNY session (the Brain: patch state, history, renders, exports)

@MainActor
final class VinnySession: ObservableObject {
    @Published var patch: VinnyPatch
    @Published var renderedWAV: Data?
    @Published var renderedMIDI: Data?
    @Published var renderedStems: [String: Data] = [:]
    @Published var notes: [VinnyDSP.VinnyNote] = []
    @Published var status = "Ready. Grow a patch in GENESIS or load one from the VAULT."
    @Published var busy = false
    @Published var history: [VinnyPatch] = []
    @Published var historyIndex = -1
    @Published var lastLoop: LoopResult?
    @Published var weatherEnabled = false

    let player = VinnyPlayer()
    let store = VinnyStore.shared

    init() {
        let initial = VinnyStore.shared.presets.first ?? VinnyPatch.default
        patch = initial
        pushHistory(initial)
    }

    func setPatch(_ p: VinnyPatch, snapshot: Bool = true) {
        patch = p.normalized()
        if snapshot { pushHistory(patch) }
    }

    private func pushHistory(_ p: VinnyPatch) {
        if historyIndex < history.count - 1 { history = Array(history.prefix(historyIndex + 1)) }
        history.append(p)
        historyIndex = history.count - 1
        if history.count > 80 { history.removeFirst(history.count - 80); historyIndex = history.count - 1 }
    }

    func undo() {
        guard historyIndex > 0 else { return }
        historyIndex -= 1
        patch = history[historyIndex]
        status = "Evolution timeline: back to v\(patch.version) \"\(patch.name)\"."
    }

    func redo() {
        guard historyIndex < history.count - 1 else { return }
        historyIndex += 1
        patch = history[historyIndex]
        status = "Evolution timeline: forward to v\(patch.version) \"\(patch.name)\"."
    }

    /// Short demo phrase so every module has something to play.
    private func demoNotes() -> [VinnyDSP.VinnyNote] {
        let beat = 60.0 / patch.bpm
        var out: [VinnyDSP.VinnyNote] = []
        for (i, deg) in [0, 2, 4, 7, 4, 2].enumerated() {
            let midi = TheoryEngine.degreeToMidi(deg, octave: 4, key: patch.key, scale: patch.scale)
            out.append(VinnyDSP.VinnyNote(midi: midi, start: Double(i) * beat * 0.5, duration: beat * 0.48, velocity: 0.8, lane: 0))
        }
        return out
    }

    func renderPreview() {
        busy = true
        status = "Rendering preview…"
        let p = patch
        let phrase = demoNotes()
        Task.detached(priority: .userInitiated) {
            let duration = 60.0 / p.bpm * 3.2
            var wav = VinnyRenderer.renderWAV(patch: p, notes: phrase, durationSec: duration)
            // Sound Weather: evolving ambient bed underneath.
            if await self.weatherEnabled, let pcm = VinnyDSP.readWAV(wav) {
                let cfg = VinnyDSP.GranularConfig(grainSizeMs: 160, density: 14, pitchRandom: 0.05, positionRandom: 0.8, durationSec: duration, seed: UInt64(p.name.hashValue & 0x7fffffff))
                let bed = VinnyDSP.granularCloud(pcm.mono, config: cfg, sampleRate: pcm.sampleRate)
                let mixed = VinnyDSP.mix(pcm.mono, bed, gainA: 1.0, gainB: 0.35)
                wav = VinnyDSP.writeWAV(VinnyDSP.normalize(mixed, target: 0.88), sampleRate: pcm.sampleRate)
            }
            await MainActor.run {
                self.renderedWAV = wav
                self.notes = phrase
                self.player.load(data: wav, name: "\(p.name) — preview")
                self.player.play()
                self.status = "Preview rendered · \(String(format: "%.1f", self.player.duration))s."
                self.busy = false
            }
        }
    }

    func renderLoop(bars: Int = 4, variation: Int = 0, swing: Double = 0) {
        busy = true
        status = "Loop Factory is building your loop…"
        let p = patch
        Task.detached(priority: .userInitiated) {
            let seedBase = UInt64(abs(p.name.hashValue) % 100000)
            let seedVariation = UInt64(variation) &* 977
            let seed = seedBase &+ seedVariation
            let result = LoopFactory.makeLoop(patch: p, bars: bars, seed: seed, variation: variation, swing: swing)
            await MainActor.run {
                self.lastLoop = result
                self.renderedWAV = result.wav
                self.renderedMIDI = result.midi
                self.renderedStems = result.stems
                self.notes = result.notes
                self.player.load(data: result.wav, name: "\(p.genre) loop · \(Int(result.bpm)) BPM · \(result.key) \(result.scale)")
                self.player.play()
                self.status = "Loop ready — \(result.genre) · \(Int(result.bpm)) BPM · \(result.key) \(result.scale) · \(bars) bars · \(result.notes.count) notes."
                self.busy = false
            }
        }
    }

    // MARK: Exports (registered as chat-visible artifacts too)

    @discardableResult
    private func registerArtifact(data: Data, name: String, ext: String) -> Artifact {
        let url = FileStore.shared.saveData(data, name: name, in: FileStore.shared.artifactsDir)
        let rel = FileStore.shared.relativePath(url)
        let artifact = Artifact(name: name, relativePath: rel, kind: ext, byteSize: Int64(data.count))
        ArtifactStore.shared.add(artifact)
        return artifact
    }

    func exportWAV() {
        guard let wav = renderedWAV else { status = "Nothing rendered yet."; return }
        registerArtifact(data: wav, name: sanitized("\(patch.name).wav"), ext: "wav")
        status = "Exported WAV to Artifacts (visible in Files → EZIN → Artifacts)."
    }

    func exportMIDI() {
        let midi = renderedMIDI ?? VinnyDSP.midiFile(notes: notes, bpm: Int(patch.bpm.rounded()))
        guard !notes.isEmpty else { status = "Nothing rendered yet."; return }
        registerArtifact(data: midi, name: sanitized("\(patch.name).mid"), ext: "mid")
        status = "Exported MIDI to Artifacts."
    }

    func exportStemsZIP() {
        guard let loop = lastLoop else { status = "Render a loop first — then export its stems."; return }
        var entries: [ZipWriter.Entry] = []
        for (name, data) in loop.stems.sorted(by: { $0.key < $1.key }) {
            entries.append(ZipWriter.Entry(name: "\(patch.name)/stems/\(name).wav", data: data))
        }
        entries.append(ZipWriter.Entry(name: "\(patch.name)/full-mix.wav", data: loop.wav))
        entries.append(ZipWriter.Entry(name: "\(patch.name)/loop.mid", data: loop.midi))
        if let patchJSON = try? JSONEncoder().encode(patch) {
            entries.append(ZipWriter.Entry(name: "\(patch.name)/patch.vinnypatch.json", data: patchJSON))
        }
        guard let zip = ZipWriter.makeZip(entries: entries) else { status = "ZIP build failed."; return }
        registerArtifact(data: zip, name: sanitized("\(patch.name)-STEMS.zip"), ext: "zip")
        status = "Exported STEMS ZIP — all stems + full mix WAV + MIDI + patch file."
    }

    func exportPatch() {
        guard let data = try? JSONEncoder().encode(patch) else { return }
        registerArtifact(data: data, name: sanitized("\(patch.name).vinnypatch.json"), ext: "json")
        status = "Patch exported — share it; collaborators can re-import it in the VAULT."
    }

    private func sanitized(_ s: String) -> String {
        s.replacingOccurrences(of: "[^A-Za-z0-9._-]", with: "-", options: .regularExpression)
    }

    /// Sound DNA: capture the current render's fingerprint into the patch.
    func captureDNA() {
        guard let wav = renderedWAV, let pcm = VinnyDSP.readWAV(wav) else { status = "Render first, then capture Sound DNA."; return }
        patch.dna = VinnyDSP.fingerprint(pcm.mono, sampleRate: pcm.sampleRate)
        store.saveFingerprint(name: patch.name, vector: patch.dna)
        store.savePreset(patch)
        status = "Sound DNA captured. Use HYBRIDIZER → Inject DNA or Earprint → Match to recall it anywhere."
    }
}

// MARK: - Shared VINNY UI atoms

struct VinnySection<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: icon)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white.opacity(0.85))
            content
        }
        .padding(14)
        .glassCard()
    }
}

struct VinnySlider: View {
    let label: String
    @Binding var value: Double
    var range: ClosedRange<Double> = 0...1
    var format: String = "%.2f"
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label).font(.system(size: 11)).foregroundStyle(.white.opacity(0.6))
                Spacer()
                Text(String(format: format, value)).font(.system(size: 10, design: .monospaced)).foregroundStyle(Glass.accent2)
            }
            Slider(value: $value, in: range).tint(Glass.accent)
        }
    }
}

struct VinnyAction: View {
    let title: String
    let icon: String
    var tint: Color = Glass.accent
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                Text(title).font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(tint.opacity(0.5)))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.18), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

struct VinnyPlayerBar: View {
    @ObservedObject var player: VinnyPlayer
    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 14) {
                Button { player.skip(by: -10) } label: {
                    Image(systemName: "gobackward.10").font(.system(size: 20)).foregroundStyle(.white)
                }.buttonStyle(.plain)
                Button { player.isPlaying ? player.pause() : player.play() } label: {
                    Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 38)).foregroundStyle(Glass.accent2)
                }.buttonStyle(.plain)
                Button { player.skip(by: 10) } label: {
                    Image(systemName: "goforward.10").font(.system(size: 20)).foregroundStyle(.white)
                }.buttonStyle(.plain)
                Button { player.stop() } label: {
                    Image(systemName: "stop.fill").font(.system(size: 16)).foregroundStyle(.white.opacity(0.6))
                }.buttonStyle(.plain)
            }
            HStack(spacing: 8) {
                Text(time(player.currentTime)).font(.system(size: 10, design: .monospaced)).foregroundStyle(.white.opacity(0.55))
                Slider(value: Binding(get: { player.currentTime }, set: { player.seek(to: $0) }), in: 0...max(player.duration, 0.1))
                    .tint(Glass.accent)
                Text(time(player.duration)).font(.system(size: 10, design: .monospaced)).foregroundStyle(.white.opacity(0.55))
            }
            if !player.loadedName.isEmpty {
                Text(player.loadedName).font(.system(size: 10)).foregroundStyle(.white.opacity(0.45)).lineLimit(1)
            }
        }
        .padding(12)
        .glassCard()
    }
    private func time(_ t: Double) -> String { String(format: "%d:%02d", Int(t) / 60, Int(t) % 60) }
}

// MARK: - VINNY home (module router)

enum VinnyModule: String, CaseIterable, Identifiable {
    case brain = "Brain"
    case genesis = "Genesis"
    case waveforge = "WaveForge"
    case organica = "Organica"
    case temposhift = "TempoShift"
    case earprint = "Earprint"
    case flowstate = "FlowState"
    case spaceship = "Spaceship"
    case hybridizer = "Hybridizer"
    case stage = "Stage"
    case vault = "Vault"
    case vinnyAI = "Vinny AI"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .brain: return "brain"
        case .genesis: return "leaf"
        case .waveforge: return "waveform"
        case .organica: return "cloud"
        case .temposhift: return "clock.arrow.2.circlepath"
        case .earprint: return "ear"
        case .flowstate: return "scribble.variable"
        case .spaceship: return "sparkles"
        case .hybridizer: return "atom"
        case .stage: return "music.mic"
        case .vault: return "archivebox"
        case .vinnyAI: return "bubble.left.and.text.bubble.right"
        }
    }
    var tagline: String {
        switch self {
        case .brain: return "Signal router · macros · mood space"
        case .genesis: return "AI sound grower"
        case .waveforge: return "Wavetable synth lab"
        case .organica: return "Granular textures"
        case .temposhift: return "Time-warp FX"
        case .earprint: return "Audio identifier"
        case .flowstate: return "Modulation studio"
        case .spaceship: return "FX & spatial rack"
        case .hybridizer: return "Fusion lab"
        case .stage: return "Live performance"
        case .vault: return "Preset cloud"
        case .vinnyAI: return "Coach · color · weather"
        }
    }
}

struct VinnyHomeView: View {
    @StateObject private var session = VinnySession()
    @State private var module: VinnyModule = .brain

    var body: some View {
        ZStack {
            AuroraBackground()
            VStack(spacing: 0) {
                // Module ribbon
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(VinnyModule.allCases) { m in
                            Button { withAnimation(.easeInOut(duration: 0.2)) { module = m } } label: {
                                VStack(spacing: 3) {
                                    Image(systemName: m.icon).font(.system(size: 15, weight: .semibold))
                                    Text(m.rawValue).font(.system(size: 9, weight: .bold))
                                }
                                .frame(width: 74)
                                .padding(.vertical, 8)
                                .foregroundStyle(module == m ? .white : .white.opacity(0.5))
                                .background(RoundedRectangle(cornerRadius: 12).fill(module == m ? Glass.accent.opacity(0.45) : Color.white.opacity(0.06)))
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(module == m ? Glass.accent2.opacity(0.6) : Color.white.opacity(0.1), lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                }

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        switch module {
                        case .brain: VinnyBrainView(session: session)
                        case .genesis: VinnyGenesisView(session: session)
                        case .waveforge: VinnyWaveForgeView(session: session)
                        case .organica: VinnyOrganicaView(session: session)
                        case .temposhift: VinnyTempoShiftView(session: session)
                        case .earprint: VinnyEarprintView(session: session)
                        case .flowstate: VinnyFlowStateView(session: session)
                        case .spaceship: VinnySpaceshipView(session: session)
                        case .hybridizer: VinnyHybridizerView(session: session)
                        case .stage: VinnyStageView(session: session)
                        case .vault: VinnyVaultView(session: session)
                        case .vinnyAI: VinnyAIView(session: session)
                        }
                        statusCard
                        VinnyPlayerBar(player: session.player)
                    }
                    .padding(16)
                    .padding(.bottom, 24)
                }
            }
        }
        .navigationTitle("VINNY")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarHidden(false)
    }

    private var statusCard: some View {
        HStack(spacing: 8) {
            if session.busy { ProgressView().tint(.white).scaleEffect(0.8) }
            Text(session.status).font(.system(size: 11)).foregroundStyle(.white.opacity(0.6))
            Spacer()
        }
        .padding(12)
        .glassCard()
    }
}

// MARK: - Module: Brain (router, macros, mood space)

struct VinnyBrainView: View {
    @ObservedObject var session: VinnySession

    var body: some View {
        VinnySection(title: "The Brain — \(session.patch.name)", icon: "brain") {
            Text("Every module routes through here. Twist a macro, drag the mood space, then render.")
                .font(.caption).foregroundStyle(.white.opacity(0.55))
            HStack(spacing: 10) {
                VinnyAction(title: "Preview", icon: "play.fill") { session.renderPreview() }
                VinnyAction(title: "Loop", icon: "repeat", tint: Glass.accent2) { session.renderLoop() }
                Menu {
                    Button("Export WAV") { session.exportWAV() }
                    Button("Export MIDI") { session.exportMIDI() }
                    Button("Export STEMS ZIP") { session.exportStemsZIP() }
                    Button("Export Patch (collab share)") { session.exportPatch() }
                    Button("Capture Sound DNA") { session.captureDNA() }
                } label: {
                    HStack(spacing: 6) { Image(systemName: "square.and.arrow.up"); Text("Export").font(.system(size: 13, weight: .semibold)) }
                        .foregroundStyle(.white).frame(maxWidth: .infinity).padding(.vertical, 11)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color.purple.opacity(0.45)))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.18), lineWidth: 1))
                }
            }
        }

        VinnySection(title: "Global Macros (8 assignable)", icon: "dial.medium") {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 12) {
                ForEach(0..<8, id: \.self) { i in
                    VStack(spacing: 4) {
                        Text("M\(i + 1)").font(.system(size: 9, weight: .bold)).foregroundStyle(.white.opacity(0.5))
                        ZStack {
                            Circle().stroke(Color.white.opacity(0.15), lineWidth: 4)
                            Circle().trim(from: 0, to: CGFloat(session.patch.macros[i]))
                                .stroke(Glass.accent2, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                                .rotationEffect(.degrees(-90))
                            Text("\(Int(session.patch.macros[i] * 100))").font(.system(size: 10, weight: .bold)).foregroundStyle(.white)
                        }
                        .frame(width: 44, height: 44)
                        Slider(value: $session.patch.macros[i]).tint(Glass.accent2).frame(width: 64)
                    }
                }
            }
            Text("M1 drives the render intensity; the rest are saved per preset for your controller mappings.")
                .font(.system(size: 10)).foregroundStyle(.white.opacity(0.4))
        }

        VinnySection(title: "Mood-to-Sound Space", icon: "slider.horizontal.below.square.filled.and.square") {
            VinnySlider(label: "Dark ↔ Bright", value: $session.patch.moodDark, range: -1...1)
            VinnySlider(label: "Tense ↔ Calm", value: $session.patch.moodTense, range: -1...1)
            VinnySlider(label: "Organic ↔ Digital", value: $session.patch.moodOrganic, range: -1...1)
            HStack(spacing: 10) {
                VinnyAction(title: "Apply Mood", icon: "wand.and.stars") { applyMood() }
                VinnyAction(title: "Time Machine Snapshot", icon: "clock.arrow.circlepath", tint: .purple) {
                    session.store.snapshot(session.patch)
                    session.status = "Snapshot stored in the Time Machine (VAULT)."
                }
            }
        }

        VinnySection(title: "Voice Stack & Engine", icon: "person.3.sequence") {
            VinnySlider(label: "Unison voices: \(session.patch.unisonVoices)", value: Binding(
                get: { Double(session.patch.unisonVoices) },
                set: { session.patch.unisonVoices = Int($0.rounded()) }), range: 1...16, format: "%.0f")
            VinnySlider(label: "Unison detune", value: $session.patch.unisonDetune)
            VinnySlider(label: "Stereo width", value: $session.patch.stereoWidth)
            VinnySlider(label: "BPM: \(Int(session.patch.bpm))", value: $session.patch.bpm, range: 50...220, format: "%.0f")
            HStack {
                Text("Weather system").font(.system(size: 11)).foregroundStyle(.white.opacity(0.6))
                Spacer()
                Toggle("", isOn: $session.weatherEnabled).labelsHidden().tint(Glass.accent2)
            }
            Text("Weather adds a generative ambient bed that evolves under your preview — a living climate per patch.")
                .font(.system(size: 10)).foregroundStyle(.white.opacity(0.4))
        }
    }

    private func applyMood() {
        var p = session.patch
        // Mood drives dozens of parameters at once.
        p.filterCutoff = min(max(6000 * (1 - p.moodDark) + 800, 200), 18000)
        p.env.attack = max(0.002, 0.2 * (1 - p.moodTense) * 0.5)
        p.fmAmount = max(0, p.moodTense) * 0.4
        p.unisonVoices = p.moodOrganic > 0 ? Int(2 + p.moodOrganic * 6) : max(1, Int(1 - p.moodOrganic * 0))
        p.osc[0].wave = p.moodOrganic > 0.3 ? .triangle : p.moodOrganic < -0.3 ? .wavetable : .saw
        session.setPatch(p)
        session.status = "Mood applied across the engine. Preview it."
    }
}

// MARK: - Module: Genesis (AI sound grower)

struct VinnyGenesisView: View {
    @ObservedObject var session: VinnySession
    @State private var prompt = "warm analog bass with a metallic tail"
    @State private var mutations: [VinnyPatch] = []
    @State private var showImporter = false

    var body: some View {
        VinnySection(title: "Text-to-Patch AI", icon: "text.bubble") {
            TextEditor(text: $prompt)
                .frame(height: 64)
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.06)))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.12), lineWidth: 1))
                .foregroundStyle(.white)
            VinnyAction(title: "Grow Patch", icon: "leaf.fill") {
                let p = GenesisEngine.patch(fromText: prompt, seed: UInt64(Date().timeIntervalSince1970))
                session.setPatch(p)
                session.store.savePreset(p)
                mutations = GenesisEngine.mutations(of: p)
                session.status = "Grew \"\(p.name)\" — \(p.genre), \(p.key) \(p.scale), \(Int(p.bpm)) BPM. 8 mutations spawned below."
                session.renderPreview()
            }
        }

        VinnySection(title: "Audio-to-Patch Reverse Engineering", icon: "doc.viewfinder") {
            Text("Drop any WAV and VINNY rebuilds the patch that made it — filter, oscillators, key, tempo, FX.")
                .font(.caption).foregroundStyle(.white.opacity(0.55))
            VinnyAction(title: "Import Reference Audio", icon: "square.and.arrow.down", tint: .purple) { showImporter = true }
        }

        if !mutations.isEmpty {
            VinnySection(title: "Mutation Tree — crossbreed the DNA", icon: "point.3.connected.trianglepath.dotted") {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(mutations) { m in
                        Button {
                            session.setPatch(m)
                            session.renderPreview()
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(m.name).font(.system(size: 11, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                                Text("cutoff \(Int(m.filterCutoff)) · \(m.unisonVoices)v · v\(m.version)").font(.system(size: 9)).foregroundStyle(.white.opacity(0.5))
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.06)))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.1), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }

        VinnySection(title: "Preset Evolution Timeline", icon: "arrow.triangle.branch") {
            HStack(spacing: 10) {
                VinnyAction(title: "◂ Undo", icon: "arrow.uturn.backward") { session.undo() }
                VinnyAction(title: "Redo ▸", icon: "arrow.uturn.forward") { session.redo() }
            }
            Text("\(session.history.count) states in this session's branching history (v\(session.patch.version) now).")
                .font(.system(size: 10)).foregroundStyle(.white.opacity(0.45))
        }
        .sheet(isPresented: $showImporter) {
            DocumentPicker { urls in
                guard let url = urls.first, let data = try? Data(contentsOf: url) else { return }
                if let p = GenesisEngine.patch(fromAudio: data) {
                    session.setPatch(p)
                    session.store.savePreset(p)
                    session.status = "Reverse-engineered \(url.lastPathComponent) → key \(p.key) \(p.scale), \(Int(p.bpm)) BPM, cutoff \(Int(p.filterCutoff)) Hz."
                    session.renderPreview()
                } else {
                    session.status = "That file isn't a 16-bit PCM WAV. Export or convert to WAV first."
                }
            }
        }
    }
}

// MARK: - Module: WaveForge (wavetable synth lab)

struct VinnyWaveForgeView: View {
    @ObservedObject var session: VinnySession

    var body: some View {
        ForEach(0..<4, id: \.self) { i in
            VinnySection(title: "Oscillator \(i + 1)", icon: "waveform") {
                HStack {
                    Toggle("", isOn: $session.patch.osc[i].enabled).labelsHidden().tint(Glass.accent2)
                    Picker("Wave", selection: $session.patch.osc[i].wave) {
                        ForEach(VinnyDSP.Wave.allCases) { w in Text(w.label).tag(w) }
                    }
                    .pickerStyle(.menu).tint(Glass.accent2)
                    Spacer()
                    Stepper("Oct \(session.patch.osc[i].octave)", value: $session.patch.osc[i].octave, in: -2...2)
                        .font(.system(size: 11)).foregroundStyle(.white.opacity(0.7)).frame(width: 130)
                }
                VinnySlider(label: "Level", value: $session.patch.osc[i].level)
                VinnySlider(label: "Detune (cents)", value: $session.patch.osc[i].detune, range: -50...50, format: "%.0f")
                if session.patch.osc[i].wave == .wavetable {
                    Text("Spectral editor — paint the harmonics").font(.system(size: 10)).foregroundStyle(.white.opacity(0.5))
                    HStack(alignment: .bottom, spacing: 4) {
                        ForEach(0..<min(8, session.patch.osc[i].harmonics.count), id: \.self) { h in
                            VStack(spacing: 2) {
                                Slider(value: $session.patch.osc[i].harmonics[h], in: 0...1)
                                    .rotationEffect(.degrees(-90)).frame(width: 40, height: 40)
                                    .tint(Glass.accent)
                                Text("H\(h + 1)").font(.system(size: 8)).foregroundStyle(.white.opacity(0.45))
                            }
                            .frame(height: 64)
                        }
                    }
                }
            }
        }

        VinnySection(title: "Cross-Modulation Matrix", icon: "arrow.triangle.swap") {
            VinnySlider(label: "FM (osc 2 → 1)", value: $session.patch.fmAmount)
            VinnySlider(label: "Ring mod", value: $session.patch.rmAmount)
            VinnySlider(label: "Amplitude mod", value: $session.patch.amAmount)
            VinnySlider(label: "Sub oscillator", value: $session.patch.subLevel)
            VinnySlider(label: "Noise", value: $session.patch.noiseLevel)
        }

        VinnySection(title: "Filter & Envelope", icon: "line.3.horizontal.decrease.circle") {
            Picker("Type", selection: $session.patch.filterType) {
                Text("Low-pass").tag(0); Text("High-pass").tag(1); Text("Band-pass").tag(2)
            }
            .pickerStyle(.segmented)
            VinnySlider(label: "Cutoff: \(Int(session.patch.filterCutoff)) Hz", value: $session.patch.filterCutoff, range: 100...18000, format: "%.0f")
            VinnySlider(label: "Resonance", value: $session.patch.filterReso, range: 0.2...4)
            VinnySlider(label: "Attack", value: $session.patch.env.attack, range: 0.001...1.5, format: "%.3f")
            VinnySlider(label: "Decay", value: $session.patch.env.decay, range: 0.01...1.5)
            VinnySlider(label: "Sustain", value: $session.patch.env.sustain)
            VinnySlider(label: "Release", value: $session.patch.env.release, range: 0.01...2.5)
            VinnyAction(title: "Hear It", icon: "play.fill") { session.renderPreview() }
        }
    }
}

// MARK: - Module: Organica (granular & texture engine)

struct VinnyOrganicaView: View {
    @ObservedObject var session: VinnySession
    @State private var grainSize = 90.0
    @State private var density = 24.0
    @State private var pitchRandom = 0.12
    @State private var positionRandom = 0.4
    @State private var cloudDuration = 4.0
    @State private var showImporter = false
    @State private var imported: Data?

    var body: some View {
        VinnySection(title: "Granular Cloud Engine", icon: "cloud.fill") {
            Text("Scatter any source into grains. Uses your last render — or import a sample.")
                .font(.caption).foregroundStyle(.white.opacity(0.55))
            HStack(spacing: 10) {
                VinnyAction(title: "Import Sample", icon: "square.and.arrow.down", tint: .purple) { showImporter = true }
                if imported != nil { Text("sample loaded").font(.system(size: 10)).foregroundStyle(Glass.buy) }
            }
            VinnySlider(label: "Grain size: \(Int(grainSize)) ms", value: $grainSize, range: 20...300, format: "%.0f")
            VinnySlider(label: "Density: \(Int(density))/s", value: $density, range: 4...60, format: "%.0f")
            VinnySlider(label: "Pitch scatter", value: $pitchRandom)
            VinnySlider(label: "Position scatter", value: $positionRandom)
            VinnySlider(label: "Cloud length: \(Int(cloudDuration))s", value: $cloudDuration, range: 2...12, format: "%.0f")
            VinnyAction(title: "Render Cloud", icon: "cloud.rain") { renderCloud() }
        }

        VinnySection(title: "Time Freeze", icon: "snowflake") {
            Text("Freeze any moment of your last render into an infinite pad.")
                .font(.caption).foregroundStyle(.white.opacity(0.55))
            VinnyAction(title: "Freeze → Infinite Pad", icon: "pause.circle") { freeze() }
        }

        VinnySection(title: "Built-In Sound Library", icon: "books.vertical") {
            Text("Curated starter textures — tap to grow a patch from one.")
                .font(.caption).foregroundStyle(.white.opacity(0.55))
            ForEach(["rainforest field recording", "vinyl crackle foley", "cathedral drone", "ocean swell pad"], id: \.self) { name in
                Button {
                    let p = GenesisEngine.patch(fromText: "ambient cinematic pad, organic, wide, calm, reverb", seed: UInt64(abs(name.hashValue)))
                    session.setPatch(p)
                    session.weatherEnabled = true
                    session.renderPreview()
                    session.status = "Loaded library texture \"\(name)\" (weather bed on)."
                } label: {
                    HStack {
                        Image(systemName: "waveform.path").foregroundStyle(Glass.accent2)
                        Text(name).font(.system(size: 12)).foregroundStyle(.white.opacity(0.8))
                        Spacer()
                        Image(systemName: "play.fill").font(.system(size: 10)).foregroundStyle(.white.opacity(0.4))
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.05)))
                }
                .buttonStyle(.plain)
            }
        }
        .sheet(isPresented: $showImporter) {
            DocumentPicker { urls in
                guard let url = urls.first, let data = try? Data(contentsOf: url), VinnyDSP.readWAV(data) != nil else {
                    session.status = "Import a 16-bit PCM WAV for granular work."
                    return
                }
                imported = data
                session.status = "Sample loaded — render the cloud."
            }
        }
    }

    private func renderCloud() {
        guard let source = imported ?? session.renderedWAV, let pcm = VinnyDSP.readWAV(source) else {
            session.status = "Render a preview first (Brain → Preview) or import a sample."
            return
        }
        session.busy = true
        let cfg = VinnyDSP.GranularConfig(grainSizeMs: grainSize, density: density, pitchRandom: pitchRandom, positionRandom: positionRandom, durationSec: cloudDuration, seed: UInt64(Date().timeIntervalSince1970))
        Task.detached(priority: .userInitiated) {
            let cloud = VinnyDSP.granularCloud(pcm.mono, config: cfg, sampleRate: pcm.sampleRate)
            let wet = VinnyDSP.reverb(cloud, roomSize: 0.6, damping: 0.4, mix: 0.35, sampleRate: pcm.sampleRate)
            let wav = VinnyDSP.writeWAV(VinnyDSP.normalize(wet, target: 0.88), sampleRate: pcm.sampleRate)
            await MainActor.run {
                session.renderedWAV = wav
                session.player.load(data: wav, name: "Granular cloud")
                session.player.play()
                session.busy = false
                session.status = "Cloud rendered — \(Int(cfg.durationSec))s of scattered grains."
            }
        }
    }

    private func freeze() {
        guard let wav = session.renderedWAV, let pcm = VinnyDSP.readWAV(wav) else {
            session.status = "Render something first, then freeze it."
            return
        }
        session.busy = true
        Task.detached(priority: .userInitiated) {
            let pad = VinnyDSP.freezePad(pcm.mono, at: Double(session.player.currentTime) / max(session.player.duration, 0.1), durationSec: 6, sampleRate: pcm.sampleRate)
            let out = VinnyDSP.writeWAV(pad, sampleRate: pcm.sampleRate)
            await MainActor.run {
                session.renderedWAV = out
                session.player.load(data: out, name: "Frozen pad")
                session.player.play()
                session.busy = false
                session.status = "Froze the moment into a 6s infinite pad."
            }
        }
    }
}
