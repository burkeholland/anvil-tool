import SwiftUI
import AppKit
import SwiftTerm

/// Wraps a SwiftTerm terminal with process lifecycle management.
/// Shows a restart overlay when the shell process exits.
struct EmbeddedTerminalView: View {
    @ObservedObject var workingDirectory: WorkingDirectoryModel
    @EnvironmentObject var terminalProxy: TerminalInputProxy
    /// When non-nil, overrides the AppStorage setting for this instance.
    var launchCopilotOverride: Bool?
    /// When true, this tab's terminal is connected to the TerminalInputProxy.
    var isActiveTab: Bool = true
    /// Called when the terminal reports a title change via OSC sequences.
    var onTitleChange: ((String) -> Void)?
    /// Called when the user ⌘-clicks a file path in the terminal output.
    var onOpenFile: ((URL) -> Void)?
    @AppStorage("autoLaunchCopilot") private var autoLaunchCopilot = true
    @AppStorage("terminalFontSize") private var fontSize: Double = 14
    @AppStorage("terminalThemeID") private var themeID: String = TerminalTheme.defaultDark.id
    @State private var processRunning = true
    @State private var lastExitCode: Int32?
    @State private var terminalID = UUID()

    private var shouldLaunchCopilot: Bool {
        // Only launch Copilot if the tab allows it AND the global setting is on
        if let override = launchCopilotOverride {
            return override && autoLaunchCopilot
        }
        return autoLaunchCopilot
    }

    static let minFontSize: Double = 9
    static let maxFontSize: Double = 32
    static let defaultFontSize: Double = 14

    func increaseFontSize() {
        fontSize = min(fontSize + 1, Self.maxFontSize)
    }

    func decreaseFontSize() {
        fontSize = max(fontSize - 1, Self.minFontSize)
    }

    func resetFontSize() {
        fontSize = Self.defaultFontSize
    }

    var body: some View {
        ZStack {
            TerminalNSView(
                workingDirectory: workingDirectory,
                terminalProxy: isActiveTab ? terminalProxy : nil,
                autoLaunchCopilot: shouldLaunchCopilot,
                fontSize: fontSize,
                theme: TerminalTheme.theme(forID: themeID),
                onProcessExit: { code in
                    lastExitCode = code
                    processRunning = false
                },
                onTitleChange: onTitleChange,
                onOpenFile: onOpenFile
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
/// Includes ⌘-click file path detection via TerminalFilePathDetector.
private struct TerminalNSView: NSViewRepresentable {
    @ObservedObject var workingDirectory: WorkingDirectoryModel
    var terminalProxy: TerminalInputProxy?
    var autoLaunchCopilot: Bool
    var fontSize: Double
    var theme: TerminalTheme
    var onProcessExit: (Int32?) -> Void
    var onTitleChange: ((String) -> Void)?
    var onOpenFile: ((URL) -> Void)?

    func makeNSView(context: Context) -> LocalProcessTerminalView {
        let terminalView = LocalProcessTerminalView(frame: .zero)
        terminalView.processDelegate = context.coordinator
        if let proxy = terminalProxy {
            proxy.terminalView = terminalView
        }

        terminalView.font = NSFont.monospacedSystemFont(ofSize: CGFloat(fontSize), weight: .regular)
        applyTheme(theme, to: terminalView)

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

        // Attach ⌘-click file path detector
        let detector = context.coordinator.filePathDetector
        detector.onOpenFile = onOpenFile
        detector.attach(to: terminalView, rootURL: workingDirectory.directoryURL)

        context.coordinator.lastFontSize = fontSize
        context.coordinator.lastThemeID = theme.id

        return terminalView
    }

    func updateNSView(_ nsView: LocalProcessTerminalView, context: Context) {
        if context.coordinator.lastFontSize != fontSize {
            context.coordinator.lastFontSize = fontSize
            nsView.font = NSFont.monospacedSystemFont(ofSize: CGFloat(fontSize), weight: .regular)
        }
        if context.coordinator.lastThemeID != theme.id {
            context.coordinator.lastThemeID = theme.id
            applyTheme(theme, to: nsView)
        }
        // Keep detector in sync with current state
        let detector = context.coordinator.filePathDetector
        detector.updateRoot(workingDirectory.directoryURL)
        detector.onOpenFile = onOpenFile
        // Reconnect proxy when this tab becomes active
        if let proxy = terminalProxy, proxy.terminalView !== nsView {
            proxy.terminalView = nsView
        }
    }

    private func applyTheme(_ theme: TerminalTheme, to view: LocalProcessTerminalView) {
        view.nativeBackgroundColor = theme.background
        view.nativeForegroundColor = theme.foreground
        view.caretColor = theme.cursor
        view.selectedTextBackgroundColor = theme.selection
        view.installColors(theme.swiftTermColors)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onProcessExit: onProcessExit, onTitleChange: onTitleChange)
    }

    final class Coordinator: NSObject, LocalProcessTerminalViewDelegate {
        let onProcessExit: (Int32?) -> Void
        let onTitleChange: ((String) -> Void)?
        let filePathDetector = TerminalFilePathDetector()
        var lastFontSize: Double = 14
        var lastThemeID: String = TerminalTheme.defaultDark.id

        init(onProcessExit: @escaping (Int32?) -> Void, onTitleChange: ((String) -> Void)?) {
            self.onProcessExit = onProcessExit
            self.onTitleChange = onTitleChange
        }

        deinit {
            filePathDetector.detach()
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

        func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
            DispatchQueue.main.async { [weak self] in
                self?.onTitleChange?(title)
            }
        }

        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}

        func processTerminated(source: TerminalView, exitCode: Int32?) {
            DispatchQueue.main.async { [weak self] in
                self?.onProcessExit(exitCode)
            }
        }
    }
}
