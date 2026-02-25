import SwiftUI
import SwiftTerm

/// Floating search bar overlay for the terminal pane, activated by ⌘F.
/// Highlights all matches in the scrollback buffer via SwiftTerm's public search API
/// and allows navigating between them with ⌘G / ⌘⇧G (or the arrow buttons).
struct TerminalSearchBarView: View {
    @ObservedObject var proxy: TerminalInputProxy
    @State private var searchText: String = ""
    @State private var isCaseSensitive: Bool = false
    @State private var isRegex: Bool = false
    @FocusState private var searchFieldFocused: Bool

    private var searchOptions: SearchOptions {
        SearchOptions(caseSensitive: isCaseSensitive, regex: isRegex)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                // Search text field
                TextField("Find", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .frame(minWidth: 160)
                    .focused($searchFieldFocused)
                    .onSubmit { proxy.findTerminalNext() }
                    .onChange(of: searchText) { _, newValue in
                        proxy.updateSearch(term: newValue, options: searchOptions)
                    }

                // Match count indicator
                if !searchText.isEmpty {
                    Text("\(proxy.findMatchCount) match\(proxy.findMatchCount == 1 ? "" : "es")")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize()
                }

                Divider()
                    .frame(height: 16)

                // Case-sensitive toggle
                Toggle(isOn: $isCaseSensitive) {
                    Text("Aa")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                }
                .toggleStyle(.button)
                .controlSize(.small)
                .help("Case Sensitive")
                .onChange(of: isCaseSensitive) { _, _ in
                    proxy.updateSearch(term: searchText, options: searchOptions)
                }

                // Regex toggle
                Toggle(isOn: $isRegex) {
                    Text(".*")
                        .font(.system(size: 11, design: .monospaced))
                }
                .toggleStyle(.button)
                .controlSize(.small)
                .help("Regular Expression")
                .onChange(of: isRegex) { _, _ in
                    proxy.updateSearch(term: searchText, options: searchOptions)
                }

                Divider()
                    .frame(height: 16)

                // Previous match button
                Button {
                    proxy.findTerminalPrevious()
                } label: {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.plain)
                .help("Previous Match (⌘⇧G)")
                .disabled(searchText.isEmpty || proxy.findMatchCount == 0)

                // Next match button
                Button {
                    proxy.findTerminalNext()
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.plain)
                .help("Next Match (⌘G)")
                .disabled(searchText.isEmpty || proxy.findMatchCount == 0)

                Divider()
                    .frame(height: 16)

                // Close button
                Button {
                    dismissBar()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Close (Escape)")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
        }
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(.separator, lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.18), radius: 8, x: 0, y: 2)
        .frame(maxWidth: 500)
        .padding(.top, 8)
        .padding(.trailing, 8)
        .onAppear {
            searchFieldFocused = true
        }
        .onExitCommand {
            dismissBar()
        }
    }

    private func dismissBar() {
        searchText = ""
        proxy.dismissFindBar()
    }
}
