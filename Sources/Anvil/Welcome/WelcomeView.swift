import SwiftUI

/// Shown when no working directory is selected. Displays recent projects
/// and an option to open a new directory.
struct WelcomeView: View {
    @ObservedObject var recentProjects: RecentProjectsModel
    var onOpen: (URL) -> Void
    var onBrowse: () -> Void

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
                            RecentProjectRow(project: project) {
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

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

struct RecentProjectRow: View {
    let project: RecentProjectsModel.RecentProject
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 10) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.accentColor)

                VStack(alignment: .leading, spacing: 2) {
                    Text(project.name)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Text(displayPath(project.path))
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.head)
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
