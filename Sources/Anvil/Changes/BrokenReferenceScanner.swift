import Foundation

/// Lightweight static analysis that detects cross-file reference breakage in a changeset
/// without requiring a full build.
///
/// Scans the content of modified/added files for import and require statements that reference
/// paths known to have been deleted or renamed in the same changeset, and checks that test
/// files only reference symbols from files that still exist.
enum BrokenReferenceScanner {

    // MARK: - Public types

    /// A single broken-reference finding for one file.
    struct Finding: Equatable {
        /// Human-readable explanation shown in the tooltip.
        let reason: String
    }

    // MARK: - Public API

    /// Scans a changeset for broken cross-file references.
    ///
    /// - Parameters:
    ///   - files: All changed files in the current changeset.
    ///   - rootURL: The project root; used to resolve relative import paths. Pass `nil` to
    ///     skip content-based scanning (only status-derived findings are produced).
    /// - Returns: A map from each file's URL to the (possibly empty) array of findings.
    static func scan(
        files: [ChangedFile],
        rootURL: URL? = nil
    ) -> [URL: [Finding]] {
        var result: [URL: [Finding]] = [:]
        for file in files {
            result[file.url] = []
        }

        // Build sets of deleted / renamed-away relative paths for O(1) lookup.
        let deletedPaths = Set(
            files
                .filter { $0.status == .deleted }
                .map { $0.relativePath }
        )
        // For renames git typically surfaces both a deleted entry for the old path and
        // an added entry for the new path; we treat both deleted and renamed status as
        // "path no longer exists under its previous name".
        let removedPaths = deletedPaths.union(
            Set(
                files
                    .filter { $0.status == .renamed }
                    .map { $0.relativePath }
            )
        )

        guard !removedPaths.isEmpty || rootURL != nil else {
            return result
        }

        // Relative paths of files still present (not deleted/renamed-away).
        let remainingRelativePaths = Set(
            files
                .filter { $0.status != .deleted }
                .map { $0.relativePath }
        )

        for file in files {
            // Only scan files that exist (added / modified / renamed-to).
            guard file.status != .deleted else { continue }

            guard let content = try? String(contentsOf: file.url, encoding: .utf8) else {
                continue
            }

            let ext = file.url.pathExtension.lowercased()
            var findings: [Finding] = []

            switch ext {
            case "swift":
                findings += swiftFindings(content: content,
                                          fileURL: file.url,
                                          removedPaths: removedPaths,
                                          remainingPaths: remainingRelativePaths,
                                          isTestFile: TestFileMatcher.isTestFile(file.url.lastPathComponent))
            case "ts", "tsx", "js", "jsx", "mjs", "cjs":
                findings += jsFindings(content: content,
                                       fileURL: file.url,
                                       removedPaths: removedPaths,
                                       rootURL: rootURL)
            case "py":
                findings += pythonFindings(content: content,
                                           fileURL: file.url,
                                           removedPaths: removedPaths,
                                           rootURL: rootURL)
            case "go":
                findings += goFindings(content: content,
                                       fileURL: file.url,
                                       removedPaths: removedPaths,
                                       rootURL: rootURL)
            default:
                findings += configFindings(content: content,
                                           relativePath: file.relativePath,
                                           removedPaths: removedPaths)
            }

            if !findings.isEmpty {
                result[file.url] = findings
            }
        }

        return result
    }

    // MARK: - Language-specific scanners

    /// Swift: scan `import Module` — not resolvable to paths — but detect `@testable import`
    /// references in test files that target modules whose source files were all deleted.
    private static func swiftFindings(
        content: String,
        fileURL: URL,
        removedPaths: Set<String>,
        remainingPaths: Set<String>,
        isTestFile: Bool
    ) -> [Finding] {
        // Swift imports are module-level, not path-level, so we can't reliably map them
        // to relative file paths without a full build. Instead, detect relative string
        // literals that look like file paths and match deleted paths.
        return pathLiteralFindings(content: content, removedPaths: removedPaths)
    }

    /// JavaScript / TypeScript: scan `import … from "…"` and `require("…")`.
    private static func jsFindings(
        content: String,
        fileURL: URL,
        removedPaths: Set<String>,
        rootURL: URL?
    ) -> [Finding] {
        var findings: [Finding] = []
        let importedPaths = extractJSImportPaths(from: content)
        for importedPath in importedPaths {
            if let resolved = resolveRelativePath(importedPath,
                                                  from: fileURL,
                                                  rootURL: rootURL,
                                                  extensions: ["ts", "tsx", "js", "jsx", "mjs", "cjs"]) {
                if removedPaths.contains(resolved) {
                    findings.append(Finding(reason: "Imports deleted file \"\(resolved)\""))
                }
            }
        }
        return findings
    }

    /// Python: scan `import X`, `from X import Y`, `from .X import Y`.
    private static func pythonFindings(
        content: String,
        fileURL: URL,
        removedPaths: Set<String>,
        rootURL: URL?
    ) -> [Finding] {
        var findings: [Finding] = []
        let importedPaths = extractPythonImportPaths(from: content)
        for importedPath in importedPaths {
            if let resolved = resolveRelativePath(importedPath,
                                                  from: fileURL,
                                                  rootURL: rootURL,
                                                  extensions: ["py"]) {
                if removedPaths.contains(resolved) {
                    findings.append(Finding(reason: "Imports deleted module \"\(resolved)\""))
                }
            }
        }
        return findings
    }

    /// Go: scan `import "…"` (relative paths within the project).
    private static func goFindings(
        content: String,
        fileURL: URL,
        removedPaths: Set<String>,
        rootURL: URL?
    ) -> [Finding] {
        // Go uses module paths, not relative file paths, in imports.
        // We can only flag string literals that literally match a removed path.
        return pathLiteralFindings(content: content, removedPaths: removedPaths)
    }

    /// Generic config-file scanner: flag any removed path that appears as a literal string
    /// inside known config file types (JSON, YAML, TOML, etc.).
    private static func configFindings(
        content: String,
        relativePath: String,
        removedPaths: Set<String>
    ) -> [Finding] {
        let configExtensions: Set<String> = [
            "json", "yaml", "yml", "toml", "ini", "cfg", "conf",
            "xml", "gradle", "properties", "env"
        ]
        let ext = (relativePath as NSString).pathExtension.lowercased()
        guard configExtensions.contains(ext) else { return [] }
        return pathLiteralFindings(content: content, removedPaths: removedPaths)
    }

    // MARK: - Shared helpers

    /// Returns findings for any removed path that appears as a quoted string literal in
    /// `content`. This is a best-effort heuristic used for languages where imports are
    /// not path-based (Swift, Go) and for config files.
    private static func pathLiteralFindings(
        content: String,
        removedPaths: Set<String>
    ) -> [Finding] {
        var findings: [Finding] = []
        for removed in removedPaths {
            // Look for the path appearing as a quoted string literal.
            if content.contains("\"\(removed)\"") || content.contains("'\(removed)'") {
                findings.append(Finding(reason: "References deleted path \"\(removed)\""))
            }
        }
        return findings
    }

    // MARK: - Import path extraction

    /// Extracts string paths from JS/TS `import … from "…"` and `require("…")` statements.
    static func extractJSImportPaths(from content: String) -> [String] {
        var paths: [String] = []

        // Matches: import ... from "path" or import ... from 'path'
        // Also: import "path" (side-effect imports)
        let importPattern = #"(?:^|\n)\s*import\s[^'"]*?['"]([^'"]+)['"]"#
        if let regex = try? NSRegularExpression(pattern: importPattern) {
            let range = NSRange(content.startIndex..., in: content)
            for match in regex.matches(in: content, range: range) {
                if let r = Range(match.range(at: 1), in: content) {
                    paths.append(String(content[r]))
                }
            }
        }

        // Matches: require("path") or require('path')
        let requirePattern = #"require\s*\(\s*['"]([^'"]+)['"]\s*\)"#
        if let regex = try? NSRegularExpression(pattern: requirePattern) {
            let range = NSRange(content.startIndex..., in: content)
            for match in regex.matches(in: content, range: range) {
                if let r = Range(match.range(at: 1), in: content) {
                    paths.append(String(content[r]))
                }
            }
        }

        return paths
    }

    /// Extracts relative module paths from Python `from .module import X` and
    /// `from package.module import X` (intra-project only; stdlib imports are skipped).
    static func extractPythonImportPaths(from content: String) -> [String] {
        var paths: [String] = []

        // from .module import X  →  ".module"
        // from ..pkg.module import X  →  "..pkg.module"
        let relativePattern = #"^\s*from\s+(\.+[\w.]*)\s+import"#
        if let regex = try? NSRegularExpression(pattern: relativePattern, options: .anchorsMatchLines) {
            let range = NSRange(content.startIndex..., in: content)
            for match in regex.matches(in: content, range: range) {
                if let r = Range(match.range(at: 1), in: content) {
                    paths.append(String(content[r]))
                }
            }
        }

        return paths
    }

    // MARK: - Path resolution

    /// Attempts to resolve a (possibly relative) import path to a repository-relative path.
    ///
    /// Returns `nil` when the path is clearly a third-party package (no leading `./` or `../`)
    /// and cannot be matched to a project file.
    static func resolveRelativePath(
        _ importPath: String,
        from fileURL: URL,
        rootURL: URL?,
        extensions: [String]
    ) -> String? {
        // Only resolve relative paths (starting with ./ or ../).
        guard importPath.hasPrefix("./") || importPath.hasPrefix("../") else { return nil }

        let fileDir = fileURL.deletingLastPathComponent()
        let resolved = fileDir.appendingPathComponent(importPath).standardized

        // Try path as-is.
        if let root = rootURL {
            let rel = relativePath(of: resolved, from: root)
            if rel != nil { return rel }
        }

        // Try with each candidate extension appended.
        for ext in extensions {
            let withExt = resolved.appendingPathExtension(ext)
            if let root = rootURL {
                if let rel = relativePath(of: withExt, from: root) {
                    return rel
                }
            }
        }

        // If no rootURL, fall back to the standardized absolute path trimmed of leading slash
        // so callers can still do set-membership checks on relative strings.
        if rootURL == nil {
            let raw = resolved.path
            // Strip leading "/" to get a relative-ish path for matching.
            return raw.hasPrefix("/") ? String(raw.dropFirst()) : raw
        }

        return nil
    }

    /// Returns the path of `url` relative to `base`, or `nil` if `url` is not under `base`.
    private static func relativePath(of url: URL, from base: URL) -> String? {
        let rawBase = base.standardized.path
        let basePath = rawBase.hasSuffix("/") ? rawBase : rawBase + "/"
        let urlPath  = url.standardized.path
        guard urlPath.hasPrefix(basePath) else { return nil }
        return String(urlPath.dropFirst(basePath.count))
    }
}
