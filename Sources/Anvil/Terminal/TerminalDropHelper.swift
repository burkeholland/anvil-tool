import Foundation

/// Utility helpers for handling file drag-and-drop onto the terminal.
/// Functions are `internal` so they can be covered by unit tests.
enum TerminalDropHelper {

    /// Returns the project-relative path for `url` when possible, otherwise
    /// returns the absolute path.  Correctly handles root paths that do or do
    /// not end with a trailing slash.
    static func projectRelativePath(for url: URL, rootURL: URL?) -> String {
        guard let rootURL = rootURL else { return url.path }
        let rootPath = rootURL.standardizedFileURL.path
        let filePath = url.standardizedFileURL.path
        let rootPrefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        if filePath.hasPrefix(rootPrefix) {
            return String(filePath.dropFirst(rootPrefix.count))
        }
        return url.path
    }

    /// Shell special characters that require the path to be single-quoted.
    static let shellSpecialChars: Set<Character> = [
        " ", "\t", "\n", "!", "\"", "#", "$", "&", "'",
        "(", ")", "*", ",", ";", "<", "=", ">", "?",
        "[", "\\", "]", "^", "`", "{", "|", "}", "~"
    ]

    /// Single-quotes `path` for safe shell use when it contains special
    /// characters.  Embedded single-quotes are escaped using the `'\''`
    /// idiom recognised by all POSIX-compatible shells.
    static func shellEscapePath(_ path: String) -> String {
        guard path.contains(where: { shellSpecialChars.contains($0) }) else { return path }
        let escaped = path.replacingOccurrences(of: "'", with: "'\\''")
        return "'\(escaped)'"
    }

    /// Strips C0/DEL control characters from `path` to prevent terminal
    /// injection before the path is sent to the shell.
    static func sanitizePath(_ path: String) -> String {
        String(path.unicodeScalars
            .filter { $0.value >= 0x20 && $0 != "\u{7F}" }
            .map { Character($0) })
    }
}
