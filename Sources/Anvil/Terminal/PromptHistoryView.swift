import SwiftUI

/// A searchable panel showing all past prompts sent to the Copilot terminal.
/// Prompts can be filtered by text and re-sent to the active terminal with one click.
struct PromptHistoryView: View {
    @EnvironmentObject var terminalProxy: TerminalInputProxy
    @ObservedObject var store: PromptHistoryStore
    var onDismiss: () -> Void

    @State private var searchText = ""

    private var filteredEntries: [PromptEntry] {
        guard !searchText.isEmpty else { return store.entries }
        return store.entries.filter {
            $0.text.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Label("Prompt History", systemImage: "clock.arrow.circlepath")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                if !store.entries.isEmpty {
                    Button("Clear All") {
                        store.clearAll()
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .buttonStyle(.plain)
                }
                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider()

            // Search field
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                TextField("Filter prompts…", text: $searchText)
                    .font(.system(size: 12))
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Color(nsColor: .controlBackgroundColor))
            .overlay(alignment: .bottom) { Divider() }

            if store.entries.isEmpty {
                emptyStateView
            } else if filteredEntries.isEmpty {
                noMatchView
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filteredEntries) { entry in
                            PromptEntryRow(
                                entry: entry,
                                onReSend: {
                                    terminalProxy.sendPrompt(entry.text)
                                    onDismiss()
                                },
                                onDelete: {
                                    store.remove(entry)
                                }
                            )
                            Divider().padding(.leading, 14)
                        }
                    }
                }
            }
        }
        .frame(minWidth: 400, idealWidth: 480)
        .frame(minHeight: 300)
    }

    private var emptyStateView: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 24))
                .foregroundStyle(.tertiary)
            Text("No prompt history yet")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Text("Prompts you send to Copilot\nwill appear here.")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity, minHeight: 100)
    }

    private var noMatchView: some View {
        VStack {
            Spacer()
            Text("No matching prompts")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, minHeight: 60)
    }
}

// MARK: - Entry Row

private struct PromptEntryRow: View {
    let entry: PromptEntry
    let onReSend: () -> Void
    let onDelete: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.text)
                    .font(.system(size: 12))
                    .lineLimit(3)
                    .truncationMode(.tail)
                    .foregroundStyle(.primary)
                Text(entry.date, style: .relative)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            if isHovering {
                HStack(spacing: 4) {
                    Button {
                        onDelete()
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .frame(width: 22, height: 22)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Delete entry")

                    Button {
                        onReSend()
                    } label: {
                        Image(systemName: "arrow.uturn.forward")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 22, height: 22)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Re-send to terminal")
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
    }
}
