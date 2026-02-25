import Foundation
import SwiftTerm

/// Allows other views to send text to the embedded terminal.
/// Injected as an `@EnvironmentObject` throughout the view hierarchy.
final class TerminalInputProxy: ObservableObject {
    weak var terminalView: LocalProcessTerminalView?

    func send(_ text: String) {
        terminalView?.send(txt: text)
    }

    /// Sends @relativePath to the terminal for Copilot CLI file mentions.
    /// Strips control characters to prevent terminal injection.
    func mentionFile(relativePath: String) {
        let sanitized = relativePath.unicodeScalars
            .filter { $0.value >= 0x20 && $0 != "\u{7F}" }
            .map { Character($0) }
        send("@\(String(sanitized)) ")
    }
}
