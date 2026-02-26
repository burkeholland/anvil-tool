import XCTest
@testable import Anvil

final class NewTaskViewTests: XCTestCase {

    // MARK: - slugify

    func testSlugifyLowercasesInput() {
        XCTAssertEqual(NewTaskView.slugify("HelloWorld"), "helloworld")
    }

    func testSlugifyReplaceSpacesWithDashes() {
        XCTAssertEqual(NewTaskView.slugify("add user auth"), "add-user-auth")
    }

    func testSlugifyStripsLeadingAndTrailingDashes() {
        XCTAssertEqual(NewTaskView.slugify("  add login  "), "add-login")
    }

    func testSlugifyCollapsesMultipleSeparators() {
        XCTAssertEqual(NewTaskView.slugify("add -- login"), "add-login")
    }

    func testSlugifyRemovesNonAlphanumeric() {
        XCTAssertEqual(NewTaskView.slugify("fix: auth/login bug!"), "fix-auth-login-bug")
    }

    func testSlugifyEmptyString() {
        XCTAssertEqual(NewTaskView.slugify(""), "")
    }

    func testSlugifyOnlySpecialChars() {
        XCTAssertEqual(NewTaskView.slugify("!!!"), "")
    }

    // MARK: - suggestBranchName

    func testSuggestFromLastPrompt() {
        let name = NewTaskView.suggestBranchName(lastPrompt: "Add user authentication", clipboard: nil)
        XCTAssertTrue(name.hasPrefix("feature/"), "Expected 'feature/' prefix, got: \(name)")
        XCTAssertTrue(name.contains("add"), "Expected slug from prompt. Got: \(name)")
    }

    func testSuggestFromClipboardShortText() {
        let name = NewTaskView.suggestBranchName(lastPrompt: nil, clipboard: "refactor database layer")
        XCTAssertTrue(name.hasPrefix("feature/"), "Expected 'feature/' prefix, got: \(name)")
        XCTAssertTrue(name.contains("refactor"), "Expected slug from clipboard. Got: \(name)")
    }

    func testClipboardPreferredOverPrompt() {
        let name = NewTaskView.suggestBranchName(
            lastPrompt: "Fix the login page",
            clipboard: "add caching layer"
        )
        XCTAssertTrue(name.contains("add"), "Clipboard should take priority. Got: \(name)")
    }

    func testLongClipboardTruncated() {
        let longText = String(repeating: "a", count: 200)
        let name = NewTaskView.suggestBranchName(lastPrompt: nil, clipboard: longText)
        // Long clipboard text (>100 chars) should be skipped; falls back to prompt or timestamp
        XCTAssertFalse(name.hasPrefix("feature/aaa"), "Long clipboard should be ignored. Got: \(name)")
    }

    func testMultiLineClipboardSkipped() {
        let multiline = "line one\nline two"
        let name = NewTaskView.suggestBranchName(lastPrompt: "use this prompt instead", clipboard: multiline)
        XCTAssertTrue(name.contains("use") || name.contains("copilot"), "Multiline clipboard should be skipped. Got: \(name)")
    }

    func testFallbackWhenNoBranchSeed() {
        // Very short clipboard that won't form a useful slug, no prompt
        let name = NewTaskView.suggestBranchName(lastPrompt: nil, clipboard: "ab")
        // Should fall back to autoBranchName format: copilot/task-YYYYMMDD-HHMM
        XCTAssertTrue(name.hasPrefix("copilot/task-"), "Expected fallback auto name. Got: \(name)")
    }

    func testBranchNameTruncatedTo50Chars() {
        let longPrompt = "This is a very long prompt that describes a really complicated task requiring many words"
        let name = NewTaskView.suggestBranchName(lastPrompt: longPrompt, clipboard: nil)
        // feature/ prefix (8) + max 50 slug chars = max 58 chars total
        let slugPart = name.hasPrefix("feature/") ? String(name.dropFirst("feature/".count)) : name
        XCTAssertLessThanOrEqual(slugPart.count, 50, "Slug portion should be ≤50 chars. Got: \(name)")
    }
}
