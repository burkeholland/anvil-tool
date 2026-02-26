import XCTest
@testable import Anvil

final class ContextStoreTests: XCTestCase {

    // MARK: - Initial state

    func testPinnedPathsStartsEmpty() {
        let store = ContextStore()
        XCTAssertTrue(store.pinnedPaths.isEmpty)
    }

    // MARK: - add

    func testAddInsertsRelativePath() {
        let store = ContextStore()
        store.add(relativePath: "Sources/Foo.swift")
        XCTAssertEqual(store.pinnedPaths, ["Sources/Foo.swift"])
    }

    func testAddMultiplePathsPreservesOrder() {
        let store = ContextStore()
        store.add(relativePath: "a.swift")
        store.add(relativePath: "b.swift")
        store.add(relativePath: "c.swift")
        XCTAssertEqual(store.pinnedPaths, ["a.swift", "b.swift", "c.swift"])
    }

    func testAddDeduplicates() {
        let store = ContextStore()
        store.add(relativePath: "Sources/Foo.swift")
        store.add(relativePath: "Sources/Foo.swift")
        XCTAssertEqual(store.pinnedPaths.count, 1)
    }

    func testAddIgnoresEmptyString() {
        let store = ContextStore()
        store.add(relativePath: "")
        XCTAssertTrue(store.pinnedPaths.isEmpty)
    }

    // MARK: - remove

    func testRemoveDeletesPath() {
        let store = ContextStore()
        store.add(relativePath: "Sources/Foo.swift")
        store.remove(relativePath: "Sources/Foo.swift")
        XCTAssertTrue(store.pinnedPaths.isEmpty)
    }

    func testRemoveNonExistentIsNoop() {
        let store = ContextStore()
        store.add(relativePath: "Sources/Foo.swift")
        store.remove(relativePath: "Sources/Bar.swift")
        XCTAssertEqual(store.pinnedPaths.count, 1)
    }

    func testRemoveLeavesOtherPaths() {
        let store = ContextStore()
        store.add(relativePath: "a.swift")
        store.add(relativePath: "b.swift")
        store.add(relativePath: "c.swift")
        store.remove(relativePath: "b.swift")
        XCTAssertEqual(store.pinnedPaths, ["a.swift", "c.swift"])
    }

    // MARK: - contains

    func testContainsReturnsTrueForPinnedPath() {
        let store = ContextStore()
        store.add(relativePath: "Sources/Foo.swift")
        XCTAssertTrue(store.contains(relativePath: "Sources/Foo.swift"))
    }

    func testContainsReturnsFalseForUnpinnedPath() {
        let store = ContextStore()
        XCTAssertFalse(store.contains(relativePath: "Sources/Foo.swift"))
    }

    func testContainsReturnsFalseAfterRemove() {
        let store = ContextStore()
        store.add(relativePath: "Sources/Foo.swift")
        store.remove(relativePath: "Sources/Foo.swift")
        XCTAssertFalse(store.contains(relativePath: "Sources/Foo.swift"))
    }

    // MARK: - clear

    func testClearEmptiesPinnedPaths() {
        let store = ContextStore()
        store.add(relativePath: "a.swift")
        store.add(relativePath: "b.swift")
        XCTAssertFalse(store.pinnedPaths.isEmpty)
        store.clear()
        XCTAssertTrue(store.pinnedPaths.isEmpty)
    }

    func testClearOnEmptyIsIdempotent() {
        let store = ContextStore()
        store.clear()
        XCTAssertTrue(store.pinnedPaths.isEmpty)
    }

    func testClearThenAddWorks() {
        let store = ContextStore()
        store.add(relativePath: "a.swift")
        store.clear()
        store.add(relativePath: "b.swift")
        XCTAssertEqual(store.pinnedPaths, ["b.swift"])
    }
}
