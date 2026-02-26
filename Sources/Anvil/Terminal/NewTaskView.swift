import AppKit
import SwiftUI

/// A sheet that orchestrates transitioning to a new agent task:
/// handles staged/uncommitted changes, switches to the default branch,
/// creates a new feature branch, sends `/compact` to Copilot, and
/// focuses the terminal for the next prompt.
struct NewTaskView: View {
    let rootURL: URL
    let changedFiles: [ChangedFile]
    let stagedFiles: [ChangedFile]
    let generatedCommitMessage: String
    let lastPrompt: String?

    @EnvironmentObject var terminalProxy: TerminalInputProxy

    /// Called with the toast summary string on success.
    var onComplete: (String) -> Void
    var onDismiss: () -> Void

    enum ChangeHandling: String, CaseIterable {
        case commit = "Commit staged changes"
        case stash  = "Stash all changes"
    }

    @State private var branchName: String = ""
    @State private var changeHandling: ChangeHandling = .commit
    @State private var isRunning = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Title bar
            HStack {
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.accentColor)
                Text("New Task")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .keyboardShortcut(.escape, modifiers: [])
                .disabled(isRunning)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            VStack(alignment: .leading, spacing: 16) {
                // Changed-files handling
                if !changedFiles.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Current Changes (\(changedFiles.count) file\(changedFiles.count == 1 ? "" : "s"))")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)

                        Picker("", selection: $changeHandling) {
                            ForEach(ChangeHandling.allCases, id: \.self) { option in
                                Text(option.rawValue).tag(option)
                            }
                        }
                        .pickerStyle(.radioGroup)
                        .labelsHidden()

                        if changeHandling == .commit {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Commit message")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                Text(generatedCommitMessage.isEmpty ? "(no staged changes)" : generatedCommitMessage)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(generatedCommitMessage.isEmpty ? .tertiary : .primary)
                                    .lineLimit(3)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(8)
                                    .background(Color(nsColor: .textBackgroundColor))
                                    .clipShape(RoundedRectangle(cornerRadius: 5))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 5)
                                            .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5)
                                    )
                            }
                        }
                    }
                }

                // Branch name
                VStack(alignment: .leading, spacing: 6) {
                    Text("New Branch Name")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)

                    TextField("feature/…", text: $branchName)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12, design: .monospaced))
                        .onSubmit {
                            if canStart { startTask() }
                        }
                }

                // Error
                if let error = errorMessage {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.red)
                        Text(error)
                            .font(.system(size: 11))
                            .foregroundStyle(.red)
                            .lineLimit(3)
                    }
                    .padding(8)
                    .background(Color.red.opacity(0.07), in: RoundedRectangle(cornerRadius: 6))
                }
            }
            .padding(16)

            Divider()

            // Footer buttons
            HStack {
                Spacer()
                Button("Cancel") {
                    onDismiss()
                }
                .keyboardShortcut(.cancelAction)
                .disabled(isRunning)

                Button {
                    startTask()
                } label: {
                    if isRunning {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text("Starting…")
                        }
                    } else {
                        Text("Start New Task")
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canStart || isRunning)
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .frame(width: 420)
        .onAppear {
            branchName = Self.suggestBranchName(lastPrompt: lastPrompt, clipboard: clipboardString)
        }
    }

    // MARK: - Helpers

    private var canStart: Bool {
        !branchName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var clipboardString: String? {
        NSPasteboard.general.string(forType: .string)
    }

    private func startTask() {
        guard canStart else { return }
        let name = branchName.trimmingCharacters(in: .whitespacesAndNewlines)
        let oldBranch = Self.currentBranch(in: rootURL) ?? "unknown"
        isRunning = true
        errorMessage = nil

        let handling = changeHandling
        let hasChanges = !changedFiles.isEmpty
        let commitMsg = generatedCommitMessage
        let files = changedFiles

        DispatchQueue.global(qos: .userInitiated).async {
            var committedFileCount = 0

            // Step 1: Handle current changes
            if hasChanges {
                if handling == .commit {
                    let msg = commitMsg.isEmpty
                        ? Self.fallbackCommitMessage(files: files)
                        : commitMsg
                    let result = Self.commitAll(message: msg, in: rootURL)
                    if !result.success {
                        DispatchQueue.main.async {
                            self.isRunning = false
                            self.errorMessage = result.error ?? "Commit failed"
                        }
                        return
                    }
                    committedFileCount = files.count
                } else {
                    let result = GitStashProvider.push(
                        message: "WIP: new task stash",
                        includeUntracked: true,
                        in: rootURL
                    )
                    if !result.success {
                        DispatchQueue.main.async {
                            self.isRunning = false
                            self.errorMessage = result.error ?? "Stash failed"
                        }
                        return
                    }
                }
            }

            // Step 2: Fetch (best-effort — ignore errors if no remote)
            _ = GitRemoteProvider.fetch(in: rootURL)

            // Step 3: Detect and checkout default branch
            let defaultBranch = Self.defaultBranch(in: rootURL)
            let switchResult = GitBranchProvider.switchBranch(to: defaultBranch, in: rootURL)
            if !switchResult.success {
                DispatchQueue.main.async {
                    self.isRunning = false
                    self.errorMessage = switchResult.error ?? "Failed to switch to \(defaultBranch)"
                }
                return
            }

            // Step 4: Create new feature branch
            let createResult = GitBranchProvider.createBranch(named: name, in: rootURL)
            if !createResult.success {
                DispatchQueue.main.async {
                    self.isRunning = false
                    self.errorMessage = createResult.error ?? "Failed to create branch '\(name)'"
                }
                return
            }

            // Step 5: Notify main thread and focus terminal
            let summary: String
            if hasChanges {
                if handling == .commit {
                    let fileWord = committedFileCount == 1 ? "file" : "files"
                    summary = "Committed \(committedFileCount) \(fileWord) on \(oldBranch) → new branch \(name)"
                } else {
                    summary = "Stashed changes from \(oldBranch) → new branch \(name)"
                }
            } else {
                summary = "Switched from \(oldBranch) → new branch \(name)"
            }

            DispatchQueue.main.async {
                self.isRunning = false
                // Send /compact to reset Copilot session context
                self.terminalProxy.send("/compact\n")
                // Focus terminal
                if let tv = self.terminalProxy.terminalView {
                    tv.window?.makeFirstResponder(tv)
                }
                self.onComplete(summary)
            }
        }
    }

    // MARK: - Git Helpers

    /// Stages all changes and commits with the given message.
    private static func commitAll(message: String, in directory: URL) -> (success: Bool, error: String?) {
        // Stage all tracked + untracked changes
        let addResult = runGit(args: ["add", "-A"], at: directory)
        if !addResult.success { return addResult }
        return runGit(args: ["commit", "-m", message], at: directory)
    }

    /// Returns the default branch for the repo (tries remote HEAD, then falls back to main/master).
    static func defaultBranch(in directory: URL) -> String {
        // Try remote HEAD ref: "refs/remotes/origin/main" → "main"
        if let output = runGitOutput(args: ["symbolic-ref", "refs/remotes/origin/HEAD"], at: directory),
           let last = output.components(separatedBy: "/").last, !last.isEmpty {
            return last
        }
        // Verify 'main' exists
        if runGitOutput(args: ["rev-parse", "--verify", "main"], at: directory) != nil {
            return "main"
        }
        return "master"
    }

    static func currentBranch(in directory: URL) -> String? {
        runGitOutput(args: ["rev-parse", "--abbrev-ref", "HEAD"], at: directory)
    }

    /// Derives a smart branch name from clipboard text or the last prompt.
    static func suggestBranchName(lastPrompt: String?, clipboard: String?) -> String {
        if let clip = clipboard?.trimmingCharacters(in: .whitespacesAndNewlines),
           !clip.isEmpty, clip.count < 100, !clip.contains("\n") {
            let slug = slugify(clip)
            if slug.count >= 3 {
                return "feature/\(String(slug.prefix(50)))"
            }
        }
        if let prompt = lastPrompt?.trimmingCharacters(in: .whitespacesAndNewlines), !prompt.isEmpty {
            let line = prompt.components(separatedBy: "\n").first ?? prompt
            let slug = slugify(line)
            if slug.count >= 3 {
                return "feature/\(String(slug.prefix(50)))"
            }
        }
        return BranchGuardBanner.autoBranchName()
    }

    /// Converts arbitrary text into a git-safe branch name slug.
    static func slugify(_ text: String) -> String {
        var result = ""
        var lastWasSeparator = true // start true to strip leading dashes
        for char in text.lowercased() {
            if char.isLetter || char.isNumber {
                result.append(char)
                lastWasSeparator = false
            } else if !lastWasSeparator && !result.isEmpty {
                result.append("-")
                lastWasSeparator = true
            }
        }
        // Strip trailing dash
        while result.last == "-" { result.removeLast() }
        return result
    }

    private static func fallbackCommitMessage(files: [ChangedFile]) -> String {
        let n = files.count
        return "chore: task commit — \(n) file\(n == 1 ? "" : "s") changed"
    }

    private static func runGitOutput(args: [String], at directory: URL) -> String? {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = args
        process.currentDirectoryURL = directory
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let outData = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        let output = String(data: outData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return output?.isEmpty == false ? output : nil
    }

    private static func runGit(args: [String], at directory: URL) -> (success: Bool, error: String?) {
        let process = Process()
        let errPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = args
        process.currentDirectoryURL = directory
        process.standardOutput = FileHandle.nullDevice
        process.standardError = errPipe
        do { try process.run() } catch { return (false, error.localizedDescription) }
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        if process.terminationStatus == 0 { return (true, nil) }
        let msg = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (false, msg)
    }
}
