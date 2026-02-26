import XCTest
@testable import Anvil

final class AgentModeWatcherTests: XCTestCase {
    let watcher = AgentModeWatcher()

    // MARK: - detectMode: prompt-style markers

    func testInteractiveParenthesesMarker() {
        XCTAssertEqual(watcher.detectMode(in: "copilot (interactive) >"), .interactive)
    }

    func testInteractiveBracketMarker() {
        XCTAssertEqual(watcher.detectMode(in: "[interactive] prompt"), .interactive)
    }

    func testAskParenthesesMarker() {
        XCTAssertEqual(watcher.detectMode(in: "copilot (ask) >"), .interactive)
    }

    func testAskBracketMarker() {
        XCTAssertEqual(watcher.detectMode(in: "[ask]"), .interactive)
    }

    func testPlanParenthesesMarker() {
        XCTAssertEqual(watcher.detectMode(in: "copilot (plan) >"), .plan)
    }

    func testPlanBracketMarker() {
        XCTAssertEqual(watcher.detectMode(in: "[plan]"), .plan)
    }

    func testAutopilotParenthesesMarker() {
        XCTAssertEqual(watcher.detectMode(in: "copilot (autopilot) >"), .autopilot)
    }

    func testAutopilotBracketMarker() {
        XCTAssertEqual(watcher.detectMode(in: "[autopilot]"), .autopilot)
    }

    func testAgentParenthesesMarker() {
        XCTAssertEqual(watcher.detectMode(in: "copilot (agent) >"), .autopilot)
    }

    func testAgentBracketMarker() {
        XCTAssertEqual(watcher.detectMode(in: "[agent]"), .autopilot)
    }

    // MARK: - detectMode: status lines

    func testModeInteractiveStatusLine() {
        XCTAssertEqual(watcher.detectMode(in: "mode: interactive"), .interactive)
    }

    func testModeAskStatusLine() {
        XCTAssertEqual(watcher.detectMode(in: "Mode: ask"), .interactive)
    }

    func testModePlanStatusLine() {
        XCTAssertEqual(watcher.detectMode(in: "Current mode: plan"), .plan)
    }

    func testModeAutopilotStatusLine() {
        XCTAssertEqual(watcher.detectMode(in: "mode: autopilot"), .autopilot)
    }

    func testModeAgentStatusLine() {
        XCTAssertEqual(watcher.detectMode(in: "mode: agent"), .autopilot)
    }

    // MARK: - detectMode: transition lines

    func testSwitchedToInteractive() {
        XCTAssertEqual(watcher.detectMode(in: "Switched to interactive mode"), .interactive)
    }

    func testSwitchedToAsk() {
        XCTAssertEqual(watcher.detectMode(in: "Switched to ask mode"), .interactive)
    }

    func testSwitchedToPlan() {
        XCTAssertEqual(watcher.detectMode(in: "Switched to plan mode"), .plan)
    }

    func testSwitchedToAutopilot() {
        XCTAssertEqual(watcher.detectMode(in: "Switched to autopilot mode"), .autopilot)
    }

    func testSwitchedToAgent() {
        XCTAssertEqual(watcher.detectMode(in: "Switched to agent mode"), .autopilot)
    }

    // MARK: - detectMode: non-matching lines

    func testRandomOutputReturnsNil() {
        XCTAssertNil(watcher.detectMode(in: "Reading files from disk..."))
    }

    func testEmptyLineReturnsNil() {
        XCTAssertNil(watcher.detectMode(in: ""))
    }

    func testCodeLineReturnsNil() {
        XCTAssertNil(watcher.detectMode(in: "if condition { return true }"))
    }

    // MARK: - detectModel

    func testModelColon() {
        XCTAssertEqual(watcher.detectModel(in: "model: gpt-4.1"), "gpt-4.1")
    }

    func testModelColonUppercase() {
        XCTAssertEqual(watcher.detectModel(in: "Model: gpt-4o"), "gpt-4o")
    }

    func testUsingModelPrefix() {
        XCTAssertEqual(watcher.detectModel(in: "Using model: o3"), "o3")
    }

    func testUsingModelNoSpace() {
        XCTAssertEqual(watcher.detectModel(in: "using model:claude-3.5-sonnet"), "claude-3.5-sonnet")
    }

    func testModelWithTrailingPunctuation() {
        XCTAssertEqual(watcher.detectModel(in: "model: gpt-4.1,"), "gpt-4.1")
    }

    func testModelWithTrailingPeriod() {
        XCTAssertEqual(watcher.detectModel(in: "model: o1."), "o1")
    }

    func testNoModelReturnsNil() {
        XCTAssertNil(watcher.detectModel(in: "Reading files from disk..."))
    }

    func testEmptyLineModelReturnsNil() {
        XCTAssertNil(watcher.detectModel(in: ""))
    }

    // MARK: - AgentMode helpers

    func testAgentModeNextCycles() {
        XCTAssertEqual(AgentMode.interactive.next, .plan)
        XCTAssertEqual(AgentMode.plan.next, .autopilot)
        XCTAssertEqual(AgentMode.autopilot.next, .interactive)
    }

    func testAgentModeDisplayNames() {
        XCTAssertEqual(AgentMode.interactive.displayName, "Interactive")
        XCTAssertEqual(AgentMode.plan.displayName, "Plan")
        XCTAssertEqual(AgentMode.autopilot.displayName, "Autopilot")
    }

    func testAgentModeActivateCommands() {
        XCTAssertEqual(AgentMode.interactive.activateCommand, "/agent interactive\n")
        XCTAssertEqual(AgentMode.plan.activateCommand, "/agent plan\n")
        XCTAssertEqual(AgentMode.autopilot.activateCommand, "/agent autopilot\n")
    }
}
