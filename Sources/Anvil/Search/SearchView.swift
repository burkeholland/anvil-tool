import SwiftUI
import AppKit

/// Sidebar view for project-wide text search with results grouped by file.
struct SearchView: View {
    @ObservedObject var model: SearchModel
    @ObservedObject var filePreview: FilePreviewModel
    @EnvironmentObject var terminalProxy: TerminalInputProxy

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Search input
            SearchInputBar(model: model)

            Divider()

            // Results
            if model.query.trimmingCharacters(in: .whitespaces).isEmpty {
                emptyState
            } else if model.isSearching {
                searchingState
            } else if model.results.isEmpty {
                noResultsState
            } else {
                resultsList
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "magnifyingglass")
                .font(.system(size: 28))
                .foregroundStyle(.tertiary)
            Text("Search in files")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("Type to search across\nall project files")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var searchingState: some View {
        VStack(spacing: 8) {
            Spacer()
            ProgressView()
                .controlSize(.small)
            Text("Searching…")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var noResultsState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "magnifyingglass")
                .font(.system(size: 28))
                .foregroundStyle(.tertiary)
            Text("No results")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("No matches for \"\(model.query)\"")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var resultsList: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Summary
            HStack {
                Text("\(model.totalMatches) result\(model.totalMatches == 1 ? "" : "s") in \(model.results.count) file\(model.results.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    model.clear()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Clear search")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))

            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(model.results) { fileResult in
                        SearchFileSection(
                            fileResult: fileResult,
                            query: model.query,
                            caseSensitive: model.caseSensitive,
                            useRegex: model.useRegex,
                            filePreview: filePreview
                        )
                    }
                }
            }
        }
    }
}

struct SearchInputBar: View {
    @ObservedObject var model: SearchModel

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)

                TextField("Search", text: $model.query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))

                if !model.query.isEmpty {
                    Button {
                        model.clear()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.borderless)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(nsColor: .textBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5)
            )

            HStack {
                Toggle(isOn: $model.caseSensitive) {
                    Text("Aa")
                        .font(.system(size: 11, weight: model.caseSensitive ? .bold : .regular, design: .monospaced))
                }
                .toggleStyle(.button)
                .controlSize(.small)
                .help("Case Sensitive")

                Toggle(isOn: $model.useRegex) {
                    Text(".*")
                        .font(.system(size: 11, weight: model.useRegex ? .bold : .regular, design: .monospaced))
                }
                .toggleStyle(.button)
                .controlSize(.small)
                .help("Use Regular Expression")

                Spacer()
            }

            if let error = model.regexError {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.yellow)
                    Text(error)
                        .font(.system(size: 10))
                        .foregroundStyle(.red)
                        .lineLimit(2)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

struct SearchFileSection: View {
    let fileResult: SearchFileResult
    let query: String
    let caseSensitive: Bool
    let useRegex: Bool
    @ObservedObject var filePreview: FilePreviewModel
    @EnvironmentObject var terminalProxy: TerminalInputProxy
    @State private var isExpanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // File header
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .frame(width: 12)

                    Image(systemName: "doc")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)

                    Text(fileResult.fileName)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.middle)

                    if !fileResult.directoryPath.isEmpty {
                        Text(fileResult.directoryPath)
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .truncationMode(.head)
                    }

                    Spacer()

                    Text("\(fileResult.matches.count)")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color.secondary.opacity(0.15)))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .contextMenu {
                Button {
                    terminalProxy.mentionFile(relativePath: fileResult.relativePath)
                } label: {
                    Label("Mention in Terminal", systemImage: "terminal")
                }

                Divider()

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(fileResult.relativePath, forType: .string)
                } label: {
                    Label("Copy Relative Path", systemImage: "doc.on.doc")
                }

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(fileResult.url.path, forType: .string)
                } label: {
                    Label("Copy Absolute Path", systemImage: "doc.on.doc.fill")
                }

                Divider()

                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([fileResult.url])
                } label: {
                    Label("Reveal in Finder", systemImage: "folder")
                }
            }

            // Match rows
            if isExpanded {
                ForEach(fileResult.matches) { match in
                    SearchMatchRow(
                        match: match,
                        query: query,
                        caseSensitive: caseSensitive,
                        useRegex: useRegex,
                        fileURL: fileResult.url,
                        filePreview: filePreview
                    )
                }
            }
        }
    }
}

struct SearchMatchRow: View {
    let match: SearchMatch
    let query: String
    let caseSensitive: Bool
    let useRegex: Bool
    let fileURL: URL
    @ObservedObject var filePreview: FilePreviewModel

    var body: some View {
        HStack(spacing: 6) {
            // Line number
            Text("\(match.lineNumber)")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.tertiary)
                .frame(width: 36, alignment: .trailing)

            // Line content with highlighted match
            highlightedText
                .font(.system(size: 11, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .onTapGesture {
            filePreview.select(fileURL)
        }
        .background(
            filePreview.selectedURL == fileURL
                ? RoundedRectangle(cornerRadius: 3).fill(Color.accentColor.opacity(0.08))
                : nil
        )
    }

    private var highlightedText: Text {
        let content = match.lineContent.trimmingCharacters(in: .whitespaces)

        if useRegex {
            let options: NSRegularExpression.Options = caseSensitive ? [] : [.caseInsensitive]
            guard let regex = try? NSRegularExpression(pattern: query, options: options),
                  let nsMatch = regex.firstMatch(in: content, range: NSRange(content.startIndex..., in: content)),
                  let swiftRange = Range(nsMatch.range, in: content) else {
                return Text(content).foregroundColor(.secondary)
            }
            let before = String(content[content.startIndex..<swiftRange.lowerBound])
            let matched = String(content[swiftRange])
            let after = String(content[swiftRange.upperBound...])
            return Text(before).foregroundColor(.secondary)
                + Text(matched).foregroundColor(.primary).bold()
                + Text(after).foregroundColor(.secondary)
        }

        let options: String.CompareOptions = caseSensitive ? [.literal] : [.literal, .caseInsensitive]

        guard let range = content.range(of: query, options: options) else {
            return Text(content).foregroundColor(.secondary)
        }

        let before = String(content[content.startIndex..<range.lowerBound])
        let matched = String(content[range])
        let after = String(content[range.upperBound...])

        return Text(before).foregroundColor(.secondary)
            + Text(matched).foregroundColor(.primary).bold()
            + Text(after).foregroundColor(.secondary)
    }
}
