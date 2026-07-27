import Foundation

/// Manages the app's own on-device directory tree. Because UIFileSharingEnabled and
/// LSSupportsOpeningDocumentsInPlace are set, this directory is visible under
/// "On My iPhone → EZIN" in the Files app. All app data is persisted here automatically.
enum FileStoreError: Error, LocalizedError {
    case unsupportedModelFormat
    case modelTooLarge
    case invalidRelativePath

    var errorDescription: String? {
        switch self {
        case .unsupportedModelFormat: return "Unsupported model format. Import GGUF, SafeTensors, or BIN."
        case .modelTooLarge: return "The model exceeds the 16 GB import limit."
        case .invalidRelativePath: return "The requested file path is outside the EZIN container."
        }
    }
}

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
    var chatDir: URL { root.appendingPathComponent("Chat", isDirectory: true) }
    var projectsDir: URL { root.appendingPathComponent("Projects", isDirectory: true) }
    var artifactsDir: URL { root.appendingPathComponent("Artifacts", isDirectory: true) }

    /// Create the directory structure on first launch.
    func bootstrap() {
        for dir in [modelsDir, dataDir, pipelinesDir, logsDir, chatDir, projectsDir, artifactsDir] {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        // Drop a readme so the folder is obvious inside Files.
        let readme = root.appendingPathComponent("README.txt")
        if !fm.fileExists(atPath: readme.path) {
            try? "EZIN app data. Models/, Data/, Pipelines/, Logs/ are managed automatically."
                .write(to: readme, atomically: true, encoding: .utf8)
        }
    }

    @discardableResult
    func write<T: Encodable>(_ value: T, to name: String, in dir: URL) -> Bool {
        let url = dir.appendingPathComponent(name)
        guard let data = try? JSONEncoder().encode(value) else { return false }
        do {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    func read<T: Decodable>(_ type: T.Type, from name: String, in dir: URL) -> T? {
        let url = dir.appendingPathComponent(name)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    // MARK: - Generic data / artifacts

    /// Absolute URL for a path relative to the app root (e.g. "Artifacts/song.wav").
    func url(forRelative rel: String) -> URL { root.appendingPathComponent(rel) }

    /// Resolve only paths that remain inside the app container. Files and imported
    /// JSON are user-visible, so never trust `../` components from persisted data.
    func validatedURL(forRelative rel: String) -> URL? {
        let base = root.standardizedFileURL.path
        let candidate = root.appendingPathComponent(rel).standardizedFileURL
        guard candidate.path == base || candidate.path.hasPrefix(base + "/") else { return nil }
        return candidate
    }

    /// Write raw data into a directory, returning the created file URL.
    @discardableResult
    func saveData(_ data: Data, name: String, in dir: URL) -> URL {
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(name)
        try? data.write(to: url, options: .atomic)
        return url
    }

    /// Relative path (from app root) for a URL, for compact persistence.
    func relativePath(_ url: URL) -> String {
        url.path.replacingOccurrences(of: root.path + "/", with: "")
    }

    /// Ensure a project's folder exists and return it.
    @discardableResult
    func projectFolder(_ project: ChatProject) -> URL {
        let dir = projectsDir.appendingPathComponent(project.folderName, isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func deleteProjectFolder(_ project: ChatProject) {
        try? fm.removeItem(at: projectsDir.appendingPathComponent(project.folderName, isDirectory: true))
    }

    func fileSize(atRelative rel: String) -> Int64 {
        guard let safe = validatedURL(forRelative: rel) else { return 0 }
        let attrs = try? fm.attributesOfItem(atPath: safe.path)
        return (attrs?[.size] as? NSNumber)?.int64Value ?? 0
    }

    /// Copy a supported model file (security-scoped) into the Models directory with a
    /// bounded size so an accidental import cannot exhaust app storage.
    @discardableResult
    func importModel(from source: URL) throws -> LLMModel {
        let needsScope = source.startAccessingSecurityScopedResource()
        defer { if needsScope { source.stopAccessingSecurityScopedResource() } }

        let ext = source.pathExtension.lowercased()
        guard ["gguf", "safetensors", "bin"].contains(ext) else {
            throw FileStoreError.unsupportedModelFormat
        }
        let sourceSize = (try? source.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard sourceSize <= 16 * 1024 * 1024 * 1024 else {
            throw FileStoreError.modelTooLarge
        }

        let fileName = source.lastPathComponent
        let dest = modelsDir.appendingPathComponent(fileName)
        if fm.fileExists(atPath: dest.path) { try? fm.removeItem(at: dest) }
        try fm.copyItem(at: source, to: dest)

        let attrs = try? fm.attributesOfItem(atPath: dest.path)
        let size = (attrs?[.size] as? NSNumber)?.int64Value ?? 0
        return LLMModel(name: source.deletingPathExtension().lastPathComponent,
                        fileName: fileName,
                        relativePath: "Models/\(fileName)",
                        byteSize: size,
                        format: ext.isEmpty ? "bin" : ext,
                        importedAt: Date())
    }

    func deleteModel(_ model: LLMModel) {
        guard let url = validatedURL(forRelative: model.relativePath) else { return }
        try? fm.removeItem(at: url)
    }

    // MARK: - Raw data helpers

    @discardableResult
    func writeRaw(_ data: Data, to name: String, in dir: URL) -> Bool {
        let url = dir.appendingPathComponent(name)
        do {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    func readRaw(from name: String, in dir: URL) -> Data? {
        let url = dir.appendingPathComponent(name)
        return try? Data(contentsOf: url)
    }
}
