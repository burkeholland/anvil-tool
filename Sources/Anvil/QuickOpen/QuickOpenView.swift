import SwiftUI
import AppKit

/// A floating palette for quickly opening files by fuzzy name search.
/// Activated via ⌘⇧O. When `onMentionSelect` is provided, acts as a
/// file mention picker (⌘M) that inserts @path into the terminal instead.
struct QuickOpenView: View {
    @ObservedObject var model: QuickOpenModel
    @ObservedObject var filePreview: FilePreviewModel
    var onDismiss: () -> Void
    /// When set, the picker is in "mention" mode: selecting a file calls this
    /// closure with the result instead of opening it in the preview.
    var onMentionSelect: ((QuickOpenResult) -> Void)? = nil

    private var isMentionMode: Bool { onMentionSelect != nil }

    @FocusState private var isSearchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Search field
            HStack(spacing: 8) {
                Image(systemName: isMentionMode ? "at" : "magnifyingglass")
                    .font(.system(size: 14))
                    .foregroundStyle(isMentionMode ? .orange : .secondary)

                TextField(isMentionMode ? "Mention file in terminal…" : "Open file by name…", text: $model.query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 16))
                    .focused($isSearchFocused)
                    .onSubmit { openSelected() }

                if !model.query.isEmpty {
                    Button {
                        model.query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            Divider()

            // Results list
            if model.results.isEmpty && !model.query.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "doc.questionmark")
                        .font(.system(size: 24))
                        .foregroundStyle(.tertiary)
                    Text("No matching files")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, minHeight: 100)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(model.results.enumerated()), id: \.element.id) { index, result in
                                QuickOpenResultRow(
                                    result: result,
                                    isSelected: index == model.selectedIndex
                                )
                                .id(result.id)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    model.selectedIndex = index
                                    openSelected()
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .frame(maxHeight: 340)
                    .onChange(of: model.selectedIndex) { _, newIndex in
                        if let result = model.results[safe: newIndex] {
                            proxy.scrollTo(result.id, anchor: .center)
                        }
                    }
                }
            }

            // Footer hint
            HStack(spacing: 16) {
                KeyHint(keys: ["↑", "↓"], label: "navigate")
                KeyHint(keys: ["↩"], label: isMentionMode ? "mention" : "open")
                KeyHint(keys: ["esc"], label: "dismiss")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        }
        .frame(width: 500)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .windowBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.3), radius: 20, y: 10)
        .onAppear {
            isSearchFocused = true
        }
        .onKeyPress(.upArrow) {
            model.moveSelection(-1)
            return .handled
        }
        .onKeyPress(.downArrow) {
            model.moveSelection(1)
            return .handled
        }
        .onKeyPress(.escape) {
            onDismiss()
            return .handled
        }
    }

    private func openSelected() {
        guard let result = model.selectedResult else { return }
        if let onMentionSelect {
            onMentionSelect(result)
        } else {
            filePreview.select(result.url)
        }
        onDismiss()
    }
}

struct QuickOpenResultRow: View {
    let result: QuickOpenResult
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: iconForExtension(result.fileExtension))
                .font(.system(size: 13))
                .foregroundStyle(iconColor(result.fileExtension))
                .frame(width: 20)

            Text(result.name)
                .font(.system(size: 13))
                .lineLimit(1)
                .truncationMode(.middle)

            if !result.directoryPath.isEmpty {
                Text(result.directoryPath)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }

            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(
            isSelected
                ? RoundedRectangle(cornerRadius: 4).fill(Color.accentColor.opacity(0.2))
                    .padding(.horizontal, 4)
                : nil
        )
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
        case "yml", "yaml", "toml":         return "gearshape"
        default:                            return "doc"
        }
    }

    private func iconColor(_ ext: String) -> Color {
        switch ext {
        case "swift":                       return .orange
        case "js", "jsx":                   return .yellow
        case "ts", "tsx":                   return .blue
        case "json":                        return .green
        case "md", "txt":                   return .secondary
        case "py":                          return .cyan
        default:                            return .secondary
        }
    }
}

struct KeyHint: View {
    let keys: [String]
    let label: String

    var body: some View {
        HStack(spacing: 4) {
            ForEach(keys, id: \.self) { key in
                Text(key)
                    .font(.system(size: 10, design: .monospaced))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color(nsColor: .controlBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 3)
                            .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
                    )
            }
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
    }
}

// MARK: - Safe array subscript

extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
