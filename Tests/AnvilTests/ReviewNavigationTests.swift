import XCTest
@testable import Anvil

final class ReviewNavigationTests: XCTestCase {

    private func makeFile(path: String) -> ChangedFile {
        ChangedFile(
            url: URL(fileURLWithPath: "/tmp/project/\(path)"),
            relativePath: path,
            status: .modified,
            staging: .unstaged
        )
    }

    // MARK: - focusNextUnreviewedFile

    func testNextUnreviewed_noFilesDoesNothing() {
        let model = ChangesModel()
        model.focusNextUnreviewedFile()
        XCTAssertNil(model.focusedFileIndex)
    }

    func testNextUnreviewed_allReviewedDoesNothing() {
        let model = ChangesModel()
        let files = [makeFile(path: "a.swift"), makeFile(path: "b.swift")]
        model.setChangedFilesForTesting(files)
        model.toggleReviewed(files[0])
        model.toggleReviewed(files[1])
        model.focusNextUnreviewedFile()
        XCTAssertNil(model.focusedFileIndex)
    }

    func testNextUnreviewed_wrapsAroundWhenNoneAfterCurrent() {
        let model = ChangesModel()
        let files = [makeFile(path: "a.swift"), makeFile(path: "b.swift"), makeFile(path: "c.swift")]
        model.setChangedFilesForTesting(files)
        // Mark b.swift reviewed; leave a.swift and c.swift unreviewed
        model.toggleReviewed(files[1])
        // Focus c.swift (index 2) — next unreviewed should wrap back to a.swift (index 0)
        model.focusedFileIndex = 2
        model.focusNextUnreviewedFile()
        XCTAssertEqual(model.focusedFileIndex, 0)
    }

    func testNextUnreviewed_picksFirstUnreviewedAfterCurrent() {
        let model = ChangesModel()
        let files = [makeFile(path: "a.swift"), makeFile(path: "b.swift"), makeFile(path: "c.swift")]
        model.setChangedFilesForTesting(files)
        model.toggleReviewed(files[0])  // a.swift reviewed
        // No focused file → should go to first unreviewed (b.swift at index 1)
        model.focusNextUnreviewedFile()
        XCTAssertEqual(model.focusedFileIndex, 1)
        // Now at b.swift, next unreviewed should be c.swift
        model.focusNextUnreviewedFile()
        XCTAssertEqual(model.focusedFileIndex, 2)
    }

    func testNextUnreviewed_clearsFocusedHunkIndex() {
        let model = ChangesModel()
        let files = [makeFile(path: "a.swift")]
        model.setChangedFilesForTesting(files)
        model.focusedFileIndex = 0
        model.focusedHunkIndex = 1
        model.focusNextUnreviewedFile()
        XCTAssertNil(model.focusedHunkIndex)
    }

    // MARK: - focusPreviousUnreviewedFile

    func testPreviousUnreviewed_noFilesDoesNothing() {
        let model = ChangesModel()
        model.focusPreviousUnreviewedFile()
        XCTAssertNil(model.focusedFileIndex)
    }

    func testPreviousUnreviewed_allReviewedDoesNothing() {
        let model = ChangesModel()
        let files = [makeFile(path: "a.swift"), makeFile(path: "b.swift")]
        model.setChangedFilesForTesting(files)
        model.toggleReviewed(files[0])
        model.toggleReviewed(files[1])
        model.focusPreviousUnreviewedFile()
        XCTAssertNil(model.focusedFileIndex)
    }

    func testPreviousUnreviewed_wrapsAroundWhenNoneBeforeCurrent() {
        let model = ChangesModel()
        let files = [makeFile(path: "a.swift"), makeFile(path: "b.swift"), makeFile(path: "c.swift")]
        model.setChangedFilesForTesting(files)
        // Mark b.swift reviewed; leave a.swift and c.swift unreviewed
        model.toggleReviewed(files[1])
        // Focus a.swift (index 0) — previous unreviewed should wrap to c.swift (index 2)
        model.focusedFileIndex = 0
        model.focusPreviousUnreviewedFile()
        XCTAssertEqual(model.focusedFileIndex, 2)
    }

    func testPreviousUnreviewed_picksLastUnreviewedBeforeCurrent() {
        let model = ChangesModel()
        let files = [makeFile(path: "a.swift"), makeFile(path: "b.swift"), makeFile(path: "c.swift")]
        model.setChangedFilesForTesting(files)
        model.toggleReviewed(files[2])  // c.swift reviewed
        // Focus c.swift (index 2) — previous unreviewed should be b.swift (index 1)
        model.focusedFileIndex = 2
        model.focusPreviousUnreviewedFile()
        XCTAssertEqual(model.focusedFileIndex, 1)
        // Now at b.swift, previous unreviewed should be a.swift
        model.focusPreviousUnreviewedFile()
        XCTAssertEqual(model.focusedFileIndex, 0)
    }

    func testPreviousUnreviewed_clearsFocusedHunkIndex() {
        let model = ChangesModel()
        let files = [makeFile(path: "a.swift")]
        model.setChangedFilesForTesting(files)
        model.focusedFileIndex = 0
        model.focusedHunkIndex = 2
        model.focusPreviousUnreviewedFile()
        XCTAssertNil(model.focusedHunkIndex)
    }

    // MARK: - noFocused initial state

    func testNextUnreviewed_noFocused_goesToFirstUnreviewed() {
        let model = ChangesModel()
        let files = [makeFile(path: "a.swift"), makeFile(path: "b.swift")]
        model.setChangedFilesForTesting(files)
        model.toggleReviewed(files[0])  // a.swift reviewed
        model.focusNextUnreviewedFile()
        XCTAssertEqual(model.focusedFileIndex, 1)
    }

    func testPreviousUnreviewed_noFocused_goesToLastUnreviewed() {
        let model = ChangesModel()
        let files = [makeFile(path: "a.swift"), makeFile(path: "b.swift")]
        model.setChangedFilesForTesting(files)
        model.toggleReviewed(files[1])  // b.swift reviewed
        model.focusPreviousUnreviewedFile()
        XCTAssertEqual(model.focusedFileIndex, 0)
    }
}
