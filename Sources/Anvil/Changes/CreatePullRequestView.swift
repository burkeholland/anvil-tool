import SwiftUI

/// Sheet for creating a GitHub Pull Request via `gh pr create`.
struct CreatePullRequestView: View {
    @ObservedObject var workingDirectory: WorkingDirectoryModel
    @ObservedObject var changesModel: ChangesModel
    @ObservedObject var activityFeedModel: ActivityFeedModel
    var onDismiss: () -> Void

    @State private var prTitle: String = ""
    @State private var prBody: String = ""
    @State private var baseBranch: String = ""
    @State private var availableBranches: [String] = []
    @State private var isCreating = false
    @State private var createdPRURL: String?
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Image(systemName: "arrow.triangle.pull")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.purple)
                Text("Create Pull Request")
                    .font(.headline)
                Spacer()
                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()

            Divider()

            if let prURL = createdPRURL {
                // Success state
                VStack(spacing: 16) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(.green)
                    Text("Pull Request Created")
                        .font(.headline)
                    if let url = URL(string: prURL) {
                        Text(prURL)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .truncationMode(.middle)
                        Button {
                            NSWorkspace.shared.open(url)
                        } label: {
                            Label("Open in Browser", systemImage: "safari")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    Button("Done") { onDismiss() }
                        .keyboardShortcut(.defaultAction)
                }
                .frame(maxWidth: .infinity)
                .padding(32)
            } else {
                // Form state
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // Title
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Title")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.secondary)
                            TextField("Pull request title", text: $prTitle)
                                .textFieldStyle(.roundedBorder)
                        }

                        // Base branch
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Base Branch")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.secondary)
                            if availableBranches.isEmpty {
                                TextField("Base branch (e.g. main)", text: $baseBranch)
                                    .textFieldStyle(.roundedBorder)
                            } else {
                                Picker("Base Branch", selection: $baseBranch) {
                                    ForEach(availableBranches, id: \.self) { branch in
                                        Text(branch).tag(branch)
                                    }
                                }
                                .labelsHidden()
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }

                        // Body
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Description")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.secondary)
                            TextEditor(text: $prBody)
                                .font(.system(size: 12))
                                .frame(minHeight: 120)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 4)
                                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                                )
                        }

                        if let error = errorMessage {
                            Text(error)
                                .font(.system(size: 11))
                                .foregroundStyle(.red)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding()
                }

                Divider()

                // Action buttons
                HStack {
                    Spacer()
                    Button("Cancel") { onDismiss() }
                        .keyboardShortcut(.cancelAction)
                    Button {
                        createPR()
                    } label: {
                        HStack(spacing: 4) {
                            if isCreating {
                                ProgressView().controlSize(.mini)
                            }
                            Text("Create Pull Request")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(prTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                              || baseBranch.isEmpty || isCreating)
                    .keyboardShortcut(.defaultAction)
                }
                .padding()
            }
        }
        .frame(width: 480)
        .frame(minHeight: 360)
        .onAppear { loadInitialData() }
    }

    private func loadInitialData() {
        guard let url = workingDirectory.directoryURL else { return }
        // Capture model state on the main thread before dispatching to background.
        let changedFilesSnapshot = changesModel.changedFiles
        let recentCommitsSnapshot = changesModel.recentCommits
        let sessionStatsSnapshot = activityFeedModel.sessionStats
        DispatchQueue.global(qos: .userInitiated).async {
            let branches = PullRequestProvider.remoteBranches(in: url)
            let suggestedBase = suggestBaseBranch(from: branches)
            let suggestedTitle = suggestTitle(recentCommits: recentCommitsSnapshot)
            let suggestedBody = generateBody(
                baseBranch: suggestedBase,
                changedFiles: changedFilesSnapshot,
                recentCommits: recentCommitsSnapshot,
                sessionStats: sessionStatsSnapshot,
                in: url
            )
            DispatchQueue.main.async {
                availableBranches = branches
                if baseBranch.isEmpty { baseBranch = suggestedBase }
                if prTitle.isEmpty { prTitle = suggestedTitle }
                if prBody.isEmpty { prBody = suggestedBody }
            }
        }
    }

    private func suggestBaseBranch(from branches: [String]) -> String {
        let currentBranch = workingDirectory.gitBranch ?? ""
        let preferred = ["main", "master", "develop", "dev"]
        for candidate in preferred where candidate != currentBranch && branches.contains(candidate) {
            return candidate
        }
        return branches.first(where: { $0 != currentBranch }) ?? "main"
    }

    private func suggestTitle(recentCommits: [GitCommit]) -> String {
        if let firstCommit = recentCommits.first {
            return firstCommit.message.components(separatedBy: "\n").first ?? firstCommit.message
        }
        let branch = workingDirectory.gitBranch ?? ""
        let name = branch.components(separatedBy: "/").last ?? branch
        let readable = name
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
        return readable.prefix(1).uppercased() + readable.dropFirst()
    }

    private func generateBody(
        baseBranch: String,
        changedFiles: [ChangedFile],
        recentCommits: [GitCommit],
        sessionStats: ActivityFeedModel.SessionStats,
        in url: URL
    ) -> String {
        var sections: [String] = []

        // --- Commits on this branch ---
        let branchCommits = GitLogProvider.branchCommits(base: baseBranch, in: url)
        let commitsToShow = branchCommits.isEmpty ? Array(recentCommits.prefix(10)) : Array(branchCommits.prefix(10))
        if !commitsToShow.isEmpty {
            var lines = ["## Commits", ""]
            for commit in commitsToShow {
                let subject = commit.message.components(separatedBy: "\n").first ?? commit.message
                lines.append("- \(commit.shortSHA) \(subject)")
            }
            sections.append(lines.joined(separator: "\n"))
        }

        // --- File changes grouped by directory ---
        if !changedFiles.isEmpty {
            var lines = ["## Changed Files", ""]
            let grouped = Dictionary(grouping: changedFiles) { $0.directoryPath }
            for dir in grouped.keys.sorted() {
                let dirLabel = dir.isEmpty ? "(root)" : "\(dir)/"
                lines.append("**\(dirLabel)**")
                for file in (grouped[dir] ?? []).sorted(by: { $0.fileName < $1.fileName }) {
                    let adds = file.diff?.additionCount ?? 0
                    let dels = file.diff?.deletionCount ?? 0
                    let stats = (adds > 0 || dels > 0) ? " (+\(adds) -\(dels))" : ""
                    lines.append("  - \(file.fileName)\(stats)")
                }
            }
            sections.append(lines.joined(separator: "\n"))
        }

        // --- Session stats ---
        if sessionStats.isActive {
            var lines = ["## Session Stats", ""]
            lines.append("- Files touched: \(sessionStats.totalFilesTouched)")
            lines.append("- Lines added: \(sessionStats.totalAdditions)")
            lines.append("- Lines removed: \(sessionStats.totalDeletions)")
            sections.append(lines.joined(separator: "\n"))
        }

        return sections.joined(separator: "\n\n")
    }

    private func createPR() {
        guard let url = workingDirectory.directoryURL else { return }
        let title = prTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        isCreating = true
        errorMessage = nil
        DispatchQueue.global(qos: .userInitiated).async {
            let result = PullRequestProvider.create(title: title, body: prBody, base: baseBranch, in: url)
            DispatchQueue.main.async {
                isCreating = false
                if result.success {
                    createdPRURL = result.urlOrError
                    workingDirectory.refreshOpenPR()
                } else {
                    errorMessage = result.urlOrError ?? "Failed to create pull request"
                }
            }
        }
    }
}
