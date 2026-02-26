import SwiftUI

/// Bottom status bar showing selected file info and changes summary.
struct StatusBarView: View {
    @ObservedObject var workingDirectory: WorkingDirectoryModel
    @ObservedObject var filePreview: FilePreviewModel
    @ObservedObject var changesModel: ChangesModel

    var body: some View {
        HStack(spacing: 0) {
            // Left: Selected file info
            if filePreview.selectedURL != nil {
                HStack(spacing: 5) {
                    Image(systemName: "doc")
                        .font(.system(size: 9))
                    Text(filePreview.relativePath)
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
        .font(.system(size: 12, design: .monospaced))
        .foregroundStyle(.secondary)
        .frame(height: 26)
        .frame(maxWidth: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(alignment: .top) { Divider() }
        .overlay(alignment: .top) {
            if let error = workingDirectory.lastSyncError {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.yellow)
                    Text(error)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer()
                    Button {
                        workingDirectory.lastSyncError = nil
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.borderless)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(.ultraThinMaterial)
                .overlay(alignment: .bottom) { Divider() }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: workingDirectory.lastSyncError != nil)
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
