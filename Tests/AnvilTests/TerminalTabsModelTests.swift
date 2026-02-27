import XCTest
@testable import Anvil

final class TerminalTabsModelTests: XCTestCase {

    func testInitialTabHasNoSessionSummary() {
        let model = TerminalTabsModel()
        XCTAssertNil(model.tabs.first?.sessionSummary)
    }

    func testSetSessionSummaryStoresValue() {
        let model = TerminalTabsModel()
        guard let id = model.tabs.first?.id else {
            XCTFail("Expected initial tab")
            return
        }
        model.setSessionSummary("Refactor auth module", for: id)
        XCTAssertEqual(model.tabs.first?.sessionSummary, "Refactor auth module")
    }

    func testSetSessionSummaryTrimsWhitespace() {
        let model = TerminalTabsModel()
        guard let id = model.tabs.first?.id else {
            XCTFail("Expected initial tab")
            return
        }
        model.setSessionSummary("  Fix login bug  ", for: id)
        XCTAssertEqual(model.tabs.first?.sessionSummary, "Fix login bug")
    }

    func testSetSessionSummaryWithEmptyStringClearsValue() {
        let model = TerminalTabsModel()
        guard let id = model.tabs.first?.id else {
            XCTFail("Expected initial tab")
            return
        }
        model.setSessionSummary("Some summary", for: id)
        model.setSessionSummary("", for: id)
        XCTAssertNil(model.tabs.first?.sessionSummary)
    }

    func testSetSessionSummaryWithWhitespaceOnlyClearsValue() {
        let model = TerminalTabsModel()
        guard let id = model.tabs.first?.id else {
            XCTFail("Expected initial tab")
            return
        }
        model.setSessionSummary("Some summary", for: id)
        model.setSessionSummary("   ", for: id)
        XCTAssertNil(model.tabs.first?.sessionSummary)
    }

    func testSetSessionSummaryWithNilClearsValue() {
        let model = TerminalTabsModel()
        guard let id = model.tabs.first?.id else {
            XCTFail("Expected initial tab")
            return
        }
        model.setSessionSummary("Some summary", for: id)
        model.setSessionSummary(nil, for: id)
        XCTAssertNil(model.tabs.first?.sessionSummary)
    }

    func testSetSessionSummaryForUnknownIDIsNoOp() {
        let model = TerminalTabsModel()
        let originalSummary = model.tabs.first?.sessionSummary
        model.setSessionSummary("Ignored", for: UUID())
        XCTAssertEqual(model.tabs.first?.sessionSummary, originalSummary)
    }

    func testNewTabHasNoSessionSummary() {
        let model = TerminalTabsModel()
        model.addTab()
        XCTAssertNil(model.tabs.last?.sessionSummary)
    }

    func testAddCopilotTabHasNoSessionSummary() {
        let model = TerminalTabsModel()
        model.addCopilotTab()
        XCTAssertNil(model.tabs.last?.sessionSummary)
    }

    // MARK: - Resume session

    func testAddResumeSessionTabCreatesNewTab() {
        let model = TerminalTabsModel(autoLaunchCopilot: false)
        let initialCount = model.tabs.count
        model.addResumeSessionTab(sessionID: "session-1")
        XCTAssertEqual(model.tabs.count, initialCount + 1)
        XCTAssertEqual(model.tabs.last?.resumeSessionID, "session-1")
        XCTAssertTrue(model.tabs.last?.launchCopilot == true)
    }

    func testAddResumeSessionTabActivatesNewTab() {
        let model = TerminalTabsModel(autoLaunchCopilot: false)
        model.addResumeSessionTab(sessionID: "session-1")
        XCTAssertEqual(model.activeTabID, model.tabs.last?.id)
    }

    func testAddResumeSessionTabDeduplicates() {
        let model = TerminalTabsModel(autoLaunchCopilot: false)
        model.addResumeSessionTab(sessionID: "session-1")
        let existingTabID = model.tabs.last!.id
        let tabCountAfterFirst = model.tabs.count
        // Switch to a different tab
        model.addTab()
        XCTAssertNotEqual(model.activeTabID, existingTabID)
        // Opening same session again should switch, not create
        model.addResumeSessionTab(sessionID: "session-1")
        XCTAssertEqual(model.tabs.count, tabCountAfterFirst + 1)
        XCTAssertEqual(model.activeTabID, existingTabID)
    }

    func testActiveSessionIDsReflectsOpenTabs() {
        let model = TerminalTabsModel(autoLaunchCopilot: false)
        model.addResumeSessionTab(sessionID: "session-1")
        model.addResumeSessionTab(sessionID: "session-2")
        XCTAssertTrue(model.activeSessionIDs.contains("session-1"))
        XCTAssertTrue(model.activeSessionIDs.contains("session-2"))
        XCTAssertFalse(model.activeSessionIDs.contains("session-3"))
    }

    func testActiveSessionIDsExcludesPlainTabs() {
        let model = TerminalTabsModel(autoLaunchCopilot: true)
        XCTAssertTrue(model.activeSessionIDs.isEmpty)
    }

    func testInitialTabHasNoResumeSessionID() {
        let model = TerminalTabsModel()
        XCTAssertNil(model.tabs.first?.resumeSessionID)
    }
}
