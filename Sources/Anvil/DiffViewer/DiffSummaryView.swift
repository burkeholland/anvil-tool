import SwiftUI

/// Shows a summary of all file diffs (e.g. after a Copilot session) with a filter/search bar.
struct DiffSummaryView: View {
    let fileDiffs: [FileDiff]

    @State private var searchText = ""
    @State private var currentMatchIndex = 0

    var body: some View {
        VStack(spacing: 0) {
            DiffFilterBar(
                searchText: $searchText,
                matchCount: contentMatchCount,
                currentMatchIndex: $currentMatchIndex
            )

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(filteredDiffs) { diff in
                            DiffFileSection(
                                fileDiff: diff,
                                searchTerm: searchText,
                                highlightedMatch: currentHighlightedMatch(for: diff)
                            )
                        }

                        if filteredDiffs.isEmpty && !searchText.isEmpty {
                            Text("No files match \"\(searchText)\"")
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity)
                                .padding()
                        }
                    }
                    .padding()
                }
                .onChange(of: currentMatchIndex) { _, _ in
                    scrollToCurrentMatch(proxy: proxy)
                }
                .onChange(of: searchText) { _, newValue in
                    currentMatchIndex = 0
                    if newValue.isEmpty {
                        currentMatchIndex = 0
                    }
                }
            }
        }
    }

    // MARK: - Filtering

    /// Files filtered by path match OR diff content match.
    private var filteredDiffs: [FileDiff] {
        guard !searchText.isEmpty else { return fileDiffs }
        let lowered = searchText.lowercased()
        return fileDiffs.filter { diff in
            diff.path.lowercased().contains(lowered) ||
            diff.containsSearchTerm(searchText)
        }
    }

    // MARK: - Content match navigation

    /// All (fileDiff, hunkIndex, lineIndex) tuples across the filtered diffs.
    private var allContentMatches: [(diffID: UUID, hunkIndex: Int, lineIndex: Int)] {
        filteredDiffs.flatMap { diff in
            diff.matchingLineIndices(for: searchText).map { match in
                (diffID: diff.id, hunkIndex: match.hunkIndex, lineIndex: match.lineIndex)
            }
        }
    }

    private var contentMatchCount: Int {
        allContentMatches.count
    }

    private func currentHighlightedMatch(for diff: FileDiff) -> (hunkIndex: Int, lineIndex: Int)? {
        guard contentMatchCount > 0 else { return nil }
        let safeIndex = currentMatchIndex % contentMatchCount
        let match = allContentMatches[safeIndex]
        guard match.diffID == diff.id else { return nil }
        return (hunkIndex: match.hunkIndex, lineIndex: match.lineIndex)
    }

    private func scrollToCurrentMatch(proxy: ScrollViewProxy) {
        guard contentMatchCount > 0 else { return }
        let safeIndex = currentMatchIndex % contentMatchCount
        let match = allContentMatches[safeIndex]
        // Find the corresponding FileDiff to build the anchor
        if let diff = filteredDiffs.first(where: { $0.id == match.diffID }) {
            let anchor = DiffView(fileDiff: diff).lineAnchor(
                hunkIndex: match.hunkIndex,
                lineIndex: match.lineIndex
            )
            withAnimation {
                proxy.scrollTo(anchor, anchor: .center)
            }
        }
    }
}

// MARK: - DiffFileSection

/// A collapsible section showing one file's diff.
struct DiffFileSection: View {
    let fileDiff: FileDiff
    var searchTerm: String = ""
    var highlightedMatch: (hunkIndex: Int, lineIndex: Int)? = nil

    @State private var isExpanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // File header
            Button(action: { isExpanded.toggle() }) {
                HStack {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .frame(width: 16)

                    Text(fileDiff.path)
                        .font(.system(.body, design: .monospaced))
                        .lineLimit(1)

                    Spacer()

                    HStack(spacing: 4) {
                        if fileDiff.additions > 0 {
                            Text("+\(fileDiff.additions)")
                                .foregroundStyle(.green)
                        }
                        if fileDiff.deletions > 0 {
                            Text("-\(fileDiff.deletions)")
                                .foregroundStyle(.red)
                        }
                    }
                    .font(.system(.caption, design: .monospaced))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Color.secondary.opacity(0.06))
                .cornerRadius(4)
            }
            .buttonStyle(.plain)

            if isExpanded {
                DiffView(
                    fileDiff: fileDiff,
                    searchTerm: searchTerm,
                    highlightedMatch: highlightedMatch
                )
                .padding(.leading, 4)
            }
        }
    }
}
