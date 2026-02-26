import XCTest
@testable import Anvil

final class FileEntryTests: XCTestCase {

    private func makeTempDir() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("AnvilTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    func testLoadChildrenReturnsFilesAndDirs() throws {
        let tempDir = try makeTempDir()
        defer { cleanup(tempDir) }

        let subDir = tempDir.appendingPathComponent("src")
        try FileManager.default.createDirectory(at: subDir, withIntermediateDirectories: true)
        try "hello".write(to: tempDir.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        try "code".write(to: tempDir.appendingPathComponent("main.swift"), atomically: true, encoding: .utf8)

        let entries = FileEntry.loadChildren(of: tempDir)

        XCTAssertEqual(entries.first?.name, "src")
        XCTAssertEqual(entries.first?.isDirectory, true)
        XCTAssertEqual(entries.count, 3)
    }

    func testLoadChildrenHidesGitDir() throws {
        let tempDir = try makeTempDir()
        defer { cleanup(tempDir) }

        let gitDir = tempDir.appendingPathComponent(".git")
        try FileManager.default.createDirectory(at: gitDir, withIntermediateDirectories: true)
        try "file".write(to: tempDir.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)

        let entries = FileEntry.loadChildren(of: tempDir)

        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.name, "Package.swift")
    }

    func testIconForSwiftFile() {
        let entry = FileEntry(
            url: URL(fileURLWithPath: "/test/file.swift"),
            name: "file.swift",
            isDirectory: false,
            depth: 0
        )
        XCTAssertEqual(entry.icon, "swift")
    }

    func testIconForDirectory() {
        let entry = FileEntry(
            url: URL(fileURLWithPath: "/test/src"),
            name: "src",
            isDirectory: true,
            depth: 0
        )
        XCTAssertEqual(entry.icon, "folder.fill")
    }

    func testDepthPreserved() {
        let entry = FileEntry(
            url: URL(fileURLWithPath: "/test/a/b/c.txt"),
            name: "c.txt",
            isDirectory: false,
            depth: 3
        )
        XCTAssertEqual(entry.depth, 3)
    }

    func testEmptyDirectoryReturnsEmptyArray() throws {
        let tempDir = try makeTempDir()
        defer { cleanup(tempDir) }

        let entries = FileEntry.loadChildren(of: tempDir)
        XCTAssertTrue(entries.isEmpty)
    }
}
