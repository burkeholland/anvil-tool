import XCTest
import Combine
@testable import Anvil

final class DiffToastControllerTests: XCTestCase {

    // MARK: - Initial state

    func testInitialStateIsEmpty() {
        let controller = DiffToastController(displayDuration: 60)
        XCTAssertTrue(controller.toasts.isEmpty)
    }

    // MARK: - Enqueue / dismiss

    func testEnqueueAddsToast() {
        let controller = DiffToastController(displayDuration: 60)
        controller._testEnqueue(makeItem())
        XCTAssertEqual(controller.toasts.count, 1)
    }

    func testDismissRemovesToast() {
        let controller = DiffToastController(displayDuration: 60)
        let item = makeItem()
        controller._testEnqueue(item)
        XCTAssertEqual(controller.toasts.count, 1)

        controller.dismiss(id: item.id)
        XCTAssertTrue(controller.toasts.isEmpty)
    }

    func testDismissAllClearsStack() {
        let controller = DiffToastController(displayDuration: 60)
        controller._testEnqueue(makeItem())
        controller._testEnqueue(makeItem())
        controller._testEnqueue(makeItem())
        XCTAssertEqual(controller.toasts.count, 3)

        controller.dismissAll()
        XCTAssertTrue(controller.toasts.isEmpty)
    }

    // MARK: - Deduplication

    func testDuplicateFileURLReplacesExistingToast() {
        let controller = DiffToastController(displayDuration: 60)
        let url = URL(fileURLWithPath: "/tmp/foo.swift")
        let item1 = makeItem(url: url)
        let item2 = makeItem(url: url)

        controller._testEnqueue(item1)
        XCTAssertEqual(controller.toasts.count, 1)
        XCTAssertEqual(controller.toasts.first?.id, item1.id)

        controller._testEnqueue(item2)
        XCTAssertEqual(controller.toasts.count, 1, "Second toast for same file should replace first")
        XCTAssertEqual(controller.toasts.first?.id, item2.id)
    }

    // MARK: - Stack cap

    func testStackCapEvictsOldest() {
        let controller = DiffToastController(displayDuration: 60)
        var items: [DiffToastItem] = []
        for i in 0..<6 {
            let item = makeItem(url: URL(fileURLWithPath: "/tmp/file\(i).swift"))
            items.append(item)
            controller._testEnqueue(item)
        }
        XCTAssertLessThanOrEqual(controller.toasts.count, 5, "Stack should be capped at 5")
        XCTAssertFalse(controller.toasts.contains(where: { $0.id == items[0].id }),
                       "Oldest toast should be evicted when stack overflows")
    }

    // MARK: - Auto-dismiss

    func testAutoDismissAfterDuration() {
        let controller = DiffToastController(displayDuration: 0.1)
        controller._testEnqueue(makeItem())
        XCTAssertEqual(controller.toasts.count, 1)

        let exp = XCTestExpectation(description: "Auto-dismiss after timeout")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            XCTAssertTrue(controller.toasts.isEmpty, "Toast should auto-dismiss after displayDuration")
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1.0)
    }

    // MARK: - Helpers

    private func makeItem(url: URL = URL(fileURLWithPath: "/tmp/test.swift")) -> DiffToastItem {
        DiffToastItem(
            id: UUID(),
            fileURL: url,
            fileName: url.lastPathComponent,
            relativePath: url.lastPathComponent,
            diff: nil,
            createdAt: Date()
        )
    }
}

