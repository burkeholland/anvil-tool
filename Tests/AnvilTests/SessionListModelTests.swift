import XCTest
@testable import Anvil

final class SessionListModelTests: XCTestCase {

    // MARK: - Initial state

    func testInitialStateIsEmpty() {
        let model = SessionListModel()
        XCTAssertTrue(model.sessions.isEmpty)
        XCTAssertFalse(model.isLoading)
        XCTAssertNil(model.errorMessage)
    }

    // MARK: - openSession callback

    func testOpenSessionFiresCallback() {
        let model = SessionListModel()
        var receivedID: String?
        model.onOpenSession = { id in receivedID = id }

        let session = CopilotSession(id: "abc-123", title: "My Session", date: nil)
        model.openSession(session)

        XCTAssertEqual(receivedID, "abc-123")
    }

    func testOpenSessionWithNoCallbackIsNoop() {
        let model = SessionListModel()
        model.onOpenSession = nil
        let session = CopilotSession(id: "abc-123", title: nil, date: nil)
        // Should not crash
        model.openSession(session)
    }

    // MARK: - openNewSession callback

    func testOpenNewSessionFiresCallback() {
        let model = SessionListModel()
        var newSessionCalled = false
        model.onNewSession = { newSessionCalled = true }

        model.openNewSession()

        XCTAssertTrue(newSessionCalled)
    }

    func testOpenNewSessionWithNoCallbackIsNoop() {
        let model = SessionListModel()
        model.onNewSession = nil
        // Should not crash
        model.openNewSession()
    }
}

// MARK: - CopilotSession

final class CopilotSessionTests: XCTestCase {

    func testDisplayTitleUsesTitle() {
        let session = CopilotSession(id: "abc-123", title: "My Session", date: nil)
        XCTAssertEqual(session.displayTitle, "My Session")
    }

    func testDisplayTitleFallsBackToIDWhenTitleNil() {
        let session = CopilotSession(id: "abc-123", title: nil, date: nil)
        XCTAssertEqual(session.displayTitle, "abc-123")
    }

    func testDisplayTitleFallsBackToIDWhenTitleEmpty() {
        let session = CopilotSession(id: "abc-123", title: "", date: nil)
        XCTAssertEqual(session.displayTitle, "abc-123")
    }

    func testDecodeSessionWithAllFields() throws {
        let json = """
        [{"id":"abc-123","title":"Test Session","date":"2024-01-15T10:30:00Z"}]
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let sessions = try decoder.decode([CopilotSession].self, from: json)

        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions[0].id, "abc-123")
        XCTAssertEqual(sessions[0].title, "Test Session")
        XCTAssertNotNil(sessions[0].date)
    }

    func testDecodeSessionWithMissingOptionalFields() throws {
        let json = """
        [{"id":"abc-123"}]
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let sessions = try decoder.decode([CopilotSession].self, from: json)

        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions[0].id, "abc-123")
        XCTAssertNil(sessions[0].title)
        XCTAssertNil(sessions[0].date)
    }

    func testDecodeEmptyArray() throws {
        let json = "[]".data(using: .utf8)!
        let decoder = JSONDecoder()
        let sessions = try decoder.decode([CopilotSession].self, from: json)
        XCTAssertTrue(sessions.isEmpty)
    }
}

// MARK: - TerminalTabsModel resume session

final class TerminalTabsResumeSessionTests: XCTestCase {

    func testAddResumeSessionTabCreatesNewTab() {
        let model = TerminalTabsModel(autoLaunchCopilot: false)
        let initialCount = model.tabs.count

        model.addResumeSessionTab(sessionID: "session-1")

        XCTAssertEqual(model.tabs.count, initialCount + 1)
        XCTAssertEqual(model.tabs.last?.resumeSessionID, "session-1")
        XCTAssertTrue(model.tabs.last?.launchCopilot == true)
    }

    func testAddResumeSessionTabActivatesNewTab() {
        let model = TerminalTabsModel(autoLaunchCopilot: false)

        model.addResumeSessionTab(sessionID: "session-1")

        XCTAssertEqual(model.activeTabID, model.tabs.last?.id)
    }

    func testAddResumeSessionTabDeduplicatesSwitchesToExisting() {
        let model = TerminalTabsModel(autoLaunchCopilot: false)
        model.addResumeSessionTab(sessionID: "session-1")
        let existingTabID = model.tabs.last!.id
        let tabCountAfterFirst = model.tabs.count

        // Switch to a different tab so we can verify the switch-back
        model.addTab()
        XCTAssertNotEqual(model.activeTabID, existingTabID)

        // Now try to open the same session again — should switch, not create
        model.addResumeSessionTab(sessionID: "session-1")

        XCTAssertEqual(model.tabs.count, tabCountAfterFirst + 1) // shell tab still there, no new session tab
        XCTAssertEqual(model.activeTabID, existingTabID)
    }

    func testActiveSessionIDsReflectsOpenTabs() {
        let model = TerminalTabsModel(autoLaunchCopilot: false)

        model.addResumeSessionTab(sessionID: "session-1")
        model.addResumeSessionTab(sessionID: "session-2")

        XCTAssertTrue(model.activeSessionIDs.contains("session-1"))
        XCTAssertTrue(model.activeSessionIDs.contains("session-2"))
        XCTAssertFalse(model.activeSessionIDs.contains("session-3"))
    }

    func testActiveSessionIDsExcludesTabsWithNoSessionID() {
        let model = TerminalTabsModel(autoLaunchCopilot: true)
        // The default tab has no resumeSessionID
        XCTAssertTrue(model.activeSessionIDs.isEmpty)
    }

    func testActiveSessionIDsUpdatesAfterCloseTab() {
        let model = TerminalTabsModel(autoLaunchCopilot: false)
        model.addResumeSessionTab(sessionID: "session-1")
        let tabID = model.tabs.last!.id
        model.addTab() // ensure >1 tab so close is allowed

        model.closeTab(tabID)

        XCTAssertFalse(model.activeSessionIDs.contains("session-1"))
    }

    func testResumeTabHasCopilotTrue() {
        let model = TerminalTabsModel(autoLaunchCopilot: false)
        let tab = model.addResumeSessionTab(sessionID: "session-abc")
        XCTAssertTrue(tab.launchCopilot)
    }

    func testTerminalTabStoresResumeSessionID() {
        let tab = TerminalTab(id: UUID(), title: "Copilot", launchCopilot: true, defaultTitle: "Copilot", resumeSessionID: "my-session")
        XCTAssertEqual(tab.resumeSessionID, "my-session")
    }

    func testTerminalTabDefaultResumeSessionIDIsNil() {
        let tab = TerminalTab(id: UUID(), title: "Copilot", launchCopilot: true, defaultTitle: "Copilot")
        XCTAssertNil(tab.resumeSessionID)
    }
}
