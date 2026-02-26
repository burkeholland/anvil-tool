import Foundation
import AppKit
import SwiftTerm

/// Allows other views to send text to the embedded terminal.
/// Injected as an `@EnvironmentObject` throughout the view hierarchy.
final class TerminalInputProxy: ObservableObject {
    weak var terminalView: LocalProcessTerminalView?

    /// Whether the floating find bar overlay is currently visible.
    @Published var isShowingFindBar = false
    /// Number of matches for the current search term across the full scrollback buffer.
    @Published var findMatchCount: Int = 0
    /// Incremented each time the user submits a prompt via sendPrompt().
    /// Observers can use onChange(of:) to react to new prompts (e.g. auto-dismiss banners).
    @Published private(set) var promptSentCount: Int = 0

    /// Optional store for recording prompt history.
    var historyStore: PromptHistoryStore?

    /// Optional session health monitor updated on each prompt turn.
    var sessionMonitor: SessionHealthMonitor?

    /// Optional store for session-scoped prompt timeline markers.
    var markerStore: PromptMarkerStore?

    /// Tracks the highest `buffer.yDisp` value seen since the terminal was last reset.
    /// Approximates the current maximum scrollback depth so the timeline overlay can
    /// position markers proportionally and restore scroll positions.
    @Published private(set) var estimatedMaxScrollback: Int = 0

    private var currentFindTerm: String = ""
    private var currentFindOptions: SearchOptions = SearchOptions()

    func send(_ text: String) {
        terminalView?.send(txt: text)
    }

    /// Records the prompt in history and sends it followed by a newline to the active terminal.
    /// Also increments promptSentCount so observers can auto-dismiss contextual banners.
    func sendPrompt(_ text: String) {
        let anchorYDisp = terminalView?.terminal.buffer.yDisp ?? 0
        historyStore?.add(text)
        markerStore?.addMarker(text: text, anchorYDisp: anchorYDisp)
        sessionMonitor?.recordTurn()
        send(text + "\n")
        promptSentCount += 1
    }

    /// Sends a single control character (e.g. Ctrl+C = 0x03, Ctrl+D = 0x04).
    func sendControl(_ byte: UInt8) {
        send(String(UnicodeScalar(byte)))
    }

    /// Sends an escape sequence (e.g. Shift+Tab = ESC [ Z).
    func sendEscape(_ sequence: String) {
        send("\u{1B}\(sequence)")
    }

    /// Sanitizes a file path by stripping control characters to prevent terminal injection.
    private func sanitizePath(_ path: String) -> String {
        let chars = path.unicodeScalars
            .filter { $0.value >= 0x20 && $0 != "\u{7F}" }
            .map { Character($0) }
        return String(chars)
    }

    /// Sends `/context add <relativePath>` to the terminal to add a file to the Copilot CLI context.
    /// Strips control characters to prevent terminal injection.
    func addToContext(relativePath: String) {
        send("/context add \(sanitizePath(relativePath))\n")
    }

    /// Sends @relativePath to the terminal for Copilot CLI file mentions.
    /// Strips control characters to prevent terminal injection.
    func mentionFile(relativePath: String) {
        send("@\(sanitizePath(relativePath)) ")
    }

    /// Sends a formatted code snippet to the terminal with file path and line range context.
    /// Strips control characters (except newlines) from the code to prevent terminal injection.
    /// When `code` is empty, sends only the file path and line range.
    func sendCodeSnippet(relativePath: String, language: String?, startLine: Int, endLine: Int, code: String) {
        let sanitizedPath = sanitizePath(relativePath)
        let lineRange = startLine == endLine ? "line \(startLine)" : "lines \(startLine)-\(endLine)"
        if code.isEmpty {
            send("\(sanitizedPath) \(lineRange)\n")
        } else {
            let sanitizedCode = code.unicodeScalars
                .filter { $0.value == 0x0A || ($0.value >= 0x20 && $0 != "\u{7F}") }
                .map { Character($0) }
            let lang = language ?? ""
            send("\(sanitizedPath) \(lineRange):\n```\(lang)\n\(String(sanitizedCode))\n```\n")
        }
    }

    /// Called from the terminal's `rangeChanged` delegate to keep scroll metrics current.
    /// Updates `estimatedMaxScrollback` using the current `buffer.yDisp`, which equals
    /// the maximum scrollback depth when the terminal is pinned to the bottom.
    func updateScrollMetrics(terminalView tv: LocalProcessTerminalView) {
        let yDisp = tv.terminal.buffer.yDisp
        if yDisp > estimatedMaxScrollback {
            estimatedMaxScrollback = yDisp
        }
    }

    /// Scrolls the terminal to the position recorded in the given marker.
    func scrollToMarker(_ marker: PromptMarker) {
        guard let tv = terminalView, estimatedMaxScrollback > 0 else { return }
        let fraction = Double(marker.anchorYDisp) / Double(estimatedMaxScrollback)
        tv.scroll(toPosition: min(max(fraction, 0), 1))
    }

    /// Shows the floating find bar overlay (⌘F).
    func showFindBar() {
        isShowingFindBar = true
    }

    /// Hides the find bar and clears search highlights.
    func dismissFindBar() {
        isShowingFindBar = false
        currentFindTerm = ""
        currentFindOptions = SearchOptions()
        findMatchCount = 0
        terminalView?.clearSearch()
    }

    /// Updates the active search term and options, highlights the first match,
    /// and refreshes the match count.
    func updateSearch(term: String, options: SearchOptions) {
        currentFindTerm = term
        currentFindOptions = options
        guard let tv = terminalView else {
            findMatchCount = 0
            return
        }
        if term.isEmpty {
            tv.clearSearch()
            findMatchCount = 0
            return
        }
        tv.findNext(term, options: options)
        findMatchCount = countAllMatches(term: term, options: options)
    }

    /// Moves to the next search match (⌘G).
    func findTerminalNext() {
        guard !currentFindTerm.isEmpty else { return }
        terminalView?.findNext(currentFindTerm, options: currentFindOptions)
    }

    /// Moves to the previous search match (⌘⇧G).
    func findTerminalPrevious() {
        guard !currentFindTerm.isEmpty else { return }
        terminalView?.findPrevious(currentFindTerm, options: currentFindOptions)
    }

    // MARK: - Private helpers

    private func countAllMatches(term: String, options: SearchOptions) -> Int {
        guard let terminal = terminalView?.terminal, !term.isEmpty else { return 0 }
        var count = 0
        var row = 0
        while let line = terminal.getScrollInvariantLine(row: row) {
            let text = line.translateToString(trimRight: true)
            count += occurrences(of: term, in: text, options: options)
            row += 1
        }
        return count
    }

    private func occurrences(of term: String, in text: String, options: SearchOptions) -> Int {
        if options.regex {
            var regexOptions: NSRegularExpression.Options = []
            if !options.caseSensitive { regexOptions.insert(.caseInsensitive) }
            guard let regex = try? NSRegularExpression(pattern: term, options: regexOptions) else { return 0 }
            return regex.numberOfMatches(in: text, range: NSRange(text.startIndex..., in: text))
        } else {
            var searchOptions: String.CompareOptions = []
            if !options.caseSensitive { searchOptions.insert(.caseInsensitive) }
            var count = 0
            var searchRange = text.startIndex..<text.endIndex
            while let range = text.range(of: term, options: searchOptions, range: searchRange) {
                count += 1
                if range.isEmpty {
                    // Zero-width match: advance by one character to avoid infinite loop
                    let next = text.index(after: range.lowerBound)
                    guard next <= text.endIndex else { break }
                    searchRange = next..<text.endIndex
                } else {
                    searchRange = range.upperBound..<text.endIndex
                }
            }
            return count
        }
    }
}
