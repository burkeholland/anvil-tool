#if os(macOS)
import SwiftUI
import SwiftTerm
import AppKit

/// An NSViewRepresentable that embeds a SwiftTerm `LocalProcessTerminalView`,
/// runs the Copilot CLI, and exposes an `isCopilotPromptVisible` signal that
/// fires whenever the terminal buffer shows the Copilot input prompt (">" line).
///
/// The prompt signal is produced by `TerminalPromptDetector`, which periodically
/// scans the terminal buffer via `terminal.getLine(row:).translateToString()`.
struct EmbeddedTerminalView: NSViewRepresentable {

    // MARK: - Bindings / Observables

    /// Working directory for the spawned process.
    let workingDirectory: String

    /// Whether this tab is a Copilot CLI tab (enables prompt-based detection).
    var isCopilotTab: Bool = true

    /// Callback invoked on the main queue when the Copilot prompt visibility changes.
    var onPromptVisibilityChanged: ((Bool) -> Void)?

    // MARK: - NSViewRepresentable

    func makeNSView(context: Context) -> LocalProcessTerminalView {
        let termView = LocalProcessTerminalView(frame: .zero)

        // Spawn the Copilot CLI (or a shell for non-Copilot tabs).
        let executable = isCopilotTab ? resolvedCopilotPath() : defaultShell()
        let args = isCopilotTab ? [executable] : [executable]
        let env = buildEnvironment(workingDirectory: workingDirectory)

        termView.startProcess(
            executable: executable,
            args: args,
            environment: env,
            execName: (executable as NSString).lastPathComponent
        )

        // Wire up the prompt detector for Copilot tabs.
        if isCopilotTab {
            let detector = TerminalPromptDetector(terminal: termView.terminal)
            detector.onPromptVisibilityChanged = { [weak termView] visible in
                // Keep a strong reference to the detector via the view's layer.
                _ = termView // silence capture warning
                onPromptVisibilityChanged?(visible)
            }
            context.coordinator.detector = detector
            detector.start()
        }

        return termView
    }

    func updateNSView(_ nsView: LocalProcessTerminalView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    // MARK: - Coordinator

    final class Coordinator {
        var detector: TerminalPromptDetector?
    }

    // MARK: - Helpers

    private func resolvedCopilotPath() -> String {
        let candidates = [
            "/usr/local/bin/copilot",
            "/opt/homebrew/bin/copilot",
            "/usr/bin/copilot"
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
            ?? "/usr/local/bin/copilot"
    }

    private func defaultShell() -> String {
        ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
    }

    private func buildEnvironment(workingDirectory: String) -> [String] {
        var env = ProcessInfo.processInfo.environment
        env["TERM"] = "xterm-256color"
        env["PWD"] = workingDirectory
        return env.map { "\($0.key)=\($0.value)" }
    }
}
#endif
