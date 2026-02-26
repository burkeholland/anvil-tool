import XCTest
@testable import Anvil

final class PromptMarkerStoreTests: XCTestCase {

    func testAddMarkerAppendsInOrder() {
        let store = PromptMarkerStore()
        store.addMarker(text: "first prompt", anchorYDisp: 10)
        store.addMarker(text: "second prompt", anchorYDisp: 20)

        XCTAssertEqual(store.markers.count, 2)
        XCTAssertEqual(store.markers[0].text, "first prompt")
        XCTAssertEqual(store.markers[0].anchorYDisp, 10)
        XCTAssertEqual(store.markers[1].text, "second prompt")
        XCTAssertEqual(store.markers[1].anchorYDisp, 20)
    }

    func testAddMarkerTrimsWhitespace() {
        let store = PromptMarkerStore()
        store.addMarker(text: "  hello world  ", anchorYDisp: 5)

        XCTAssertEqual(store.markers.count, 1)
        XCTAssertEqual(store.markers[0].text, "hello world")
    }

    func testAddMarkerIgnoresEmptyText() {
        let store = PromptMarkerStore()
        store.addMarker(text: "", anchorYDisp: 0)
        store.addMarker(text: "   ", anchorYDisp: 0)

        XCTAssertEqual(store.markers.count, 0)
    }

    func testClearRemovesAllMarkers() {
        let store = PromptMarkerStore()
        store.addMarker(text: "prompt one", anchorYDisp: 10)
        store.addMarker(text: "prompt two", anchorYDisp: 20)
        XCTAssertEqual(store.markers.count, 2)

        store.clear()
        XCTAssertEqual(store.markers.count, 0)
    }

    func testMarkerIdsAreUnique() {
        let store = PromptMarkerStore()
        store.addMarker(text: "same text", anchorYDisp: 0)
        store.addMarker(text: "same text", anchorYDisp: 0)

        let ids = store.markers.map { $0.id }
        XCTAssertNotEqual(ids[0], ids[1])
    }

    func testMarkerDateIsSet() {
        let before = Date()
        let store = PromptMarkerStore()
        store.addMarker(text: "dated prompt", anchorYDisp: 0)
        let after = Date()

        XCTAssertGreaterThanOrEqual(store.markers[0].date, before)
        XCTAssertLessThanOrEqual(store.markers[0].date, after)
    }

    func testClearOnEmptyStoreIsIdempotent() {
        let store = PromptMarkerStore()
        store.clear()
        XCTAssertEqual(store.markers.count, 0)
    }
}
