import XCTest
@testable import Anvil

final class BuildDiagnosticAnnotationTests: XCTestCase {

    // MARK: - filterDiagnostics

    func testAbsolutePathMatchesCurrentFile() {
        let url = URL(fileURLWithPath: "/Users/alice/project/Sources/Foo.swift")
        let d = BuildDiagnostic(filePath: "/Users/alice/project/Sources/Foo.swift",
                                line: 10, column: 5, severity: .error, message: "use of unresolved identifier")
        let result = FilePreviewView.filterDiagnostics([d], for: url, relativePath: "Sources/Foo.swift")
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[10]?.message, "use of unresolved identifier")
    }

    func testAbsolutePathDoesNotMatchDifferentFile() {
        let url = URL(fileURLWithPath: "/Users/alice/project/Sources/Bar.swift")
        let d = BuildDiagnostic(filePath: "/Users/alice/project/Sources/Foo.swift",
                                line: 10, column: nil, severity: .error, message: "err")
        let result = FilePreviewView.filterDiagnostics([d], for: url, relativePath: "Sources/Bar.swift")
        XCTAssertTrue(result.isEmpty)
    }

    func testRelativePathExactMatch() {
        let url = URL(fileURLWithPath: "/Users/alice/project/Sources/Foo.swift")
        let d = BuildDiagnostic(filePath: "Sources/Foo.swift",
                                line: 3, column: 1, severity: .warning, message: "unused variable")
        let result = FilePreviewView.filterDiagnostics([d], for: url, relativePath: "Sources/Foo.swift")
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[3]?.severity, .warning)
    }

    func testRelativePathSuffixMatch() {
        let url = URL(fileURLWithPath: "/Users/alice/project/Sources/Foo.swift")
        // Build tool reported just the filename, not the full relative path
        let d = BuildDiagnostic(filePath: "Foo.swift",
                                line: 7, column: nil, severity: .note, message: "note here")
        let result = FilePreviewView.filterDiagnostics([d], for: url, relativePath: "Sources/Foo.swift")
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[7]?.severity, .note)
    }

    func testRelativePathNoMatch() {
        let url = URL(fileURLWithPath: "/Users/alice/project/Sources/Bar.swift")
        let d = BuildDiagnostic(filePath: "Sources/Foo.swift",
                                line: 7, column: nil, severity: .error, message: "err")
        let result = FilePreviewView.filterDiagnostics([d], for: url, relativePath: "Sources/Bar.swift")
        XCTAssertTrue(result.isEmpty)
    }

    func testMultipleDiagnosticsOnSameLineLastWins() {
        let url = URL(fileURLWithPath: "/project/Foo.swift")
        let d1 = BuildDiagnostic(filePath: "Foo.swift", line: 5, column: 1, severity: .error, message: "first")
        let d2 = BuildDiagnostic(filePath: "Foo.swift", line: 5, column: 2, severity: .warning, message: "second")
        let result = FilePreviewView.filterDiagnostics([d1, d2], for: url, relativePath: "Foo.swift")
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[5]?.message, "second")
    }

    func testMultipleDiagnosticsDifferentLines() {
        let url = URL(fileURLWithPath: "/project/Foo.swift")
        let d1 = BuildDiagnostic(filePath: "Foo.swift", line: 5, column: nil, severity: .error, message: "a")
        let d2 = BuildDiagnostic(filePath: "Foo.swift", line: 10, column: nil, severity: .warning, message: "b")
        let result = FilePreviewView.filterDiagnostics([d1, d2], for: url, relativePath: "Foo.swift")
        XCTAssertEqual(result.count, 2)
        XCTAssertNotNil(result[5])
        XCTAssertNotNil(result[10])
    }

    func testEmptyDiagnosticsReturnsEmpty() {
        let url = URL(fileURLWithPath: "/project/Foo.swift")
        let result = FilePreviewView.filterDiagnostics([], for: url, relativePath: "Foo.swift")
        XCTAssertTrue(result.isEmpty)
    }

    func testDiagnosticsForOtherFilesFiltered() {
        let url = URL(fileURLWithPath: "/project/Sources/Foo.swift")
        let dMatch = BuildDiagnostic(filePath: "Sources/Foo.swift", line: 1, column: nil, severity: .error, message: "in foo")
        let dOther = BuildDiagnostic(filePath: "Sources/Bar.swift", line: 2, column: nil, severity: .error, message: "in bar")
        let result = FilePreviewView.filterDiagnostics([dMatch, dOther], for: url, relativePath: "Sources/Foo.swift")
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[1]?.message, "in foo")
    }
}
