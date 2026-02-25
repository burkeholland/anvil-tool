import SwiftUI
import AppKit
import Highlightr

struct FilePreviewView: View {
    @ObservedObject var model: FilePreviewModel

    var body: some View {
        VStack(spacing: 0) {
            // Header bar
            HStack(spacing: 8) {
                Image(systemName: iconForExtension(model.fileExtension))
                    .foregroundStyle(.secondary)
                    .font(.system(size: 12))

                Text(model.fileName)
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer()

                // Source / Changes tab picker (only when diff is available)
                if model.hasDiff {
                    Picker("", selection: $model.activeTab) {
                        Text("Source").tag(PreviewTab.source)
                        HStack(spacing: 4) {
                            Text("Changes")
                            if let diff = model.fileDiff {
                                Text("+\(diff.additionCount)/-\(diff.deletionCount)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }.tag(PreviewTab.changes)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 200)
                }

                Button {
                    model.close()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Close Preview")
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
            } else if model.activeTab == .changes, let diff = model.fileDiff {
                DiffView(diff: diff)
            } else if let content = model.fileContent {
                HighlightedTextView(
                    content: content,
                    language: model.highlightLanguage
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
}

/// NSViewRepresentable wrapper around NSTextView with Highlightr syntax highlighting
/// and a line number gutter.
struct HighlightedTextView: NSViewRepresentable {
    let content: String
    let language: String?

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

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.applyHighlighting(content: content, language: language)
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

/// Draws line numbers in a vertical ruler alongside an NSTextView.
final class LineNumberRulerView: NSRulerView {
    private weak var targetTextView: NSTextView?
    private let gutterBackground = NSColor(red: 0.10, green: 0.10, blue: 0.12, alpha: 1.0)
    private let lineNumberColor = NSColor(white: 0.40, alpha: 1.0)
    private let lineNumberFont = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)

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
            }

            charIndex = NSMaxRange(lineRange)
            lineNumber += 1
        }
    }
}
