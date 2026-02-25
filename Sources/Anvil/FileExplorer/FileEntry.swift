import SwiftUI
import Foundation

struct FileEntry: Identifiable {
    let url: URL
    let name: String
    let isDirectory: Bool
    let depth: Int

    var id: URL { url }

    var icon: String {
        if isDirectory { return "folder.fill" }
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "swift":                       return "swift"
        case "js", "ts", "jsx", "tsx":      return "curlybraces"
        case "json":                        return "curlybraces.square"
        case "md", "txt", "rtf":            return "doc.text"
        case "py":                          return "chevron.left.forwardslash.chevron.right"
        case "sh", "bash", "zsh":           return "terminal"
        case "png", "jpg", "jpeg", "gif", "svg": return "photo"
        case "yml", "yaml", "toml":         return "gearshape"
        default:                            return "doc"
        }
    }

    var iconColor: Color {
        if isDirectory { return .accentColor }
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "swift":                       return .orange
        case "js", "jsx":                   return .yellow
        case "ts", "tsx":                   return .blue
        case "json":                        return .green
        case "md", "txt":                   return .secondary
        case "py":                          return .cyan
        default:                            return .secondary
        }
    }

    /// Hidden directories and files that clutter the file tree
    private static let hiddenPrefixes: Set<String> = [".git", ".build", ".DS_Store", ".swiftpm"]

    static func loadChildren(of url: URL, depth: Int = 0) -> [FileEntry] {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return contents
            .filter { !hiddenPrefixes.contains($0.lastPathComponent) }
            .sorted { lhs, rhs in
                let lhsIsDir = (try? lhs.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                let rhsIsDir = (try? rhs.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                if lhsIsDir != rhsIsDir { return lhsIsDir }
                return lhs.lastPathComponent.localizedStandardCompare(rhs.lastPathComponent) == .orderedAscending
            }
            .map { childURL in
                let isDir = (try? childURL.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                return FileEntry(
                    url: childURL,
                    name: childURL.lastPathComponent,
                    isDirectory: isDir,
                    depth: depth
                )
            }
    }
}
