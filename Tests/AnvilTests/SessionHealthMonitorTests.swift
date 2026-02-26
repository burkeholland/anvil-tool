import XCTest
@testable import Anvil

final class SessionHealthMonitorTests: XCTestCase {

    private let secondsPerMinute: TimeInterval = 60
    private let secondsPerHour: TimeInterval = 3600

    func testInitialState() {
        let monitor = SessionHealthMonitor()
        XCTAssertEqual(monitor.turnCount, 0)
        XCTAssertEqual(monitor.contextFillness, 0.0, accuracy: 0.01)
        XCTAssertFalse(monitor.isSaturated)
        XCTAssertEqual(monitor.elapsedString, "0m")
    }

    func testRecordTurnIncreasesTurnCount() {
        let monitor = SessionHealthMonitor()
        monitor.recordTurn()
        XCTAssertEqual(monitor.turnCount, 1)
        monitor.recordTurn()
        XCTAssertEqual(monitor.turnCount, 2)
    }

    func testContextFillnessGrowsWithTurns() {
        let monitor = SessionHealthMonitor()
        for _ in 0..<20 {
            monitor.recordTurn()
        }
        // 20 turns out of 40 max = 0.5
        XCTAssertEqual(monitor.contextFillness, 0.5, accuracy: 0.01)
    }

    func testContextFillnessCapsAtOne() {
        let monitor = SessionHealthMonitor()
        for _ in 0..<100 {
            monitor.recordTurn()
        }
        XCTAssertLessThanOrEqual(monitor.contextFillness, 1.0)
    }

    func testIsSaturatedAfterEnoughTurns() {
        let monitor = SessionHealthMonitor()
        // 40 turns * 0.8 threshold = 32 turns needed
        for _ in 0..<33 {
            monitor.recordTurn()
        }
        XCTAssertTrue(monitor.isSaturated)
    }

    func testResetClearsAllState() {
        let monitor = SessionHealthMonitor()
        for _ in 0..<40 {
            monitor.recordTurn()
        }
        XCTAssertTrue(monitor.isSaturated)

        monitor.reset()
        XCTAssertEqual(monitor.turnCount, 0)
        XCTAssertEqual(monitor.contextFillness, 0.0, accuracy: 0.01)
        XCTAssertFalse(monitor.isSaturated)
        XCTAssertEqual(monitor.elapsedString, "0m")
    }

    func testElapsedStringFormatMinutes() {
        let monitor = SessionHealthMonitor()
        // Override sessionStart to 45 minutes ago
        monitor.sessionStart = Date(timeIntervalSinceNow: -45 * secondsPerMinute)
        monitor.updateMetrics()
        XCTAssertEqual(monitor.elapsedString, "45m")
    }

    func testElapsedStringFormatHoursOnly() {
        let monitor = SessionHealthMonitor()
        monitor.sessionStart = Date(timeIntervalSinceNow: -2 * secondsPerHour)
        monitor.updateMetrics()
        XCTAssertEqual(monitor.elapsedString, "2h")
    }

    func testElapsedStringFormatHoursAndMinutes() {
        let monitor = SessionHealthMonitor()
        monitor.sessionStart = Date(timeIntervalSinceNow: -(1 * secondsPerHour + 30 * secondsPerMinute))
        monitor.updateMetrics()
        XCTAssertEqual(monitor.elapsedString, "1h30m")
    }

    func testTimeFractionContributesToFillness() {
        let monitor = SessionHealthMonitor()
        // Set start to 1 hour ago (= 50% of 2h max)
        monitor.sessionStart = Date(timeIntervalSinceNow: -secondsPerHour)
        monitor.updateMetrics()
        // Turn count is 0 → fullness comes from time fraction alone
        XCTAssertEqual(monitor.contextFillness, 0.5, accuracy: 0.02)
    }
}
