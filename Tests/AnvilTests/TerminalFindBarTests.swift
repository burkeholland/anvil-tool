import XCTest
@testable import Anvil

final class TerminalFindBarTests: XCTestCase {

    // MARK: - Initial state

    func testInitialStateHidesFindBar() {
        let proxy = TerminalInputProxy()
        XCTAssertFalse(proxy.isShowingFindBar)
    }

    func testInitialMatchCountIsZero() {
        let proxy = TerminalInputProxy()
        XCTAssertEqual(proxy.findMatchCount, 0)
    }

    // MARK: - showFindBar

    func testShowFindBarSetsIsShowingFindBar() {
        let proxy = TerminalInputProxy()
        proxy.showFindBar()
        XCTAssertTrue(proxy.isShowingFindBar)
    }

    func testShowFindBarIsIdempotent() {
        let proxy = TerminalInputProxy()
        proxy.showFindBar()
        proxy.showFindBar()
        XCTAssertTrue(proxy.isShowingFindBar)
    }

    // MARK: - dismissFindBar

    func testDismissFindBarHidesFindBar() {
        let proxy = TerminalInputProxy()
        proxy.showFindBar()
        proxy.dismissFindBar()
        XCTAssertFalse(proxy.isShowingFindBar)
    }

    func testDismissFindBarResetsMatchCount() {
        let proxy = TerminalInputProxy()
        proxy.showFindBar()
        // updateSearch with no terminal leaves matchCount at 0, so we set it directly
        // to simulate a non-zero match count before dismiss.
        proxy.findMatchCount = 3
        proxy.dismissFindBar()
        XCTAssertEqual(proxy.findMatchCount, 0)
    }

    func testDismissFindBarOnHiddenBarIsNoop() {
        let proxy = TerminalInputProxy()
        // Already hidden; dismiss should not throw or toggle state.
        proxy.dismissFindBar()
        XCTAssertFalse(proxy.isShowingFindBar)
        XCTAssertEqual(proxy.findMatchCount, 0)
    }

    // MARK: - updateSearch with no terminal view

    func testUpdateSearchWithEmptyTermSetsMatchCountZero() {
        let proxy = TerminalInputProxy()
        proxy.updateSearch(term: "", options: SearchOptions())
        XCTAssertEqual(proxy.findMatchCount, 0)
    }

    func testUpdateSearchWithNonEmptyTermAndNoTerminalSetsMatchCountZero() {
        let proxy = TerminalInputProxy()
        // terminalView is nil – should not crash, should report 0 matches.
        proxy.updateSearch(term: "error", options: SearchOptions())
        XCTAssertEqual(proxy.findMatchCount, 0)
    }

    func testUpdateSearchWithRegexAndNoTerminalSetsMatchCountZero() {
        let proxy = TerminalInputProxy()
        let options = SearchOptions(caseSensitive: false, regex: true)
        proxy.updateSearch(term: "err.*", options: options)
        XCTAssertEqual(proxy.findMatchCount, 0)
    }

    // MARK: - findTerminalNext / findTerminalPrevious with no terminal

    func testFindTerminalNextWithNoTerminalDoesNotCrash() {
        let proxy = TerminalInputProxy()
        // Prime the proxy with a current search term so the guard passes.
        proxy.updateSearch(term: "hello", options: SearchOptions())
        // Calling with no terminalView must not crash.
        proxy.findTerminalNext()
    }

    func testFindTerminalPreviousWithNoTerminalDoesNotCrash() {
        let proxy = TerminalInputProxy()
        proxy.updateSearch(term: "hello", options: SearchOptions())
        proxy.findTerminalPrevious()
    }

    // MARK: - showFindBar / dismiss round-trip

    func testShowThenDismissThenShowAgain() {
        let proxy = TerminalInputProxy()
        proxy.showFindBar()
        XCTAssertTrue(proxy.isShowingFindBar)
        proxy.dismissFindBar()
        XCTAssertFalse(proxy.isShowingFindBar)
        proxy.showFindBar()
        XCTAssertTrue(proxy.isShowingFindBar)
    }
}
