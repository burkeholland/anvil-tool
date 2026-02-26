import Foundation

/// Generates a structured markdown summary of changed files suitable for PR descriptions.
enum ChangeSummaryGenerator {

    /// Generates a PR-ready markdown summary.
    ///
    /// - Parameters:
    ///   - files: The changed files to summarize.
    ///   - taskPrompt: The task prompt that initiated the changes, if available.
    static func generate(files: [ChangedFile], taskPrompt: String? = nil) -> String {
        var lines: [String] = []

        // Task section
        if let prompt = taskPrompt?.trimmingCharacters(in: .whitespacesAndNewlines), !prompt.isEmpty {
            lines.append("## Task")
            lines.append("")
            let quoted = prompt.components(separatedBy: "\n").map { "> \($0)" }.joined(separator: "\n")
            lines.append(quoted)
            lines.append("")
        }

        // Stats
        let added    = files.filter { $0.status == .added || $0.status == .untracked }.count
        let modified = files.filter { $0.status == .modified }.count
        let deleted  = files.filter { $0.status == .deleted }.count
        let renamed  = files.filter { $0.status == .renamed }.count

        let totalAdditions = files.compactMap(\.diff).reduce(0) { $0 + $1.additionCount }
        let totalDeletions = files.compactMap(\.diff).reduce(0) { $0 + $1.deletionCount }

        lines.append("## Changes")
        lines.append("")

        var statParts: [String] = []
        if added    > 0 { statParts.append("\(added) added") }
        if modified > 0 { statParts.append("\(modified) modified") }
        if deleted  > 0 { statParts.append("\(deleted) deleted") }
        if renamed  > 0 { statParts.append("\(renamed) renamed") }

        let fileWord = files.count == 1 ? "file" : "files"
        let statSuffix = statParts.isEmpty ? "" : " — \(statParts.joined(separator: ", "))"
        lines.append("**\(files.count) \(fileWord) changed**\(statSuffix)")

        if totalAdditions > 0 || totalDeletions > 0 {
            var lineParts: [String] = []
            if totalAdditions > 0 { lineParts.append("+\(totalAdditions)") }
            if totalDeletions > 0 { lineParts.append("-\(totalDeletions)") }
            lines.append("**Lines:** \(lineParts.joined(separator: " / "))")
        }
        lines.append("")

        // Categorized file list
        let categories: [(label: String, statuses: [GitFileStatus])] = [
            ("Added",    [.added, .untracked]),
            ("Modified", [.modified]),
            ("Deleted",  [.deleted]),
            ("Renamed",  [.renamed]),
        ]

        for category in categories {
            let categoryFiles = files.filter { category.statuses.contains($0.status) }
            guard !categoryFiles.isEmpty else { continue }
            lines.append("### \(category.label)")
            for file in categoryFiles {
                var row = "- `\(file.relativePath)`"
                if let diff = file.diff {
                    var diffParts: [String] = []
                    if diff.additionCount > 0 { diffParts.append("+\(diff.additionCount)") }
                    if diff.deletionCount > 0 { diffParts.append("-\(diff.deletionCount)") }
                    if !diffParts.isEmpty { row += " (\(diffParts.joined(separator: ", ")))" }
                }
                lines.append(row)
            }
            lines.append("")
        }

        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
