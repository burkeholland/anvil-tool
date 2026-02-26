import XCTest
@testable import Anvil

final class DiffParserTests: XCTestCase {

    func testParseSimpleDiff() {
        let diffOutput = """
        diff --git a/hello.txt b/hello.txt
        index abc1234..def5678 100644
        --- a/hello.txt
        +++ b/hello.txt
        @@ -1,3 +1,4 @@
         line one
        -line two
        +line two modified
        +line three new
         line four
        """

        let diffs = DiffParser.parse(diffOutput)

        XCTAssertEqual(diffs.count, 1)
        XCTAssertEqual(diffs[0].oldPath, "hello.txt")
        XCTAssertEqual(diffs[0].newPath, "hello.txt")
        XCTAssertEqual(diffs[0].hunks.count, 1)
        XCTAssertEqual(diffs[0].additionCount, 2)
        XCTAssertEqual(diffs[0].deletionCount, 1)
    }

    func testParseHunkHeader() {
        let (oldStart, newStart) = DiffParser.parseHunkHeader("@@ -10,5 +12,7 @@ func example()")
        XCTAssertEqual(oldStart, 10)
        XCTAssertEqual(newStart, 12)
    }

    func testParseHunkHeaderNoCount() {
        let (oldStart, newStart) = DiffParser.parseHunkHeader("@@ -1 +1 @@")
        XCTAssertEqual(oldStart, 1)
        XCTAssertEqual(newStart, 1)
    }

    func testLineKinds() {
        let diffOutput = """
        diff --git a/test.swift b/test.swift
        index 1234567..abcdefg 100644
        --- a/test.swift
        +++ b/test.swift
        @@ -1,3 +1,3 @@
         context line
        -removed line
        +added line
        """

        let diffs = DiffParser.parse(diffOutput)
        let lines = diffs[0].hunks[0].lines

        XCTAssertEqual(lines[0].kind, .hunkHeader)
        XCTAssertEqual(lines[1].kind, .context)
        XCTAssertEqual(lines[1].text, "context line")
        XCTAssertEqual(lines[2].kind, .deletion)
        XCTAssertEqual(lines[2].text, "removed line")
        XCTAssertEqual(lines[3].kind, .addition)
        XCTAssertEqual(lines[3].text, "added line")
    }

    func testLineNumbers() {
        let diffOutput = """
        diff --git a/test.txt b/test.txt
        index 1234567..abcdefg 100644
        --- a/test.txt
        +++ b/test.txt
        @@ -5,4 +5,5 @@
         unchanged
        -old
        +new first
        +new second
         also unchanged
        """

        let diffs = DiffParser.parse(diffOutput)
        let lines = diffs[0].hunks[0].lines

        XCTAssertEqual(lines[1].oldLineNumber, 5)
        XCTAssertEqual(lines[1].newLineNumber, 5)
        XCTAssertEqual(lines[2].oldLineNumber, 6)
        XCTAssertNil(lines[2].newLineNumber)
        XCTAssertNil(lines[3].oldLineNumber)
        XCTAssertEqual(lines[3].newLineNumber, 6)
        XCTAssertNil(lines[4].oldLineNumber)
        XCTAssertEqual(lines[4].newLineNumber, 7)
        XCTAssertEqual(lines[5].oldLineNumber, 7)
        XCTAssertEqual(lines[5].newLineNumber, 8)
    }

    func testMultiFileDiff() {
        let diffOutput = """
        diff --git a/file1.txt b/file1.txt
        index 1234567..abcdefg 100644
        --- a/file1.txt
        +++ b/file1.txt
        @@ -1,2 +1,2 @@
        -old content
        +new content
        diff --git a/file2.txt b/file2.txt
        index 1234567..abcdefg 100644
        --- a/file2.txt
        +++ b/file2.txt
        @@ -1,1 +1,2 @@
         existing
        +added
        """

        let diffs = DiffParser.parse(diffOutput)
        XCTAssertEqual(diffs.count, 2)
        XCTAssertEqual(diffs[0].newPath, "file1.txt")
        XCTAssertEqual(diffs[1].newPath, "file2.txt")
    }

    func testRenamedFile() {
        let diffOutput = """
        diff --git a/old_name.txt b/new_name.txt
        similarity index 90%
        rename from old_name.txt
        rename to new_name.txt
        index 1234567..abcdefg 100644
        --- a/old_name.txt
        +++ b/new_name.txt
        @@ -1,2 +1,2 @@
        -old
        +new
        """

        let diffs = DiffParser.parse(diffOutput)
        XCTAssertEqual(diffs.count, 1)
        XCTAssertEqual(diffs[0].oldPath, "old_name.txt")
        XCTAssertEqual(diffs[0].newPath, "new_name.txt")
    }

    func testEmptyDiff() {
        let diffs = DiffParser.parse("")
        XCTAssertTrue(diffs.isEmpty)
    }

    func testMultipleHunks() {
        let diffOutput = """
        diff --git a/big.txt b/big.txt
        index 1234567..abcdefg 100644
        --- a/big.txt
        +++ b/big.txt
        @@ -1,3 +1,3 @@
         top
        -old top
        +new top
         mid
        @@ -10,3 +10,3 @@
         bottom
        -old bottom
        +new bottom
         end
        """

        let diffs = DiffParser.parse(diffOutput)
        XCTAssertEqual(diffs.count, 1)
        XCTAssertEqual(diffs[0].hunks.count, 2)
    }

    func testAdditionDeletionCounts() {
        let diffOutput = """
        diff --git a/counts.txt b/counts.txt
        index 1234567..abcdefg 100644
        --- a/counts.txt
        +++ b/counts.txt
        @@ -1,5 +1,6 @@
         keep
        -remove1
        -remove2
        +add1
        +add2
        +add3
         keep
        """

        let diffs = DiffParser.parse(diffOutput)
        XCTAssertEqual(diffs[0].additionCount, 3)
        XCTAssertEqual(diffs[0].deletionCount, 2)
    }

    // MARK: - Inline Highlighting

    func testComputeCharDiffSimple() {
        let (oldHL, newHL) = DiffParser.computeCharDiff(old: "hello world", new: "hello earth")
        // Common prefix: "hello ", common suffix: ""
        // old change: 6..<11 ("world"), new change: 6..<11 ("earth")
        XCTAssertEqual(oldHL, [6..<11])
        XCTAssertEqual(newHL, [6..<11])
    }

    func testComputeCharDiffMiddleChange() {
        let (oldHL, newHL) = DiffParser.computeCharDiff(old: "let userId = guid()", new: "let userID = guid()")
        // Word-level LCS: "let", "=", "guid()" match; "userId" vs "userID" are the changed tokens
        // "userId" occupies chars 4..<10 in the old string; "userID" occupies 4..<10 in the new string
        XCTAssertEqual(oldHL, [4..<10])
        XCTAssertEqual(newHL, [4..<10])
    }

    func testComputeCharDiffEntirelyDifferent() {
        let (oldHL, newHL) = DiffParser.computeCharDiff(old: "abc", new: "xyz")
        // No common prefix or suffix → no highlights
        XCTAssertTrue(oldHL.isEmpty)
        XCTAssertTrue(newHL.isEmpty)
    }

    func testComputeCharDiffInsertion() {
        let (oldHL, newHL) = DiffParser.computeCharDiff(old: "foo()", new: "foo(bar)")
        // Common prefix: "foo(", common suffix: ")"
        // old change: 4..<4 (empty), new change: 4..<7 ("bar")
        XCTAssertTrue(oldHL.isEmpty)
        XCTAssertEqual(newHL, [4..<7])
    }

    func testComputeCharDiffDeletion() {
        let (oldHL, newHL) = DiffParser.computeCharDiff(old: "foo(bar)", new: "foo()")
        // old change: 4..<7 ("bar"), new change: 4..<4 (empty)
        XCTAssertEqual(oldHL, [4..<7])
        XCTAssertTrue(newHL.isEmpty)
    }

    // MARK: - Word-level LCS helpers

    func testTokenize() {
        let tokens = DiffParser.tokenize("let x = 42")
        XCTAssertEqual(tokens.map(\.text), ["let", "x", "=", "42"])
        XCTAssertEqual(tokens.map(\.range), [0..<3, 4..<5, 6..<7, 8..<10])
    }

    func testTokenizeLeadingTrailingWhitespace() {
        let tokens = DiffParser.tokenize("  hello world  ")
        XCTAssertEqual(tokens.map(\.text), ["hello", "world"])
        XCTAssertEqual(tokens.map(\.range), [2..<7, 8..<13])
    }

    func testTokenizeEmpty() {
        XCTAssertTrue(DiffParser.tokenize("").isEmpty)
        XCTAssertTrue(DiffParser.tokenize("   ").isEmpty)
    }

    func testLCSTokenIndices() {
        let pairs = DiffParser.lcsTokenIndices(old: ["a", "b", "c"], new: ["a", "x", "c"])
        // LCS is ["a", "c"] at old indices (0, 2) and new indices (0, 2)
        XCTAssertEqual(pairs.map(\.0), [0, 2])
        XCTAssertEqual(pairs.map(\.1), [0, 2])
    }

    func testLCSTokenIndicesEmpty() {
        XCTAssertTrue(DiffParser.lcsTokenIndices(old: [], new: ["a"]).isEmpty)
        XCTAssertTrue(DiffParser.lcsTokenIndices(old: ["a"], new: []).isEmpty)
    }

    func testWordLevelDiffMiddleWordChanged() {
        // "foo bar baz" → "foo ZAP baz": only the middle word changes
        let (oldHL, newHL) = DiffParser.computeCharDiff(old: "foo bar baz", new: "foo ZAP baz")
        XCTAssertEqual(oldHL, [4..<7])   // "bar"
        XCTAssertEqual(newHL, [4..<7])   // "ZAP"
    }

    func testWordLevelDiffMultipleChangedWords() {
        // "foo bar baz" → "qux bar quux": first and last words change, middle is common
        let (oldHL, newHL) = DiffParser.computeCharDiff(old: "foo bar baz", new: "qux bar quux")
        XCTAssertEqual(oldHL, [0..<3, 8..<11])    // "foo", "baz"
        XCTAssertEqual(newHL, [0..<3, 8..<12])    // "qux", "quux"
    }

    func testWordLevelDiffAdjacentChangedTokensMerged() {
        // "a b c d" → "a X Y d": two consecutive changed tokens merge into one range
        let (oldHL, newHL) = DiffParser.computeCharDiff(old: "a b c d", new: "a X Y d")
        XCTAssertEqual(oldHL, [2..<5])   // "b c" (merged)
        XCTAssertEqual(newHL, [2..<5])   // "X Y" (merged)
    }

    func testInlineHighlightsInParsedDiff() {
        let diffOutput = """
        diff --git a/test.swift b/test.swift
        index 1234567..abcdefg 100644
        --- a/test.swift
        +++ b/test.swift
        @@ -1,3 +1,3 @@
         context line
        -let value = oldFunc()
        +let value = newFunc()
        """

        let diffs = DiffParser.parse(diffOutput)
        let lines = diffs[0].hunks[0].lines

        // Word-level LCS: "let", "value", "=" match; "oldFunc()" vs "newFunc()" are the changed tokens.
        // "oldFunc()" occupies chars 12..<21 in "let value = oldFunc()"
        let deletionLine = lines.first { $0.kind == .deletion }!
        XCTAssertNotNil(deletionLine.inlineHighlights)
        XCTAssertEqual(deletionLine.inlineHighlights, [12..<21])

        // Addition line: "let value = newFunc()" → highlight "newFunc()"
        let additionLine = lines.first { $0.kind == .addition }!
        XCTAssertNotNil(additionLine.inlineHighlights)
        XCTAssertEqual(additionLine.inlineHighlights, [12..<21])
    }

    func testNoInlineHighlightsWhenUnpaired() {
        let diffOutput = """
        diff --git a/test.txt b/test.txt
        index 1234567..abcdefg 100644
        --- a/test.txt
        +++ b/test.txt
        @@ -1,2 +1,1 @@
         keep
        -removed line
        """

        let diffs = DiffParser.parse(diffOutput)
        let lines = diffs[0].hunks[0].lines
        let deletionLine = lines.first { $0.kind == .deletion }!
        XCTAssertNil(deletionLine.inlineHighlights)
    }

    // MARK: - Side-by-Side Row Pairing

    func testPairContextLines() {
        let lines = [
            DiffLine(id: 0, kind: .context, text: "unchanged", oldLineNumber: 1, newLineNumber: 1),
        ]
        let hunk = DiffHunk(id: 0, header: "@@ -1,1 +1,1 @@", lines: lines)
        let rows = DiffRowPairer.pairLines(from: [hunk])
        XCTAssertEqual(rows.count, 1)
        XCTAssertNotNil(rows[0].left)
        XCTAssertNotNil(rows[0].right)
        XCTAssertEqual(rows[0].left?.kind, .context)
        XCTAssertEqual(rows[0].right?.kind, .context)
    }

    func testPairMatchedDeletionAddition() {
        let lines = [
            DiffLine(id: 0, kind: .deletion, text: "old", oldLineNumber: 1, newLineNumber: nil),
            DiffLine(id: 1, kind: .addition, text: "new", oldLineNumber: nil, newLineNumber: 1),
        ]
        let hunk = DiffHunk(id: 0, header: "@@ -1,1 +1,1 @@", lines: lines)
        let rows = DiffRowPairer.pairLines(from: [hunk])
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].left?.kind, .deletion)
        XCTAssertEqual(rows[0].right?.kind, .addition)
    }

    func testPairMoreDeletionsThanAdditions() {
        let lines = [
            DiffLine(id: 0, kind: .deletion, text: "del1", oldLineNumber: 1, newLineNumber: nil),
            DiffLine(id: 1, kind: .deletion, text: "del2", oldLineNumber: 2, newLineNumber: nil),
            DiffLine(id: 2, kind: .addition, text: "add1", oldLineNumber: nil, newLineNumber: 1),
        ]
        let hunk = DiffHunk(id: 0, header: "@@ -1,2 +1,1 @@", lines: lines)
        let rows = DiffRowPairer.pairLines(from: [hunk])
        XCTAssertEqual(rows.count, 2)
        // First row: paired
        XCTAssertEqual(rows[0].left?.text, "del1")
        XCTAssertEqual(rows[0].right?.text, "add1")
        // Second row: orphaned deletion
        XCTAssertEqual(rows[1].left?.text, "del2")
        XCTAssertNil(rows[1].right)
    }

    func testPairMoreAdditionsThanDeletions() {
        let lines = [
            DiffLine(id: 0, kind: .deletion, text: "del1", oldLineNumber: 1, newLineNumber: nil),
            DiffLine(id: 1, kind: .addition, text: "add1", oldLineNumber: nil, newLineNumber: 1),
            DiffLine(id: 2, kind: .addition, text: "add2", oldLineNumber: nil, newLineNumber: 2),
        ]
        let hunk = DiffHunk(id: 0, header: "@@ -1,1 +1,2 @@", lines: lines)
        let rows = DiffRowPairer.pairLines(from: [hunk])
        XCTAssertEqual(rows.count, 2)
        // First row: paired
        XCTAssertEqual(rows[0].left?.text, "del1")
        XCTAssertEqual(rows[0].right?.text, "add1")
        // Second row: orphaned addition
        XCTAssertNil(rows[1].left)
        XCTAssertEqual(rows[1].right?.text, "add2")
    }

    func testPairStandaloneAddition() {
        let lines = [
            DiffLine(id: 0, kind: .context, text: "ctx", oldLineNumber: 1, newLineNumber: 1),
            DiffLine(id: 1, kind: .addition, text: "new", oldLineNumber: nil, newLineNumber: 2),
            DiffLine(id: 2, kind: .context, text: "ctx2", oldLineNumber: 2, newLineNumber: 3),
        ]
        let hunk = DiffHunk(id: 0, header: "@@ -1,2 +1,3 @@", lines: lines)
        let rows = DiffRowPairer.pairLines(from: [hunk])
        XCTAssertEqual(rows.count, 3)
        XCTAssertNil(rows[1].left)
        XCTAssertEqual(rows[1].right?.kind, .addition)
    }

    func testPairHunkHeader() {
        let lines = [
            DiffLine(id: 0, kind: .hunkHeader, text: "@@ -1,1 +1,1 @@", oldLineNumber: nil, newLineNumber: nil),
            DiffLine(id: 1, kind: .context, text: "line", oldLineNumber: 1, newLineNumber: 1),
        ]
        let hunk = DiffHunk(id: 0, header: "@@ -1,1 +1,1 @@", lines: lines)
        let rows = DiffRowPairer.pairLines(from: [hunk])
        XCTAssertEqual(rows.count, 2)
        // Hunk header appears on both sides
        XCTAssertEqual(rows[0].left?.kind, .hunkHeader)
        XCTAssertEqual(rows[0].right?.kind, .hunkHeader)
    }

    // MARK: - Patch Reconstruction

    func testReconstructPatch() {
        let diffOutput = """
        diff --git a/hello.txt b/hello.txt
        index abc1234..def5678 100644
        --- a/hello.txt
        +++ b/hello.txt
        @@ -1,3 +1,4 @@
         line one
        -line two
        +line two modified
        +line three new
         line four
        """

        let diffs = DiffParser.parse(diffOutput)
        let patch = DiffParser.reconstructPatch(fileDiff: diffs[0], hunk: diffs[0].hunks[0])

        // Verify the patch has the required git diff headers
        XCTAssertTrue(patch.hasPrefix("diff --git a/hello.txt b/hello.txt\n"))
        XCTAssertTrue(patch.contains("--- a/hello.txt\n"))
        XCTAssertTrue(patch.contains("+++ b/hello.txt\n"))
        XCTAssertTrue(patch.contains("@@ -1,3 +1,4 @@\n"))

        // Verify content lines are properly prefixed
        XCTAssertTrue(patch.contains(" line one\n"))
        XCTAssertTrue(patch.contains("-line two\n"))
        XCTAssertTrue(patch.contains("+line two modified\n"))
        XCTAssertTrue(patch.contains("+line three new\n"))
        XCTAssertTrue(patch.contains(" line four\n"))

        // Verify trailing newline
        XCTAssertTrue(patch.hasSuffix("\n"))
    }

    // MARK: - Gutter Changes

    func testGutterChangesAddedLines() {
        let diffOutput = """
        diff --git a/test.txt b/test.txt
        index 1234567..abcdefg 100644
        --- a/test.txt
        +++ b/test.txt
        @@ -1,2 +1,4 @@
         unchanged
        +added line A
        +added line B
         unchanged
        """

        let diffs = DiffParser.parse(diffOutput)
        let changes = DiffParser.gutterChanges(from: diffs[0])

        // Pure additions (not preceded by deletions) → .added
        XCTAssertEqual(changes[2], .added)
        XCTAssertEqual(changes[3], .added)
        // Context lines have no marker
        XCTAssertNil(changes[1])
        XCTAssertNil(changes[4])
    }

    func testGutterChangesModifiedLines() {
        let diffOutput = """
        diff --git a/test.txt b/test.txt
        index 1234567..abcdefg 100644
        --- a/test.txt
        +++ b/test.txt
        @@ -1,3 +1,3 @@
         unchanged
        -old line
        +new line
         unchanged
        """

        let diffs = DiffParser.parse(diffOutput)
        let changes = DiffParser.gutterChanges(from: diffs[0])

        // Deletion followed immediately by addition → .modified on the new-file line
        XCTAssertEqual(changes[2], .modified)
        XCTAssertNil(changes[1])
        XCTAssertNil(changes[3])
    }

    func testGutterChangesDeletedLines() {
        let diffOutput = """
        diff --git a/test.txt b/test.txt
        index 1234567..abcdefg 100644
        --- a/test.txt
        +++ b/test.txt
        @@ -1,3 +1,2 @@
         before
        -removed line
         after
        """

        let diffs = DiffParser.parse(diffOutput)
        let changes = DiffParser.gutterChanges(from: diffs[0])

        // Pure deletion → .deleted marker placed at nearest new-file line (line 2 = "after")
        XCTAssertEqual(changes[2], .deleted)
        XCTAssertNil(changes[1])
    }

    func testGutterChangesEmptyDiff() {
        let diff = FileDiff(id: "empty.txt", oldPath: "empty.txt", newPath: "empty.txt", hunks: [])
        let changes = DiffParser.gutterChanges(from: diff)
        XCTAssertTrue(changes.isEmpty)
    }

    func testReconstructPatchSelectsOneHunk() {
        let diffOutput = """
        diff --git a/big.txt b/big.txt
        index 1234567..abcdefg 100644
        --- a/big.txt
        +++ b/big.txt
        @@ -1,3 +1,3 @@
         top
        -old top
        +new top
         mid
        @@ -10,3 +10,3 @@
         bottom
        -old bottom
        +new bottom
         end
        """

        let diffs = DiffParser.parse(diffOutput)
        XCTAssertEqual(diffs[0].hunks.count, 2)

        // Reconstruct patch for second hunk only
        let patch = DiffParser.reconstructPatch(fileDiff: diffs[0], hunk: diffs[0].hunks[1])

        // Should contain second hunk header, not first
        XCTAssertTrue(patch.contains("@@ -10,3 +10,3 @@"))
        XCTAssertFalse(patch.contains("@@ -1,3 +1,3 @@"))
        XCTAssertTrue(patch.contains("-old bottom\n"))
        XCTAssertTrue(patch.contains("+new bottom\n"))
        XCTAssertFalse(patch.contains("old top"))
    }
}
