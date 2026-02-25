import Foundation
import SwiftTerm

/// Polls the visible terminal buffer at a regular interval, strips ANSI escape codes,
/// and pattern-matches each newly-appearing line against known Copilot CLI output
/// formats to emit structured `ActivityEvent` values (`.commandRun`, `.fileRead`,
/// `.agentStatus`).
///
/// Attach the parser to a `LocalProcessTerminalView` via `attach(to:)`.  The
/// `onEvent` closure is called on the main thread for every detected agent action.
final class TerminalOutputParser {

    /// Called on the main thread for each detected agent action.
    var onEvent: ((ActivityEvent) -> Void)?

    private weak var terminalView: LocalProcessTerminalView?
    private var pollTimer: Timer?
    /// Last observed text for each visible row index, keyed by row number.
    private var lastRowTexts: [Int: String] = [:]

    // MARK: - Lifecycle

    func attach(to view: LocalProcessTerminalView) {
        detach()
        terminalView = view
        lastRowTexts = [:]
        schedulePoll()
    }

    func detach() {
        pollTimer?.invalidate()
        pollTimer = nil
        terminalView = nil
        lastRowTexts = [:]
    }

    deinit {
        pollTimer?.invalidate()
    }

    // MARK: - Polling

    private func schedulePoll() {
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.poll()
        }
    }

    private func poll() {
        guard let tv = terminalView else { return }
        let terminal = tv.getTerminal()
        let rows = terminal.rows

        for row in 0..<rows {
            guard let bufLine = terminal.getLine(row: row) else { continue }
            let raw = bufLine.translateToString(trimRight: true)
            // Only process rows whose content has changed since the last poll
            guard raw != (lastRowTexts[row] ?? "") else { continue }
            lastRowTexts[row] = raw

            let clean = stripANSI(raw).trimmingCharacters(in: .whitespaces)
            guard !clean.isEmpty else { continue }

            if let event = parseAgentLine(clean) {
                onEvent?(event)
            }
        }

        // Prune stale entries when the terminal shrinks
        for key in lastRowTexts.keys where key >= rows {
            lastRowTexts.removeValue(forKey: key)
        }
    }

    // MARK: - Line Parsing

    private func parseAgentLine(_ line: String) -> ActivityEvent? {
        let now = Date()

        if let path = matchFileRead(line) {
            return ActivityEvent(
                id: UUID(), timestamp: now,
                kind: .fileRead(path: path),
                path: path, fileURL: nil
            )
        }

        if let command = matchCommandRun(line) {
            return ActivityEvent(
                id: UUID(), timestamp: now,
                kind: .commandRun(command: command),
                path: "", fileURL: nil
            )
        }

        if let status = matchAgentStatus(line) {
            return ActivityEvent(
                id: UUID(), timestamp: now,
                kind: .agentStatus(status: status),
                path: "", fileURL: nil
            )
        }

        return nil
    }

    // MARK: - Pattern Matchers

    private func matchFileRead(_ line: String) -> String? {
        let patterns: [String] = [
            #"(?i)reading file[:\s]+(.+)"#,
            #"(?i)opening file[:\s]+(.+)"#,
            #"(?i)\bread[:\s]+([^\s].+\.\w{1,10})\b"#,
        ]
        for pattern in patterns {
            if let captured = firstCapture(pattern: pattern, in: line) {
                let trimmed = captured.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty { return trimmed }
            }
        }
        return nil
    }

    private func matchCommandRun(_ line: String) -> String? {
        let patterns: [String] = [
            #"(?i)running[:\s]+(.+)"#,
            #"(?i)executing[:\s]+(.+)"#,
            #"^>\s+(.+)"#,
            #"^\$\s+(.+)"#,
        ]
        for pattern in patterns {
            if let captured = firstCapture(pattern: pattern, in: line) {
                let trimmed = captured.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty { return trimmed }
            }
        }
        return nil
    }

    private func matchAgentStatus(_ line: String) -> String? {
        // Short lines (< 80 chars) containing known Copilot status keywords
        let keywords = ["thinking", "working", "planning", "analyzing",
                        "searching", "generating", "processing"]
        if line.count < 80 {
            let lower = line.lowercased()
            if keywords.contains(where: { lower.contains($0) }) {
                return line
            }
        }

        // Lines prefixed with a check mark or spinner character
        let prefixPatterns: [String] = [
            #"^[✓✔]\s+(.+)"#,
            #"^[⠸⠼⠴⠦⠧⠇⠏⠋⠙⠹]\s+(.+)"#,
        ]
        for pattern in prefixPatterns {
            if let captured = firstCapture(pattern: pattern, in: line) {
                let trimmed = captured.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty { return trimmed }
            }
        }

        return nil
    }

    // MARK: - Helpers

    private func firstCapture(pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
        let ns = text as NSString
        guard let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)),
              match.numberOfRanges >= 2 else { return nil }
        let captureRange = match.range(at: 1)
        guard captureRange.location != NSNotFound else { return nil }
        return ns.substring(with: captureRange)
    }

    /// Strips ANSI/VT escape sequences from terminal output.
    private func stripANSI(_ text: String) -> String {
        guard let regex = try? NSRegularExpression(
            pattern: #"\x1B(?:[@-Z\\-_]|\[[0-?]*[ -/]*[@-~])"#,
            options: []
        ) else { return text }
        let ns = text as NSString
        return regex.stringByReplacingMatches(
            in: text,
            range: NSRange(location: 0, length: ns.length),
            withTemplate: ""
        )
    }
}
