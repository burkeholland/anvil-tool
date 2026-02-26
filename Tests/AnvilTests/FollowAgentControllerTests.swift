import XCTest
import Combine
@testable import Anvil

final class FollowAgentControllerTests: XCTestCase {

    func testReportChangeFiredAfterDebounce() {
        let controller = FollowAgentController(debounceInterval: 0.1)
        let expectation = XCTestExpectation(description: "Follow event published after debounce")
        var received: FollowEvent?

        let cancellable = controller.$followEvent
            .compactMap { $0 }
            .sink { event in
                received = event
                expectation.fulfill()
            }

        let url = URL(fileURLWithPath: "/tmp/test.swift")
        controller.reportChange(url)

        wait(for: [expectation], timeout: 1.0)
        XCTAssertEqual(received?.url, url)
        _ = cancellable
    }

    func testRapidChangesCoalescedToLastURL() {
        let controller = FollowAgentController(debounceInterval: 0.1)
        let expectation = XCTestExpectation(description: "Only last URL is followed after burst")
        expectation.expectedFulfillmentCount = 1

        var receivedURLs: [URL] = []
        let cancellable = controller.$followEvent
            .compactMap { $0 }
            .sink { event in
                receivedURLs.append(event.url)
                expectation.fulfill()
            }

        let url1 = URL(fileURLWithPath: "/tmp/first.swift")
        let url2 = URL(fileURLWithPath: "/tmp/second.swift")
        let url3 = URL(fileURLWithPath: "/tmp/third.swift")

        controller.reportChange(url1)
        controller.reportChange(url2)
        controller.reportChange(url3)

        wait(for: [expectation], timeout: 1.0)
        XCTAssertEqual(receivedURLs.count, 1, "Burst of changes should coalesce into a single follow event")
        XCTAssertEqual(receivedURLs.first, url3, "Should follow the last URL in a burst")
        _ = cancellable
    }

    func testCancelPreventsFollow() {
        let controller = FollowAgentController(debounceInterval: 0.1)
        var received: FollowEvent?

        let cancellable = controller.$followEvent
            .compactMap { $0 }
            .sink { event in
                received = event
            }

        controller.reportChange(URL(fileURLWithPath: "/tmp/test.swift"))
        controller.cancel()

        // Wait past the debounce interval
        let waitExp = XCTestExpectation(description: "Waiting past debounce")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            waitExp.fulfill()
        }
        wait(for: [waitExp], timeout: 1.0)

        XCTAssertNil(received, "Cancelled follow should not fire a follow event")
        _ = cancellable
    }

    func testFollowEventHasUniqueIDPerFire() {
        let controller = FollowAgentController(debounceInterval: 0.05)
        let url = URL(fileURLWithPath: "/tmp/test.swift")
        var events: [FollowEvent] = []
        let exp = XCTestExpectation(description: "Two separate follow events")
        exp.expectedFulfillmentCount = 2

        let cancellable = controller.$followEvent
            .compactMap { $0 }
            .sink { event in
                events.append(event)
                exp.fulfill()
            }

        controller.reportChange(url)
        // Wait for first debounce to fire, then report again
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            controller.reportChange(url)
        }

        wait(for: [exp], timeout: 1.5)
        XCTAssertEqual(events.count, 2)
        XCTAssertNotEqual(events[0].id, events[1].id, "Each follow event should have a unique ID")
        _ = cancellable
    }
}
