import SwiftUI

/// A popover for quickly switching between recent projects from the toolbar.
struct ProjectSwitcherView: View {
    @ObservedObject var recentProjects: RecentProjectsModel
    var currentPath: String?
    var onSelect: (URL) -> Void
    var onBrowse: () -> Void
    var onClone: () -> Void
    var onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Label("Switch Project", systemImage: "folder.badge.gearshape")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider()

            if recentProjects.recentProjects.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Text("No recent projects")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
                .frame(height: 80)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(recentProjects.recentProjects) { project in
                            let isCurrent = project.path == currentPath
                            ProjectSwitcherRow(
                                project: project,
                                gitInfo: recentProjects.gitInfo[project.path],
                                isCurrent: isCurrent
                            ) {
                                if !isCurrent {
                                    onSelect(project.url)
                                }
                                onDismiss()
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(maxHeight: 320)
            }

            Divider()

            VStack(spacing: 0) {
                Button {
                    onBrowse()
                    onDismiss()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "folder.badge.plus")
                            .font(.system(size: 11))
                        Text("Open Other…")
                            .font(.system(size: 12))
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Button {
                    onClone()
                    onDismiss()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.down.circle")
                            .font(.system(size: 11))
                        Text("Clone Repository…")
                            .font(.system(size: 12))
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(width: 300)
        .onAppear {
            recentProjects.refreshGitInfo()
        }
    }
}

private struct ProjectSwitcherRow: View {
    let project: RecentProjectsModel.RecentProject
    var gitInfo: GitProjectInfo?
    let isCurrent: Bool
    let onSelect: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 8) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(isCurrent ? Color.accentColor : .secondary)

                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 5) {
                        Text(project.name)
                            .font(.system(size: 12, weight: isCurrent ? .semibold : .regular))
                            .lineLimit(1)

                        if isCurrent {
                            Text("current")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Capsule().fill(Color.accentColor.opacity(0.8)))
                        }

                        if let info = gitInfo, info.isDirty {
                            Circle()
                                .fill(.orange)
                                .frame(width: 5, height: 5)
                                .help("\(info.changedFileCount) uncommitted change\(info.changedFileCount == 1 ? "" : "s")")
                        }
                    }

                    HStack(spacing: 4) {
                        if let info = gitInfo, let branch = info.branch {
                            HStack(spacing: 2) {
                                Image(systemName: "arrow.triangle.branch")
                                    .font(.system(size: 8))
                                Text(branch)
                                    .font(.system(size: 10))
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            .foregroundStyle(.secondary)
                        }

                        if let info = gitInfo, info.isDirty {
                            Text("\(info.changedFileCount) changed")
                                .font(.system(size: 10))
                                .foregroundStyle(.orange.opacity(0.8))
                        }
                    }
                }

                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .background(
                isHovering && !isCurrent
                    ? RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(0.05))
                    : nil
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .disabled(!project.exists)
        .opacity(project.exists ? 1 : 0.4)
    }
}
