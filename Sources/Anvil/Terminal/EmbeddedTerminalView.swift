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
    /// When true, this tab's terminal is connected to the TerminalInputProxy.
    var isActiveTab: Bool = true
    /// Called when the terminal reports a title change via OSC sequences.
    var onTitleChange: ((String) -> Void)?
    /// Called when the user ⌘-clicks a file path in the terminal output. The Int? is a 1-based line number.
    var onOpenFile: ((URL, Int?) -> Void)?
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
                fontSize: fontSize,
                theme: TerminalTheme.theme(forID: themeID),
                onProcessExit: { code in
                    lastExitCode = code
                    processRunning = false
                },
                onTitleChange: onTitleChange,
                onOpenFile: onOpenFile,
                onCopilotNotFound: {
                    copilotNotFound = true
                },
                onOpenURL: { url in
                    NSWorkspace.shared.open(url)
                }
            )
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
        }
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
    var fontSize: Double
    var theme: TerminalTheme
    var onProcessExit: (Int32?) -> Void
    var onTitleChange: ((String) -> Void)?
    var onOpenFile: ((URL, Int?) -> Void)?
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
            context.coordinator.scheduleAutoLaunch(terminalView)
        }

        // Attach ⌘-click file path and URL detector
        let detector = context.coordinator.filePathDetector
        detector.onOpenFile = onOpenFile
        detector.onOpenURL = onOpenURL
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
        detector.onOpenURL = onOpenURL
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
        var lastFontSize: Double = 14
        var lastThemeID: String = TerminalTheme.defaultDark.id

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
        func scheduleAutoLaunch(_ terminalView: LocalProcessTerminalView) {
            DispatchQueue.global(qos: .userInitiated).async { [weak self, weak terminalView] in
                guard CopilotDetector.isAvailable() else {
                    DispatchQueue.main.async { [weak self] in
                        self?.onCopilotNotFound?()
                    }
                    return
                }
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
