import AppKit
import SwiftTerm

/// Detects ⌘-click on file paths and URLs in the terminal output.
/// File paths open in the preview panel (with optional line navigation).
/// URLs open in the default browser.
/// Uses an NSEvent local monitor so no subclassing of SwiftTerm views is required.
final class TerminalFilePathDetector {

    private var monitor: Any?
    private weak var terminalView: LocalProcessTerminalView?
    private var projectRootURL: URL?
    /// Called when ⌘-clicking a file path. The Int? is the 1-based line number if present.
    var onOpenFile: ((URL, Int?) -> Void)?
    /// Called when ⌘-clicking a URL. Opens in the default browser.
    var onOpenURL: ((URL) -> Void)?

    func attach(to view: LocalProcessTerminalView, rootURL: URL?) {
        detach()
        terminalView = view
        projectRootURL = rootURL
        monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp) { [weak self] event in
            self?.handleMouseUp(event) ?? event
        }
    }

    func updateRoot(_ url: URL?) {
        projectRootURL = url
    }

    func detach() {
        if let monitor = monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
        terminalView = nil
    }

    deinit {
        detach()
    }

    // MARK: - Event Handling

    private func handleMouseUp(_ event: NSEvent) -> NSEvent? {
        guard event.modifierFlags.contains(.command),
              let tv = terminalView else {
            return event
        }

        // Only handle clicks on our terminal view
        guard let windowContentView = event.window?.contentView else { return event }
        let pointInWindow = event.locationInWindow
        let pointInContent = windowContentView.convert(pointInWindow, from: nil)
        let hitView = windowContentView.hitTest(pointInContent)
        guard hitView === tv || hitView?.isDescendant(of: tv) == true else { return event }

        // Calculate grid position
        let pointInView = tv.convert(pointInWindow, from: nil)
        guard let (col, row) = gridPosition(in: tv, at: pointInView) else { return event }

        // Extract line text
        let terminal = tv.getTerminal()
        guard let bufferLine = terminal.getLine(row: row) else { return event }
        let lineText = bufferLine.translateToString(trimRight: true)

        // Try file path first (requires project root)
        if let rootURL = projectRootURL,
           let token = extractPathToken(from: lineText, column: col) {
            let (pathPart, lineNumber) = parseLineNumber(from: token)
            if let fileURL = resolveFilePath(pathPart, rootURL: rootURL) {
                DispatchQueue.main.async { [weak self] in
                    self?.onOpenFile?(fileURL, lineNumber)
                }
                return nil
            }
        }

        // Fall back to URL detection
        if let url = extractURL(from: lineText, column: col) {
            DispatchQueue.main.async { [weak self] in
                self?.onOpenURL?(url)
            }
            return nil
        }

        return event
    }

    // MARK: - Grid Position Calculation

    /// Computes the cell dimensions from the terminal view's font.
    private func cellSize(for view: LocalProcessTerminalView) -> CGSize {
        let font = view.font ?? NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        let ctFont = font as CTFont
        let ascent = CTFontGetAscent(ctFont)
        let descent = CTFontGetDescent(ctFont)
        let leading = CTFontGetLeading(ctFont)
        let cellHeight = ceil(ascent + descent + leading)
        let glyph = font.glyph(withName: "W")
        let cellWidth = font.advancement(forGlyph: glyph).width
        return CGSize(width: max(1, cellWidth), height: max(1, cellHeight))
    }

    private func gridPosition(in view: LocalProcessTerminalView, at point: CGPoint) -> (col: Int, row: Int)? {
        let cell = cellSize(for: view)
        let col = Int(point.x / cell.width)
        let row = Int((view.frame.height - point.y) / cell.height)
        let terminal = view.getTerminal()
        guard col >= 0, col < terminal.cols, row >= 0, row < terminal.rows else { return nil }
        return (col, row)
    }

    // MARK: - Path Token Extraction (internal for testing)

    /// Extracts a file-path-like token around the given column in a line of text.
    /// The token may include a `:line` or `:line:col` suffix (e.g., `main.swift:42:10`).
    func extractPathToken(from line: String, column: Int) -> String? {
        guard !line.isEmpty else { return nil }
        let chars = Array(line)
        let safeCol = min(max(column, 0), chars.count - 1)

        // Expand left
        var left = safeCol
        while left > 0 && isPathOrLocChar(chars[left - 1]) {
            left -= 1
        }

        // Expand right
        var right = safeCol
        while right < chars.count - 1 && isPathOrLocChar(chars[right + 1]) {
            right += 1
        }

        guard left <= right else { return nil }
        var token = String(chars[left...right])

        // Strip trailing colon (e.g., from "file.swift:42:" at end of error message)
        while token.hasSuffix(":") {
            token = String(token.dropLast())
        }

        // Must contain at least one path separator or dot to look like a file path
        guard token.contains("/") || token.contains(".") else { return nil }
        // Must be at least 3 chars (e.g., "a.b")
        guard token.count >= 3 else { return nil }

        return token
    }

    /// Separates a path token into the file path and an optional line number.
    /// Handles `path:line`, `path:line:col`, and plain `path`.
    func parseLineNumber(from token: String) -> (path: String, line: Int?) {
        let parts = token.components(separatedBy: ":")
        guard parts.count >= 2 else { return (token, nil) }

        // Try parsing from the end: the last numeric segments are line/col
        if parts.count >= 3,
           let _ = Int(parts[parts.count - 1]),
           let line = Int(parts[parts.count - 2]) {
            // path:line:col
            let path = parts.dropLast(2).joined(separator: ":")
            return (path, line)
        } else if let line = Int(parts.last!) {
            // path:line
            let path = parts.dropLast().joined(separator: ":")
            return (path, line)
        }

        return (token, nil)
    }

    func isPathOrLocChar(_ ch: Character) -> Bool {
        ch.isLetter || ch.isNumber || ch == "/" || ch == "." || ch == "-"
            || ch == "_" || ch == "+" || ch == "@" || ch == "~" || ch == ":"
    }

    // MARK: - URL Detection

    /// Extracts a URL from the line text around the given column position.
    func extractURL(from line: String, column: Int) -> URL? {
        // Find all URL-like ranges in the line using a simple regex
        guard let regex = try? NSRegularExpression(
            pattern: #"https?://[^\s<>\"\'\)\]}>]+"#,
            options: []
        ) else { return nil }

        let nsLine = line as NSString
        let matches = regex.matches(in: line, range: NSRange(location: 0, length: nsLine.length))

        for match in matches {
            let range = match.range
            // Check if the click column falls within this URL
            if column >= range.location && column < range.location + range.length {
                let urlString = nsLine.substring(with: range)
                // Strip trailing punctuation that's likely not part of the URL
                let cleaned = urlString.trimmingCharacters(in: CharacterSet(charactersIn: ".,;:!?)]}"))
                return URL(string: cleaned)
            }
        }

        return nil
    }

    // MARK: - File Path Resolution

    /// Resolves a token to a file URL under the project root, or nil if not a valid file.
    private func resolveFilePath(_ token: String, rootURL: URL) -> URL? {
        let cleaned = token.hasPrefix("./") ? String(token.dropFirst(2)) : token
        let candidateURL = rootURL.appendingPathComponent(cleaned).standardizedFileURL
        let rootPath = rootURL.standardizedFileURL.path
        let rootPrefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"

        // Security: only open files strictly under the project root
        guard candidateURL.path.hasPrefix(rootPrefix) else { return nil }

        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: candidateURL.path, isDirectory: &isDir), !isDir.boolValue {
            return candidateURL
        }

        return nil
    }
}
