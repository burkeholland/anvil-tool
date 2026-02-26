import XCTest
@testable import Anvil

final class TerminalDropHelperTests: XCTestCase {

    // MARK: - projectRelativePath

    func testRelativePathBasic() {
        let root = URL(fileURLWithPath: "/Users/dev/myproject")
        let file = URL(fileURLWithPath: "/Users/dev/myproject/Sources/main.swift")
        XCTAssertEqual(TerminalDropHelper.projectRelativePath(for: file, rootURL: root),
                       "Sources/main.swift")
    }

    func testRelativePathRootWithTrailingSlash() {
        let root = URL(fileURLWithPath: "/Users/dev/myproject/")
        let file = URL(fileURLWithPath: "/Users/dev/myproject/README.md")
        XCTAssertEqual(TerminalDropHelper.projectRelativePath(for: file, rootURL: root),
                       "README.md")
    }

    func testRelativePathFileAtProjectRoot() {
        let root = URL(fileURLWithPath: "/Users/dev/myproject")
        let file = URL(fileURLWithPath: "/Users/dev/myproject/Package.swift")
        XCTAssertEqual(TerminalDropHelper.projectRelativePath(for: file, rootURL: root),
                       "Package.swift")
    }

    func testRelativePathOutsideProject() {
        let root = URL(fileURLWithPath: "/Users/dev/myproject")
        let file = URL(fileURLWithPath: "/Users/dev/other/file.swift")
        XCTAssertEqual(TerminalDropHelper.projectRelativePath(for: file, rootURL: root),
                       "/Users/dev/other/file.swift")
    }

    func testRelativePathNilRoot() {
        let file = URL(fileURLWithPath: "/Users/dev/myproject/main.swift")
        XCTAssertEqual(TerminalDropHelper.projectRelativePath(for: file, rootURL: nil),
                       "/Users/dev/myproject/main.swift")
    }

    func testRelativePathDoesNotMatchPartialName() {
        // "/Users/dev/myproject-other" should NOT be treated as inside "/Users/dev/myproject"
        let root = URL(fileURLWithPath: "/Users/dev/myproject")
        let file = URL(fileURLWithPath: "/Users/dev/myproject-other/file.swift")
        XCTAssertEqual(TerminalDropHelper.projectRelativePath(for: file, rootURL: root),
                       "/Users/dev/myproject-other/file.swift")
    }

    func testRelativePathNestedDirectory() {
        let root = URL(fileURLWithPath: "/Users/dev/myproject")
        let file = URL(fileURLWithPath: "/Users/dev/myproject/Sources/Anvil/Views/ContentView.swift")
        XCTAssertEqual(TerminalDropHelper.projectRelativePath(for: file, rootURL: root),
                       "Sources/Anvil/Views/ContentView.swift")
    }

    // MARK: - shellEscapePath

    func testShellEscapeSimplePath() {
        XCTAssertEqual(TerminalDropHelper.shellEscapePath("Sources/main.swift"),
                       "Sources/main.swift")
    }

    func testShellEscapePathWithSpace() {
        XCTAssertEqual(TerminalDropHelper.shellEscapePath("My Project/main.swift"),
                       "'My Project/main.swift'")
    }

    func testShellEscapePathWithDollarSign() {
        XCTAssertEqual(TerminalDropHelper.shellEscapePath("src/$generated.swift"),
                       "'src/$generated.swift'")
    }

    func testShellEscapePathWithSingleQuote() {
        XCTAssertEqual(TerminalDropHelper.shellEscapePath("src/it's.swift"),
                       "'src/it'\\''s.swift'")
    }

    func testShellEscapePathWithMultipleSpecialChars() {
        XCTAssertEqual(TerminalDropHelper.shellEscapePath("src/foo (bar).swift"),
                       "'src/foo (bar).swift'")
    }

    func testShellEscapePathWithBackslash() {
        XCTAssertEqual(TerminalDropHelper.shellEscapePath("src\\foo.swift"),
                       "'src\\foo.swift'")
    }

    func testShellEscapePathWithTilde() {
        XCTAssertEqual(TerminalDropHelper.shellEscapePath("~/project/main.swift"),
                       "'~/project/main.swift'")
    }

    // MARK: - sanitizePath

    func testSanitizePathNormal() {
        XCTAssertEqual(TerminalDropHelper.sanitizePath("Sources/main.swift"),
                       "Sources/main.swift")
    }

    func testSanitizePathRemovesControlChars() {
        let withControl = "Sources/\u{01}main\u{1B}.swift"
        XCTAssertEqual(TerminalDropHelper.sanitizePath(withControl),
                       "Sources/main.swift")
    }

    func testSanitizePathRemovesDEL() {
        let withDEL = "Sources/ma\u{7F}in.swift"
        XCTAssertEqual(TerminalDropHelper.sanitizePath(withDEL),
                       "Sources/main.swift")
    }

    func testSanitizePathPreservesSpaces() {
        XCTAssertEqual(TerminalDropHelper.sanitizePath("My Project/main.swift"),
                       "My Project/main.swift")
    }
}
