import SwiftUI
import AppKit
import SwiftTerm

/// Wraps a SwiftTerm terminal with process lifecycle management.
/// Shows a restart overlay when the shell process exits.
struct EmbeddedTerminalView: View {
    @ObservedObject var workingDirectory: WorkingDirectoryModel
    @EnvironmentObject var terminalProxy: TerminalInputProxy
    @AppStorage("autoLaunchCopilot") private var autoLaunchCopilot = true
    @State private var processRunning = true
    @State private var lastExitCode: Int32?
    @State private var terminalID = UUID()

    var body: some View {
        ZStack {
            TerminalNSView(
                workingDirectory: workingDirectory,
                terminalProxy: terminalProxy,
                autoLaunchCopilot: autoLaunchCopilot,
                onProcessExit: { code in
                    lastExitCode = code
                    processRunning = false
                }
            )
            .id(terminalID)

            if !processRunning {
                terminalRestartOverlay
            }
        }
    }

    private var terminalRestartOverlay: some View {
        ZStack {
            Color.black.opacity(0.6)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                Image(systemName: "terminal")
                    .font(.system(size: 32))
                    .foregroundStyle(.secondary)

                Text("Process exited")
                    .font(.headline)
                    .foregroundStyle(.primary)

                if let code = lastExitCode {
                    Text("Exit code: \(code)")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                Button {
                    processRunning = true
                    lastExitCode = nil
                    terminalID = UUID()
                } label: {
                    Label("Restart Shell", systemImage: "arrow.counterclockwise")
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.return, modifiers: [])
            }
            .padding(32)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(.ultraThinMaterial)
            )
        }
    }
}

/// NSViewRepresentable that wraps SwiftTerm's LocalProcessTerminalView.
private struct TerminalNSView: NSViewRepresentable {
    @ObservedObject var workingDirectory: WorkingDirectoryModel
    var terminalProxy: TerminalInputProxy
    var autoLaunchCopilot: Bool
    var onProcessExit: (Int32?) -> Void

    func makeNSView(context: Context) -> LocalProcessTerminalView {
        let terminalView = LocalProcessTerminalView(frame: .zero)
        terminalView.processDelegate = context.coordinator
        terminalProxy.terminalView = terminalView

        let fontSize: CGFloat = 14
        terminalView.font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        terminalView.nativeBackgroundColor = NSColor(red: 0.1, green: 0.1, blue: 0.12, alpha: 1.0)
        terminalView.nativeForegroundColor = NSColor(red: 0.9, green: 0.9, blue: 0.9, alpha: 1.0)

        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let env = Terminal.getEnvironmentVariables(termName: "xterm-256color")
        terminalView.startProcess(
            executable: shell,
            args: [],
            environment: env,
            execName: "-" + (shell as NSString).lastPathComponent,
            currentDirectory: workingDirectory.path
        )

        if autoLaunchCopilot {
            context.coordinator.scheduleAutoLaunch(terminalView)
        }

        return terminalView
    }

    func updateNSView(_ nsView: LocalProcessTerminalView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onProcessExit: onProcessExit)
    }

    final class Coordinator: NSObject, LocalProcessTerminalViewDelegate {
        let onProcessExit: (Int32?) -> Void

        init(onProcessExit: @escaping (Int32?) -> Void) {
            self.onProcessExit = onProcessExit
        }

        /// Detects whether the Copilot CLI is installed, then sends the launch
        /// command to the terminal after the shell has had time to initialize.
        func scheduleAutoLaunch(_ terminalView: LocalProcessTerminalView) {
            DispatchQueue.global(qos: .userInitiated).async { [weak terminalView] in
                guard CopilotDetector.isAvailable() else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak terminalView] in
                    terminalView?.send(txt: "copilot\n")
                }
            }
        }

        func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}

        func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}

        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}

        func processTerminated(source: TerminalView, exitCode: Int32?) {
            DispatchQueue.main.async { [weak self] in
                self?.onProcessExit(exitCode)
            }
        }
    }
}
