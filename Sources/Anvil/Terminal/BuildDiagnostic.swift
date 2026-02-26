import Foundation

/// Severity level of a build diagnostic entry.
enum DiagnosticSeverity: String {
    case error
    case warning
    case note
}

/// A single structured diagnostic produced by a build tool.
struct BuildDiagnostic: Identifiable {
    let id = UUID()
    /// File path as reported by the build tool (may be relative or absolute).
    let filePath: String
    /// 1-based line number.
    let line: Int
    /// 1-based column number, or nil if not reported.
    let column: Int?
    let severity: DiagnosticSeverity
    let message: String
}

/// Parses raw build output from multiple build tool formats into
/// structured ``BuildDiagnostic`` entries.
///
/// Supported formats:
/// - Swift / swiftc / GCC / Clang:  `path:line:col: severity: message`
/// - TypeScript / tsc:              `path(line,col): error TSxxxx: message`
/// - Cargo / rustc:                 `error[Exxxx]: message\n --> path:line:col`
enum BuildDiagnosticParser {

    /// Parse all lines of combined build output and return structured diagnostics.
    /// Only entries with a resolvable file location are returned.
    static func parse(_ output: String) -> [BuildDiagnostic] {
        let lines = output.components(separatedBy: "\n")
        var result: [BuildDiagnostic] = []
        // Rust emits the message on one line then the file location on the next.
        var pendingRust: (severity: DiagnosticSeverity, message: String)?

        for line in lines {
            // 1. Swift / GCC / Clang:  /path/to/file.swift:10:5: error: message
            if let d = matchSwiftGCC(line) {
                result.append(d)
                pendingRust = nil
                continue
            }

            // 2. TypeScript / tsc:  /path/to/file.ts(10,5): error TS2345: message
            if let d = matchTypeScript(line) {
                result.append(d)
                pendingRust = nil
                continue
            }

            // 3a. Cargo/rustc message header:  error[E0308]: mismatched types
            if let pair = matchRustHeader(line) {
                pendingRust = pair
                continue
            }

            // 3b. Cargo/rustc location arrow:   --> src/main.rs:10:5
            if let pending = pendingRust,
               let d = matchRustArrow(line, severity: pending.severity, message: pending.message) {
                result.append(d)
                pendingRust = nil
                continue
            }

            // Any non-blank, non-continuation line resets a pending Rust header.
            if pendingRust != nil {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty && !trimmed.hasPrefix("-->") && !trimmed.hasPrefix("= ") {
                    pendingRust = nil
                }
            }
        }

        return result
    }

    // MARK: - Compiled patterns

    // Swift/GCC/Clang:  path:line:col: error|warning|note: message
    private static let reSwiftGCC = try! NSRegularExpression(
        pattern: #"^(.+?):(\d+):(\d+):\s*(error|warning|note):\s*(.+)$"#
    )

    // TypeScript/tsc:  path(line,col): error|warning TSxxxx: message
    private static let reTypeScript = try! NSRegularExpression(
        pattern: #"^(.+?)\((\d+),(\d+)\):\s*(error|warning)\s+\S+:\s*(.+)$"#
    )

    // Cargo/rustc message header:  error[E0308]: msg  OR  warning: msg
    private static let reRustHeader = try! NSRegularExpression(
        pattern: #"^(error|warning)(?:\[E\d+\])?:\s*(.+)$"#
    )

    // Cargo/rustc file location:   --> src/file.rs:10:5
    private static let reRustArrow = try! NSRegularExpression(
        pattern: #"^\s+-->\s+(.+?):(\d+):(\d+)$"#
    )

    // MARK: - Matchers

    private static func matchSwiftGCC(_ line: String) -> BuildDiagnostic? {
        guard let m = reSwiftGCC.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              m.numberOfRanges == 6 else { return nil }
        guard let fp   = group(line, m, 1),
              let lnS  = group(line, m, 2),
              let colS = group(line, m, 3),
              let sevS = group(line, m, 4),
              let msg  = group(line, m, 5),
              let ln   = Int(lnS), ln > 0,
              let col  = Int(colS) else { return nil }
        return BuildDiagnostic(filePath: fp, line: ln, column: col,
                               severity: DiagnosticSeverity(rawValue: sevS) ?? .error,
                               message: msg)
    }

    private static func matchTypeScript(_ line: String) -> BuildDiagnostic? {
        guard let m = reTypeScript.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              m.numberOfRanges == 6 else { return nil }
        guard let fp   = group(line, m, 1),
              let lnS  = group(line, m, 2),
              let colS = group(line, m, 3),
              let sevS = group(line, m, 4),
              let msg  = group(line, m, 5),
              let ln   = Int(lnS), ln > 0,
              let col  = Int(colS) else { return nil }
        return BuildDiagnostic(filePath: fp, line: ln, column: col,
                               severity: DiagnosticSeverity(rawValue: sevS) ?? .error,
                               message: msg)
    }

    private static func matchRustHeader(_ line: String) -> (DiagnosticSeverity, String)? {
        guard let m = reRustHeader.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              m.numberOfRanges == 3 else { return nil }
        guard let sevS = group(line, m, 1),
              let msg  = group(line, m, 2) else { return nil }
        return (DiagnosticSeverity(rawValue: sevS) ?? .error, msg)
    }

    private static func matchRustArrow(_ line: String, severity: DiagnosticSeverity, message: String) -> BuildDiagnostic? {
        guard let m = reRustArrow.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              m.numberOfRanges == 4 else { return nil }
        guard let fp   = group(line, m, 1),
              let lnS  = group(line, m, 2),
              let colS = group(line, m, 3),
              let ln   = Int(lnS), ln > 0,
              let col  = Int(colS) else { return nil }
        return BuildDiagnostic(filePath: fp, line: ln, column: col,
                               severity: severity, message: message)
    }

    /// Extracts the string for capture group `index` from a regex match.
    private static func group(_ s: String, _ m: NSTextCheckingResult, _ index: Int) -> String? {
        let r = m.range(at: index)
        guard r.location != NSNotFound, let range = Range(r, in: s) else { return nil }
        return String(s[range])
    }
}
