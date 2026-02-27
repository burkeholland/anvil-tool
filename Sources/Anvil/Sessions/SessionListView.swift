import SwiftUI

/// Sidebar view that lists past Copilot CLI sessions grouped by date.
struct SessionListView: View {
    @ObservedObject var model: SessionListModel
    /// IDs of sessions currently open in a terminal tab (highlighted with accent color).
    var activeSessionIDs: Set<String> = []

    @State private var searchText = ""

    var body: some View {
        VStack(spacing: 0) {
            sidebarHeader
            Divider()
            if model.groups.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(model.groups, id: \.group) { entry in
                            Section {
                                ForEach(entry.items) { item in
                                    SessionRowView(
                                        item: item,
                                        isActive: activeSessionIDs.contains(item.id),
                                        onTap: { model.onOpenSession?(item.id) }
                                    )
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
    }

    private var sidebarHeader: some View {
        VStack(spacing: Spacing.xs) {
            HStack {
                Text("Sessions")
                    .font(.headline)
                    .fontWeight(.semibold)
                Spacer()
                Button {
                    model.onNewSession?()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .medium))
                }
                .buttonStyle(.plain)
                .help("New Copilot Session")
            }
            .padding(.horizontal, Spacing.md)
            .padding(.top, Spacing.sm)

            HStack(spacing: Spacing.xs) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
                TextField("Search", text: $searchText)
                    .font(.subheadline)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)
            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
            .padding(.horizontal, Spacing.md)
            .padding(.bottom, Spacing.sm)
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
    let isActive: Bool
    let onTap: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: Spacing.sm) {
                // Leading sparkle icon (matches Copilot tab bar visual language)
                Image(systemName: "sparkle")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(isActive ? Color.accentColor : .tertiary)
                    .frame(width: 16)
                    .padding(.top, 1)

                VStack(alignment: .leading, spacing: Spacing.xs) {
                    HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
                        // Summary line
                        Text(item.summary)
                            .font(.subheadline)
                            .italic(item.isFallbackSummary)
                            .lineLimit(2)
                            .foregroundStyle(summaryColor)

                        // Active indicator dot
                        if isActive {
                            Circle()
                                .fill(Color.accentColor)
                                .frame(width: 6, height: 6)
                                .padding(.top, 3)
                        }
                    }

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
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                (isHovered || isActive)
                    ? Color.primary.opacity(0.05)
                    : Color.clear
            )
            .animation(.easeInOut(duration: 0.15), value: isHovered)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(item.summary)
    }

    private func relativeTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private var summaryColor: Color {
        if isActive { return Color.accentColor }
        return item.isFallbackSummary ? .secondary : .primary
    }
}

// MARK: - Branch Badge

private struct BranchBadge: View {
    let branch: String

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 10))
            Text(branch)
                .font(.system(size: 11))
                .lineLimit(1)
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Color.primary.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
    }
}
