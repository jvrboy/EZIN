import Foundation

/// Chat-side VINNY state: keeps the last generated loop/patch so follow-up commands
/// ("now export the stems", "make a variation") chain naturally across messages.
@MainActor
final class VinnyChatState {
    static let shared = VinnyChatState()
    var lastLoop: LoopResult?
    var lastPatch: VinnyPatch?
    var lastReferenceAnalysis: String?
    private init() {}
}

/// VINNY chat tools — the full sound engine, driven from the chat tab.
extension ToolRegistry {

    // MARK: helpers

    private func registerArtifact(data: Data, name: String, ext: String) -> Artifact {
        let safe = name.replacingOccurrences(of: "[^A-Za-z0-9._-]", with: "-", options: .regularExpression)
        let url = FileStore.shared.saveData(data, name: safe, in: FileStore.shared.artifactsDir)
        let artifact = Artifact(name: safe, relativePath: FileStore.shared.relativePath(url), kind: ext, byteSize: Int64(data.count))
        ArtifactStore.shared.add(artifact)
        return artifact
    }

    /// Find an audio artifact by (fuzzy) name, or fall back to the most recent audio upload.
    private func findAudioArtifact(named name: String) -> (Artifact, Data)? {
        let audioExts = ["wav", "mp3", "m4a", "aif", "aiff", "caf"]
        let items = ArtifactStore.shared.items.filter { audioExts.contains($0.kind.lowercased()) }
        let q = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let pick: Artifact?
        if q.isEmpty {
            pick = items.first
        } else {
            pick = items.first(where: { $0.name.lowercased() == q })
                ?? items.first(where: { $0.name.lowercased().contains(q) })
        }
        guard let artifact = pick else { return nil }
        let url = FileStore.shared.url(forRelative: artifact.relativePath)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return (artifact, data)
    }

    // MARK: vinny_loop — "create me a loop"

    func vinnyLoopTool(_ args: [String: Any]) async -> String {
        let prompt = str(args, "prompt").isEmpty ? str(args, "style") : str(args, "prompt")
        guard !prompt.isEmpty else { return "Give me a style, e.g. \"dusty lo-fi loop, 80 bpm, A minor\"." }
        let bars = max(1, min(16, (args["bars"] as? Int) ?? Int(str(args, "bars")) ?? 4))
        let variation = max(0, min(50, (args["variation"] as? Int) ?? Int(str(args, "variation")) ?? 0))

        let patch = GenesisEngine.patch(fromText: prompt, seed: UInt64(Date().timeIntervalSince1970))
        let result: LoopResult = await Task.detached(priority: .userInitiated) {
            LoopFactory.makeLoop(patch: patch, bars: bars, seed: UInt64(abs(prompt.hashValue) % 100000 &+ UInt64(variation &* 977)), variation: variation)
        }.value

        VinnyChatState.shared.lastLoop = result
        VinnyChatState.shared.lastPatch = patch
        VinnyStore.shared.savePreset(patch)

        registerArtifact(data: result.midi, name: "\(patch.name).mid", ext: "mid")
        let audio = registerArtifact(data: result.wav, name: "\(patch.name).wav", ext: "wav")
        ArtifactStore.shared.lastArtifact = audio   // the bubble attaches the audio (inline player)

        return """
        **VINNY Loop Factory** built your loop:
        • Style: \(patch.genre) · \(Int(result.bpm)) BPM · \(result.key) \(result.scale)
        • \(bars) bars, \(result.notes.count) notes (drums + bass + chords + lead, all scale-locked)
        • Saved patch "\(patch.name)" to the VINNY Vault.
        Attached: \(audio.name) (WAV, playable right here with skip/rewind) + the MIDI file.
        Say **"export stems"** for the STEMS ZIP, or **"make a variation"** for another take.
        """
    }

    // MARK: vinny_patch — "grow a patch from words"

    func vinnyPatchTool(_ args: [String: Any]) async -> String {
        let prompt = str(args, "prompt")
        guard !prompt.isEmpty else { return "Describe the sound, e.g. \"warm analog bass with a metallic tail\"." }
        let patch = GenesisEngine.patch(fromText: prompt, seed: UInt64(Date().timeIntervalSince1970))
        VinnyChatState.shared.lastPatch = patch
        VinnyStore.shared.savePreset(patch)

        let wav: Data = await Task.detached(priority: .userInitiated) {
            let beat = 60.0 / patch.bpm
            var notes: [VinnyDSP.VinnyNote] = []
            for (i, deg) in [0, 2, 4, 7, 4, 2].enumerated() {
                notes.append(VinnyDSP.VinnyNote(midi: TheoryEngine.degreeToMidi(deg, octave: 4, key: patch.key, scale: patch.scale), start: Double(i) * beat * 0.5, duration: beat * 0.48, velocity: 0.8, lane: 0))
            }
            return VinnyRenderer.renderWAV(patch: patch, notes: notes, durationSec: beat * 3.2)
        }.value

        let audio = registerArtifact(data: wav, name: "\(patch.name)-preview.wav", ext: "wav")
        ArtifactStore.shared.lastArtifact = audio
        return """
        **VINNY Genesis** grew "\(patch.name)":
        • \(patch.genre) · \(patch.key) \(patch.scale) · \(Int(patch.bpm)) BPM · cutoff \(Int(patch.filterCutoff)) Hz
        • \(patch.unisonVoices) voices, \(patch.fx.map { $0.kind.label }.joined(separator: " + "))
        Attached: a playable preview. Find the editable patch in Games → VINNY → Vault.
        """
    }

    // MARK: vinny_reference — "here's a reference track, make something like it"

    func vinnyReferenceTool(_ args: [String: Any]) async -> String {
        let name = str(args, "file").isEmpty ? str(args, "name") : str(args, "file")
        guard let (artifact, data) = findAudioArtifact(named: name) else {
            return "I couldn't find an audio file in Artifacts. Upload a WAV into chat first (paperclip → pick file), then say \"make a loop like this\"."
        }
        guard let pcm = VinnyDSP.readWAV(data) else {
            return "\"\(artifact.name)\" isn't 16-bit PCM WAV — Earprint can't read mp3/m4a on-device. Convert it to WAV and upload again."
        }

        let analysis: (bpm: Double, key: String, scale: String, centroid: Double, patch: VinnyPatch?) = await Task.detached(priority: .userInitiated) {
            let x = pcm.mono
            let bpm = VinnyDSP.estimateBPM(x, sampleRate: pcm.sampleRate)
            let key = VinnyDSP.detectKey(x, sampleRate: pcm.sampleRate)
            let centroid = VinnyDSP.spectralCentroid(x, sampleRate: pcm.sampleRate)
            let patch = GenesisEngine.patch(fromAudio: data)
            return (bpm, key.key, key.scale, centroid, patch)
        }.value

        guard var patch = analysis.patch else { return "Analysis failed on \"\(artifact.name)\" — file may be too short." }
        patch.name = "Like \(artifact.name.replacingOccurrences(of: ".\(artifact.kind)", with: ""))"
        VinnyChatState.shared.lastPatch = patch
        VinnyStore.shared.savePreset(patch)

        let result: LoopResult = await Task.detached(priority: .userInitiated) {
            LoopFactory.makeLoop(patch: patch, bars: 4, seed: UInt64(abs(artifact.name.hashValue) % 100000))
        }.value
        VinnyChatState.shared.lastLoop = result

        registerArtifact(data: result.midi, name: "\(patch.name).mid", ext: "mid")
        let audio = registerArtifact(data: result.wav, name: "\(patch.name).wav", ext: "wav")
        ArtifactStore.shared.lastArtifact = audio

        return """
        **VINNY Earprint** decoded "\(artifact.name)":
        • ~\(String(format: "%.1f", analysis.bpm)) BPM · \(analysis.key) \(analysis.scale) · brightness \(Int(analysis.centroid)) Hz
        • Rebuilt it as patch "\(patch.name)" and generated a **new loop in the same character** (attached, playable here).
        Say **"export stems"** for the STEMS ZIP.
        """
    }

    // MARK: vinny_stems — real stems ZIP (drums / bass / chords / lead + mix + MIDI)

    func vinnyStemsTool(_ args: [String: Any]) async -> String {
        var loop = VinnyChatState.shared.lastLoop
        if loop == nil {
            // Generate one on the spot so the tool always delivers.
            let patch = VinnyChatState.shared.lastPatch ?? VinnyPatch.default
            let fresh: LoopResult = await Task.detached(priority: .userInitiated) {
                LoopFactory.makeLoop(patch: patch, bars: 4, seed: 7)
            }.value
            loop = fresh
            VinnyChatState.shared.lastLoop = fresh
            VinnyChatState.shared.lastPatch = patch
        }
        guard let result = loop else { return "Couldn't build stems right now." }
        let baseName = (VinnyChatState.shared.lastPatch?.name ?? "vinny-loop")

        var entries: [ZipWriter.Entry] = []
        for (stem, data) in result.stems.sorted(by: { $0.key < $1.key }) {
            entries.append(ZipWriter.Entry(name: "\(baseName)/stems/\(stem).wav", data: data))
        }
        entries.append(ZipWriter.Entry(name: "\(baseName)/full-mix.wav", data: result.wav))
        entries.append(ZipWriter.Entry(name: "\(baseName)/loop.mid", data: result.midi))
        if let patch = VinnyChatState.shared.lastPatch, let json = try? JSONEncoder().encode(patch) {
            entries.append(ZipWriter.Entry(name: "\(baseName)/patch.vinnypatch.json", data: json))
        }
        guard let zip = ZipWriter.makeZip(entries: entries) else { return "ZIP build failed." }
        let artifact = registerArtifact(data: zip, name: "\(baseName)-STEMS.zip", ext: "zip")
        ArtifactStore.shared.lastArtifact = artifact
        return """
        **VINNY STEMS ZIP** for "\(baseName)":
        • stems/drums.wav · stems/bass.wav · stems/chords.wav · stems/lead.wav
        • full-mix.wav · loop.mid · patch.vinnypatch.json (importable in VINNY → Vault)
        Attached: \(artifact.name).
        """
    }

    // MARK: vinny_library — what's in the Vault

    func vinnyLibraryTool(_ args: [String: Any]) -> String {
        let presets = VinnyStore.shared.presets
        guard !presets.isEmpty else { return "The VINNY Vault is empty — ask me to grow a patch or a loop first." }
        var s = "**VINNY Vault** — \(presets.count) presets:\n"
        for p in presets.prefix(12) {
            s += "• \(p.name) — \(p.genre), \(p.key) \(p.scale), \(Int(p.bpm)) BPM (v\(p.version))\n"
        }
        if let loop = VinnyChatState.shared.lastLoop {
            s += "\nLast loop: \(loop.genre), \(Int(loop.bpm)) BPM, \(loop.key) \(loop.scale) — say \"export stems\" for its ZIP."
        }
        s += "\nOpen Games → VINNY for the full workstation (Genesis, WaveForge, Earprint, Stage…)."
        return s
    }
}
