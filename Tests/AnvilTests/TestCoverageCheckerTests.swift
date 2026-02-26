import XCTest
@testable import Anvil

final class TestCoverageCheckerTests: XCTestCase {

    // MARK: - Helpers

    private func makeFile(_ name: String) -> ChangedFile {
        ChangedFile(
            url: URL(fileURLWithPath: "/proj/\(name)"),
            relativePath: name,
            status: .modified,
            staging: .unstaged
        )
    }

    // MARK: - notApplicable cases

    func testTestFilesAreNotApplicable() {
        let files = [makeFile("FooTests.swift"), makeFile("bar.test.ts"), makeFile("test_baz.py")]
        let map = TestCoverageChecker.coverage(for: files)
        for file in files {
            XCTAssertEqual(map[file.url], .notApplicable)
        }
    }

    func testUnsupportedExtensionIsNotApplicable() {
        let files = [makeFile("README.md"), makeFile("config.json"), makeFile("style.css")]
        let map = TestCoverageChecker.coverage(for: files)
        for file in files {
            XCTAssertEqual(map[file.url], .notApplicable)
        }
    }

    // MARK: - covered

    func testSwiftImplWithMatchingTestIsMarkedCovered() {
        let impl = makeFile("Foo.swift")
        let tests = makeFile("FooTests.swift")
        let map = TestCoverageChecker.coverage(for: [impl, tests])
        XCTAssertEqual(map[impl.url], .covered)
        XCTAssertEqual(map[tests.url], .notApplicable)
    }

    func testTypeScriptImplWithMatchingTestIsMarkedCovered() {
        let impl = makeFile("bar.ts")
        let tests = makeFile("bar.test.ts")
        let map = TestCoverageChecker.coverage(for: [impl, tests])
        XCTAssertEqual(map[impl.url], .covered)
        XCTAssertEqual(map[tests.url], .notApplicable)
    }

    func testPythonImplWithMatchingTestIsMarkedCovered() {
        let impl = makeFile("baz.py")
        let tests = makeFile("test_baz.py")
        let map = TestCoverageChecker.coverage(for: [impl, tests])
        XCTAssertEqual(map[impl.url], .covered)
    }

    func testGoImplWithMatchingTestIsMarkedCovered() {
        let impl = makeFile("foo.go")
        let tests = makeFile("foo_test.go")
        let map = TestCoverageChecker.coverage(for: [impl, tests])
        XCTAssertEqual(map[impl.url], .covered)
    }

    func testRustImplWithMatchingTestIsMarkedCovered() {
        let impl = makeFile("foo.rs")
        let tests = makeFile("foo_test.rs")
        let map = TestCoverageChecker.coverage(for: [impl, tests])
        XCTAssertEqual(map[impl.url], .covered)
    }

    // MARK: - uncovered

    func testSwiftImplWithNoMatchingTestIsMarkedUncovered() {
        let impl = makeFile("Foo.swift")
        let map = TestCoverageChecker.coverage(for: [impl])
        XCTAssertEqual(map[impl.url], .uncovered)
    }

    func testTypeScriptImplWithNoMatchingTestIsMarkedUncovered() {
        let impl = makeFile("bar.ts")
        let map = TestCoverageChecker.coverage(for: [impl])
        XCTAssertEqual(map[impl.url], .uncovered)
    }

    // MARK: - stats

    func testStatsWithMixedCoverage() {
        let impl1 = makeFile("A.swift")
        let impl2 = makeFile("B.swift")
        let impl3 = makeFile("C.swift")
        let test1 = makeFile("ATests.swift")
        // A is covered, B and C are uncovered, ATests is notApplicable
        let map = TestCoverageChecker.coverage(for: [impl1, impl2, impl3, test1])
        let (covered, total) = TestCoverageChecker.stats(from: map)
        XCTAssertEqual(covered, 1)
        XCTAssertEqual(total, 3)
    }

    func testStatsAllCovered() {
        let impl = makeFile("Foo.swift")
        let tests = makeFile("FooTests.swift")
        let map = TestCoverageChecker.coverage(for: [impl, tests])
        let (covered, total) = TestCoverageChecker.stats(from: map)
        XCTAssertEqual(covered, 1)
        XCTAssertEqual(total, 1)
    }

    func testStatsNoneTracked() {
        let files = [makeFile("README.md"), makeFile("FooTests.swift")]
        let map = TestCoverageChecker.coverage(for: files)
        let (covered, total) = TestCoverageChecker.stats(from: map)
        XCTAssertEqual(covered, 0)
        XCTAssertEqual(total, 0)
    }

    func testStatsEmptyMap() {
        let (covered, total) = TestCoverageChecker.stats(from: [:])
        XCTAssertEqual(covered, 0)
        XCTAssertEqual(total, 0)
    }

    // MARK: - spec variant counts as covered

    func testSpecVariantCountsAsCovered() {
        let impl = makeFile("Foo.swift")
        let spec = makeFile("FooSpec.swift")
        let map = TestCoverageChecker.coverage(for: [impl, spec])
        XCTAssertEqual(map[impl.url], .covered)
    }

    func testJsSpecVariantCountsAsCovered() {
        let impl = makeFile("bar.js")
        let spec = makeFile("bar.spec.js")
        let map = TestCoverageChecker.coverage(for: [impl, spec])
        XCTAssertEqual(map[impl.url], .covered)
    }
}
