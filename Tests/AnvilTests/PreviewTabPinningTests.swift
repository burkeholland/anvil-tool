import XCTest
@testable import Anvil

final class PreviewTabPinningTests: XCTestCase {

    private func makeURL(_ name: String) -> URL {
        URL(fileURLWithPath: "/tmp/project/\(name)")
    }

    // MARK: - togglePinTab

    func testTogglePinTab_pinsThenUnpins() {
        let model = FilePreviewModel()
        let url = makeURL("a.swift")
        XCTAssertFalse(model.pinnedTabs.contains(url))

        model.togglePinTab(url)
        XCTAssertTrue(model.pinnedTabs.contains(url))

        model.togglePinTab(url)
        XCTAssertFalse(model.pinnedTabs.contains(url))
    }

    func testTogglePinTab_multipleTabs() {
        let model = FilePreviewModel()
        let a = makeURL("a.swift")
        let b = makeURL("b.swift")

        model.togglePinTab(a)
        model.togglePinTab(b)

        XCTAssertTrue(model.pinnedTabs.contains(a))
        XCTAssertTrue(model.pinnedTabs.contains(b))

        model.togglePinTab(a)
        XCTAssertFalse(model.pinnedTabs.contains(a))
        XCTAssertTrue(model.pinnedTabs.contains(b))
    }

    // MARK: - closeTab ignores pinned tabs

    func testCloseTab_pinnedTabIsNotRemoved() {
        let model = FilePreviewModel()
        let a = makeURL("a.swift")
        model.openTabsForTesting([a])
        model.togglePinTab(a)

        model.closeTab(a)

        XCTAssertTrue(model.openTabs.contains(a), "Pinned tab should not be removed by closeTab")
    }

    func testCloseTab_unpinnedTabIsRemoved() {
        let model = FilePreviewModel()
        let a = makeURL("a.swift")
        let b = makeURL("b.swift")
        model.openTabsForTesting([a, b])

        model.closeTab(a)

        XCTAssertFalse(model.openTabs.contains(a))
        XCTAssertTrue(model.openTabs.contains(b))
    }

    // MARK: - LRU eviction skips pinned tabs

    func testEviction_pinnedTabSurvivesLRUEviction() {
        let model = FilePreviewModel()
        // Fill tabs up to max (12) and pin one of the early ones
        let urls = (1...12).map { makeURL("file\($0).swift") }
        model.openTabsForTesting(urls)
        model.recentlyViewedURLsForTesting(urls.reversed()) // urls[0] is LRU

        // Pin the would-be-evicted tab
        model.togglePinTab(urls[0])

        // Trigger eviction by inserting one more tab
        let extra = makeURL("extra.swift")
        model.openTabsForTesting(urls + [extra])
        model.evictLRUTabIfNeededForTesting(keeping: extra)

        XCTAssertTrue(model.openTabs.contains(urls[0]), "Pinned tab should survive LRU eviction")
        // The second-LRU (urls[1]) should have been evicted instead
        XCTAssertFalse(model.openTabs.contains(urls[1]), "Second LRU unpinned tab should be evicted")
    }

    // MARK: - reorderTab

    func testReorderTab_movesTabForward() {
        let model = FilePreviewModel()
        let a = makeURL("a.swift")
        let b = makeURL("b.swift")
        let c = makeURL("c.swift")
        model.openTabsForTesting([a, b, c])

        model.reorderTab(fromOffsets: IndexSet(integer: 0), toOffset: 2)

        XCTAssertEqual(model.openTabs, [b, a, c])
    }

    func testReorderTab_movesTabBackward() {
        let model = FilePreviewModel()
        let a = makeURL("a.swift")
        let b = makeURL("b.swift")
        let c = makeURL("c.swift")
        model.openTabsForTesting([a, b, c])

        model.reorderTab(fromOffsets: IndexSet(integer: 2), toOffset: 0)

        XCTAssertEqual(model.openTabs, [c, a, b])
    }

    // MARK: - close clears pinnedTabs

    func testClose_clearsPinnedTabs() {
        let model = FilePreviewModel()
        let a = makeURL("a.swift")
        model.openTabsForTesting([a])
        model.togglePinTab(a)
        XCTAssertFalse(model.pinnedTabs.isEmpty)

        model.close(persist: false)

        XCTAssertTrue(model.pinnedTabs.isEmpty)
    }
}
