import XCTest
@testable import Anvil

final class DiffChangeDescriberTests: XCTestCase {

    // MARK: - Helpers

    private func makeDiff(added: [String] = [], deleted: [String] = []) -> FileDiff {
        var lines: [DiffLine] = []
        var id = 0
        for text in deleted {
            lines.append(DiffLine(id: id, kind: .deletion, text: text, oldLineNumber: id + 1, newLineNumber: nil))
            id += 1
        }
        for text in added {
            lines.append(DiffLine(id: id, kind: .addition, text: text, oldLineNumber: nil, newLineNumber: id + 1))
            id += 1
        }
        let hunk = DiffHunk(id: 0, header: "@@ -1,\(deleted.count) +1,\(added.count) @@", lines: lines)
        return FileDiff(id: "file", oldPath: "file", newPath: "file", hunks: [hunk])
    }

    // MARK: - No diff / unknown extension

    func testNilWhenNoDiff() {
        // No diff — nil expected
        let diff = makeDiff()
        let result = DiffChangeDescriber.describe(diff: diff, fileExtension: "swift")
        XCTAssertNil(result)
    }

    func testNilForUnknownExtension() {
        let diff = makeDiff(added: ["func doSomething() {"])
        let result = DiffChangeDescriber.describe(diff: diff, fileExtension: "xyz")
        XCTAssertNil(result)
    }

    func testNilForConfigFile() {
        // YAML has no recognised language — should return nil even with content
        let diff = makeDiff(added: ["key: value", "another: thing"])
        let result = DiffChangeDescriber.describe(diff: diff, fileExtension: "yml")
        XCTAssertNil(result)
    }

    // MARK: - Added function

    func testAddedSwiftFunction() {
        let diff = makeDiff(added: [
            "func authenticate(user: String) -> Bool {",
            "    return true",
            "}",
        ])
        let result = DiffChangeDescriber.describe(diff: diff, fileExtension: "swift")
        XCTAssertNotNil(result)
        XCTAssertTrue(result!.contains("authenticate"), "Expected function name in description, got: \(result!)")
        XCTAssertTrue(result!.lowercased().contains("added"), "Expected 'Added' prefix, got: \(result!)")
    }

    func testAddedTypeScriptFunction() {
        let diff = makeDiff(added: [
            "export async function fetchUser(id: string): Promise<User> {",
            "    return db.find(id);",
            "}",
        ])
        let result = DiffChangeDescriber.describe(diff: diff, fileExtension: "ts")
        XCTAssertNotNil(result)
        XCTAssertTrue(result!.contains("fetchUser"), "Expected function name, got: \(result!)")
    }

    func testAddedPythonFunction() {
        let diff = makeDiff(added: [
            "def process_request(data):",
            "    pass",
        ])
        let result = DiffChangeDescriber.describe(diff: diff, fileExtension: "py")
        XCTAssertNotNil(result)
        XCTAssertTrue(result!.contains("process_request"), "Expected function name, got: \(result!)")
    }

    // MARK: - Removed function

    func testRemovedSwiftFunction() {
        let diff = makeDiff(deleted: [
            "func deprecatedHelper() {",
            "}",
        ])
        let result = DiffChangeDescriber.describe(diff: diff, fileExtension: "swift")
        XCTAssertNotNil(result)
        XCTAssertTrue(result!.contains("deprecatedHelper"), "Expected function name, got: \(result!)")
        XCTAssertTrue(result!.lowercased().contains("removed"), "Expected 'Removed', got: \(result!)")
    }

    // MARK: - Modified function (present in both added and deleted)

    func testModifiedFunction() {
        let diff = makeDiff(
            added:   ["func processRequest() { /* new impl */ }"],
            deleted: ["func processRequest() { /* old impl */ }"]
        )
        let result = DiffChangeDescriber.describe(diff: diff, fileExtension: "swift")
        XCTAssertNotNil(result)
        XCTAssertTrue(result!.contains("processRequest"), "Expected function name, got: \(result!)")
        XCTAssertTrue(result!.lowercased().contains("updated"), "Expected 'Updated', got: \(result!)")
    }

    // MARK: - Added struct / class

    func testAddedStruct() {
        let diff = makeDiff(added: [
            "struct UserProfile {",
            "    var name: String",
            "}",
        ])
        let result = DiffChangeDescriber.describe(diff: diff, fileExtension: "swift")
        XCTAssertNotNil(result)
        XCTAssertTrue(result!.contains("UserProfile"), "Expected type name, got: \(result!)")
        XCTAssertTrue(result!.lowercased().contains("added"), "Expected 'Added', got: \(result!)")
    }

    // MARK: - Import changes

    func testImportOnlyChanges() {
        let diff = makeDiff(added: ["import Foundation", "import Combine"])
        let result = DiffChangeDescriber.describe(diff: diff, fileExtension: "swift")
        XCTAssertNotNil(result)
        XCTAssertTrue(result!.lowercased().contains("import"), "Expected import mention, got: \(result!)")
    }

    func testImportPlusSymbolChanges() {
        let diff = makeDiff(added: [
            "import Foundation",
            "func newHelper() {",
            "}",
        ])
        let result = DiffChangeDescriber.describe(diff: diff, fileExtension: "swift")
        XCTAssertNotNil(result)
        XCTAssertTrue(result!.contains("newHelper"), "Expected function name, got: \(result!)")
        XCTAssertTrue(result!.lowercased().contains("import"), "Expected import mention, got: \(result!)")
    }

    // MARK: - Truncation

    func testDescriptionIsTruncatedAt80Chars() {
        // Generate many added functions to force a long description
        let funcs = (1...10).map { "func veryLongFunctionName\($0)() {}" }
        let diff = makeDiff(added: funcs)
        let result = DiffChangeDescriber.describe(diff: diff, fileExtension: "swift")
        if let result = result {
            XCTAssertLessThanOrEqual(
                result.count,
                DiffChangeDescriber.maxDescriptionLength,
                "Description should be ≤\(DiffChangeDescriber.maxDescriptionLength) chars, got \(result.count): \(result)"
            )
        }
    }

    // MARK: - Multiple symbols capped at 2

    func testAtMostTwoFunctionNamesListed() {
        let diff = makeDiff(added: [
            "func alpha() {}",
            "func beta() {}",
            "func gamma() {}",
        ])
        let result = DiffChangeDescriber.describe(diff: diff, fileExtension: "swift")
        XCTAssertNotNil(result)
        // "Added alpha(), beta()" — exactly two names and no third one
        let matchingNames = ["alpha", "beta", "gamma"].filter { result!.contains($0) }
        XCTAssertLessThanOrEqual(matchingNames.count, 2, "Should list ≤2 names, got: \(result!)")
    }
}
