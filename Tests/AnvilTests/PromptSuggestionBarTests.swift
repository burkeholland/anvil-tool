import XCTest
@testable import Anvil

final class PromptSuggestionBarTests: XCTestCase {

    // MARK: - Build failure chips

    func testNoBuildChipWhenIdle() {
        let chips = makeChips(buildStatus: .idle)
        XCTAssertTrue(chips.filter { $0.icon == "xmark.octagon.fill" }.isEmpty)
    }

    func testNoBuildChipWhenPassed() {
        let chips = makeChips(buildStatus: .passed)
        XCTAssertTrue(chips.filter { $0.icon == "xmark.octagon.fill" }.isEmpty)
    }

    func testBuildChipAppearsWhenFailed_noDiagnostics() {
        let chips = makeChips(buildStatus: .failed(output: "build failed"))
        let chip = chips.first { $0.icon == "xmark.octagon.fill" }
        XCTAssertNotNil(chip)
        XCTAssertEqual(chip?.label, "Fix build errors")
        XCTAssertEqual(chip?.prompt, "Fix the build errors")
    }

    func testBuildChipShowsErrorCount() {
        let diags = [
            BuildDiagnostic(filePath: "Sources/Foo.swift", line: 1, column: nil, severity: .error, message: "err1"),
            BuildDiagnostic(filePath: "Sources/Bar.swift", line: 2, column: nil, severity: .error, message: "err2"),
        ]
        let chips = makeChips(buildStatus: .failed(output: ""), buildDiagnostics: diags)
        let chip = chips.first { $0.icon == "xmark.octagon.fill" }
        XCTAssertNotNil(chip)
        XCTAssertEqual(chip?.label, "Fix 2 build errors")
        XCTAssertTrue(chip?.prompt.contains("Fix the 2 build errors in") == true)
        XCTAssertTrue(chip?.prompt.contains("Foo.swift") == true || chip?.prompt.contains("Bar.swift") == true)
    }

    func testBuildChipSingleError() {
        let diags = [
            BuildDiagnostic(filePath: "Sources/Foo.swift", line: 1, column: nil, severity: .error, message: "err1"),
        ]
        let chips = makeChips(buildStatus: .failed(output: ""), buildDiagnostics: diags)
        let chip = chips.first { $0.icon == "xmark.octagon.fill" }
        XCTAssertEqual(chip?.label, "Fix 1 build error")
        XCTAssertTrue(chip?.prompt.contains("Fix the 1 build error in") == true)
    }

    func testBuildChipIgnoresWarnings() {
        // Warnings only → chip still appears (build failed) but no error count
        let diags = [
            BuildDiagnostic(filePath: "Sources/Foo.swift", line: 1, column: nil, severity: .warning, message: "warn"),
        ]
        let chips = makeChips(buildStatus: .failed(output: ""), buildDiagnostics: diags)
        let chip = chips.first { $0.icon == "xmark.octagon.fill" }
        XCTAssertNotNil(chip)
        // errorDiags.count == 0, so falls back to generic label
        XCTAssertEqual(chip?.label, "Fix build errors")
    }

    // MARK: - Test failure chips

    func testNoTestChipWhenIdle() {
        let chips = makeChips(testStatus: .idle)
        XCTAssertTrue(chips.filter { $0.icon == "xmark.circle.fill" }.isEmpty)
    }

    func testNoTestChipWhenPassed() {
        let chips = makeChips(testStatus: .passed(total: 5))
        XCTAssertTrue(chips.filter { $0.icon == "xmark.circle.fill" }.isEmpty)
    }

    func testTestChipAppearsWithNoNames() {
        let chips = makeChips(testStatus: .failed(failedTests: [], output: ""))
        let chip = chips.first { $0.icon == "xmark.circle.fill" }
        XCTAssertNotNil(chip)
        XCTAssertEqual(chip?.label, "Fix failing tests")
        XCTAssertEqual(chip?.prompt, "Fix the failing tests")
    }

    func testTestChipWithNames() {
        let chips = makeChips(testStatus: .failed(failedTests: ["testFoo", "testBar"], output: ""))
        let chip = chips.first { $0.icon == "xmark.circle.fill" }
        XCTAssertNotNil(chip)
        XCTAssertEqual(chip?.label, "Fix 2 failing tests")
        XCTAssertTrue(chip?.prompt.contains("testFoo") == true)
        XCTAssertTrue(chip?.prompt.contains("testBar") == true)
    }

    func testTestChipSingleFailure() {
        let chips = makeChips(testStatus: .failed(failedTests: ["testAlpha"], output: ""))
        let chip = chips.first { $0.icon == "xmark.circle.fill" }
        XCTAssertEqual(chip?.label, "Fix 1 failing test")
    }

    func testTestChipTruncatesLongNameList() {
        let names = ["t1", "t2", "t3", "t4", "t5"]
        let chips = makeChips(testStatus: .failed(failedTests: names, output: ""))
        let chip = chips.first { $0.icon == "xmark.circle.fill" }
        XCTAssertEqual(chip?.label, "Fix 5 failing tests")
        // First 3 names appear, extras mentioned as count
        XCTAssertTrue(chip?.prompt.contains("t1") == true)
        XCTAssertTrue(chip?.prompt.contains("and 2 more") == true)
    }

    // MARK: - Unreviewed changes chip

    func testNoExplainChipWhenFewChanges() {
        let chips = makeChips(unreviewedCount: 2)
        XCTAssertTrue(chips.filter { $0.icon == "doc.text.magnifyingglass" }.isEmpty)
    }

    func testExplainChipAppearsAt3() {
        let chips = makeChips(unreviewedCount: 3)
        let chip = chips.first { $0.icon == "doc.text.magnifyingglass" }
        XCTAssertNotNil(chip)
        XCTAssertEqual(chip?.prompt, "Explain what you changed")
    }

    func testExplainChipAppearsAboveThreshold() {
        let chips = makeChips(unreviewedCount: 10)
        XCTAssertNotNil(chips.first { $0.icon == "doc.text.magnifyingglass" })
    }

    // MARK: - Annotation chip

    func testNoAnnotationChipWhenEmpty() {
        let chips = makeChips(annotationCount: 0, annotationPrompt: "")
        XCTAssertTrue(chips.filter { $0.icon == "bubble.left.fill" }.isEmpty)
    }

    func testAnnotationChipAppearsWithCount() {
        let prompt = "Please address the following review annotations:\n\n@Foo.swift#L1: fix this\n"
        let chips = makeChips(annotationCount: 1, annotationPrompt: prompt)
        let chip = chips.first { $0.icon == "bubble.left.fill" }
        XCTAssertNotNil(chip)
        XCTAssertEqual(chip?.label, "Address 1 review note")
        XCTAssertEqual(chip?.prompt, prompt)
    }

    func testAnnotationChipPluralLabel() {
        let prompt = "annotations"
        let chips = makeChips(annotationCount: 3, annotationPrompt: prompt)
        let chip = chips.first { $0.icon == "bubble.left.fill" }
        XCTAssertEqual(chip?.label, "Address 3 review notes")
    }

    func testAnnotationChipSuppressedWhenPromptEmpty() {
        // annotationCount > 0 but prompt is empty → no chip
        let chips = makeChips(annotationCount: 2, annotationPrompt: "")
        XCTAssertTrue(chips.filter { $0.icon == "bubble.left.fill" }.isEmpty)
    }

    // MARK: - Compact session chip

    func testNoCompactChipWhenNotSaturated() {
        let chips = makeChips(isSaturated: false)
        XCTAssertTrue(chips.filter { $0.icon == "arrow.triangle.2.circlepath" }.isEmpty)
    }

    func testCompactChipAppearsWhenSaturated() {
        let chips = makeChips(isSaturated: true)
        let chip = chips.first { $0.icon == "arrow.triangle.2.circlepath" }
        XCTAssertNotNil(chip)
        XCTAssertEqual(chip?.label, "Compact session")
        XCTAssertEqual(chip?.prompt, "/compact")
    }

    // MARK: - Multiple chips

    func testMultipleChipsCanAppearTogether() {
        let diags = [BuildDiagnostic(filePath: "A.swift", line: 1, column: nil, severity: .error, message: "e")]
        let chips = makeChips(
            buildStatus: .failed(output: ""),
            buildDiagnostics: diags,
            testStatus: .failed(failedTests: ["t1"], output: ""),
            unreviewedCount: 5,
            isSaturated: true
        )
        XCTAssertTrue(chips.contains { $0.icon == "xmark.octagon.fill" })
        XCTAssertTrue(chips.contains { $0.icon == "xmark.circle.fill" })
        XCTAssertTrue(chips.contains { $0.icon == "doc.text.magnifyingglass" })
        XCTAssertTrue(chips.contains { $0.icon == "arrow.triangle.2.circlepath" })
    }

    func testNoChipsWhenAllClear() {
        let chips = makeChips()
        XCTAssertTrue(chips.isEmpty)
    }

    // MARK: - Helpers

    private func makeChips(
        buildStatus: BuildVerifier.Status = .idle,
        buildDiagnostics: [BuildDiagnostic] = [],
        testStatus: TestRunner.Status = .idle,
        unreviewedCount: Int = 0,
        totalChangedCount: Int = 0,
        annotationCount: Int = 0,
        annotationPrompt: String = "",
        isSaturated: Bool = false
    ) -> [PromptSuggestion] {
        PromptSuggestionBar.makeChips(
            buildStatus: buildStatus,
            buildDiagnostics: buildDiagnostics,
            testStatus: testStatus,
            unreviewedCount: unreviewedCount,
            totalChangedCount: totalChangedCount,
            annotationCount: annotationCount,
            annotationPrompt: annotationPrompt,
            isSaturated: isSaturated
        )
    }
}
