import XCTest
@testable import Anvil

final class CommitMessageTests: XCTestCase {

    private func makeFile(
        path: String,
        status: GitFileStatus,
        staging: StagingState = .unstaged,
        additions: Int = 0,
        deletions: Int = 0
    ) -> ChangedFile {
        let url = URL(fileURLWithPath: "/tmp/project/\(path)")
        let diff: FileDiff? = (additions > 0 || deletions > 0) ? makeDiff(path: path, additions: additions, deletions: deletions) : nil
        return ChangedFile(url: url, relativePath: path, status: status, staging: staging, diff: diff)
    }

    private func makeDiff(path: String, additions: Int, deletions: Int) -> FileDiff {
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
    }

    func testSingleNewFile() {
        let model = ChangesModel()
        model.setChangedFilesForTesting([
            makeFile(path: "NewFile.swift", status: .untracked)
        ])

        let message = model.generateCommitMessage()
        XCTAssertTrue(message.hasPrefix("Add NewFile.swift"), "Got: \(message)")
    }

    func testSingleModifiedFile() {
        let model = ChangesModel()
        model.setChangedFilesForTesting([
            makeFile(path: "ContentView.swift", status: .modified, additions: 10, deletions: 3)
        ])

        let message = model.generateCommitMessage()
        XCTAssertTrue(message.hasPrefix("Update ContentView.swift"), "Got: \(message)")
    }

    func testMixedChanges() {
        let model = ChangesModel()
        model.setChangedFilesForTesting([
            makeFile(path: "NewFile.swift", status: .added, additions: 20),
            makeFile(path: "OldFile.swift", status: .modified, additions: 5, deletions: 2),
            makeFile(path: "Removed.swift", status: .deleted, deletions: 10),
        ])

        let message = model.generateCommitMessage()
        XCTAssertTrue(message.contains("Add NewFile.swift"), "Got: \(message)")
        XCTAssertTrue(message.contains("Update OldFile.swift"), "Got: \(message)")
        XCTAssertTrue(message.contains("Remove Removed.swift"), "Got: \(message)")
    }

    func testMultipleFilesIncludeBody() {
        let model = ChangesModel()
        model.setChangedFilesForTesting([
            makeFile(path: "A.swift", status: .modified, additions: 5, deletions: 2),
            makeFile(path: "B.swift", status: .modified, additions: 3, deletions: 1),
        ])

        let message = model.generateCommitMessage()
        // Body should list individual files
        XCTAssertTrue(message.contains("- A.swift"), "Got: \(message)")
        XCTAssertTrue(message.contains("- B.swift"), "Got: \(message)")
        XCTAssertTrue(message.contains("+5/-2"), "Got: \(message)")
    }

    func testEmptyChanges() {
        let model = ChangesModel()
        model.setChangedFilesForTesting([])
        XCTAssertEqual(model.generateCommitMessage(), "")
    }

    func testManyFiles() {
        let model = ChangesModel()
        var files: [ChangedFile] = []
        for i in 0..<6 {
            files.append(makeFile(path: "File\(i).swift", status: .modified, additions: i + 1))
        }
        model.setChangedFilesForTesting(files)

        let message = model.generateCommitMessage()
        // Should truncate to 3 files + "and N more"
        XCTAssertTrue(message.contains("and 3 more"), "Got: \(message)")
    }

    func testUseStagedWhenAvailable() {
        let model = ChangesModel()
        model.setChangedFilesForTesting([
            makeFile(path: "Staged.swift", status: .modified, staging: .staged, additions: 5),
            makeFile(path: "Unstaged.swift", status: .modified, staging: .unstaged, additions: 3),
        ])

        let message = model.generateCommitMessage()
        // Should only reference staged file in subject
        XCTAssertTrue(message.contains("Staged.swift"), "Got: \(message)")
        XCTAssertFalse(message.contains("Unstaged.swift"), "Should not mention unstaged. Got: \(message)")
    }
}
