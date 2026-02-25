import SwiftUI

/// Popover view that shows the status of Copilot CLI instruction files in the project.
/// Lets the user view existing files or create missing ones from templates.
struct InstructionsView: View {
    let rootURL: URL
    @ObservedObject var filePreview: FilePreviewModel
    var onDismiss: () -> Void

    @State private var files: [InstructionFile] = []
    @State private var customFiles: [InstructionFile] = []
    @State private var justCreated: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Image(systemName: "doc.text.fill")
                    .foregroundStyle(.secondary)
                Text("Project Instructions")
                    .font(.headline)
                Spacer()
                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)

            Divider()

            // Description
            Text("These files configure how the Copilot CLI behaves in this project.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

            ScrollView {
                VStack(spacing: 2) {
                    ForEach(files) { file in
                        InstructionFileRow(
                            file: file,
                            justCreated: justCreated == file.id,
                            onOpen: {
                                if let url = file.url {
                                    filePreview.select(url)
                                    onDismiss()
                                }
                            },
                            onCreate: {
                                if let url = InstructionsProvider.create(spec: file.spec, rootURL: rootURL) {
                                    justCreated = file.id
                                    filePreview.select(url)
                                    refresh()
                                    // Clear the "just created" indicator after a moment
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                                        if justCreated == file.id {
                                            justCreated = nil
                                        }
                                    }
                                }
                            },
                            onOpenInEditor: {
                                if let url = file.url {
                                    ExternalEditorManager.openFile(url)
                                }
                            }
                        )
                    }

                    // Custom instruction files
                    if !customFiles.isEmpty {
                        Divider()
                            .padding(.vertical, 6)
                            .padding(.horizontal, 12)

                        HStack {
                            Text("Custom Instructions")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 4)

                        ForEach(customFiles) { file in
                            InstructionFileRow(
                                file: file,
                                justCreated: false,
                                onOpen: {
                                    if let url = file.url {
                                        filePreview.select(url)
                                        onDismiss()
                                    }
                                },
                                onCreate: nil,
                                onOpenInEditor: {
                                    if let url = file.url {
                                        ExternalEditorManager.openFile(url)
                                    }
                                }
                            )
                        }
                    }
                }
                .padding(.vertical, 4)
            }

            Divider()

            // Summary footer
            HStack(spacing: 6) {
                let knownExisting = files.filter(\.exists).count
                let totalKnown = files.count
                Circle()
                    .fill(knownExisting > 0 || !customFiles.isEmpty ? Color.green : Color.orange)
                    .frame(width: 6, height: 6)
                Text("\(knownExisting) of \(totalKnown) configured")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                if !customFiles.isEmpty {
                    Text("+ \(customFiles.count) custom")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .frame(width: 360)
        .frame(maxHeight: 480)
        .onAppear { refresh() }
    }

    private func refresh() {
        files = InstructionsProvider.scan(rootURL: rootURL)
        customFiles = InstructionsProvider.scanCustomInstructions(rootURL: rootURL)
    }
}

/// A single row representing an instruction file — either existing or available to create.
private struct InstructionFileRow: View {
    let file: InstructionFile
    let justCreated: Bool
    let onOpen: () -> Void
    let onCreate: (() -> Void)?
    let onOpenInEditor: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            // Status indicator
            Image(systemName: file.exists ? "checkmark.circle.fill" : "circle.dashed")
                .font(.system(size: 14))
                .foregroundStyle(statusColor)

            VStack(alignment: .leading, spacing: 2) {
                Text(file.spec.relativePath)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(file.spec.description)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if file.exists, let size = file.fileSize {
                    Text(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            if justCreated {
                Text("Created!")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.green)
                    .transition(.opacity)
            } else if file.exists {
                Button {
                    onOpen()
                } label: {
                    Text("View")
                        .font(.system(size: 11))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            } else if let onCreate = onCreate {
                Button {
                    onCreate()
                } label: {
                    Text("Create")
                        .font(.system(size: 11))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture {
            if file.exists {
                onOpen()
            }
        }
        .contextMenu {
            if file.exists {
                Button {
                    onOpen()
                } label: {
                    Label("View in Preview", systemImage: "eye")
                }

                Button {
                    onOpenInEditor()
                } label: {
                    if let editor = ExternalEditorManager.preferred {
                        Label("Open in \(editor.name)", systemImage: "square.and.pencil")
                    } else {
                        Label("Open in Default App", systemImage: "square.and.pencil")
                    }
                }

                Divider()

                if let url = file.url {
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(file.spec.relativePath, forType: .string)
                    } label: {
                        Label("Copy Path", systemImage: "doc.on.doc")
                    }

                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    } label: {
                        Label("Reveal in Finder", systemImage: "folder")
                    }
                }
            }
        }
    }

    private var statusColor: Color {
        if justCreated { return .green }
        return file.exists ? .green : .secondary.opacity(0.4)
    }
}
