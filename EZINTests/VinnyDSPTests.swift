import XCTest
@testable import EZIN

// MARK: - VINNY DSP engine tests

final class VinnyDSPTests: XCTestCase {

    private let sr = VinnyDSP.defaultSampleRate

    // MARK: WAV round-trip

    func testWAVWriteReadRoundTrip() {
        var samples = [Float](repeating: 0, count: 4410)
        for i in 0..<samples.count { samples[i] = Float(sin(2 * .pi * 440 * Double(i) / 44100.0)) * 0.5 }
        let data = VinnyDSP.writeWAV(samples, sampleRate: sr)
        let pcm = VinnyDSP.readWAV(data)
        XCTAssertNotNil(pcm)
        if let pcm {
            XCTAssertEqual(pcm.sampleRate, sr)
            XCTAssertEqual(pcm.channels, 1)
            XCTAssertEqual(pcm.samples.count, samples.count)
            XCTAssertEqual(pcm.samples[100], samples[100], accuracy: 0.001)
        }
    }

    func testWAVStereoRoundTrip() {
        let mono = [Float](repeating: 100, count: 2000).enumerated().map { Float($0.offset % 100) / 100 }
        let stereo = VinnyDSP.toStereo(mono, width: 0.8, sampleRate: sr)
        XCTAssertEqual(stereo.count, mono.count * 2)
        let data = VinnyDSP.writeWAV(stereo, sampleRate: sr, channels: 2)
        let pcm = VinnyDSP.readWAV(data)
        XCTAssertEqual(pcm?.channels, 2)
        XCTAssertEqual(pcm?.frames, mono.count)
    }

    // MARK: Oscillators & envelopes

    func testOscillatorsAreBounded() {
        var rng = SeededRNG(42)
        for wave in VinnyDSP.Wave.allCases {
            for i in 0..<100 {
                let v = VinnyDSP.osc(wave, phase: Double(i) * 0.013, table: [0, 1, 0, -1], rng: &rng)
                XCTAssertGreaterThanOrEqual(v, -1.5)
                XCTAssertLessThanOrEqual(v, 1.5)
            }
        }
    }

    func testTriangleWaveShape() {
        var rng = SeededRNG(1)
        XCTAssertEqual(VinnyDSP.osc(.triangle, phase: 0.0, rng: &rng), 1, accuracy: 0.01)
        XCTAssertEqual(VinnyDSP.osc(.triangle, phase: 0.5, rng: &rng), -1, accuracy: 0.01)
    }

    func testADSRLifecycle() {
        let env = VinnyDSP.ADSR(attack: 0.1, decay: 0.1, sustain: 0.5, release: 0.1)
        XCTAssertEqual(env.value(at: 0, noteDuration: 1.0), 0, accuracy: 0.01)
        XCTAssertEqual(env.value(at: 0.1, noteDuration: 1.0), 1, accuracy: 0.01)
        XCTAssertEqual(env.value(at: 0.5, noteDuration: 1.0), 0.5, accuracy: 0.01)
        XCTAssertEqual(env.value(at: 2.0, noteDuration: 1.0), 0, accuracy: 0.01)
    }

    func testWavetableMorphIsBlended() {
        let a = VinnyDSP.makeWavetable(harmonics: [1])
        let b = VinnyDSP.makeWavetable(harmonics: [0, 0, 0, 1])
        let mid = VinnyDSP.morphTables(a, b, t: 0.5)
        XCTAssertEqual(mid.count, a.count)
        let peakA = VinnyDSP.peak(a), peakMid = VinnyDSP.peak(mid)
        XCTAssertGreaterThan(peakA, 0)
        XCTAssertGreaterThan(peakMid, 0)
    }

    // MARK: FX

    func testFXKeepSignalBoundedAndLength() {
        var x = [Float](repeating: 0, count: sr / 2)
        for i in 0..<x.count { x[i] = Float(sin(2 * .pi * 220 * Double(i) / Double(sr))) * 0.6 }
        let fx: [[Float]] = [
            VinnyDSP.reverb(x, roomSize: 0.7, damping: 0.4, mix: 0.4, sampleRate: sr),
            VinnyDSP.delay(x, timeSec: 0.2, feedback: 0.4, mix: 0.4, sampleRate: sr),
            VinnyDSP.chorus(x, rateHz: 1.0, depthMs: 8, mix: 0.5, sampleRate: sr),
            VinnyDSP.flanger(x, rateHz: 0.5, depthMs: 4, feedback: 0.4, mix: 0.5, sampleRate: sr),
            VinnyDSP.distort(x, drive: 0.6, mix: 0.8),
            VinnyDSP.bitcrush(x, bits: 8, downsample: 3, mix: 0.7),
            VinnyDSP.compress(x, threshold: 0.5, ratio: 4, attackMs: 5, releaseMs: 100, sampleRate: sr),
            VinnyDSP.eq3(x, lowGain: 1.2, midGain: 0.8, highGain: 1.1, sampleRate: sr)
        ]
        for out in fx {
            XCTAssertEqual(out.count, x.count)
            XCTAssertLessThanOrEqual(VinnyDSP.peak(out), 2.0)
        }
    }

    // MARK: Time warping

    func testSpeedWarpHalvesAndDoubles() {
        let x = [Float](repeating: 0.5, count: 10000)
        XCTAssertEqual(VinnyDSP.speedWarp(x, factor: 0.5).count, 20000)
        XCTAssertEqual(VinnyDSP.speedWarp(x, factor: 2.0).count, 5000)
    }

    func testTimeStretchKeepsPitchChangesDuration() {
        var x = [Float](repeating: 0, count: sr)
        for i in 0..<x.count { x[i] = Float(sin(2 * .pi * 440 * Double(i) / Double(sr))) }
        let stretched = VinnyDSP.timeStretch(x, factor: 2.0, sampleRate: sr)
        XCTAssertGreaterThan(stretched.count, Int(Double(x.count) * 1.6))
    }

    func testGateMutesClosedSteps() {
        let x = [Float](repeating: 0.8, count: sr)
        let out = VinnyDSP.gate(x, pattern: [true, false], bpm: 120, sampleRate: sr, subdivide: 1)
        // Step length at 120 BPM / 1 subdiv = 0.5s → samples 22050...44100 are "muted" region
        let mutedRegion = Array(out[23000..<43000])
        XCTAssertLessThan(VinnyDSP.rms(mutedRegion), VinnyDSP.rms(x) * 0.6)
    }

    // MARK: Analysis

    func testBPMEstimateOnClickTrack() {
        // 120 BPM click track: a kick every 0.5s for 8 seconds.
        var x = [Float](repeating: 0, count: sr * 8)
        let kick = VinnyDSP.kick(sampleRate: sr)
        var t = 0.0
        while t < 7.5 {
            x = VinnyDSP.place(on: x, hit: kick, atSec: t, gain: 0.9, sampleRate: sr)
            t += 0.5
        }
        let bpm = VinnyDSP.estimateBPM(x, sampleRate: sr)
        XCTAssertEqual(bpm, 120, accuracy: 6)
    }

    func testKeyDetectionOnCMajorChord() {
        // Render C4 + E4 + G4 sines; expect C major-ish.
        var x = [Float](repeating: 0, count: sr * 2)
        for midi in [60, 64, 67] {
            let f = 440.0 * pow(2.0, Double(midi - 69) / 12.0)
            for i in 0..<x.count { x[i] += Float(sin(2 * .pi * f * Double(i) / Double(sr))) * 0.3 }
        }
        let result = VinnyDSP.detectKey(x, sampleRate: sr)
        XCTAssertEqual(result.key, "C")
        XCTAssertEqual(result.scale, "major")
    }

    func testFingerprintDimensionsAndDistance() {
        var x = [Float](repeating: 0, count: sr)
        for i in 0..<x.count { x[i] = Float(sin(2 * .pi * 330 * Double(i) / Double(sr))) * 0.5 }
        let fp = VinnyDSP.fingerprint(x, sampleRate: sr)
        XCTAssertEqual(fp.count, 8)
        XCTAssertEqual(VinnyDSP.fingerprintDistance(fp, fp), 0, accuracy: 0.0001)
    }

    func testFFTMagnitudesFindsSinePeak() {
        let n = 1024
        var frame = [Float](repeating: 0, count: n)
        let binFreq = 10.0 // exactly bin 10
        for i in 0..<n { frame[i] = Float(sin(2 * .pi * binFreq * Double(i) / Double(n))) }
        let mags = VinnyDSP.fftMagnitudes(frame)
        let peakBin = mags.enumerated().max(by: { $0.element < $1.element })?.offset
        XCTAssertEqual(peakBin, 10)
    }

    func testSpectralFuseProducesCleanOutput() {
        var a = [Float](repeating: 0, count: sr)
        var b = [Float](repeating: 0, count: sr)
        for i in 0..<sr {
            a[i] = Float(sin(2 * .pi * 110 * Double(i) / Double(sr))) * 0.5
            b[i] = Float(sin(2 * .pi * 880 * Double(i) / Double(sr))) * 0.5
        }
        let fused = VinnyDSP.spectralFuse(a, b, amount: 0.5, sampleRate: sr)
        XCTAssertGreaterThan(fused.count, 0)
        XCTAssertLessThanOrEqual(VinnyDSP.peak(fused), 1.01)
        XCTAssertGreaterThan(VinnyDSP.rms(fused), 0.01)
    }

    // MARK: MIDI

    func testMIDIFileHeaderAndNotes() {
        let notes = [
            VinnyDSP.VinnyNote(midi: 60, start: 0, duration: 0.5, velocity: 0.8, lane: 0),
            VinnyDSP.VinnyNote(midi: 36, start: 0, duration: 0.25, velocity: 1.0, lane: 9, drum: 36)
        ]
        let data = VinnyDSP.midiFile(notes: notes, bpm: 120)
        let bytes = [UInt8](data)
        XCTAssertEqual(String(bytes: bytes[0..<4], encoding: .ascii), "MThd")
        XCTAssertTrue(data.count > 30)
    }

    // MARK: Renderer / Loop Factory

    func testRendererProducesAudio() {
        var patch = VinnyPatch.default
        patch.bpm = 120
        let notes = [VinnyDSP.VinnyNote(midi: 60, start: 0, duration: 0.5, velocity: 0.8, lane: 0),
                     VinnyDSP.VinnyNote(midi: 64, start: 0.5, duration: 0.5, velocity: 0.8, lane: 0)]
        let pcm = VinnyRenderer.render(patch: patch, notes: notes, durationSec: 1.5)
        XCTAssertEqual(pcm.count, Int(1.5 * Double(sr)))
        XCTAssertGreaterThan(VinnyDSP.rms(pcm), 0.001)
        XCTAssertLessThanOrEqual(VinnyDSP.peak(pcm), 1.0)
    }

    func testLoopFactoryBuildsFullArrangement() {
        let patch = GenesisEngine.patch(fromText: "dusty lo-fi keys", seed: 99)
        let result = LoopFactory.makeLoop(patch: patch, bars: 2, seed: 42)
        XCTAssertFalse(result.wav.isEmpty)
        XCTAssertFalse(result.midi.isEmpty)
        XCTAssertEqual(result.stems.count, 4)
        XCTAssertGreaterThan(result.notes.count, 10)
        // Stems must be valid WAVs.
        for (_, data) in result.stems { XCTAssertNotNil(VinnyDSP.readWAV(data)) }
    }

    func testGenesisTextToPatchMapsKeywords() {
        let dark = GenesisEngine.patch(fromText: "dark aggressive trap 808 sub", seed: 1)
        XCTAssertGreaterThan(dark.subLevel, 0.3)
        XCTAssertEqual(dark.genre, "Trap")
        let calm = GenesisEngine.patch(fromText: "calm bright ambient pad", seed: 1)
        XCTAssertGreaterThan(calm.env.attack, 0.1)
        XCTAssertEqual(calm.genre, "Ambient")
    }

    func testMutationsAndBreedingDiffer() {
        let base = GenesisEngine.patch(fromText: "warm analog bass", seed: 7)
        let muts = GenesisEngine.mutations(of: base)
        XCTAssertEqual(muts.count, 8)
        XCTAssertTrue(muts.contains { $0.filterCutoff != base.filterCutoff || $0.unisonVoices != base.unisonVoices })
        let other = GenesisEngine.patch(fromText: "bright bell pluck", seed: 8)
        let child = GenesisEngine.breed(base, other)
        XCTAssertFalse(child.name.isEmpty)
        XCTAssertEqual(child.normalized().osc.count, 4)
    }

    func testTheoryQuantizeAndProgression() {
        // C# is not in C major → should snap to C or D.
        let snapped = TheoryEngine.quantize(61, key: "C", scale: "major")
        XCTAssertTrue([60, 62].contains(snapped))
        let prog = TheoryEngine.progression(genre: "Lo-Fi", seed: 5)
        XCTAssertEqual(prog.count, 4)
        let chord = TheoryEngine.chord(rootDegree: 0, key: "A", scale: "minor", style: "seventh")
        XCTAssertEqual(chord.count, 4)
    }

    func testAssistantAppliesCommands() {
        var p = VinnyPatch.default
        p.filterCutoff = 8000
        let (darker, reply) = VinnyAssistant.apply(command: "make it darker and add grit", to: p)
        XCTAssertLessThan(darker.filterCutoff, p.filterCutoff)
        XCTAssertTrue(darker.fx.contains { $0.kind == .distortion })
        XCTAssertFalse(reply.isEmpty)
    }

    func testGranularCloudOutput() {
        var x = [Float](repeating: 0, count: sr)
        for i in 0..<x.count { x[i] = Float(sin(2 * .pi * 220 * Double(i) / Double(sr))) * 0.5 }
        let cloud = VinnyDSP.granularCloud(x, config: VinnyDSP.GranularConfig(durationSec: 2), sampleRate: sr)
        XCTAssertGreaterThan(cloud.count, sr)
        XCTAssertGreaterThan(VinnyDSP.rms(cloud), 0.001)
    }

    func testPlaceRejectsNegativeAndOverflowTimes() {
        // Regression: humanized timing at loop start can go slightly negative —
        // placing a hit there must be a no-op, not a crash.
        let base = [Float](repeating: 0, count: 1000)
        let hit = [Float](repeating: 0.5, count: 100)
        let neg = VinnyDSP.place(on: base, hit: hit, atSec: -0.003, gain: 1, sampleRate: sr)
        XCTAssertEqual(neg, base)
        let far = VinnyDSP.place(on: base, hit: hit, atSec: 99, gain: 1, sampleRate: sr)
        XCTAssertEqual(far, base)
    }

    func testStemsZIPRoundTrip() {
        let patch = GenesisEngine.patch(fromText: "techno rumble", seed: 3)
        let result = LoopFactory.makeLoop(patch: patch, bars: 1, seed: 1)
        var entries: [ZipWriter.Entry] = result.stems.map { ZipWriter.Entry(name: "stems/\($0.key).wav", data: $0.value) }
        entries.append(ZipWriter.Entry(name: "mix.wav", data: result.wav))
        let zip = ZipWriter.makeZip(entries: entries)
        XCTAssertNotNil(zip)
        XCTAssertGreaterThan(zip?.count ?? 0, 1000)
    }
}
