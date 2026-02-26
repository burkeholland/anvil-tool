import XCTest
@testable import Anvil

final class DiffRiskScannerTests: XCTestCase {

    // MARK: - Helpers

    private func makeLine(kind: DiffLine.Kind, text: String,
                          oldLine: Int? = 1, newLine: Int? = nil) -> DiffLine {
        DiffLine(id: 0, kind: kind, text: text,
                 oldLineNumber: oldLine, newLineNumber: newLine)
    }

    private func makeHunk(lines: [DiffLine]) -> DiffHunk {
        DiffHunk(id: 0, header: "@@ -1,4 +1,4 @@", lines: lines)
    }

    // MARK: - Deleted error handling

    func testDeletedCatch() {
        let hunk = makeHunk(lines: [
            makeLine(kind: .deletion, text: "    } catch let error { print(error) }")
        ])
        let flags = DiffRiskScanner.scan(hunk)
        XCTAssertTrue(flags.contains { $0.kind == .deletedErrorHandling })
    }

    func testDeletedRescue() {
        let hunk = makeHunk(lines: [
            makeLine(kind: .deletion, text: "rescue StandardError => e")
        ])
        let flags = DiffRiskScanner.scan(hunk)
        XCTAssertTrue(flags.contains { $0.kind == .deletedErrorHandling })
    }

    func testDeletedExcept() {
        let hunk = makeHunk(lines: [
            makeLine(kind: .deletion, text: "except ValueError as e:")
        ])
        let flags = DiffRiskScanner.scan(hunk)
        XCTAssertTrue(flags.contains { $0.kind == .deletedErrorHandling })
    }

    func testAddedCatchNotFlagged() {
        // Adding a catch block is fine — only deletion is risky
        let hunk = makeHunk(lines: [
            makeLine(kind: .addition, text: "    } catch let error { }", oldLine: nil, newLine: 5)
        ])
        let flags = DiffRiskScanner.scan(hunk)
        XCTAssertFalse(flags.contains { $0.kind == .deletedErrorHandling })
    }

    // MARK: - Deleted nil / guard checks

    func testDeletedNilEquality() {
        let hunk = makeHunk(lines: [
            makeLine(kind: .deletion, text: "if value == nil { return }")
        ])
        let flags = DiffRiskScanner.scan(hunk)
        XCTAssertTrue(flags.contains { $0.kind == .deletedNilCheck })
    }

    func testDeletedNotNil() {
        let hunk = makeHunk(lines: [
            makeLine(kind: .deletion, text: "guard result != nil else { return }")
        ])
        let flags = DiffRiskScanner.scan(hunk)
        XCTAssertTrue(flags.contains { $0.kind == .deletedNilCheck })
    }

    func testDeletedGuardLet() {
        let hunk = makeHunk(lines: [
            makeLine(kind: .deletion, text: "guard let name = user.name else { return }")
        ])
        let flags = DiffRiskScanner.scan(hunk)
        XCTAssertTrue(flags.contains { $0.kind == .deletedNilCheck })
    }

    func testDeletedIfLet() {
        let hunk = makeHunk(lines: [
            makeLine(kind: .deletion, text: "if let value = optional {")
        ])
        let flags = DiffRiskScanner.scan(hunk)
        XCTAssertTrue(flags.contains { $0.kind == .deletedNilCheck })
    }

    // MARK: - Credential-like strings

    func testPasswordAssignment() {
        let hunk = makeHunk(lines: [
            makeLine(kind: .addition, text: #"let password = "hunter2""#, oldLine: nil, newLine: 10)
        ])
        let flags = DiffRiskScanner.scan(hunk)
        XCTAssertTrue(flags.contains { $0.kind == .credentialLike })
    }

    func testApiKeyAssignment() {
        let hunk = makeHunk(lines: [
            makeLine(kind: .addition, text: #"api_key = 'abc123xyz'"#, oldLine: nil, newLine: 12)
        ])
        let flags = DiffRiskScanner.scan(hunk)
        XCTAssertTrue(flags.contains { $0.kind == .credentialLike })
    }

    func testTokenAssignment() {
        let hunk = makeHunk(lines: [
            makeLine(kind: .addition, text: #"let token = "sk-realtoken12345""#, oldLine: nil, newLine: 3)
        ])
        let flags = DiffRiskScanner.scan(hunk)
        XCTAssertTrue(flags.contains { $0.kind == .credentialLike })
    }

    func testPlainVariableNoCredential() {
        // A variable named 'counter' should not trigger the credential scanner
        let hunk = makeHunk(lines: [
            makeLine(kind: .addition, text: #"let counter = "hello""#, oldLine: nil, newLine: 3)
        ])
        let flags = DiffRiskScanner.scan(hunk)
        XCTAssertFalse(flags.contains { $0.kind == .credentialLike })
    }

    // MARK: - Force-unwrap additions

    func testForceUnwrapOnIdentifier() {
        let hunk = makeHunk(lines: [
            makeLine(kind: .addition, text: "let x = optional!", oldLine: nil, newLine: 7)
        ])
        let flags = DiffRiskScanner.scan(hunk)
        XCTAssertTrue(flags.contains { $0.kind == .forceUnwrap })
    }

    func testForceUnwrapOnSubscript() {
        let hunk = makeHunk(lines: [
            makeLine(kind: .addition, text: "let y = dict[key]!", oldLine: nil, newLine: 8)
        ])
        let flags = DiffRiskScanner.scan(hunk)
        XCTAssertTrue(flags.contains { $0.kind == .forceUnwrap })
    }

    func testNotEqualDoesNotTriggerForceUnwrap() {
        let hunk = makeHunk(lines: [
            makeLine(kind: .addition, text: "if x != nil {", oldLine: nil, newLine: 9)
        ])
        let flags = DiffRiskScanner.scan(hunk)
        XCTAssertFalse(flags.contains { $0.kind == .forceUnwrap })
    }

    func testCommentLineDoesNotTriggerForceUnwrap() {
        let hunk = makeHunk(lines: [
            makeLine(kind: .addition, text: "// force-unwrap is bad!", oldLine: nil, newLine: 11)
        ])
        let flags = DiffRiskScanner.scan(hunk)
        XCTAssertFalse(flags.contains { $0.kind == .forceUnwrap })
    }

    func testForceUnwrapInDeletion_notFlagged() {
        // Force-unwrap in a deletion should not be flagged (it's being removed, not added)
        let hunk = makeHunk(lines: [
            makeLine(kind: .deletion, text: "let x = optional!")
        ])
        let flags = DiffRiskScanner.scan(hunk)
        XCTAssertFalse(flags.contains { $0.kind == .forceUnwrap })
    }

    // MARK: - Deleted test assertions

    func testDeletedXCTAssert() {
        let hunk = makeHunk(lines: [
            makeLine(kind: .deletion, text: "XCTAssertEqual(result, expected)")
        ])
        let flags = DiffRiskScanner.scan(hunk)
        XCTAssertTrue(flags.contains { $0.kind == .deletedTestAssertion })
    }

    func testDeletedAssertCall() {
        let hunk = makeHunk(lines: [
            makeLine(kind: .deletion, text: "assert(value > 0, \"must be positive\")")
        ])
        let flags = DiffRiskScanner.scan(hunk)
        XCTAssertTrue(flags.contains { $0.kind == .deletedTestAssertion })
    }

    // MARK: - TODO / HACK markers

    func testAddedTodo() {
        let hunk = makeHunk(lines: [
            makeLine(kind: .addition, text: "// TODO: fix this later", oldLine: nil, newLine: 5)
        ])
        let flags = DiffRiskScanner.scan(hunk)
        XCTAssertTrue(flags.contains { $0.kind == .todoHackMarker })
    }

    func testAddedHack() {
        let hunk = makeHunk(lines: [
            makeLine(kind: .addition, text: "// HACK: temporary workaround", oldLine: nil, newLine: 6)
        ])
        let flags = DiffRiskScanner.scan(hunk)
        XCTAssertTrue(flags.contains { $0.kind == .todoHackMarker })
    }

    func testAddedFixme() {
        let hunk = makeHunk(lines: [
            makeLine(kind: .addition, text: "// FIXME: broken edge case", oldLine: nil, newLine: 7)
        ])
        let flags = DiffRiskScanner.scan(hunk)
        XCTAssertTrue(flags.contains { $0.kind == .todoHackMarker })
    }

    func testDeletedTodoNotFlagged() {
        // Removing a TODO is fine
        let hunk = makeHunk(lines: [
            makeLine(kind: .deletion, text: "// TODO: old task")
        ])
        let flags = DiffRiskScanner.scan(hunk)
        XCTAssertFalse(flags.contains { $0.kind == .todoHackMarker })
    }

    // MARK: - Context lines ignored

    func testContextLinesNotScanned() {
        let hunk = makeHunk(lines: [
            DiffLine(id: 0, kind: .context, text: "catch let error { }",
                     oldLineNumber: 1, newLineNumber: 1)
        ])
        let flags = DiffRiskScanner.scan(hunk)
        XCTAssertTrue(flags.isEmpty)
    }

    // MARK: - Empty hunk

    func testEmptyHunkProducesNoFlags() {
        let hunk = makeHunk(lines: [])
        XCTAssertTrue(DiffRiskScanner.scan(hunk).isEmpty)
    }

    // MARK: - Multiple flags in one hunk

    func testMultipleFlagsInOneHunk() {
        let hunk = makeHunk(lines: [
            makeLine(kind: .deletion, text: "    } catch { }"),
            makeLine(kind: .addition, text: "// TODO: handle error", oldLine: nil, newLine: 5),
        ])
        let flags = DiffRiskScanner.scan(hunk)
        XCTAssertTrue(flags.contains { $0.kind == .deletedErrorHandling })
        XCTAssertTrue(flags.contains { $0.kind == .todoHackMarker })
    }
}
