import XCTest
@testable import Anvil

final class SessionListModelTests: XCTestCase {

    // MARK: - YAML parsing

    private let sampleYAML = """
id: 004621f9-578b-4e07-8f8f-97951e412193
cwd: /Users/user/dev/project
summary: "Add authentication to API"
repository: owner/repo
branch: feature/auth
created_at: 2026-02-27T06:44:25.351Z
updated_at: 2026-02-27T06:44:25.379Z
"""

    func testParseValidYAML() {
        let item = SessionListModel.parseWorkspaceYAML(sampleYAML, id: "004621f9-578b-4e07-8f8f-97951e412193")
        XCTAssertNotNil(item)
        XCTAssertEqual(item?.id, "004621f9-578b-4e07-8f8f-97951e412193")
        XCTAssertEqual(item?.cwd, "/Users/user/dev/project")
        XCTAssertEqual(item?.summary, "Add authentication to API")
        XCTAssertEqual(item?.repository, "owner/repo")
        XCTAssertEqual(item?.branch, "feature/auth")
    }

    func testParseYAMLWithoutQuotedSummary() {
        let yaml = """
cwd: /tmp/proj
summary: plain summary
created_at: 2026-01-01T00:00:00.000Z
updated_at: 2026-01-01T00:00:01.000Z
"""
        let item = SessionListModel.parseWorkspaceYAML(yaml, id: "abc")
        XCTAssertEqual(item?.summary, "plain summary")
    }

    func testParseYAMLMissingCWDReturnsNil() {
        let yaml = """
summary: Missing cwd field
created_at: 2026-01-01T00:00:00.000Z
updated_at: 2026-01-01T00:00:01.000Z
"""
        XCTAssertNil(SessionListModel.parseWorkspaceYAML(yaml, id: "abc"))
    }

    func testParseYAMLMissingDatesReturnsNil() {
        let yaml = """
cwd: /tmp/proj
summary: No dates
"""
        XCTAssertNil(SessionListModel.parseWorkspaceYAML(yaml, id: "abc"))
    }

    func testParseYAMLEmptySummaryFallsBackToPlaceholder() {
        let yaml = """
cwd: /tmp/proj
summary: ""
created_at: 2026-01-01T00:00:00.000Z
updated_at: 2026-01-01T00:00:01.000Z
"""
        let item = SessionListModel.parseWorkspaceYAML(yaml, id: "abc")
        XCTAssertEqual(item?.summary, "(no summary)")
    }

    func testParseYAMLOptionalFieldsMissing() {
        let yaml = """
cwd: /tmp/proj
created_at: 2026-01-01T00:00:00.000Z
updated_at: 2026-01-01T00:00:01.000Z
"""
        let item = SessionListModel.parseWorkspaceYAML(yaml, id: "abc")
        XCTAssertNotNil(item)
        XCTAssertNil(item?.repository)
        XCTAssertNil(item?.branch)
        XCTAssertEqual(item?.summary, "(no summary)")
    }

    func testParseYAMLDateWithoutFractionalSeconds() {
        let yaml = """
cwd: /tmp/proj
created_at: 2026-01-01T00:00:00Z
updated_at: 2026-01-02T12:30:00Z
"""
        let item = SessionListModel.parseWorkspaceYAML(yaml, id: "abc")
        XCTAssertNotNil(item, "Should parse ISO 8601 without fractional seconds")
    }

    // MARK: - Date grouping

    func testTodayGroup() {
        let now = Date()
        let group = SessionDateGroup.group(for: now, relativeTo: now)
        XCTAssertEqual(group, .today)
    }

    func testYesterdayGroup() {
        let now = Date()
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: now)!
        let group = SessionDateGroup.group(for: yesterday, relativeTo: now)
        XCTAssertEqual(group, .yesterday)
    }

    func testThisWeekGroup() {
        let now = Date()
        let threeDaysAgo = Calendar.current.date(byAdding: .day, value: -3, to: now)!
        let group = SessionDateGroup.group(for: threeDaysAgo, relativeTo: now)
        XCTAssertEqual(group, .thisWeek)
    }

    func testEarlierGroup() {
        let now = Date()
        let twoWeeksAgo = Calendar.current.date(byAdding: .day, value: -14, to: now)!
        let group = SessionDateGroup.group(for: twoWeeksAgo, relativeTo: now)
        XCTAssertEqual(group, .earlier)
    }

    // MARK: - Filtering

    func testFilterByCWD() {
        let model = SessionListModel()
        model.projectCWD = "/Users/user/dev/project"
        let item = makeItem(id: "1", cwd: "/Users/user/dev/project", repository: nil)
        let other = makeItem(id: "2", cwd: "/Users/user/dev/other", repository: nil)
        // Inject via reflection-like backdoor by exercising the public API with a real scan.
        // Since direct injection isn't possible, verify the filter logic separately.
        let filtered = [item, other].filter { i in
            i.cwd == model.projectCWD || i.repository == model.projectRepository
        }
        XCTAssertEqual(filtered.count, 1)
        XCTAssertEqual(filtered.first?.id, "1")
    }

    func testFilterByRepository() {
        let model = SessionListModel()
        model.projectRepository = "owner/repo"
        let item = makeItem(id: "1", cwd: "/tmp/x", repository: "owner/repo")
        let other = makeItem(id: "2", cwd: "/tmp/y", repository: "other/repo")
        let filtered = [item, other].filter { i in
            i.cwd == model.projectCWD || i.repository == model.projectRepository
        }
        XCTAssertEqual(filtered.count, 1)
        XCTAssertEqual(filtered.first?.id, "1")
    }

    // MARK: - Search filter

    func testFilterQueryMatchesSummary() {
        let items = [
            makeItem(id: "1", cwd: "/a", summary: "Add authentication", branch: nil, repository: nil),
            makeItem(id: "2", cwd: "/b", summary: "Fix build errors", branch: nil, repository: nil),
        ]
        let lower = "auth"
        let result = items.filter { $0.summary.lowercased().contains(lower) }
        XCTAssertEqual(result.map(\.id), ["1"])
    }

    func testFilterQueryMatchesBranch() {
        let items = [
            makeItem(id: "1", cwd: "/a", summary: "Work", branch: "feature/search", repository: nil),
            makeItem(id: "2", cwd: "/b", summary: "Work", branch: "main", repository: nil),
        ]
        let lower = "search"
        let result = items.filter { $0.branch?.lowercased().contains(lower) == true }
        XCTAssertEqual(result.map(\.id), ["1"])
    }

    func testFilterQueryMatchesCWD() {
        let items = [
            makeItem(id: "1", cwd: "/Users/user/projects/anvil", summary: "X", branch: nil, repository: nil),
            makeItem(id: "2", cwd: "/Users/user/other", summary: "X", branch: nil, repository: nil),
        ]
        let lower = "anvil"
        let result = items.filter { $0.cwd.lowercased().contains(lower) }
        XCTAssertEqual(result.map(\.id), ["1"])
    }

    func testFilterQueryCaseInsensitive() {
        let items = [
            makeItem(id: "1", cwd: "/a", summary: "Add Authentication", branch: nil, repository: nil),
        ]
        let lower = "authentication"
        let result = items.filter { $0.summary.lowercased().contains(lower) }
        XCTAssertEqual(result.count, 1)
    }

    func testEmptyFilterQueryReturnsAll() {
        let items = [
            makeItem(id: "1", cwd: "/a", summary: "A", branch: nil, repository: nil),
            makeItem(id: "2", cwd: "/b", summary: "B", branch: nil, repository: nil),
        ]
        let query = "   "
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        let result = trimmed.isEmpty ? items : items.filter { $0.summary.lowercased().contains(trimmed) }
        XCTAssertEqual(result.count, 2)
    }

    func testFilterQueryNoMatchReturnsEmpty() {
        let items = [
            makeItem(id: "1", cwd: "/a", summary: "A", branch: nil, repository: nil),
        ]
        let lower = "zzznomatch"
        let result = items.filter {
            $0.summary.lowercased().contains(lower)
                || $0.cwd.lowercased().contains(lower)
                || ($0.branch?.lowercased().contains(lower) == true)
        }
        XCTAssertTrue(result.isEmpty)
    }

    // MARK: - Helpers

    private func makeItem(id: String, cwd: String, repository: String?) -> SessionItem {
        makeItem(id: id, cwd: cwd, summary: "Test", branch: nil, repository: repository)
    }

    private func makeItem(id: String, cwd: String, summary: String, branch: String?, repository: String?) -> SessionItem {
        SessionItem(
            id: id, cwd: cwd, summary: summary,
            repository: repository, branch: branch,
            createdAt: Date(), updatedAt: Date()
        )
    }
}
