import Foundation

/// A path-confined workspace for assistant-created files.
///
/// iOS does not permit arbitrary process execution inside an App Store application, so this
/// service intentionally provides file-system capabilities rather than pretending to be a host
/// shell. Computation that requires a real runtime can be delegated to an explicitly configured
/// MCP executor; all local files remain under `Documents/EZIN/AgentWorkspace`.
actor AgentWorkspace {
    static let shared = AgentWorkspace()

    struct Entry: Codable, Sendable {
        let path: String
        let isDirectory: Bool
        let byteSize: Int64
        let modifiedAt: Date?
    }

    enum WorkspaceError: Error, LocalizedError {
        case invalidPath
        case fileTooLarge(Int)
        case workspaceQuotaExceeded
        case notFound
        case isDirectory
        case unreadable

        var errorDescription: String? {
            switch self {
            case .invalidPath: return "The workspace path is invalid or escapes the workspace root."
            case .fileTooLarge(let limit): return "The file exceeds the \(limit)-byte workspace file limit."
            case .workspaceQuotaExceeded: return "The agent workspace has reached its storage quota."
            case .notFound: return "The workspace item was not found."
            case .isDirectory: return "The requested workspace item is a directory."
            case .unreadable: return "The workspace item could not be read."
            }
        }
    }

    private let manager = FileManager.default
    private let maxFileBytes = 5 * 1024 * 1024
    private let maxReadBytes = 512 * 1024
    private let maxWorkspaceBytes: Int64 = 50 * 1024 * 1024
    private let root: URL

    private init() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        root = documents.appendingPathComponent("EZIN/AgentWorkspace", isDirectory: true).standardizedFileURL
        try? manager.createDirectory(at: root, withIntermediateDirectories: true)
    }

    @discardableResult
    func write(path: String, data: Data, overwrite: Bool = true) throws -> Entry {
        guard data.count <= maxFileBytes else { throw WorkspaceError.fileTooLarge(maxFileBytes) }
        let destination = try validatedURL(for: path, allowRoot: false)
        if manager.fileExists(atPath: destination.path), !overwrite {
            throw CocoaError(.fileWriteFileExists)
        }

        let existingSize = ((try? destination.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        let projected = try totalByteSize() - Int64(existingSize) + Int64(data.count)
        guard projected <= maxWorkspaceBytes else { throw WorkspaceError.workspaceQuotaExceeded }

        try manager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: destination, options: .atomic)
        return try entry(for: destination)
    }

    @discardableResult
    func writeText(path: String, content: String, overwrite: Bool = true) throws -> Entry {
        guard let data = content.data(using: .utf8) else { throw WorkspaceError.unreadable }
        return try write(path: path, data: data, overwrite: overwrite)
    }

    func read(path: String) throws -> Data {
        let source = try validatedURL(for: path, allowRoot: false)
        var isDirectory: ObjCBool = false
        guard manager.fileExists(atPath: source.path, isDirectory: &isDirectory) else { throw WorkspaceError.notFound }
        guard !isDirectory.boolValue else { throw WorkspaceError.isDirectory }
        let size = (try? source.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard size <= maxReadBytes else { throw WorkspaceError.fileTooLarge(maxReadBytes) }
        return try Data(contentsOf: source, options: .mappedIfSafe)
    }

    func readText(path: String) throws -> String {
        let data = try read(path: path)
        guard let value = String(data: data, encoding: .utf8) else { throw WorkspaceError.unreadable }
        return value
    }

    func list(path: String = "", recursive: Bool = true, limit: Int = 200) throws -> [Entry] {
        let directory = try validatedURL(for: path, allowRoot: true)
        var isDirectory: ObjCBool = false
        guard manager.fileExists(atPath: directory.path, isDirectory: &isDirectory) else { throw WorkspaceError.notFound }
        guard isDirectory.boolValue else { return [try entry(for: directory)] }

        let keys: [URLResourceKey] = [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey, .isHiddenKey]
        guard let enumerator = manager.enumerator(
            at: directory,
            includingPropertiesForKeys: keys,
            options: recursive ? [.skipsHiddenFiles] : [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
        ) else { return [] }

        var result: [Entry] = []
        while let url = enumerator.nextObject() as? URL, result.count < max(1, min(limit, 1_000)) {
            result.append(try entry(for: url))
        }
        return result.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    func delete(path: String) throws {
        let target = try validatedURL(for: path, allowRoot: false)
        guard manager.fileExists(atPath: target.path) else { throw WorkspaceError.notFound }
        try manager.removeItem(at: target)
    }

    func totalByteSize() throws -> Int64 {
        guard let enumerator = manager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }
        var total: Int64 = 0
        while let url = enumerator.nextObject() as? URL {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            if values.isRegularFile == true { total += Int64(values.fileSize ?? 0) }
        }
        return total
    }

    private func validatedURL(for relativePath: String, allowRoot: Bool) throws -> URL {
        let trimmed = relativePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard allowRoot || !trimmed.isEmpty else { throw WorkspaceError.invalidPath }
        guard !trimmed.hasPrefix("/") && !trimmed.contains("\0") else { throw WorkspaceError.invalidPath }

        let resolvedRoot = root.resolvingSymlinksInPath().standardizedFileURL
        let candidate = root.appendingPathComponent(trimmed, isDirectory: false).standardizedFileURL
        let resolvedCandidate = candidate.resolvingSymlinksInPath().standardizedFileURL
        let rootPath = resolvedRoot.path.hasSuffix("/") ? resolvedRoot.path : resolvedRoot.path + "/"
        guard resolvedCandidate.path == resolvedRoot.path || resolvedCandidate.path.hasPrefix(rootPath) else {
            throw WorkspaceError.invalidPath
        }
        guard allowRoot || resolvedCandidate.path != resolvedRoot.path else { throw WorkspaceError.invalidPath }
        return resolvedCandidate
    }

    private func entry(for url: URL) throws -> Entry {
        let values = try url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey])
        let rootPrefix = root.path.hasSuffix("/") ? root.path : root.path + "/"
        let relative = url.path.hasPrefix(rootPrefix) ? String(url.path.dropFirst(rootPrefix.count)) : ""
        return Entry(
            path: relative,
            isDirectory: values.isDirectory ?? false,
            byteSize: Int64(values.fileSize ?? 0),
            modifiedAt: values.contentModificationDate
        )
    }
}
