import SwiftUI
import AppKit
import Highlightr

struct FilePreviewView: View {
    @ObservedObject var model: FilePreviewModel
    var changesModel: ChangesModel?
    @EnvironmentObject var terminalProxy: TerminalInputProxy
    @State private var showGoToLine = false
    @State private var goToLineText = ""

    /// Gutter changes for the current file, cached for navigation.
    private var currentGutterChanges: [Int: GutterChangeKind] {
        model.fileDiff.map { DiffParser.gutterChanges(from: $0) } ?? [:]
    }

    /// Document symbols parsed from the current file.
    private var documentSymbols: [DocumentSymbol] {
        guard let content = model.fileContent else { return [] }
        return SymbolParser.parse(source: content, language: model.highlightLanguage)
    }

    /// Number of contiguous change regions in the current file.
    private var changeRegionCount: Int {
        model.changeRegions(from: currentGutterChanges).count
    }

    /// True when viewing a working-tree diff (not commit history).
    private var isLiveDiffAvailable: Bool {
        model.commitDiffContext == nil && model.fileDiff != nil
    }

    /// Dynamic width for the segmented tab picker based on visible tabs.
    private var pickerWidth: CGFloat {
        var tabs = 1 // Source is always present
        if model.hasDiff { tabs += 1 }
        if model.isMarkdownFile { tabs += 1 }
        if !model.fileHistory.isEmpty { tabs += 1 }
        switch tabs {
        case 1:  return 100
        case 2:  return 200
        case 3:  return 280
        default: return 360
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Tab bar (when multiple tabs are open)
            if model.openTabs.count > 1 {
                PreviewTabBar(model: model)
            }

            // Header bar
            HStack(spacing: 8) {
                Image(systemName: iconForExtension(model.fileExtension))
                    .foregroundStyle(.secondary)
                    .font(.system(size: 12))

                breadcrumbPath

                if let ctx = model.commitDiffContext {
                    Text(String(ctx.sha.prefix(8)))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(.purple.opacity(0.7)))
                }

                Spacer()

                // Change navigation (source tab with changes)
                if model.activeTab == .source && changeRegionCount > 0 {
                    HStack(spacing: 4) {
                        Text("\(changeRegionCount) change\(changeRegionCount == 1 ? "" : "s")")
                            .font(.system(size: 10))
                            .foregroundStyle(.orange)

                        Button {
                            model.goToPreviousChange(gutterChanges: currentGutterChanges)
                        } label: {
                            Image(systemName: "chevron.up")
                                .font(.system(size: 9, weight: .semibold))
                                .frame(width: 18, height: 16)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.borderless)
                        .help("Previous Change")

                        Button {
                            model.goToNextChange(gutterChanges: currentGutterChanges)
                        } label: {
                            Image(systemName: "chevron.down")
                                .font(.system(size: 9, weight: .semibold))
                                .frame(width: 18, height: 16)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.borderless)
                        .help("Next Change")
                    }
                    .padding(.horizontal, 4)
                }

                // Source / Changes / Preview / History tab picker
                if model.hasDiff || model.isMarkdownFile || !model.fileHistory.isEmpty {
                    Picker("", selection: $model.activeTab) {
                        Text("Source").tag(PreviewTab.source)
                        if model.hasDiff {
                            HStack(spacing: 4) {
                                Text("Changes")
                                if let diff = model.fileDiff {
                                    Text("+\(diff.additionCount)/-\(diff.deletionCount)")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }.tag(PreviewTab.changes)
                        }
                        if model.isMarkdownFile {
                            Text("Preview").tag(PreviewTab.rendered)
                        }
                        if !model.fileHistory.isEmpty {
                            HStack(spacing: 4) {
                                Text("History")
                                Text("\(model.fileHistory.count)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }.tag(PreviewTab.history)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: pickerWidth)
                }

                // Symbol outline
                if !documentSymbols.isEmpty && model.activeTab == .source {
                    Button {
                        model.showSymbolOutline.toggle()
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "list.bullet.indent")
                                .font(.system(size: 11))
                            Text("\(documentSymbols.count)")
                                .font(.system(size: 10))
                        }
                        .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                    .help("Document Symbols")
                    .popover(isPresented: $model.showSymbolOutline, arrowEdge: .bottom) {
                        SymbolOutlineView(
                            symbols: documentSymbols,
                            onSelect: { line in
                                model.scrollToLine = line
                                model.lastNavigatedLine = line
                            },
                            onDismiss: { model.showSymbolOutline = false }
                        )
                    }
                }

                // Git blame toggle
                if model.activeTab == .source && !model.fileHistory.isEmpty {
                    Button {
                        model.showBlame.toggle()
                        if model.showBlame {
                            model.loadBlame()
                        } else {
                            model.clearBlame()
                        }
                    } label: {
                        Image(systemName: "person.text.rectangle")
                            .font(.system(size: 11))
                            .foregroundStyle(model.showBlame ? Color.accentColor : Color.secondary)
                    }
                    .buttonStyle(.borderless)
                    .help(model.showBlame ? "Hide Blame Annotations" : "Show Blame Annotations")
                }

                // @Mention in terminal
                Button {
                    terminalProxy.mentionFile(relativePath: model.relativePath)
                } label: {
                    Image(systemName: "at")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Mention in Terminal (@)")
                .disabled(model.selectedURL == nil)

                Button {
                    if let url = model.selectedURL {
                        ExternalEditorManager.openFile(url)
                    }
                } label: {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help(ExternalEditorManager.preferred.map { "Open in \($0.name)" } ?? "Open in Default App")
                .disabled(model.selectedURL == nil)

                Button {
                    if let rootURL = model.rootDirectory {
                        if let ctx = model.commitDiffContext {
                            GitHubURLBuilder.openFile(rootURL: rootURL, sha: ctx.sha, relativePath: ctx.filePath)
                        } else {
                            GitHubURLBuilder.openFile(rootURL: rootURL, relativePath: model.relativePath)
                        }
                    }
                } label: {
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Open in GitHub")
                .disabled(model.selectedURL == nil || model.rootDirectory == nil)

                Button {
                    if let url = model.selectedURL {
                        model.closeTab(url)
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Close Tab")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.bar)

            Divider()

            // Content area
            ZStack {
                if model.isLoading {
                    Spacer()
                    ProgressView()
                        .controlSize(.small)
                    Spacer()
                } else if let image = model.previewImage {
                    ImagePreviewContent(
                        image: image,
                        imageSize: model.imageSize,
                        fileSize: model.imageFileSize
                    )
                } else if model.activeTab == .changes, let diff = model.fileDiff {
                    // Only show hunk actions for working tree diffs, not commit history
                    let isLiveDiff = model.commitDiffContext == nil
                    DiffView(
                        diff: diff,
                        onStageHunk: isLiveDiff ? changesModel.map { cm in
                            { hunk in cm.stageHunk(patch: DiffParser.reconstructPatch(fileDiff: diff, hunk: hunk)) }
                        } : nil,
                        onDiscardHunk: isLiveDiff ? changesModel.map { cm in
                            { hunk in cm.discardHunk(patch: DiffParser.reconstructPatch(fileDiff: diff, hunk: hunk)) }
                        } : nil
                    )
                } else if model.activeTab == .rendered, model.isMarkdownFile, let content = model.fileContent {
                    MarkdownPreviewView(content: content)
                } else if model.activeTab == .history {
                    if let rootURL = model.rootDirectory {
                        FileHistoryView(model: model, rootURL: rootURL)
                    }
                } else if let content = model.fileContent {
                    HighlightedTextView(
                        content: content,
                        language: model.highlightLanguage,
                        gutterChanges: currentGutterChanges,
                        fileDiff: isLiveDiffAvailable ? model.fileDiff : nil,
                        onRevertHunk: isLiveDiffAvailable ? changesModel.map { cm in
                            { hunk in
                                if let diff = model.fileDiff {
                                    cm.discardHunk(patch: DiffParser.reconstructPatch(fileDiff: diff, hunk: hunk))
                                }
                            }
                        } : nil,
                        blameLines: model.showBlame ? model.blameLines : [],
                        scrollToLine: $model.scrollToLine,
                        onSendToTerminal: { [model, terminalProxy] code, startLine, endLine in
                            terminalProxy.sendCodeSnippet(
                                relativePath: model.relativePath,
                                language: model.highlightLanguage,
                                startLine: startLine,
                                endLine: endLine,
                                code: code
                            )
                        }
                    )
                } else {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "doc.questionmark")
                            .font(.system(size: 28))
                            .foregroundStyle(.tertiary)
                        Text("Unable to preview this file")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text("File may be binary or too large")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    Spacer()
                }

                // Go to Line overlay
                if showGoToLine {
                    VStack {
                        GoToLineBar(
                            text: $goToLineText,
                            lineCount: model.lineCount,
                            onGo: { line in
                                model.scrollToLine = line
                                model.lastNavigatedLine = line
                                showGoToLine = false
                                goToLineText = ""
                            },
                            onDismiss: {
                                showGoToLine = false
                                goToLineText = ""
                            }
                        )
                        .padding(.horizontal, 40)
                        .padding(.top, 8)
                        Spacer()
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }

            // Copilot prompt bar
            CopilotPromptBar(relativePath: model.relativePath)
        }
        .background(Color(nsColor: .textBackgroundColor))
        .onChange(of: model.showGoToLine) { _, show in
            guard show, model.selectedURL != nil, model.fileContent != nil, model.activeTab == .source else { return }
            withAnimation(.easeOut(duration: 0.15)) {
                showGoToLine = true
            }
            model.showGoToLine = false
        }
    }

    private func iconForExtension(_ ext: String) -> String {
        switch ext {
        case "swift":                       return "swift"
        case "js", "ts", "jsx", "tsx":      return "curlybraces"
        case "json":                        return "curlybraces.square"
        case "md", "txt":                   return "doc.text"
        case "py":                          return "chevron.left.forwardslash.chevron.right"
        case "sh", "bash", "zsh":           return "terminal"
        case "png", "jpg", "jpeg", "gif":   return "photo"
        default:                            return "doc"
        }
    }

    /// Breadcrumb-style path display: directories in tertiary, filename in primary.
    @ViewBuilder
    private var breadcrumbPath: some View {
        let dirs = model.relativeDirectoryComponents
        if dirs.isEmpty {
            Text(model.fileName)
                .font(.system(.body, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
        } else {
            (Text(dirs.joined(separator: " / ") + " / ")
                .foregroundStyle(.tertiary)
             + Text(model.fileName))
                .font(.system(.body, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.head)
        }
    }
}

/// Floating input bar for jumping to a specific line number.
struct GoToLineBar: View {
    @Binding var text: String
    let lineCount: Int
    var onGo: (Int) -> Void
    var onDismiss: () -> Void
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.right.to.line")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            TextField("Go to line (1–\(lineCount))", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 13, design: .monospaced))
                .focused($isFocused)
                .onSubmit {
                    if let line = Int(text.trimmingCharacters(in: .whitespaces)),
                       line >= 1, line <= lineCount {
                        onGo(line)
                    }
                }
                .onExitCommand {
                    onDismiss()
                }

            if let line = Int(text.trimmingCharacters(in: .whitespaces)),
               line >= 1, line <= lineCount {
                Text("↵")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            } else if !text.isEmpty {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 10))
                    .foregroundStyle(.orange)
            }

            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.accentColor.opacity(0.4), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
        .onAppear {
            isFocused = true
        }
    }
}

/// Compact input bar at the bottom of file preview for sending prompts to the Copilot CLI
/// with the current file as context (e.g. "@filename fix the alignment on line 42").
struct CopilotPromptBar: View {
    let relativePath: String
    @EnvironmentObject var terminalProxy: TerminalInputProxy
    @State private var promptText = ""
    @State private var isExpanded = false
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            Divider()

            if isExpanded {
                HStack(spacing: 8) {
                    Text("@\(fileName)")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.cyan)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    TextField("Ask Copilot about this file…", text: $promptText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .focused($isFocused)
                        .onSubmit { sendPrompt() }
                        .onExitCommand { collapse() }

                    if !promptText.isEmpty {
                        Button { sendPrompt() } label: {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(size: 16))
                                .foregroundStyle(Color.accentColor)
                        }
                        .buttonStyle(.borderless)
                        .help("Send to Copilot (↵)")
                    }

                    Button { collapse() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.borderless)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                .onAppear { isFocused = true }
            } else {
                Button { expand() } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "terminal")
                            .font(.system(size: 10))
                        Text("Ask Copilot about this file…")
                            .font(.system(size: 11))
                        Spacer()
                    }
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.3))
            }
        }
    }

    private var fileName: String {
        (relativePath as NSString).lastPathComponent
    }

    private func sendPrompt() {
        let text = promptText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        terminalProxy.mentionFile(relativePath: relativePath)
        terminalProxy.send(text + "\n")
        promptText = ""
        collapse()
    }

    private func expand() {
        withAnimation(.easeOut(duration: 0.15)) {
            isExpanded = true
        }
    }

    private func collapse() {
        withAnimation(.easeOut(duration: 0.15)) {
            isExpanded = false
            promptText = ""
        }
    }
}

/// Displays an image file centered with metadata.
struct ImagePreviewContent: View {
    let image: NSImage
    let imageSize: CGSize?
    let fileSize: Int?

    var body: some View {
        VStack(spacing: 0) {
            // Image display
            GeometryReader { geo in
                let fitted = fittedSize(for: image.size, in: geo.size)
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: fitted.width, height: fitted.height)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(checkerboard)
            }

            Divider()

            // Metadata bar
            HStack(spacing: 16) {
                if let size = imageSize, size.width > 0, size.height > 0 {
                    Label("\(Int(size.width)) × \(Int(size.height))", systemImage: "ruler")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let bytes = fileSize {
                    Label(formatBytes(bytes), systemImage: "internaldrive")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        }
    }

    /// Checkerboard background for images with transparency.
    private var checkerboard: some View {
        Canvas { context, size in
            let cellSize: CGFloat = 8
            let cols = Int(ceil(size.width / cellSize))
            let rows = Int(ceil(size.height / cellSize))
            for row in 0..<rows {
                for col in 0..<cols {
                    let isLight = (row + col) % 2 == 0
                    let rect = CGRect(
                        x: CGFloat(col) * cellSize,
                        y: CGFloat(row) * cellSize,
                        width: cellSize, height: cellSize
                    )
                    context.fill(Path(rect), with: .color(isLight ? Color(white: 0.18) : Color(white: 0.14)))
                }
            }
        }
    }

    private func fittedSize(for imageSize: CGSize, in containerSize: CGSize) -> CGSize {
        guard imageSize.width > 0, imageSize.height > 0 else { return containerSize }
        let padding: CGFloat = 24
        let maxW = containerSize.width - padding
        let maxH = containerSize.height - padding
        let scale = min(maxW / imageSize.width, maxH / imageSize.height, 1.0)
        return CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
    }

    private func formatBytes(_ bytes: Int) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        let kb = Double(bytes) / 1024
        if kb < 1024 { return String(format: "%.1f KB", kb) }
        let mb = kb / 1024
        return String(format: "%.1f MB", mb)
    }
}

/// Tab bar for switching between open files in the preview pane.
struct PreviewTabBar: View {
    @ObservedObject var model: FilePreviewModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(model.openTabs, id: \.self) { url in
                    PreviewTabItem(
                        url: url,
                        displayName: model.tabDisplayName(for: url),
                        isActive: model.selectedURL == url,
                        onSelect: { model.select(url) },
                        onClose: { model.closeTab(url) }
                    )
                }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(alignment: .bottom) {
            Divider()
        }
    }
}

struct PreviewTabItem: View {
    let url: URL
    let displayName: String
    let isActive: Bool
    let onSelect: () -> Void
    let onClose: () -> Void
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: iconForExtension(url.pathExtension.lowercased()))
                .font(.system(size: 10))
                .foregroundStyle(.secondary)

            Text(displayName)
                .font(.system(size: 11))
                .lineLimit(1)
                .foregroundStyle(isActive ? .primary : .secondary)

            Button {
                onClose()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .frame(width: 14, height: 14)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .opacity(isHovering || isActive ? 1 : 0)
            .allowsHitTesting(isHovering || isActive)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            isActive
                ? Color(nsColor: .controlBackgroundColor)
                : Color.clear
        )
        .overlay(alignment: .bottom) {
            if isActive {
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(height: 2)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { onSelect() }
        .onHover { isHovering = $0 }
    }

    private func iconForExtension(_ ext: String) -> String {
        switch ext {
        case "swift":                       return "swift"
        case "js", "ts", "jsx", "tsx":      return "curlybraces"
        case "json":                        return "curlybraces.square"
        case "md", "txt":                   return "doc.text"
        case "py":                          return "chevron.left.forwardslash.chevron.right"
        case "sh", "bash", "zsh":           return "terminal"
        case "png", "jpg", "jpeg", "gif":   return "photo"
        default:                            return "doc"
        }
    }
}

/// NSTextView subclass that adds a "Send to Terminal" context menu item and
/// handles the ⌘⇧T keyboard shortcut for sending selected code to the terminal.
private final class PreviewTextView: NSTextView {
    /// Called when the user triggers "Send to Terminal" via context menu or ⌘⇧T.
    var onSendToTerminal: (() -> Void)?

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = super.menu(for: event) ?? NSMenu()
        if onSendToTerminal != nil {
            let item = NSMenuItem(
                title: "Send to Terminal",
                action: #selector(handleSendToTerminal(_:)),
                keyEquivalent: "t"
            )
            item.keyEquivalentModifierMask = [.command, .shift]
            item.target = self
            menu.insertItem(NSMenuItem.separator(), at: 0)
            menu.insertItem(item, at: 0)
        }
        return menu
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.intersection([.command, .shift, .option, .control]) == [.command, .shift],
           event.characters?.lowercased() == "t",
           let handler = onSendToTerminal {
            handler()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    @objc private func handleSendToTerminal(_ sender: Any) {
        onSendToTerminal?()
    }
}

/// NSViewRepresentable wrapper around NSTextView with Highlightr syntax highlighting
/// and a line number gutter with optional change indicators.
struct HighlightedTextView: NSViewRepresentable {
    let content: String
    let language: String?
    var gutterChanges: [Int: GutterChangeKind] = [:]
    /// The current file diff, used for gutter click popovers.
    var fileDiff: FileDiff?
    /// Called when the user clicks "Revert" in a gutter diff popover.
    var onRevertHunk: ((DiffHunk) -> Void)?
    /// Per-line blame annotations. Empty when blame is off.
    var blameLines: [BlameLine] = []
    /// Binding to scroll to a specific line (1-based). Set to nil after scrolling.
    @Binding var scrollToLine: Int?
    /// Called when the user triggers "Send to Terminal". Receives the selected code (or empty
    /// string when nothing is selected), plus the 1-based start and end line numbers.
    var onSendToTerminal: ((String, Int, Int) -> Void)?

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false

        let textView = PreviewTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = true
        textView.drawsBackground = true
        textView.backgroundColor = NSColor(red: 0.12, green: 0.12, blue: 0.14, alpha: 1.0)
        textView.textContainerInset = NSSize(width: 8, height: 12)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false

        // Allow horizontal scrolling
        textView.isHorizontallyResizable = true
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)

        scrollView.documentView = textView

        // Install line number ruler
        scrollView.rulersVisible = true
        scrollView.hasVerticalRuler = true
        scrollView.contentView.postsBoundsChangedNotifications = true
        let rulerView = LineNumberRulerView(textView: textView)
        scrollView.verticalRulerView = rulerView

        // Wire gutter click to popover
        rulerView.onGutterClick = { [weak rulerView] lineNumber, screenRect in
            context.coordinator.handleGutterClick(lineNumber: lineNumber, rect: screenRect, rulerView: rulerView)
        }

        context.coordinator.textView = textView
        context.coordinator.rulerView = rulerView
        context.coordinator.fileDiff = fileDiff
        context.coordinator.onRevertHunk = onRevertHunk
        context.coordinator.onSendToTerminalAction = onSendToTerminal
        context.coordinator.applyHighlighting(content: content, language: language)
        rulerView.gutterChanges = gutterChanges
        rulerView.blameLines = blameLines

        let coordinator = context.coordinator
        textView.onSendToTerminal = { [weak coordinator] in
            coordinator?.sendCurrentSelectionToTerminal()
        }

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.applyHighlighting(content: content, language: language)
        context.coordinator.rulerView?.gutterChanges = gutterChanges
        context.coordinator.rulerView?.blameLines = blameLines
        context.coordinator.fileDiff = fileDiff
        context.coordinator.onRevertHunk = onRevertHunk
        context.coordinator.onSendToTerminalAction = onSendToTerminal
        if let textView = context.coordinator.textView as? PreviewTextView {
            let coordinator = context.coordinator
            textView.onSendToTerminal = onSendToTerminal != nil ? { [weak coordinator] in
                coordinator?.sendCurrentSelectionToTerminal()
            } : nil
        }

        if let line = scrollToLine {
            DispatchQueue.main.async {
                context.coordinator.scrollToLine(line)
                self.scrollToLine = nil
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        weak var textView: NSTextView?
        weak var rulerView: LineNumberRulerView?
        var fileDiff: FileDiff?
        var onRevertHunk: ((DiffHunk) -> Void)?
        /// Called when the user triggers "Send to Terminal". Receives code, startLine, endLine.
        var onSendToTerminalAction: ((String, Int, Int) -> Void)?
        private let highlightr: Highlightr? = Highlightr()
        private var lastContent: String?
        private var lastLanguage: String?
        private var activePopover: NSPopover?

        init() {
            highlightr?.setTheme(to: "atom-one-dark")
        }

        func applyHighlighting(content: String, language: String?) {
            guard let textView = textView else { return }
            // Skip if content hasn't changed
            if content == lastContent && language == lastLanguage { return }
            lastContent = content
            lastLanguage = language

            let attributed: NSAttributedString
            if let highlightr = highlightr,
               let highlighted = highlightr.highlight(content, as: language) {
                attributed = highlighted
            } else {
                // Fallback: plain monospaced text
                attributed = NSAttributedString(
                    string: content,
                    attributes: [
                        .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
                        .foregroundColor: NSColor(white: 0.85, alpha: 1.0),
                    ]
                )
            }

            textView.textStorage?.setAttributedString(attributed)
            rulerView?.refreshAfterContentChange()

        }

        /// Handles a click on a gutter change indicator.
        func handleGutterClick(lineNumber: Int, rect: NSRect, rulerView: NSRulerView?) {
            guard let diff = fileDiff,
                  let region = DiffParser.changeRegion(forLine: lineNumber, in: diff),
                  let ruler = rulerView else { return }

            // Dismiss any existing popover
            activePopover?.close()

            let popover = NSPopover()
            popover.behavior = .transient
            popover.animates = true

            let revertHandler: (() -> Void)? = onRevertHunk.map { handler in
                { [weak popover] in
                    handler(region.hunk)
                    popover?.close()
                }
            }

            let contentView = GutterDiffPopoverView(
                deletedLines: region.deletedLines,
                addedLines: region.addedLines,
                onRevert: revertHandler
            )
            popover.contentViewController = NSHostingController(rootView: contentView)
            popover.show(relativeTo: rect, of: ruler, preferredEdge: .maxX)
            activePopover = popover
        }

        /// Scrolls the text view so the given 1-based line number is visible near the top.
        func scrollToLine(_ lineNumber: Int) {
            guard let textView = textView,
                  let layoutManager = textView.layoutManager,
                  textView.textContainer != nil else { return }

            let content = textView.string as NSString
            let totalLength = content.length
            let targetLine = max(1, lineNumber)

            // Walk through lines using NSString to stay in UTF-16 space consistently
            var charIndex = 0
            var currentLine = 1
            while currentLine < targetLine && charIndex < totalLength {
                let lineRange = content.lineRange(for: NSRange(location: charIndex, length: 0))
                charIndex = NSMaxRange(lineRange)
                currentLine += 1
            }
            charIndex = min(charIndex, totalLength)

            let glyphRange = layoutManager.glyphRange(
                forCharacterRange: NSRange(location: charIndex, length: 0),
                actualCharacterRange: nil
            )
            var lineRect = layoutManager.lineFragmentRect(forGlyphAt: max(glyphRange.location, 0), effectiveRange: nil)
            lineRect.origin.y += textView.textContainerInset.height

            // Scroll so the line is ~1/4 from the top
            guard let scrollView = textView.enclosingScrollView else { return }
            let visibleHeight = scrollView.contentView.bounds.height
            let targetY = max(lineRect.origin.y - visibleHeight * 0.25, 0)
            scrollView.contentView.scroll(to: NSPoint(x: 0, y: targetY))
            scrollView.reflectScrolledClipView(scrollView.contentView)

            // Flash the line briefly for visibility
            let flashRect = NSRect(
                x: 0,
                y: lineRect.origin.y,
                width: textView.bounds.width,
                height: lineRect.height
            )
            let flashView = NSView(frame: flashRect)
            flashView.wantsLayer = true
            flashView.layer?.backgroundColor = NSColor.systemYellow.withAlphaComponent(0.3).cgColor
            textView.addSubview(flashView)
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.6
                flashView.animator().alphaValue = 0
            }, completionHandler: {
                flashView.removeFromSuperview()
            })
        }

        /// Returns the approximate 1-based line number at the top of the visible area.
        func visibleTopLine() -> Int {
            guard let textView = textView,
                  let layoutManager = textView.layoutManager,
                  let textContainer = textView.textContainer,
                  let scrollView = textView.enclosingScrollView else { return 1 }

            let visibleRect = scrollView.contentView.bounds
            let glyphRange = layoutManager.glyphRange(forBoundingRect: visibleRect, in: textContainer)
            let charRange = layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
            let content = textView.string as NSString
            let upToVisible = content.substring(to: charRange.location)
            return upToVisible.components(separatedBy: "\n").count
        }

        /// Returns the approximate 1-based line number at the bottom of the visible area.
        func visibleBottomLine() -> Int {
            guard let textView = textView,
                  let layoutManager = textView.layoutManager,
                  let textContainer = textView.textContainer,
                  let scrollView = textView.enclosingScrollView else { return 1 }

            let visibleRect = scrollView.contentView.bounds
            let glyphRange = layoutManager.glyphRange(forBoundingRect: visibleRect, in: textContainer)
            let charRange = layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
            let content = textView.string as NSString
            let endIndex = min(NSMaxRange(charRange), content.length)
            let upToEnd = content.substring(to: endIndex)
            return upToEnd.components(separatedBy: "\n").count
        }

        /// Computes the selection (or visible range if nothing is selected) and invokes
        /// `onSendToTerminalAction` with the code string and 1-based start/end line numbers.
        func sendCurrentSelectionToTerminal() {
            guard let textView = textView else { return }
            let nsString = textView.string as NSString
            let sel = textView.selectedRange()

            let code: String
            let startLine: Int
            let endLine: Int

            if sel.length > 0 {
                code = nsString.substring(with: sel)
                startLine = nsString.substring(to: sel.location).components(separatedBy: "\n").count
                let endCharIndex = max(0, NSMaxRange(sel) - 1)
                endLine = nsString.substring(to: endCharIndex).components(separatedBy: "\n").count
            } else {
                startLine = visibleTopLine()
                endLine = visibleBottomLine()
                code = ""
            }

            onSendToTerminalAction?(code, startLine, endLine)
        }
    }
}

/// Draws line numbers in a vertical ruler alongside an NSTextView,
/// with optional colored gutter bars for changed lines.
final class LineNumberRulerView: NSRulerView {
    private weak var targetTextView: NSTextView?
    private let gutterBackground = NSColor(red: 0.10, green: 0.10, blue: 0.12, alpha: 1.0)
    private let lineNumberColor = NSColor(white: 0.40, alpha: 1.0)
    private let lineNumberFont = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
    private let blameFont = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular)
    private let blameAuthorColor = NSColor(white: 0.50, alpha: 1.0)
    private let blameDateColor = NSColor(white: 0.35, alpha: 1.0)

    /// Line-number → change kind mapping. Set externally; triggers redraw.
    var gutterChanges: [Int: GutterChangeKind] = [:] {
        didSet { needsDisplay = true }
    }

    /// Per-line blame annotations indexed by 1-based line number.
    var blameLines: [BlameLine] = [] {
        didSet {
            blameMap = Dictionary(uniqueKeysWithValues: blameLines.map { ($0.lineNumber, $0) })
            updateThickness()
            needsDisplay = true
        }
    }
    /// Fast lookup for blame by line number.
    private var blameMap: [Int: BlameLine] = [:]

    /// Called when the user clicks on a gutter change indicator.
    /// Parameters: (lineNumber, rectInRulerCoordinates).
    var onGutterClick: ((Int, NSRect) -> Void)?

    init(textView: NSTextView) {
        self.targetTextView = textView
        super.init(scrollView: textView.enclosingScrollView!, orientation: .verticalRuler)
        self.ruleThickness = 40
        self.clientView = textView

        // Redraw when text changes or view scrolls
        NotificationCenter.default.addObserver(
            self, selector: #selector(textDidChange),
            name: NSText.didChangeNotification, object: textView
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(textDidChange),
            name: NSView.boundsDidChangeNotification,
            object: textView.enclosingScrollView?.contentView
        )
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func textDidChange(_ notification: Notification) {
        updateThickness()
        needsDisplay = true
    }

    /// Called by the coordinator after setting new content programmatically.
    func refreshAfterContentChange() {
        updateThickness()
        needsDisplay = true
    }

    private func updateThickness() {
        guard let textView = targetTextView else { return }
        let lineCount = max(textView.string.components(separatedBy: "\n").count, 1)
        let digitCount = max(String(lineCount).count, 2)
        let sampleString = String(repeating: "8", count: digitCount) as NSString
        let lineNumWidth = sampleString.size(withAttributes: [.font: lineNumberFont]).width
        let baseThickness = ceil(lineNumWidth) + 20 // 10pt padding on each side

        let newThickness: CGFloat
        if !blameMap.isEmpty {
            // Add space for blame: "author  2d ago" (approx 20 chars)
            let blameLabel = String(repeating: "M", count: 20) as NSString
            let blameWidth = blameLabel.size(withAttributes: [.font: blameFont]).width
            newThickness = baseThickness + blameWidth + 12 // 12pt gap between blame and line numbers
        } else {
            newThickness = baseThickness
        }
        if abs(ruleThickness - newThickness) > 1 {
            ruleThickness = newThickness
        }
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard let lineNum = lineNumber(at: point),
              gutterChanges[lineNum] != nil else {
            super.mouseDown(with: event)
            return
        }
        // Build a rect in ruler coordinates for the clicked line
        if let lineRect = lineRect(forLine: lineNum) {
            onGutterClick?(lineNum, lineRect)
        }
    }

    /// Returns the 1-based line number at the given point in ruler coordinates.
    private func lineNumber(at point: NSPoint) -> Int? {
        guard let textView = targetTextView,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer,
              let sv = scrollView else { return nil }

        let visibleRect = sv.contentView.bounds
        // Convert ruler Y to text view Y
        let textY = point.y + visibleRect.origin.y
        let adjustedY = textY - textView.textContainerInset.height

        let glyphIndex = layoutManager.glyphIndex(for: NSPoint(x: 0, y: adjustedY), in: textContainer)
        let charIndex = layoutManager.characterIndexForGlyph(at: glyphIndex)
        let content = textView.string as NSString
        let upTo = content.substring(to: min(charIndex, content.length))
        return upTo.components(separatedBy: "\n").count
    }

    /// Returns the rect in ruler coordinates for a given 1-based line number.
    private func lineRect(forLine lineNumber: Int) -> NSRect? {
        guard let textView = targetTextView,
              let layoutManager = textView.layoutManager,
              let sv = scrollView else { return nil }

        let content = textView.string as NSString
        let totalLength = content.length
        var charIndex = 0
        var currentLine = 1
        while currentLine < lineNumber && charIndex < totalLength {
            let lineRange = content.lineRange(for: NSRange(location: charIndex, length: 0))
            charIndex = NSMaxRange(lineRange)
            currentLine += 1
        }
        charIndex = min(charIndex, totalLength)

        let glyphRange = layoutManager.glyphRange(
            forCharacterRange: NSRange(location: charIndex, length: 0),
            actualCharacterRange: nil
        )
        var rect = layoutManager.lineFragmentRect(forGlyphAt: max(glyphRange.location, 0), effectiveRange: nil)
        rect.origin.y += textView.textContainerInset.height

        let visibleRect = sv.contentView.bounds
        return NSRect(
            x: 0,
            y: rect.minY - visibleRect.origin.y,
            width: ruleThickness,
            height: rect.height
        )
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let textView = targetTextView,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else { return }

        // Fill gutter background
        gutterBackground.setFill()
        rect.fill()

        // Draw separator line
        NSColor(white: 0.25, alpha: 1.0).setStroke()
        let separatorX = bounds.maxX - 0.5
        let separatorPath = NSBezierPath()
        separatorPath.move(to: NSPoint(x: separatorX, y: rect.minY))
        separatorPath.line(to: NSPoint(x: separatorX, y: rect.maxY))
        separatorPath.lineWidth = 1
        separatorPath.stroke()

        let hasBlame = !blameMap.isEmpty

        // When blame is active, draw a second separator between blame and line numbers
        if hasBlame {
            let blameLabel = String(repeating: "M", count: 20) as NSString
            let blameWidth = blameLabel.size(withAttributes: [.font: blameFont]).width
            let blameSepX = blameWidth + 8 + 0.5
            NSColor(white: 0.20, alpha: 1.0).setStroke()
            let blameSepPath = NSBezierPath()
            blameSepPath.move(to: NSPoint(x: blameSepX, y: rect.minY))
            blameSepPath.line(to: NSPoint(x: blameSepX, y: rect.maxY))
            blameSepPath.lineWidth = 1
            blameSepPath.stroke()
        }

        let content = textView.string as NSString
        let visibleRect = scrollView!.contentView.bounds
        let textInset = textView.textContainerInset

        // Visible glyph range
        let visibleGlyphRange = layoutManager.glyphRange(
            forBoundingRect: visibleRect, in: textContainer
        )
        let visibleCharRange = layoutManager.characterRange(
            forGlyphRange: visibleGlyphRange, actualGlyphRange: nil
        )

        let lineNumAttrs: [NSAttributedString.Key: Any] = [
            .font: lineNumberFont,
            .foregroundColor: lineNumberColor,
        ]

        let blameAuthorAttrs: [NSAttributedString.Key: Any] = [
            .font: blameFont,
            .foregroundColor: blameAuthorColor,
        ]
        let blameDateAttrs: [NSAttributedString.Key: Any] = [
            .font: blameFont,
            .foregroundColor: blameDateColor,
        ]

        // Track the previous line's commit SHA to suppress repeated blame rows
        var previousBlameSHA: String?

        // Walk through each line in the visible range
        var lineNumber = content.substring(to: visibleCharRange.location)
            .components(separatedBy: "\n").count
        var charIndex = visibleCharRange.location

        // Pre-compute the previous line's blame SHA for the first visible line
        if hasBlame, lineNumber > 1, let prev = blameMap[lineNumber - 1] {
            previousBlameSHA = prev.sha
        }

        while charIndex < NSMaxRange(visibleCharRange) {
            let lineRange = content.lineRange(for: NSRange(location: charIndex, length: 0))
            let glyphRange = layoutManager.glyphRange(forCharacterRange: lineRange, actualCharacterRange: nil)
            var lineRect = layoutManager.lineFragmentRect(forGlyphAt: glyphRange.location, effectiveRange: nil)
            lineRect.origin.y += textInset.height

            // Only draw if visible
            if lineRect.maxY >= visibleRect.minY && lineRect.minY <= visibleRect.maxY {
                let drawY = lineRect.minY - visibleRect.origin.y

                // Blame annotation (left of line number)
                if hasBlame, let blame = blameMap[lineNumber] {
                    let isNewCommit = blame.sha != previousBlameSHA
                    if isNewCommit {
                        // Author name (truncated to ~10 chars)
                        let authorName = blame.isUncommitted ? "Uncommitted" : String(blame.author.prefix(12))
                        let authorStr = authorName as NSString
                        let authorSize = authorStr.size(withAttributes: blameAuthorAttrs)
                        let authorPoint = NSPoint(
                            x: 6,
                            y: drawY + (lineRect.height - authorSize.height) / 2
                        )
                        authorStr.draw(at: authorPoint, withAttributes: blameAuthorAttrs)

                        // Relative date
                        let dateStr = blame.relativeDate as NSString
                        let dateSize = dateStr.size(withAttributes: blameDateAttrs)
                        let datePoint = NSPoint(
                            x: 6 + authorSize.width + 4,
                            y: drawY + (lineRect.height - dateSize.height) / 2
                        )
                        dateStr.draw(at: datePoint, withAttributes: blameDateAttrs)
                    }
                    previousBlameSHA = blame.sha
                }

                // Line number (right-aligned within line number region)
                let numStr = "\(lineNumber)" as NSString
                let strSize = numStr.size(withAttributes: lineNumAttrs)
                let drawPoint = NSPoint(
                    x: ruleThickness - strSize.width - 10,
                    y: drawY + (lineRect.height - strSize.height) / 2
                )
                numStr.draw(at: drawPoint, withAttributes: lineNumAttrs)

                // Draw gutter change indicator bar
                if let change = gutterChanges[lineNumber] {
                    let barColor: NSColor
                    switch change {
                    case .added:    barColor = NSColor.systemGreen
                    case .modified: barColor = NSColor.systemBlue
                    case .deleted:  barColor = NSColor.systemRed
                    }
                    barColor.setFill()
                    let barWidth: CGFloat = change == .deleted ? 6 : 3
                    let barY = lineRect.minY - visibleRect.origin.y
                    let barHeight = change == .deleted ? 3 : lineRect.height
                    let barRect = NSRect(
                        x: bounds.maxX - barWidth - 1,
                        y: barY,
                        width: barWidth,
                        height: barHeight
                    )
                    NSBezierPath(roundedRect: barRect, xRadius: 1, yRadius: 1).fill()
                }
            }

            charIndex = NSMaxRange(lineRange)
            lineNumber += 1
        }
    }
}

/// Popover content showing the old/new code for a gutter change region.
struct GutterDiffPopoverView: View {
    let deletedLines: [String]
    let addedLines: [String]
    var onRevert: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 6) {
                Image(systemName: "arrow.left.arrow.right")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Text(headerText)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                if let onRevert {
                    Button {
                        onRevert()
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "arrow.uturn.backward")
                                .font(.system(size: 9))
                            Text("Revert")
                                .font(.system(size: 10, weight: .medium))
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))

            Divider()

            // Diff content
            ScrollView([.horizontal, .vertical]) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(deletedLines.enumerated()), id: \.offset) { _, line in
                        Text(line.isEmpty ? " " : line)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(Color.red.opacity(0.9))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 1)
                            .background(Color.red.opacity(0.1))
                    }
                    ForEach(Array(addedLines.enumerated()), id: \.offset) { _, line in
                        Text(line.isEmpty ? " " : line)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(Color.green.opacity(0.9))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 1)
                            .background(Color.green.opacity(0.1))
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(maxHeight: 300)
        }
        .frame(width: 420)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var headerText: String {
        if deletedLines.isEmpty {
            return "\(addedLines.count) line\(addedLines.count == 1 ? "" : "s") added"
        } else if addedLines.isEmpty {
            return "\(deletedLines.count) line\(deletedLines.count == 1 ? "" : "s") deleted"
        } else {
            return "\(deletedLines.count) deleted → \(addedLines.count) added"
        }
    }
}
