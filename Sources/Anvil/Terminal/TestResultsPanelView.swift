import SwiftUI

/// A persistent sidebar panel that retains the latest test run results across agent
/// interactions. Shows all test cases with pass/fail status, execution time, and
/// failure messages, with a per-test "Fix with Copilot" action and a "Re-run" button.
struct TestResultsPanelView: View {
    @ObservedObject var store: TestResultsStore
    @ObservedObject var testRunner: TestRunner
    var rootURL: URL?
    /// Called when the user taps "Fix with Copilot" on a failing test.
    var onFixTestCase: ((String) -> Void)?
    /// Called when the user taps "Fix All with Copilot" (passes raw output).
    var onFixTestFailure: ((String) -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            // Header toolbar
            HStack(spacing: 8) {
                Text("Tests")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.primary)

                Spacer()

                if case .running = testRunner.status {
                    ProgressView()
                        .controlSize(.mini)
                        .scaleEffect(0.8)
                    Text("Running…")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                } else {
                    if let run = store.latestRun {
                        summaryBadge(run: run)
                    }

                    Button {
                        if let url = rootURL {
                            testRunner.run(at: url)
                        }
                    } label: {
                        Image(systemName: "play.circle")
                            .font(.system(size: 13))
                            .foregroundStyle(.accentColor)
                    }
                    .buttonStyle(.plain)
                    .disabled(rootURL == nil)
                    .help("Run all tests")
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            if let run = store.latestRun {
                if run.testCases.isEmpty {
                    // No per-case data: show raw output
                    rawOutputPanel(output: run.rawOutput, succeeded: run.succeeded)
                } else {
                    testCaseList(run: run)
                }
            } else {
                emptyState
            }
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private func summaryBadge(run: TestRunRecord) -> some View {
        if run.succeeded {
            HStack(spacing: 3) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.green)
                Text(run.testCases.isEmpty
                        ? "Passed"
                        : "\(run.passedCount) passed")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        } else {
            HStack(spacing: 3) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.red)
                Text("\(run.failedCount) failed")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func testCaseList(run: TestRunRecord) -> some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(run.testCases) { testCase in
                    TestCaseRow(
                        testCase: testCase,
                        rootURL: rootURL,
                        onFix: onFixTestCase != nil ? { onFixTestCase?(testCase.name) } : nil,
                        onRerun: rootURL != nil ? {
                            testRunner.runSingle(testCase.name, at: rootURL!)
                        } : nil
                    )
                    Divider().padding(.leading, 30)
                }
            }
        }

        // "Fix all" footer shown only when there are failures
        if !run.succeeded, let handler = onFixTestFailure {
            Divider()
            HStack {
                Spacer()
                Button {
                    handler(run.rawOutput)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "ant.circle")
                            .font(.system(size: 10))
                        Text("Fix All with Copilot")
                            .font(.system(size: 11))
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .controlSize(.small)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
            }
            .background(Color(nsColor: .controlBackgroundColor))
        }
    }

    @ViewBuilder
    private func rawOutputPanel(output: String, succeeded: Bool) -> some View {
        ScrollView {
            VStack(spacing: 0) {
                HStack(spacing: 6) {
                    Image(systemName: succeeded ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(succeeded ? .green : .red)
                        .font(.system(size: 12))
                    Text(succeeded ? "Tests passed" : "Tests failed")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.primary)
                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)

                Text(output)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 10)
                    .textSelection(.enabled)
            }
        }

        if !succeeded, let handler = onFixTestFailure {
            Divider()
            HStack {
                Spacer()
                Button {
                    handler(output)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "ant.circle")
                            .font(.system(size: 10))
                        Text("Fix with Copilot")
                            .font(.system(size: 11))
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .controlSize(.small)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
            }
            .background(Color(nsColor: .controlBackgroundColor))
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "checkmark.seal")
                .font(.system(size: 28))
                .foregroundStyle(.tertiary)
            Text("No test results yet")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("Run tests to see results here")
                .font(.caption)
                .foregroundStyle(.tertiary)
            if rootURL != nil {
                Button {
                    if let url = rootURL {
                        testRunner.run(at: url)
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "play.circle")
                            .font(.system(size: 11))
                        Text("Run Tests")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(Color.accentColor, in: Capsule())
                    .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - TestCaseRow

private struct TestCaseRow: View {
    let testCase: TestResultParser.TestCaseResult
    var rootURL: URL?
    var onFix: (() -> Void)?
    var onRerun: (() -> Void)?

    @State private var isHovering = false
    @State private var showFailureMessage = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                // Pass/fail icon
                Image(systemName: testCase.passed ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(testCase.passed ? .green : .red)
                    .frame(width: 14)

                // Test name (truncated)
                Text(testCase.name)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)

                // Duration badge
                if let dur = testCase.duration {
                    Text(formatDuration(dur))
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }

                // Hover actions
                if isHovering {
                    if !testCase.passed, let fix = onFix {
                        Button(action: fix) {
                            HStack(spacing: 3) {
                                Image(systemName: "ant.circle")
                                    .font(.system(size: 9))
                                Text("Fix")
                                    .font(.system(size: 10, weight: .medium))
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.red.opacity(0.85), in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .transition(.opacity)
                    }

                    if let rerun = onRerun {
                        Button(action: rerun) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 10))
                                .foregroundStyle(.accentColor)
                        }
                        .buttonStyle(.plain)
                        .help("Re-run this test")
                        .transition(.opacity)
                    }
                }

                // Chevron for failure message when available
                if !testCase.passed, testCase.failureMessage != nil {
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            showFailureMessage.toggle()
                        }
                    } label: {
                        Image(systemName: showFailureMessage ? "chevron.up" : "chevron.down")
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(isHovering ? Color.accentColor.opacity(0.08) : Color.clear)
            .contentShape(Rectangle())
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.12)) { isHovering = hovering }
            }

            // Expandable failure message
            if showFailureMessage, let msg = testCase.failureMessage {
                Text(msg)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 30)
                    .padding(.bottom, 5)
                    .textSelection(.enabled)
            }
        }
    }

    private func formatDuration(_ seconds: Double) -> String {
        if seconds < 1 {
            return String(format: "%.0fms", seconds * 1000)
        }
        return String(format: "%.2fs", seconds)
    }
}
