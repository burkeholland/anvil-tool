import XCTest
@testable import Anvil

final class FilePreviewNavigationTests: XCTestCase {

    private func makeURL(_ name: String) -> URL {
        URL(fileURLWithPath: "/tmp/project/\(name)")
    }

    // MARK: - Initial state

    func testInitialState_noHistory() {
        let model = FilePreviewModel()
        XCTAssertFalse(model.canGoBack)
        XCTAssertFalse(model.canGoForward)
        XCTAssertNil(model.backDestinationName)
        XCTAssertNil(model.forwardDestinationName)
        XCTAssertEqual(model.navIndex, -1)
        XCTAssertTrue(model.navStack.isEmpty)
    }

    // MARK: - pushNavHistory via select (unit-testing the stack directly)

    func testPushNavHistory_singleEntry() {
        let model = FilePreviewModel()
        model.pushNavHistoryForTesting(makeURL("a.swift"))
        XCTAssertEqual(model.navStack.count, 1)
        XCTAssertEqual(model.navIndex, 0)
        XCTAssertFalse(model.canGoBack)
        XCTAssertFalse(model.canGoForward)
    }

    func testPushNavHistory_twoDistinctEntries() {
        let model = FilePreviewModel()
        model.pushNavHistoryForTesting(makeURL("a.swift"))
        model.pushNavHistoryForTesting(makeURL("b.swift"))
        XCTAssertEqual(model.navStack.count, 2)
        XCTAssertEqual(model.navIndex, 1)
        XCTAssertTrue(model.canGoBack)
        XCTAssertFalse(model.canGoForward)
    }

    func testPushNavHistory_deduplicatesConsecutive() {
        let model = FilePreviewModel()
        let url = makeURL("a.swift")
        model.pushNavHistoryForTesting(url)
        model.pushNavHistoryForTesting(url)
        XCTAssertEqual(model.navStack.count, 1)
        XCTAssertEqual(model.navIndex, 0)
    }

    func testPushNavHistory_allowsNonConsecutiveDuplicate() {
        let model = FilePreviewModel()
        model.pushNavHistoryForTesting(makeURL("a.swift"))
        model.pushNavHistoryForTesting(makeURL("b.swift"))
        model.pushNavHistoryForTesting(makeURL("a.swift"))
        XCTAssertEqual(model.navStack.count, 3)
        XCTAssertEqual(model.navIndex, 2)
    }

    // MARK: - Back navigation

    func testNavigateBack_movesToPreviousEntry() {
        let model = FilePreviewModel()
        model.pushNavHistoryForTesting(makeURL("a.swift"))
        model.pushNavHistoryForTesting(makeURL("b.swift"))
        // Direct manipulation of navIndex to test stack state without triggering file I/O
        // (navigateBack() calls select() which loads files asynchronously)
        model.navIndexForTesting -= 1
        XCTAssertEqual(model.navIndex, 0)
        XCTAssertFalse(model.canGoBack)
        XCTAssertTrue(model.canGoForward)
    }

    func testNavigateBack_decrementsIndex() {
        let model = FilePreviewModel()
        model.pushNavHistoryForTesting(makeURL("a.swift"))
        model.pushNavHistoryForTesting(makeURL("b.swift"))
        // navigateBack() decrements navIndex synchronously (async file load is a side effect)
        model.navigateBack()
        XCTAssertEqual(model.navIndex, 0)
        XCTAssertFalse(model.canGoBack)
        XCTAssertTrue(model.canGoForward)
    }

    func testNavigateBack_noHistoryDoesNothing() {
        let model = FilePreviewModel()
        model.navigateBack()
        XCTAssertEqual(model.navIndex, -1)
    }

    func testBackDestinationName_correctFilename() {
        let model = FilePreviewModel()
        model.pushNavHistoryForTesting(makeURL("a.swift"))
        model.pushNavHistoryForTesting(makeURL("b.swift"))
        XCTAssertEqual(model.backDestinationName, "a.swift")
        XCTAssertNil(model.forwardDestinationName)
    }

    // MARK: - Forward navigation

    func testForwardDestinationName_correctFilename() {
        let model = FilePreviewModel()
        model.pushNavHistoryForTesting(makeURL("a.swift"))
        model.pushNavHistoryForTesting(makeURL("b.swift"))
        model.pushNavHistoryForTesting(makeURL("c.swift"))
        model.navIndexForTesting = 0
        XCTAssertEqual(model.forwardDestinationName, "b.swift")
    }

    func testNavigateForward_incrementsIndex() {
        let model = FilePreviewModel()
        model.pushNavHistoryForTesting(makeURL("a.swift"))
        model.pushNavHistoryForTesting(makeURL("b.swift"))
        model.pushNavHistoryForTesting(makeURL("c.swift"))
        model.navIndexForTesting = 0
        // navigateForward() increments navIndex synchronously
        model.navigateForward()
        XCTAssertEqual(model.navIndex, 1)
    }

    func testNavigateForward_noForwardDoesNothing() {
        let model = FilePreviewModel()
        model.pushNavHistoryForTesting(makeURL("a.swift"))
        model.navigateForward()
        XCTAssertEqual(model.navIndex, 0)
    }

    // MARK: - Truncation of forward history on new navigation

    func testPushAfterBack_truncatesForwardHistory() {
        let model = FilePreviewModel()
        model.pushNavHistoryForTesting(makeURL("a.swift"))
        model.pushNavHistoryForTesting(makeURL("b.swift"))
        model.pushNavHistoryForTesting(makeURL("c.swift"))
        // Go back two steps
        model.navIndexForTesting = 0
        // Push new entry — forward history (b, c) should be dropped
        model.pushNavHistoryForTesting(makeURL("d.swift"))
        XCTAssertEqual(model.navStack.count, 2)
        XCTAssertEqual(model.navStack.last?.lastPathComponent, "d.swift")
        XCTAssertFalse(model.canGoForward)
    }

    // MARK: - History cap

    func testNavStack_cappedAtMaxHistory() {
        let model = FilePreviewModel()
        for i in 0..<35 {
            model.pushNavHistoryForTesting(makeURL("file\(i).swift"))
        }
        XCTAssertLessThanOrEqual(model.navStack.count, 30)
        XCTAssertEqual(model.navIndex, model.navStack.count - 1)
    }

    // MARK: - Close resets history

    func testClose_resetsNavHistory() {
        let model = FilePreviewModel()
        model.pushNavHistoryForTesting(makeURL("a.swift"))
        model.pushNavHistoryForTesting(makeURL("b.swift"))
        model.close(persist: false)
        XCTAssertTrue(model.navStack.isEmpty)
        XCTAssertEqual(model.navIndex, -1)
        XCTAssertFalse(model.canGoBack)
        XCTAssertFalse(model.canGoForward)
    }
}
