import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// A file the assistant generated for the user (song, document, data file, zip, …).
/// Saved into the app's Artifacts folder (visible in the Files app) and attachable to chat.
struct Artifact: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var relativePath: String        // path from app root, e.g. "Artifacts/song.wav"
    var kind: String                // "wav", "midi", "zip", "text", "csv", "json", …
    var byteSize: Int64 = 0
    var createdAt = Date()

    var sizeDisplay: String { ByteCountFormatter.string(fromByteCount: byteSize, countStyle: .file) }
}

/// Registry of generated artifacts. `lastArtifact` lets the chat loop attach the most
/// recent creation to a message bubble.
final class ArtifactStore: ObservableObject {
    static let shared = ArtifactStore()
    @Published private(set) var items: [Artifact] = []
    @Published var lastArtifact: Artifact?
    private let file = "artifacts.json"

    private init() {
        items = FileStore.shared.read([Artifact].self, from: file, in: FileStore.shared.chatDir) ?? []
    }

    func add(_ a: Artifact) {
        items.insert(a, at: 0)
        lastArtifact = a
        save()
    }

    func remove(_ a: Artifact) {
        try? FileManager.default.removeItem(at: FileStore.shared.url(forRelative: a.relativePath))
        items.removeAll { $0.id == a.id }
        save()
    }

    private func save() { FileStore.shared.write(items, to: file, in: FileStore.shared.chatDir) }
}

/// A tappable chip that shares/opens a generated artifact file.
struct ArtifactChip: View {
    let name: String
    let relativePath: String
    @State private var showShare = false

    private var url: URL { FileStore.shared.url(forRelative: relativePath) }

    var body: some View {
        Button { showShare = true } label: {
            HStack(spacing: 8) {
                Image(systemName: icon).font(.system(size: 15))
                VStack(alignment: .leading, spacing: 1) {
                    Text(name).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                        .lineLimit(1)
                    Text("Tap to download / share").font(.system(size: 10)).foregroundStyle(.white.opacity(0.5))
                }
                Spacer(minLength: 4)
                Image(systemName: "square.and.arrow.up").font(.system(size: 13)).foregroundStyle(Glass.accent2)
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.06)))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.12), lineWidth: 1))
        }
        .buttonStyle(.plain)
        #if canImport(UIKit)
        .sheet(isPresented: $showShare) { ShareSheet(items: [url]) }
        #endif
    }

    private var icon: String {
        let ext = (name as NSString).pathExtension.lowercased()
        switch ext {
        case "wav", "mp3", "aac", "m4a": return "waveform"
        case "mid", "midi": return "pianokeys"
        case "zip": return "doc.zipper"
        case "csv": return "tablecells"
        case "json": return "curlybraces"
        case "png", "jpg", "jpeg": return "photo"
        default: return "doc.text"
        }
    }
}

/// Inline audio player for generated audio artifacts: play/pause, −10s/+10s skip,
/// scrubbing and share. Appears right inside the chat bubble.
struct AudioArtifactPlayer: View {
    let name: String
    let relativePath: String
    @StateObject private var player = VinnyPlayer()
    @State private var showShare = false
    @State private var loadFailed = false

    private var url: URL { FileStore.shared.url(forRelative: relativePath) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "waveform").foregroundStyle(Glass.accent2)
                Text(name).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                Spacer()
                Button { showShare = true } label: {
                    Image(systemName: "square.and.arrow.up").font(.system(size: 13)).foregroundStyle(Glass.accent2)
                }.buttonStyle(.plain)
            }
            if loadFailed {
                Text("Couldn't load this audio file.").font(.system(size: 11)).foregroundStyle(Glass.sell.opacity(0.8))
            } else {
                HStack(spacing: 14) {
                    Button { player.skip(by: -10) } label: {
                        Image(systemName: "gobackward.10").font(.system(size: 17)).foregroundStyle(.white.opacity(0.85))
                    }.buttonStyle(.plain)
                    Button { player.isPlaying ? player.pause() : player.play() } label: {
                        Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 32)).foregroundStyle(Glass.accent2)
                    }.buttonStyle(.plain)
                    Button { player.skip(by: 10) } label: {
                        Image(systemName: "goforward.10").font(.system(size: 17)).foregroundStyle(.white.opacity(0.85))
                    }.buttonStyle(.plain)
                    VStack(spacing: 2) {
                        Slider(value: Binding(get: { player.currentTime }, set: { player.seek(to: $0) }), in: 0...max(player.duration, 0.1))
                            .tint(Glass.accent)
                        HStack {
                            Text(fmt(player.currentTime))
                            Spacer()
                            Text(fmt(player.duration))
                        }
                        .font(.system(size: 9, design: .monospaced)).foregroundStyle(.white.opacity(0.5))
                    }
                }
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.12), lineWidth: 1))
        .onAppear {
            guard let data = try? Data(contentsOf: url), !data.isEmpty else { loadFailed = true; return }
            player.load(data: data, name: name)
            if player.duration <= 0 { loadFailed = true }
        }
        #if canImport(UIKit)
        .sheet(isPresented: $showShare) { ShareSheet(items: [url]) }
        #endif
    }

    private func fmt(_ t: Double) -> String { String(format: "%d:%02d", Int(t) / 60, Int(t) % 60) }
}

#if canImport(UIKit)
/// UIActivityViewController wrapper (share / save-to-Files) — works on iOS 15+.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
#endif
