import Foundation

/// Clusters a flat list of `ChangedFile` into semantically related groups using:
/// 1. Temporal co-occurrence from an activity feed (files modified in the same burst).
/// 2. Path heuristics — same stem (component + its tests/types), same directory.
///
/// Each resulting group receives a short human-readable label and an SF Symbol icon.
enum SemanticGrouper {

    struct Group: Identifiable {
        let id: String   // derived from sorted file paths for stable identity
        let label: String
        let systemImage: String
        let files: [ChangedFile]
    }

    // MARK: - Public API

    /// Cluster `files` into semantic groups.
    ///
    /// - Parameters:
    ///   - files: The files to cluster (ordered by review priority or any preferred order).
    ///   - activityGroups: Activity groups from `ActivityFeedModel.groups`, used for
    ///     temporal co-occurrence.  Pass `[]` when no feed is available.
    static func group(
        files: [ChangedFile],
        activityGroups: [ActivityGroup]
    ) -> [Group] {
        guard !files.isEmpty else { return [] }

        // --- Step 1: build a co-occurrence graph from temporal activity ---
        // Two files are "related" if they appear in the same activity group.
        var coOccurrence: [String: Set<String>] = [:]  // relativePath → set of co-changed paths
        for ag in activityGroups {
            let paths = ag.events.map(\.path).filter { !$0.isEmpty }
            for path in paths {
                for other in paths where other != path {
                    coOccurrence[path, default: []].insert(other)
                }
            }
        }

        // --- Step 2: build a stem similarity table ---
        // Files with the same logical stem are placed together regardless of subdirectory.
        // e.g. "UserService.swift" and "UserServiceTests.swift" share stem "userservice".
        var stemMap: [String: [ChangedFile]] = [:]  // stem → files
        for file in files {
            let stem = logicalStem(of: file)
            stemMap[stem, default: []].append(file)
        }

        // --- Step 3: union-find clustering ---
        var parent: [String: String] = [:]
        for file in files { parent[file.relativePath] = file.relativePath }

        func find(_ x: String) -> String {
            var root = x
            while parent[root] != root { root = parent[root] ?? root }
            // Path compression
            var node = x
            while node != root {
                let next = parent[node] ?? root
                parent[node] = root
                node = next
            }
            return root
        }

        func union(_ a: String, _ b: String) {
            let ra = find(a), rb = find(b)
            guard ra != rb else { return }
            parent[ra] = rb
        }

        // Union by co-occurrence
        for (path, others) in coOccurrence {
            guard files.contains(where: { $0.relativePath == path }) else { continue }
            for other in others where files.contains(where: { $0.relativePath == other }) {
                union(path, other)
            }
        }

        // Union by stem
        for (_, stemFiles) in stemMap where stemFiles.count > 1 {
            for i in 1..<stemFiles.count {
                union(stemFiles[0].relativePath, stemFiles[i].relativePath)
            }
        }

        // Union by directory (only if ≤4 files in that directory; larger dirs stay separate)
        var dirFiles: [String: [ChangedFile]] = [:]
        for file in files { dirFiles[file.directoryPath, default: []].append(file) }
        for (_, dirGroup) in dirFiles where dirGroup.count > 1 && dirGroup.count <= 4 {
            for i in 1..<dirGroup.count {
                union(dirGroup[0].relativePath, dirGroup[i].relativePath)
            }
        }

        // --- Step 4: collect clusters ---
        var clusters: [String: [ChangedFile]] = [:]
        for file in files {
            let root = find(file.relativePath)
            clusters[root, default: []].append(file)
        }

        // Preserve the original file order within each cluster
        let fileOrder = Dictionary(uniqueKeysWithValues: files.enumerated().map { ($1.relativePath, $0) })
        var sortedClusters = clusters.values.map { group in
            group.sorted { (fileOrder[$0.relativePath] ?? 0) < (fileOrder[$1.relativePath] ?? 0) }
        }

        // Sort clusters by the first file's position in the original list
        sortedClusters.sort {
            (fileOrder[$0.first?.relativePath ?? ""] ?? 0) < (fileOrder[$1.first?.relativePath ?? ""] ?? 0)
        }

        // --- Step 5: generate labels ---
        return sortedClusters.map { clusterFiles in
            let label = makeLabel(for: clusterFiles)
            let icon  = makeIcon(for: clusterFiles)
            let id    = clusterFiles.map(\.relativePath).sorted().joined(separator: "|")
            return Group(id: id, label: label, systemImage: icon, files: clusterFiles)
        }
    }

    // MARK: - Helpers

    /// Computes a "logical stem" for a file used to detect related pairs.
    /// Strips common test/spec suffixes and the file extension.
    static func logicalStem(of file: ChangedFile) -> String {
        let baseName = (file.fileName as NSString).deletingPathExtension.lowercased()
        let testSuffixes = ["tests", "test", "spec", "specs", "mock", "mocks", "stub", "stubs",
                            "_test", "_spec", "_mock", ".test", ".spec"]
        for suffix in testSuffixes {
            if baseName.hasSuffix(suffix) {
                let trimmed = String(baseName.dropLast(suffix.count))
                if !trimmed.isEmpty { return trimmed }
            }
        }
        return baseName
    }

    /// Generates a human-readable label for a group of files.
    private static func makeLabel(for files: [ChangedFile]) -> String {
        guard !files.isEmpty else { return "Files" }

        // Single file: use its name
        if files.count == 1 {
            return files[0].fileName
        }

        // Check if all files share the same stem (component + test/types pattern)
        let stems = Set(files.map { logicalStem(of: $0) })
        if stems.count == 1, let stem = stems.first {
            let capitalized = stem.prefix(1).uppercased() + stem.dropFirst()
            return "\(capitalized) (\(files.count) files)"
        }

        // Check if all files share the same directory
        let dirs = Set(files.map(\.directoryPath))
        if dirs.count == 1, let dir = dirs.first {
            let leaf = dir.isEmpty ? "Root" : (dir as NSString).lastPathComponent
            return "\(leaf) (\(files.count) files)"
        }

        // Find the longest common directory prefix
        if let prefix = commonDirectoryPrefix(of: files), !prefix.isEmpty {
            let leaf = (prefix as NSString).lastPathComponent
            return "\(leaf) (\(files.count) files)"
        }

        // Describe by kinds present
        let hasSource = files.contains { !isTestFile($0) && !isConfigFile($0) && !isDocFile($0) }
        let hasTest   = files.contains { isTestFile($0) }
        let hasConfig = files.contains { isConfigFile($0) }
        let hasDoc    = files.contains { isDocFile($0) }

        var parts: [String] = []
        if hasSource { parts.append("Source") }
        if hasTest   { parts.append("Tests") }
        if hasConfig { parts.append("Config") }
        if hasDoc    { parts.append("Docs") }

        let kindLabel = parts.isEmpty ? "Mixed" : parts.joined(separator: " + ")
        return "\(kindLabel) (\(files.count) files)"
    }

    /// Returns an SF Symbol name for a group.
    private static func makeIcon(for files: [ChangedFile]) -> String {
        let hasTest   = files.contains { isTestFile($0) }
        let hasConfig = files.contains { isConfigFile($0) }
        let hasDoc    = files.contains { isDocFile($0) }
        let hasSource = files.contains { !isTestFile($0) && !isConfigFile($0) && !isDocFile($0) }

        switch (hasSource, hasTest, hasConfig, hasDoc) {
        case (_, true, false, false): return "testtube.2"
        case (false, false, true, false): return "gearshape.fill"
        case (false, false, false, true): return "doc.text.fill"
        case (true, true, _, _): return "square.and.pencil"
        default: return "folder.fill"
        }
    }

    /// Finds the longest directory path that is a prefix of all files' paths.
    private static func commonDirectoryPrefix(of files: [ChangedFile]) -> String? {
        guard files.count > 1 else { return files.first?.directoryPath }
        let dirComponents = files.map { ($0.directoryPath as NSString).pathComponents }
        guard let first = dirComponents.first else { return nil }
        var common: [String] = []
        for (index, component) in first.enumerated() {
            if dirComponents.allSatisfy({ index < $0.count && $0[index] == component }) {
                common.append(component)
            } else {
                break
            }
        }
        return common.isEmpty ? nil : NSString.path(withComponents: common)
    }

    private static func isTestFile(_ file: ChangedFile) -> Bool {
        ReviewPriorityScorer.isTestFile(file.relativePath)
    }

    private static func isConfigFile(_ file: ChangedFile) -> Bool {
        let name = file.fileName.lowercased()
        let ext  = (file.fileName as NSString).pathExtension.lowercased()
        let configExtensions: Set<String> = ["json", "yaml", "yml", "toml", "lock", "env", "ini", "cfg", "conf"]
        let configNames: Set<String> = [
            ".gitignore", ".gitattributes", ".editorconfig", ".eslintrc", ".prettierrc",
            ".babelrc", ".swiftlint.yml", "makefile", "dockerfile", "package.json",
            "tsconfig.json", "jest.config.js", "vite.config.ts", "webpack.config.js",
        ]
        return configExtensions.contains(ext) || configNames.contains(name)
    }

    private static func isDocFile(_ file: ChangedFile) -> Bool {
        let name = file.fileName.lowercased()
        let ext  = (file.fileName as NSString).pathExtension.lowercased()
        let docExtensions: Set<String> = ["md", "rst", "txt", "adoc"]
        let docPrefixes = ["readme", "changelog", "license", "contributing", "authors", "notice"]
        return docExtensions.contains(ext) || docPrefixes.contains(where: { name.hasPrefix($0) })
    }
}
