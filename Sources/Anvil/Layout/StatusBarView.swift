import SwiftUI

/// Bottom status bar showing git branch, selected file info, and changes summary.
struct StatusBarView: View {
    @ObservedObject var workingDirectory: WorkingDirectoryModel
    @ObservedObject var filePreview: FilePreviewModel
    @ObservedObject var changesModel: ChangesModel

    var body: some View {
        HStack(spacing: 0) {
            // Left: Git branch
            if let branch = workingDirectory.gitBranch {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.triangle.branch")
                        .font(.system(size: 10))
                    Text(branch)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .padding(.horizontal, 10)
                .help("Current branch: \(branch)")

                StatusBarDivider()
            }

            // Center: Selected file info
            if let url = filePreview.selectedURL {
                HStack(spacing: 5) {
                    Image(systemName: "doc")
                        .font(.system(size: 9))
                    Text(url.lastPathComponent)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .padding(.horizontal, 10)

                if let lang = filePreview.highlightLanguage {
                    StatusBarDivider()

                    Text(lang.capitalized)
                        .padding(.horizontal, 10)
                }

                if filePreview.lineCount > 0 {
                    StatusBarDivider()

                    let lineCount = filePreview.lineCount
                    Text("\(lineCount) line\(lineCount == 1 ? "" : "s")")
                        .padding(.horizontal, 10)
                }
            }

            Spacer()

            // Right: Changes summary
            if !changesModel.changedFiles.isEmpty {
                HStack(spacing: 8) {
                    Text("\(changesModel.changedFiles.count) changed")

                    if changesModel.totalAdditions > 0 {
                        Text("+\(changesModel.totalAdditions)")
                            .foregroundStyle(.green)
                    }
                    if changesModel.totalDeletions > 0 {
                        Text("-\(changesModel.totalDeletions)")
                            .foregroundStyle(.red)
                    }
                }
                .padding(.horizontal, 10)
            }
        }
        .font(.system(size: 11, design: .monospaced))
        .foregroundStyle(.secondary)
        .frame(height: 22)
        .frame(maxWidth: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(alignment: .top) { Divider() }
    }
}

/// Thin vertical separator for status bar items.
private struct StatusBarDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.secondary.opacity(0.2))
            .frame(width: 1, height: 12)
    }
}
