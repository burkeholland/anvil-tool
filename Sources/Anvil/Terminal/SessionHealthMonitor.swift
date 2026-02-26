import Foundation
import Combine

/// Tracks Copilot CLI session health metrics to estimate context quality.
/// Computes context fullness from turn count and elapsed session time.
final class SessionHealthMonitor: ObservableObject {

    /// When the current session started.
    var sessionStart: Date = Date()

    /// Number of prompts (turns) sent in this session.
    @Published private(set) var turnCount: Int = 0

    /// Estimated context fullness fraction (0.0 = empty, 1.0 = saturated).
    @Published private(set) var contextFillness: Double = 0.0

    /// Human-readable elapsed session time (e.g. "5m", "1h30m").
    @Published private(set) var elapsedString: String = "0m"

    /// Whether context appears saturated (fullness > 0.8).
    var isSaturated: Bool { contextFillness > 0.8 }

    /// Number of turns after which context is considered saturated.
    private let maxTurns = 40

    /// Duration (seconds) after which context is considered saturated (2 hours).
    private let maxDuration: TimeInterval = 2 * 3600

    private var timer: AnyCancellable?

    init() {
        startTimer()
    }

    /// Increments the turn counter and updates metrics.
    func recordTurn() {
        turnCount += 1
        updateMetrics()
    }

    /// Resets all session state (call after /compact or when a new session begins).
    func reset() {
        sessionStart = Date()
        turnCount = 0
        contextFillness = 0.0
        elapsedString = "0m"
    }

    // MARK: - Private

    private func startTimer() {
        timer = Timer.publish(every: 60, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.updateMetrics() }
    }

    /// Internal (not private) to allow unit tests to trigger a metric refresh
    /// after manipulating `sessionStart` without waiting for the timer.
    func updateMetrics() {
        let elapsed = Date().timeIntervalSince(sessionStart)

        // Build human-readable elapsed string
        let totalMinutes = max(0, Int(elapsed) / 60)
        if totalMinutes < 60 {
            elapsedString = "\(totalMinutes)m"
        } else {
            let hours = totalMinutes / 60
            let mins = totalMinutes % 60
            elapsedString = mins > 0 ? "\(hours)h\(mins)m" : "\(hours)h"
        }

        // Context fullness = max of turn-based and time-based fractions
        let turnFraction = min(1.0, Double(turnCount) / Double(maxTurns))
        let timeFraction = min(1.0, elapsed / maxDuration)
        contextFillness = max(turnFraction, timeFraction)
    }
}
