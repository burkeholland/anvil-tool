import Foundation

// MARK: - Risk Flag Model

/// The kind of risk pattern detected in a diff hunk.
enum DiffRiskKind: String, CaseIterable {
    case deletedErrorHandling   = "Deleted error handling"
    case deletedNilCheck        = "Deleted nil/guard check"
    case credentialLike         = "Possible credential"
    case forceUnwrap            = "Force-unwrap added"
    case deletedTestAssertion   = "Deleted test assertion"
    case todoHackMarker         = "TODO / HACK marker added"

    /// Short label used in the gutter tooltip.
    var shortDescription: String { rawValue }

    /// SF Symbol name for this risk kind.
    var symbolName: String {
        switch self {
        case .deletedErrorHandling: return "exclamationmark.triangle"
        case .deletedNilCheck:      return "exclamationmark.triangle"
        case .credentialLike:       return "key"
        case .forceUnwrap:          return "exclamationmark.triangle"
        case .deletedTestAssertion: return "xmark.circle"
        case .todoHackMarker:       return "text.badge.plus"
        }
    }
}

/// A single risk flag attached to a line in a diff hunk.
struct DiffRiskFlag: Identifiable {
    let id = UUID()
    let kind: DiffRiskKind
    /// Line number within the diff (uses `newLineNumber ?? oldLineNumber`).
    let lineNumber: Int?
    /// Human-readable description including the risk kind and any supporting detail.
    let description: String
}

// MARK: - Scanner

/// Scans a `DiffHunk` and returns any risk flags found in its lines.
/// Risk patterns are evaluated against deletion and addition lines only;
/// context lines are ignored unless a pattern explicitly targets them.
enum DiffRiskScanner {

    // MARK: - Public API

    /// Returns an array of risk flags for the given hunk.
    /// The returned array may be empty when no risks are detected.
    static func scan(_ hunk: DiffHunk) -> [DiffRiskFlag] {
        var flags: [DiffRiskFlag] = []
        for line in hunk.lines {
            switch line.kind {
            case .deletion:
                flags += deletionRisks(for: line)
            case .addition:
                flags += additionRisks(for: line)
            default:
                break
            }
        }
        return flags
    }

    // MARK: - Deletion-line patterns

    private static func deletionRisks(for line: DiffLine) -> [DiffRiskFlag] {
        var flags: [DiffRiskFlag] = []
        let text = line.text
        let lineNum = line.oldLineNumber

        // Deleted error handling: catch or guard (Swift/Kotlin/Java)
        if containsErrorHandling(text) {
            flags.append(DiffRiskFlag(
                kind: .deletedErrorHandling,
                lineNumber: lineNum,
                description: "Deleted error handling: \(text.trimmingCharacters(in: .whitespaces).truncated(to: 60))"
            ))
        }

        // Deleted nil / guard check
        if containsNilCheck(text) {
            flags.append(DiffRiskFlag(
                kind: .deletedNilCheck,
                lineNumber: lineNum,
                description: "Deleted nil/guard check: \(text.trimmingCharacters(in: .whitespaces).truncated(to: 60))"
            ))
        }

        // Deleted test assertion
        if containsTestAssertion(text) {
            flags.append(DiffRiskFlag(
                kind: .deletedTestAssertion,
                lineNumber: lineNum,
                description: "Deleted test assertion: \(text.trimmingCharacters(in: .whitespaces).truncated(to: 60))"
            ))
        }

        return flags
    }

    // MARK: - Addition-line patterns

    private static func additionRisks(for line: DiffLine) -> [DiffRiskFlag] {
        var flags: [DiffRiskFlag] = []
        let text = line.text
        let lineNum = line.newLineNumber

        // Credential-like strings
        if containsCredential(text) {
            flags.append(DiffRiskFlag(
                kind: .credentialLike,
                lineNumber: lineNum,
                description: "Possible credential: \(text.trimmingCharacters(in: .whitespaces).truncated(to: 60))"
            ))
        }

        // Force-unwrap additions (Swift `!` suffix on non-comment lines)
        if containsForceUnwrap(text) {
            flags.append(DiffRiskFlag(
                kind: .forceUnwrap,
                lineNumber: lineNum,
                description: "Force-unwrap added: \(text.trimmingCharacters(in: .whitespaces).truncated(to: 60))"
            ))
        }

        // New TODO / HACK marker
        if containsTodoHack(text) {
            flags.append(DiffRiskFlag(
                kind: .todoHackMarker,
                lineNumber: lineNum,
                description: "TODO/HACK marker: \(text.trimmingCharacters(in: .whitespaces).truncated(to: 60))"
            ))
        }

        return flags
    }

    // MARK: - Pattern Helpers

    /// Matches `catch`, `rescue`, `except`, `on error` patterns (Swift/Ruby/Python/JS).
    private static func containsErrorHandling(_ text: String) -> Bool {
        let keywords = [#"\bcatch\b"#, #"\brescue\b"#, #"\bexcept\b"#, #"\bon\s+error\b"#]
        return keywords.contains { text.range(of: $0, options: .regularExpression) != nil }
    }

    /// Matches `== nil`, `!= nil`, `guard let`, `guard var`, `if let`, `if var`.
    private static func containsNilCheck(_ text: String) -> Bool {
        let patterns = [#"==\s*nil"#, #"!=\s*nil"#, #"\bguard\s+let\b"#, #"\bguard\s+var\b"#, #"\bif\s+let\b"#, #"\bif\s+var\b"#]
        return patterns.contains { text.range(of: $0, options: .regularExpression) != nil }
    }

    /// Matches XCTest / JUnit / pytest assertion calls.
    private static func containsTestAssertion(_ text: String) -> Bool {
        let patterns = [#"\bXCTAssert"#, #"\bassert\s*("#, #"\bAssert\."#, #"\bexpect\s*("#, #"\bshould\s*\("#]
        return patterns.contains { text.range(of: $0, options: .regularExpression) != nil }
    }

    /// Matches string literals or assignment values that look like credentials.
    private static func containsCredential(_ text: String) -> Bool {
        // Match: variable name containing password/secret/token/apikey/api_key = "..." or = '...'
        let pattern = #"(?i)(password|secret|token|api[_-]?key|access[_-]?key|private[_-]?key)\s*[=:]\s*["'][^"']{4,}["']"#
        return text.range(of: pattern, options: .regularExpression) != nil
    }

    /// Matches Swift force-unwrap: a `!` that is not part of `!=`, `!is`, or a comment prefix.
    private static func containsForceUnwrap(_ text: String) -> Bool {
        // Exclude lines that are purely comments
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("//") || trimmed.hasPrefix("*") { return false }
        // Look for `!` not followed by `=`, `!`, or whitespace-only tail (logical-not on standalone)
        let pattern = #"[A-Za-z0-9_\])\?]\!"#
        return text.range(of: pattern, options: .regularExpression) != nil
    }

    /// Matches TODO: or HACK: in newly added lines.
    private static func containsTodoHack(_ text: String) -> Bool {
        let pattern = #"(?i)\b(TODO|FIXME|HACK|XXX)\s*:"#
        return text.range(of: pattern, options: .regularExpression) != nil
    }
}

// MARK: - String helper

private extension String {
    /// Truncates the string to `maxLength` characters, appending "…" if truncated.
    func truncated(to maxLength: Int) -> String {
        guard count > maxLength else { return self }
        return String(prefix(maxLength)) + "…"
    }
}
