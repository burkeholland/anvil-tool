import SwiftUI

/// Minimal bottom status bar showing the current working directory.
struct StatusBarView: View {
    @ObservedObject var workingDirectory: WorkingDirectoryModel
    @AppStorage("terminalThemeID") private var themeID: String = TerminalTheme.defaultDark.id

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "folder")
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
            Text(workingDirectory.displayPath)
                .lineLimit(1)
                .truncationMode(.head)
                .foregroundStyle(.secondary)

            Spacer()
        }
        .font(.system(size: 11, design: .monospaced))
        .padding(.horizontal, 14)
        .frame(height: 22)
        .frame(maxWidth: .infinity)
        .background(Color(nsColor: TerminalTheme.theme(forID: themeID).background))
        .overlay(alignment: .top) { Divider().opacity(0.3) }
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
