import SwiftUI
import AppKit

/// Displays a live timeline of file changes and git commits detected while the agent works.
struct ActivityFeedView: View {
    @ObservedObject var model: ActivityFeedModel
    @ObservedObject var filePreview: FilePreviewModel

    var body: some View {
        if model.groups.isEmpty {
            VStack(spacing: 12) {
                Spacer()
                Image(systemName: "clock")
                    .font(.system(size: 28))
                    .foregroundStyle(.tertiary)
                Text("No activity yet")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("File changes will appear here\nas the agent works")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                Spacer()
            }
            .frame(maxWidth: .infinity)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                // Header with count and clear button
                HStack {
                    Text("\(model.events.count) event\(model.events.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        model.clear()
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                    .help("Clear activity")
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))

                Divider()

                // Timeline
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(model.groups) { group in
                                ActivityGroupView(
                                    group: group,
                                    filePreview: filePreview
                                )
                            }
                        }
                    }
                    .onChange(of: model.groups.count) { _, _ in
                        // Auto-scroll to the latest group
                        if let last = model.groups.last {
                            withAnimation(.easeOut(duration: 0.2)) {
                                proxy.scrollTo(last.id, anchor: .bottom)
                            }
                        }
                    }
                }
            }
        }
    }
}

struct ActivityGroupView: View {
    let group: ActivityGroup
    @ObservedObject var filePreview: FilePreviewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Timestamp header
            HStack(spacing: 6) {
                Circle()
                    .fill(Color.secondary.opacity(0.3))
                    .frame(width: 6, height: 6)

                Text(group.timestamp, style: .time)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.tertiary)

                if group.events.count > 1 {
                    Text("(\(group.events.count) changes)")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 4)

            // Events in this group
            ForEach(group.events) { event in
                ActivityEventRow(event: event, filePreview: filePreview)
            }
        }
        .id(group.id)
    }
}

struct ActivityEventRow: View {
    let event: ActivityEvent
    @ObservedObject var filePreview: FilePreviewModel
    @EnvironmentObject var terminalProxy: TerminalInputProxy

    var body: some View {
        HStack(spacing: 6) {
            // Timeline line
            Rectangle()
                .fill(Color.secondary.opacity(0.15))
                .frame(width: 1)
                .padding(.leading, 14)

            Image(systemName: event.icon)
                .font(.system(size: 11))
                .foregroundStyle(iconColor)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 1) {
                Text(event.fileName.isEmpty ? event.label : event.fileName)
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .truncationMode(.middle)

                if !event.directoryPath.isEmpty {
                    Text(event.directoryPath)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.head)
                }

                if case .gitCommit(let msg, let sha) = event.kind {
                    HStack(spacing: 4) {
                        Text(sha)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.purple.opacity(0.8))
                        Text(msg)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }

            Spacer()
        }
        .padding(.vertical, 3)
        .padding(.trailing, 8)
        .contentShape(Rectangle())
        .onTapGesture {
            if let url = event.fileURL {
                filePreview.select(url)
            }
        }
        .background(
            filePreview.selectedURL == event.fileURL && event.fileURL != nil
                ? RoundedRectangle(cornerRadius: 4).fill(Color.accentColor.opacity(0.1))
                : nil
        )
        .contextMenu {
            if let url = event.fileURL {
                if !event.path.isEmpty {
                    Button {
                        terminalProxy.mentionFile(relativePath: event.path)
                    } label: {
                        Label("Mention in Terminal", systemImage: "terminal")
                    }

                    Divider()

                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(event.path, forType: .string)
                    } label: {
                        Label("Copy Relative Path", systemImage: "doc.on.doc")
                    }
                }

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(url.path, forType: .string)
                } label: {
                    Label("Copy Absolute Path", systemImage: "doc.on.doc.fill")
                }

                Divider()

                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                } label: {
                    Label("Reveal in Finder", systemImage: "folder")
                }
            }
        }
    }

    private var iconColor: Color {
        switch event.kind {
        case .fileCreated:  return .green
        case .fileModified: return .orange
        case .fileDeleted:  return .red
        case .fileRenamed:  return .blue
        case .gitCommit:    return .purple
        }
    }
}
