import Foundation
import SwiftTerm

/// Encapsulates the logic for detecting whether the Copilot CLI has returned
/// to its input prompt by periodically scanning the terminal buffer.
///
/// Detection strategy: scan the last few visible rows of the terminal buffer
/// for a line that matches the Copilot prompt pattern (a line whose trimmed
/// content is exactly ">" or starts with "> ").
final class TerminalPromptDetector {

    // MARK: - Public state

    /// Set to `true` whenever the Copilot prompt is visible in the terminal buffer.
    private(set) var isCopilotPromptVisible: Bool = false

    // MARK: - Private

    private weak var terminal: Terminal?
    private var timer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "com.anvil.TerminalPromptDetector", qos: .utility)

    /// How often to poll the terminal buffer (seconds).
    private let pollInterval: TimeInterval = 0.5

    /// Number of rows from the bottom of the buffer to scan.
    private let scanRowCount: Int = 10

    /// Callback invoked on the main queue whenever `isCopilotPromptVisible` changes.
    var onPromptVisibilityChanged: ((Bool) -> Void)?

    // MARK: - Init / deinit

    init(terminal: Terminal) {
        self.terminal = terminal
    }

    deinit {
        stop()
    }

    // MARK: - Start / Stop

    func start() {
        guard timer == nil else { return }
        let source = DispatchSource.makeTimerSource(queue: queue)
        source.schedule(deadline: .now() + pollInterval, repeating: pollInterval)
        source.setEventHandler { [weak self] in
            self?.poll()
        }
        source.resume()
        timer = source
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    // MARK: - Polling

    private func poll() {
        guard let terminal = terminal else { return }
        let newValue = scanBuffer(terminal)
        if newValue != isCopilotPromptVisible {
            isCopilotPromptVisible = newValue
            let value = newValue
            DispatchQueue.main.async { [weak self] in
                self?.onPromptVisibilityChanged?(value)
            }
        }
    }

    /// Scans the bottom `scanRowCount` rows of the terminal buffer and returns
    /// `true` if any row matches the Copilot input-prompt pattern.
    func scanBuffer(_ terminal: Terminal) -> Bool {
        let rows = terminal.rows
        let startRow = max(0, rows - scanRowCount)
        for row in startRow..<rows {
            guard let line = terminal.getLine(row: row) else { continue }
            let text = line.translateToString(trimRight: true)
            if isCopilotPrompt(text) {
                return true
            }
        }
        return false
    }

    // MARK: - Pattern matching

    /// Returns `true` if the given line looks like the Copilot CLI input prompt.
    ///
    /// The Copilot CLI shows a `> ` prompt (with optional leading whitespace and
    /// possible ANSI-stripped content). We match lines that are exactly ">" or
    /// start with "> " after stripping leading whitespace.
    func isCopilotPrompt(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed == ">" || trimmed.hasPrefix("> ")
    }
}
