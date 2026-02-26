import XCTest
@testable import Anvil

final class SemanticGrouperTests: XCTestCase {

    // MARK: - Helpers

    private func makeFile(path: String, status: GitFileStatus = .modified) -> ChangedFile {
        let url = URL(fileURLWithPath: "/tmp/project/\(path)")
        return ChangedFile(url: url, relativePath: path, status: status, staging: .unstaged)
    }

    private func makeActivityGroup(paths: [String]) -> ActivityGroup {
        let base = Date(timeIntervalSince1970: 1_000_000)
        let events = paths.map { path in
            ActivityEvent(
                id: UUID(),
                timestamp: base,
                kind: .fileModified,
                path: path,
                fileURL: URL(fileURLWithPath: "/tmp/project/\(path)"),
                diffStats: nil
            )
        }
        return ActivityGroup(id: UUID(), timestamp: base, events: events)
    }

    // MARK: - logicalStem

    func testLogicalStemStripsTestSuffix() {
        let file = makeFile(path: "Tests/UserServiceTests.swift")
        XCTAssertEqual(SemanticGrouper.logicalStem(of: file), "userservice")
    }

    func testLogicalStemStripsSpecSuffix() {
        let file = makeFile(path: "spec/user_spec.rb")
        XCTAssertEqual(SemanticGrouper.logicalStem(of: file), "user")
    }

    func testLogicalStemPreservesSourceFile() {
        let file = makeFile(path: "Sources/Anvil/ContentView.swift")
        XCTAssertEqual(SemanticGrouper.logicalStem(of: file), "contentview")
    }

    func testLogicalStemStripsTestDotPrefix() {
        let file = makeFile(path: "src/Button.test.ts")
        // After lowercasing: "button.test" → strips ".test" suffix → "button"
        // Note: the stem stripping works on the base name without extension first.
        // "Button.test" → pathExtension "ts" stripped → "Button.test"
        // then lowercased: "button.test", suffix ".test" stripped → "button"
        XCTAssertEqual(SemanticGrouper.logicalStem(of: file), "button")
    }

    // MARK: - group: empty / single file

    func testEmptyFilesReturnsEmpty() {
        let result = SemanticGrouper.group(files: [], activityGroups: [])
        XCTAssertTrue(result.isEmpty)
    }

    func testSingleFileReturnsOneGroup() {
        let files = [makeFile(path: "Sources/Anvil/Foo.swift")]
        let groups = SemanticGrouper.group(files: files, activityGroups: [])
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].files.count, 1)
    }

    // MARK: - group: stem grouping

    func testStemGroupsComponentWithItsTest() {
        let files = [
            makeFile(path: "Sources/Anvil/UserService.swift"),
            makeFile(path: "Tests/AnvilTests/UserServiceTests.swift"),
        ]
        let groups = SemanticGrouper.group(files: files, activityGroups: [])
        // Both files should be in the same group
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].files.count, 2)
    }

    func testDistinctStemsProduceSeparateGroups() {
        let files = [
            makeFile(path: "Sources/Foo.swift"),
            makeFile(path: "Sources/Bar.swift"),
        ]
        let groups = SemanticGrouper.group(files: files, activityGroups: [])
        // Each file has a distinct stem and they're in the same directory (≤4 files) →
        // directory heuristic groups them together
        XCTAssertEqual(groups.count, 1)
    }

    func testStemGroupingWithTypeFile() {
        let files = [
            makeFile(path: "Sources/Anvil/Button.swift"),
            makeFile(path: "Sources/Anvil/ButtonTests.swift"),
            makeFile(path: "Sources/Anvil/ButtonStyles.swift"),
        ]
        // Button + ButtonTests share stem "button"; ButtonStyles has stem "buttonstyles"
        // All are in same directory (≤4) so directory heuristic also merges them
        let groups = SemanticGrouper.group(files: files, activityGroups: [])
        XCTAssertEqual(groups.count, 1, "All three should be in one group")
    }

    // MARK: - group: temporal co-occurrence

    func testTemporalCoOccurrenceGroupsFiles() {
        let fileA = makeFile(path: "Sources/A.swift")
        let fileB = makeFile(path: "Sources/B.swift")
        let fileC = makeFile(path: "Sources/C.swift")
        let fileD = makeFile(path: "Sources/D.swift")
        let fileE = makeFile(path: "Sources/E.swift")

        // A, B, C were co-modified in one burst; D, E in another
        let ag1 = makeActivityGroup(paths: ["Sources/A.swift", "Sources/B.swift", "Sources/C.swift"])
        let ag2 = makeActivityGroup(paths: ["Sources/D.swift", "Sources/E.swift"])

        let groups = SemanticGrouper.group(files: [fileA, fileB, fileC, fileD, fileE],
                                           activityGroups: [ag1, ag2])
        // Expect 2 clusters: {A,B,C} and {D,E}
        XCTAssertEqual(groups.count, 2)
        let sizes = groups.map(\.files.count).sorted()
        XCTAssertEqual(sizes, [2, 3])
    }

    // MARK: - group: label generation

    func testLabelUsesFilenameForSingleFile() {
        let files = [makeFile(path: "Sources/Anvil/ContentView.swift")]
        let groups = SemanticGrouper.group(files: files, activityGroups: [])
        XCTAssertEqual(groups[0].label, "ContentView.swift")
    }

    func testLabelUsesStemForMatchingPair() {
        let files = [
            makeFile(path: "Sources/Anvil/Auth.swift"),
            makeFile(path: "Tests/AnvilTests/AuthTests.swift"),
        ]
        let groups = SemanticGrouper.group(files: files, activityGroups: [])
        XCTAssertEqual(groups.count, 1)
        // Stem "auth" → "Auth (2 files)"
        XCTAssertEqual(groups[0].label, "Auth (2 files)")
    }

    func testLabelUsesDirectoryForSameDirGroup() {
        let files = [
            makeFile(path: "Sources/Networking/Foo.swift"),
            makeFile(path: "Sources/Networking/Bar.swift"),
        ]
        let groups = SemanticGrouper.group(files: files, activityGroups: [])
        XCTAssertEqual(groups.count, 1)
        XCTAssertTrue(groups[0].label.contains("Networking"), "Label should contain directory name")
    }

    // MARK: - group: original order preserved

    func testOriginalFileOrderPreserved() {
        let paths = ["Sources/A.swift", "Sources/B.swift", "Sources/C.swift"]
        let files = paths.map { makeFile(path: $0) }
        let ag = makeActivityGroup(paths: paths)
        let groups = SemanticGrouper.group(files: files, activityGroups: [ag])
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].files.map(\.relativePath), paths)
    }

    // MARK: - group: large directory not auto-merged

    func testLargeDirectoryNotAutoMerged() {
        // 5 files in the same directory — exceeds the auto-merge threshold of ≤4
        let files = (1...5).map { makeFile(path: "Sources/Big/File\($0).swift") }
        let groups = SemanticGrouper.group(files: files, activityGroups: [])
        // Each file should be its own group because neither stem nor co-occurrence merges them
        XCTAssertEqual(groups.count, 5)
    }
}
