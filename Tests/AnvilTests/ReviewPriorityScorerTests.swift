import XCTest
@testable import Anvil

final class ReviewPriorityScorerTests: XCTestCase {

    // MARK: - Helpers

    private func makeFile(
        path: String,
        status: GitFileStatus = .modified,
        staging: StagingState = .unstaged,
        additions: Int = 0,
        deletions: Int = 0,
        hunkHeaders: [String] = []
    ) -> ChangedFile {
        let url = URL(fileURLWithPath: "/tmp/project/\(path)")
        let diff: FileDiff? = makeFileDiff(path: path, additions: additions, deletions: deletions, hunkHeaders: hunkHeaders)
        return ChangedFile(url: url, relativePath: path, status: status, staging: staging, diff: diff)
    }

    private func makeFileDiff(path: String, additions: Int, deletions: Int, hunkHeaders: [String]) -> FileDiff? {
        guard additions > 0 || deletions > 0 || !hunkHeaders.isEmpty else { return nil }
        if hunkHeaders.isEmpty {
            var lines: [DiffLine] = []
            var lineID = 0
            for i in 0..<additions {
                lines.append(DiffLine(id: lineID, kind: .addition, text: "+line\(i)", oldLineNumber: nil, newLineNumber: i + 1))
                lineID += 1
            }
            for i in 0..<deletions {
                lines.append(DiffLine(id: lineID, kind: .deletion, text: "-line\(i)", oldLineNumber: i + 1, newLineNumber: nil))
                lineID += 1
            }
            let hunk = DiffHunk(id: 0, header: "@@ -1,\(deletions) +1,\(additions) @@", lines: lines)
            return FileDiff(id: path, oldPath: path, newPath: path, hunks: [hunk])
        } else {
            let hunks = hunkHeaders.enumerated().map { i, header in
                DiffHunk(id: i, header: header, lines: [])
            }
            return FileDiff(id: path, oldPath: path, newPath: path, hunks: hunks)
        }
    }

    // MARK: - isTestFile

    func testTestFileByDirectory() {
        XCTAssertTrue(ReviewPriorityScorer.isTestFile("Tests/AnvilTests/MyTest.swift"))
        XCTAssertTrue(ReviewPriorityScorer.isTestFile("src/__tests__/Button.test.ts"))
        XCTAssertTrue(ReviewPriorityScorer.isTestFile("spec/models/user_spec.rb"))
    }

    func testTestFileBySuffix() {
        XCTAssertTrue(ReviewPriorityScorer.isTestFile("Sources/MyViewTests.swift"))
        XCTAssertTrue(ReviewPriorityScorer.isTestFile("src/LoginSpec.ts"))
        XCTAssertTrue(ReviewPriorityScorer.isTestFile("models/UserMock.swift"))
    }

    func testSourceFilesAreNotTestFiles() {
        XCTAssertFalse(ReviewPriorityScorer.isTestFile("Sources/Anvil/ContentView.swift"))
        XCTAssertFalse(ReviewPriorityScorer.isTestFile("src/components/Button.tsx"))
        XCTAssertFalse(ReviewPriorityScorer.isTestFile("main.go"))
    }

    // MARK: - isHubFile

    func testHubFilesByCommonStems() {
        XCTAssertTrue(ReviewPriorityScorer.isHubFile("src/index.ts"))
        XCTAssertTrue(ReviewPriorityScorer.isHubFile("Sources/utils.swift"))
        XCTAssertTrue(ReviewPriorityScorer.isHubFile("store/models.ts"))
        XCTAssertTrue(ReviewPriorityScorer.isHubFile("app/config.json"))
        XCTAssertTrue(ReviewPriorityScorer.isHubFile("services/api.py"))
    }

    func testNonHubFiles() {
        XCTAssertFalse(ReviewPriorityScorer.isHubFile("Sources/Anvil/ContentView.swift"))
        XCTAssertFalse(ReviewPriorityScorer.isHubFile("src/LoginView.tsx"))
        XCTAssertFalse(ReviewPriorityScorer.isHubFile("Readme.md"))
    }

    // MARK: - countSignificantHunks

    func testNoHunks() {
        XCTAssertEqual(ReviewPriorityScorer.countSignificantHunks(in: nil), 0)
    }

    func testHunksWithoutContext() {
        let hunks = [
            DiffHunk(id: 0, header: "@@ -1,5 +1,7 @@", lines: []),
            DiffHunk(id: 1, header: "@@ -10,3 +12,3 @@", lines: []),
        ]
        let diff = FileDiff(id: "f", oldPath: "f", newPath: "f", hunks: hunks)
        XCTAssertEqual(ReviewPriorityScorer.countSignificantHunks(in: diff), 0)
    }

    func testHunksWithContext() {
        let hunks = [
            DiffHunk(id: 0, header: "@@ -1,5 +1,7 @@ func loadData()", lines: []),
            DiffHunk(id: 1, header: "@@ -20,3 +22,3 @@ class MyView", lines: []),
        ]
        let diff = FileDiff(id: "f", oldPath: "f", newPath: "f", hunks: hunks)
        XCTAssertEqual(ReviewPriorityScorer.countSignificantHunks(in: diff), 2)
    }

    // MARK: - score

    func testNewFileIsAtLeastMedium() {
        let file = makeFile(path: "Sources/NewFeature.swift", status: .added)
        let priority = ReviewPriorityScorer.score(file)
        XCTAssertGreaterThanOrEqual(priority.level, .medium)
        XCTAssertTrue(priority.reasons.contains("New file"))
    }

    func testDeletedFileIsAtLeastMedium() {
        let file = makeFile(path: "Sources/OldFeature.swift", status: .deleted)
        let priority = ReviewPriorityScorer.score(file)
        XCTAssertGreaterThanOrEqual(priority.level, .medium)
        XCTAssertTrue(priority.reasons.contains("File deleted"))
    }

    func testLargeChangeIsHighPriority() {
        // 110 lines changed + source file → should reach high
        let file = makeFile(path: "Sources/BigFile.swift", additions: 80, deletions: 30)
        let priority = ReviewPriorityScorer.score(file)
        XCTAssertEqual(priority.level, .high)
    }

    func testSmallChangeInTestFileIsLow() {
        let file = makeFile(path: "Tests/AnvilTests/SmallTest.swift", additions: 5, deletions: 2)
        let priority = ReviewPriorityScorer.score(file)
        XCTAssertEqual(priority.level, .low)
    }

    func testHubFileGetsBoostedPriority() {
        // utils.swift modified with moderate change → should be at least medium
        let file = makeFile(path: "Sources/utils.swift", additions: 10, deletions: 5)
        let priority = ReviewPriorityScorer.score(file)
        XCTAssertGreaterThanOrEqual(priority.level, .medium)
        XCTAssertTrue(priority.reasons.contains("Core module"))
    }

    func testManyFunctionsAffectedRaisesScore() {
        // 4 hunks with context strings → +2 points
        let headers = [
            "@@ -1,5 +1,7 @@ func alpha()",
            "@@ -20,3 +22,4 @@ func beta()",
            "@@ -40,5 +43,3 @@ func gamma()",
            "@@ -60,2 +62,2 @@ func delta()",
        ]
        let file = makeFile(path: "Sources/Logic.swift", hunkHeaders: headers)
        let priority = ReviewPriorityScorer.score(file)
        XCTAssertTrue(priority.reasons.contains(where: { $0.contains("functions affected") }))
    }

    func testSortedPutsHighFirstLowLast() {
        let low    = makeFile(path: "Tests/SomeTest.swift", additions: 2)
        let high   = makeFile(path: "Sources/index.swift", status: .added, additions: 120)
        let medium = makeFile(path: "Sources/Feature.swift", additions: 50)

        let sorted = ReviewPriorityScorer.sorted([low, high, medium])
        XCTAssertEqual(sorted.first?.relativePath, "Sources/index.swift")
        XCTAssertEqual(sorted.last?.relativePath, "Tests/SomeTest.swift")
    }

    func testTooltipTextIncludesReasons() {
        let file = makeFile(path: "Sources/utils.swift", status: .added, additions: 200)
        let priority = ReviewPriorityScorer.score(file)
        XCTAssertTrue(priority.tooltipText.contains(priority.level.label))
        XCTAssertFalse(priority.tooltipText.isEmpty)
    }
}
