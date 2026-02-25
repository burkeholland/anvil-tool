import SwiftUI

/// Context for a "Request Fix" prompt, capturing the file path and optional hunk line range.
struct RequestFixContext {
    let filePath: String
    /// Optional hunk line range, e.g. "L10-L20", included when triggered from a specific hunk.
    let lineRange: String?

    /// The @-mention prefix pre-seeded in the prompt bar.
    var mentionPrefix: String {
        if let range = lineRange {
            return "@\(filePath)#\(range)"
        }
        return "@\(filePath)"
    }
}

/// Compact one-line prompt bar shown within diff views.
/// Pre-seeds the file (and optional hunk line range) as an @-mention, lets the developer
/// type a natural-language instruction, then sends the composed prompt to the active Copilot
/// terminal via `TerminalInputProxy`.
struct RequestFixPromptView: View {
    let context: RequestFixContext
    var onSubmit: (String) -> Void
    var onDismiss: () -> Void

    @State private var instruction = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "wrench.and.screwdriver")
                .font(.system(size: 11))
                .foregroundStyle(.orange)

            Text(context.mentionPrefix)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.blue)
                .lineLimit(1)
                .truncationMode(.middle)

            TextField("Describe the fix (e.g. add error handling)…", text: $instruction)
                .font(.system(size: 12))
                .textFieldStyle(.plain)
                .focused($isFocused)
                .onSubmit { submit() }
                .onKeyPress(.escape) {
                    onDismiss()
                    return .handled
                }

            Button("Send") { submit() }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help("Cancel (Esc)")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(nsColor: .controlBackgroundColor))
        .overlay(alignment: .bottom) { Divider() }
        .onAppear { isFocused = true }
    }

    private func submit() {
        let trimmed = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        onSubmit("\(context.mentionPrefix) \(trimmed)\n")
    }
}

// MARK: - Hunk line range helper

extension DiffHunk {
    /// Parses the hunk header to extract the new-file line range (e.g. "L12-L19").
    /// Returns nil if the header cannot be parsed.
    var newFileLineRange: String? {
        guard let match = DiffHunk.hunkRangeRegex.firstMatch(in: header, range: NSRange(header.startIndex..., in: header)),
              let startRange = Range(match.range(at: 1), in: header),
              let start = Int(header[startRange])
        else { return nil }

        if let countRange = Range(match.range(at: 2), in: header),
           let count = Int(header[countRange]), count > 1 {
            return "L\(start)-L\(start + count - 1)"
        }
        return "L\(start)"
    }

    private static let hunkRangeRegex: NSRegularExpression = {
        // swiftlint:disable:next force_try
        try! NSRegularExpression(pattern: #"\+(\d+)(?:,(\d+))?"#)
    }()
}
