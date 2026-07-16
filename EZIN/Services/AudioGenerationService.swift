import Foundation
import AVFoundation

/// Generates audio files (WAV, MIDI) from code/parameter descriptions.
/// Used by the chat assistant's `create_song` and related tools.
enum AudioGenerationService {

    // MARK: - Song / Tone Generation

    struct Note {
        let frequency: Double   // Hz
        let duration: Double    // seconds
        let amplitude: Double   // 0...1
    }

    /// Parse a text description into musical notes.
    /// Supports: "C4 0.5s", "E4 1s amp 0.8", "rest 0.25s", "chord C4 E4 G4 1s"
    static func parseNotes(from description: String) -> [Note] {
        let noteMap: [String: Double] = [
            "C": 261.63, "C#": 277.18, "Db": 277.18,
            "D": 293.66, "D#": 311.13, "Eb": 311.13,
            "E": 329.63,
            "F": 349.23, "F#": 369.99, "Gb": 369.99,
            "G": 392.00, "G#": 415.30, "Ab": 415.30,
            "A": 440.00, "A#": 466.16, "Bb": 466.16,
            "B": 493.88
        ]

        var notes: [Note] = []
        let lines = description.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("//") else { continue }

            if trimmed.lowercased().hasPrefix("chord ") {
                // chord C4 E4 G4 1s [amp 0.7]
                let parts = trimmed.dropFirst(6).split(separator: " ").map(String.init)
                var dur = 1.0
                var amp = 0.5
                var freqList: [Double] = []
                for (i, p) in parts.enumerated() {
                    if p.hasSuffix("s"), let d = Double(p.dropLast()) {
                        dur = d
                    } else if p == "amp", i + 1 < parts.count, let a = Double(parts[i + 1]) {
                        amp = a
                    } else {
                        freqList.append(parseNoteToFreq(p, map: noteMap))
                    }
                }
                // Add each note of the chord
                for f in freqList where f > 0 {
                    notes.append(Note(frequency: f, duration: dur, amplitude: amp))
                }
            } else if trimmed.lowercased().hasPrefix("rest ") {
                // rest 0.5s
                let parts = trimmed.split(separator: " ")
                if parts.count >= 2, let dur = Double(parts[1].dropLast()) {
                    notes.append(Note(frequency: 0, duration: dur, amplitude: 0)) // silent note
                }
            } else {
                // Single note: C4 0.5s [amp 0.8]
                let parts = trimmed.split(separator: " ").map(String.init)
                guard !parts.isEmpty else { continue }
                let noteStr = parts[0]
                var dur = 0.5
                var amp = 0.5
                for (i, p) in parts.enumerated() {
                    if p.hasSuffix("s"), let d = Double(p.dropLast()) {
                        dur = d
                    } else if p == "amp", i + 1 < parts.count, let a = Double(parts[i + 1]) {
                        amp = a
                    }
                }
                let freq = parseNoteToFreq(noteStr, map: noteMap)
                if freq > 0 {
                    notes.append(Note(frequency: freq, duration: dur, amplitude: amp))
                }
            }
        }
        return notes
    }

    private static func parseNoteToFreq(_ note: String, map: [String: Double]) -> Double {
        let trimmed = note.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return 0 }
        // Extract note letter and octave
        let letter = trimmed.prefix { $0.isLetter || $0 == "#" || $0 == "b" }
        let octaveStr = String(trimmed.reversed().prefix { $0.isNumber }.reversed())
        guard let octave = Int(octaveStr), let baseFreq = map[String(letter)] else { return 0 }
        // Adjust for octave
        let octaveDiff = octave - 4
        return baseFreq * pow(2.0, Double(octaveDiff))
    }

    // MARK: - WAV Generation

    static func generateWAV(notes: [Note], sampleRate: Double = 44100) -> Data? {
        guard !notes.isEmpty else { return nil }
        let totalSamples = Int(notes.reduce(0) { $0 + $1.duration } * sampleRate)
        guard totalSamples > 0 else { return nil }

        var samples = [Float](repeating: 0, count: totalSamples)
        var sampleOffset = 0

        for note in notes {
            let noteSamples = Int(note.duration * sampleRate)
            guard noteSamples > 0 else { continue }

            if note.frequency > 0 {
                // Generate sine wave with ADSR envelope
                let attackSamples = min(noteSamples / 20, Int(0.01 * sampleRate))
                let decaySamples = min(noteSamples / 10, Int(0.05 * sampleRate))
                let releaseSamples = min(noteSamples / 10, Int(0.05 * sampleRate))
                let sustainLevel: Float = 0.7

                for i in 0..<noteSamples {
                    let t = Double(i) / sampleRate
                    // Sine wave with slight harmonics for richer sound
                    let phase = 2.0 * .pi * note.frequency * t
                    let sine = sin(phase)
                    let harmonic2 = 0.15 * sin(phase * 2)
                    let harmonic3 = 0.05 * sin(phase * 3)
                    let raw = Float(sine + harmonic2 + harmonic3)

                    // ADSR envelope
                    var envelope: Float = 1.0
                    if i < attackSamples {
                        envelope = Float(i) / Float(attackSamples)
                    } else if i < attackSamples + decaySamples {
                        let decayProgress = Float(i - attackSamples) / Float(decaySamples)
                        envelope = 1.0 - (1.0 - sustainLevel) * decayProgress
                    } else if i >= noteSamples - releaseSamples {
                        let releaseProgress = Float(noteSamples - i) / Float(releaseSamples)
                        envelope = sustainLevel * releaseProgress
                    } else {
                        envelope = sustainLevel
                    }

                    let idx = sampleOffset + i
                    if idx < samples.count {
                        samples[idx] += raw * envelope * Float(note.amplitude) * 0.3
                    }
                }
            }
            // else: rest (silence), just advance offset
            sampleOffset += noteSamples
        }

        // Normalize to prevent clipping
        let maxAmp = samples.map(abs).max() ?? 1.0
        if maxAmp > 0.99 {
            samples = samples.map { $0 * (0.99 / maxAmp) }
        }

        return writeWAVData(samples: samples, sampleRate: Int(sampleRate))
    }

    /// Generate a simple WAV from a text description of notes.
    static func generateWAV(from description: String, sampleRate: Double = 44100) -> Data? {
        let notes = parseNotes(from: description)
        return generateWAV(notes: notes, sampleRate: sampleRate)
    }

    private static func writeWAVData(samples: [Float], sampleRate: Int) -> Data {
        let bytesPerSample = 2
        let dataSize = samples.count * bytesPerSample
        let totalSize = 44 + dataSize

        var data = Data(capacity: totalSize)

        // RIFF header
        data.append(contentsOf: Array("RIFF".utf8))
        data.append(contentsOf: UInt32(totalSize - 8).littleEndianBytes)
        data.append(contentsOf: Array("WAVE".utf8))

        // fmt chunk
        data.append(contentsOf: Array("fmt ".utf8))
        data.append(contentsOf: UInt32(16).littleEndianBytes) // chunk size
        data.append(contentsOf: UInt16(1).littleEndianBytes)  // PCM
        data.append(contentsOf: UInt16(1).littleEndianBytes)  // mono
        data.append(contentsOf: UInt32(sampleRate).littleEndianBytes)
        data.append(contentsOf: UInt32(sampleRate * bytesPerSample).littleEndianBytes) // byte rate
        data.append(contentsOf: UInt16(bytesPerSample).littleEndianBytes) // block align
        data.append(contentsOf: UInt16(16).littleEndianBytes) // bits per sample

        // data chunk
        data.append(contentsOf: Array("data".utf8))
        data.append(contentsOf: UInt32(dataSize).littleEndianBytes)

        // Convert float samples to 16-bit PCM
        for sample in samples {
            let clamped = max(-1.0, min(1.0, Double(sample)))
            let pcm = Int16(clamped * 32767.0)
            data.append(contentsOf: pcm.littleEndianBytes)
        }

        return data
    }

    // MARK: - MIDI Generation

    struct MIDINote {
        let noteNumber: UInt8  // MIDI note number (60 = C4)
        let duration: UInt32   // ticks
        let velocity: UInt8    // 0-127
    }

    /// Convert frequency notes to MIDI notes and generate a MIDI file.
    static func generateMIDI(notes: [Note], tempoBPM: UInt16 = 120) -> Data? {
        guard !notes.isEmpty else { return nil }
        let ticksPerQuarter: UInt16 = 480
        var midiNotes: [MIDINote] = []

        for note in notes {
            let midiNum = freqToMIDINote(note.frequency)
            let duration = UInt32(note.duration * Double(tempoBPM) / 60.0 * Double(ticksPerQuarter))
            let velocity = UInt8(min(127, max(1, Int(note.amplitude * 127))))
            midiNotes.append(MIDINote(noteNumber: midiNum, duration: max(duration, 1), velocity: velocity))
        }

        return writeMIDIFile(notes: midiNotes, tempoBPM: tempoBPM, ticksPerQuarter: ticksPerQuarter)
    }

    static func generateMIDI(from description: String, tempoBPM: UInt16 = 120) -> Data? {
        let notes = parseNotes(from: description)
        return generateMIDI(notes: notes, tempoBPM: tempoBPM)
    }

    private static func freqToMIDINote(_ freq: Double) -> UInt8 {
        guard freq > 0 else { return 0 }
        let midi = 69 + 12 * log2(freq / 440.0)
        return UInt8(min(127, max(0, Int(round(midi)))))
    }

    private static func writeMIDIFile(notes: [MIDINote], tempoBPM: UInt16, ticksPerQuarter: UInt16) -> Data {
        var data = Data()

        // MThd header
        data.append(contentsOf: Array("MThd".utf8))
        data.append(contentsOf: UInt32(6).bigEndianBytes)
        data.append(contentsOf: UInt16(0).bigEndianBytes) // format 0
        data.append(contentsOf: UInt16(1).bigEndianBytes) // 1 track
        data.append(contentsOf: ticksPerQuarter.bigEndianBytes)

        // MTrk header
        data.append(contentsOf: Array("MTrk".utf8))

        var trackData = Data()

        // Tempo meta event
        let microsecondsPerQuarter = 60000000 / Int(tempoBPM)
        trackData.append(contentsOf: variableLengthQuantity(0)) // delta time
        trackData.append(0xFF) // meta event
        trackData.append(0x51) // set tempo
        trackData.append(0x03) // 3 bytes
        trackData.append(UInt8((microsecondsPerQuarter >> 16) & 0xFF))
        trackData.append(UInt8((microsecondsPerQuarter >> 8) & 0xFF))
        trackData.append(UInt8(microsecondsPerQuarter & 0xFF))

        // Program change (piano = 0)
        trackData.append(contentsOf: variableLengthQuantity(0))
        trackData.append(0xC0)
        trackData.append(0x00)

        // Notes
        for note in notes {
            if note.noteNumber == 0 {
                // Rest - just advance time
                trackData.append(contentsOf: variableLengthQuantity(note.duration))
            } else {
                // Note on
                trackData.append(contentsOf: variableLengthQuantity(0))
                trackData.append(0x90) // note on channel 0
                trackData.append(note.noteNumber)
                trackData.append(note.velocity)

                // Note off (after duration)
                trackData.append(contentsOf: variableLengthQuantity(note.duration))
                trackData.append(0x80) // note off channel 0
                trackData.append(note.noteNumber)
                trackData.append(0x00)
            }
        }

        // End of track
        trackData.append(contentsOf: variableLengthQuantity(0))
        trackData.append(0xFF)
        trackData.append(0x2F)
        trackData.append(0x00)

        data.append(contentsOf: UInt32(trackData.count).bigEndianBytes)
        data.append(trackData)

        return data
    }

    private static func variableLengthQuantity(_ value: UInt32) -> [UInt8] {
        var result: [UInt8] = []
        var v = value
        repeat {
            var byte = UInt8(v & 0x7F)
            v >>= 7
            if !result.isEmpty { byte |= 0x80 }
            result.insert(byte, at: 0)
        } while v > 0
        if result.isEmpty { result = [0] }
        return result
    }

    // MARK: - Stem Operations (DSP-lite)

    private struct WAVPCM { let samples: [Float]; let sampleRate: Int }

    /// Read uncompressed 16-bit PCM WAV (mono or stereo) into mono Float samples.
    private static func readWAVPCM(_ data: Data) -> WAVPCM? {
        guard data.count > 44 else { return nil }
        let bytes = [UInt8](data)
        func ascii(_ range: Range<Int>) -> String { String(bytes: bytes[range], encoding: .ascii) ?? "" }
        guard ascii(0..<4) == "RIFF", ascii(8..<12) == "WAVE" else { return nil }
        func u16(_ offset: Int) -> Int { Int(bytes[offset]) | (Int(bytes[offset + 1]) << 8) }
        func u32(_ offset: Int) -> Int { Int(bytes[offset]) | (Int(bytes[offset + 1]) << 8) | (Int(bytes[offset + 2]) << 16) | (Int(bytes[offset + 3]) << 24) }
        var offset = 12
        var sampleRate = 44100
        var channels = 1
        var bits = 16
        var pcmStart = -1
        var pcmCount = 0
        while offset + 8 <= bytes.count {
            let id = ascii(offset..<(offset + 4))
            let size = u32(offset + 4)
            if id == "fmt " {
                channels = u16(offset + 10)
                sampleRate = u32(offset + 12)
                bits = u16(offset + 22)
            } else if id == "data" {
                pcmStart = offset + 8
                pcmCount = min(size, bytes.count - pcmStart)
                break
            }
            offset += 8 + size + (size % 2)
        }
        guard pcmStart >= 0, bits == 16, channels == 1 || channels == 2 else { return nil }
        let frames = pcmCount / (2 * channels)
        var samples: [Float] = []
        samples.reserveCapacity(frames)
        for i in 0..<frames {
            let base = pcmStart + i * 2 * channels
            func sample(_ ch: Int) -> Float {
                let o = base + ch * 2
                let v = Int16(bitPattern: UInt16(bytes[o]) | (UInt16(bytes[o + 1]) << 8))
                return Float(v) / 32768.0
            }
            samples.append(channels == 1 ? sample(0) : (sample(0) + sample(1)) * 0.5)
        }
        return WAVPCM(samples: samples, sampleRate: sampleRate)
    }

    private static func onePoleLowPass(_ x: [Float], cutoff: Double, sampleRate: Int) -> [Float] {
        guard !x.isEmpty else { return [] }
        let rc = 1.0 / (2.0 * Double.pi * max(cutoff, 1.0))
        let dt = 1.0 / Double(max(sampleRate, 1))
        let alpha = Float(dt / (rc + dt))
        var y = x
        var prev = x[0]
        for i in x.indices {
            prev = prev + alpha * (x[i] - prev)
            y[i] = prev
        }
        return y
    }

    private static func sub(_ a: [Float], _ b: [Float]) -> [Float] {
        zip(a, b).map { max(-1, min(1, $0.0 - $0.1)) }
    }

    private static func gain(_ x: [Float], _ g: Float) -> [Float] { x.map { max(-1, min(1, $0 * g)) } }

    /// Split audio into useful frequency-band stems with real one-pole DSP filtering.
    /// This is not ML source separation, but it is deterministic local DSP rather than a mock.
    static func splitStems(wavData: Data) -> [String: Data] {
        guard let pcm = readWAVPCM(wavData) else { return ["full": wavData] }
        let bass = onePoleLowPass(pcm.samples, cutoff: 180, sampleRate: pcm.sampleRate)
        let lowMid = onePoleLowPass(pcm.samples, cutoff: 900, sampleRate: pcm.sampleRate)
        let mids = sub(lowMid, bass)
        let air = sub(pcm.samples, lowMid)
        let drums = gain(sub(pcm.samples, onePoleLowPass(pcm.samples, cutoff: 60, sampleRate: pcm.sampleRate)), 0.9)
        let vocals = gain(sub(pcm.samples, bass), 0.65)
        let sr = pcm.sampleRate
        return [
            "full": wavData,
            "bass": writeWAVData(samples: bass, sampleRate: sr),
            "vocals_band": writeWAVData(samples: vocals, sampleRate: sr),
            "drums_transient": writeWAVData(samples: drums, sampleRate: sr),
            "mids": writeWAVData(samples: mids, sampleRate: sr),
            "air": writeWAVData(samples: air, sampleRate: sr)
        ]
    }

    /// Create a stem mix by summing decoded PCM stems with per-stem gain.
    static func mixStems(stems: [(data: Data, volume: Float)]) -> Data? {
        var mixed: [Float] = []
        var sampleRate = 44100
        for (data, volume) in stems {
            guard let pcm = readWAVPCM(data) else { continue }
            sampleRate = pcm.sampleRate
            if mixed.count < pcm.samples.count { mixed.append(contentsOf: repeatElement(0, count: pcm.samples.count - mixed.count)) }
            for i in pcm.samples.indices { mixed[i] = max(-1, min(1, mixed[i] + pcm.samples[i] * volume)) }
        }
        guard !mixed.isEmpty else { return nil }
        return writeWAVData(samples: mixed, sampleRate: sampleRate)
    }
}

// MARK: - Byte Helpers

private extension UInt32 {
    var littleEndianBytes: [UInt8] {
        [UInt8(self & 0xFF), UInt8((self >> 8) & 0xFF), UInt8((self >> 16) & 0xFF), UInt8((self >> 24) & 0xFF)]
    }
    var bigEndianBytes: [UInt8] {
        [UInt8((self >> 24) & 0xFF), UInt8((self >> 16) & 0xFF), UInt8((self >> 8) & 0xFF), UInt8(self & 0xFF)]
    }
}

private extension UInt16 {
    var littleEndianBytes: [UInt8] {
        [UInt8(self & 0xFF), UInt8((self >> 8) & 0xFF)]
    }
    var bigEndianBytes: [UInt8] {
        [UInt8((self >> 8) & 0xFF), UInt8(self & 0xFF)]
    }
}

private extension Int16 {
    var littleEndianBytes: [UInt8] {
        let u = UInt16(bitPattern: self)
        return u.littleEndianBytes
    }
}
