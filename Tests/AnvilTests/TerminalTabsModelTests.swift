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
}
