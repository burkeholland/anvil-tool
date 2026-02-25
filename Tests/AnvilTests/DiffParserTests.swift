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
}
