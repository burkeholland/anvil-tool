import SwiftUI

/// Severity level for the per-file review-priority indicator.
enum ReviewPriorityLevel: Int, Comparable {
    case low    = 0
    case medium = 1
    case high   = 2

    static func < (lhs: ReviewPriorityLevel, rhs: ReviewPriorityLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// Color of the indicator dot shown next to the file row.
    var color: Color {
        switch self {
        case .high:   return .red
        case .medium: return .orange
        case .low:    return .green
        }
    }

    /// Accessibility label for the indicator.
    var label: String {
        switch self {
        case .high:   return "High risk"
        case .medium: return "Medium risk"
        case .low:    return "Low risk"
        }
    }
}

/// The result of scoring a single changed file.
struct ReviewPriority {
    let level: ReviewPriorityLevel
    /// Short, human-readable reasons explaining why this priority was assigned.
    let reasons: [String]

    /// Tooltip text shown when the user hovers the indicator dot.
    var tooltipText: String {
        if reasons.isEmpty {
            return level.label
        }
        return "\(level.label) · \(reasons.joined(separator: " · "))"
    }
}

/// A small color-coded dot indicator displayed next to a file row.
/// Tapping or hovering shows a tooltip explaining why the file received its priority score.
struct ReviewPriorityIndicator: View {
    let priority: ReviewPriority

    var body: some View {
        Circle()
            .fill(priority.level.color)
            .frame(width: 8, height: 8)
            .help(priority.tooltipText)
            .accessibilityLabel(priority.level.label)
    }
}

/// Computes a heuristic review-priority score for each changed file.
///
/// Heuristics (each adds to a raw point total):
/// - **New / deleted file** – brand-new or removed files warrant extra scrutiny.
/// - **Lines changed** – large diffs are harder to review correctly.
/// - **Core module** – hub files (index, utils, store, etc.) are widely imported
///   and a mistake propagates broadly.
/// - **Multiple functions affected** – many independent hunks suggest broad impact.
/// - **Source vs. test** – test files are scored slightly lower than source files.
enum ReviewPriorityScorer {

    // MARK: - Public API

    static func score(_ file: ChangedFile) -> ReviewPriority {
        var points = 0
        var reasons: [String] = []

        // 1. New or deleted file
        switch file.status {
        case .added:
            points += 2
            reasons.append("New file")
        case .deleted:
            points += 2
            reasons.append("File deleted")
        default:
            break
        }

        // 2. Lines changed (additions + deletions, used as proxy for change magnitude)
        let totalLinesChanged = (file.diff?.additionCount ?? 0) + (file.diff?.deletionCount ?? 0)
        if totalLinesChanged > 100 {
            points += 3
            reasons.append("\(totalLinesChanged) lines changed")
        } else if totalLinesChanged > 30 {
            points += 1
            reasons.append("\(totalLinesChanged) lines changed")
        }

        // 3. Source vs. test — test files carry lower risk
        if isTestFile(file.relativePath) {
            points -= 1
        } else {
            points += 1
        }

        // 4. Hub / core module — likely imported by many other files
        if isHubFile(file.relativePath) {
            points += 2
            reasons.append("Core module")
        }

        // 5. Multiple distinct logical units changed (non-trivial hunk headers)
        let hunksWithContext = countSignificantHunks(in: file.diff)
        if hunksWithContext > 3 {
            points += 2
            reasons.append("\(hunksWithContext) functions affected")
        } else if hunksWithContext > 1 {
            points += 1
            reasons.append("\(hunksWithContext) functions affected")
        }

        let level: ReviewPriorityLevel
        if points >= 5 {
            level = .high
        } else if points >= 2 {
            level = .medium
        } else {
            level = .low
        }

        return ReviewPriority(level: level, reasons: reasons)
    }

    // MARK: - Sorting helpers

    /// Sorts a sequence of changed files highest-priority first.
    /// Files with equal priority retain their original relative order (stable sort).
    /// Scores are computed once per file to avoid redundant work during the sort.
    static func sorted<C: Collection>(_ files: C) -> [ChangedFile] where C.Element == ChangedFile {
        let scored = files.map { (file: $0, level: score($0).level) }
        return scored.sorted { $0.level > $1.level }.map(\.file)
    }

    // MARK: - Internal heuristics

    private static let testPathComponents: Set<String> = [
        "test", "tests", "spec", "specs", "__tests__", "__mocks__",
        "mock", "mocks", "fixture", "fixtures",
    ]

    private static let testFileSuffixes: [String] = [
        "test", "tests", "spec", "specs", "mock", "mocks", "fixture", "fixtures",
    ]

    static func isTestFile(_ path: String) -> Bool {
        let lower = path.lowercased()
        let components = lower.split(separator: "/").map(String.init)
        // Any directory component is a well-known test directory
        if components.dropLast().contains(where: { testPathComponents.contains($0) }) {
            return true
        }
        // File stem ends with a test suffix (e.g. "LoginTests", "ButtonSpec")
        let filename = (lower as NSString).lastPathComponent
        let stem = (filename as NSString).deletingPathExtension
        return testFileSuffixes.contains(where: { stem.hasSuffix($0) })
    }

    /// File stems that are commonly imported / depended on by many other modules.
    private static let hubFileStems: Set<String> = [
        "index", "mod", "main", "app", "root",
        "utils", "util", "helpers", "helper",
        "common", "shared", "base",
        "core", "kernel",
        "types", "type", "interfaces", "interface",
        "schema", "schemas",
        "models", "model",
        "store", "stores",
        "config", "configuration", "constants", "settings",
        "manager", "managers",
        "provider", "providers",
        "service", "services",
        "api", "client", "server",
    ]

    static func isHubFile(_ path: String) -> Bool {
        let filename = (path.lowercased() as NSString).lastPathComponent
        let stem = (filename as NSString).deletingPathExtension
        return hubFileStems.contains(stem)
    }

    /// Counts hunks that carry a non-empty function/symbol context string in their header,
    /// which indicates a distinct logical code unit was changed.
    static func countSignificantHunks(in diff: FileDiff?) -> Int {
        guard let diff else { return 0 }
        return diff.hunks.filter { hunk in
            // Unified diff hunk headers: "@@ -a,b +c,d @@ <optional function context>"
            // Text after the second "@@" (if any) is the enclosing function/class name.
            guard let lastRange = hunk.header.range(of: "@@", options: .backwards) else {
                return false
            }
            let context = String(hunk.header[lastRange.upperBound...])
                .trimmingCharacters(in: .whitespaces)
            return !context.isEmpty
        }.count
    }
}
