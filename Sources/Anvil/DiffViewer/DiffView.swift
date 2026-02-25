import SwiftUI

/// Renders a unified diff with colored additions/deletions and line numbers.
struct DiffView: View {
    let diff: FileDiff

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            VStack(alignment: .leading, spacing: 0) {
                // Stats bar
                HStack(spacing: 12) {
                    Label("\(diff.additionCount) additions", systemImage: "plus")
                        .foregroundStyle(.green)
                    Label("\(diff.deletionCount) deletions", systemImage: "minus")
                        .foregroundStyle(.red)
                    Spacer()
                }
                .font(.caption)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(nsColor: .controlBackgroundColor))

                Divider()

                // Hunks
                ForEach(diff.hunks) { hunk in
                    DiffHunkView(hunk: hunk)
                }
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
    }
}

struct DiffHunkView: View {
    let hunk: DiffHunk

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(hunk.lines) { line in
                DiffLineView(line: line)
            }
        }
    }
}

struct DiffLineView: View {
    let line: DiffLine

    var body: some View {
        HStack(spacing: 0) {
            // Old line number
            Text(line.oldLineNumber.map { String($0) } ?? "")
                .frame(width: 44, alignment: .trailing)
                .foregroundStyle(.tertiary)
                .font(.system(size: 11, design: .monospaced))

            // New line number
            Text(line.newLineNumber.map { String($0) } ?? "")
                .frame(width: 44, alignment: .trailing)
                .foregroundStyle(.tertiary)
                .font(.system(size: 11, design: .monospaced))

            // Gutter marker
            Text(gutterMarker)
                .frame(width: 20, alignment: .center)
                .foregroundStyle(gutterColor)
                .font(.system(size: 12, design: .monospaced))

            // Content
            Text(line.text)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(textColor)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
        .frame(height: 20)
        .background(backgroundColor)
    }

    private var gutterMarker: String {
        switch line.kind {
        case .addition:   return "+"
        case .deletion:   return "-"
        case .hunkHeader: return "…"
        case .context:    return " "
        }
    }

    private var backgroundColor: Color {
        switch line.kind {
        case .addition:   return Color.green.opacity(0.1)
        case .deletion:   return Color.red.opacity(0.1)
        case .hunkHeader: return Color(nsColor: .controlBackgroundColor)
        case .context:    return .clear
        }
    }

    private var textColor: Color {
        switch line.kind {
        case .addition:   return Color.green
        case .deletion:   return Color.red
        case .hunkHeader: return Color.secondary
        case .context:    return Color(nsColor: .textColor)
        }
    }

    private var gutterColor: Color {
        switch line.kind {
        case .addition:   return .green
        case .deletion:   return .red
        default:          return .secondary
        }
    }
}
