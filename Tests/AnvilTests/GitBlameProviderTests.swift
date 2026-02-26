import XCTest
@testable import Anvil

final class GitBlameProviderTests: XCTestCase {

    func testParsePorcelainSingleCommit() {
        let porcelain = """
        abc1234567890abcdef1234567890abcdef123456 1 1 3
        author Alice
        author-mail <alice@example.com>
        author-time 1700000000
        author-tz +0000
        committer Alice
        committer-mail <alice@example.com>
        committer-time 1700000000
        committer-tz +0000
        summary Initial commit
        filename hello.txt
        \tline one
        abc1234567890abcdef1234567890abcdef123456 2 2
        \tline two
        abc1234567890abcdef1234567890abcdef123456 3 3
        \tline three
        """

        let result = GitBlameProvider.parsePorcelain(porcelain)

        XCTAssertEqual(result.count, 3)

        // All lines from same commit
        XCTAssertEqual(result[0].sha, "abc1234567890abcdef1234567890abcdef123456")
        XCTAssertEqual(result[0].shortSHA, "abc12345")
        XCTAssertEqual(result[0].author, "Alice")
        XCTAssertEqual(result[0].summary, "Initial commit")
        XCTAssertEqual(result[0].lineNumber, 1)

        XCTAssertEqual(result[1].lineNumber, 2)
        XCTAssertEqual(result[1].sha, result[0].sha)

        XCTAssertEqual(result[2].lineNumber, 3)
    }

    func testParsePorcelainMultipleCommits() {
        let porcelain = """
        aaaa000000000000000000000000000000000000 1 1 1
        author Alice
        author-mail <alice@example.com>
        author-time 1700000000
        author-tz +0000
        committer Alice
        committer-mail <alice@example.com>
        committer-time 1700000000
        committer-tz +0000
        summary First commit
        filename test.swift
        \tfunc hello() {
        bbbb111111111111111111111111111111111111 2 2 1
        author Bob
        author-mail <bob@example.com>
        author-time 1700100000
        author-tz +0000
        committer Bob
        committer-mail <bob@example.com>
        committer-time 1700100000
        committer-tz +0000
        summary Second commit
        filename test.swift
        \t    print("hello")
        aaaa000000000000000000000000000000000000 3 3
        \t}
        """

        let result = GitBlameProvider.parsePorcelain(porcelain)

        XCTAssertEqual(result.count, 3)
        XCTAssertEqual(result[0].author, "Alice")
        XCTAssertEqual(result[0].summary, "First commit")
        XCTAssertEqual(result[0].lineNumber, 1)

        XCTAssertEqual(result[1].author, "Bob")
        XCTAssertEqual(result[1].summary, "Second commit")
        XCTAssertEqual(result[1].lineNumber, 2)

        // Third line reuses Alice's commit (no full header)
        XCTAssertEqual(result[2].author, "Alice")
        XCTAssertEqual(result[2].lineNumber, 3)
    }

    func testUncommittedLine() {
        let porcelain = """
        0000000000000000000000000000000000000000 1 1 1
        author Not Committed Yet
        author-mail <not.committed.yet>
        author-time 1700200000
        author-tz +0000
        committer Not Committed Yet
        committer-mail <not.committed.yet>
        committer-time 1700200000
        committer-tz +0000
        summary Not Yet Committed
        filename new.txt
        \tnew content
        """

        let result = GitBlameProvider.parsePorcelain(porcelain)

        XCTAssertEqual(result.count, 1)
        XCTAssertTrue(result[0].isUncommitted)
        XCTAssertEqual(result[0].author, "Not Committed Yet")
    }

    func testEmptyInput() {
        let result = GitBlameProvider.parsePorcelain("")
        XCTAssertTrue(result.isEmpty)
    }

    // MARK: - Tooltip content properties

    func testCommittedLineTooltipFields() {
        // The blame gutter tooltip for committed lines uses shortSHA, author, summary, and date.
        let porcelain = """
        cccc222222222222222222222222222222222222 1 1 1
        author Carol
        author-mail <carol@example.com>
        author-time 1704067200
        author-tz +0000
        committer Carol
        committer-mail <carol@example.com>
        committer-time 1704067200
        committer-tz +0000
        summary Fix the bug
        filename foo.swift
        \treturn true
        """
        let result = GitBlameProvider.parsePorcelain(porcelain)
        XCTAssertEqual(result.count, 1)
        let line = result[0]
        XCTAssertFalse(line.isUncommitted)
        XCTAssertEqual(line.shortSHA, "cccc2222")
        XCTAssertEqual(line.author, "Carol")
        XCTAssertEqual(line.summary, "Fix the bug")
        // date should be set from the epoch value
        XCTAssertEqual(line.date.timeIntervalSince1970, 1_704_067_200, accuracy: 1)
        // relativeDate should be a non-empty string
        XCTAssertFalse(line.relativeDate.isEmpty)
    }

    func testUncommittedLineTooltipText() {
        // Uncommitted lines should be flagged so the tooltip shows "Not Committed Yet".
        let porcelain = """
        0000000000000000000000000000000000000000 1 1 1
        author Not Committed Yet
        author-mail <not.committed.yet>
        author-time 1704067200
        author-tz +0000
        committer Not Committed Yet
        committer-mail <not.committed.yet>
        committer-time 1704067200
        committer-tz +0000
        summary Not Yet Committed
        filename bar.swift
        \tnew line
        """
        let result = GitBlameProvider.parsePorcelain(porcelain)
        XCTAssertEqual(result.count, 1)
        XCTAssertTrue(result[0].isUncommitted)
    }
}
