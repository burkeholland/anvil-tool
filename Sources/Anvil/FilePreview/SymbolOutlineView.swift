import SwiftUI

/// A popover that shows document symbols (functions, classes, etc.) parsed from the current file.
/// Supports filtering and click-to-jump navigation.
/// Symbols that fall within git-changed lines are highlighted in orange.
struct SymbolOutlineView: View {
    let symbols: [DocumentSymbol]
    /// Set of 1-based line numbers that have git changes (additions or modifications).
    let changedLines: Set<Int>
    let onSelect: (Int) -> Void
    let onDismiss: () -> Void
    @State private var filterText = ""
    @FocusState private var isFilterFocused: Bool

    private var filtered: [DocumentSymbol] {
        if filterText.isEmpty { return symbols }
        let query = filterText.lowercased()
        return symbols.filter { $0.name.lowercased().contains(query) }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search field
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                TextField("Filter symbols…", text: $filterText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .focused($isFilterFocused)

                if !filterText.isEmpty {
                    Button {
                        filterText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            if filtered.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 20))
                        .foregroundStyle(.tertiary)
                    Text(filterText.isEmpty ? "No symbols found" : "No matching symbols")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 80)
                .padding()
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(filtered) { symbol in
                            SymbolRow(symbol: symbol, isChanged: changedLines.contains(symbol.line))
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    onSelect(symbol.line)
                                    onDismiss()
                                }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            Divider()

            // Footer with count
            HStack {
                Text("\(filtered.count) symbol\(filtered.count == 1 ? "" : "s")")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                let changedCount = filtered.filter { changedLines.contains($0.line) }.count
                if changedCount > 0 {
                    Text("·")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                    Image(systemName: "circle.fill")
                        .font(.system(size: 6))
                        .foregroundStyle(.orange)
                    Text("\(changedCount) changed")
                        .font(.system(size: 10))
                        .foregroundStyle(.orange)
                }
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
        }
        .frame(width: 280)
        .frame(maxHeight: 400)
        .onAppear {
            isFilterFocused = true
        }
    }
}

/// A single row in the symbol outline.
private struct SymbolRow: View {
    let symbol: DocumentSymbol
    let isChanged: Bool

    var body: some View {
        HStack(spacing: 6) {
            // Indentation
            if symbol.depth > 0 {
                Spacer()
                    .frame(width: CGFloat(symbol.depth) * 12)
            }

            Image(systemName: symbol.icon)
                .font(.system(size: 10))
                .foregroundStyle(iconColor)
                .frame(width: 16, height: 16)

            Text(symbol.name)
                .font(.system(size: 12, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer()

            if isChanged {
                Image(systemName: "circle.fill")
                    .font(.system(size: 6))
                    .foregroundStyle(.orange)
            }

            Text("L\(symbol.line)")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(isChanged ? .orange : .tertiary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 3)
        .background(isChanged ? Color.orange.opacity(0.06) : Color.clear)
        .onHover { hovering in
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }

    private var iconColor: Color {
        switch symbol.iconColor {
        case "blue":      return .blue
        case "purple":    return .purple
        case "orange":    return .orange
        case "green":     return .green
        case "teal":      return .teal
        case "secondary": return .secondary
        default:          return .primary
        }
    }
}
