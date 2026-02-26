import Foundation

/// Resolves the test ↔ implementation counterpart for a source file using common
/// naming conventions across Swift, TypeScript, JavaScript, Python, Go, and Rust.
enum TestFileMatcher {

    // MARK: - Public API

    /// Returns `true` when `fileName` looks like a test file.
    static func isTestFile(_ fileName: String) -> Bool {
        candidateImplementationNames(for: fileName) != nil
    }

    /// Given the URL of the currently open file and the project root, returns the
    /// URL of the matching test / implementation file if one exists on disk.
    ///
    /// The search first looks in the same directory as `fileURL`, then expands to
    /// the whole project tree.
    static func counterpart(for fileURL: URL, in rootURL: URL) -> URL? {
        let fileName = fileURL.lastPathComponent
        let containingDir = fileURL.deletingLastPathComponent()

        let candidates: [String]
        if let impls = candidateImplementationNames(for: fileName) {
            candidates = impls
        } else if let tests = candidateTestNames(for: fileName) {
            candidates = tests
        } else {
            return nil
        }

        // 1. Same directory
        for candidate in candidates {
            let url = containingDir.appendingPathComponent(candidate)
            if FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }

        // 2. Walk the project tree (breadth-first, skipping hidden dirs)
        if let found = searchTree(rootURL: rootURL, candidates: Set(candidates),
                                  excluding: fileURL) {
            return found
        }

        return nil
    }

    // MARK: - Candidate name generation

    /// Returns candidate **implementation** file names for a given test file name,
    /// or `nil` when the file does not appear to be a test file.
    static func candidateImplementationNames(for fileName: String) -> [String]? {
        guard let dot = fileName.lastIndex(of: ".") else { return nil }
        let base = String(fileName[fileName.startIndex..<dot])
        let ext  = String(fileName[fileName.index(after: dot)...])

        switch ext {
        case "swift":
            // FooTests.swift, FooTest.swift, FooSpec.swift → Foo.swift
            for suffix in ["Tests", "Test", "Spec"] {
                if base.hasSuffix(suffix) {
                    let impl = String(base.dropLast(suffix.count))
                    if !impl.isEmpty {
                        return ["\(impl).swift"]
                    }
                }
            }
            return nil

        case "ts", "tsx", "js", "jsx":
            // bar.test.ts, bar.spec.ts → bar.ts
            for infix in [".test", ".spec"] {
                if base.hasSuffix(infix) {
                    let impl = String(base.dropLast(infix.count))
                    if !impl.isEmpty {
                        return ["\(impl).\(ext)"]
                    }
                }
            }
            return nil

        case "py":
            // test_baz.py → baz.py
            if base.hasPrefix("test_") {
                let impl = String(base.dropFirst(5))
                if !impl.isEmpty {
                    return ["\(impl).py"]
                }
            }
            // baz_test.py → baz.py
            if base.hasSuffix("_test") {
                let impl = String(base.dropLast(5))
                if !impl.isEmpty {
                    return ["\(impl).py"]
                }
            }
            return nil

        case "go":
            // foo_test.go → foo.go
            if base.hasSuffix("_test") {
                let impl = String(base.dropLast(5))
                if !impl.isEmpty {
                    return ["\(impl).go"]
                }
            }
            return nil

        case "rs":
            // foo_test.rs → foo.rs
            if base.hasSuffix("_test") {
                let impl = String(base.dropLast(5))
                if !impl.isEmpty {
                    return ["\(impl).rs"]
                }
            }
            return nil

        default:
            return nil
        }
    }

    /// Returns candidate **test** file names for a given implementation file name,
    /// or `nil` when the extension is not a supported language.
    static func candidateTestNames(for fileName: String) -> [String]? {
        guard let dot = fileName.lastIndex(of: ".") else { return nil }
        let base = String(fileName[fileName.startIndex..<dot])
        let ext  = String(fileName[fileName.index(after: dot)...])

        // Skip files that are already tests
        guard candidateImplementationNames(for: fileName) == nil else { return nil }

        switch ext {
        case "swift":
            return ["\(base)Tests.swift", "\(base)Test.swift", "\(base)Spec.swift"]

        case "ts", "tsx", "js", "jsx":
            return ["\(base).test.\(ext)", "\(base).spec.\(ext)"]

        case "py":
            return ["test_\(base).py", "\(base)_test.py"]

        case "go":
            return ["\(base)_test.go"]

        case "rs":
            return ["\(base)_test.rs"]

        default:
            return nil
        }
    }

    // MARK: - File-system search

    private static func searchTree(rootURL: URL, candidates: Set<String>,
                                   excluding excluded: URL) -> URL? {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }

        for case let url as URL in enumerator {
            // Skip hidden directories
            if let isDir = try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory,
               isDir == true {
                let name = url.lastPathComponent
                if name.hasPrefix(".") || name == "node_modules" || name == ".build" {
                    enumerator.skipDescendants()
                }
                continue
            }
            if url == excluded { continue }
            if candidates.contains(url.lastPathComponent) {
                return url
            }
        }
        return nil
    }
}
