import SwiftUI

/// Popover view that provides a tabbed inline text editor for Copilot CLI instruction files.
/// Each existing instruction file gets its own tab; missing files can be created from templates.
struct InstructionsView: View {
    let rootURL: URL
    @ObservedObject var filePreview: FilePreviewModel
    var onDismiss: () -> Void

    @State private var files: [InstructionFile] = []
    @State private var customFiles: [InstructionFile] = []
    @State private var selectedID: String? = nil
    /// In-memory content per file ID (source of truth for the editor).
    @State private var tabContents: [String: String] = [:]
    /// Last-saved (on-disk) content per file ID, used to detect dirty state.
    @State private var savedContents: [String: String] = [:]
    @State private var showSavedToast = false
    @State private var toastDismissTask: DispatchWorkItem?
    /// Non-nil when the last save attempt failed; drives the error toast.
    @State private var saveErrorMessage: String? = nil
    @State private var justCreated: String?

    /// All instruction files that already exist on disk (known + custom).
    private var existingFiles: [InstructionFile] {
        files.filter(\.exists) + customFiles
    }

    /// Known instruction files that have not yet been created.
    private var missingFiles: [InstructionFile] {
        files.filter { !$0.exists }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerView
            Divider()

            if existingFiles.isEmpty {
                emptyStateView
            } else {
                tabBarView
                Divider()
                editorView
            }

            if !missingFiles.isEmpty {
                Divider()
                createSection
            }

            Divider()
            footerView
        }
        .frame(width: 440)
        .frame(minHeight: 360, maxHeight: 560)
        .onAppear { refresh() }
        .overlay(alignment: .bottom) {
            if showSavedToast {
                savedToastView
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                    .padding(.bottom, 8)
            } else if let errMsg = saveErrorMessage {
                errorToastView(message: errMsg)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                    .padding(.bottom, 8)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showSavedToast)
        .animation(.easeInOut(duration: 0.2), value: saveErrorMessage)
    }

    // MARK: - Subviews

    private var headerView: some View {
        HStack {
            Image(systemName: "doc.text.fill")
                .foregroundStyle(.secondary)
            Text("Project Instructions")
                .font(.headline)
            Spacer()
            Button { onDismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    private var tabBarView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                ForEach(existingFiles) { file in
                    InstructionTabItem(
                        title: tabTitle(for: file),
                        isSelected: selectedID == file.id,
                        isDirty: isDirty(file.id)
                    ) {
                        selectTab(file)
                    }
                    .contextMenu {
                        Button {
                            if let url = file.url {
                                filePreview.select(url)
                                onDismiss()
                            }
                        } label: {
                            Label("View in Preview Panel", systemImage: "eye")
                        }
                        Button {
                            if let url = file.url {
                                ExternalEditorManager.openFile(url)
                            }
                        } label: {
                            if let editor = ExternalEditorManager.preferred {
                                Label("Open in \(editor.name)", systemImage: "square.and.pencil")
                            } else {
                                Label("Open in Default App", systemImage: "square.and.pencil")
                            }
                        }
                        Divider()
                        Button {
                            if let url = file.url {
                                NSWorkspace.shared.activateFileViewerSelecting([url])
                            }
                        } label: {
                            Label("Reveal in Finder", systemImage: "folder")
                        }
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
        .frame(height: 34)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.4))
    }

    private var editorView: some View {
        Group {
            if let id = selectedID {
                TextEditor(text: Binding(
                    get: { tabContents[id] ?? "" },
                    set: { tabContents[id] = $0 }
                ))
                .font(.system(size: 12, design: .monospaced))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Text("Select a file above to edit")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(height: 260)
    }

    private var emptyStateView: some View {
        VStack(spacing: 8) {
            Image(systemName: "doc.text.badge.plus")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            Text("No instruction files yet")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Create one below to configure agent behavior.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }

    private var createSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text("Create")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 2)

            ForEach(missingFiles) { file in
                HStack(spacing: 8) {
                    Image(systemName: "circle.dashed")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary.opacity(0.5))
                    Text(file.spec.relativePath)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    if justCreated == file.id {
                        Text("✓")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.green)
                            .transition(.opacity)
                    } else {
                        Button {
                            createFile(file)
                        } label: {
                            Text("Create")
                                .font(.system(size: 11))
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
            }
            .padding(.bottom, 4)
        }
    }

    private var footerView: some View {
        HStack(spacing: 8) {
            if let id = selectedID {
                if isDirty(id) {
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 6, height: 6)
                    Text("Unsaved changes")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                } else {
                    Text("⌘S to save")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
            } else {
                let knownExisting = files.filter(\.exists).count
                Circle()
                    .fill(knownExisting > 0 || !customFiles.isEmpty ? Color.green : Color.orange)
                    .frame(width: 6, height: 6)
                Text("\(knownExisting) of \(files.count) configured")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                if !customFiles.isEmpty {
                    Text("+ \(customFiles.count) custom")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer()
            if let id = selectedID {
                Button {
                    saveCurrentTab()
                } label: {
                    Text("Save")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .keyboardShortcut("s", modifiers: .command)
                .disabled(!isDirty(id))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private var savedToastView: some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 12))
                .foregroundStyle(.green)
            Text("Saved — agent will pick up changes on next turn")
                .font(.system(size: 12, weight: .medium))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .shadow(radius: 4)
    }

    private func errorToastView(message: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12))
                .foregroundStyle(.red)
            Text(message)
                .font(.system(size: 12, weight: .medium))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .shadow(radius: 4)
    }

    // MARK: - Helpers

    private func tabTitle(for file: InstructionFile) -> String {
        URL(fileURLWithPath: file.spec.relativePath).lastPathComponent
    }

    private func isDirty(_ id: String) -> Bool {
        guard let current = tabContents[id], let saved = savedContents[id] else { return false }
        return current != saved
    }

    private func selectTab(_ file: InstructionFile) {
        selectedID = file.id
        if tabContents[file.id] == nil {
            loadContent(for: file)
        }
    }

    private func loadContent(for file: InstructionFile) {
        guard let url = file.url else { return }
        if let data = FileManager.default.contents(atPath: url.path),
           let text = String(data: data, encoding: .utf8) {
            tabContents[file.id] = text
            savedContents[file.id] = text
        }
    }

    private func saveCurrentTab() {
        guard let id = selectedID,
              let content = tabContents[id],
              let file = existingFiles.first(where: { $0.id == id }),
              let url = file.url else { return }
        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
            savedContents[id] = content
            showSuccessToast()
        } catch {
            showErrorToast("Could not save: \(error.localizedDescription)")
        }
    }

    private func showSuccessToast() {
        toastDismissTask?.cancel()
        saveErrorMessage = nil
        showSavedToast = true
        let task = DispatchWorkItem { showSavedToast = false }
        toastDismissTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5, execute: task)
    }

    private func showErrorToast(_ message: String) {
        toastDismissTask?.cancel()
        showSavedToast = false
        saveErrorMessage = message
        let task = DispatchWorkItem { saveErrorMessage = nil }
        toastDismissTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0, execute: task)
    }

    private func createFile(_ file: InstructionFile) {
        guard InstructionsProvider.create(spec: file.spec, rootURL: rootURL) != nil else { return }
        justCreated = file.id
        refresh()
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            if justCreated == file.id { justCreated = nil }
        }
    }

    private func refresh() {
        files = InstructionsProvider.scan(rootURL: rootURL)
        customFiles = InstructionsProvider.scanCustomInstructions(rootURL: rootURL)

        // Auto-select the first existing file when none is selected (or selection is stale)
        let allExisting = files.filter(\.exists) + customFiles
        if selectedID == nil || !allExisting.contains(where: { $0.id == selectedID }) {
            if let first = allExisting.first {
                selectTab(first)
            }
        }
    }
}

// MARK: - Tab Item

/// A single tab button in the instruction editor tab bar.
private struct InstructionTabItem: View {
    let title: String
    let isSelected: Bool
    let isDirty: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 4) {
                if isDirty {
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 6, height: 6)
                }
                Text(title)
                    .font(.system(
                        size: 11,
                        weight: isSelected ? .semibold : .regular,
                        design: .monospaced
                    ))
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
            )
            .foregroundStyle(isSelected ? Color.primary : Color.secondary)
        }
        .buttonStyle(.plain)
    }
}
