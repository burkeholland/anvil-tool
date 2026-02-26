import XCTest
@testable import Anvil

final class ReviewNeedsWorkTests: XCTestCase {

    private func makeFile(path: String) -> ChangedFile {
        ChangedFile(
            url: URL(fileURLWithPath: "/tmp/project/\(path)"),
            relativePath: path,
            status: .modified,
            staging: .unstaged
        )
    }

    // MARK: - Three-state toggle cycle

    func testToggleCycle_unreviewedToReviewed() {
        let model = ChangesModel()
        let file = makeFile(path: "a.swift")
        model.setChangedFilesForTesting([file])
        // Initial state: unreviewed
        XCTAssertFalse(model.isReviewed(file))
        XCTAssertFalse(model.isNeedsWork(file))
        // First toggle → reviewed
        model.toggleReviewed(file)
        XCTAssertTrue(model.isReviewed(file))
        XCTAssertFalse(model.isNeedsWork(file))
    }

    func testToggleCycle_reviewedToNeedsWork() {
        let model = ChangesModel()
        let file = makeFile(path: "a.swift")
        model.setChangedFilesForTesting([file])
        model.toggleReviewed(file) // → reviewed
        model.toggleReviewed(file) // → needs work
        XCTAssertFalse(model.isReviewed(file))
        XCTAssertTrue(model.isNeedsWork(file))
    }

    func testToggleCycle_needsWorkToUnreviewed() {
        let model = ChangesModel()
        let file = makeFile(path: "a.swift")
        model.setChangedFilesForTesting([file])
        model.toggleReviewed(file) // → reviewed
        model.toggleReviewed(file) // → needs work
        model.toggleReviewed(file) // → unreviewed
        XCTAssertFalse(model.isReviewed(file))
        XCTAssertFalse(model.isNeedsWork(file))
    }

    // MARK: - Mutually exclusive states

    func testReviewedAndNeedsWorkAreMutuallyExclusive() {
        let model = ChangesModel()
        let file = makeFile(path: "a.swift")
        model.setChangedFilesForTesting([file])
        model.toggleReviewed(file) // → reviewed
        model.toggleReviewed(file) // → needs work
        // reviewed should be cleared when needs-work is set
        XCTAssertFalse(model.isReviewed(file))
        XCTAssertTrue(model.isNeedsWork(file))
        // Toggle once more → unreviewed (both cleared)
        model.toggleReviewed(file)
        XCTAssertFalse(model.isReviewed(file))
        XCTAssertFalse(model.isNeedsWork(file))
    }

    // MARK: - Counts

    func testReviewedCount_excludesNeedsWork() {
        let model = ChangesModel()
        let files = [makeFile(path: "a.swift"), makeFile(path: "b.swift")]
        model.setChangedFilesForTesting(files)
        model.toggleReviewed(files[0]) // → reviewed
        model.toggleReviewed(files[1]) // → reviewed
        model.toggleReviewed(files[1]) // → needs work
        XCTAssertEqual(model.reviewedCount, 1)
        XCTAssertEqual(model.needsWorkCount, 1)
    }

    func testUnreviewedStagedCount_excludesBothReviewedAndNeedsWork() {
        let model = ChangesModel()
        let staged = ChangedFile(
            url: URL(fileURLWithPath: "/tmp/project/a.swift"),
            relativePath: "a.swift",
            status: .modified,
            staging: .staged
        )
        let stagedNeedsWork = ChangedFile(
            url: URL(fileURLWithPath: "/tmp/project/b.swift"),
            relativePath: "b.swift",
            status: .modified,
            staging: .staged
        )
        let stagedUnreviewed = ChangedFile(
            url: URL(fileURLWithPath: "/tmp/project/c.swift"),
            relativePath: "c.swift",
            status: .modified,
            staging: .staged
        )
        model.setChangedFilesForTesting([staged, stagedNeedsWork, stagedUnreviewed])
        model.toggleReviewed(staged)       // → reviewed
        model.toggleReviewed(stagedNeedsWork)  // → reviewed
        model.toggleReviewed(stagedNeedsWork)  // → needs work
        // Only stagedUnreviewed counts as unreviewed staged
        XCTAssertEqual(model.unreviewedStagedCount, 1)
    }

    // MARK: - markAllReviewed clears needsWork

    func testMarkAllReviewed_clearsNeedsWork() {
        let model = ChangesModel()
        let files = [makeFile(path: "a.swift"), makeFile(path: "b.swift")]
        model.setChangedFilesForTesting(files)
        model.toggleReviewed(files[0]) // → reviewed
        model.toggleReviewed(files[0]) // → needs work
        model.markAllReviewed()
        XCTAssertTrue(model.isReviewed(files[0]))
        XCTAssertFalse(model.isNeedsWork(files[0]))
        XCTAssertTrue(model.isReviewed(files[1]))
    }

    // MARK: - clearAllReviewed clears needsWork

    func testClearAllReviewed_clearsNeedsWork() {
        let model = ChangesModel()
        let files = [makeFile(path: "a.swift"), makeFile(path: "b.swift")]
        model.setChangedFilesForTesting(files)
        model.toggleReviewed(files[0]) // → reviewed
        model.toggleReviewed(files[1]) // → reviewed
        model.toggleReviewed(files[1]) // → needs work
        model.clearAllReviewed()
        XCTAssertFalse(model.isReviewed(files[0]))
        XCTAssertFalse(model.isNeedsWork(files[1]))
        XCTAssertEqual(model.reviewedCount, 0)
        XCTAssertEqual(model.needsWorkCount, 0)
    }
}
