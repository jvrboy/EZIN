import Foundation

/// VINNY DSP core — the Unified Sound Intelligence Engine's audio brain.
/// Everything is pure, deterministic Swift: oscillators, wavetables, filters, FX,
/// granular, time-warping, spectral fusion and audio analysis. No network, no mocks —
/// real PCM in, real PCM out, rendered to standard 16-bit WAV.
enum VinnyDSP {

    static let defaultSampleRate = 44100

    // MARK: - Note model

    struct VinnyNote: Codable, Equatable {
        var midi: Int          // 0...127 (60 = C4)
        var start: Double      // seconds
        var duration: Double   // seconds
        var velocity: Double   // 0...1
        var lane: Int          // 0 lead · 1 bass · 2 chords · 3 arp · 9 drums
        var drum: Int = 0      // GM drum note when lane == 9

        var frequency: Double { 440.0 * pow(2.0, Double(midi - 69) / 12.0) }
    }

    // MARK: - WAV I/O (16-bit PCM, mono or stereo)

    struct PCM {
        var samples: [Float]   // interleaved when channels == 2
        var channels: Int
        var sampleRate: Int
        var frames: Int { samples.count / max(channels, 1) }
        var mono: [Float] {
            guard channels == 2 else { return samples }
            var out = [Float](); out.reserveCapacity(frames)
            for i in 0..<frames { out.append((samples[2 * i] + samples[2 * i + 1]) * 0.5) }
            return out
        }
    }

    static func writeWAV(_ samples: [Float], sampleRate: Int = defaultSampleRate, channels: Int = 1) -> Data {
        let bytesPerSample = 2
        let dataSize = samples.count * bytesPerSample
        var data = Data(capacity: 44 + dataSize)
        data.append(contentsOf: Array("RIFF".utf8))
        data.appendLE(UInt32(36 + dataSize))
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8))
        data.appendLE(UInt32(16))
        data.appendLE(UInt16(1))                    // PCM
        data.appendLE(UInt16(channels))
        data.appendLE(UInt32(sampleRate))
        data.appendLE(UInt32(sampleRate * channels * bytesPerSample))
        data.appendLE(UInt16(channels * bytesPerSample))
        data.appendLE(UInt16(16))
        data.append(contentsOf: Array("data".utf8))
        data.appendLE(UInt32(dataSize))
        for s in samples {
            let c = max(-1.0, min(1.0, Double(s)))
            data.appendLE(Int16(c * 32767.0))
        }
        return data
    }

    static func readWAV(_ data: Data) -> PCM? {
        guard data.count > 44 else { return nil }
        let bytes = [UInt8](data)
        func ascii(_ r: Range<Int>) -> String { String(bytes: bytes[r], encoding: .ascii) ?? "" }
        guard ascii(0..<4) == "RIFF", ascii(8..<12) == "WAVE" else { return nil }
        func u16(_ o: Int) -> Int { Int(bytes[o]) | (Int(bytes[o + 1]) << 8) }
        func u32(_ o: Int) -> Int { u16(o) | (u16(o + 2) << 16) }
        var offset = 12, sampleRate = defaultSampleRate, channels = 1, bits = 16, start = -1, count = 0
        while offset + 8 <= bytes.count {
            let id = ascii(offset..<(offset + 4))
            let size = u32(offset + 4)
            if id == "fmt " {
                channels = u16(offset + 10)
                sampleRate = u32(offset + 12)
                bits = u16(offset + 22)
            } else if id == "data" {
                start = offset + 8
                count = min(size, bytes.count - start)
                break
            }
            offset += 8 + size + (size % 2)
        }
        guard start >= 0, bits == 16, channels == 1 || channels == 2 else { return nil }
        let frames = count / (2 * channels)
        var out = [Float](); out.reserveCapacity(frames * channels)
        for i in 0..<frames {
            for ch in 0..<channels {
                let o = start + (i * channels + ch) * 2
                let v = Int16(bitPattern: UInt16(bytes[o]) | (UInt16(bytes[o + 1]) << 8))
                out.append(Float(v) / 32768.0)
            }
        }
        return PCM(samples: out, channels: channels, sampleRate: sampleRate)
    }

    // MARK: - Oscillators & wavetables

    enum Wave: String, Codable, CaseIterable, Identifiable {
        case sine, triangle, saw, square, noise, wavetable
        var id: String { rawValue }
        var label: String { rawValue.capitalized }
    }

    /// Band-limited-ish oscillator. `phase` in cycles (0...1 wraps).
    static func osc(_ wave: Wave, phase: Double, table: [Float]? = nil, rng: inout SeededRNG) -> Float {
        let p = phase - phase.rounded(.down)
        switch wave {
        case .sine: return Float(sin(2 * .pi * p))
        case .triangle: return Float(4 * abs(p - 0.5) - 1)
        case .saw:
            // Naive saw softened with a 2-sample average to reduce aliasing.
            let a = Float(2 * p - 1)
            let p2 = (p + 0.001) - (p + 0.001).rounded(.down)
            return (a + Float(2 * p2 - 1)) * 0.5 * 0.9
        case .square: return (p < 0.5 ? 1 : -1) * 0.85
        case .noise: return rng.nextFloat() * 2 - 1
        case .wavetable:
            guard let t = table, !t.isEmpty else { return Float(sin(2 * .pi * p)) }
            let pos = p * Double(t.count)
            let i0 = Int(pos) % t.count
            let i1 = (i0 + 1) % t.count
            let frac = Float(pos - pos.rounded(.down))
            return t[i0] * (1 - frac) + t[i1] * frac
        }
    }

    /// Build a 2048-sample single-cycle wavetable from harmonic amplitudes (1...16).
    static func makeWavetable(harmonics: [Float], size: Int = 2048) -> [Float] {
        var table = [Float](repeating: 0, count: size)
        for (h, amp) in harmonics.enumerated() where amp != 0 {
            let n = h + 1
            for i in 0..<size {
                table[i] += amp * Float(sin(2 * .pi * Double(n) * Double(i) / Double(size)))
            }
        }
        return normalize(table, target: 0.9)
    }

    /// Crossfade between two wavetables; `t` in 0...1. Supports "16-table morph paths"
    /// by chaining pairwise morphs along a bezier-ish eased curve.
    static func morphTables(_ a: [Float], _ b: [Float], t: Double) -> [Float] {
        guard a.count == b.count, !a.isEmpty else { return a }
        let e = t * t * (3 - 2 * t) // smoothstep easing
        return zip(a, b).map { Float(Double($0.0) * (1 - e) + Double($0.1) * e) }
    }

    /// Multi-table morph path across N tables (up to 16) at position t in 0...1.
    static func morphPath(_ tables: [[Float]], t: Double) -> [Float] {
        guard !tables.isEmpty else { return [] }
        if tables.count == 1 { return tables[0] }
        let pos = min(max(t, 0), 1) * Double(tables.count - 1)
        let idx = min(Int(pos), tables.count - 2)
        return morphTables(tables[idx], tables[idx + 1], t: pos - Double(idx))
    }

    // MARK: - Envelopes & modulators

    struct ADSR: Codable, Equatable {
        var attack = 0.01, decay = 0.08, sustain = 0.7, release = 0.12

        func value(at t: Double, noteDuration: Double) -> Float {
            if t < 0 { return 0 }
            let a = max(attack, 0.001), d = max(decay, 0.001), r = max(release, 0.001)
            if t < a { return Float(t / a) }
            if t < a + d { return Float(1 - (1 - sustain) * (t - a) / d) }
            let relStart = max(noteDuration - r, a + d)
            if t < relStart { return Float(sustain) }
            if t < noteDuration + r {
                let into = t - relStart
                let span = max(noteDuration + r - relStart, 0.001)
                return Float(sustain) * max(0, Float(1 - into / span))
            }
            return 0
        }
    }

    enum LFOShape: String, Codable, CaseIterable, Identifiable {
        case sine, triangle, square, sampleHold, gravity, pendulum, chaos
        var id: String { rawValue }
    }

    /// Drawable/physics modulators — LFOs, envelopes, step curves, gravity bounces,
    /// pendulum swings and logistic-map chaos. Returns 0...1.
    static func modulator(_ shape: LFOShape, phase: Double, rateHz: Double, seed: UInt64, step: Int) -> Double {
        let t = phase * rateHz
        switch shape {
        case .sine: return 0.5 + 0.5 * sin(2 * .pi * t)
        case .triangle:
            let p = t - t.rounded(.down)
            return p < 0.5 ? p * 2 : 2 - p * 2
        case .square: return (t - t.rounded(.down)) < 0.5 ? 1 : 0
        case .sampleHold:
            var rng = SeededRNG(seed &+ UInt64(step / 8))
            return rng.next01()
        case .gravity:
            // Bouncing ball: parabolic arcs with decaying height.
            let p = t - t.rounded(.down)
            let bounce = abs(1 - pow(2 * p - 1, 2))
            return bounce
        case .pendulum:
            return 0.5 + 0.5 * sin(2 * .pi * t) * cos(.pi * t * 0.25)
        case .chaos:
            // Logistic map x = 3.9·x·(1−x), iterated per step.
            var x = Double((seed % 1000) + 1) / 1001.0
            for _ in 0...max(1, step % 64) { x = 3.9 * x * (1 - x) }
            return x
        }
    }

    // MARK: - Filters

    struct Biquad {
        enum Kind { case lowpass, highpass, bandpass, notch, peak }
        private var b0 = 0.0, b1 = 0.0, b2 = 0.0, a1 = 0.0, a2 = 0.0
        private var x1 = 0.0, x2 = 0.0, y1 = 0.0, y2 = 0.0

        init(kind: Kind, cutoff: Double, q: Double, sampleRate: Int, gainDB: Double = 0) {
            let w = 2 * .pi * min(max(cutoff, 20), Double(sampleRate) * 0.45) / Double(sampleRate)
            let alpha = sin(w) / (2 * max(q, 0.05))
            let cw = cos(w)
            var b0 = 0.0, b1 = 0.0, b2 = 0.0, a0 = 1.0, a1 = 0.0, a2 = 0.0
            switch kind {
            case .lowpass:
                b0 = (1 - cw) / 2; b1 = 1 - cw; b2 = (1 - cw) / 2
                a0 = 1 + alpha; a1 = -2 * cw; a2 = 1 - alpha
            case .highpass:
                b0 = (1 + cw) / 2; b1 = -(1 + cw); b2 = (1 + cw) / 2
                a0 = 1 + alpha; a1 = -2 * cw; a2 = 1 - alpha
            case .bandpass:
                b0 = alpha; b1 = 0; b2 = -alpha
                a0 = 1 + alpha; a1 = -2 * cw; a2 = 1 - alpha
            case .notch:
                b0 = 1; b1 = -2 * cw; b2 = 1
                a0 = 1 + alpha; a1 = -2 * cw; a2 = 1 - alpha
            case .peak:
                let A = pow(10.0, gainDB / 40)
                b0 = 1 + alpha * A; b1 = -2 * cw; b2 = 1 - alpha * A
                a0 = 1 + alpha / A; a1 = -2 * cw; a2 = 1 - alpha / A
            }
            self.b0 = b0 / a0; self.b1 = b1 / a0; self.b2 = b2 / a0
            self.a1 = a1 / a0; self.a2 = a2 / a0
        }

        mutating func process(_ x: Float) -> Float {
            let xd = Double(x)
            let y = b0 * xd + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
            x2 = x1; x1 = xd; y2 = y1; y1 = y
            return Float(y)
        }

        static func apply(_ kind: Kind, to x: [Float], cutoff: Double, q: Double, sampleRate: Int, gainDB: Double = 0) -> [Float] {
            var f = Biquad(kind: kind, cutoff: cutoff, q: q, sampleRate: sampleRate, gainDB: gainDB)
            return x.map { f.process($0) }
        }
    }

    // MARK: - FX rack (offline, deterministic)

    static func delay(_ x: [Float], timeSec: Double, feedback: Double, mix: Double, sampleRate: Int, pingPong: Bool = false) -> [Float] {
        let d = max(1, Int(timeSec * Double(sampleRate)))
        var out = x
        for i in d..<x.count {
            let fb = out[i - d] * Float(feedback)
            out[i] = x[i] * Float(1 - mix) + (x[i] + fb) * Float(mix)
            if pingPong, i + d < x.count { out[i + d] += fb * 0.5 }
        }
        return out
    }

    /// Schroeder reverb: 4 parallel combs + 2 series allpasses.
    static func reverb(_ x: [Float], roomSize: Double, damping: Double, mix: Double, sampleRate: Int) -> [Float] {
        let combTunings = [1116, 1188, 1277, 1356].map { Int(Double($0) * Double(sampleRate) / 44100.0 * (0.5 + roomSize)) }
        let allTunings = [556, 441].map { Int(Double($0) * Double(sampleRate) / 44100.0) }
        var wet = [Float](repeating: 0, count: x.count)
        for len in combTunings where len > 4 {
            var buf = [Float](repeating: 0, count: len)
            var idx = 0
            var store = 0.0
            for (i, s) in x.enumerated() {
                let out = buf[idx]
                store = Double(out) * (1 - damping) + store * damping
                buf[idx] = s + Float(store) * Float(0.74 * roomSize + 0.1)
                wet[i] += out * 0.25
                idx = (idx + 1) % len
            }
        }
        for len in allTunings where len > 4 {
            var buf = [Float](repeating: 0, count: len)
            var idx = 0
            for i in 0..<wet.count {
                let out = buf[idx]
                buf[idx] = wet[i] + out * 0.5
                wet[i] = out - wet[i] * 0.5
                idx = (idx + 1) % len
            }
        }
        return zip(x, wet).map { Float(Double($0.0) * (1 - mix) + Double($0.1) * mix) }
    }

    static func chorus(_ x: [Float], rateHz: Double, depthMs: Double, mix: Double, sampleRate: Int) -> [Float] {
        let base = Int(0.012 * Double(sampleRate))
        let depth = depthMs * Double(sampleRate) / 1000.0
        var out = [Float](repeating: 0, count: x.count)
        for i in 0..<x.count {
            let lfo = sin(2 * .pi * rateHz * Double(i) / Double(sampleRate))
            let d = Int(Double(base) + depth * (0.5 + 0.5 * lfo))
            let wet: Float = i - d >= 0 ? x[i - d] : 0
            out[i] = x[i] * Float(1 - mix) + (x[i] + wet) * 0.5 * Float(mix) * 2 * 0.7 + x[i] * 0.3 * Float(mix)
        }
        return out
    }

    static func flanger(_ x: [Float], rateHz: Double, depthMs: Double, feedback: Double, mix: Double, sampleRate: Int) -> [Float] {
        let depth = depthMs * Double(sampleRate) / 1000.0
        var out = [Float](repeating: 0, count: x.count)
        for i in 0..<x.count {
            let lfo = 0.5 + 0.5 * sin(2 * .pi * rateHz * Double(i) / Double(sampleRate))
            let d = Int(depth * lfo) + 1
            var wet: Float = i - d >= 0 ? x[i - d] : 0
            wet += (i - d >= 0 ? out[i - d] : 0) * Float(feedback * 0.6)
            out[i] = x[i] * Float(1 - mix) + (x[i] + wet) * Float(mix) * 0.8
        }
        return out
    }

    static func distort(_ x: [Float], drive: Double, mix: Double, tone: Double = 0.5) -> [Float] {
        let k = Float(1 + drive * 30)
        return x.map { s in
            let shaped = tanh(k * s) / tanh(k)
            return s * Float(1 - mix) + shaped * Float(mix)
        }
    }

    static func bitcrush(_ x: [Float], bits: Double, downsample: Double, mix: Double) -> [Float] {
        let levels = pow(2.0, max(2, min(16, bits)))
        let step = max(1, Int(downsample))
        var out = [Float](repeating: 0, count: x.count)
        var held: Float = 0
        for i in 0..<x.count {
            if i % step == 0 { held = Float((Double(x[i]) * levels).rounded() / levels) }
            out[i] = x[i] * Float(1 - mix) + held * Float(mix)
        }
        return out
    }

    static func ringMod(_ x: [Float], freqHz: Double, mix: Double, sampleRate: Int) -> [Float] {
        var out = [Float](repeating: 0, count: x.count)
        for i in 0..<x.count {
            let c = Float(sin(2 * .pi * freqHz * Double(i) / Double(sampleRate)))
            out[i] = x[i] * (Float(1 - mix) + c * Float(mix))
        }
        return out
    }

    /// Simple one-knob compressor/limiter.
    static func compress(_ x: [Float], threshold: Double, ratio: Double, attackMs: Double, releaseMs: Double, sampleRate: Int) -> [Float] {
        let atk = exp(-1.0 / (max(attackMs, 0.1) * 0.001 * Double(sampleRate)))
        let rel = exp(-1.0 / (max(releaseMs, 1) * 0.001 * Double(sampleRate)))
        var env = 0.0
        var out = [Float](repeating: 0, count: x.count)
        for i in 0..<x.count {
            let a = abs(Double(x[i]))
            env = a > env ? atk * env + (1 - atk) * a : rel * env + (1 - rel) * a
            var gain = 1.0
            if env > threshold {
                let over = env / threshold
                gain = pow(over, 1.0 / max(ratio, 1) - 1.0)
            }
            out[i] = Float(Double(x[i]) * gain)
        }
        return out
    }

    /// 3-band tilt EQ: low shelf-ish, mid peak, high shelf-ish via biquads.
    static func eq3(_ x: [Float], lowGain: Double, midGain: Double, highGain: Double, sampleRate: Int) -> [Float] {
        var low = Biquad(kind: .lowpass, cutoff: 250, q: 0.7, sampleRate: sampleRate)
        var mid = Biquad(kind: .bandpass, cutoff: 1500, q: 0.8, sampleRate: sampleRate)
        var high = Biquad(kind: .highpass, cutoff: 4000, q: 0.7, sampleRate: sampleRate)
        return x.map { s in
            let l = low.process(s), m = mid.process(s), h = high.process(s)
            return l * Float(lowGain) + m * Float(midGain) + h * Float(highGain) + s * 0.2
        }
    }

    /// Decorrelated stereo widener (complementary short delays) → interleaved stereo.
    static func toStereo(_ x: [Float], width: Double, sampleRate: Int) -> [Float] {
        let d = Int(0.011 * Double(sampleRate))
        var out = [Float](repeating: 0, count: x.count * 2)
        for i in 0..<x.count {
            let delayed: Float = i - d >= 0 ? x[i - d] : 0
            let l = x[i] + delayed * Float(width) * 0.4
            let r = x[i] + (i - 2 * d >= 0 ? x[i - 2 * d] : 0) * Float(width) * 0.4
            out[2 * i] = max(-1, min(1, l))
            out[2 * i + 1] = max(-1, min(1, r))
        }
        return out
    }

    // MARK: - Time / pitch manipulation (TempoShift)

    /// Speed warp: 0.5 = half speed (pitched down), 2 = double speed. Resampling.
    static func speedWarp(_ x: [Float], factor: Double) -> [Float] {
        guard factor > 0, !x.isEmpty else { return x }
        let newCount = Int(Double(x.count) / factor)
        var out = [Float](repeating: 0, count: max(1, newCount))
        for i in 0..<out.count {
            let pos = Double(i) * factor
            let i0 = min(Int(pos), x.count - 1)
            let i1 = min(i0 + 1, x.count - 1)
            let frac = Float(pos - Double(i0))
            out[i] = x[i0] * (1 - frac) + x[i1] * frac
        }
        return out
    }

    /// Granular time stretch (duration changes, pitch stays).
    static func timeStretch(_ x: [Float], factor: Double, grainMs: Double = 60, sampleRate: Int) -> [Float] {
        guard factor > 0.05, !x.isEmpty else { return x }
        let grain = max(64, Int(grainMs * 0.001 * Double(sampleRate)))
        let hop = grain / 2
        let outCount = Int(Double(x.count) * factor)
        var out = [Float](repeating: 0, count: outCount)
        var src = 0, dst = 0
        while dst + grain < outCount {
            let readPos = min(src, max(0, x.count - grain - 1))
            for g in 0..<grain where dst + g < outCount {
                let w = Float(0.5 - 0.5 * cos(2 * .pi * Double(g) / Double(grain))) // Hann
                out[dst + g] += x[readPos + g] * w * 0.75
            }
            src += Int(Double(hop) / factor)
            dst += hop
        }
        return out
    }

    static func reverse(_ x: [Float]) -> [Float] { x.reversed() }

    /// Rhythmic gate/stutter over a 16-step pattern (true = pass, false = mute + stutter-tail).
    static func gate(_ x: [Float], pattern: [Bool], bpm: Double, sampleRate: Int, subdivide: Int = 4) -> [Float] {
        guard !pattern.isEmpty else { return x }
        let stepDur = 60.0 / bpm / Double(subdivide)
        let stepSamples = max(1, Int(stepDur * Double(sampleRate)))
        var out = [Float](repeating: 0, count: x.count)
        for i in 0..<x.count {
            let step = (i / stepSamples) % pattern.count
            let into = i % stepSamples
            if pattern[step] {
                out[i] = x[i]
            } else {
                // Stutter tail: repeat the first 30ms of the step with fast decay.
                let tail = min(Int(0.03 * Double(sampleRate)), stepSamples)
                let src = i - into + (into % max(tail, 1))
                let decay = Float(1.0 - Double(into) / Double(stepSamples))
                out[i] = x[src] * max(0, decay)
            }
        }
        return out
    }

    /// Vinyl-style tape stop across the whole buffer.
    static func tapeStop(_ x: [Float]) -> [Float] {
        guard !x.isEmpty else { return x }
        var out = [Float]()
        out.reserveCapacity(x.count * 2)
        var pos = 0.0
        var speed = 1.0
        while pos < Double(x.count - 1), speed > 0.02 {
            let i0 = Int(pos)
            let frac = Float(pos - Double(i0))
            out.append(x[i0] * (1 - frac) + x[min(i0 + 1, x.count - 1)] * frac)
            pos += speed
            speed *= 0.9985
        }
        return out
    }

    // MARK: - Granular cloud (Organica)

    struct GranularConfig {
        var grainSizeMs = 90.0
        var density = 24.0          // grains per second
        var pitchRandom = 0.12      // semitone-ish random ratio range
        var positionRandom = 0.4    // 0...1 how far grains scatter
        var durationSec = 4.0
        var seed: UInt64 = 42
    }

    static func granularCloud(_ x: [Float], config: GranularConfig, sampleRate: Int) -> [Float] {
        guard !x.isEmpty else { return [] }
        var rng = SeededRNG(config.seed)
        let grain = max(64, Int(config.grainSizeMs * 0.001 * Double(sampleRate)))
        let totalGrains = max(1, Int(config.durationSec * config.density))
        let outCount = Int(config.durationSec * Double(sampleRate)) + grain
        var out = [Float](repeating: 0, count: outCount)
        for _ in 0..<totalGrains {
            let posR = min(max(rng.next01() + (rng.next01() - 0.5) * config.positionRandom, 0), 1)
            let start = Int(posR * Double(max(0, x.count - grain - 1)))
            let pitch = 1.0 + (rng.next01() - 0.5) * config.pitchRandom
            let outPos = Int(rng.next01() * Double(max(1, outCount - grain)))
            let amp = 0.9 / sqrt(config.density / 12)
            for g in 0..<grain {
                let readPos = min(Double(start) + Double(g) * pitch, Double(x.count - 1))
                let i0 = Int(readPos)
                let frac = Float(readPos - Double(i0))
                let s = x[i0] * (1 - frac) + x[min(i0 + 1, x.count - 1)] * frac
                let w = Float(0.5 - 0.5 * cos(2 * .pi * Double(g) / Double(grain)))
                out[outPos + g] += s * w * Float(amp)
            }
        }
        return normalize(out, target: 0.85)
    }

    /// Time freeze: take a short slice and stretch it into an infinite pad.
    static func freezePad(_ x: [Float], at position: Double, durationSec: Double, sampleRate: Int) -> [Float] {
        guard x.count > sampleRate / 2 else { return [] }
        let sliceLen = min(Int(0.4 * Double(sampleRate)), x.count - 2)
        guard sliceLen > 64 else { return [] }
        let center = Int(min(max(position, 0), 1) * Double(x.count - sliceLen - 1))
        let slice = Array(x[center..<(center + sliceLen)])
        var cfg = GranularConfig(grainSizeMs: 140, density: 30, pitchRandom: 0.04, positionRandom: 0.9, durationSec: durationSec)
        cfg.seed = UInt64(sliceLen)
        let pad = granularCloud(slice, config: cfg, sampleRate: sampleRate)
        return reverb(pad, roomSize: 0.85, damping: 0.4, mix: 0.5, sampleRate: sampleRate)
    }

    // MARK: - Drum synthesis (for the Loop Factory)

    static func kick(freq: Double = 55, decay: Double = 0.28, sampleRate: Int) -> [Float] {
        let n = Int(decay * 2.2 * Double(sampleRate))
        var out = [Float](repeating: 0, count: n)
        var phase = 0.0
        for i in 0..<n {
            let t = Double(i) / Double(sampleRate)
            let env = exp(-t / decay)
            let f = freq * (1 + 3.5 * exp(-t * 30)) // pitch drop
            phase += 2 * .pi * f / Double(sampleRate)
            out[i] = Float(sin(phase) * env)
        }
        return out
    }

    static func snare(decay: Double = 0.16, sampleRate: Int) -> [Float] {
        let n = Int(decay * 2.5 * Double(sampleRate))
        var rng = SeededRNG(7)
        var out = [Float](repeating: 0, count: n)
        var phase = 0.0
        var bp = Biquad(kind: .bandpass, cutoff: 1800, q: 0.8, sampleRate: sampleRate)
        for i in 0..<n {
            let t = Double(i) / Double(sampleRate)
            let env = exp(-t / decay)
            phase += 2 * .pi * 190 / Double(sampleRate)
            let tone = sin(phase) * env * 0.5
            let noise = Double(bp.process(rng.nextFloat() * 2 - 1)) * env * 2.2
            out[i] = Float(tone + noise)
        }
        return normalize(out, target: 0.8)
    }

    static func hat(open: Bool = false, sampleRate: Int) -> [Float] {
        let decay = open ? 0.25 : 0.05
        let n = Int(decay * 3 * Double(sampleRate))
        var rng = SeededRNG(open ? 11 : 13)
        var hp = Biquad(kind: .highpass, cutoff: 7000, q: 0.7, sampleRate: sampleRate)
        var out = [Float](repeating: 0, count: n)
        for i in 0..<n {
            let t = Double(i) / Double(sampleRate)
            out[i] = hp.process(rng.nextFloat() * 2 - 1) * Float(exp(-t / decay)) * 0.6
        }
        return out
    }

    static func clap(sampleRate: Int) -> [Float] {
        let n = Int(0.3 * Double(sampleRate))
        var rng = SeededRNG(17)
        var bp = Biquad(kind: .bandpass, cutoff: 1200, q: 1.2, sampleRate: sampleRate)
        var out = [Float](repeating: 0, count: n)
        for i in 0..<n {
            let t = Double(i) / Double(sampleRate)
            // Three quick bursts + tail.
            let burst = (t < 0.01 || (t > 0.02 && t < 0.03) || (t > 0.04 && t < 0.05)) ? 1.0 : 0.25
            out[i] = bp.process(rng.nextFloat() * 2 - 1) * Float(exp(-t / 0.09) * burst) * 2.0
        }
        return normalize(out, target: 0.7)
    }

    static func place(on base: [Float], hit: [Float], atSec: Double, gain: Float, sampleRate: Int) -> [Float] {
        var out = base
        let start = Int(atSec * Double(sampleRate))
        guard start >= 0, start < out.count else { return out }
        for (i, s) in hit.enumerated() where start + i < out.count {
            out[start + i] = max(-1, min(1, out[start + i] + s * gain))
        }
        return out
    }

    // MARK: - Analysis (Earprint)

    /// Onset-autocorrelation BPM estimate.
    static func estimateBPM(_ x: [Float], sampleRate: Int) -> Double {
        guard x.count > sampleRate else { return 120 }
        // Energy envelope at 100 Hz.
        let frame = sampleRate / 100
        var env: [Double] = []
        var i = 0
        while i + frame < x.count {
            var e = 0.0
            for j in 0..<frame { let s = Double(x[i + j]); e += s * s }
            env.append(e)
            i += frame
        }
        guard env.count > 40 else { return 120 }
        // Half-wave rectified derivative = onset strength.
        var onset = [Double](repeating: 0, count: env.count)
        for k in 1..<env.count { onset[k] = max(0, env[k] - env[k - 1]) }
        let m = onset.reduce(0, +) / Double(onset.count)
        // Autocorrelate over 0.25s...1s lags (60...240 BPM at 100 fps).
        var best = (lag: 0, score: 0.0)
        let maxLag = min(100, onset.count - 1)
        guard maxLag > 25 else { return 120 }
        for lag in 25...maxLag {
            var score = 0.0
            for k in lag..<onset.count { score += (onset[k] - m) * (onset[k - lag] - m) }
            if score > best.score { best = (lag, score) }
        }
        guard best.lag > 0 else { return 120 }
        let bpm = 60.0 * 100.0 / Double(best.lag)
        // Snap into a musical range.
        var snapped = bpm
        while snapped < 70 { snapped *= 2 }
        while snapped > 180 { snapped /= 2 }
        return (snapped * 10).rounded() / 10
    }

    /// Krumhansl-Schmuckler key detection from a chromagram.
    static func detectKey(_ x: [Float], sampleRate: Int) -> (key: String, scale: String, confidence: Double) {
        let names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
        guard x.count > 4096 else { return ("C", "major", 0.3) }
        // Chroma energy via Goertzel at MIDI notes 36...84 on 4096 windows.
        var chroma = [Double](repeating: 0, count: 12)
        let winSize = 4096
        var pos = 0
        var windows = 0
        while pos + winSize <= x.count, windows < 24 {
            for midi in 36...84 {
                let f = 440.0 * pow(2.0, Double(midi - 69) / 12.0)
                let w = 2 * .pi * f / Double(sampleRate)
                var s0 = 0.0, s1 = 0.0, s2 = 0.0
                let coeff = 2 * cos(w)
                for i in 0..<winSize {
                    s0 = Double(x[pos + i]) + coeff * s1 - s2
                    s2 = s1; s1 = s0
                }
                let power = s1 * s1 + s2 * s2 - coeff * s1 * s2
                chroma[midi % 12] += max(power, 0)
            }
            pos += winSize * 2
            windows += 1
        }
        let majorProfile = [6.35, 2.23, 3.48, 2.33, 4.38, 4.09, 2.52, 5.19, 2.39, 3.66, 2.29, 2.88]
        let minorProfile = [6.33, 2.68, 3.52, 5.38, 2.60, 3.53, 2.54, 4.75, 3.98, 2.69, 3.34, 3.17]
        let meanC = chroma.reduce(0, +) / 12
        var best = (score: -2.0, key: 0, minor: false)
        for root in 0..<12 {
            for minor in [false, true] {
                let profile = minor ? minorProfile : majorProfile
                var num = 0.0, d1 = 0.0, d2 = 0.0
                let meanP = profile.reduce(0, +) / 12
                for k in 0..<12 {
                    let a = chroma[(root + k) % 12] - meanC
                    let b = profile[k] - meanP
                    num += a * b; d1 += a * a; d2 += b * b
                }
                let score = (d1 > 0 && d2 > 0) ? num / sqrt(d1 * d2) : 0
                if score > best.score { best = (score, root, minor) }
            }
        }
        return (names[best.key], best.minor ? "minor" : "major", min(max(best.score, 0), 1))
    }

    /// Average spectral centroid (brightness) in Hz — small DFT on windows.
    static func spectralCentroid(_ x: [Float], sampleRate: Int) -> Double {
        let win = 1024
        guard x.count >= win else { return 0 }
        var total = 0.0, norm = 0.0
        var pos = 0
        var windows = 0
        while pos + win <= x.count, windows < 12 {
            var frame = Array(x[pos..<(pos + win)])
            for i in 0..<win { frame[i] *= Float(0.5 - 0.5 * cos(2 * .pi * Double(i) / Double(win))) }
            let mags = fftMagnitudes(frame)
            var weighted = 0.0, sum = 0.0
            for (k, mag) in mags.enumerated() {
                let freq = Double(k) * Double(sampleRate) / Double(win)
                weighted += freq * Double(mag)
                sum += Double(mag)
            }
            if sum > 0 { total += weighted / sum; norm += 1 }
            pos += win * 2
            windows += 1
        }
        return norm > 0 ? total / norm : 0
    }

    static func rms(_ x: [Float]) -> Double {
        guard !x.isEmpty else { return 0 }
        return sqrt(x.reduce(0) { $0 + Double($1) * Double($1) } / Double(x.count))
    }

    static func peak(_ x: [Float]) -> Float { x.map { abs($0) }.max() ?? 0 }

    static func loudnessDB(_ x: [Float]) -> Double {
        let r = rms(x)
        return r > 0 ? 20 * log10(r) : -120
    }

    /// Sonic fingerprint: 8-D vector [centroid-norm, rms, zcr, lowRatio, midRatio,
    /// highRatio, bpm-norm, crest]. Comparable with cosine distance for preset match.
    static func fingerprint(_ x: [Float], sampleRate: Int) -> [Double] {
        guard !x.isEmpty else { return [] }
        let centroid = spectralCentroid(x, sampleRate: sampleRate) / 8000
        let energy = rms(x) * 4
        var crossings = 0
        for i in 1..<x.count where (x[i] >= 0) != (x[i - 1] >= 0) { crossings += 1 }
        let zcr = Double(crossings) / Double(x.count) * 6
        let bands = bandEnergies(x, sampleRate: sampleRate)
        let bpm = estimateBPM(x, sampleRate: sampleRate) / 180
        let crest = Double(peak(x)) / max(rms(x), 1e-6) / 6
        return [min(centroid, 1.5), min(energy, 1.5), min(zcr, 1.5), bands.0, bands.1, bands.2, min(bpm, 1.5), min(crest, 1.5)]
    }

    static func bandEnergies(_ x: [Float], sampleRate: Int) -> (Double, Double, Double) {
        let low = Biquad.apply(.lowpass, to: x, cutoff: 200, q: 0.7, sampleRate: sampleRate)
        let high = Biquad.apply(.highpass, to: x, cutoff: 2000, q: 0.7, sampleRate: sampleRate)
        var mid = [Float](repeating: 0, count: x.count)
        for i in 0..<x.count { mid[i] = x[i] - low[i] - high[i] }
        let l = rms(low), m = rms(mid), h = rms(high)
        let total = max(l + m + h, 1e-9)
        return (l / total, m / total, h / total)
    }

    static func fingerprintDistance(_ a: [Double], _ b: [Double]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 1 }
        var dot = 0.0, na = 0.0, nb = 0.0
        for i in a.indices { dot += a[i] * b[i]; na += a[i] * a[i]; nb += b[i] * b[i] }
        guard na > 0, nb > 0 else { return 1 }
        return 1 - dot / (sqrt(na) * sqrt(nb))
    }

    // MARK: - FFT (iterative radix-2, complex)

    static func fft(_ re: inout [Double], _ im: inout [Double], inverse: Bool = false) {
        let n = re.count
        guard n > 1, n & (n - 1) == 0 else { return }
        var j = 0
        for i in 1..<n {
            var bit = n >> 1
            while j & bit != 0 { j ^= bit; bit >>= 1 }
            j |= bit
            if i < j { re.swapAt(i, j); im.swapAt(i, j) }
        }
        var len = 2
        while len <= n {
            let ang = 2 * Double.pi / Double(len) * (inverse ? 1 : -1)
            let wr = cos(ang), wi = sin(ang)
            var i = 0
            while i < n {
                var curR = 1.0, curI = 0.0
                for k in 0..<(len / 2) {
                    let uR = re[i + k], uI = im[i + k]
                    let vR = re[i + k + len / 2] * curR - im[i + k + len / 2] * curI
                    let vI = re[i + k + len / 2] * curI + im[i + k + len / 2] * curR
                    re[i + k] = uR + vR; im[i + k] = uI + vI
                    re[i + k + len / 2] = uR - vR; im[i + k + len / 2] = uI - vI
                    let nextR = curR * wr - curI * wi
                    curI = curR * wi + curI * wr
                    curR = nextR
                }
                i += len
            }
            len <<= 1
        }
        if inverse {
            for i in 0..<n { re[i] /= Double(n); im[i] /= Double(n) }
        }
    }

    static func fftMagnitudes(_ frame: [Float]) -> [Float] {
        let n = frame.count
        guard n > 1, n & (n - 1) == 0 else { return [] }
        var re = frame.map(Double.init)
        var im = [Double](repeating: 0, count: n)
        fft(&re, &im)
        return (0..<(n / 2)).map { Float(sqrt(re[$0] * re[$0] + im[$0] * im[$0]) / Double(n / 2)) }
    }

    // MARK: - Hybridizer (spectral fusion, rhythm & timbre transfer)

    /// True spectral fusion via STFT magnitude morphing (not layering):
    /// geometric blend of magnitude spectra with phase from the dominant side.
    static func spectralFuse(_ a: [Float], _ b: [Float], amount: Double, sampleRate: Int) -> [Float] {
        let win = 1024, hop = 512
        let count = min(a.count, b.count)
        guard count > win * 2 else { return mix(a, b, gainA: Float(1 - amount), gainB: Float(amount)) }
        let t = min(max(amount, 0), 1)
        var out = [Float](repeating: 0, count: count)
        var norm = [Float](repeating: 0, count: count)
        var pos = 0
        while pos + win <= count {
            var reA = [Double](repeating: 0, count: win), imA = [Double](repeating: 0, count: win)
            var reB = [Double](repeating: 0, count: win), imB = [Double](repeating: 0, count: win)
            for i in 0..<win {
                let w = 0.5 - 0.5 * cos(2 * .pi * Double(i) / Double(win))
                reA[i] = Double(a[pos + i]) * w
                reB[i] = Double(b[pos + i]) * w
            }
            fft(&reA, &imA); fft(&reB, &imB)
            var reF = [Double](repeating: 0, count: win), imF = [Double](repeating: 0, count: win)
            for k in 0..<win {
                let magA = sqrt(reA[k] * reA[k] + imA[k] * imA[k])
                let magB = sqrt(reB[k] * reB[k] + imB[k] * imB[k])
                let magF = pow(magA + 1e-12, 1 - t) * pow(magB + 1e-12, t)
                let srcR = t < 0.5 ? reA[k] : reB[k], srcI = t < 0.5 ? imA[k] : imB[k]
                let srcMag = t < 0.5 ? magA : magB
                let scale = srcMag > 1e-9 ? magF / srcMag : 0
                reF[k] = srcR * scale
                imF[k] = srcI * scale
            }
            fft(&reF, &imF, inverse: true)
            for i in 0..<win {
                let w = 0.5 - 0.5 * cos(2 * .pi * Double(i) / Double(win))
                out[pos + i] += Float(reF[i]) * Float(w)
                norm[pos + i] += Float(w * w)
            }
            pos += hop
        }
        for i in 0..<count where norm[i] > 1e-6 { out[i] /= norm[i] / 0.75 }
        return normalize(out, target: 0.85)
    }

    /// Mix two buffers with gains (utility).
    static func mix(_ a: [Float], _ b: [Float], gainA: Float, gainB: Float) -> [Float] {
        let n = max(a.count, b.count)
        var out = [Float](repeating: 0, count: n)
        for i in 0..<n {
            let sa: Float = i < a.count ? a[i] : 0
            let sb: Float = i < b.count ? b[i] : 0
            out[i] = sa * gainA + sb * gainB
        }
        return out
    }

    /// Rhythm transfer: onset envelope of `src` re-grooves `dst`.
    static func rhythmTransfer(src: [Float], dst: [Float], sampleRate: Int, strength: Double = 0.8) -> [Float] {
        let frame = sampleRate / 100
        guard src.count > frame * 4, dst.count > frame * 4 else { return dst }
        func envelope(_ x: [Float]) -> [Float] {
            var env = [Float](repeating: 0, count: x.count)
            var e = 0.0
            for i in 0..<x.count {
                let a = abs(Double(x[i]))
                e = max(a, e * 0.9995)
                env[i] = Float(min(e * 1.6, 1.2))
            }
            return env
        }
        let envA = envelope(src)
        let envB = envelope(dst)
        var out = [Float](repeating: 0, count: dst.count)
        for i in 0..<dst.count {
            let ratio = envA[i % envA.count] / max(envB[i], 0.02)
            let g = 1 + (min(max(ratio, 0), 2.5) - 1) * Float(strength)
            out[i] = max(-1, min(1, dst[i] * g))
        }
        return out
    }

    /// Timbre transfer: tilt `dst` until its spectral centroid approaches `src`,
    /// then match loudness. Piano → violin-ish, voice → pad-ish.
    static func timbreTransfer(src: [Float], dst: [Float], sampleRate: Int) -> [Float] {
        let cSrc = spectralCentroid(src, sampleRate: sampleRate)
        let cDst = spectralCentroid(dst, sampleRate: sampleRate)
        guard cSrc > 0, cDst > 0 else { return dst }
        var out = dst
        if cSrc > cDst * 1.15 {
            out = Biquad.apply(.highpass, to: out, cutoff: min(cSrc * 0.5, 3000), q: 0.5, sampleRate: sampleRate)
            out = mix(dst, out, gainA: 0.4, gainB: 0.9)
        } else if cSrc < cDst * 0.85 {
            out = Biquad.apply(.lowpass, to: out, cutoff: max(cSrc * 1.8, 400), q: 0.5, sampleRate: sampleRate)
            out = mix(dst, out, gainA: 0.4, gainB: 0.9)
        }
        // Match RMS loudness.
        let g = rms(src) / max(rms(out), 1e-6)
        return out.map { max(-1, min(1, $0 * Float(min(g, 3)))) }
    }

    // MARK: - Utilities

    static func normalize(_ x: [Float], target: Float = 0.95) -> [Float] {
        let p = peak(x)
        guard p > 1e-6 else { return x }
        let g = target / p
        return g < 1 ? x.map { $0 * g } : x
    }

    static func fadeEdges(_ x: [Float], fadeMs: Double = 4, sampleRate: Int) -> [Float] {
        var out = x
        let n = min(Int(fadeMs * 0.001 * Double(sampleRate)), x.count / 4)
        guard n > 1 else { return out }
        for i in 0..<n {
            let g = Float(i) / Float(n)
            out[i] *= g
            out[out.count - 1 - i] *= g
        }
        return out
    }

    // MARK: - MIDI writer (multi-lane, absolute timing)

    static func midiFile(notes: [VinnyNote], bpm: Int) -> Data {
        let tpq = 480
        var data = Data()
        data.append(contentsOf: Array("MThd".utf8))
        data.append(contentsOf: [0, 0, 0, 6])
        data.append(contentsOf: [0, 0])           // format 0
        data.append(contentsOf: [0, 1])           // 1 track
        data.append(contentsOf: [UInt8(tpq >> 8), UInt8(tpq & 0xFF)])

        var track = Data()
        // Tempo
        let mpq = 60_000_000 / max(bpm, 20)
        track.append(contentsOf: [0, 0xFF, 0x51, 0x03, UInt8((mpq >> 16) & 0xFF), UInt8((mpq >> 8) & 0xFF), UInt8(mpq & 0xFF)])

        struct Ev { let tick: Int; let bytes: [UInt8] }
        var events: [Ev] = []
        func vlq(_ v: Int) -> [UInt8] {
            var value = v, out: [UInt8] = [UInt8(value & 0x7F)]
            value >>= 7
            while value > 0 { out.insert(UInt8((value & 0x7F) | 0x80), at: 0); value >>= 7 }
            return out
        }
        for n in notes {
            let startTick = max(0, Int(n.start * Double(bpm) / 60.0 * Double(tpq)))
            let endTick = max(startTick + 1, Int((n.start + n.duration) * Double(bpm) / 60.0 * Double(tpq)))
            let vel = UInt8(min(127, max(1, Int(n.velocity * 127))))
            let noteNum = UInt8(min(127, max(0, n.lane == 9 ? n.drum : n.midi)))
            let channel = UInt8(n.lane == 9 ? 9 : min(n.lane, 3))
            events.append(Ev(tick: startTick, bytes: [0x90 | channel, noteNum, vel]))
            events.append(Ev(tick: endTick, bytes: [0x80 | channel, noteNum, 0]))
        }
        events.sort { $0.tick < $1.tick }
        var lastTick = 0
        for e in events {
            track.append(contentsOf: vlq(e.tick - lastTick))
            track.append(contentsOf: e.bytes)
            lastTick = e.tick
        }
        track.append(contentsOf: [0, 0xFF, 0x2F, 0])

        let len = track.count
        data.append(contentsOf: Array("MTrk".utf8))
        data.append(contentsOf: [UInt8((len >> 24) & 0xFF), UInt8((len >> 16) & 0xFF), UInt8((len >> 8) & 0xFF), UInt8(len & 0xFF)])
        data.append(track)
        return data
    }
}

// MARK: - Deterministic RNG

struct SeededRNG {
    private var state: UInt64
    init(_ seed: UInt64) { state = seed &+ 0x9E3779B97F4A7C15 }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
    mutating func next01() -> Double { Double(next() >> 11) / Double(1 << 53) }
    mutating func nextFloat() -> Float { Float(next01()) }
    mutating func nextInt(_ range: ClosedRange<Int>) -> Int { range.lowerBound + Int(next() % UInt64(range.upperBound - range.lowerBound + 1)) }
    mutating func nextInt(_ range: Range<Int>) -> Int { range.lowerBound + Int(next() % UInt64(range.upperBound - range.lowerBound)) }
}
