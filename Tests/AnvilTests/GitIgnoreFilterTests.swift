import XCTest
@testable import Anvil

final class GitIgnoreFilterTests: XCTestCase {

    // MARK: - Testable initializer (known file list + ignored dirs)

    func testAllowsTrackedFiles() {
        let filter = GitIgnoreFilter(rootPath: "/project", knownFiles: [
            "README.md",
            "src/main.swift",
            "src/utils/helpers.swift",
        ])

        XCTAssertTrue(filter.shouldShow(name: "README.md", relativePath: "README.md", isDirectory: false))
        XCTAssertTrue(filter.shouldShow(name: "main.swift", relativePath: "src/main.swift", isDirectory: false))
        XCTAssertTrue(filter.shouldShow(name: "helpers.swift", relativePath: "src/utils/helpers.swift", isDirectory: false))
    }

    func testHidesIgnoredFiles() {
        let filter = GitIgnoreFilter(rootPath: "/project", knownFiles: [
            "README.md",
            "src/main.swift",
        ])

        XCTAssertFalse(filter.shouldShow(name: "secret.env", relativePath: "secret.env", isDirectory: false))
        XCTAssertFalse(filter.shouldShow(name: "cache.db", relativePath: "build/cache.db", isDirectory: false))
    }

    func testShowsNonIgnoredDirectories() {
        let filter = GitIgnoreFilter(
            rootPath: "/project",
            knownFiles: ["src/main.swift"],
            ignoredDirectories: ["node_modules", "build", ".build"]
        )

        // Non-ignored directories should be visible
        XCTAssertTrue(filter.shouldShow(name: "src", relativePath: "src", isDirectory: true))
        XCTAssertTrue(filter.shouldShow(name: "tests", relativePath: "tests", isDirectory: true))

        // Ignored directories should be hidden
        XCTAssertFalse(filter.shouldShow(name: "node_modules", relativePath: "node_modules", isDirectory: true))
        XCTAssertFalse(filter.shouldShow(name: "build", relativePath: "build", isDirectory: true))
        XCTAssertFalse(filter.shouldShow(name: ".build", relativePath: ".build", isDirectory: true))
    }

    func testEmptyDirectoryIsVisible() {
        // Empty directories not in the ignored list should show up
        let filter = GitIgnoreFilter(
            rootPath: "/project",
            knownFiles: ["README.md"],
            ignoredDirectories: ["node_modules"]
        )

        XCTAssertTrue(filter.shouldShow(name: "new-folder", relativePath: "new-folder", isDirectory: true))
    }

    func testAlwaysHidesGitDir() {
        let filter = GitIgnoreFilter(rootPath: "/project", knownFiles: [
            ".git/config",  // Even if somehow in the list
            "README.md",
        ])

        XCTAssertFalse(filter.shouldShow(name: ".git", relativePath: ".git", isDirectory: true))
        XCTAssertFalse(filter.shouldShow(name: ".DS_Store", relativePath: ".DS_Store", isDirectory: false))
    }

    func testShowsDotFilesInGitRepo() {
        let filter = GitIgnoreFilter(rootPath: "/project", knownFiles: [
            ".github/copilot-instructions.md",
            ".eslintrc",
            "README.md",
        ])

        XCTAssertTrue(filter.shouldShow(name: ".eslintrc", relativePath: ".eslintrc", isDirectory: false))
        // .github is a directory — not in ignored list, so it shows
        XCTAssertTrue(filter.shouldShow(name: ".github", relativePath: ".github", isDirectory: true))
    }

    func testEmptyFileListHidesFiles() {
        let filter = GitIgnoreFilter(rootPath: "/project", knownFiles: [])

        // Files not in allowedFiles are hidden
        XCTAssertFalse(filter.shouldShow(name: "anything.txt", relativePath: "anything.txt", isDirectory: false))
        // Directories not in ignoredDirs are shown (empty dirs visible)
        XCTAssertTrue(filter.shouldShow(name: "src", relativePath: "src", isDirectory: true))
    }

    func testRelativePath() {
        let filter = GitIgnoreFilter(rootPath: "/Users/dev/project", knownFiles: ["README.md"])

        let url = URL(fileURLWithPath: "/Users/dev/project/src/main.swift")
        XCTAssertEqual(filter.relativePath(for: url), "src/main.swift")

        let rootFile = URL(fileURLWithPath: "/Users/dev/project/README.md")
        XCTAssertEqual(filter.relativePath(for: rootFile), "README.md")
    }

    func testNestedIgnoredDirs() {
        let filter = GitIgnoreFilter(
            rootPath: "/project",
            knownFiles: ["src/main.swift"],
            ignoredDirectories: ["src/build", "dist"]
        )

        XCTAssertTrue(filter.shouldShow(name: "src", relativePath: "src", isDirectory: true))
        XCTAssertFalse(filter.shouldShow(name: "build", relativePath: "src/build", isDirectory: true))
        XCTAssertFalse(filter.shouldShow(name: "dist", relativePath: "dist", isDirectory: true))
    }

    // MARK: - Non-git repo fallback

    func testNonGitRepoFallback() {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("GitIgnoreFilterTest-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let filter = GitIgnoreFilter(rootURL: tmpDir)
        XCTAssertFalse(filter.isGitRepo)

        // Hardcoded exclusions should apply
        XCTAssertFalse(filter.shouldShow(name: ".git", relativePath: ".git", isDirectory: true))
        XCTAssertFalse(filter.shouldShow(name: "node_modules", relativePath: "node_modules", isDirectory: true))
        XCTAssertFalse(filter.shouldShow(name: ".DS_Store", relativePath: ".DS_Store", isDirectory: false))
        XCTAssertFalse(filter.shouldShow(name: ".build", relativePath: ".build", isDirectory: true))

        // Hidden (dot) files should be hidden in non-git repos
        XCTAssertFalse(filter.shouldShow(name: ".eslintrc", relativePath: ".eslintrc", isDirectory: false))

        // Normal files should be visible
        XCTAssertTrue(filter.shouldShow(name: "README.md", relativePath: "README.md", isDirectory: false))
        XCTAssertTrue(filter.shouldShow(name: "src", relativePath: "src", isDirectory: true))
    }

    // MARK: - Fallback when filter not loaded

    func testFallbackBeforeRefresh() {
        // rootURL init doesn't call refresh() anymore — filter starts unavailable
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("GitIgnoreFilterTest-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        // Create a .git directory to simulate a git repo
        try? FileManager.default.createDirectory(
            at: tmpDir.appendingPathComponent(".git"),
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let filter = GitIgnoreFilter(rootURL: tmpDir)
        XCTAssertTrue(filter.isGitRepo)

        // Before refresh(), should use safe fallback (hide dot-files + defaultHidden)
        XCTAssertFalse(filter.shouldShow(name: ".git", relativePath: ".git", isDirectory: true))
        XCTAssertFalse(filter.shouldShow(name: "node_modules", relativePath: "node_modules", isDirectory: true))
        XCTAssertTrue(filter.shouldShow(name: "README.md", relativePath: "README.md", isDirectory: false))
    }
}
