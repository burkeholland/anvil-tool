import SwiftUI

/// Shown when no working directory is selected. Displays recent projects
/// and an option to open a new directory.
struct WelcomeView: View {
    @ObservedObject var recentProjects: RecentProjectsModel
    var isDroppingFolder: Bool
    var onOpen: (URL) -> Void
    var onBrowse: () -> Void
    @State private var copilotAvailable: Bool?

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // App icon and title
            VStack(spacing: 16) {
                Image(systemName: "hammer.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)

                Text("Anvil")
                    .font(.system(size: 28, weight: .semibold))

                Text("Open a project to get started with Copilot CLI")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                // Copilot CLI status
                copilotStatusView
            }

            Spacer()
                .frame(height: 40)

            // Recent projects
            if !recentProjects.recentProjects.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Recent Projects")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)

                    VStack(spacing: 2) {
                        ForEach(recentProjects.recentProjects) { project in
                            RecentProjectRow(
                                project: project,
                                gitInfo: recentProjects.gitInfo[project.path]
                            ) {
                                onOpen(project.url)
                            }
                        }
                    }
                }
                .frame(maxWidth: 400)
                .padding(.bottom, 24)
            }

            // Open button
            Button {
                onBrowse()
            } label: {
                Label("Open Directory…", systemImage: "folder")
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.return, modifiers: .command)

            Text("or drag a folder here")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.top, 6)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay {
            if isDroppingFolder {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [10, 5]))
                    .background(Color.accentColor.opacity(0.06).clipShape(RoundedRectangle(cornerRadius: 12)))
                    .padding(12)
                    .allowsHitTesting(false)
            }
        }
        .onAppear {
            checkCopilotAvailability()
            recentProjects.refreshGitInfo()
        }
    }

    @ViewBuilder
    private var copilotStatusView: some View {
        switch copilotAvailable {
        case .none:
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.mini)
                Text("Checking Copilot CLI…")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.top, 4)
        case .some(true):
            HStack(spacing: 5) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.green)
                Text("Copilot CLI ready")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 4)
        case .some(false):
            VStack(spacing: 6) {
                HStack(spacing: 5) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.yellow)
                    Text("Copilot CLI not found")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text("Install it to enable auto-launch in the terminal.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.top, 4)
        }
    }

    private func checkCopilotAvailability() {
        copilotAvailable = nil
        DispatchQueue.global(qos: .userInitiated).async {
            let available = CopilotDetector.isAvailable()
            DispatchQueue.main.async {
                withAnimation(.easeInOut(duration: 0.2)) {
                    copilotAvailable = available
                }
            }
        }
    }
}

struct RecentProjectRow: View {
    let project: RecentProjectsModel.RecentProject
    var gitInfo: GitProjectInfo?
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 10) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.accentColor)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(project.name)
                            .font(.system(size: 13, weight: .medium))
                            .lineLimit(1)
                            .truncationMode(.middle)

                        if let info = gitInfo {
                            if info.isDirty {
                                Circle()
                                    .fill(.orange)
                                    .frame(width: 6, height: 6)
                                    .help("\(info.changedFileCount) uncommitted change\(info.changedFileCount == 1 ? "" : "s")")
                            }
                        }
                    }

                    HStack(spacing: 6) {
                        Text(displayPath(project.path))
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .truncationMode(.head)

                        if let info = gitInfo, let branch = info.branch {
                            HStack(spacing: 3) {
                                Image(systemName: "arrow.triangle.branch")
                                    .font(.system(size: 8))
                                Text(branch)
                                    .font(.system(size: 10))
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            .foregroundStyle(.secondary)
                        }
                    }
                }

                Spacer()

                Text(project.lastOpened, style: .relative)
                    .font(.system(size: 11))
                    .foregroundStyle(.quaternary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        )
        .onHover { hovering in
            // Hover effect handled by SwiftUI's button style
        }
    }

    private func displayPath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }
}
