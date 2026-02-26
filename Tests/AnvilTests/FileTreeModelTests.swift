import XCTest
@testable import Anvil

final class FileTreeModelTests: XCTestCase {

    func testDirChangeCountsSingleFile() {
        let statuses: [String: GitFileStatus] = [
            "/project/src/main.swift": .modified
        ]
        let counts = FileTreeModel.computeDirChangeCounts(statuses: statuses, rootPath: "/project")
        XCTAssertEqual(counts["/project/src"], 1)
        XCTAssertEqual(counts["/project"], 1)
    }

    func testDirChangeCountsMultipleFilesInSameDir() {
        let statuses: [String: GitFileStatus] = [
            "/project/src/a.swift": .modified,
            "/project/src/b.swift": .added
        ]
        let counts = FileTreeModel.computeDirChangeCounts(statuses: statuses, rootPath: "/project")
        XCTAssertEqual(counts["/project/src"], 2)
        XCTAssertEqual(counts["/project"], 2)
    }

    func testDirChangeCountsNestedDirs() {
        let statuses: [String: GitFileStatus] = [
            "/project/src/models/user.swift": .modified,
            "/project/src/views/main.swift": .added,
            "/project/tests/test.swift": .modified
        ]
        let counts = FileTreeModel.computeDirChangeCounts(statuses: statuses, rootPath: "/project")
        XCTAssertEqual(counts["/project/src/models"], 1)
        XCTAssertEqual(counts["/project/src/views"], 1)
        XCTAssertEqual(counts["/project/src"], 2)
        XCTAssertEqual(counts["/project/tests"], 1)
        XCTAssertEqual(counts["/project"], 3)
    }

    func testDirChangeCountsEmptyStatuses() {
        let counts = FileTreeModel.computeDirChangeCounts(statuses: [:], rootPath: "/project")
        XCTAssertTrue(counts.isEmpty)
    }

    func testDirChangeCountsDoesNotCountAboveRoot() {
        let statuses: [String: GitFileStatus] = [
            "/project/file.txt": .untracked
        ]
        let counts = FileTreeModel.computeDirChangeCounts(statuses: statuses, rootPath: "/project")
        XCTAssertEqual(counts["/project"], 1)
        // Should not have entries above root
        XCTAssertNil(counts["/"])
    }

    func testDirChangeCountsIgnoresPropagatedDirectoryEntries() {
        // GitStatusProvider.parse() propagates statuses to parent dirs.
        // computeDirChangeCounts should only count leaf (file) entries.
        let statuses: [String: GitFileStatus] = [
            "/project/src/main.swift": .modified,
            "/project/src": .modified,            // propagated directory entry
            "/project": .modified                  // propagated directory entry
        ]
        let counts = FileTreeModel.computeDirChangeCounts(statuses: statuses, rootPath: "/project")
        XCTAssertEqual(counts["/project/src"], 1)
        XCTAssertEqual(counts["/project"], 1)
    }
}
