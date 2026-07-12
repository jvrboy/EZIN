import Foundation

/// Manages the app's own on-device directory tree. Because UIFileSharingEnabled and
/// LSSupportsOpeningDocumentsInPlace are set, this directory is visible under
/// "On My iPhone → EZIN" in the Files app. All app data is persisted here automatically.
final class FileStore {
    static let shared = FileStore()
    private init() {}

    let fm = FileManager.default

    var documents: URL {
        fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
    var root: URL { documents }                             // EZIN app container root
    var modelsDir: URL { root.appendingPathComponent("Models", isDirectory: true) }
    var dataDir: URL { root.appendingPathComponent("Data", isDirectory: true) }
    var pipelinesDir: URL { root.appendingPathComponent("Pipelines", isDirectory: true) }
    var logsDir: URL { root.appendingPathComponent("Logs", isDirectory: true) }

    /// Create the directory structure on first launch.
    func bootstrap() {
        for dir in [modelsDir, dataDir, pipelinesDir, logsDir] {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        // Drop a readme so the folder is obvious inside Files.
        let readme = root.appendingPathComponent("README.txt")
        if !fm.fileExists(atPath: readme.path) {
            try? "EZIN app data. Models/, Data/, Pipelines/, Logs/ are managed automatically."
                .write(to: readme, atomically: true, encoding: .utf8)
        }
    }

    func write<T: Encodable>(_ value: T, to name: String, in dir: URL) {
        let url = dir.appendingPathComponent(name)
        if let data = try? JSONEncoder().encode(value) { try? data.write(to: url) }
    }

    func read<T: Decodable>(_ type: T.Type, from name: String, in dir: URL) -> T? {
        let url = dir.appendingPathComponent(name)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    /// Copy an imported file (security-scoped) into the Models directory. No size limit.
    @discardableResult
    func importModel(from source: URL) throws -> LLMModel {
        let needsScope = source.startAccessingSecurityScopedResource()
        defer { if needsScope { source.stopAccessingSecurityScopedResource() } }

        let fileName = source.lastPathComponent
        let dest = modelsDir.appendingPathComponent(fileName)
        if fm.fileExists(atPath: dest.path) { try? fm.removeItem(at: dest) }
        try fm.copyItem(at: source, to: dest)

        let attrs = try? fm.attributesOfItem(atPath: dest.path)
        let size = (attrs?[.size] as? NSNumber)?.int64Value ?? 0
        let ext = source.pathExtension.lowercased()
        return LLMModel(name: source.deletingPathExtension().lastPathComponent,
                        fileName: fileName,
                        relativePath: "Models/\(fileName)",
                        byteSize: size,
                        format: ext.isEmpty ? "bin" : ext,
                        importedAt: Date())
    }

    func deleteModel(_ model: LLMModel) {
        let url = root.appendingPathComponent(model.relativePath)
        try? fm.removeItem(at: url)
    }
}
