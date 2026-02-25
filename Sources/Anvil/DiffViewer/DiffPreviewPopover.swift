import SwiftUI

/// A compact popover that shows the first few diff hunks with syntax highlighting.
/// Used for hover previews on file rows in the Changes and Activity panels.
struct DiffPreviewPopover: View {
    let diff: FileDiff
    var onOpenFull: (() -> Void)?
    private let maxHunks = 3

    private var previewHunks: [DiffHunk] {
        Array(diff.hunks.prefix(maxHunks))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 8) {
                Text((diff.newPath as NSString).lastPathComponent)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer()

                if diff.additionCount > 0 {
                    Text("+\(diff.additionCount)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.green)
                }
                if diff.deletionCount > 0 {
                    Text("-\(diff.deletionCount)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.red)
                }

                if let onOpenFull {
                    Button {
                        onOpenFull()
                    } label: {
                        Image(systemName: "arrow.up.right.square")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                    .help("Open full diff")
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            ScrollView(.vertical) {
                let highlights = DiffSyntaxHighlighter.highlight(diff: diff)
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(previewHunks) { hunk in
                        DiffHunkView(hunk: hunk, syntaxHighlights: highlights)
                    }
                    if diff.hunks.count > maxHunks {
                        let remaining = diff.hunks.count - maxHunks
                        Text("… \(remaining) more hunk\(remaining == 1 ? "" : "s") not shown")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                    }
                }
            }
            .frame(maxHeight: 300)
        }
        .frame(width: 520)
        .background(Color(nsColor: .textBackgroundColor))
    }
}
