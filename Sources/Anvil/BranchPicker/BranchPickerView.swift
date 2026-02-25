import SwiftUI

/// Popover view for switching, creating, and managing git branches.
struct BranchPickerView: View {
    let rootURL: URL
    let currentBranch: String?
    let onDismiss: () -> Void
    let onBranchChanged: () -> Void

    @State private var branches: [GitBranch] = []
    @State private var filterText = ""
    @State private var isLoading = true
    @State private var newBranchName = ""
    @State private var showNewBranchField = false
    @State private var errorMessage: String?
    @State private var branchToDelete: GitBranch?
    @State private var isOperating = false

    private var filteredBranches: [GitBranch] {
        if filterText.isEmpty { return branches }
        let query = filterText.lowercased()
        return branches.filter { $0.name.lowercased().contains(query) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Search field
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.tertiary)
                    .font(.system(size: 12))
                TextField("Filter branches…", text: $filterText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                if !filterText.isEmpty {
                    Button {
                        filterText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color(nsColor: .textBackgroundColor))

            Divider()

            if isLoading {
                HStack {
                    Spacer()
                    ProgressView()
                        .controlSize(.small)
                    Spacer()
                }
                .padding(.vertical, 20)
            } else if filteredBranches.isEmpty {
                VStack(spacing: 6) {
                    Text(filterText.isEmpty ? "No branches found" : "No matching branches")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(filteredBranches) { branch in
                            BranchRow(
                                branch: branch,
                                isDisabled: isOperating,
                                onSwitch: { switchToBranch(branch.name) },
                                onDelete: { branchToDelete = branch }
                            )
                        }
                    }
                }
                .frame(maxHeight: 300)
            }

            Divider()

            // New branch section
            if showNewBranchField {
                HStack(spacing: 6) {
                    Image(systemName: "plus.circle")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 12))
                    TextField("New branch name…", text: $newBranchName)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .onSubmit { createNewBranch() }
                    Button("Create") { createNewBranch() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.mini)
                        .disabled(newBranchName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isOperating)
                    Button {
                        showNewBranchField = false
                        newBranchName = ""
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
            } else {
                Button {
                    showNewBranchField = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .medium))
                        Text("New Branch")
                            .font(.system(size: 12))
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            // Error message
            if let error = errorMessage {
                Divider()
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.yellow)
                    Text(error)
                        .font(.system(size: 10))
                        .foregroundStyle(.red)
                        .lineLimit(2)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
            }
        }
        .frame(width: 300)
        .background(Color(nsColor: .controlBackgroundColor))
        .onAppear { loadBranches() }
        .alert("Delete Branch?", isPresented: Binding(
            get: { branchToDelete != nil },
            set: { if !$0 { branchToDelete = nil } }
        )) {
            Button("Delete", role: .destructive) {
                if let branch = branchToDelete {
                    deleteBranch(branch.name)
                }
                branchToDelete = nil
            }
            Button("Cancel", role: .cancel) {
                branchToDelete = nil
            }
        } message: {
            if let branch = branchToDelete {
                Text("Delete local branch \"\(branch.name)\"? This only removes the local branch reference.")
            }
        }
    }

    private func loadBranches() {
        isLoading = true
        DispatchQueue.global(qos: .userInitiated).async {
            let result = GitBranchProvider.branches(in: rootURL)
            DispatchQueue.main.async {
                branches = result
                isLoading = false
            }
        }
    }

    private func switchToBranch(_ name: String) {
        guard name != currentBranch, !isOperating else { return }
        errorMessage = nil
        isOperating = true

        DispatchQueue.global(qos: .userInitiated).async {
            let result = GitBranchProvider.switchBranch(to: name, in: rootURL)
            DispatchQueue.main.async {
                isOperating = false
                if result.success {
                    onBranchChanged()
                    onDismiss()
                } else {
                    errorMessage = result.error ?? "Failed to switch branch"
                }
            }
        }
    }

    private func createNewBranch() {
        let name = newBranchName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !isOperating else { return }
        errorMessage = nil
        isOperating = true

        DispatchQueue.global(qos: .userInitiated).async {
            let result = GitBranchProvider.createBranch(named: name, in: rootURL)
            DispatchQueue.main.async {
                isOperating = false
                if result.success {
                    newBranchName = ""
                    showNewBranchField = false
                    onBranchChanged()
                    onDismiss()
                } else {
                    errorMessage = result.error ?? "Failed to create branch"
                }
            }
        }
    }

    private func deleteBranch(_ name: String) {
        guard !isOperating else { return }
        errorMessage = nil
        isOperating = true

        DispatchQueue.global(qos: .userInitiated).async {
            let result = GitBranchProvider.deleteBranch(named: name, in: rootURL)
            DispatchQueue.main.async {
                isOperating = false
                if result.success {
                    loadBranches()
                    onBranchChanged()
                } else {
                    errorMessage = result.error ?? "Failed to delete branch"
                }
            }
        }
    }
}

// MARK: - Branch Row

private struct BranchRow: View {
    let branch: GitBranch
    var isDisabled: Bool = false
    let onSwitch: () -> Void
    let onDelete: () -> Void
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 8) {
            // Current branch indicator
            Image(systemName: branch.isCurrent ? "checkmark" : "arrow.triangle.branch")
                .font(.system(size: 11, weight: branch.isCurrent ? .semibold : .regular))
                .foregroundStyle(branch.isCurrent ? .green : .secondary)
                .frame(width: 14)

            VStack(alignment: .leading, spacing: 1) {
                Text(branch.name)
                    .font(.system(size: 12, weight: branch.isCurrent ? .semibold : .regular, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(branch.isCurrent ? .primary : .primary)

                if let message = branch.lastCommitMessage, !message.isEmpty {
                    Text(message)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }

            Spacer()

            // Delete button (not for current branch)
            if isHovering && !branch.isCurrent && !isDisabled {
                Button {
                    onDelete()
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Delete branch")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(isHovering && !branch.isCurrent && !isDisabled ? Color(nsColor: .controlBackgroundColor).opacity(0.8) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture {
            if !isDisabled { onSwitch() }
        }
        .onHover { isHovering = $0 }
        .opacity(isDisabled ? 0.5 : 1.0)
        .contextMenu {
            if !branch.isCurrent {
                Button("Switch to \(branch.name)") { onSwitch() }
                    .disabled(isDisabled)
                Divider()
                Button("Delete Branch…", role: .destructive) { onDelete() }
                    .disabled(isDisabled)
            } else {
                Text("Current Branch")
            }
        }
    }
}
