import XCTest
@testable import Anvil

final class TestResultsStoreTests: XCTestCase {

    // MARK: - Initial state

    func testInitiallyEmpty() {
        let store = TestResultsStore()
        XCTAssertNil(store.latestRun)
    }

    // MARK: - record

    func testRecordStoresRun() {
        let store = TestResultsStore()
        let run = TestRunRecord(date: Date(), testCases: [], rawOutput: "output", succeeded: true)
        store.record(run)
        XCTAssertNotNil(store.latestRun)
        XCTAssertTrue(store.latestRun?.succeeded == true)
        XCTAssertEqual(store.latestRun?.rawOutput, "output")
    }

    func testRecordReplacesExistingRun() {
        let store = TestResultsStore()
        let run1 = TestRunRecord(date: Date(), testCases: [], rawOutput: "first", succeeded: true)
        let run2 = TestRunRecord(date: Date(), testCases: [], rawOutput: "second", succeeded: false)
        store.record(run1)
        store.record(run2)
        XCTAssertEqual(store.latestRun?.rawOutput, "second")
        XCTAssertFalse(store.latestRun?.succeeded ?? true)
    }

    // MARK: - clear

    func testClearRemovesRun() {
        let store = TestResultsStore()
        let run = TestRunRecord(date: Date(), testCases: [], rawOutput: "output", succeeded: true)
        store.record(run)
        store.clear()
        XCTAssertNil(store.latestRun)
    }

    // MARK: - TestRunRecord computed properties

    func testPassedAndFailedCount() {
        let cases: [TestResultParser.TestCaseResult] = [
            TestResultParser.TestCaseResult(name: "testA", passed: true),
            TestResultParser.TestCaseResult(name: "testB", passed: true),
            TestResultParser.TestCaseResult(name: "testC", passed: false),
        ]
        let run = TestRunRecord(date: Date(), testCases: cases, rawOutput: "", succeeded: false)
        XCTAssertEqual(run.passedCount, 2)
        XCTAssertEqual(run.failedCount, 1)
    }

    func testEmptyTestCasesCount() {
        let run = TestRunRecord(date: Date(), testCases: [], rawOutput: "", succeeded: true)
        XCTAssertEqual(run.passedCount, 0)
        XCTAssertEqual(run.failedCount, 0)
    }

    // MARK: - TestCaseResult

    func testTestCaseResultDefaults() {
        let tc = TestResultParser.TestCaseResult(name: "testSomething", passed: true)
        XCTAssertEqual(tc.name, "testSomething")
        XCTAssertTrue(tc.passed)
        XCTAssertNil(tc.duration)
        XCTAssertNil(tc.failureMessage)
    }

    func testTestCaseResultWithAllFields() {
        let tc = TestResultParser.TestCaseResult(name: "testFoo", passed: false, duration: 1.234, failureMessage: "XCTAssertEqual failed")
        XCTAssertFalse(tc.passed)
        XCTAssertEqual(tc.duration, 1.234, accuracy: 0.001)
        XCTAssertEqual(tc.failureMessage, "XCTAssertEqual failed")
    }
}
