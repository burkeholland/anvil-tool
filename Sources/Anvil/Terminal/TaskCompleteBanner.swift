import SwiftUI

/// A floating banner that appears when the Copilot agent goes idle after making
/// changes, providing a summary and quick actions for the review workflow.
struct TaskCompleteBanner: View {
    let changedFileCount: Int
    let totalAdditions: Int
    let totalDeletions: Int
    var onReviewAll: () -> Void
    var onStageAllAndCommit: () -> Void
    var onNewTask: () -> Void
    var onDismiss: () -> Void

    var body: some View {
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

            Spacer()

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
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) { Divider() }
    }
}
