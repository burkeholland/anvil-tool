import SwiftUI

/// Shared search/filter bar for diff review views.
///
/// Supports file-path filtering and diff-content search with match navigation.
struct DiffFilterBar: View {
    @Binding var searchText: String
    let matchCount: Int
    @Binding var currentMatchIndex: Int

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField("Filter files or search diffs…", text: $searchText)
                .textFieldStyle(.plain)
                .onSubmit {
                    advanceMatch()
                }

            if !searchText.isEmpty {
                if matchCount > 0 {
                    Text("\(currentMatchIndex + 1)/\(matchCount)")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)

                    Button(action: previousMatch) {
                        Image(systemName: "chevron.up")
                    }
                    .buttonStyle(.plain)

                    Button(action: advanceMatch) {
                        Image(systemName: "chevron.down")
                    }
                    .buttonStyle(.plain)
                }

                Button(action: { searchText = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.bar)
    }

    private func advanceMatch() {
        guard matchCount > 0 else { return }
        currentMatchIndex = (currentMatchIndex + 1) % matchCount
    }

    private func previousMatch() {
        guard matchCount > 0 else { return }
        currentMatchIndex = (currentMatchIndex - 1 + matchCount) % matchCount
    }
}
