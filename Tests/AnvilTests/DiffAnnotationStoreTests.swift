import XCTest
@testable import Anvil

final class DiffAnnotationStoreTests: XCTestCase {

    // MARK: - add / update

    func testAddAnnotation() {
        let store = DiffAnnotationStore()
        store.add(filePath: "foo.swift", lineNumber: 10, comment: "wrong name")
        XCTAssertEqual(store.annotations.count, 1)
        XCTAssertEqual(store.annotations[0].filePath, "foo.swift")
        XCTAssertEqual(store.annotations[0].lineNumber, 10)
        XCTAssertEqual(store.annotations[0].comment, "wrong name")
    }

    func testAddAnnotationReplacesExistingForSameLine() {
        let store = DiffAnnotationStore()
        store.add(filePath: "foo.swift", lineNumber: 10, comment: "first")
        store.add(filePath: "foo.swift", lineNumber: 10, comment: "updated")
        XCTAssertEqual(store.annotations.count, 1)
        XCTAssertEqual(store.annotations[0].comment, "updated")
    }

    func testAddAnnotationsDifferentLines() {
        let store = DiffAnnotationStore()
        store.add(filePath: "foo.swift", lineNumber: 5, comment: "a")
        store.add(filePath: "foo.swift", lineNumber: 10, comment: "b")
        XCTAssertEqual(store.annotations.count, 2)
    }

    func testAddAnnotationsDifferentFiles() {
        let store = DiffAnnotationStore()
        store.add(filePath: "a.swift", lineNumber: 1, comment: "x")
        store.add(filePath: "b.swift", lineNumber: 1, comment: "y")
        XCTAssertEqual(store.annotations.count, 2)
    }

    // MARK: - isEmpty

    func testIsEmptyWhenNoAnnotations() {
        let store = DiffAnnotationStore()
        XCTAssertTrue(store.isEmpty)
    }

    func testIsNotEmptyAfterAdd() {
        let store = DiffAnnotationStore()
        store.add(filePath: "a.swift", lineNumber: 1, comment: "x")
        XCTAssertFalse(store.isEmpty)
    }

    // MARK: - remove

    func testRemoveAnnotation() {
        let store = DiffAnnotationStore()
        store.add(filePath: "foo.swift", lineNumber: 10, comment: "note")
        store.remove(filePath: "foo.swift", lineNumber: 10)
        XCTAssertTrue(store.annotations.isEmpty)
    }

    func testRemoveNonExistentIsNoop() {
        let store = DiffAnnotationStore()
        store.add(filePath: "foo.swift", lineNumber: 10, comment: "note")
        store.remove(filePath: "foo.swift", lineNumber: 99)
        XCTAssertEqual(store.annotations.count, 1)
    }

    // MARK: - clearAll

    func testClearAll() {
        let store = DiffAnnotationStore()
        store.add(filePath: "a.swift", lineNumber: 1, comment: "x")
        store.add(filePath: "b.swift", lineNumber: 2, comment: "y")
        store.clearAll()
        XCTAssertTrue(store.annotations.isEmpty)
    }

    // MARK: - comment(forFile:line:)

    func testCommentLookup() {
        let store = DiffAnnotationStore()
        store.add(filePath: "foo.swift", lineNumber: 5, comment: "missing nil check")
        XCTAssertEqual(store.comment(forFile: "foo.swift", line: 5), "missing nil check")
        XCTAssertNil(store.comment(forFile: "foo.swift", line: 6))
        XCTAssertNil(store.comment(forFile: "bar.swift", line: 5))
    }

    // MARK: - lineAnnotations(forFile:)

    func testLineAnnotationsForFile() {
        let store = DiffAnnotationStore()
        store.add(filePath: "foo.swift", lineNumber: 5, comment: "a")
        store.add(filePath: "foo.swift", lineNumber: 10, comment: "b")
        store.add(filePath: "bar.swift", lineNumber: 5, comment: "c")
        let map = store.lineAnnotations(forFile: "foo.swift")
        XCTAssertEqual(map.count, 2)
        XCTAssertEqual(map[5], "a")
        XCTAssertEqual(map[10], "b")
        XCTAssertNotEqual(map[5], "c") // bar.swift annotation must not appear
    }

    // MARK: - buildPrompt

    func testBuildPromptEmpty() {
        let store = DiffAnnotationStore()
        XCTAssertEqual(store.buildPrompt(), "")
    }

    func testBuildPromptSingleAnnotation() {
        let store = DiffAnnotationStore()
        store.add(filePath: "src/Foo.swift", lineNumber: 42, comment: "wrong variable name")
        let prompt = store.buildPrompt()
        XCTAssertTrue(prompt.contains("@src/Foo.swift#L42: wrong variable name"))
        XCTAssertTrue(prompt.hasPrefix("Please address the following review annotations:"))
    }

    func testBuildPromptSortedByFileAndLine() {
        let store = DiffAnnotationStore()
        store.add(filePath: "z.swift", lineNumber: 1, comment: "z")
        store.add(filePath: "a.swift", lineNumber: 20, comment: "a20")
        store.add(filePath: "a.swift", lineNumber: 5, comment: "a5")
        let prompt = store.buildPrompt()
        let a5Range = prompt.range(of: "@a.swift#L5")!
        let a20Range = prompt.range(of: "@a.swift#L20")!
        let zRange = prompt.range(of: "@z.swift#L1")!
        XCTAssertLessThan(a5Range.lowerBound, a20Range.lowerBound)
        XCTAssertLessThan(a20Range.lowerBound, zRange.lowerBound)
    }

    // MARK: - sanitization

    func testAddWithControlCharactersStripped() {
        let store = DiffAnnotationStore()
        // Include a control character (BEL = 0x07) in the comment
        store.add(filePath: "foo.swift", lineNumber: 1, comment: "bad\u{07}comment")
        XCTAssertEqual(store.annotations[0].comment, "badcomment")
    }

    func testAddWithC1ControlCharactersStripped() {
        let store = DiffAnnotationStore()
        // Include a C1 control character (CSI = 0x9B, used in ANSI escape sequences)
        store.add(filePath: "foo.swift", lineNumber: 1, comment: "bad\u{9B}[31mredcomment")
        XCTAssertEqual(store.annotations[0].comment, "bad[31mredcomment")
    }

    func testAddEmptyAfterSanitizationIsIgnored() {
        let store = DiffAnnotationStore()
        // Only control characters — should be stripped to empty and not added
        store.add(filePath: "foo.swift", lineNumber: 1, comment: "\u{01}\u{02}")
        XCTAssertTrue(store.annotations.isEmpty)
    }
}
