import AppKit
import SwiftUI

/// Sidebar view that lists past Copilot CLI sessions grouped by date.
struct SessionListView: View {
    @ObservedObject var model: SessionListModel
    /// IDs of sessions currently open in a terminal tab (highlighted with accent color).
    var activeSessionIDs: Set<String> = []

    var body: some View {
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
                                    sessionStateURL: model.sessionStateURL,
                                    onTap: { model.onOpenSession?(item.id) },
                                    onDelete: { model.deleteSession(id: item.id) }
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
    let sessionStateURL: URL
    let onTap: () -> Void
    let onDelete: () -> Void
    @State private var isHovered = false
    @State private var showDeleteConfirm = false

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                // Summary line
                Text(item.summary)
                    .font(.subheadline)
                    .lineLimit(2)
                    .foregroundStyle(isActive ? Color.accentColor : .primary)

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

                    // Active indicator dot
                    if isActive {
                        Spacer(minLength: 0)
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 6, height: 6)
                    }
                }
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                isHovered || isActive
                    ? Color.primary.opacity(0.05)
                    : Color.clear
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help("Resume session")
        .contextMenu {
            Button("Resume Session", action: onTap)
            Button("Copy Session ID") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(item.id, forType: .string)
            }
            Button("Reveal in Finder") {
                let url = sessionStateURL.appendingPathComponent(item.id)
                NSWorkspace.shared.open(url)
            }
            Divider()
            Button("Delete Session", role: .destructive) {
                showDeleteConfirm = true
            }
        }
        .confirmationDialog(
            "Delete Session?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive, action: onDelete)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete the session and cannot be undone.")
        }
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
