import SwiftUI

struct ContentView: View {
    @StateObject private var workingDirectory = WorkingDirectoryModel()
    @StateObject private var filePreview = FilePreviewModel()
    @State private var sidebarWidth: CGFloat = 240
    @State private var showSidebar = true

    var body: some View {
        HStack(spacing: 0) {
            if showSidebar {
                SidebarView(model: workingDirectory, filePreview: filePreview)
                    .frame(width: sidebarWidth)

                Divider()
            }

            VStack(spacing: 0) {
                ToolbarView(
                    workingDirectory: workingDirectory,
                    showSidebar: $showSidebar
                )

                EmbeddedTerminalView(workingDirectory: workingDirectory)
                    .id(workingDirectory.directoryURL) // Respawn shell on directory change
            }

            if filePreview.selectedURL != nil {
                Divider()

                FilePreviewView(model: filePreview)
                    .frame(minWidth: 300, idealWidth: 400)
            }
        }
        .frame(minWidth: 800, minHeight: 500)
        .background(Color(nsColor: .windowBackgroundColor))
        .onChange(of: workingDirectory.directoryURL) { _, newURL in
            filePreview.close()
            filePreview.rootDirectory = newURL
        }
        .onAppear {
            filePreview.rootDirectory = workingDirectory.directoryURL
        }
    }
}

struct ToolbarView: View {
    @ObservedObject var workingDirectory: WorkingDirectoryModel
    @Binding var showSidebar: Bool

    var body: some View {
        HStack(spacing: 12) {
            Button {
                showSidebar.toggle()
            } label: {
                Image(systemName: "sidebar.leading")
            }
            .buttonStyle(.borderless)
            .help("Toggle Sidebar")

            Divider()
                .frame(height: 16)

            Image(systemName: "folder")
                .foregroundStyle(.secondary)
            Text(workingDirectory.displayPath)
                .font(.system(.body, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.head)

            Spacer()

            Button("Open…") {
                chooseDirectory()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private func chooseDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "Choose a working directory for the Copilot CLI"
        if panel.runModal() == .OK, let url = panel.url {
            workingDirectory.setDirectory(url)
        }
    }
}

struct SidebarView: View {
    @ObservedObject var model: WorkingDirectoryModel
    @ObservedObject var filePreview: FilePreviewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Files")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(.bar)

            if let rootURL = model.directoryURL {
                FileTreeView(rootURL: rootURL, filePreview: filePreview)
                    .id(rootURL) // Reset state when directory changes
            } else {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "folder.badge.questionmark")
                        .font(.system(size: 32))
                        .foregroundStyle(.tertiary)
                    Text("No directory selected")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("Use Open… to choose a project")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }
}
