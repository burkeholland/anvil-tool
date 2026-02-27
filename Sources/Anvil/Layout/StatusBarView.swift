import SwiftUI

/// Bottom status bar showing working-directory sync errors.
struct StatusBarView: View {
    @ObservedObject var workingDirectory: WorkingDirectoryModel

    var body: some View {
        HStack(spacing: 0) {
            Spacer()
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
