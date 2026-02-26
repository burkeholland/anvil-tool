import XCTest
@testable import Anvil

final class TerminalFilePathDetectorTests: XCTestCase {
    let detector = TerminalFilePathDetector()

    // MARK: - extractPathToken

    func testExtractSimplePath() {
        let line = "error in Sources/Anvil/ContentView.swift during compilation"
        let token = detector.extractPathToken(from: line, column: 20)
        XCTAssertEqual(token, "Sources/Anvil/ContentView.swift")
    }

    func testExtractPathWithLineNumber() {
        let line = "Sources/Anvil/ContentView.swift:42:10: error: missing return"
        let token = detector.extractPathToken(from: line, column: 10)
        XCTAssertEqual(token, "Sources/Anvil/ContentView.swift:42:10")
    }

    func testExtractPathWithLineOnly() {
        let line = "  main.swift:99 warning: unused variable"
        let token = detector.extractPathToken(from: line, column: 8)
        XCTAssertEqual(token, "main.swift:99")
    }

    func testExtractPathStripsTrailingColon() {
        let line = "file.swift:42: error here"
        let token = detector.extractPathToken(from: line, column: 5)
        XCTAssertEqual(token, "file.swift:42")
    }

    func testExtractPathEmptyLine() {
        XCTAssertNil(detector.extractPathToken(from: "", column: 0))
    }

    func testExtractPathNoPathLikeContent() {
        let line = "just some words here"
        XCTAssertNil(detector.extractPathToken(from: line, column: 5))
    }

    // MARK: - parseLineNumber

    func testParseLineNumberPlainPath() {
        let (path, line) = detector.parseLineNumber(from: "src/main.swift")
        XCTAssertEqual(path, "src/main.swift")
        XCTAssertNil(line)
    }

    func testParseLineNumberWithLine() {
        let (path, line) = detector.parseLineNumber(from: "src/main.swift:42")
        XCTAssertEqual(path, "src/main.swift")
        XCTAssertEqual(line, 42)
    }

    func testParseLineNumberWithLineAndCol() {
        let (path, line) = detector.parseLineNumber(from: "src/main.swift:42:10")
        XCTAssertEqual(path, "src/main.swift")
        XCTAssertEqual(line, 42)
    }

    func testParseLineNumberNonNumericSuffix() {
        let (path, line) = detector.parseLineNumber(from: "readme.md")
        XCTAssertEqual(path, "readme.md")
        XCTAssertNil(line)
    }

    // MARK: - extractURL

    func testExtractHTTPSURL() {
        let line = "See https://github.com/user/repo/pull/123 for details"
        let url = detector.extractURL(from: line, column: 20)
        XCTAssertEqual(url?.absoluteString, "https://github.com/user/repo/pull/123")
    }

    func testExtractHTTPURL() {
        let line = "Running at http://localhost:3000/api"
        let url = detector.extractURL(from: line, column: 18)
        XCTAssertEqual(url?.absoluteString, "http://localhost:3000/api")
    }

    func testExtractURLClickOutsideRange() {
        let line = "See https://github.com/repo for details"
        let url = detector.extractURL(from: line, column: 0)
        XCTAssertNil(url)
    }

    func testExtractURLNoURL() {
        let line = "no urls here at all"
        let url = detector.extractURL(from: line, column: 5)
        XCTAssertNil(url)
    }

    func testExtractURLStripsTrailingPunctuation() {
        let line = "Visit https://example.com/page."
        let url = detector.extractURL(from: line, column: 15)
        XCTAssertEqual(url?.absoluteString, "https://example.com/page")
    }

    func testExtractURLWithQueryParams() {
        let line = "Open https://example.com/search?q=test&page=1 to see results"
        let url = detector.extractURL(from: line, column: 20)
        XCTAssertEqual(url?.absoluteString, "https://example.com/search?q=test&page=1")
    }

    // MARK: - scanOutputLine

    func testScanOutputLineNilRootURL() {
        let line = "Writing Sources/Anvil/ContentView.swift..."
        let url = detector.scanOutputLine(line, rootURL: nil)
        XCTAssertNil(url, "Should return nil when no root URL is provided")
    }

    func testScanOutputLineEmptyLine() {
        let tmp = FileManager.default.temporaryDirectory
        let url = detector.scanOutputLine("", rootURL: tmp)
        XCTAssertNil(url, "Should return nil for an empty line")
    }

    func testScanOutputLineNoPathLikeContent() {
        let tmp = FileManager.default.temporaryDirectory
        let url = detector.scanOutputLine("just some plain text", rootURL: tmp)
        XCTAssertNil(url, "Should return nil when no file-path-like tokens are present")
    }

    func testScanOutputLineWithExistingFile() throws {
        let tmp = FileManager.default.temporaryDirectory
        let fileName = "test_scan_\(UUID().uuidString).txt"
        let fileURL = tmp.appendingPathComponent(fileName)
        FileManager.default.createFile(atPath: fileURL.path, contents: Data())
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let line = "Writing \(fileName) to disk"
        let result = detector.scanOutputLine(line, rootURL: tmp)
        XCTAssertEqual(result?.standardizedFileURL, fileURL.standardizedFileURL,
                       "Should resolve an existing file mentioned in a terminal output line")
    }

    func testScanOutputLineWithNonExistentFile() {
        let tmp = FileManager.default.temporaryDirectory
        let line = "Writing nonexistent_file_abc123.swift to disk"
        let result = detector.scanOutputLine(line, rootURL: tmp)
        XCTAssertNil(result, "Should return nil when mentioned file does not exist on disk")
    }

    func testScanOutputLinePicksFirstMatch() throws {
        let tmp = FileManager.default.temporaryDirectory
        let file1 = "first_\(UUID().uuidString).txt"
        let file2 = "second_\(UUID().uuidString).txt"
        let url1 = tmp.appendingPathComponent(file1)
        let url2 = tmp.appendingPathComponent(file2)
        FileManager.default.createFile(atPath: url1.path, contents: Data())
        FileManager.default.createFile(atPath: url2.path, contents: Data())
        defer {
            try? FileManager.default.removeItem(at: url1)
            try? FileManager.default.removeItem(at: url2)
        }

        let line = "Wrote \(file1) and also \(file2)"
        let result = detector.scanOutputLine(line, rootURL: tmp)
        XCTAssertEqual(result?.standardizedFileURL, url1.standardizedFileURL,
                       "Should return the first matching file in the line")
    }
}
