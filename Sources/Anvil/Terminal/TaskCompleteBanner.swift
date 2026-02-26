import SwiftUI

/// A floating banner that appears when the Copilot agent goes idle after making
/// changes, providing a summary and quick actions for the review workflow.
struct TaskCompleteBanner: View {
    let changedFileCount: Int
    let totalAdditions: Int
    let totalDeletions: Int
    let buildStatus: BuildVerifier.Status
    /// Number of changed files that match sensitive patterns (CI/CD, secrets, etc.).
    var sensitiveFileCount: Int = 0
    /// Structured diagnostics parsed from the failed build output.
    var buildDiagnostics: [BuildDiagnostic] = []
    /// Called when the user taps a diagnostic row to navigate to the error location.
    var onOpenDiagnostic: ((BuildDiagnostic) -> Void)?
    /// Test suite status reported by TestRunner.
    var testStatus: TestRunner.Status = .idle
    /// Called when the user taps "Run Tests" to trigger a manual re-run.
    var onRunTests: (() -> Void)?
    /// Called when the user taps "Fix with Agent" after a test failure.
    /// The argument is the raw test output to send to the agent.
    var onFixTestFailure: ((String) -> Void)?
    /// Current git branch name, used to decide whether to show the "Create PR" suggestion.
    var gitBranch: String? = nil
    /// Number of local commits ahead of upstream. Used together with gitBranch for the PR suggestion.
    var aheadCount: Int = 0
    /// True when an open pull request already exists for the branch (suppresses the Create PR suggestion).
    var hasOpenPR: Bool = false
    /// Called when the user taps "Create PR". When nil, the Create PR button is not shown.
    var onCreatePR: (() -> Void)? = nil
    var onReviewAll: () -> Void
    var onStageAllAndCommit: () -> Void
    var onNewTask: () -> Void
    var onDismiss: () -> Void

    /// Changed file entries to show in the collapsible file list.
    var changedFiles: [ChangedFile] = []
    /// Called when the user taps a file row to navigate to that file's diff.
    var onOpenFileDiff: ((ChangedFile) -> Void)?

    @State private var showBuildOutput = false
    @State private var showTestOutput = false
    @State private var showChangedFiles = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.green)

                Text("Agent idle")
                    .font(.system(size: 12, weight: .semibold))

                if changedFileCount > 0 {
                    Text("•")
                        .foregroundStyle(.tertiary)
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showChangedFiles.toggle()
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text("\(changedFileCount) file\(changedFileCount == 1 ? "" : "s") changed")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                            Image(systemName: showChangedFiles ? "chevron.up" : "chevron.down")
                                .font(.system(size: 9))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                }

                if totalAdditions > 0 || totalDeletions > 0 {
                    HStack(spacing: 4) {
                        if totalAdditions > 0 {
                            Text("+\(totalAdditions)")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.green)
                        }
                        if totalDeletions > 0 {
                            Text("-\(totalDeletions)")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.red)
                        }
                    }
                }

                // Build status badge
                buildStatusBadge

                // Test status badge
                testStatusBadge

                // Sensitive file warning badge
                if sensitiveFileCount > 0 {
                    HStack(spacing: 4) {
                        Text("⚠️")
                            .font(.system(size: 11))
                        Text("\(sensitiveFileCount) sensitive file\(sensitiveFileCount == 1 ? "" : "s")")
                            .font(.system(size: 11))
                            .foregroundStyle(.orange)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
                    .help("One or more changed files require careful review (CI/CD, secrets, dependencies, etc.)")
                }

                Spacer()

                if onRunTests != nil {
                    switch testStatus {
                    case .running:
                        EmptyView()
                    default:
                        BannerPillButton(
                            icon: "play.circle",
                            label: "Run Tests",
                            style: .secondary
                        ) {
                            onRunTests?()
                        }
                    }
                }

                if changedFileCount > 0 {
                    BannerPillButton(
                        icon: "doc.text.magnifyingglass",
                        label: "Review Changes",
                        style: .prominent
                    ) {
                        onReviewAll()
                    }

                    BannerPillButton(
                        icon: "checkmark.circle",
                        label: "Stage All & Commit",
                        style: .secondary
                    ) {
                        onStageAllAndCommit()
                    }
                }

                if shouldShowCreatePR {
                    BannerPillButton(
                        icon: "arrow.triangle.pull",
                        label: "Create PR",
                        style: .secondary
                    ) {
                        onCreatePR?()
                    }
                }

                BannerPillButton(
                    icon: "plus.circle",
                    label: "New Task",
                    style: .secondary
                ) {
                    onNewTask()
                }

                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            // Expandable build error panel
            if showBuildOutput, case .failed(let output) = buildStatus {
                Divider()
                if buildDiagnostics.isEmpty {
                    // Fallback: raw output when no diagnostics could be parsed
                    ScrollView {
                        Text(output)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .textSelection(.enabled)
                    }
                    .frame(maxHeight: 180)
                    .background(Color(nsColor: .textBackgroundColor).opacity(0.6))
                } else {
                    // Structured diagnostics list with click-to-navigate
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(buildDiagnostics) { diagnostic in
                                DiagnosticRow(diagnostic: diagnostic) {
                                    onOpenDiagnostic?(diagnostic)
                                }
                                Divider().padding(.leading, 32)
                            }
                        }
                    }
                    .frame(maxHeight: 180)
                    .background(Color(nsColor: .textBackgroundColor).opacity(0.6))
                }
            }

            // Expandable test failure panel
            if showTestOutput, case .failed(let failedTests, let output) = testStatus {
                Divider()
                VStack(spacing: 0) {
                    if failedTests.isEmpty {
                        ScrollView {
                            Text(output)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.primary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(10)
                                .textSelection(.enabled)
                        }
                        .frame(maxHeight: 180)
                    } else {
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 0) {
                                ForEach(failedTests, id: \.self) { testName in
                                    HStack(spacing: 8) {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.system(size: 11))
                                            .foregroundStyle(.red)
                                            .frame(width: 14)
                                        Text(testName)
                                            .font(.system(size: 11, design: .monospaced))
                                            .foregroundStyle(.primary)
                                            .lineLimit(1)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    Divider().padding(.leading, 32)
                                }
                            }
                        }
                        .frame(maxHeight: 180)
                    }

                    if let handler = onFixTestFailure {
                        Divider()
                        HStack {
                            Spacer()
                            Button {
                                handler(output)
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "ant.circle")
                                        .font(.system(size: 10))
                                    Text("Fix with Agent")
                                        .font(.system(size: 12))
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.red)
                            .controlSize(.small)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                        }
                        .background(Color(nsColor: .textBackgroundColor).opacity(0.6))
                    }
                }
                .background(Color(nsColor: .textBackgroundColor).opacity(0.6))
            }
            // Expandable changed-files panel
            if showChangedFiles && !changedFiles.isEmpty {
                Divider()
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(ReviewPriorityScorer.sorted(changedFiles)) { file in
                            BannerFileRow(file: file) {
                                onOpenFileDiff?(file)
                            }
                            Divider().padding(.leading, 32)
                        }
                    }
                }
                .frame(maxHeight: 180)
                .background(Color(nsColor: .textBackgroundColor).opacity(0.6))
            }
        }
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) { Divider() }
    }

    /// Branch names that are considered "default" and should not trigger the Create PR suggestion.
    private static let defaultBranchNames: Set<String> = ["main", "master", "develop"]

    /// True when the "Create PR" pill should be shown: non-default feature branch with
    /// unpushed commits and no PR already open.
    private var shouldShowCreatePR: Bool {
        guard let branch = gitBranch, onCreatePR != nil else { return false }
        return !Self.defaultBranchNames.contains(branch) && aheadCount > 0 && !hasOpenPR
    }

    @ViewBuilder
    private var buildStatusBadge: some View {
        switch buildStatus {
        case .idle:
            EmptyView()
        case .running:
            HStack(spacing: 4) {
                ProgressView()
                    .controlSize(.mini)
                    .scaleEffect(0.7)
                Text("Building…")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
        case .passed:
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.green)
                Text("Build passed")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Color.green.opacity(0.1), in: RoundedRectangle(cornerRadius: 4))
        case .failed:
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showBuildOutput.toggle()
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.red)
                    Text("Build failed")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    if !buildDiagnostics.isEmpty {
                        Text("(\(buildDiagnostics.count))")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                    Image(systemName: showBuildOutput ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 4))
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var testStatusBadge: some View {
        switch testStatus {
        case .idle:
            EmptyView()
        case .running:
            HStack(spacing: 4) {
                ProgressView()
                    .controlSize(.mini)
                    .scaleEffect(0.7)
                Text("Testing…")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
        case .passed(let total):
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.green)
                Text(total > 0 ? "Tests passed (\(total))" : "Tests passed")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Color.green.opacity(0.1), in: RoundedRectangle(cornerRadius: 4))
        case .failed(let failedTests, _):
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showTestOutput.toggle()
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.red)
                    Text("Tests failed")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    if !failedTests.isEmpty {
                        Text("(\(failedTests.count))")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                    Image(systemName: showTestOutput ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 4))
            }
            .buttonStyle(.plain)
        }
    }
}

/// A single row in the diagnostics list, showing severity icon, message, and file location.
private struct DiagnosticRow: View {
    let diagnostic: BuildDiagnostic
    let onTap: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                severityIcon
                    .font(.system(size: 11))
                    .frame(width: 14)

                VStack(alignment: .leading, spacing: 1) {
                    Text(diagnostic.message)
                        .font(.system(size: 11))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    HStack(spacing: 4) {
                        Text(locationLabel)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
            .background(isHovering ? Color.accentColor.opacity(0.08) : Color.clear)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help("Click to open file at \(locationLabel)")
    }

    @ViewBuilder
    private var severityIcon: some View {
        switch diagnostic.severity {
        case .error:
            Image(systemName: "xmark.octagon.fill")
                .foregroundStyle(.red)
        case .warning:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
        case .note:
            Image(systemName: "info.circle.fill")
                .foregroundStyle(.blue)
        }
    }

    private var locationLabel: String {
        let filename = (diagnostic.filePath as NSString).lastPathComponent
        if let col = diagnostic.column {
            return "\(filename):\(diagnostic.line):\(col)"
        }
        return "\(filename):\(diagnostic.line)"
    }
}

/// A single row in the changed-files list showing status badge, path, diff stats, and risk indicator.
private struct BannerFileRow: View {
    let file: ChangedFile
    let onTap: () -> Void

    @State private var isHovering = false

    private var priority: ReviewPriority { ReviewPriorityScorer.score(file) }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                Text(statusLabel)
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white)
                    .frame(width: 16, height: 16)
                    .background(
                        RoundedRectangle(cornerRadius: 2)
                            .fill(file.status.color)
                    )

                Text(file.relativePath)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let diff = file.diff {
                    HStack(spacing: 4) {
                        if diff.additionCount > 0 {
                            Text("+\(diff.additionCount)")
                                .font(.system(size: 10).monospacedDigit())
                                .foregroundStyle(.green)
                        }
                        if diff.deletionCount > 0 {
                            Text("-\(diff.deletionCount)")
                                .font(.system(size: 10).monospacedDigit())
                                .foregroundStyle(.red)
                        }
                    }
                }

                ReviewPriorityIndicator(priority: priority)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
            .background(isHovering ? Color.accentColor.opacity(0.08) : Color.clear)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help("Click to view diff for \(file.fileName)")
    }

    private var statusLabel: String {
        switch file.status {
        case .modified:   return "M"
        case .added:      return "A"
        case .deleted:    return "D"
        case .untracked:  return "?"
        case .renamed:    return "R"
        case .conflicted: return "!"
        }
    }
}

// MARK: - Pill Button

/// A pill-shaped action button used in the task-complete suggestion bar.
private struct BannerPillButton: View {
    enum Style { case prominent, secondary }

    let icon: String
    let label: String
    var style: Style = .secondary
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                Text(label)
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(style == .prominent ? .white : .primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                Capsule().fill(backgroundColor)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }

    private var backgroundColor: Color {
        switch style {
        case .prominent:
            return isHovering ? Color.accentColor.opacity(0.85) : Color.accentColor
        case .secondary:
            return isHovering ? Color.primary.opacity(0.12) : Color.primary.opacity(0.07)
        }
    }
}

