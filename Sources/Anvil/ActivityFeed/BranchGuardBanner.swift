import SwiftUI

/// Non-blocking alert banner shown when the agent first modifies a file on
/// the default branch (main/master), offering to create a feature branch.
struct BranchGuardBanner: View {
    let branchName: String
    let rootURL: URL
    var onBranchCreated: (String) -> Void
    var onDismiss: () -> Void

    @State private var isCreating = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(.orange)

                Text("Working on \(branchName)")
                    .font(.system(size: 12, weight: .semibold))

                Text("–")
                    .foregroundStyle(.tertiary)

                Text("Agent is editing files directly on the default branch.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer()

                if isCreating {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Button {
                        createBranch()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.triangle.branch")
                                .font(.system(size: 10))
                            Text("Create Branch & Continue")
                                .font(.system(size: 12))
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .controlSize(.small)
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

            if let error = errorMessage {
                Divider()
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.red)
                    Text(error)
                        .font(.system(size: 11))
                        .foregroundStyle(.red)
                        .lineLimit(2)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(Color.red.opacity(0.05))
            }
        }
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) { Divider() }
    }

    private func createBranch() {
        isCreating = true
        errorMessage = nil
        let name = BranchGuardBanner.autoBranchName()
        DispatchQueue.global(qos: .userInitiated).async {
            let result = GitBranchProvider.createBranch(named: name, in: rootURL)
            DispatchQueue.main.async {
                isCreating = false
                if result.success {
                    onBranchCreated(name)
                } else {
                    errorMessage = result.error ?? "Failed to create branch"
                }
            }
        }
    }

    /// Generates a branch name like `copilot/task-20260226-0227`.
    static func autoBranchName() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmm"
        return "copilot/task-\(formatter.string(from: Date()))"
    }
}
