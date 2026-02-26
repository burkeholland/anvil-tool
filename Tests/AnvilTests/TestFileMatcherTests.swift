import XCTest
@testable import Anvil

final class TestFileMatcherTests: XCTestCase {

    // MARK: - isTestFile

    func testSwiftTestFilesAreDetected() {
        XCTAssertTrue(TestFileMatcher.isTestFile("FooTests.swift"))
        XCTAssertTrue(TestFileMatcher.isTestFile("FooTest.swift"))
        XCTAssertTrue(TestFileMatcher.isTestFile("FooSpec.swift"))
    }

    func testSwiftImplementationFilesAreNotDetected() {
        XCTAssertFalse(TestFileMatcher.isTestFile("Foo.swift"))
        XCTAssertFalse(TestFileMatcher.isTestFile("ContentView.swift"))
    }

    func testTypeScriptTestFilesAreDetected() {
        XCTAssertTrue(TestFileMatcher.isTestFile("bar.test.ts"))
        XCTAssertTrue(TestFileMatcher.isTestFile("bar.spec.ts"))
        XCTAssertTrue(TestFileMatcher.isTestFile("bar.test.tsx"))
        XCTAssertTrue(TestFileMatcher.isTestFile("bar.spec.tsx"))
    }

    func testJavaScriptTestFilesAreDetected() {
        XCTAssertTrue(TestFileMatcher.isTestFile("bar.test.js"))
        XCTAssertTrue(TestFileMatcher.isTestFile("bar.spec.js"))
        XCTAssertTrue(TestFileMatcher.isTestFile("bar.test.jsx"))
        XCTAssertTrue(TestFileMatcher.isTestFile("bar.spec.jsx"))
    }

    func testPythonTestFilesAreDetected() {
        XCTAssertTrue(TestFileMatcher.isTestFile("test_baz.py"))
        XCTAssertTrue(TestFileMatcher.isTestFile("baz_test.py"))
    }

    func testGoTestFilesAreDetected() {
        XCTAssertTrue(TestFileMatcher.isTestFile("foo_test.go"))
    }

    func testRustTestFilesAreDetected() {
        XCTAssertTrue(TestFileMatcher.isTestFile("foo_test.rs"))
    }

    // MARK: - candidateImplementationNames

    func testSwiftTestToImpl() {
        XCTAssertEqual(TestFileMatcher.candidateImplementationNames(for: "FooTests.swift"), ["Foo.swift"])
        XCTAssertEqual(TestFileMatcher.candidateImplementationNames(for: "FooTest.swift"), ["Foo.swift"])
        XCTAssertEqual(TestFileMatcher.candidateImplementationNames(for: "FooSpec.swift"), ["Foo.swift"])
    }

    func testSwiftImplReturnsNil() {
        XCTAssertNil(TestFileMatcher.candidateImplementationNames(for: "Foo.swift"))
    }

    func testTypeScriptTestToImpl() {
        XCTAssertEqual(TestFileMatcher.candidateImplementationNames(for: "bar.test.ts"), ["bar.ts"])
        XCTAssertEqual(TestFileMatcher.candidateImplementationNames(for: "bar.spec.ts"), ["bar.ts"])
        XCTAssertEqual(TestFileMatcher.candidateImplementationNames(for: "bar.test.tsx"), ["bar.tsx"])
    }

    func testJavaScriptTestToImpl() {
        XCTAssertEqual(TestFileMatcher.candidateImplementationNames(for: "bar.test.js"), ["bar.js"])
        XCTAssertEqual(TestFileMatcher.candidateImplementationNames(for: "bar.spec.jsx"), ["bar.jsx"])
    }

    func testPythonTestToImpl() {
        XCTAssertEqual(TestFileMatcher.candidateImplementationNames(for: "test_baz.py"), ["baz.py"])
        XCTAssertEqual(TestFileMatcher.candidateImplementationNames(for: "baz_test.py"), ["baz.py"])
    }

    func testGoTestToImpl() {
        XCTAssertEqual(TestFileMatcher.candidateImplementationNames(for: "foo_test.go"), ["foo.go"])
    }

    func testRustTestToImpl() {
        XCTAssertEqual(TestFileMatcher.candidateImplementationNames(for: "foo_test.rs"), ["foo.rs"])
    }

    // MARK: - candidateTestNames

    func testSwiftImplToTest() {
        let names = TestFileMatcher.candidateTestNames(for: "Foo.swift")
        XCTAssertEqual(names, ["FooTests.swift", "FooTest.swift", "FooSpec.swift"])
    }

    func testTypeScriptImplToTest() {
        let names = TestFileMatcher.candidateTestNames(for: "bar.ts")
        XCTAssertEqual(names, ["bar.test.ts", "bar.spec.ts"])
    }

    func testJavaScriptImplToTest() {
        let names = TestFileMatcher.candidateTestNames(for: "bar.js")
        XCTAssertEqual(names, ["bar.test.js", "bar.spec.js"])
    }

    func testPythonImplToTest() {
        let names = TestFileMatcher.candidateTestNames(for: "baz.py")
        XCTAssertEqual(names, ["test_baz.py", "baz_test.py"])
    }

    func testGoImplToTest() {
        let names = TestFileMatcher.candidateTestNames(for: "foo.go")
        XCTAssertEqual(names, ["foo_test.go"])
    }

    func testRustImplToTest() {
        let names = TestFileMatcher.candidateTestNames(for: "foo.rs")
        XCTAssertEqual(names, ["foo_test.rs"])
    }

    func testCandidateTestNamesReturnsNilForTestFiles() {
        XCTAssertNil(TestFileMatcher.candidateTestNames(for: "FooTests.swift"))
        XCTAssertNil(TestFileMatcher.candidateTestNames(for: "bar.test.ts"))
        XCTAssertNil(TestFileMatcher.candidateTestNames(for: "test_baz.py"))
    }

    func testUnsupportedExtensionReturnsNil() {
        XCTAssertNil(TestFileMatcher.candidateTestNames(for: "readme.md"))
        XCTAssertNil(TestFileMatcher.candidateImplementationNames(for: "readme.md"))
    }

    // MARK: - counterpart(for:in:) with real filesystem

    func testCounterpartFindsTestInSameDirectory() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let implURL = dir.appendingPathComponent("Foo.swift")
        let testURL = dir.appendingPathComponent("FooTests.swift")
        try "".write(to: implURL, atomically: true, encoding: .utf8)
        try "".write(to: testURL, atomically: true, encoding: .utf8)

        let result = TestFileMatcher.counterpart(for: implURL, in: dir)
        XCTAssertEqual(result, testURL)
    }

    func testCounterpartFindsImplInSameDirectory() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let implURL = dir.appendingPathComponent("Foo.swift")
        let testURL = dir.appendingPathComponent("FooTests.swift")
        try "".write(to: implURL, atomically: true, encoding: .utf8)
        try "".write(to: testURL, atomically: true, encoding: .utf8)

        let result = TestFileMatcher.counterpart(for: testURL, in: dir)
        XCTAssertEqual(result, implURL)
    }

    func testCounterpartFindsTestInSubdirectory() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let srcDir = root.appendingPathComponent("Sources")
        let testDir = root.appendingPathComponent("Tests")
        try FileManager.default.createDirectory(at: srcDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: testDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let implURL = srcDir.appendingPathComponent("Bar.swift")
        let testURL = testDir.appendingPathComponent("BarTests.swift")
        try "".write(to: implURL, atomically: true, encoding: .utf8)
        try "".write(to: testURL, atomically: true, encoding: .utf8)

        let result = TestFileMatcher.counterpart(for: implURL, in: root)
        XCTAssertEqual(result, testURL)
    }

    func testCounterpartReturnsNilWhenNoMatch() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let implURL = dir.appendingPathComponent("Foo.swift")
        try "".write(to: implURL, atomically: true, encoding: .utf8)

        let result = TestFileMatcher.counterpart(for: implURL, in: dir)
        XCTAssertNil(result)
    }
}
