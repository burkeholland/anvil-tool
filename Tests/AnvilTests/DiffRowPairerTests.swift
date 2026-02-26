import XCTest
@testable import Anvil

final class DiffRowPairerTests: XCTestCase {

    // MARK: - Helpers

    /// Builds a FileDiff with a single hunk from a list of (text, kind) pairs.
    private func makeDiff(lines: [(String, DiffLine.Kind)]) -> FileDiff {
        var lineObjs: [DiffLine] = []
        var lineID = 0
        var oldNum = 1
        var newNum = 1
        for (text, kind) in lines {
            let old: Int? = (kind == .addition || kind == .hunkHeader) ? nil : oldNum
            let new: Int? = (kind == .deletion || kind == .hunkHeader) ? nil : newNum
            lineObjs.append(DiffLine(id: lineID, kind: kind, text: text, oldLineNumber: old, newLineNumber: new))
            lineID += 1
            if kind != .addition { oldNum += 1 }
            if kind != .deletion { newNum += 1 }
        }
        let hunk = DiffHunk(id: 0, header: "@@ -1 +1 @@", lines: lineObjs)
        return FileDiff(id: "a.txt", oldPath: "a.txt", newPath: "a.txt", hunks: [hunk])
    }

    // MARK: - DiffRowPairer tests

    func testContextLinesProducePairedRows() {
        let diff = makeDiff(lines: [
            ("context", .context),
            ("context2", .context),
        ])
        let rows = DiffRowPairer.pairLines(from: diff.hunks)
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[0].left?.text, "context")
        XCTAssertEqual(rows[0].right?.text, "context")
        XCTAssertEqual(rows[1].left?.text, "context2")
        XCTAssertEqual(rows[1].right?.text, "context2")
    }

    func testDeletionOnlyProducesLeftOnlyRow() {
        let diff = makeDiff(lines: [("removed", .deletion)])
        let rows = DiffRowPairer.pairLines(from: diff.hunks)
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].left?.text, "removed")
        XCTAssertNil(rows[0].right)
    }

    func testAdditionOnlyProducesRightOnlyRow() {
        let diff = makeDiff(lines: [("added", .addition)])
        let rows = DiffRowPairer.pairLines(from: diff.hunks)
        XCTAssertEqual(rows.count, 1)
        XCTAssertNil(rows[0].left)
        XCTAssertEqual(rows[0].right?.text, "added")
    }

    func testDeletionFollowedByAdditionArePaired() {
        let diff = makeDiff(lines: [
            ("old line", .deletion),
            ("new line", .addition),
        ])
        let rows = DiffRowPairer.pairLines(from: diff.hunks)
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].left?.text, "old line")
        XCTAssertEqual(rows[0].right?.text, "new line")
    }

    func testMoreDeletionsThanAdditions() {
        let diff = makeDiff(lines: [
            ("del1", .deletion),
            ("del2", .deletion),
            ("del3", .deletion),
            ("add1", .addition),
        ])
        let rows = DiffRowPairer.pairLines(from: diff.hunks)
        XCTAssertEqual(rows.count, 3)
        XCTAssertEqual(rows[0].left?.text, "del1"); XCTAssertEqual(rows[0].right?.text, "add1")
        XCTAssertEqual(rows[1].left?.text, "del2"); XCTAssertNil(rows[1].right)
        XCTAssertEqual(rows[2].left?.text, "del3"); XCTAssertNil(rows[2].right)
    }

    func testMoreAdditionsThanDeletions() {
        let diff = makeDiff(lines: [
            ("del1", .deletion),
            ("add1", .addition),
            ("add2", .addition),
            ("add3", .addition),
        ])
        let rows = DiffRowPairer.pairLines(from: diff.hunks)
        XCTAssertEqual(rows.count, 3)
        XCTAssertEqual(rows[0].left?.text, "del1"); XCTAssertEqual(rows[0].right?.text, "add1")
        XCTAssertNil(rows[1].left); XCTAssertEqual(rows[1].right?.text, "add2")
        XCTAssertNil(rows[2].left); XCTAssertEqual(rows[2].right?.text, "add3")
    }

    func testHunkHeaderSpansBothColumns() {
        let hunkHeader = DiffLine(id: 0, kind: .hunkHeader, text: "@@ -1,3 +1,3 @@", oldLineNumber: nil, newLineNumber: nil)
        let hunk = DiffHunk(id: 0, header: "@@ -1,3 +1,3 @@", lines: [hunkHeader])
        let diff = FileDiff(id: "a.txt", oldPath: "a.txt", newPath: "a.txt", hunks: [hunk])
        let rows = DiffRowPairer.pairLines(from: diff.hunks)
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].left?.kind, .hunkHeader)
        XCTAssertEqual(rows[0].right?.kind, .hunkHeader)
    }

    func testRowIDsAreMonotonicallyIncreasing() {
        let diff = makeDiff(lines: [
            ("ctx", .context), ("del", .deletion), ("add", .addition), ("ctx2", .context),
        ])
        let rows = DiffRowPairer.pairLines(from: diff.hunks)
        for i in 1..<rows.count {
            XCTAssertGreaterThan(rows[i].id, rows[i - 1].id)
        }
    }

    func testEmptyHunksProduceNoRows() {
        let diff = FileDiff(id: "a.txt", oldPath: "a.txt", newPath: "a.txt", hunks: [])
        let rows = DiffRowPairer.pairLines(from: diff.hunks)
        XCTAssertTrue(rows.isEmpty)
    }

    // MARK: - DiffViewMode tests

    func testDiffViewModeRawValues() {
        XCTAssertEqual(DiffViewMode.unified.rawValue, "Unified")
        XCTAssertEqual(DiffViewMode.sideBySide.rawValue, "Side by Side")
        XCTAssertEqual(DiffViewMode.allCases.count, 2)
    }

    func testDiffViewModeToggledFromUnified() {
        XCTAssertEqual(DiffViewMode.unified.toggled, .sideBySide)
    }

    func testDiffViewModeToggledFromSideBySide() {
        XCTAssertEqual(DiffViewMode.sideBySide.toggled, .unified)
    }

    func testDiffViewModeToggledIsIdempotentOverTwoInversions() {
        XCTAssertEqual(DiffViewMode.unified.toggled.toggled, .unified)
        XCTAssertEqual(DiffViewMode.sideBySide.toggled.toggled, .sideBySide)
    }
}
