import Foundation
import SwiftTerm

/// Scans terminal output rows to detect when the Copilot agent is waiting
/// for user input (e.g. plan approval, y/n confirmation, clarifying question).
///
/// Detection heuristic: look at the bottom 5 visible rows for a recognised
/// interactive-prompt pattern while no CLI spinner character is present.
/// The state is re-evaluated on every `rangeChanged` call that touches the
/// bottom portion of the viewport, so it clears automatically once the agent
/// starts printing new output.
final class AgentInputWatcher {
    /// Called on the main queue whenever `isWaitingForInput` changes.
    var onStateChanged: ((Bool) -> Void)?

    /// Whether the watcher currently believes the agent is blocked waiting
    /// for user input.
    private(set) var isWaitingForInput = false

    // MARK: - Constants

    /// Braille spinner characters produced by popular CLI spinner libraries
    /// (ora, cli-spinners, etc.) that indicate the agent is still processing.
    private static let spinnerChars: Set<Character> = [
        "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"
    ]

    /// Confirmation-choice suffixes that are appended to interactive prompts.
    private static let confirmationSuffixes: [String] = [
        "[y/n]", "[Y/n]", "[y/N]", "[Y/N]",
        "(y/n)", "(Y/n)", "(y/N)", "(Y/N)",
        "(yes/no)", "[yes/no]",
        "press enter", "press any key"
    ]

    /// Number of rows from the bottom of the viewport to scan.  Interactive
    /// prompts always appear at the cursor position which is at or near the
    /// last row, so 5 rows is enough to capture multi-line prompts while
    /// keeping the scan inexpensive.
    private static let scanWindowRows = 5

    // MARK: - Public interface

    /// Re-evaluates the waiting state whenever the terminal viewport is
    /// updated.  Only rescans when the update touches the bottom rows of the
    /// screen, because interactive prompts always appear at the cursor
    /// position near the bottom.
    func processTerminalRange(in view: LocalProcessTerminalView, startY: Int, endY: Int) {
        let terminal = view.getTerminal()
        let lastRow = terminal.rows - 1
        guard endY >= max(0, lastRow - (Self.scanWindowRows - 1)) else { return }

        let scanStart = max(0, lastRow - (Self.scanWindowRows - 1))
        var promptFound = false
        var spinnerFound = false

        for row in scanStart...lastRow {
            guard let bufferLine = terminal.getLine(row: row) else { continue }
            let text = bufferLine.translateToString(trimRight: true)
            guard !text.isEmpty else { continue }
            if !promptFound && isPromptLine(text) { promptFound = true }
            if !spinnerFound && containsSpinner(text) { spinnerFound = true }
        }

        let nowWaiting = promptFound && !spinnerFound
        guard nowWaiting != isWaitingForInput else { return }
        isWaitingForInput = nowWaiting
        let value = nowWaiting
        DispatchQueue.main.async { [weak self] in
            self?.onStateChanged?(value)
        }
    }

    // MARK: - Pattern helpers

    /// Returns true when `text` looks like an interactive prompt line.
    /// Internal access for testability.
    func isPromptLine(_ text: String) -> Bool {
        let stripped = text.trimmingCharacters(in: .whitespaces)
        // inquirer.js / GitHub CLI style: lines beginning with "? "
        if stripped.hasPrefix("? ") { return true }
        let lower = stripped.lowercased()
        for suffix in Self.confirmationSuffixes {
            if lower.hasSuffix(suffix) || lower.contains(" " + suffix) {
                return true
            }
        }
        return false
    }

    /// Returns true when `text` contains a spinner character, indicating the
    /// agent is still actively processing output.
    /// Internal access for testability.
    func containsSpinner(_ text: String) -> Bool {
        text.contains(where: { Self.spinnerChars.contains($0) })
    }
}
