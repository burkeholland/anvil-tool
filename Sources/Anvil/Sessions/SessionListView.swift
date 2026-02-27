import SwiftUI

/// Sidebar view that lists past Copilot CLI sessions grouped by date.
struct SessionListView: View {
    @ObservedObject var model: SessionListModel

    var body: some View {
        if model.groups.isEmpty {
            emptyState
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(model.groups, id: \.group) { entry in
                        Section {
                            ForEach(entry.items) { item in
                                SessionRowView(item: item)
                                Divider()
                                    .padding(.leading, Spacing.md)
                            }
                        } header: {
                            Text(entry.group.rawValue)
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, Spacing.md)
                                .padding(.top, Spacing.md)
                                .padding(.bottom, Spacing.xs)
                        }
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: Spacing.md) {
            Spacer()
            Image(systemName: "clock.badge")
                .font(.system(size: 32))
                .foregroundStyle(.tertiary)
            Text("No sessions yet")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("Copilot CLI sessions for this\nproject will appear here")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Session Row

private struct SessionRowView: View {
    let item: SessionItem
    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            // Summary line
            Text(item.summary)
                .font(.subheadline)
                .lineLimit(2)
                .foregroundStyle(.primary)

            HStack(spacing: Spacing.xs) {
                // Relative timestamp
                Text(relativeTime(item.updatedAt))
                    .font(.caption)
                    .foregroundStyle(.tertiary)

                // Branch badge
                if let branch = item.branch {
                    Spacer(minLength: 0)
                    BranchBadge(branch: branch)
                }
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .background(
            isHovered
                ? Color.primary.opacity(0.05)
                : Color.clear
        )
        .onHover { isHovered = $0 }
    }

    private func relativeTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Branch Badge

private struct BranchBadge: View {
    let branch: String

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 9))
            Text(branch)
                .font(.system(size: 10))
                .lineLimit(1)
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 4))
    }
}
