import SwiftUI
import AppKit
import SwiftTerm

/// Wraps SwiftTerm's LocalProcessTerminalView in a SwiftUI-compatible view.
struct EmbeddedTerminalView: NSViewRepresentable {
    @ObservedObject var workingDirectory: WorkingDirectoryModel

    func makeNSView(context: Context) -> LocalProcessTerminalView {
        let terminalView = LocalProcessTerminalView(frame: .zero)
        terminalView.processDelegate = context.coordinator

        // Configure appearance
        let fontSize: CGFloat = 14
        terminalView.font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        terminalView.nativeBackgroundColor = NSColor(red: 0.1, green: 0.1, blue: 0.12, alpha: 1.0)
        terminalView.nativeForegroundColor = NSColor(red: 0.9, green: 0.9, blue: 0.9, alpha: 1.0)

        // Launch shell in working directory
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let env = Terminal.getEnvironmentVariables(termName: "xterm-256color")
        terminalView.startProcess(
            executable: shell,
            args: [],
            environment: env,
            execName: "-" + (shell as NSString).lastPathComponent, // login shell
            currentDirectory: workingDirectory.path
        )

        return terminalView
    }

    func updateNSView(_ nsView: LocalProcessTerminalView, context: Context) {
        // Working directory changes are handled by the shell itself (cd commands)
        // or by relaunching the terminal — we don't force-change cwd on a running shell.
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator: NSObject, LocalProcessTerminalViewDelegate {
        func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {
            // Terminal resized — no action needed
        }

        func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
            // Could update window title
        }

        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
            // Could sync with WorkingDirectoryModel
        }

        func processTerminated(source: TerminalView, exitCode: Int32?) {
            // Process ended — could show restart UI
        }
    }
}
