import SwiftUI

/// A floating banner that appears when the Copilot agent goes idle after making
/// changes, providing a summary and quick actions for the review workflow.
struct TaskCompleteBanner: View {
    let changedFileCount: Int
    let totalAdditions: Int
    let totalDeletions: Int
    let buildStatus: BuildVerifier.Status
    /// Structured diagnostics parsed from the failed build output.
    var buildDiagnostics: [BuildDiagnostic] = []
    /// Called when the user taps a diagnostic row to navigate to the error location.
    var onOpenDiagnostic: ((BuildDiagnostic) -> Void)?
    var onReviewAll: () -> Void
    var onStageAllAndCommit: () -> Void
    var onNewTask: () -> Void
    var onDismiss: () -> Void

    @State private var showBuildOutput = false

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

                Spacer()

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
        }
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) { Divider() }
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

