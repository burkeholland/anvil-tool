import XCTest
@testable import Anvil

final class FileTreeModelAgentTests: XCTestCase {

    // MARK: - markAgentReference

    func testMarkAgentReferenceAddsPath() {
        let model = FileTreeModel()
        let url = URL(fileURLWithPath: "/tmp/project/Sources/Foo.swift")
        model.markAgentReference(url)
        XCTAssertTrue(model.agentReferencedPaths.contains(url.standardizedFileURL.path))
    }

    func testMarkAgentReferenceDeduplicates() {
        let model = FileTreeModel()
        let url = URL(fileURLWithPath: "/tmp/project/Sources/Foo.swift")
        model.markAgentReference(url)
        model.markAgentReference(url)
        XCTAssertEqual(model.agentReferencedPaths.count, 1)
    }

    func testMarkAgentReferenceMultipleFiles() {
        let model = FileTreeModel()
        let url1 = URL(fileURLWithPath: "/tmp/project/Sources/Foo.swift")
        let url2 = URL(fileURLWithPath: "/tmp/project/Sources/Bar.swift")
        model.markAgentReference(url1)
        model.markAgentReference(url2)
        XCTAssertEqual(model.agentReferencedPaths.count, 2)
        XCTAssertTrue(model.agentReferencedPaths.contains(url1.standardizedFileURL.path))
        XCTAssertTrue(model.agentReferencedPaths.contains(url2.standardizedFileURL.path))
    }

    func testMarkAgentReferenceStandardizesPaths() {
        let model = FileTreeModel()
        // URL with a double slash component — standardizedFileURL normalizes it
        let url = URL(fileURLWithPath: "/tmp/project/./Sources/Foo.swift")
        model.markAgentReference(url)
        let standardPath = url.standardizedFileURL.path
        XCTAssertTrue(model.agentReferencedPaths.contains(standardPath))
    }

    // MARK: - clearAgentReferences

    func testClearAgentReferencesEmptiesSet() {
        let model = FileTreeModel()
        model.markAgentReference(URL(fileURLWithPath: "/tmp/project/Foo.swift"))
        model.markAgentReference(URL(fileURLWithPath: "/tmp/project/Bar.swift"))
        XCTAssertFalse(model.agentReferencedPaths.isEmpty)

        model.clearAgentReferences()
        XCTAssertTrue(model.agentReferencedPaths.isEmpty)
    }

    func testClearAgentReferencesOnEmptyIsIdempotent() {
        let model = FileTreeModel()
        model.clearAgentReferences()
        XCTAssertTrue(model.agentReferencedPaths.isEmpty)
    }

    func testClearAgentReferencesThenMarkWorks() {
        let model = FileTreeModel()
        let url = URL(fileURLWithPath: "/tmp/project/Foo.swift")
        model.markAgentReference(url)
        model.clearAgentReferences()
        model.markAgentReference(url)
        XCTAssertEqual(model.agentReferencedPaths.count, 1)
    }

    // MARK: - showAgentTouchedOnly initial state

    func testShowAgentTouchedOnlyDefaultsFalse() {
        let model = FileTreeModel()
        XCTAssertFalse(model.showAgentTouchedOnly)
    }

    func testAgentReferencedPathsStartsEmpty() {
        let model = FileTreeModel()
        XCTAssertTrue(model.agentReferencedPaths.isEmpty)
    }
}
