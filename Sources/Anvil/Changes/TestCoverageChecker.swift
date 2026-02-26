import Foundation

/// Determines which implementation files in a changeset have test counterparts
/// also present in the same changeset.
///
/// Uses `TestFileMatcher` naming conventions to map implementation files to their
/// expected test file names, then checks whether any of those names appear among
/// the other changed files. No filesystem access is required.
enum TestCoverageChecker {

    // MARK: - Types

    /// Coverage status for a single changed file.
    enum TestCoverage: Equatable {
        /// An implementation file whose test counterpart is also in the changeset.
        case covered
        /// An implementation file with no test counterpart in the changeset.
        case uncovered
        /// A test file, config file, or file type where test coverage is not tracked.
        case notApplicable
    }

    // MARK: - Public API

    /// Returns a map from each changed file's URL to its `TestCoverage` status.
    ///
    /// Only implementation files for supported languages (Swift, TypeScript,
    /// JavaScript, Python, Go, Rust) can receive `.covered` or `.uncovered`.
    /// All other files (test files, configs, docs) get `.notApplicable`.
    static func coverage(for files: [ChangedFile]) -> [URL: TestCoverage] {
        let changedNames = Set(files.map { $0.url.lastPathComponent })
        var result: [URL: TestCoverage] = [:]

        for file in files {
            let fileName = file.url.lastPathComponent

            if TestFileMatcher.isTestFile(fileName) {
                result[file.url] = .notApplicable
                continue
            }

            guard let candidates = TestFileMatcher.candidateTestNames(for: fileName) else {
                result[file.url] = .notApplicable
                continue
            }

            let hasCoverage = candidates.contains { changedNames.contains($0) }
            result[file.url] = hasCoverage ? .covered : .uncovered
        }

        return result
    }

    /// Returns `(covered, total)` counts for implementation files in a coverage map,
    /// where `total` is the number of files with status `.covered` or `.uncovered`.
    static func stats(from map: [URL: TestCoverage]) -> (covered: Int, total: Int) {
        var covered = 0
        var total = 0
        for status in map.values {
            switch status {
            case .covered:       covered += 1; total += 1
            case .uncovered:     total += 1
            case .notApplicable: break
            }
        }
        return (covered, total)
    }
}
