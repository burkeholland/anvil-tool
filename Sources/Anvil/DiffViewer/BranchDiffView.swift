import SwiftUI

/// Shows a diff between two branches with a filter/search bar.
struct BranchDiffView: View {
    let fileDiffs: [FileDiff]
    let baseBranch: String
    let compareBranch: String

    @State private var searchText = ""
    @State private var currentMatchIndex = 0

    var body: some View {
        VStack(spacing: 0) {
            // Branch header
            HStack {
                Label(baseBranch, systemImage: "arrow.triangle.branch")
                Image(systemName: "arrow.right")
                    .foregroundStyle(.secondary)
                Label(compareBranch, systemImage: "arrow.triangle.branch")
                Spacer()
                Text("\(fileDiffs.count) files changed")
                    .foregroundStyle(.secondary)
            }
            .font(.callout)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

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
