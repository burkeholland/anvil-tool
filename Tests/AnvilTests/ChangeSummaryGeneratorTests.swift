import XCTest
@testable import Anvil

final class ChangeSummaryGeneratorTests: XCTestCase {

    // Helper to make a ChangedFile without a diff
    private func makeFile(_ path: String, status: GitFileStatus) -> ChangedFile {
        ChangedFile(url: URL(fileURLWithPath: "/repo/\(path)"), relativePath: path, status: status, staging: .unstaged)
    }

    func testEmptyFileList() {
        let output = ChangeSummaryGenerator.generate(files: [])
        XCTAssertTrue(output.contains("0 files changed"))
    }

    func testSingleAddedFile() {
        let file = makeFile("Sources/Foo.swift", status: .added)
        let output = ChangeSummaryGenerator.generate(files: [file])
        XCTAssertTrue(output.contains("1 file changed"))
        XCTAssertTrue(output.contains("1 added"))
        XCTAssertTrue(output.contains("### Added"))
        XCTAssertTrue(output.contains("`Sources/Foo.swift`"))
    }

    func testTaskPromptIsIncluded() {
        let output = ChangeSummaryGenerator.generate(files: [], taskPrompt: "Fix the login bug")
        XCTAssertTrue(output.contains("## Task"))
        XCTAssertTrue(output.contains("> Fix the login bug"))
    }

    func testTaskPromptIsOmittedWhenNil() {
        let output = ChangeSummaryGenerator.generate(files: [])
        XCTAssertFalse(output.contains("## Task"))
    }

    func testMultipleStatusCategories() {
        let files = [
            makeFile("New.swift", status: .added),
            makeFile("Existing.swift", status: .modified),
            makeFile("Old.swift", status: .deleted),
        ]
        let output = ChangeSummaryGenerator.generate(files: files)
        XCTAssertTrue(output.contains("3 files changed"))
        XCTAssertTrue(output.contains("1 added"))
        XCTAssertTrue(output.contains("1 modified"))
        XCTAssertTrue(output.contains("1 deleted"))
        XCTAssertTrue(output.contains("### Added"))
        XCTAssertTrue(output.contains("### Modified"))
        XCTAssertTrue(output.contains("### Deleted"))
    }

    func testMultilinePromptIsQuoted() {
        let prompt = "Line one\nLine two"
        let output = ChangeSummaryGenerator.generate(files: [], taskPrompt: prompt)
        XCTAssertTrue(output.contains("> Line one"))
        XCTAssertTrue(output.contains("> Line two"))
    }

    func testEmptyPromptIsIgnored() {
        let output = ChangeSummaryGenerator.generate(files: [], taskPrompt: "  \n  ")
        XCTAssertFalse(output.contains("## Task"))
    }
}
