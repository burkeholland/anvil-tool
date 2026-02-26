import XCTest
@testable import Anvil

final class DiffSnapshotTests: XCTestCase {

    // MARK: - Helpers

    private func makeLine(id: Int, kind: DiffLine.Kind, text: String) -> DiffLine {
        DiffLine(id: id, kind: kind, text: text, oldLineNumber: 1, newLineNumber: 1)
    }

    private func makeHunk(id: Int, lines: [DiffLine]) -> DiffHunk {
        DiffHunk(id: id, header: "@@ -1,1 +1,1 @@", lines: lines)
    }

    private func makeFileDiff(path: String, hunks: [DiffHunk]) -> FileDiff {
        FileDiff(id: path, oldPath: path, newPath: path, hunks: hunks)
    }

    private func makeFile(path: String, diff: FileDiff? = nil) -> ChangedFile {
        ChangedFile(
            url: URL(fileURLWithPath: "/tmp/project/\(path)"),
            relativePath: path,
            status: .modified,
            staging: .unstaged,
            diff: diff
        )
    }

    // MARK: - takeSnapshot

    func testTakeSnapshotAppendsSnapshot() {
        let model = ChangesModel()
        let file = makeFile(path: "a.swift")
        model.setChangedFilesForTesting([file])
        model.takeSnapshot()
        XCTAssertEqual(model.snapshots.count, 1)
    }

    func testTakeSnapshotSetsActiveSnapshotID() {
        let model = ChangesModel()
        model.setChangedFilesForTesting([makeFile(path: "a.swift")])
        model.takeSnapshot()
        XCTAssertEqual(model.activeSnapshotID, model.snapshots.first?.id)
    }

    func testMultipleSnapshots() {
        let model = ChangesModel()
        model.setChangedFilesForTesting([makeFile(path: "a.swift")])
        model.takeSnapshot()
        model.takeSnapshot()
        XCTAssertEqual(model.snapshots.count, 2)
    }

    func testActiveSnapshotReturnsLatestWhenNilID() {
        let model = ChangesModel()
        model.setChangedFilesForTesting([makeFile(path: "a.swift")])
        model.takeSnapshot()
        model.takeSnapshot()
        model.activeSnapshotID = nil
        XCTAssertEqual(model.activeSnapshot?.id, model.snapshots.last?.id)
    }

    func testActiveSnapshotReturnsNilWhenNoSnapshots() {
        let model = ChangesModel()
        XCTAssertNil(model.activeSnapshot)
    }

    // MARK: - snapshotDeltaFiles – new files

    func testNewFileSinceSnapshotIsIncluded() {
        let model = ChangesModel()
        let existing = makeFile(path: "a.swift")
        model.setChangedFilesForTesting([existing])
        model.takeSnapshot()

        // Add a new file after snapshot
        let newFile = makeFile(path: "b.swift")
        model.setChangedFilesForTesting([existing, newFile])

        let delta = model.snapshotDeltaFiles
        XCTAssertEqual(delta.count, 1)
        XCTAssertEqual(delta[0].relativePath, "b.swift")
    }

    func testFileInSnapshotWithUnchangedDiffIsExcluded() {
        let hunk = makeHunk(id: 0, lines: [makeLine(id: 0, kind: .addition, text: "hello")])
        let diff = makeFileDiff(path: "a.swift", hunks: [hunk])
        let file = makeFile(path: "a.swift", diff: diff)
        let model = ChangesModel()
        model.setChangedFilesForTesting([file])
        model.takeSnapshot()

        // Same file, same diff after snapshot
        let delta = model.snapshotDeltaFiles
        XCTAssertTrue(delta.isEmpty)
    }

    // MARK: - snapshotDeltaFiles – changed hunks

    func testNewHunkInExistingFileIsIncluded() {
        let hunk1 = makeHunk(id: 0, lines: [makeLine(id: 0, kind: .addition, text: "line1")])
        let diff1 = makeFileDiff(path: "a.swift", hunks: [hunk1])
        let file1 = makeFile(path: "a.swift", diff: diff1)
        let model = ChangesModel()
        model.setChangedFilesForTesting([file1])
        model.takeSnapshot()

        // Add a second hunk to the file
        let hunk2 = makeHunk(id: 1, lines: [makeLine(id: 1, kind: .addition, text: "line2")])
        let diff2 = makeFileDiff(path: "a.swift", hunks: [hunk1, hunk2])
        let file2 = makeFile(path: "a.swift", diff: diff2)
        model.setChangedFilesForTesting([file2])

        let delta = model.snapshotDeltaFiles
        XCTAssertEqual(delta.count, 1)
        // Only the new hunk should remain
        XCTAssertEqual(delta[0].diff?.hunks.count, 1)
        XCTAssertEqual(delta[0].diff?.hunks[0].lines[0].text, "line2")
    }

    func testChangedHunkContentIsIncluded() {
        let hunk = makeHunk(id: 0, lines: [makeLine(id: 0, kind: .addition, text: "old content")])
        let diff = makeFileDiff(path: "a.swift", hunks: [hunk])
        let file = makeFile(path: "a.swift", diff: diff)
        let model = ChangesModel()
        model.setChangedFilesForTesting([file])
        model.takeSnapshot()

        // Same hunk id but different text
        let hunk2 = makeHunk(id: 0, lines: [makeLine(id: 0, kind: .addition, text: "new content")])
        let diff2 = makeFileDiff(path: "a.swift", hunks: [hunk2])
        let file2 = makeFile(path: "a.swift", diff: diff2)
        model.setChangedFilesForTesting([file2])

        let delta = model.snapshotDeltaFiles
        XCTAssertEqual(delta.count, 1)
        XCTAssertEqual(delta[0].diff?.hunks[0].lines[0].text, "new content")
    }

    // MARK: - snapshotDeltaFiles – no snapshot

    func testDeltaReturnsAllFilesWhenNoSnapshot() {
        let model = ChangesModel()
        let files = [makeFile(path: "a.swift"), makeFile(path: "b.swift")]
        model.setChangedFilesForTesting(files)
        let delta = model.snapshotDeltaFiles
        XCTAssertEqual(delta.count, 2)
    }

    // MARK: - hunkFingerprint

    func testHunkFingerprintMatchesIdenticalHunks() {
        let lines = [makeLine(id: 0, kind: .addition, text: "hello")]
        let h1 = makeHunk(id: 0, lines: lines)
        let h2 = makeHunk(id: 99, lines: lines) // different id, same content
        XCTAssertEqual(
            ChangesModel.DiffSnapshot.hunkFingerprint(h1),
            ChangesModel.DiffSnapshot.hunkFingerprint(h2)
        )
    }

    func testHunkFingerprintDiffersForDifferentContent() {
        let h1 = makeHunk(id: 0, lines: [makeLine(id: 0, kind: .addition, text: "foo")])
        let h2 = makeHunk(id: 0, lines: [makeLine(id: 0, kind: .addition, text: "bar")])
        XCTAssertNotEqual(
            ChangesModel.DiffSnapshot.hunkFingerprint(h1),
            ChangesModel.DiffSnapshot.hunkFingerprint(h2)
        )
    }

    func testHunkFingerprintDiffersForDifferentLineKind() {
        let h1 = makeHunk(id: 0, lines: [makeLine(id: 0, kind: .addition, text: "x")])
        let h2 = makeHunk(id: 0, lines: [makeLine(id: 0, kind: .deletion, text: "x")])
        XCTAssertNotEqual(
            ChangesModel.DiffSnapshot.hunkFingerprint(h1),
            ChangesModel.DiffSnapshot.hunkFingerprint(h2)
        )
    }

    // MARK: - snapshot label

    func testSnapshotLabelIsNonEmpty() {
        let model = ChangesModel()
        model.setChangedFilesForTesting([makeFile(path: "a.swift")])
        model.takeSnapshot()
        XCTAssertFalse(model.snapshots[0].label.isEmpty)
    }
}
