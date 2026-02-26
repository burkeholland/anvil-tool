import Foundation

/// A single test run record, capturing a timestamp, structured per-test results, and raw output.
struct TestRunRecord {
    let date: Date
    let testCases: [TestResultParser.TestCaseResult]
    let rawOutput: String
    let succeeded: Bool

    var passedCount: Int { testCases.filter { $0.passed }.count }
    var failedCount: Int { testCases.filter { !$0.passed }.count }
}

/// Persists the latest test run result across agent interactions so the persistent
/// test results panel can display up-to-date status even after the TaskCompleteBanner
/// has been dismissed.
final class TestResultsStore: ObservableObject {
    /// The most recent completed test run, or nil if no tests have been run yet.
    @Published private(set) var latestRun: TestRunRecord?

    /// Replaces the stored record with the provided run result.
    func record(_ run: TestRunRecord) {
        latestRun = run
    }

    /// Clears the stored results (e.g. when switching projects).
    func clear() {
        latestRun = nil
    }
}
