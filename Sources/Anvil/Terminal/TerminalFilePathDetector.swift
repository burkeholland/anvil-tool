import AppKit
import SwiftTerm

/// Detects ⌘-click on file paths in the terminal output and opens them in the preview panel.
/// Uses an NSEvent local monitor so no subclassing of SwiftTerm views is required.
final class TerminalFilePathDetector {

    private var monitor: Any?
    private weak var terminalView: LocalProcessTerminalView?
    private var projectRootURL: URL?
    var onOpenFile: ((URL) -> Void)?

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
              let tv = terminalView,
              let rootURL = projectRootURL else {
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

        // Extract line text and find file path
        let terminal = tv.getTerminal()
        guard let bufferLine = terminal.getLine(row: row) else { return event }
        let lineText = bufferLine.translateToString(trimRight: true)
        guard let token = extractPathToken(from: lineText, column: col) else { return event }

        // Resolve to a real file
        guard let fileURL = resolveFilePath(token, rootURL: rootURL) else { return event }

        // Open the file — consume the event so SwiftTerm doesn't also handle it
        DispatchQueue.main.async { [weak self] in
            self?.onOpenFile?(fileURL)
        }
        return nil
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

    // MARK: - Path Token Extraction

    /// Extracts a file-path-like token around the given column in a line of text.
    private func extractPathToken(from line: String, column: Int) -> String? {
        guard !line.isEmpty else { return nil }
        let chars = Array(line)
        let safeCol = min(max(column, 0), chars.count - 1)

        // Expand left
        var left = safeCol
        while left > 0 && isPathChar(chars[left - 1]) {
            left -= 1
        }

        // Expand right
        var right = safeCol
        while right < chars.count - 1 && isPathChar(chars[right + 1]) {
            right += 1
        }

        guard left <= right else { return nil }
        let token = String(chars[left...right])

        // Must contain at least one path separator or dot to look like a file path
        guard token.contains("/") || token.contains(".") else { return nil }
        // Must be at least 3 chars (e.g., "a.b")
        guard token.count >= 3 else { return nil }

        return token
    }

    private func isPathChar(_ ch: Character) -> Bool {
        ch.isLetter || ch.isNumber || ch == "/" || ch == "." || ch == "-"
            || ch == "_" || ch == "+" || ch == "@" || ch == "~"
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
