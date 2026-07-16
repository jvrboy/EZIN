import Foundation

// MARK: - VINNY patch & FX model

enum FXKind: String, Codable, CaseIterable, Identifiable {
    case reverb, delay, chorus, flanger, distortion, bitcrusher, ringMod, compressor, eq, widener
    var id: String { rawValue }
    var label: String {
        switch self {
        case .reverb: return "Reverb"
        case .delay: return "Delay"
        case .chorus: return "Chorus"
        case .flanger: return "Flanger"
        case .distortion: return "Distortion"
        case .bitcrusher: return "Bitcrusher"
        case .ringMod: return "Ring Mod"
        case .compressor: return "Compressor"
        case .eq: return "3-Band EQ"
        case .widener: return "Stereo Widener"
        }
    }
    var icon: String {
        switch self {
        case .reverb: return "building.2"
        case .delay: return "repeat"
        case .chorus: return "person.3"
        case .flanger: return "airplane"
        case .distortion: return "bolt.fill"
        case .bitcrusher: return "square.grid.3x3"
        case .ringMod: return "circle.circle"
        case .compressor: return "arrow.down.to.line"
        case .eq: return "slider.vertical.3"
        case .widener: return "arrow.left.and.right"
        }
    }
    /// (p1, p2, p3) labels per effect.
    var paramLabels: (String, String, String) {
        switch self {
        case .reverb: return ("Room", "Damping", "Mix")
        case .delay: return ("Time", "Feedback", "Mix")
        case .chorus: return ("Rate", "Depth", "Mix")
        case .flanger: return ("Rate", "Depth", "Feedback")
        case .distortion: return ("Drive", "Tone", "Mix")
        case .bitcrusher: return ("Bits", "Downsample", "Mix")
        case .ringMod: return ("Freq", "Mix", "—")
        case .compressor: return ("Thresh", "Ratio", "Attack")
        case .eq: return ("Low", "Mid", "High")
        case .widener: return ("Width", "—", "—")
        }
    }
}

struct FXSlot: Codable, Equatable, Identifiable {
    var id = UUID()
    var kind: FXKind
    var enabled = true
    var mix = 0.4
    var p1 = 0.5, p2 = 0.5, p3 = 0.5
}

struct OscConfig: Codable, Equatable, Identifiable {
    var id = UUID()
    var enabled = true
    var wave: VinnyDSP.Wave = .saw
    var octave = 0                 // -2...+2
    var semitone = 0               // -12...+12
    var detune = 0.0               // cents
    var level = 0.5
    var harmonics: [Float] = [1, 0.35, 0.12, 0.05]  // wavetable partials (spectral editor)
    var morphT = 0.0               // morph position between this table and its neighbor
}

/// A full VINNY patch — every module's state in one Codable document.
/// Saved to the Vault, versioned, breedable, morphable, exportable.
struct VinnyPatch: Codable, Equatable, Identifiable {
    var id = UUID()
    var name = "Init Patch"
    var genre = "Electronic"
    var tags: [String] = []
    // Mood space
    var moodDark = 0.0      // -1 bright … +1 dark
    var moodTense = 0.0     // -1 calm … +1 tense
    var moodOrganic = 0.0   // -1 digital … +1 organic
    // Engine
    var osc: [OscConfig] = [OscConfig(), OscConfig(wave: .sine, level: 0.0), OscConfig(wave: .square, level: 0.0), OscConfig(wave: .triangle, level: 0.0)]
    var subLevel = 0.0
    var noiseLevel = 0.0
    var filterCutoff = 9000.0
    var filterReso = 0.7
    var filterType = 0      // 0 lowpass · 1 highpass · 2 bandpass
    var filterEnvAmount = 0.0
    var env = VinnyDSP.ADSR()
    var unisonVoices = 1
    var unisonDetune = 0.0  // 0...1 (spread)
    var stereoWidth = 0.3
    var fmAmount = 0.0
    var rmAmount = 0.0
    var amAmount = 0.0
    var fx: [FXSlot] = []
    var macros: [Double] = Array(repeating: 0.5, count: 8)
    var bpm = 120.0
    var key = "C"
    var scale = "minor"
    var createdAt = Date()
    var version = 1
    var parentName: String? = nil
    var dna: [Double] = []  // Sound DNA vector (fingerprint of the patch's own render)

    static var `default`: VinnyPatch {
        var p = VinnyPatch()
        p.name = "Init Patch"
        p.fx = [FXSlot(kind: .reverb, mix: 0.25)]
        return p
    }

    /// Guard against malformed/imported patches: engine expects exactly 4 oscillators
    /// and 8 macros. Call after decoding or before rendering.
    func normalized() -> VinnyPatch {
        var p = self
        while p.osc.count < 4 { p.osc.append(OscConfig(wave: .sine, level: 0)) }
        if p.osc.count > 4 { p.osc = Array(p.osc.prefix(4)) }
        while p.macros.count < 8 { p.macros.append(0.5) }
        if p.macros.count > 8 { p.macros = Array(p.macros.prefix(8)) }
        p.filterCutoff = min(max(p.filterCutoff, 50), 19000)
        p.bpm = min(max(p.bpm, 30), 300)
        p.unisonVoices = min(max(p.unisonVoices, 1), 16)
        return p
    }
}

// MARK: - VINNY renderer (patch + notes → PCM)

enum VinnyRenderer {

    /// Render note lanes (non-drum) of a patch into mono samples.
    static func render(patch: VinnyPatch, notes: [VinnyDSP.VinnyNote], durationSec: Double, sampleRate: Int = VinnyDSP.defaultSampleRate) -> [Float] {
        let total = max(1, Int(durationSec * Double(sampleRate)))
        var out = [Float](repeating: 0, count: total)
        var rng = SeededRNG(UInt64(patch.name.hashValue & 0x7fffffff))

        for note in notes where note.lane != 9 {
            let start = Int(note.start * Double(sampleRate))
            let noteSamples = Int((note.duration + patch.env.release + 0.05) * Double(sampleRate))
            guard start >= 0, start < total, noteSamples > 8 else { continue }
            let lanes: [OscConfig] = patch.osc.filter { $0.enabled && $0.level > 0.01 }
            guard !lanes.isEmpty else { continue }
            // Wavetables per ACTIVE lane (indices differ from patch.osc when some are off).
            let laneTables: [[Float]] = lanes.map { $0.wave == .wavetable ? VinnyDSP.makeWavetable(harmonics: $0.harmonics) : [] }

            var filter = VinnyDSP.Biquad(
                kind: patch.filterType == 1 ? .highpass : patch.filterType == 2 ? .bandpass : .lowpass,
                cutoff: patch.filterCutoff, q: patch.filterReso, sampleRate: sampleRate)
            let voices = max(1, min(16, patch.unisonVoices))
            let macroBoost = patch.macros.isEmpty ? 1.0 : (0.75 + patch.macros[0] * 0.5)

            for i in 0..<noteSamples {
                let idx = start + i
                if idx >= total { break }
                let t = Double(i) / Double(sampleRate)
                let env = patch.env.value(at: t, noteDuration: note.duration)
                if env <= 0, t > note.duration { break }

                var sample = 0.0
                var carrier = 0.0
                for (oscIdx, o) in lanes.enumerated() {
                    let semis = Double(note.midi - 69) + Double(o.octave * 12) + Double(o.semitone)
                    let baseFreq = 440.0 * pow(2.0, semis / 12.0)
                    for v in 0..<voices {
                        let spread = voices > 1 ? (Double(v) / Double(voices - 1) - 0.5) * 2 : 0
                        let detuneCents = (o.detune + spread * patch.unisonDetune * 25)
                        let f = baseFreq * pow(2.0, detuneCents / 1200.0)
                        var phase = f * t
                        // FM: osc 2 modulates osc 1.
                        if oscIdx == 0, patch.fmAmount > 0.001, lanes.count > 1 {
                            phase += carrier * patch.fmAmount * 4
                        }
                        let table = o.wave == .wavetable ? laneTables[oscIdx] : nil
                        var s = Double(VinnyDSP.osc(o.wave, phase: phase, table: table, rng: &rng))
                        // RM / AM from osc 1 onto the rest.
                        if oscIdx > 0 {
                            if patch.rmAmount > 0.001 { s *= (1 - patch.rmAmount) + carrier * patch.rmAmount }
                            if patch.amAmount > 0.001 { s *= (1 - patch.amAmount) + abs(carrier) * patch.amAmount }
                        }
                        if oscIdx == 0 { carrier = s }
                        sample += s * o.level / Double(voices)
                    }
                }
                if patch.subLevel > 0.01 {
                    sample += sin(2 * .pi * note.frequency * 0.5 * t) * patch.subLevel
                }
                if patch.noiseLevel > 0.01 {
                    sample += Double(rng.nextFloat() * 2 - 1) * patch.noiseLevel
                }
                sample = sample / max(1, Double(lanes.count)) * Double(env) * note.velocity * macroBoost

                // Per-voice filter with envelope modulation.
                if patch.filterType != 0 || patch.filterCutoff < 19000 {
                    out[idx] += filter.process(Float(sample))
                } else {
                    out[idx] += Float(sample)
                }
            }
        }

        var processed = out
        if patch.filterEnvAmount != 0 {
            // Global gentle tone shaping when env routes to cutoff.
            let shaped = VinnyDSP.Biquad.apply(patch.filterType == 1 ? .highpass : .lowpass,
                                               to: processed,
                                               cutoff: patch.filterCutoff * (1 + patch.filterEnvAmount * 0.5),
                                               q: patch.filterReso, sampleRate: sampleRate)
            processed = VinnyDSP.mix(processed, shaped, gainA: 0.3, gainB: 0.7)
        }
        processed = applyFX(patch.fx, to: processed, sampleRate: sampleRate, bpm: patch.bpm)
        processed = VinnyDSP.fadeEdges(processed, sampleRate: sampleRate)
        return VinnyDSP.normalize(processed, target: 0.92)
    }

    /// Run the modular FX rack in order (up to 24 slots).
    static func applyFX(_ chain: [FXSlot], to input: [Float], sampleRate: Int, bpm: Double = 120) -> [Float] {
        var x = input
        for slot in chain.prefix(24) where slot.enabled {
            switch slot.kind {
            case .reverb:
                x = VinnyDSP.reverb(x, roomSize: 0.15 + slot.p1 * 0.8, damping: slot.p2, mix: slot.mix, sampleRate: sampleRate)
            case .delay:
                let beatDiv = 0.25 + slot.p1 * 0.75
                x = VinnyDSP.delay(x, timeSec: 60.0 / max(bpm, 30) * beatDiv, feedback: slot.p2 * 0.85, mix: slot.mix, sampleRate: sampleRate, pingPong: slot.p3 > 0.6)
            case .chorus:
                x = VinnyDSP.chorus(x, rateHz: 0.1 + slot.p1 * 3, depthMs: 2 + slot.p2 * 12, mix: slot.mix, sampleRate: sampleRate)
            case .flanger:
                x = VinnyDSP.flanger(x, rateHz: 0.05 + slot.p1 * 2, depthMs: 1 + slot.p2 * 8, feedback: slot.p3, mix: slot.mix, sampleRate: sampleRate)
            case .distortion:
                x = VinnyDSP.distort(x, drive: slot.p1, mix: slot.mix, tone: slot.p2)
            case .bitcrusher:
                x = VinnyDSP.bitcrush(x, bits: 3 + slot.p1 * 12, downsample: 1 + slot.p2 * 12, mix: slot.mix)
            case .ringMod:
                x = VinnyDSP.ringMod(x, freqHz: 20 + slot.p1 * 900, mix: slot.mix, sampleRate: sampleRate)
            case .compressor:
                x = VinnyDSP.compress(x, threshold: 0.2 + slot.p1 * 0.6, ratio: 1 + slot.p2 * 11, attackMs: 1 + slot.p3 * 80, releaseMs: 120, sampleRate: sampleRate)
            case .eq:
                x = VinnyDSP.eq3(x, lowGain: 0.2 + slot.p1 * 1.8, midGain: 0.2 + slot.p2 * 1.8, highGain: 0.2 + slot.p3 * 1.8, sampleRate: sampleRate)
            case .widener:
                // Stereo is a final-stage concern: handled by renderWAV so the
                // mono chain never doubles its buffer mid-rack.
                break
            }
        }
        return x
    }

    /// Full pipeline: notes → mono render → FX rack → optional stereo width → WAV data.
    static func renderWAV(patch: VinnyPatch, notes: [VinnyDSP.VinnyNote], durationSec: Double, sampleRate: Int = VinnyDSP.defaultSampleRate) -> Data {
        var width = patch.stereoWidth
        for slot in patch.fx where slot.kind == .widener && slot.enabled {
            width = max(width, slot.p1)
        }
        let mono = render(patch: patch, notes: notes, durationSec: durationSec, sampleRate: sampleRate)
        if width > 0.05 {
            let stereo = VinnyDSP.toStereo(mono, width: width, sampleRate: sampleRate)
            return VinnyDSP.writeWAV(stereo, sampleRate: sampleRate, channels: 2)
        }
        return VinnyDSP.writeWAV(mono, sampleRate: sampleRate, channels: 1)
    }
}

// MARK: - Theory engine (scales, chords, progressions, melodies)

enum TheoryEngine {
    static let noteNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]

    static let scales: [String: [Int]] = [
        "major": [0, 2, 4, 5, 7, 9, 11],
        "minor": [0, 2, 3, 5, 7, 8, 10],
        "pentatonic": [0, 2, 4, 7, 9],
        "minor pentatonic": [0, 3, 5, 7, 10],
        "dorian": [0, 2, 3, 5, 7, 9, 10],
        "phrygian": [0, 1, 3, 5, 7, 8, 10],
        "lydian": [0, 2, 4, 6, 7, 9, 11],
        "mixolydian": [0, 2, 4, 5, 7, 9, 10],
        "harmonic minor": [0, 2, 3, 5, 7, 8, 11],
        "blues": [0, 3, 5, 6, 7, 10],
        "chromatic": Array(0...11)
    ]

    static var scaleNames: [String] { scales.keys.sorted() }

    static func rootMidi(_ key: String, octave: Int = 4) -> Int {
        let idx = noteNames.firstIndex(of: key) ?? 0
        return 12 * (octave + 1) + idx
    }

    /// Quantize any MIDI note into the global scale — the Universal Scale Guardian.
    static func quantize(_ midi: Int, key: String, scale: String) -> Int {
        let intervals = scales[scale] ?? scales["minor"]!
        let root = noteNames.firstIndex(of: key) ?? 0
        let pc = ((midi % 12) - root + 12) % 12
        if intervals.contains(pc) { return midi }
        // Snap to nearest in-scale pitch class.
        var best = midi, bestDist = 12
        for delta in -2...2 {
            let candidate = midi + delta
            let cpc = ((candidate % 12) - root + 12) % 12
            if intervals.contains(cpc), abs(delta) < bestDist {
                best = candidate; bestDist = abs(delta)
            }
        }
        return best
    }

    static func degreeToMidi(_ degree: Int, octave: Int, key: String, scale: String) -> Int {
        let intervals = scales[scale] ?? scales["minor"]!
        let oct = degree / intervals.count
        let step = intervals[((degree % intervals.count) + intervals.count) % intervals.count]
        return rootMidi(key, octave: octave + oct) + step
    }

    /// Chord generator with voicing styles (triads, 7ths, neo-soul 9ths, cinematic sus).
    static func chord(rootDegree: Int, key: String, scale: String, style: String = "triad", octave: Int = 4) -> [Int] {
        func deg(_ d: Int, _ oct: Int) -> Int { degreeToMidi(d, octave: oct, key: key, scale: scale) }
        switch style {
        case "seventh":
            return [deg(rootDegree, octave), deg(rootDegree + 2, octave), deg(rootDegree + 4, octave), deg(rootDegree + 6, octave)]
        case "neo-soul":
            return [deg(rootDegree, octave - 1), deg(rootDegree + 6, octave), deg(rootDegree + 2, octave), deg(rootDegree + 4, octave), deg(rootDegree + 1, octave + 1)]
        case "cinematic":
            return [deg(rootDegree, octave - 1), deg(rootDegree, octave), deg(rootDegree + 4, octave), deg(rootDegree + 1, octave + 1)]
        default:
            return [deg(rootDegree, octave), deg(rootDegree + 2, octave), deg(rootDegree + 4, octave)]
        }
    }

    /// Progression suggester — genre-aware degree sequences.
    static func progression(genre: String, seed: UInt64) -> [Int] {
        var rng = SeededRNG(seed)
        let bank: [[Int]]
        switch genre.lowercased() {
        case let g where g.contains("lo-fi") || g.contains("lofi") || g.contains("chill"):
            bank = [[0, 5, 3, 4], [1, 4, 5, 0], [0, 3, 4, 4]]
        case let g where g.contains("trap") || g.contains("drill"):
            bank = [[0, 0, 5, 6], [0, 3, 0, 5], [0, 6, 5, 6]]
        case let g where g.contains("techno") || g.contains("house") || g.contains("edm"):
            bank = [[0, 5, 6, 4], [0, 0, 3, 5], [1, 0, 4, 5]]
        case let g where g.contains("orchestral") || g.contains("cinematic") || g.contains("ambient"):
            bank = [[0, 4, 5, 3], [5, 3, 0, 4], [0, 5, 1, 4]]
        case let g where g.contains("drum") || g.contains("dnb"):
            bank = [[0, 6, 3, 5], [0, 5, 6, 5]]
        default:
            bank = [[0, 3, 4, 4], [0, 4, 5, 3], [1, 5, 6, 4]]
        }
        return bank[rng.nextInt(0..<bank.count)]
    }

    /// Melody generator with contour / tension / density control.
    static func melody(length: Int, key: String, scale: String, density: Double, contour: Double, seed: UInt64, octave: Int = 5) -> [Int] {
        var rng = SeededRNG(seed)
        let intervals = scales[scale] ?? scales["minor"]!
        var out: [Int] = []
        var degree = rng.nextInt(0..<intervals.count)
        for i in 0..<length {
            if rng.next01() > density { continue }
            let walk = rng.nextInt(-2...2)
            let tensionJump = rng.next01() < 0.12 ? rng.nextInt(-4...4) : 0
            degree = max(0, degree + Int(Double(walk) * (0.5 + contour)) + tensionJump)
            out.append(degreeToMidi(degree, octave: octave, key: key, scale: scale))
            _ = i
        }
        return out
    }
}

// MARK: - Genesis (AI sound grower: text/audio/hum → patch)

enum GenesisEngine {

    /// Text-to-Patch: natural language → fully editable synth patch.
    static func patch(fromText text: String, seed: UInt64? = nil) -> VinnyPatch {
        let t = text.lowercased()
        var rng = SeededRNG(seed ?? UInt64(abs(t.hashValue)))
        var p = VinnyPatch.default
        p.name = String(text.prefix(28)).isEmpty ? "Generated Patch" : String(text.prefix(28)).capitalized
        p.tags = t.split(separator: " ").map { String($0).trimmingCharacters(in: .punctuationCharacters) }.filter { $0.count > 2 }

        // Timbre keywords
        if t.contains("warm") || t.contains("analog") || t.contains("vintage") {
            p.osc[0].wave = .saw; p.osc[1] = OscConfig(wave: .triangle, level: 0.4, harmonics: [1, 0.2, 0.05])
            p.filterCutoff = 3200; p.unisonVoices = 3; p.unisonDetune = 0.35; p.moodOrganic += 0.4
        }
        if t.contains("metallic") || t.contains("fm") || t.contains("bell") {
            p.fmAmount = 0.6; p.osc[0].wave = .sine; p.osc[1] = OscConfig(wave: .sine, octave: 1, level: 0.5)
            p.osc[0].harmonics = [1, 0.6, 0.4, 0.3, 0.2]
        }
        if t.contains("bass") || t.contains("sub") || t.contains("808") {
            p.osc[0].octave = -1; p.osc[0].wave = .saw; p.subLevel = 0.7
            p.env = VinnyDSP.ADSR(attack: 0.003, decay: 0.25, sustain: 0.6, release: 0.1)
            p.filterCutoff = 1400
        }
        if t.contains("pad") || t.contains("lush") || t.contains("ambient") || t.contains("cinematic") {
            p.env = VinnyDSP.ADSR(attack: 0.4, decay: 0.3, sustain: 0.85, release: 1.2)
            p.unisonVoices = 6; p.unisonDetune = 0.5; p.stereoWidth = 0.7
            p.fx.append(FXSlot(kind: .reverb, mix: 0.5, p1: 0.8, p2: 0.4))
            p.genre = "Ambient"
        }
        if t.contains("pluck") || t.contains("keys") || t.contains("mallet") {
            p.env = VinnyDSP.ADSR(attack: 0.002, decay: 0.18, sustain: 0.25, release: 0.2)
        }
        if t.contains("lead") || t.contains("solo") {
            p.osc[0].wave = .square; p.unisonVoices = 2; p.unisonDetune = 0.2
            p.fx.append(FXSlot(kind: .delay, mix: 0.3, p1: 0.6, p2: 0.4))
        }
        if t.contains("grit") || t.contains("dirty") || t.contains("aggressive") || t.contains("distort") {
            p.fx.append(FXSlot(kind: .distortion, mix: 0.45, p1: 0.5))
            p.moodTense += 0.4
        }
        if t.contains("lo-fi") || t.contains("lofi") || t.contains("dusty") || t.contains("tape") {
            p.fx.append(FXSlot(kind: .bitcrusher, mix: 0.25, p1: 0.45, p2: 0.2))
            p.filterCutoff = 4200; p.genre = "Lo-Fi"; p.scale = "minor pentatonic"
            p.bpm = 82
        }
        if t.contains("dark") { p.moodDark += 0.6; p.filterCutoff *= 0.55; p.scale = "phrygian" }
        if t.contains("bright") || t.contains("sparkle") || t.contains("air") {
            p.moodDark -= 0.5; p.filterCutoff = min(p.filterCutoff * 1.8, 16000)
            p.osc[0].harmonics = [1, 0.5, 0.35, 0.25, 0.15, 0.1]
        }
        if t.contains("tense") || t.contains("anxious") { p.moodTense += 0.6; p.rmAmount = 0.25 }
        if t.contains("calm") || t.contains("soft") || t.contains("gentle") { p.moodTense -= 0.5; p.env.attack = max(p.env.attack, 0.15) }
        if t.contains("wide") || t.contains("stereo") { p.stereoWidth = 0.85; p.fx.append(FXSlot(kind: .chorus, mix: 0.35)) }
        if t.contains("reverb") || t.contains("space") || t.contains("cathedral") {
            p.fx.append(FXSlot(kind: .reverb, mix: 0.55, p1: 0.85, p2: 0.3))
        }
        if t.contains("glitch") || t.contains("stutter") { p.fx.append(FXSlot(kind: .bitcrusher, mix: 0.3, p1: 0.3, p2: 0.6)); p.moodTense += 0.3 }
        if t.contains("techno") { p.genre = "Techno"; p.bpm = 128; p.scale = "minor" }
        if t.contains("trap") { p.genre = "Trap"; p.bpm = 140; p.scale = "minor" }
        if t.contains("house") { p.genre = "House"; p.bpm = 124; p.scale = "minor" }
        if t.contains("drum") || t.contains("dnb") { p.genre = "Drum & Bass"; p.bpm = 174; p.scale = "minor" }
        if t.contains("orchestral") { p.genre = "Orchestral"; p.moodOrganic += 0.6; p.scale = "major" }
        if t.contains("happy") || t.contains("uplifting") { p.scale = "major"; p.moodDark -= 0.4 }
        if t.contains("sad") || t.contains("emotional") { p.scale = "minor"; p.moodDark += 0.3 }

        // "slow it down" / tempo words
        if t.contains("slow") { p.bpm = min(p.bpm, 85) }
        if t.contains("fast") || t.contains("uptempo") { p.bpm = max(p.bpm, 140) }
        if let bpmMatch = t.range(of: #"\b(\d{2,3})\s?bpm\b"#, options: .regularExpression) {
            let digits = t[bpmMatch].filter { $0.isNumber }
            if let bpm = Double(digits) { p.bpm = min(max(bpm, 50), 220) }
        }

        // Seeded variety so every generation is unique but reproducible.
        p.osc[0].harmonics = p.osc[0].harmonics.map { Float(max(0.02, Double($0) * (0.8 + rng.next01() * 0.5))) }
        if p.fx.isEmpty { p.fx = [FXSlot(kind: .reverb, mix: 0.3)] }
        p.tags.append(contentsOf: [p.genre.lowercased(), p.scale])
        return p
    }

    /// Audio-to-Patch reverse engineering: fingerprint the audio, rebuild a patch
    /// whose parameters recreate its sonic character.
    static func patch(fromAudio data: Data, sampleRate: Int = VinnyDSP.defaultSampleRate) -> VinnyPatch? {
        guard let pcm = VinnyDSP.readWAV(data) else { return nil }
        let x = pcm.mono
        guard x.count > 2048 else { return nil }
        let centroid = VinnyDSP.spectralCentroid(x, sampleRate: pcm.sampleRate)
        let bands = VinnyDSP.bandEnergies(x, sampleRate: pcm.sampleRate)
        let keyResult = VinnyDSP.detectKey(x, sampleRate: pcm.sampleRate)
        let bpm = VinnyDSP.estimateBPM(x, sampleRate: pcm.sampleRate)
        let level = VinnyDSP.rms(x)

        var p = VinnyPatch.default
        p.name = "Reverse-Engineered Patch"
        p.filterCutoff = min(max(centroid * 2.2, 300), 16000)
        p.bpm = bpm
        p.key = keyResult.key
        p.scale = keyResult.scale
        p.subLevel = bands.0 > 0.5 ? 0.6 : 0.15
        p.osc[0].wave = centroid > 2500 ? .saw : centroid > 1200 ? .square : .triangle
        p.osc[0].harmonics = [1, Float(min(bands.1 * 1.4, 0.9)), Float(min(bands.2 * 1.2, 0.7)), Float(min(bands.2 * 0.7, 0.5))]
        p.moodDark = centroid < 1200 ? 0.5 : -0.3
        p.moodOrganic = bands.0 > 0.4 ? 0.4 : 0
        p.fx = [FXSlot(kind: .reverb, mix: 0.35, p1: 0.6)]
        if level > 0.25 { p.fx.append(FXSlot(kind: .compressor, mix: 0.5, p1: 0.4, p2: 0.5)) }
        p.tags = ["reverse-engineered", p.genre.lowercased(), keyResult.key + " " + keyResult.scale]
        p.dna = VinnyDSP.fingerprint(x, sampleRate: pcm.sampleRate)
        return p
    }

    /// Mutation tree: 8 genetic variations of a patch.
    static func mutations(of base: VinnyPatch, count: Int = 8) -> [VinnyPatch] {
        var out: [VinnyPatch] = []
        for i in 0..<count {
            var rng = SeededRNG(UInt64(i &+ 1) &* 7919 &+ UInt64(abs(base.name.hashValue) % 1000))
            var p = base
            p.id = UUID()
            p.version = base.version + 1
            p.parentName = base.name
            p.name = "\(base.name) M\(i + 1)"
            p.filterCutoff = min(max(base.filterCutoff * (0.6 + rng.next01() * 0.9), 150), 18000)
            p.fmAmount = min(max(base.fmAmount + (rng.next01() - 0.5) * 0.5, 0), 1)
            p.rmAmount = min(max(base.rmAmount + (rng.next01() - 0.5) * 0.3, 0), 1)
            p.unisonVoices = max(1, min(16, base.unisonVoices + rng.nextInt(-2...3)))
            p.stereoWidth = min(max(base.stereoWidth + (rng.next01() - 0.5) * 0.5, 0), 1)
            p.env.attack = max(0.001, base.env.attack * (0.5 + rng.next01() * 1.6))
            p.env.release = max(0.02, base.env.release * (0.5 + rng.next01() * 1.8))
            p.osc[0].harmonics = base.osc[0].harmonics.map { Float(min(max(Double($0) * (0.6 + rng.next01() * 0.9), 0.01), 1)) }
            if rng.next01() > 0.6, let kind = FXKind.allCases.randomElement() {
                p.fx.append(FXSlot(kind: kind, mix: 0.2 + rng.next01() * 0.3))
            }
            out.append(p)
        }
        return out
    }

    /// Sound Breeding: two presets birth a child inheriting traits from both.
    static func breed(_ a: VinnyPatch, _ b: VinnyPatch, seed: UInt64 = 5) -> VinnyPatch {
        var rng = SeededRNG(seed)
        var child = VinnyPatch.default
        child.name = "\(a.name) × \(b.name)"
        child.parentName = "\(a.name) + \(b.name)"
        child.genre = rng.next01() > 0.5 ? a.genre : b.genre
        child.moodDark = (a.moodDark + b.moodDark) / 2
        child.moodTense = (a.moodTense + b.moodTense) / 2
        child.moodOrganic = (a.moodOrganic + b.moodOrganic) / 2
        child.osc = rng.next01() > 0.5 ? a.osc : b.osc
        if rng.next01() > 0.5, child.osc.count > 1, b.osc.count > 1 {
            child.osc[1] = b.osc[1]
        }
        child.filterCutoff = (a.filterCutoff + b.filterCutoff) / 2
        child.filterReso = (a.filterReso + b.filterReso) / 2
        child.env = rng.next01() > 0.5 ? a.env : b.env
        child.unisonVoices = (a.unisonVoices + b.unisonVoices) / 2
        child.stereoWidth = (a.stereoWidth + b.stereoWidth) / 2
        child.fmAmount = (a.fmAmount + b.fmAmount) / 2
        child.fx = Array((a.fx + b.fx).prefix(6))
        child.bpm = (a.bpm + b.bpm) / 2
        child.key = rng.next01() > 0.5 ? a.key : b.key
        child.scale = rng.next01() > 0.5 ? a.scale : b.scale
        child.tags = Array(Set(a.tags + b.tags)).prefix(8).map { $0 }
        return child
    }

    /// Genre Migrator: morph a patch toward a target genre's signature.
    static func morph(_ p: VinnyPatch, towardGenre genre: String, amount: Double) -> VinnyPatch {
        var out = p
        let t = min(max(amount, 0), 1)
        func lerp(_ a: Double, _ b: Double) -> Double { a + (b - a) * t }
        var target = VinnyPatch.default
        switch genre.lowercased() {
        case let g where g.contains("lo-fi"):
            target.filterCutoff = 3600; target.bpm = 80; target.scale = "minor pentatonic"
            target.fx = [FXSlot(kind: .bitcrusher, mix: 0.25, p1: 0.4), FXSlot(kind: .reverb, mix: 0.3)]
            target.genre = "Lo-Fi"
        case let g where g.contains("techno"):
            target.filterCutoff = 7000; target.bpm = 130; target.scale = "minor"
            target.fmAmount = 0.3; target.moodDark = 0.5; target.moodTense = 0.4
            target.fx = [FXSlot(kind: .delay, mix: 0.25, p1: 0.7), FXSlot(kind: .distortion, mix: 0.2, p1: 0.3)]
            target.genre = "Techno"
        case let g where g.contains("orchestral") || g.contains("cinematic"):
            target.filterCutoff = 9000; target.bpm = 100; target.scale = "major"
            target.moodOrganic = 0.7; target.unisonVoices = 8; target.stereoWidth = 0.8
            target.env = VinnyDSP.ADSR(attack: 0.25, decay: 0.3, sustain: 0.9, release: 1.4)
            target.fx = [FXSlot(kind: .reverb, mix: 0.55, p1: 0.9, p2: 0.35)]
            target.genre = "Orchestral"
        case let g where g.contains("trap"):
            target.filterCutoff = 2400; target.bpm = 140; target.subLevel = 0.8; target.scale = "minor"
            target.fx = [FXSlot(kind: .distortion, mix: 0.3, p1: 0.4)]
            target.genre = "Trap"
        default:
            target.genre = genre
        }
        out.filterCutoff = lerp(p.filterCutoff, target.filterCutoff)
        out.bpm = lerp(p.bpm, target.bpm)
        out.subLevel = lerp(p.subLevel, target.subLevel)
        out.fmAmount = lerp(p.fmAmount, target.fmAmount)
        out.moodDark = lerp(p.moodDark, target.moodDark)
        out.moodTense = lerp(p.moodTense, target.moodTense)
        out.moodOrganic = lerp(p.moodOrganic, target.moodOrganic)
        out.unisonVoices = Int(lerp(Double(p.unisonVoices), Double(target.unisonVoices)).rounded())
        out.stereoWidth = lerp(p.stereoWidth, target.stereoWidth)
        if t > 0.4 { out.scale = target.scale; out.genre = target.genre; out.fx = target.fx }
        out.name = "\(p.name) → \(target.genre)"
        out.version = p.version + 1
        out.parentName = p.name
        return out
    }
}
