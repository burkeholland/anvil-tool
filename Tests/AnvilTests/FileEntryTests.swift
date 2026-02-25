import Testing
@testable import Anvil

@Suite("FileEntry Tests")
struct FileEntryTests {

    private func makeTempDir() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("AnvilTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    @Test("Loads files and directories, dirs first")
    func loadChildrenReturnsFilesAndDirs() throws {
        let tempDir = try makeTempDir()
        defer { cleanup(tempDir) }

        let subDir = tempDir.appendingPathComponent("src")
        try FileManager.default.createDirectory(at: subDir, withIntermediateDirectories: true)
        try "hello".write(to: tempDir.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        try "code".write(to: tempDir.appendingPathComponent("main.swift"), atomically: true, encoding: .utf8)

        let entries = FileEntry.loadChildren(of: tempDir)

        #expect(entries.first?.name == "src")
        #expect(entries.first?.isDirectory == true)
        #expect(entries.count == 3)
    }

    @Test("Hides .git directory")
    func loadChildrenHidesGitDir() throws {
        let tempDir = try makeTempDir()
        defer { cleanup(tempDir) }

        let gitDir = tempDir.appendingPathComponent(".git")
        try FileManager.default.createDirectory(at: gitDir, withIntermediateDirectories: true)
        try "file".write(to: tempDir.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)

        let entries = FileEntry.loadChildren(of: tempDir)

        #expect(entries.count == 1)
        #expect(entries.first?.name == "Package.swift")
    }

    @Test("Swift file gets swift icon")
    func iconForSwiftFile() {
        let entry = FileEntry(
            url: URL(fileURLWithPath: "/test/file.swift"),
            name: "file.swift",
            isDirectory: false,
            depth: 0
        )
        #expect(entry.icon == "swift")
    }

    @Test("Directory gets folder icon")
    func iconForDirectory() {
        let entry = FileEntry(
            url: URL(fileURLWithPath: "/test/src"),
            name: "src",
            isDirectory: true,
            depth: 0
        )
        #expect(entry.icon == "folder.fill")
    }

    @Test("Depth is preserved")
    func depthPreserved() {
        let entry = FileEntry(
            url: URL(fileURLWithPath: "/test/a/b/c.txt"),
            name: "c.txt",
            isDirectory: false,
            depth: 3
        )
        #expect(entry.depth == 3)
    }

    @Test("Empty directory returns empty array")
    func emptyDirectoryReturnsEmptyArray() throws {
        let tempDir = try makeTempDir()
        defer { cleanup(tempDir) }

        let entries = FileEntry.loadChildren(of: tempDir)
        #expect(entries.isEmpty)
    }
}
