import XCTest
@testable import EZIN

final class AgentWorkspaceTests: XCTestCase {
    func testWorkspaceRoundTripAndDelete() async throws {
        let directory = "tests-\(UUID().uuidString)"
        let path = "\(directory)/nested/note.md"
        defer { Task { try? await AgentWorkspace.shared.delete(path: directory) } }

        let created = try await AgentWorkspace.shared.writeText(path: path, content: "# EZIN\nworkspace")
        XCTAssertEqual(created.path, path)
        XCTAssertFalse(created.isDirectory)

        let content = try await AgentWorkspace.shared.readText(path: path)
        XCTAssertEqual(content, "# EZIN\nworkspace")

        let entries = try await AgentWorkspace.shared.list(path: directory)
        XCTAssertTrue(entries.contains { $0.path == path })

        try await AgentWorkspace.shared.delete(path: path)
        do {
            _ = try await AgentWorkspace.shared.read(path: path)
            XCTFail("Deleted file should not be readable")
        } catch AgentWorkspace.WorkspaceError.notFound {
            // Expected.
        }
    }

    func testWorkspaceRejectsTraversalAndAbsolutePaths() async {
        for path in ["../escape.txt", "/tmp/escape.txt", "folder/../../escape.txt"] {
            do {
                _ = try await AgentWorkspace.shared.writeText(path: path, content: "blocked")
                XCTFail("Workspace accepted unsafe path: \(path)")
            } catch AgentWorkspace.WorkspaceError.invalidPath {
                // Expected.
            } catch {
                XCTFail("Unexpected error for \(path): \(error)")
            }
        }
    }

    func testWorkspaceHonorsNoOverwrite() async throws {
        let directory = "tests-\(UUID().uuidString)"
        let path = "\(directory)/unique.txt"
        defer { Task { try? await AgentWorkspace.shared.delete(path: directory) } }

        _ = try await AgentWorkspace.shared.writeText(path: path, content: "first")
        do {
            _ = try await AgentWorkspace.shared.writeText(path: path, content: "second", overwrite: false)
            XCTFail("Expected a file-exists error")
        } catch {
            // Expected; the original contents must remain intact.
        }
        XCTAssertEqual(try await AgentWorkspace.shared.readText(path: path), "first")
    }

    func testWorkspaceRejectsSymlinkEscape() async throws {
        let manager = FileManager.default
        let documents = manager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let root = documents.appendingPathComponent("EZIN/AgentWorkspace", isDirectory: true)
        let linkName = "link-\(UUID().uuidString)"
        let link = root.appendingPathComponent(linkName)
        let outside = manager.temporaryDirectory.appendingPathComponent("outside-\(UUID().uuidString)", isDirectory: true)
        try manager.createDirectory(at: root, withIntermediateDirectories: true)
        try manager.createDirectory(at: outside, withIntermediateDirectories: true)
        try manager.createSymbolicLink(at: link, withDestinationURL: outside)
        defer {
            try? manager.removeItem(at: link)
            try? manager.removeItem(at: outside)
        }

        do {
            _ = try await AgentWorkspace.shared.writeText(path: "\(linkName)/escape.txt", content: "blocked")
            XCTFail("Workspace followed a symlink outside its root")
        } catch AgentWorkspace.WorkspaceError.invalidPath {
            XCTAssertFalse(manager.fileExists(atPath: outside.appendingPathComponent("escape.txt").path))
        }
    }
}
