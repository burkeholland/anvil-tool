import SwiftUI
import AppKit

/// Sheet for cloning a git repository by URL.
struct CloneRepositoryView: View {
    var onCloned: (URL) -> Void
    var onDismiss: () -> Void

    @StateObject private var model = CloneRepositoryModel()
    @FocusState private var isURLFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Label("Clone Repository", systemImage: "arrow.down.circle")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }

            // URL field
            VStack(alignment: .leading, spacing: 4) {
                Text("Repository URL")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)

                TextField("https://github.com/owner/repo.git", text: $model.repoURL)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 13, design: .monospaced))
                    .focused($isURLFocused)
                    .onSubmit { if model.canClone { clone() } }
                    .disabled(model.isCloning)
            }

            // Destination
            VStack(alignment: .leading, spacing: 4) {
                Text("Clone to")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    Text(model.displayDestination)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.head)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color(nsColor: .controlBackgroundColor))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5)
                        )

                    Button("Choose…") {
                        browseDestination()
                    }
                    .disabled(model.isCloning)
                }

                if !model.repoName.isEmpty {
                    Text("Will create: \(model.repoName)/")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }

            // Progress
            if model.isCloning {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text(model.progressMessage)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            // Error
            if let error = model.errorMessage {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.yellow)
                    Text(error)
                        .font(.system(size: 11))
                        .foregroundStyle(.red)
                        .lineLimit(3)
                }
            }

            Spacer().frame(height: 4)

            // Actions
            HStack {
                Spacer()

                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Clone") {
                    clone()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!model.canClone)
            }
        }
        .padding(20)
        .frame(width: 480)
        .interactiveDismissDisabled(model.isCloning)
        .onDisappear {
            model.cancel()
        }
        .onAppear {
            isURLFocused = true
            // Try to paste from clipboard if it looks like a git URL
            if let clip = NSPasteboard.general.string(forType: .string),
               model.repoURL.isEmpty,
               CloneRepositoryModel.looksLikeRepoURL(clip) {
                model.repoURL = clip.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
    }

    private func clone() {
        model.clone { clonedURL in
            onCloned(clonedURL)
            onDismiss()
        }
    }

    private func dismiss() {
        model.cancel()
        onDismiss()
    }

    private func browseDestination() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "Choose where to clone the repository"
        panel.directoryURL = URL(fileURLWithPath: model.destinationPath)
        if panel.runModal() == .OK, let url = panel.url {
            model.destinationPath = url.path
        }
    }
}

// MARK: - Model

final class CloneRepositoryModel: ObservableObject {
    @Published var repoURL: String = ""
    @Published var destinationPath: String = CloneRepositoryModel.defaultDestination
    @Published private(set) var isCloning = false
    @Published private(set) var progressMessage = "Cloning…"
    @Published private(set) var errorMessage: String?

    private var cloneProcess: Process?

    var canClone: Bool {
        !isCloning && !repoName.isEmpty && !repoURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var repoName: String {
        Self.extractRepoName(from: repoURL)
    }

    var displayDestination: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if destinationPath.hasPrefix(home) {
            return "~" + destinationPath.dropFirst(home.count)
        }
        return destinationPath
    }

    func clone(completion: @escaping (URL) -> Void) {
        let url = repoURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty else { return }

        let name = Self.extractRepoName(from: url)
        let destDir = URL(fileURLWithPath: destinationPath)
        let targetDir = destDir.appendingPathComponent(name)

        // Check if directory already exists
        if FileManager.default.fileExists(atPath: targetDir.path) {
            errorMessage = "Directory \"\(name)\" already exists at this location."
            return
        }

        isCloning = true
        errorMessage = nil
        progressMessage = "Cloning \(name)…"

        let process = Process()
        let errPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["clone", "--progress", url, targetDir.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = errPipe
        process.currentDirectoryURL = destDir

        cloneProcess = process

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                try process.run()
            } catch {
                DispatchQueue.main.async {
                    self?.isCloning = false
                    self?.errorMessage = "Failed to start git: \(error.localizedDescription)"
                }
                return
            }

            // Read stderr for progress/errors
            let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let errString = String(data: errData, encoding: .utf8) ?? ""

            DispatchQueue.main.async {
                guard let self = self else { return }
                self.cloneProcess = nil
                self.isCloning = false

                if process.terminationStatus == 0 {
                    completion(targetDir)
                } else {
                    // Extract a useful error message from git stderr
                    let msg = errString
                        .components(separatedBy: "\n")
                        .filter { $0.lowercased().contains("fatal") || $0.lowercased().contains("error") }
                        .first ?? errString.trimmingCharacters(in: .whitespacesAndNewlines)
                    self.errorMessage = msg.isEmpty ? "Clone failed (exit code \(process.terminationStatus))" : msg
                }
            }
        }
    }

    func cancel() {
        cloneProcess?.terminate()
        cloneProcess = nil
        isCloning = false
        progressMessage = ""
    }

    // MARK: - Helpers

    static func extractRepoName(from urlString: String) -> String {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        // Handle SSH format: git@github.com:owner/repo.git
        if trimmed.contains(":") && !trimmed.contains("://") {
            let afterColon = trimmed.components(separatedBy: ":").last ?? ""
            return cleanRepoName(afterColon)
        }

        // Handle HTTPS: https://github.com/owner/repo.git
        if let url = URL(string: trimmed) {
            return cleanRepoName(url.lastPathComponent)
        }

        return cleanRepoName(trimmed)
    }

    private static func cleanRepoName(_ component: String) -> String {
        var name = component
            .components(separatedBy: "/").last ?? component
        if name.hasSuffix(".git") {
            name = String(name.dropLast(4))
        }
        return name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func looksLikeRepoURL(_ string: String) -> Bool {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.contains("\n") { return false }
        // HTTPS git URLs
        if trimmed.hasPrefix("https://") && trimmed.contains(".git") { return true }
        if trimmed.hasPrefix("https://github.com/") { return true }
        if trimmed.hasPrefix("https://gitlab.com/") { return true }
        if trimmed.hasPrefix("https://bitbucket.org/") { return true }
        // SSH URLs
        if trimmed.hasPrefix("git@") && trimmed.contains(":") { return true }
        return false
    }

    static var defaultDestination: String {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let developer = home.appendingPathComponent("Developer")
        if FileManager.default.fileExists(atPath: developer.path) {
            return developer.path
        }
        return home.path
    }
}
