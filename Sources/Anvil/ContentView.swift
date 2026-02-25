import SwiftUI

enum SidebarTab {
    case files
    case changes
    case activity
}

struct ContentView: View {
    @StateObject private var workingDirectory = WorkingDirectoryModel()
    @StateObject private var filePreview = FilePreviewModel()
    @StateObject private var changesModel = ChangesModel()
    @StateObject private var activityModel = ActivityFeedModel()
    @State private var sidebarWidth: CGFloat = 240
    @State private var previewWidth: CGFloat = 400
    @State private var showSidebar = true
    @State private var sidebarTab: SidebarTab = .files

    var body: some View {
        HStack(spacing: 0) {
            if showSidebar {
                SidebarView(
                    model: workingDirectory,
                    filePreview: filePreview,
                    changesModel: changesModel,
                    activityModel: activityModel,
                    activeTab: $sidebarTab
                )
                    .frame(width: max(sidebarWidth, 0))

                PanelDivider(
                    width: $sidebarWidth,
                    minWidth: 140,
                    maxWidth: 500,
                    edge: .leading
                )
            }

            VStack(spacing: 0) {
                ToolbarView(
                    workingDirectory: workingDirectory,
                    showSidebar: $showSidebar,
                    onOpenDirectory: { [weak workingDirectory] in
                        chooseDirectory(for: workingDirectory)
                    }
                )

                EmbeddedTerminalView(workingDirectory: workingDirectory)
                    .id(workingDirectory.directoryURL) // Respawn shell on directory change
            }

            if filePreview.selectedURL != nil {
                PanelDivider(
                    width: $previewWidth,
                    minWidth: 200,
                    maxWidth: 800,
                    edge: .trailing
                )

                FilePreviewView(model: filePreview)
                    .frame(width: max(previewWidth, 0))
            }
        }
        .frame(minWidth: 800, minHeight: 500)
        .background(Color(nsColor: .windowBackgroundColor))
        .navigationTitle(workingDirectory.projectName)
        .focusedSceneValue(\.sidebarVisible, $showSidebar)
        .focusedSceneValue(\.sidebarTab, $sidebarTab)
        .focusedSceneValue(\.previewOpen, filePreview.selectedURL != nil)
        .focusedSceneValue(\.closePreview, { [weak filePreview] in filePreview?.close() })
        .focusedSceneValue(\.openDirectory, { [weak workingDirectory] in
            chooseDirectory(for: workingDirectory)
        })
        .focusedSceneValue(\.refresh, { [weak changesModel, weak workingDirectory] in
            if let url = workingDirectory?.directoryURL {
                changesModel?.start(rootURL: url)
            }
        })
        .onChange(of: workingDirectory.directoryURL) { _, newURL in
            filePreview.close()
            filePreview.rootDirectory = newURL
            if let url = newURL {
                changesModel.start(rootURL: url)
                activityModel.start(rootURL: url)
            }
        }
        .onAppear {
            filePreview.rootDirectory = workingDirectory.directoryURL
            if let url = workingDirectory.directoryURL {
                changesModel.start(rootURL: url)
                activityModel.start(rootURL: url)
            }
        }
    }

    private func chooseDirectory(for model: WorkingDirectoryModel?) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "Choose a working directory for the Copilot CLI"
        if panel.runModal() == .OK, let url = panel.url {
            model?.setDirectory(url)
        }
    }
}

struct ToolbarView: View {
    @ObservedObject var workingDirectory: WorkingDirectoryModel
    @Binding var showSidebar: Bool
    var onOpenDirectory: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button {
                showSidebar.toggle()
            } label: {
                Image(systemName: "sidebar.leading")
            }
            .buttonStyle(.borderless)
            .help("Toggle Sidebar (⌘B)")

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
                onOpenDirectory()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }
}

struct SidebarView: View {
    @ObservedObject var model: WorkingDirectoryModel
    @ObservedObject var filePreview: FilePreviewModel
    @ObservedObject var changesModel: ChangesModel
    @ObservedObject var activityModel: ActivityFeedModel
    @Binding var activeTab: SidebarTab

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Tab bar
            HStack(spacing: 0) {
                SidebarTabButton(
                    title: "Files",
                    systemImage: "folder",
                    isActive: activeTab == .files
                ) {
                    activeTab = .files
                }

                SidebarTabButton(
                    title: "Changes",
                    systemImage: "arrow.triangle.2.circlepath",
                    isActive: activeTab == .changes,
                    badge: changesModel.changedFiles.isEmpty ? nil : changesModel.changedFiles.count
                ) {
                    activeTab = .changes
                }

                SidebarTabButton(
                    title: "Activity",
                    systemImage: "clock",
                    isActive: activeTab == .activity,
                    badge: activityModel.events.isEmpty ? nil : activityModel.events.count
                ) {
                    activeTab = .activity
                }

                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(.bar)

            Divider()

            // Content
            switch activeTab {
            case .files:
                if let rootURL = model.directoryURL {
                    FileTreeView(rootURL: rootURL, filePreview: filePreview)
                        .id(rootURL)
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

            case .changes:
                ChangesListView(model: changesModel, filePreview: filePreview)

            case .activity:
                ActivityFeedView(model: activityModel, filePreview: filePreview)
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

struct SidebarTabButton: View {
    let title: String
    let systemImage: String
    let isActive: Bool
    var badge: Int? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.system(size: 11))
                Text(title)
                    .font(.system(size: 12, weight: isActive ? .semibold : .regular))

                if let badge = badge {
                    Text("\(badge)")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color.accentColor))
                }
            }
            .foregroundStyle(isActive ? .primary : .secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                isActive
                    ? RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .controlBackgroundColor))
                    : nil
            )
        }
        .buttonStyle(.plain)
    }
}
