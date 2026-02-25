import SwiftUI

/// A floating banner that appears when the Copilot agent goes idle after making
/// changes, providing a summary and quick actions for the review workflow.
struct TaskCompleteBanner: View {
    let changedFileCount: Int
    let totalAdditions: Int
    let totalDeletions: Int
    let buildStatus: BuildVerifier.Status
    /// The available pre-task snapshots, newest first.
    let snapshots: [AnvilSnapshot]
    var onReviewAll: () -> Void
    var onStageAllAndCommit: () -> Void
    var onNewTask: () -> Void
    var onDismiss: () -> Void
    var onRollback: (AnvilSnapshot) -> Void

    @State private var showBuildOutput = false
    @State private var showRollbackConfirmation = false
    @State private var selectedSnapshot: AnvilSnapshot?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.green)

                Text("Agent idle")
                    .font(.system(size: 12, weight: .semibold))

                if changedFileCount > 0 {
                    Text("•")
                        .foregroundStyle(.tertiary)
                    Text("\(changedFileCount) file\(changedFileCount == 1 ? "" : "s") changed")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

                if totalAdditions > 0 || totalDeletions > 0 {
                    HStack(spacing: 4) {
                        if totalAdditions > 0 {
                            Text("+\(totalAdditions)")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.green)
                        }
                        if totalDeletions > 0 {
                            Text("-\(totalDeletions)")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.red)
                        }
                    }
                }

                // Build status badge
                buildStatusBadge

                Spacer()

                if !snapshots.isEmpty {
                    rollbackButton
                }

                if changedFileCount > 0 {
                    Button {
                        onReviewAll()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "doc.text.magnifyingglass")
                                .font(.system(size: 10))
                            Text("Review Changes")
                                .font(.system(size: 12))
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)

                    Button {
                        onStageAllAndCommit()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle")
                                .font(.system(size: 10))
                            Text("Stage All & Commit")
                                .font(.system(size: 12))
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                Button {
                    onNewTask()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus.circle")
                            .font(.system(size: 10))
                        Text("New Task")
                            .font(.system(size: 12))
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            // Expandable build error output
            if showBuildOutput, case .failed(let output) = buildStatus, !output.isEmpty {
                Divider()
                ScrollView {
                    Text(output)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .textSelection(.enabled)
                }
                .frame(maxHeight: 180)
                .background(Color(nsColor: .textBackgroundColor).opacity(0.6))
            }
        }
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) { Divider() }
        .alert("Roll Back to Pre-Task Snapshot?", isPresented: $showRollbackConfirmation) {
            Button("Roll Back", role: .destructive) {
                if let snapshot = selectedSnapshot {
                    onRollback(snapshot)
                }
            }
            Button("Cancel", role: .cancel) {
                selectedSnapshot = nil
            }
        } message: {
            if let snapshot = selectedSnapshot {
                Text("This will restore the working tree to the state from \(snapshot.relativeDate). Uncommitted changes made after that point will be discarded.")
            }
        }
    }

    @ViewBuilder
    private var rollbackButton: some View {
        if snapshots.count == 1, let snapshot = snapshots.first {
            Button {
                selectedSnapshot = snapshot
                showRollbackConfirmation = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.uturn.backward.circle")
                        .font(.system(size: 10))
                    Text("Rollback")
                        .font(.system(size: 12))
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("Restore working tree to the pre-task snapshot (\(snapshot.relativeDate))")
        } else {
            Menu {
                ForEach(snapshots) { snapshot in
                    Button {
                        selectedSnapshot = snapshot
                        showRollbackConfirmation = true
                    } label: {
                        Label(snapshot.relativeDate, systemImage: "arrow.uturn.backward.circle")
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.uturn.backward.circle")
                        .font(.system(size: 10))
                    Text("Rollback")
                        .font(.system(size: 12))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8))
                }
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5))
            .help("Roll back to a pre-task snapshot")
        }
    }

    @ViewBuilder
    private var buildStatusBadge: some View {
        switch buildStatus {
        case .idle:
            EmptyView()
        case .running:
            HStack(spacing: 4) {
                ProgressView()
                    .controlSize(.mini)
                    .scaleEffect(0.7)
                Text("Building…")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
        case .passed:
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.green)
                Text("Build passed")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Color.green.opacity(0.1), in: RoundedRectangle(cornerRadius: 4))
        case .failed:
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showBuildOutput.toggle()
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.red)
                    Text("Build failed")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Image(systemName: showBuildOutput ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 4))
            }
            .buttonStyle(.plain)
        }
    }
}
