import SwiftUI

/// A floating banner that appears when the Copilot agent goes idle after making
/// changes, providing a summary and quick actions for the review workflow.
struct TaskCompleteBanner: View {
    let changedFileCount: Int
    let totalAdditions: Int
    let totalDeletions: Int
    let buildStatus: BuildVerifier.Status
    /// The available pre-task snapshots, newest first.
    let snapshots: [AnvilSnapshot]
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
    var onReviewAll: () -> Void
    var onStageAllAndCommit: () -> Void
    var onNewTask: () -> Void
    var onDismiss: () -> Void
    var onRollback: (AnvilSnapshot) -> Void

    @State private var showBuildOutput = false
    @State private var showRollbackConfirmation = false
    @State private var selectedSnapshot: AnvilSnapshot?
    @State private var showTestOutput = false

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
                    Text("\(changedFileCount) file\(changedFileCount == 1 ? "" : "s") changed")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
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

                if !snapshots.isEmpty {
                    rollbackButton
                }

                if onRunTests != nil {
                    switch testStatus {
                    case .running:
                        EmptyView()
                    default:
                        Button {
                            onRunTests?()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "play.circle")
                                    .font(.system(size: 10))
                                Text("Run Tests")
                                    .font(.system(size: 12))
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }

                if changedFileCount > 0 {
                    Button {
                        onReviewAll()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "doc.text.magnifyingglass")
                                .font(.system(size: 10))
                            Text("Review Changes")
                                .font(.system(size: 12))
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)

                    Button {
                        onStageAllAndCommit()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle")
                                .font(.system(size: 10))
                            Text("Stage All & Commit")
                                .font(.system(size: 12))
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                Button {
                    onNewTask()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus.circle")
                            .font(.system(size: 10))
                        Text("New Task")
                            .font(.system(size: 12))
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

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
        }
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) { Divider() }
        .alert("Roll Back to Pre-Task Snapshot?", isPresented: $showRollbackConfirmation) {
            Button("Roll Back", role: .destructive) {
                if let snapshot = selectedSnapshot {
                    onRollback(snapshot)
                }
            }
            Button("Cancel", role: .cancel) {
                selectedSnapshot = nil
            }
        } message: {
            if let snapshot = selectedSnapshot {
                Text("This will restore the working tree to the state from \(snapshot.relativeDate). Uncommitted changes made after that point will be discarded.")
            }
        }
    }

    @ViewBuilder
    private var rollbackButton: some View {
        if snapshots.count == 1, let snapshot = snapshots.first {
            Button {
                selectedSnapshot = snapshot
                showRollbackConfirmation = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.uturn.backward.circle")
                        .font(.system(size: 10))
                    Text("Rollback")
                        .font(.system(size: 12))
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("Restore working tree to the pre-task snapshot (\(snapshot.relativeDate))")
        } else {
            Menu {
                ForEach(snapshots) { snapshot in
                    Button {
                        selectedSnapshot = snapshot
                        showRollbackConfirmation = true
                    } label: {
                        Label(snapshot.relativeDate, systemImage: "arrow.uturn.backward.circle")
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.uturn.backward.circle")
                        .font(.system(size: 10))
                    Text("Rollback")
                        .font(.system(size: 12))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8))
                }
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5))
            .help("Roll back to a pre-task snapshot")
        }
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

