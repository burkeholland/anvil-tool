import XCTest
@testable import Anvil

final class AgentInputWatcherTests: XCTestCase {
    let watcher = AgentInputWatcher()

    // MARK: - isPromptLine

    func testInquirerStylePrompt() {
        XCTAssertTrue(watcher.isPromptLine("? Do you want to proceed?"))
    }

    func testInquirerStylePromptWithLeadingSpace() {
        XCTAssertTrue(watcher.isPromptLine("  ? Please confirm your choice"))
    }

    func testConfirmationSuffixLowercase() {
        XCTAssertTrue(watcher.isPromptLine("Continue? [y/n]"))
    }

    func testConfirmationSuffixUpperY() {
        XCTAssertTrue(watcher.isPromptLine("Are you sure? [Y/n]"))
    }

    func testConfirmationSuffixLowerN() {
        XCTAssertTrue(watcher.isPromptLine("Delete file? [y/N]"))
    }

    func testConfirmationSuffixParentheses() {
        XCTAssertTrue(watcher.isPromptLine("Apply changes? (y/n)"))
    }

    func testPressEnterPrompt() {
        XCTAssertTrue(watcher.isPromptLine("Press Enter to continue"))
    }

    func testPressEnterCaseInsensitive() {
        XCTAssertTrue(watcher.isPromptLine("press enter to confirm"))
    }

    func testRegularOutputLineIsNotPrompt() {
        XCTAssertFalse(watcher.isPromptLine("Reading files from disk..."))
    }

    func testEmptyLineIsNotPrompt() {
        XCTAssertFalse(watcher.isPromptLine(""))
    }

    func testWhitespaceOnlyLineIsNotPrompt() {
        XCTAssertFalse(watcher.isPromptLine("   "))
    }

    func testCodeOutputIsNotPrompt() {
        XCTAssertFalse(watcher.isPromptLine("  if condition {"))
    }

    func testFilenameWithQuestionMarkIsNotPrompt() {
        // A random line containing a question mark in the middle shouldn't trigger
        XCTAssertFalse(watcher.isPromptLine("What is the answer: 42"))
    }

    // MARK: - containsSpinner

    func testBrailleSpinnerDetected() {
        XCTAssertTrue(watcher.containsSpinner("⠋ Thinking..."))
    }

    func testBrailleSpinnerMidLine() {
        XCTAssertTrue(watcher.containsSpinner("Processing ⠼ please wait"))
    }

    func testAllBrailleSpinnerChars() {
        let spinners = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]
        for spinner in spinners {
            XCTAssertTrue(watcher.containsSpinner("\(spinner) working"), "Expected spinner '\(spinner)' to be detected")
        }
    }

    func testRegularTextHasNoSpinner() {
        XCTAssertFalse(watcher.containsSpinner("normal terminal output"))
    }

    func testEmptyStringHasNoSpinner() {
        XCTAssertFalse(watcher.containsSpinner(""))
    }

    // MARK: - Combined: prompt without spinner → waiting; prompt with spinner → not waiting

    func testPromptWithoutSpinnerIsWaiting() {
        // A clean prompt line → should be considered waiting
        XCTAssertTrue(watcher.isPromptLine("? Allow Copilot to run this plan? [Y/n]"))
        XCTAssertFalse(watcher.containsSpinner("? Allow Copilot to run this plan? [Y/n]"))
    }

    func testPromptWithSpinnerIsNotWaiting() {
        // A spinner on the same line means the agent is still working
        let line = "⠋ ? thinking about the plan [y/n]"
        XCTAssertTrue(watcher.isPromptLine(line))
        XCTAssertTrue(watcher.containsSpinner(line))
        // Combined: isWaiting = prompt && !spinner → false
        let waiting = watcher.isPromptLine(line) && !watcher.containsSpinner(line)
        XCTAssertFalse(waiting)
    }
}
