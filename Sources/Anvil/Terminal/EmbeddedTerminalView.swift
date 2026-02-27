import SwiftUI
import AppKit
import SwiftTerm
import UniformTypeIdentifiers

/// Wraps a SwiftTerm terminal with process lifecycle management.
/// Shows a restart overlay when the shell process exits.
struct EmbeddedTerminalView: View {
    @ObservedObject var workingDirectory: WorkingDirectoryModel
    @EnvironmentObject var terminalProxy: TerminalInputProxy
    /// When non-nil, overrides the AppStorage setting for this instance.
    var launchCopilotOverride: Bool?
    /// When non-nil, launches `copilot --resume <id>` instead of the bare `copilot` command.
    var resumeSessionID: String? = nil
    /// When true, this tab's terminal is connected to the TerminalInputProxy.
    var isActiveTab: Bool = true
    /// Called when the terminal reports a title change via OSC sequences.
    var onTitleChange: ((String) -> Void)?
    /// Called when the user ⌘-clicks a file path in the terminal output. The Int? is a 1-based line number.
    var onOpenFile: ((URL, Int?) -> Void)?
    /// Called when a resolvable file path is detected in the terminal's scrolled-in output.
    var onOutputFilePath: ((URL) -> Void)?
    /// Called with `true` when the agent appears to be waiting for user input,
    /// and with `false` when it resumes normal output.
    var onAgentWaitingForInput: ((Bool) -> Void)?
    /// Called when the detected Copilot CLI agent mode changes.
    var onAgentModeChanged: ((AgentMode?) -> Void)?
    /// Called when the detected Copilot CLI model name changes.
    var onAgentModelChanged: ((String?) -> Void)?
    /// When non-nil and the terminal is the active tab, shows the prompt timeline
    /// gutter strip along the right margin.
    var markerStore: PromptMarkerStore? = nil
    @AppStorage("autoLaunchCopilot") private var autoLaunchCopilot = true
    @AppStorage("terminalFontSize") private var fontSize: Double = 14
    @AppStorage("terminalThemeID") private var themeID: String = TerminalTheme.defaultDark.id
    @State private var processRunning = true
    @State private var lastExitCode: Int32?
    @State private var terminalID = UUID()
    @State private var copilotNotFound = false
    @State private var isDragTargeted = false

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
        ZStack(alignment: .topTrailing) {
            TerminalNSView(
                workingDirectory: workingDirectory,
                terminalProxy: isActiveTab ? terminalProxy : nil,
                autoLaunchCopilot: shouldLaunchCopilot,
                resumeSessionID: resumeSessionID,
                fontSize: fontSize,
                theme: TerminalTheme.theme(forID: themeID),
                onProcessExit: { code in
                    lastExitCode = code
                    processRunning = false
                },
                onTitleChange: onTitleChange,
                onOpenFile: onOpenFile,
                onOutputFilePath: onOutputFilePath,
                onAgentWaitingForInput: onAgentWaitingForInput,
                onAgentModeChanged: onAgentModeChanged,
                onAgentModelChanged: onAgentModelChanged,
                onCopilotNotFound: {
                    copilotNotFound = true
                },
                onOpenURL: { url in
                    NSWorkspace.shared.open(url)
                }
            )
            .padding(14)
            .id(terminalID)

            if isDragTargeted {
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(Color.accentColor, lineWidth: 2)
                    .background(Color.accentColor.opacity(0.08).clipShape(RoundedRectangle(cornerRadius: 4)))
                    .allowsHitTesting(false)
            }

            if !processRunning {
                terminalRestartOverlay
            }

            if copilotNotFound && shouldLaunchCopilot {
                copilotNotFoundBanner
            }

            if terminalProxy.isShowingFindBar && isActiveTab {
                TerminalSearchBarView(proxy: terminalProxy)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .animation(.easeInOut(duration: 0.2), value: terminalProxy.isShowingFindBar)
            }

            // Prompt timeline gutter strip — shown only on the active tab when
            // there are markers to display.  Positioned left of the NSScroller.
            if isActiveTab, let store = markerStore, !store.markers.isEmpty {
                PromptTimelineView(markerStore: store)
                    .padding(.trailing, NSScroller.scrollerWidth(for: .regular, scrollerStyle: .legacy))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                    .allowsHitTesting(true)
            }
        }
        .background(Color(nsColor: TerminalTheme.theme(forID: themeID).background))
        .onDrop(of: [.fileURL], isTargeted: $isDragTargeted) { providers in
            handleFileDrop(providers: providers)
            return true
        }
    }

    private func handleFileDrop(providers: [NSItemProvider]) {
        var results: [Int: String] = [:]
        let group = DispatchGroup()
        let lock = NSLock()
        let rootURL = workingDirectory.directoryURL

        for (index, provider) in providers.enumerated() {
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                defer { group.leave() }
                guard let data = item as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                let raw = TerminalDropHelper.projectRelativePath(for: url, rootURL: rootURL)
                let sanitized = TerminalDropHelper.sanitizePath(raw)
                let escaped = TerminalDropHelper.shellEscapePath(sanitized)
                lock.lock()
                results[index] = escaped
                lock.unlock()
            }
        }

        group.notify(queue: .main) {
            let text = (0..<providers.count).compactMap { results[$0] }.joined(separator: " ")
            guard !text.isEmpty else { return }
            terminalProxy.send(text)
        }
    }

    private var copilotNotFoundBanner: some View {
        VStack(spacing: 0) {
            Spacer()
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(.yellow)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Copilot CLI not found")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text("Install with: npm install -g @githubnext/github-copilot-cli")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                Spacer()
                Button {
                    // Re-check — only dismiss if copilot is now available
                    DispatchQueue.global(qos: .userInitiated).async {
                        let available = CopilotDetector.isAvailable()
                        DispatchQueue.main.async {
                            if available {
                                copilotNotFound = false
                                // Send directly via proxy (best effort for current tab)
                                terminalProxy.send("copilot\n")
                            }
                        }
                    }
                } label: {
                    Text("Retry")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                Button {
                    copilotNotFound = false
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)
            .overlay(alignment: .top) { Divider() }
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .animation(.easeInOut(duration: 0.25), value: copilotNotFound)
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
    var resumeSessionID: String?
    var fontSize: Double
    var theme: TerminalTheme
    var onProcessExit: (Int32?) -> Void
    var onTitleChange: ((String) -> Void)?
    var onOpenFile: ((URL, Int?) -> Void)?
    var onOutputFilePath: ((URL) -> Void)?
    var onAgentWaitingForInput: ((Bool) -> Void)?
    var onAgentModeChanged: ((AgentMode?) -> Void)?
    var onAgentModelChanged: ((String?) -> Void)?
    var onCopilotNotFound: (() -> Void)?
    var onOpenURL: ((URL) -> Void)?

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
            context.coordinator.scheduleAutoLaunch(terminalView, resumeSessionID: resumeSessionID)
        }

        // Attach ⌘-click file path and URL detector
        let detector = context.coordinator.filePathDetector
        detector.onOpenFile = onOpenFile
        detector.onOutputFilePath = onOutputFilePath
        detector.onOpenURL = onOpenURL
        detector.attach(to: terminalView, rootURL: workingDirectory.directoryURL)

        // Wire input-waiting detector
        context.coordinator.agentInputWatcher.onStateChanged = onAgentWaitingForInput
        // Wire mode/model detector
        context.coordinator.agentModeWatcher.onModeChanged = onAgentModeChanged
        context.coordinator.agentModeWatcher.onModelChanged = onAgentModelChanged
        // Wire proxy for scroll metrics (prompt timeline)
        context.coordinator.terminalProxy = terminalProxy

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
        detector.onOutputFilePath = onOutputFilePath
        detector.onOpenURL = onOpenURL
        // Keep input-watcher callback in sync
        context.coordinator.agentInputWatcher.onStateChanged = onAgentWaitingForInput
        // Keep mode/model watcher callbacks in sync
        context.coordinator.agentModeWatcher.onModeChanged = onAgentModeChanged
        context.coordinator.agentModeWatcher.onModelChanged = onAgentModelChanged
        // Keep proxy reference in sync for scroll metrics
        context.coordinator.terminalProxy = terminalProxy
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
        Coordinator(onProcessExit: onProcessExit, onTitleChange: onTitleChange, onCopilotNotFound: onCopilotNotFound)
    }

    final class Coordinator: NSObject, LocalProcessTerminalViewDelegate {
        let onProcessExit: (Int32?) -> Void
        let onTitleChange: ((String) -> Void)?
        let onCopilotNotFound: (() -> Void)?
        let filePathDetector = TerminalFilePathDetector()
        let agentInputWatcher = AgentInputWatcher()
        let agentModeWatcher = AgentModeWatcher()
        var lastFontSize: Double = 14
        var lastThemeID: String = TerminalTheme.defaultDark.id
        /// Weak reference to the active terminal proxy so `rangeChanged` can
        /// update scroll metrics for the prompt timeline overlay.
        weak var terminalProxy: TerminalInputProxy?

        init(onProcessExit: @escaping (Int32?) -> Void, onTitleChange: ((String) -> Void)?, onCopilotNotFound: (() -> Void)?) {
            self.onProcessExit = onProcessExit
            self.onTitleChange = onTitleChange
            self.onCopilotNotFound = onCopilotNotFound
        }

        deinit {
            filePathDetector.detach()
        }

        /// Detects whether the Copilot CLI is installed, then sends the launch
        /// command to the terminal after the shell has had time to initialize.
        /// When `resumeSessionID` is non-nil, runs `copilot --resume <id>` instead.
        func scheduleAutoLaunch(_ terminalView: LocalProcessTerminalView, resumeSessionID: String? = nil) {
            DispatchQueue.global(qos: .userInitiated).async { [weak self, weak terminalView] in
                guard CopilotDetector.isAvailable() else {
                    DispatchQueue.main.async { [weak self] in
                        self?.onCopilotNotFound?()
                    }
                    return
                }
                let command: String
                if let sessionID = resumeSessionID {
                    // Sanitize the session ID to prevent shell metacharacter injection.
                    let safeID = sessionID.filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
                    command = "copilot --resume \(safeID)\n"
                } else {
                    command = "copilot\n"
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak terminalView] in
                    terminalView?.send(txt: command)
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

        func rangeChanged(source: TerminalView, startY: Int, endY: Int) {
            guard let tv = source as? LocalProcessTerminalView else { return }
            filePathDetector.processTerminalRange(in: tv, startY: startY, endY: endY)
            agentInputWatcher.processTerminalRange(in: tv, startY: startY, endY: endY)
            agentModeWatcher.processTerminalRange(in: tv, startY: startY, endY: endY)
            terminalProxy?.updateScrollMetrics(terminalView: tv)
        }
    }
}
