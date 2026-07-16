import Foundation
import Combine

// MARK: - Loop Factory (one-shot loops, variations, full arrangements)

struct LoopResult {
    let wav: Data
    let midi: Data
    let notes: [VinnyDSP.VinnyNote]
    let stems: [String: Data]     // drums / bass / chords / lead as separate WAVs
    let bpm: Double
    let key: String
    let scale: String
    let genre: String
    let durationSec: Double
}

enum LoopFactory {

    /// Generate a complete, musically-coherent loop from a patch: synthesized drums,
    /// scale-locked bassline, chord progression and a generated melody — humanized.
    static func makeLoop(patch: VinnyPatch, bars: Int = 4, seed: UInt64 = 42, variation: Int = 0, swing: Double = 0.0) -> LoopResult {
        let sampleRate = VinnyDSP.defaultSampleRate
        var rng = SeededRNG(seed &+ UInt64(variation &* 131))
        let bpm = patch.bpm
        let beatSec = 60.0 / bpm
        let barSec = beatSec * 4
        let duration = Double(bars) * barSec
        let key = patch.key, scale = patch.scale
        let genre = patch.genre

        // 16-step drum patterns per genre.
        let g = genre.lowercased()
        let kickPat: [Bool]
        let snarePat: [Bool]
        let hatPat: [Bool]
        let clapPat: [Bool]
        if g.contains("techno") || g.contains("house") {
            kickPat = [true,false,false,false, true,false,false,false, true,false,false,false, true,false,false,false]
            snarePat = [false,false,false,false, true,false,false,false, false,false,false,false, true,false,false,false]
            hatPat = [false,false,true,false, false,false,true,false, false,false,true,false, false,false,true,true]
            clapPat = [false,false,false,false, false,false,false,false, false,false,false,false, false,false,false,false]
        } else if g.contains("trap") || g.contains("drill") {
            kickPat = [true,false,false,false, false,false,true,false, false,false,true,false, false,false,false,false]
            snarePat = [false,false,false,false, true,false,false,false, false,false,false,false, true,false,false,false]
            hatPat = [true,true,true,true, true,true,true,true, true,true,true,true, true,true,true,false]
            clapPat = [false,false,false,false, true,false,false,false, false,false,false,false, true,false,false,false]
        } else if g.contains("drum") || g.contains("dnb") {
            kickPat = [true,false,false,false, false,false,false,false, false,false,true,false, false,false,false,false]
            snarePat = [false,false,false,false, true,false,false,false, false,false,false,false, true,false,true,false]
            hatPat = [true,false,true,false, true,false,true,false, true,false,true,false, true,false,true,false]
            clapPat = [false,false,false,false, false,false,false,false, false,false,false,false, false,false,false,false]
        } else if g.contains("lo-fi") || g.contains("chill") {
            kickPat = [true,false,false,false, false,false,true,false, false,false,false,false, true,false,false,false]
            snarePat = [false,false,false,false, true,false,false,false, false,false,false,false, true,false,false,true]
            hatPat = [true,false,true,true, true,false,true,false, true,true,false,true, true,false,true,false]
            clapPat = [false,false,false,false, false,false,false,false, false,false,false,false, false,false,false,false]
        } else {
            kickPat = [true,false,false,false, false,false,false,false, true,false,false,false, false,false,false,false]
            snarePat = [false,false,false,false, true,false,false,false, false,false,false,false, true,false,false,false]
            hatPat = [true,false,true,false, true,false,true,false, true,false,true,false, true,false,true,false]
            clapPat = [false,false,false,false, false,false,false,false, false,false,false,false, false,false,false,false]
        }

        // Render drums.
        let totalSamples = Int(duration * Double(sampleRate)) + sampleRate
        var drums = [Float](repeating: 0, count: totalSamples)
        let kickHit = VinnyDSP.kick(freq: g.contains("trap") ? 48 : 55, sampleRate: sampleRate)
        let snareHit = VinnyDSP.snare(sampleRate: sampleRate)
        let hatHit = VinnyDSP.hat(sampleRate: sampleRate)
        let openHat = VinnyDSP.hat(open: true, sampleRate: sampleRate)
        let clapHit = VinnyDSP.clap(sampleRate: sampleRate)
        var drumNotes: [VinnyDSP.VinnyNote] = []
        let stepSec = barSec / 16
        for bar in 0..<bars {
            for step in 0..<16 {
                var t = Double(bar) * barSec + Double(step) * stepSec
                // Swing: delay off-beat 16ths.
                if step % 2 == 1 { t += stepSec * swing * 0.6 }
                // Humanize timing (never before the loop start — a negative time would
                // index the drum buffer out of bounds).
                t = max(0, t + (rng.next01() - 0.5) * 0.006)
                let idx = (bar * 16 + step) % 16
                if kickPat[idx] {
                    drums = VinnyDSP.place(on: drums, hit: kickHit, atSec: t, gain: 0.95, sampleRate: sampleRate)
                    drumNotes.append(VinnyDSP.VinnyNote(midi: 36, start: t, duration: 0.25, velocity: 0.95, lane: 9, drum: 36))
                }
                if snarePat[idx] {
                    drums = VinnyDSP.place(on: drums, hit: snareHit, atSec: t, gain: 0.8, sampleRate: sampleRate)
                    drumNotes.append(VinnyDSP.VinnyNote(midi: 38, start: t, duration: 0.25, velocity: 0.8, lane: 9, drum: 38))
                }
                if clapPat[idx] {
                    drums = VinnyDSP.place(on: drums, hit: clapHit, atSec: t, gain: 0.7, sampleRate: sampleRate)
                    drumNotes.append(VinnyDSP.VinnyNote(midi: 39, start: t, duration: 0.25, velocity: 0.7, lane: 9, drum: 39))
                }
                if hatPat[idx] {
                    let isOpen = idx == 14 && g.contains("techno")
                    drums = VinnyDSP.place(on: drums, hit: isOpen ? openHat : hatHit, atSec: t, gain: Float(0.35 + rng.next01() * 0.2), sampleRate: sampleRate)
                    drumNotes.append(VinnyDSP.VinnyNote(midi: 42, start: t, duration: 0.1, velocity: 0.5, lane: 9, drum: 42))
                }
            }
        }

        // Harmony: progression → bass + chords + lead melody.
        let degrees = TheoryEngine.progression(genre: genre, seed: seed)
        var bassNotes: [VinnyDSP.VinnyNote] = []
        var chordNotes: [VinnyDSP.VinnyNote] = []
        var leadNotes: [VinnyDSP.VinnyNote] = []
        let chordStyle = g.contains("lo-fi") ? "neo-soul" : g.contains("orchestral") || g.contains("cinematic") ? "cinematic" : g.contains("techno") ? "triad" : "seventh"

        for bar in 0..<bars {
            let degree = degrees[bar % degrees.count]
            let barStart = Double(bar) * barSec
            // Bass: root on 1 & 3 (or 8ths for techno/dnb).
            let bassRoot = TheoryEngine.degreeToMidi(degree, octave: 2, key: key, scale: scale)
            let bassRhythm: [Double] = g.contains("techno") || g.contains("dnb") ? [0, 0.5, 1, 1.5, 2, 2.5, 3, 3.5] : [0, 2]
            for beat in bassRhythm {
                var t = barStart + beat * beatSec
                t = max(0, t + (rng.next01() - 0.5) * 0.005)
                bassNotes.append(VinnyDSP.VinnyNote(midi: bassRoot, start: t, duration: beatSec * 0.9, velocity: 0.75 + rng.next01() * 0.1, lane: 1))
            }
            // Chords: sustained, occasionally syncopated.
            let chordTones = TheoryEngine.chord(rootDegree: degree, key: key, scale: scale, style: chordStyle, octave: 4)
            let chordStart = barStart + (rng.next01() > 0.7 ? beatSec * 0.5 : 0)
            for tone in chordTones {
                chordNotes.append(VinnyDSP.VinnyNote(midi: tone, start: chordStart, duration: barSec * 0.95, velocity: 0.5 + rng.next01() * 0.12, lane: 2))
            }
            // Lead: generated melody, denser in later bars.
            let density = min(0.35 + Double(bar) * 0.1 + Double(variation) * 0.06, 0.85)
            let melody = TheoryEngine.melody(length: 8, key: key, scale: scale, density: density, contour: patch.moodTense * 0.5 + 0.6, seed: seed &+ UInt64(bar &* 17), octave: 5)
            for (i, midi) in melody.enumerated() {
                var t = barStart + Double(i) * beatSec * 0.5
                if i % 2 == 1 { t += stepSec * swing * 0.6 }
                leadNotes.append(VinnyDSP.VinnyNote(midi: midi, start: t, duration: beatSec * 0.45, velocity: 0.55 + rng.next01() * 0.2, lane: 3))
            }
        }

        // Scale-lock everything (Universal Scale Guardian).
        bassNotes = bassNotes.map { var n = $0; n.midi = TheoryEngine.quantize(n.midi, key: key, scale: scale); return n }
        chordNotes = chordNotes.map { var n = $0; n.midi = TheoryEngine.quantize(n.midi, key: key, scale: scale); return n }
        leadNotes = leadNotes.map { var n = $0; n.midi = TheoryEngine.quantize(n.midi, key: key, scale: scale); return n }

        // Render stems separately so the STEMS ZIP export is real.
        func renderStem(_ notes: [VinnyDSP.VinnyNote], tweaking: (inout VinnyPatch) -> Void) -> [Float] {
            var p = patch
            tweaking(&p)
            return VinnyRenderer.render(patch: p, notes: notes, durationSec: duration + 0.5, sampleRate: sampleRate)
        }
        let bassPCM = renderStem(bassNotes) { $0.filterCutoff = min($0.filterCutoff, 900); $0.subLevel = max($0.subLevel, 0.5); $0.fx = [] }
        let chordPCM = renderStem(chordNotes) { $0.env.attack = max($0.env.attack, 0.08) }
        let leadPCM = renderStem(leadNotes) { $0.unisonVoices = max(1, $0.unisonVoices / 2) }

        // Adaptive mix: duck conflicting bands so layers don't mask each other.
        var mixed = VinnyDSP.mix(drums, bassPCM, gainA: 1.0, gainB: 0.85)
        mixed = VinnyDSP.mix(mixed, chordPCM, gainA: 1.0, gainB: 0.7)
        mixed = VinnyDSP.mix(mixed, leadPCM, gainA: 1.0, gainB: 0.8)
        mixed = VinnyDSP.compress(mixed, threshold: 0.55, ratio: 3, attackMs: 8, releaseMs: 140, sampleRate: sampleRate)
        mixed = VinnyDSP.fadeEdges(VinnyDSP.normalize(mixed, target: 0.9), sampleRate: sampleRate)

        let allNotes = drumNotes + bassNotes + chordNotes + leadNotes
        let stereo = patch.stereoWidth > 0.05 ? VinnyDSP.toStereo(mixed, width: patch.stereoWidth, sampleRate: sampleRate) : mixed
        let wav = VinnyDSP.writeWAV(stereo, sampleRate: sampleRate, channels: patch.stereoWidth > 0.05 ? 2 : 1)
        let midi = VinnyDSP.midiFile(notes: allNotes, bpm: Int(bpm.rounded()))
        let stems: [String: Data] = [
            "drums": VinnyDSP.writeWAV(VinnyDSP.normalize(drums, target: 0.9), sampleRate: sampleRate),
            "bass": VinnyDSP.writeWAV(VinnyDSP.normalize(bassPCM, target: 0.9), sampleRate: sampleRate),
            "chords": VinnyDSP.writeWAV(VinnyDSP.normalize(chordPCM, target: 0.9), sampleRate: sampleRate),
            "lead": VinnyDSP.writeWAV(VinnyDSP.normalize(leadPCM, target: 0.9), sampleRate: sampleRate)
        ]
        return LoopResult(wav: wav, midi: midi, notes: allNotes, stems: stems,
                          bpm: bpm, key: key, scale: scale, genre: genre, durationSec: duration)
    }

    /// Rhythmic reshaper: re-groove a loop's drums non-destructively.
    static func regroove(_ result: LoopResult, swing: Double, patch: VinnyPatch) -> LoopResult {
        makeLoop(patch: patch, bars: Int((result.durationSec * result.bpm / 240).rounded()), seed: UInt64(result.notes.count &* 31 &+ 7), variation: Int((swing * 10).rounded()), swing: swing)
    }
}

// MARK: - Vinny assistant (contextual sound-design coach + voice-style commands)

enum VinnyAssistant {

    /// Coaching suggestions based on the current patch state.
    static func suggest(for p: VinnyPatch) -> [String] {
        var tips: [String] = []
        if p.filterCutoff > 12000 && p.moodDark > 0.3 {
            tips.append("Your patch is bright but the mood is dark — close the filter toward ~2 kHz or lower the mood slider.")
        }
        if p.fx.isEmpty { tips.append("No FX loaded. A little reverb (room 60%, mix 30%) adds instant depth.") }
        if p.unisonVoices == 1 && p.genre != "Lo-Fi" { tips.append("Try 3–5 unison voices with 30% detune for width without chorus.") }
        if p.subLevel > 0.5 && p.filterCutoff > 6000 { tips.append("Heavy sub + open filter can mask your kick. High-pass the patch around 120 Hz or lower the sub.") }
        if p.env.attack < 0.01 && p.genre == "Ambient" { tips.append("Ambient patches breathe with slower attacks — try 0.3–0.6s.") }
        if p.fmAmount > 0.5 && p.rmAmount > 0.3 { tips.append("FM + ring mod together can get harsh fast. Pick one as the character, keep the other subtle.") }
        if p.fx.filter({ $0.kind == .reverb }).count > 2 { tips.append("Stacked reverbs blur transients. Use one big space and one short room at most.") }
        if tips.isEmpty { tips.append("Solid patch. Breed it with another preset in HYBRIDIZER to discover a hybrid, or grow 8 mutations in GENESIS.") }
        return tips
    }

    /// Voice-command style sound design: "make it darker, add grit, slow it down".
    static func apply(command: String, to patch: VinnyPatch) -> (VinnyPatch, String) {
        let c = command.lowercased()
        var p = patch
        var did: [String] = []
        func note(_ s: String) { did.append(s) }

        if c.contains("darker") { p.filterCutoff = max(p.filterCutoff * 0.65, 200); p.moodDark = min(p.moodDark + 0.3, 1); note("closed the filter, raised dark mood") }
        if c.contains("brighter") { p.filterCutoff = min(p.filterCutoff * 1.5, 18000); p.moodDark = max(p.moodDark - 0.3, -1); note("opened the filter") }
        if c.contains("grit") || c.contains("dirt") || c.contains("crunch") {
            if let i = p.fx.firstIndex(where: { $0.kind == .distortion }) { p.fx[i].p1 = min(p.fx[i].p1 + 0.2, 1); p.fx[i].mix = min(p.fx[i].mix + 0.15, 0.8) }
            else { p.fx.append(FXSlot(kind: .distortion, mix: 0.35, p1: 0.45)) }
            note("added drive")
        }
        if c.contains("slow") { p.bpm = max(p.bpm - 10, 50); note("slowed to \(Int(p.bpm)) BPM") }
        if c.contains("faster") || c.contains("speed up") { p.bpm = min(p.bpm + 10, 220); note("sped to \(Int(p.bpm)) BPM") }
        if c.contains("wider") || c.contains("stereo") { p.stereoWidth = min(p.stereoWidth + 0.25, 1); p.unisonVoices = min(p.unisonVoices + 1, 16); note("widened the stereo field") }
        if c.contains("narrow") || c.contains("mono") { p.stereoWidth = max(p.stereoWidth - 0.3, 0); note("narrowed the image") }
        if c.contains("more reverb") || c.contains("bigger space") {
            if let i = p.fx.firstIndex(where: { $0.kind == .reverb }) { p.fx[i].mix = min(p.fx[i].mix + 0.15, 0.85); p.fx[i].p1 = min(p.fx[i].p1 + 0.15, 1) }
            else { p.fx.append(FXSlot(kind: .reverb, mix: 0.45, p1: 0.7)) }
            note("expanded the space")
        }
        if c.contains("less reverb") || c.contains("drier") {
            for i in p.fx.indices where p.fx[i].kind == .reverb { p.fx[i].mix = max(p.fx[i].mix - 0.2, 0) }
            note("pulled the reverb back")
        }
        if c.contains("punch") || c.contains("tighter") { p.env.attack = max(p.env.attack * 0.5, 0.001); p.env.sustain = min(p.env.sustain + 0.1, 1); note("tightened the envelope") }
        if c.contains("softer") || c.contains("gentler") { p.env.attack = min(p.env.attack * 2 + 0.05, 1.5); note("softened the attack") }
        if c.contains("randomize") || c.contains("surprise") {
            var rng = SeededRNG(UInt64(Date().timeIntervalSince1970))
            p.filterCutoff = 300 + rng.next01() * 9000
            p.fmAmount = rng.next01() * 0.7
            p.unisonVoices = rng.nextInt(1...8)
            p.stereoWidth = rng.next01()
            p.osc[0].harmonics = (0..<6).map { _ in Float(rng.next01()) }
            note("rolled the dice on the core engine")
        }
        if did.isEmpty {
            return (p, "Try: \"make it darker\", \"add grit\", \"slow it down\", \"wider\", \"more reverb\", \"punchier\", or \"randomize\".")
        }
        p.version += 1
        return (p, "Done — \(did.joined(separator: ", ")).")
    }
}

// MARK: - Vault store (presets, fingerprints, scenes, time machine)

@MainActor
final class VinnyStore: ObservableObject {
    static let shared = VinnyStore()

    @Published private(set) var presets: [VinnyPatch] = []
    @Published private(set) var fingerprints: [VinnyFingerprint] = []
    @Published var scenes: [VinnyPatch?] = Array(repeating: nil, count: 16)
    @Published private(set) var timeMachine: [VinnyPatch] = []

    struct VinnyFingerprint: Codable, Identifiable {
        var id = UUID()
        var name: String
        var vector: [Double]
        var createdAt = Date()
    }

    private init() {
        presets = read([VinnyPatch].self, "presets.json") ?? []
        fingerprints = read([VinnyFingerprint].self, "fingerprints.json") ?? []
        timeMachine = read([VinnyPatch].self, "timemachine.json") ?? []
        if let savedScenes = read([VinnyPatch?].self, "scenes.json"), savedScenes.count == 16 {
            scenes = savedScenes
        }
        if presets.isEmpty { installFactoryPresets() }
    }

    private var dir: URL {
        let d = FileStore.shared.root.appendingPathComponent("Vinny", isDirectory: true)
        try? FileStore.shared.fm.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }
    private func read<T: Decodable>(_ t: T.Type, _ name: String) -> T? { FileStore.shared.read(t, from: name, in: dir) }
    private func write<T: Encodable>(_ v: T, _ name: String) { FileStore.shared.write(v, to: name, in: dir) }

    func savePreset(_ p: VinnyPatch) {
        var copy = p
        if let i = presets.firstIndex(where: { $0.name == p.name }) {
            copy.version = presets[i].version + 1
            presets[i] = copy
        } else {
            presets.insert(copy, at: 0)
        }
        write(presets, "presets.json")
        snapshot(copy)
    }

    func deletePreset(_ p: VinnyPatch) {
        presets.removeAll { $0.id == p.id }
        write(presets, "presets.json")
    }

    /// Time Machine: every saved state is recoverable.
    func snapshot(_ p: VinnyPatch) {
        timeMachine.insert(p, at: 0)
        if timeMachine.count > 60 { timeMachine.removeLast(timeMachine.count - 60) }
        write(timeMachine, "timemachine.json")
    }

    func saveScene(_ p: VinnyPatch?, at index: Int) {
        guard scenes.indices.contains(index) else { return }
        scenes[index] = p
        write(scenes, "scenes.json")
    }

    // MARK: Fingerprint library (Earprint recall + preset match)

    func saveFingerprint(name: String, vector: [Double]) {
        fingerprints.insert(VinnyFingerprint(name: name, vector: vector), at: 0)
        if fingerprints.count > 100 { fingerprints.removeLast(fingerprints.count - 100) }
        write(fingerprints, "fingerprints.json")
    }

    /// "This kick sounds like…" — nearest saved fingerprints + presets by sonic DNA.
    func closest(to vector: [Double], limit: Int = 5) -> [(name: String, distance: Double)] {
        var scored: [(String, Double)] = fingerprints.map { ($0.name, VinnyDSP.fingerprintDistance(vector, $0.vector)) }
        scored += presets.compactMap { p in p.dna.isEmpty ? nil : (p.name, VinnyDSP.fingerprintDistance(vector, p.dna)) }
        return scored.sorted { $0.1 < $1.1 }.prefix(limit).map { ($0.0, $0.1) }
    }

    /// Smart browser: search by text, tag, mood, genre or similarity vector.
    func search(_ query: String, similarityTo vector: [Double]? = nil) -> [VinnyPatch] {
        let q = query.lowercased().trimmingCharacters(in: .whitespaces)
        var result = presets
        if !q.isEmpty {
            result = result.filter {
                $0.name.lowercased().contains(q) || $0.genre.lowercased().contains(q) ||
                $0.tags.contains { $0.lowercased().contains(q) } || $0.scale.contains(q) || $0.key.lowercased() == q
            }
        }
        if let v = vector {
            result = result.sorted { VinnyDSP.fingerprintDistance(v, $0.dna) < VinnyDSP.fingerprintDistance(v, $1.dna) }
        }
        return result
    }

    // MARK: Factory presets

    private func installFactoryPresets() {
        let seeds: [(String, UInt64)] = [
            ("warm analog bass with soft drive", 101),
            ("dusty lo-fi keys with tape wobble", 202),
            ("lush cinematic pad, wide and calm", 303),
            ("aggressive trap 808 sub, dark", 404),
            ("dark techno rumble lead, metallic", 505),
            ("bright glass bell pluck, sparkling", 606),
            ("warm neo-soul electric piano, gentle", 707),
            ("tense phrygian texture, metallic tail", 808)
        ]
        presets = seeds.map { GenesisEngine.patch(fromText: $0.0, seed: $0.1) }
        write(presets, "presets.json")
    }
}
