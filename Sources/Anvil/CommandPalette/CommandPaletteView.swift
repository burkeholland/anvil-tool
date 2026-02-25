import SwiftUI

/// A floating command palette for quickly executing app commands via fuzzy search.
/// Activated via ⌘⇧P. Renders as a centered overlay above the main content.
struct CommandPaletteView: View {
    @ObservedObject var model: CommandPaletteModel
    var onDismiss: () -> Void

    @FocusState private var isSearchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Search field
            HStack(spacing: 8) {
                Image(systemName: "command")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)

                TextField("Type a command…", text: $model.query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 16))
                    .focused($isSearchFocused)
                    .onSubmit { executeAndDismiss() }

                if !model.query.isEmpty {
                    Button {
                        model.query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            Divider()

            // Results list
            if model.results.isEmpty && !model.query.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "questionmark.circle")
                        .font(.system(size: 24))
                        .foregroundStyle(.tertiary)
                    Text("No matching commands")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, minHeight: 100)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(model.results.enumerated()), id: \.element.id) { index, result in
                                CommandResultRow(
                                    result: result,
                                    isSelected: index == model.selectedIndex
                                )
                                .id(result.id)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    model.selectedIndex = index
                                    executeAndDismiss()
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .frame(maxHeight: 380)
                    .onChange(of: model.selectedIndex) { _, newIndex in
                        if let result = model.results[safe: newIndex] {
                            proxy.scrollTo(result.id, anchor: .center)
                        }
                    }
                }
            }

            // Footer hint
            HStack(spacing: 16) {
                KeyHint(keys: ["↑", "↓"], label: "navigate")
                KeyHint(keys: ["↩"], label: "run")
                KeyHint(keys: ["esc"], label: "dismiss")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        }
        .frame(width: 520)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .windowBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.3), radius: 20, y: 10)
        .onAppear {
            isSearchFocused = true
        }
        .onKeyPress(.upArrow) {
            model.moveSelection(-1)
            return .handled
        }
        .onKeyPress(.downArrow) {
            model.moveSelection(1)
            return .handled
        }
        .onKeyPress(.escape) {
            onDismiss()
            return .handled
        }
    }

    private func executeAndDismiss() {
        model.executeSelected()
        onDismiss()
    }
}

struct CommandResultRow: View {
    let result: PaletteResult
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: result.command.icon)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 1) {
                Text(result.command.title)
                    .font(.system(size: 13))
                    .lineLimit(1)

                Text(result.command.category)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            Spacer()

            if let shortcut = result.command.shortcut {
                Text(shortcut)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(
            isSelected
                ? RoundedRectangle(cornerRadius: 4).fill(Color.accentColor.opacity(0.2))
                    .padding(.horizontal, 4)
                : nil
        )
    }
}
