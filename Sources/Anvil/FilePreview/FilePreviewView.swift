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

/// NSViewRepresentable wrapper around NSTextView with Highlightr syntax highlighting.
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
        textView.textContainerInset = NSSize(width: 12, height: 12)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false

        // Allow horizontal scrolling
        textView.isHorizontallyResizable = true
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)

        scrollView.documentView = textView

        context.coordinator.textView = textView
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
        }
    }
}
