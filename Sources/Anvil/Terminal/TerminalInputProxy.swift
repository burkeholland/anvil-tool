import Foundation
import AppKit
import SwiftTerm

/// Allows other views to send text to the embedded terminal.
/// Injected as an `@EnvironmentObject` throughout the view hierarchy.
final class TerminalInputProxy: ObservableObject {
    weak var terminalView: LocalProcessTerminalView?

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

    /// Moves keyboard focus to the terminal view.
    func focusTerminal() {
        guard let tv = terminalView else { return }
        tv.window?.makeFirstResponder(tv)
    }

    /// Shows the terminal's built-in find bar (⌘F).
    func showFindBar() {
        guard let tv = terminalView else { return }
        let item = NSMenuItem()
        item.tag = Int(NSFindPanelAction.showFindPanel.rawValue)
        tv.performFindPanelAction(item)
    }
}
