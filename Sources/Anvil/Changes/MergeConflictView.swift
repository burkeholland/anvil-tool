import SwiftUI

/// Visual merge conflict resolution view.
/// Shows each conflict block side-by-side with Accept Current / Accept Incoming / Accept Both buttons.
struct MergeConflictView: View {
    @ObservedObject var model: MergeConflictModel
    var onDismiss: (() -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()

            if model.blocks.isEmpty {
                emptyState
            } else if model.allResolved && model.isStaged {
                resolvedState
            } else {
                conflictList
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .font(.system(size: 12))

            Text("Resolve Conflicts")
                .font(.system(size: 13, weight: .semibold))

            if let url = model.fileURL {
                Text(url.lastPathComponent)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            if !model.blocks.isEmpty {
                let resolved = model.blocks.filter { $0.resolution != .unresolved }.count
                Text("\(resolved)/\(model.blocks.count) resolved")
                    .font(.system(size: 11))
                    .foregroundStyle(model.allResolved ? .green : .secondary)
            }

            Button {
                onDismiss?()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Close")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Conflict list

    private var conflictList: some View {
        ScrollView(.vertical) {
            LazyVStack(alignment: .leading, spacing: 0) {
                if let errorMsg = model.errorMessage {
                    errorBanner(errorMsg)
                }
                ForEach(Array(model.blocks.enumerated()), id: \.element.id) { index, block in
                    ConflictBlockView(
                        block: block,
                        index: index + 1,
                        onAcceptCurrent:  { model.acceptCurrent(id: block.id) },
                        onAcceptIncoming: { model.acceptIncoming(id: block.id) },
                        onAcceptBoth:     { model.acceptBoth(id: block.id) },
                        onUnresolve:      { model.unresolve(id: block.id) }
                    )
                    Divider()
                }
            }
        }
    }

    // MARK: - Empty / Resolved states

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "checkmark.circle")
                .font(.system(size: 24))
                .foregroundStyle(.green.opacity(0.7))
            Text("No conflicts found")
                .font(.system(size: 13, weight: .medium))
            Text("This file has no conflict markers.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var resolvedState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 32))
                .foregroundStyle(.green)
            Text("All conflicts resolved")
                .font(.system(size: 15, weight: .semibold))
            Text("The file has been written and staged.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Done") {
                onDismiss?()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Error banner

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.circle")
                .foregroundStyle(.red)
            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(.red)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.red.opacity(0.08))
    }
}

// MARK: - Individual conflict block

private struct ConflictBlockView: View {
    let block: ConflictBlock
    let index: Int
    let onAcceptCurrent: () -> Void
    let onAcceptIncoming: () -> Void
    let onAcceptBoth: () -> Void
    let onUnresolve: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            conflictHeader
            if block.resolution != .unresolved {
                resolvedRow
            } else {
                sideBySideContent
                actionBar
            }
        }
    }

    // MARK: Block header

    private var conflictHeader: some View {
        HStack(spacing: 6) {
            Text("Conflict \(index)")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)

            Spacer()

            if block.resolution != .unresolved {
                resolutionBadge
            } else {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 10))
                    .foregroundStyle(.orange)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.6))
    }

    private var resolutionBadge: some View {
        Group {
            switch block.resolution {
            case .acceptCurrent:
                Label("Current", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.blue)
            case .acceptIncoming:
                Label("Incoming", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case .acceptBoth:
                Label("Both", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.purple)
            case .unresolved:
                EmptyView()
            }
        }
        .font(.system(size: 10, weight: .medium))
    }

    // MARK: Resolved row (summary + undo)

    private var resolvedRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.system(size: 12))
            Text(resolvedSummaryText)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer()
            Button("Change") { onUnresolve() }
                .font(.system(size: 10))
                .buttonStyle(.plain)
                .foregroundStyle(.accentColor)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.green.opacity(0.06))
    }

    private var resolvedSummaryText: String {
        switch block.resolution {
        case .acceptCurrent:  return "Accepted current changes (\(block.currentLabel))"
        case .acceptIncoming: return "Accepted incoming changes (\(block.incomingLabel))"
        case .acceptBoth:     return "Accepted both versions"
        case .unresolved:     return ""
        }
    }

    // MARK: Side-by-side content

    private var sideBySideContent: some View {
        HStack(alignment: .top, spacing: 0) {
            // Current (ours / HEAD)
            conflictSide(
                label: block.currentLabel,
                lines: block.currentLines,
                color: .blue,
                background: Color.blue.opacity(0.05)
            )

            Divider()

            // Incoming (theirs)
            conflictSide(
                label: block.incomingLabel,
                lines: block.incomingLines,
                color: .green,
                background: Color.green.opacity(0.05)
            )
        }
    }

    private func conflictSide(label: String, lines: [String], color: Color, background: Color) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Side header
            HStack(spacing: 4) {
                Text(label)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(color)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.12))

            // Lines
            VStack(alignment: .leading, spacing: 0) {
                if lines.isEmpty {
                    Text("(empty)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .italic()
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                } else {
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                        Text(line.isEmpty ? " " : line)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(Color(nsColor: .labelColor))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 1)
                    }
                    .padding(.vertical, 4)
                }
            }
            .background(background)
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Action bar

    private var actionBar: some View {
        HStack(spacing: 6) {
            Spacer()
            Button {
                onAcceptCurrent()
            } label: {
                Text("Accept Current")
                    .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(.blue)

            Button {
                onAcceptIncoming()
            } label: {
                Text("Accept Incoming")
                    .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(.green)

            Button {
                onAcceptBoth()
            } label: {
                Text("Accept Both")
                    .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(.purple)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.4))
    }
}
