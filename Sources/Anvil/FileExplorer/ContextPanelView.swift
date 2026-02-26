import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// A collapsible panel shown at the bottom of the Files sidebar tab.
/// Displays files that have been pinned to the Copilot CLI agent context via `/context add`,
/// and supports adding files by drag-and-drop from the file tree.
struct ContextPanelView: View {
    @ObservedObject var contextStore: ContextStore
    let rootURL: URL
    @EnvironmentObject var terminalProxy: TerminalInputProxy
    @AppStorage("contextPanelExpanded") private var isExpanded = true

    @State private var isDropTargeted = false

    var body: some View {
        VStack(spacing: 0) {
            Divider()

            // Header row
            HStack(spacing: 5) {
                Image(systemName: "paperclip")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                Text("CONTEXT")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)

                if !contextStore.pinnedPaths.isEmpty {
                    Text("\(contextStore.pinnedPaths.count)")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color.accentColor))
                }

                Spacer()

                Button {
                    isExpanded.toggle()
                } label: {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
            .contentShape(Rectangle())
            .onTapGesture { isExpanded.toggle() }

            if isExpanded {
                if contextStore.pinnedPaths.isEmpty {
                    HStack {
                        Text("Drag files here to add to context")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                        Spacer()
                    }
                    .background(isDropTargeted ? Color.accentColor.opacity(0.06) : Color.clear)
                    .overlay(
                        isDropTargeted
                            ? RoundedRectangle(cornerRadius: 4)
                                .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                                .padding(.horizontal, 4).padding(.vertical, 2)
                            : nil
                    )
                    .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
                        handleDrop(providers)
                    }
                } else {
                    VStack(spacing: 0) {
                        ForEach(contextStore.pinnedPaths, id: \.self) { relativePath in
                            ContextFileRow(relativePath: relativePath) {
                                terminalProxy.removeFromContext(relativePath: relativePath)
                            }
                        }
                    }
                    .background(isDropTargeted ? Color.accentColor.opacity(0.04) : Color.clear)
                    .overlay(
                        isDropTargeted
                            ? RoundedRectangle(cornerRadius: 4)
                                .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                                .padding(.horizontal, 4).padding(.vertical, 2)
                            : nil
                    )
                    .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
                        handleDrop(providers)
                    }
                }
            }
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        var handled = false
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                    let url: URL?
                    if let data = item as? Data {
                        url = URL(dataRepresentation: data, relativeTo: nil)
                    } else if let existingURL = item as? URL {
                        url = existingURL
                    } else {
                        url = nil
                    }
                    guard let fileURL = url else { return }
                    var isDir: ObjCBool = false
                    guard FileManager.default.fileExists(atPath: fileURL.path, isDirectory: &isDir),
                          !isDir.boolValue else { return }
                    let relPath = TerminalDropHelper.projectRelativePath(for: fileURL, rootURL: rootURL)
                    DispatchQueue.main.async {
                        terminalProxy.addToContext(relativePath: relPath)
                    }
                }
                handled = true
            }
        }
        return handled
    }
}

/// A single row in the context panel, showing the file name and a hover-reveal remove button.
struct ContextFileRow: View {
    let relativePath: String
    let onRemove: () -> Void

    @State private var isHovering = false

    var fileName: String {
        (relativePath as NSString).lastPathComponent
    }

    var dirPath: String {
        let dir = (relativePath as NSString).deletingLastPathComponent
        return dir.isEmpty || dir == "." ? "" : dir
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "doc")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 0) {
                Text(fileName)
                    .font(.system(size: 11))
                    .lineLimit(1)
                    .truncationMode(.middle)

                if !dirPath.isEmpty {
                    Text(dirPath)
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
            }

            Spacer()

            if isHovering {
                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 16, height: 16)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Remove from context")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
    }
}
