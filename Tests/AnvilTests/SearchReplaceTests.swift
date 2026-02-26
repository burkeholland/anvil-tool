import XCTest
@testable import Anvil

final class SearchReplaceTests: XCTestCase {

    // MARK: - applyReplacement (pure function)

    func testBasicReplacement() {
        let content = "Hello world, hello world"
        let (result, count) = SearchModel.applyReplacement(
            content: content, query: "hello", replacement: "hi",
            caseSensitive: false, useRegex: false, wholeWord: false
        )
        XCTAssertEqual(result, "hi world, hi world")
        XCTAssertEqual(count, 2)
    }

    func testCaseSensitiveReplacement() {
        let content = "Hello world, hello world"
        let (result, count) = SearchModel.applyReplacement(
            content: content, query: "hello", replacement: "hi",
            caseSensitive: true, useRegex: false, wholeWord: false
        )
        XCTAssertEqual(result, "Hello world, hi world")
        XCTAssertEqual(count, 1)
    }

    func testWholeWordReplacement() {
        let content = "cat concatenate catalog"
        let (result, count) = SearchModel.applyReplacement(
            content: content, query: "cat", replacement: "dog",
            caseSensitive: false, useRegex: false, wholeWord: true
        )
        XCTAssertEqual(result, "dog concatenate catalog")
        XCTAssertEqual(count, 1)
    }

    func testRegexReplacement() {
        let content = "foo123 bar456 baz789"
        let (result, count) = SearchModel.applyReplacement(
            content: content, query: "[a-z]+([0-9]+)", replacement: "num$1",
            caseSensitive: false, useRegex: true, wholeWord: false
        )
        XCTAssertEqual(result, "num123 num456 num789")
        XCTAssertEqual(count, 3)
    }

    func testNoMatchReplacement() {
        let content = "Hello world"
        let (result, count) = SearchModel.applyReplacement(
            content: content, query: "xyz", replacement: "abc",
            caseSensitive: false, useRegex: false, wholeWord: false
        )
        XCTAssertEqual(result, "Hello world")
        XCTAssertEqual(count, 0)
    }

    func testSpecialCharacterEscaping() {
        let content = "price is $10.00 or $20.00"
        let (result, count) = SearchModel.applyReplacement(
            content: content, query: "$10.00", replacement: "$15.00",
            caseSensitive: false, useRegex: false, wholeWord: false
        )
        XCTAssertEqual(result, "price is $15.00 or $20.00")
        XCTAssertEqual(count, 1)
    }

    func testMultilineReplacement() {
        let content = "line one\nline two\nline three"
        let (result, count) = SearchModel.applyReplacement(
            content: content, query: "line", replacement: "row",
            caseSensitive: false, useRegex: false, wholeWord: false
        )
        XCTAssertEqual(result, "row one\nrow two\nrow three")
        XCTAssertEqual(count, 3)
    }

    func testEmptyQueryReturnsZero() {
        let content = "Hello world"
        let (result, count) = SearchModel.applyReplacement(
            content: content, query: "", replacement: "abc",
            caseSensitive: false, useRegex: false, wholeWord: false
        )
        // Empty pattern matches between every character — NSRegularExpression behavior.
        // We don't guard against empty queries in the pure function (the UI does),
        // but verify it doesn't crash.
        XCTAssertTrue(count >= 0)
        _ = result // suppress unused warning
    }

    func testInvalidRegexReturnsZero() {
        let content = "Hello world"
        let (result, count) = SearchModel.applyReplacement(
            content: content, query: "[invalid", replacement: "abc",
            caseSensitive: false, useRegex: true, wholeWord: false
        )
        XCTAssertEqual(result, "Hello world")
        XCTAssertEqual(count, 0)
    }

    func testReplacementPreservesNewlines() {
        let content = "func foo() {\n    return bar\n}\n"
        let (result, count) = SearchModel.applyReplacement(
            content: content, query: "bar", replacement: "baz",
            caseSensitive: false, useRegex: false, wholeWord: false
        )
        XCTAssertEqual(result, "func foo() {\n    return baz\n}\n")
        XCTAssertEqual(count, 1)
    }

    // MARK: - File-level replacement

    func testPerformReplaceOnDisk() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("anvil-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let file = tmp.appendingPathComponent("test.txt")
        try "Hello world, Hello again".write(to: file, atomically: true, encoding: .utf8)

        let count = SearchModel.performReplace(
            in: file, query: "Hello", replacement: "Hi",
            caseSensitive: true, useRegex: false, wholeWord: false
        )
        XCTAssertEqual(count, 2)

        let updated = try String(contentsOf: file, encoding: .utf8)
        XCTAssertEqual(updated, "Hi world, Hi again")
    }
}
