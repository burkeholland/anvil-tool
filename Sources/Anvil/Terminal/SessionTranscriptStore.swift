import Foundation
import CryptoKit

/// Generates and persists a markdown export of the active terminal session transcript.
/// Transcripts are stored under the same PromptHistory directory used by PromptHistoryStore,
/// using the project-path SHA-256 as the filename stem.
final class SessionTranscriptStore: ObservableObject {

    /// Maximum character count for a saved transcript (≈ 2 MB of plain text).
    private let maxExportChars = 500_000

    private var storageDirectory: URL?

    /// (Re-)configures storage for the given project path.
    /// Pass `nil` to reset without touching disk (e.g. when no project is open).
    func configure(projectPath: String?) {
        storageDirectory = projectPath.flatMap { _ in
            Self.appSupportDirectory?.appendingPathComponent("PromptHistory")
        }
    }

    // MARK: - Markdown generation

    /// Builds a markdown document from the terminal transcript and prompt timeline.
    ///
    /// - Parameters:
    ///   - transcript: The ANSI-stripped terminal scrollback content (plain text).
    ///   - prompts: Prompt markers recorded during the session, in chronological order.
    ///   - projectName: Used in the document title.
    static func makeMarkdown(
        transcript: String,
        prompts: [PromptMarker],
        projectName: String
    ) -> String {
        var lines: [String] = []
        let dateStr = DateFormatter.localizedString(from: Date(), dateStyle: .medium, timeStyle: .short)

        lines.append("# Session Transcript — \(projectName)")
        lines.append("")
        lines.append("**Exported:** \(dateStr)")
        if !prompts.isEmpty {
            lines.append("**Prompts:** \(prompts.count)")
        }
        lines.append("")
        lines.append("---")

        if !prompts.isEmpty {
            lines.append("")
            lines.append("## Prompts")
            lines.append("")
            for (i, marker) in prompts.enumerated() {
                let timeStr = DateFormatter.localizedString(
                    from: marker.date,
                    dateStyle: .none,
                    timeStyle: .medium
                )
                lines.append("\(i + 1). [\(timeStr)] \(marker.text)")
            }
            lines.append("")
            lines.append("---")
        }

        lines.append("")
        lines.append("## Terminal Output")
        lines.append("")
        lines.append("```")
        lines.append(transcript.isEmpty ? "(no output captured)" : transcript)
        lines.append("```")
        lines.append("")

        return lines.joined(separator: "\n")
    }

    // MARK: - Persistence

    /// Saves `markdown` under the PromptHistory directory for `projectPath`.
    /// The file is overwritten on each export.  Content is truncated to
    /// `maxExportChars` characters to keep file sizes manageable.
    ///
    /// - Returns: The URL of the saved file, or `nil` on failure.
    func save(markdown: String, projectPath: String) -> URL? {
        guard let dir = storageDirectory else { return nil }
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let stem = Self.sha256Filename(for: projectPath)
            let url = dir.appendingPathComponent("\(stem)_transcript.md")

            var content = markdown
            if content.count > maxExportChars {
                content = String(content.prefix(maxExportChars))
                    + "\n\n*(transcript truncated due to size limit)*\n"
            }

            try content.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            // Non-fatal: export is still available in-memory even if disk write fails
            return nil
        }
    }

    // MARK: - Helpers

    private static var appSupportDirectory: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Anvil")
    }

    /// Returns a 64-character hex SHA-256 digest of `path`, safe to use as a filename stem.
    static func sha256Filename(for path: String) -> String {
        let digest = SHA256.hash(data: Data(path.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
