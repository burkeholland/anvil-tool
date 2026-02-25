import SwiftUI
import AppKit
import Highlightr

struct FilePreviewView: View {
    @ObservedObject var model: FilePreviewModel
    var changesModel: ChangesModel?

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

                // Source / Changes / Preview tab picker
                if model.hasDiff || model.isMarkdownFile {
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
                    }
                    .pickerStyle(.segmented)
                    .frame(width: model.hasDiff && model.isMarkdownFile ? 280 : 200)
                }

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
            } else if let content = model.fileContent {
                HighlightedTextView(
                    content: content,
                    language: model.highlightLanguage,
                    gutterChanges: model.fileDiff.map { DiffParser.gutterChanges(from: $0) } ?? [:]
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
        }
        .background(Color(nsColor: .textBackgroundColor))
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

/// NSViewRepresentable wrapper around NSTextView with Highlightr syntax highlighting
/// and a line number gutter with optional change indicators.
struct HighlightedTextView: NSViewRepresentable {
    let content: String
    let language: String?
    var gutterChanges: [Int: GutterChangeKind] = [:]

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false

        let textView = NSTextView()
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

        context.coordinator.textView = textView
        context.coordinator.rulerView = rulerView
        context.coordinator.applyHighlighting(content: content, language: language)
        rulerView.gutterChanges = gutterChanges

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.applyHighlighting(content: content, language: language)
        context.coordinator.rulerView?.gutterChanges = gutterChanges
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        weak var textView: NSTextView?
        weak var rulerView: LineNumberRulerView?
        private let highlightr: Highlightr? = Highlightr()
        private var lastContent: String?
        private var lastLanguage: String?

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
    }
}

/// Draws line numbers in a vertical ruler alongside an NSTextView,
/// with optional colored gutter bars for changed lines.
final class LineNumberRulerView: NSRulerView {
    private weak var targetTextView: NSTextView?
    private let gutterBackground = NSColor(red: 0.10, green: 0.10, blue: 0.12, alpha: 1.0)
    private let lineNumberColor = NSColor(white: 0.40, alpha: 1.0)
    private let lineNumberFont = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)

    /// Line-number → change kind mapping. Set externally; triggers redraw.
    var gutterChanges: [Int: GutterChangeKind] = [:] {
        didSet { needsDisplay = true }
    }

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
        let width = sampleString.size(withAttributes: [.font: lineNumberFont]).width
        let newThickness = ceil(width) + 20 // 10pt padding on each side
        if abs(ruleThickness - newThickness) > 1 {
            ruleThickness = newThickness
        }
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

        let attrs: [NSAttributedString.Key: Any] = [
            .font: lineNumberFont,
            .foregroundColor: lineNumberColor,
        ]

        // Walk through each line in the visible range
        var lineNumber = content.substring(to: visibleCharRange.location)
            .components(separatedBy: "\n").count
        var charIndex = visibleCharRange.location

        while charIndex < NSMaxRange(visibleCharRange) {
            let lineRange = content.lineRange(for: NSRange(location: charIndex, length: 0))
            let glyphRange = layoutManager.glyphRange(forCharacterRange: lineRange, actualCharacterRange: nil)
            var lineRect = layoutManager.lineFragmentRect(forGlyphAt: glyphRange.location, effectiveRange: nil)
            lineRect.origin.y += textInset.height

            // Only draw if visible
            if lineRect.maxY >= visibleRect.minY && lineRect.minY <= visibleRect.maxY {
                let numStr = "\(lineNumber)" as NSString
                let strSize = numStr.size(withAttributes: attrs)
                let drawPoint = NSPoint(
                    x: ruleThickness - strSize.width - 10,
                    y: lineRect.minY + (lineRect.height - strSize.height) / 2 - visibleRect.origin.y
                )
                numStr.draw(at: drawPoint, withAttributes: attrs)

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
