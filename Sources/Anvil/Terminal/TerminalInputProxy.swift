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

    private var currentFindTerm: String = ""
    private var currentFindOptions: SearchOptions = SearchOptions()

    func send(_ text: String) {
        terminalView?.send(txt: text)
    }

    /// Sends a single control character (e.g. Ctrl+C = 0x03, Ctrl+D = 0x04).
    func sendControl(_ byte: UInt8) {
        send(String(UnicodeScalar(byte)))
    }

    /// Sends an escape sequence (e.g. Shift+Tab = ESC [ Z).
    func sendEscape(_ sequence: String) {
        send("\u{1B}\(sequence)")
    }

    /// Sends @relativePath to the terminal for Copilot CLI file mentions.
    /// Strips control characters to prevent terminal injection.
    func mentionFile(relativePath: String) {
        let sanitized = relativePath.unicodeScalars
            .filter { $0.value >= 0x20 && $0 != "\u{7F}" }
            .map { Character($0) }
        send("@\(String(sanitized)) ")
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
