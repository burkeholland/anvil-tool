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
    @StateObject private var recentProjects = RecentProjectsModel()
    @StateObject private var terminalProxy = TerminalInputProxy()
    @StateObject private var quickOpenModel = QuickOpenModel()
    @State private var sidebarWidth: CGFloat = 240
    @State private var previewWidth: CGFloat = 400
    @State private var showSidebar = true
    @State private var sidebarTab: SidebarTab = .files
    @State private var showQuickOpen = false
    @AppStorage("autoFollowChanges") private var autoFollow = true

    var body: some View {
        Group {
            if workingDirectory.directoryURL != nil {
                projectView
                    .environmentObject(terminalProxy)
            } else {
                WelcomeView(
                    recentProjects: recentProjects,
                    onOpen: { url in openDirectory(url) },
                    onBrowse: { browseForDirectory() }
                )
            }
        }
        .frame(minWidth: 800, minHeight: 500)
        .background(Color(nsColor: .windowBackgroundColor))
        .navigationTitle(workingDirectory.projectName)
        .focusedSceneValue(\.sidebarVisible, $showSidebar)
        .focusedSceneValue(\.sidebarTab, $sidebarTab)
        .focusedSceneValue(\.previewOpen, filePreview.selectedURL != nil)
        .focusedSceneValue(\.closePreview, { [weak filePreview] in
            if let url = filePreview?.selectedURL {
                filePreview?.closeTab(url)
            }
        })
        .focusedSceneValue(\.openDirectory, {
            browseForDirectory()
        })
        .focusedSceneValue(\.refresh, { [weak changesModel, weak workingDirectory] in
            if let url = workingDirectory?.directoryURL {
                changesModel?.start(rootURL: url)
            }
        })
        .focusedSceneValue(\.quickOpen, workingDirectory.directoryURL != nil ? { showQuickOpen = true } : nil)
        .focusedSceneValue(\.autoFollow, $autoFollow)
        .onChange(of: workingDirectory.directoryURL) { _, newURL in
            filePreview.close()
            filePreview.rootDirectory = newURL
            if let url = newURL {
                recentProjects.recordOpen(url)
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
        .onChange(of: activityModel.latestFileChange) { _, change in
            guard autoFollow, let change = change else { return }
            filePreview.select(change.url)
        }
    }

    private var projectView: some View {
        ZStack {
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
                        autoFollow: $autoFollow,
                        onOpenDirectory: { browseForDirectory() }
                    )

                    EmbeddedTerminalView(workingDirectory: workingDirectory)
                        .id(workingDirectory.directoryURL)
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

            // Quick Open overlay
            if showQuickOpen {
                Color.black.opacity(0.2)
                    .ignoresSafeArea()
                    .onTapGesture { dismissQuickOpen() }

                VStack {
                    QuickOpenView(
                        model: quickOpenModel,
                        filePreview: filePreview,
                        onDismiss: { dismissQuickOpen() }
                    )
                    .padding(.top, 60)

                    Spacer()
                }
            }
        }
        .onChange(of: showQuickOpen) { _, isShowing in
            if isShowing, let url = workingDirectory.directoryURL {
                quickOpenModel.index(rootURL: url)
            }
        }
    }

    private func openDirectory(_ url: URL) {
        // Validate directory still exists before switching
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir),
              isDir.boolValue else {
            recentProjects.remove(
                RecentProjectsModel.RecentProject(path: url.standardizedFileURL.path, name: url.lastPathComponent, lastOpened: Date())
            )
            return
        }
        workingDirectory.setDirectory(url)
    }

    private func browseForDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "Choose a working directory for the Copilot CLI"
        if panel.runModal() == .OK, let url = panel.url {
            openDirectory(url)
        }
    }

    private func dismissQuickOpen() {
        showQuickOpen = false
        quickOpenModel.reset()
    }
}

struct ToolbarView: View {
    @ObservedObject var workingDirectory: WorkingDirectoryModel
    @Binding var showSidebar: Bool
    @Binding var autoFollow: Bool
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

            Button {
                autoFollow.toggle()
            } label: {
                Image(systemName: autoFollow ? "eye" : "eye.slash")
                    .foregroundStyle(autoFollow ? .primary : .secondary)
            }
            .buttonStyle(.borderless)
            .help(autoFollow ? "Auto-Follow Changes: On" : "Auto-Follow Changes: Off")

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
