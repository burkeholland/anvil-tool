import XCTest
@testable import Anvil

final class DependencyImpactScannerTests: XCTestCase {

    // MARK: - containsImport unit tests

    func testSwiftImportDetected() {
        let content = "import Foundation\nimport ChangesModel\n\nstruct Foo {}"
        XCTAssertTrue(DependencyImpactScanner.containsImport(content: content, stem: "ChangesModel"))
    }

    func testTypeScriptFromImportDetected() {
        let content = "import { Foo } from './ChangesModel'\nexport class Bar {}"
        XCTAssertTrue(DependencyImpactScanner.containsImport(content: content, stem: "ChangesModel"))
    }

    func testRequireImportDetected() {
        let content = "const model = require('./ChangesModel');"
        XCTAssertTrue(DependencyImpactScanner.containsImport(content: content, stem: "ChangesModel"))
    }

    func testPythonImportDetected() {
        let content = "import ChangesModel\nfrom ChangesModel import Foo"
        XCTAssertTrue(DependencyImpactScanner.containsImport(content: content, stem: "ChangesModel"))
    }

    func testGoImportDetected() {
        let content = "import \"github.com/org/ChangesModel\"\n\nfunc main() {}"
        XCTAssertTrue(DependencyImpactScanner.containsImport(content: content, stem: "ChangesModel"))
    }

    func testNoImportReturnsFalse() {
        let content = "struct Foo {}\nlet x = ChangesModel()"
        XCTAssertFalse(DependencyImpactScanner.containsImport(content: content, stem: "ChangesModel"))
    }

    func testPartialWordNotMatched() {
        // "import ChangesModelExtended" should not match stem "ChangesModel" as a full word
        let content = "import ChangesModelExtended"
        XCTAssertFalse(DependencyImpactScanner.containsImport(content: content, stem: "ChangesModel"))
    }

    func testCommentedImportSkipped() {
        let content = "// import ChangesModel\nstruct Foo {}"
        XCTAssertFalse(DependencyImpactScanner.containsImport(content: content, stem: "ChangesModel"))
    }

    func testHashCommentSkipped() {
        let content = "# import ChangesModel\nclass Foo:"
        XCTAssertFalse(DependencyImpactScanner.containsImport(content: content, stem: "ChangesModel"))
    }

    func testEmptyContent() {
        XCTAssertFalse(DependencyImpactScanner.containsImport(content: "", stem: "ChangesModel"))
    }

    // MARK: - scan integration tests

    func testScanEmptyModifiedPaths() {
        let rootURL = URL(fileURLWithPath: "/tmp")
        let result = DependencyImpactScanner.scan(modifiedPaths: [], rootURL: rootURL)
        XCTAssertTrue(result.isEmpty)
    }

    func testScanDetectsImporter() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        // Create modified file
        let modified = dir.appendingPathComponent("UserModel.swift")
        try "struct UserModel {}".write(to: modified, atomically: true, encoding: .utf8)

        // Create importer file
        let importer = dir.appendingPathComponent("UserView.swift")
        try "import UserModel\nstruct UserView {}".write(to: importer, atomically: true, encoding: .utf8)

        // Create unrelated file
        let unrelated = dir.appendingPathComponent("Other.swift")
        try "struct Other {}".write(to: unrelated, atomically: true, encoding: .utf8)

        let result = DependencyImpactScanner.scan(
            modifiedPaths: [modified.standardizedFileURL.path],
            rootURL: dir
        )

        XCTAssertEqual(result[importer.standardizedFileURL.path], "Imports UserModel.swift (modified)")
        XCTAssertNil(result[unrelated.standardizedFileURL.path])
        // The modified file itself must not appear
        XCTAssertNil(result[modified.standardizedFileURL.path])
    }

    func testScanDoesNotFlagModifiedFileItself() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let modified = dir.appendingPathComponent("Foo.swift")
        try "import Foo\nstruct Foo {}".write(to: modified, atomically: true, encoding: .utf8)

        let result = DependencyImpactScanner.scan(
            modifiedPaths: [modified.standardizedFileURL.path],
            rootURL: dir
        )

        XCTAssertNil(result[modified.standardizedFileURL.path])
    }

    func testScanIgnoresNonSourceFiles() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let modified = dir.appendingPathComponent("Config.swift")
        try "struct Config {}".write(to: modified, atomically: true, encoding: .utf8)

        let mdFile = dir.appendingPathComponent("README.md")
        try "import Config".write(to: mdFile, atomically: true, encoding: .utf8)

        let result = DependencyImpactScanner.scan(
            modifiedPaths: [modified.standardizedFileURL.path],
            rootURL: dir
        )

        XCTAssertNil(result[mdFile.standardizedFileURL.path])
    }

    func testScanReturnsEmptyWhenModifiedFileIsNonSource() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        // .json is not a supported source extension
        let modified = dir.appendingPathComponent("config.json")
        try "{}".write(to: modified, atomically: true, encoding: .utf8)

        let result = DependencyImpactScanner.scan(
            modifiedPaths: [modified.standardizedFileURL.path],
            rootURL: dir
        )

        XCTAssertTrue(result.isEmpty)
    }

    func testScanMultipleModifiedFiles() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let modA = dir.appendingPathComponent("Alpha.swift")
        try "struct Alpha {}".write(to: modA, atomically: true, encoding: .utf8)

        let modB = dir.appendingPathComponent("Beta.swift")
        try "struct Beta {}".write(to: modB, atomically: true, encoding: .utf8)

        // Imports Alpha
        let importerA = dir.appendingPathComponent("ViewA.swift")
        try "import Alpha\nstruct ViewA {}".write(to: importerA, atomically: true, encoding: .utf8)

        // Imports Beta
        let importerB = dir.appendingPathComponent("ViewB.swift")
        try "import Beta\nstruct ViewB {}".write(to: importerB, atomically: true, encoding: .utf8)

        let result = DependencyImpactScanner.scan(
            modifiedPaths: [
                modA.standardizedFileURL.path,
                modB.standardizedFileURL.path
            ],
            rootURL: dir
        )

        XCTAssertEqual(result[importerA.standardizedFileURL.path], "Imports Alpha.swift (modified)")
        XCTAssertEqual(result[importerB.standardizedFileURL.path], "Imports Beta.swift (modified)")
    }

    func testScanNestedDirectories() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let src = dir.appendingPathComponent("src")
        try FileManager.default.createDirectory(at: src, withIntermediateDirectories: false)

        let modified = src.appendingPathComponent("UserModel.swift")
        try "struct UserModel {}".write(to: modified, atomically: true, encoding: .utf8)

        let views = src.appendingPathComponent("views")
        try FileManager.default.createDirectory(at: views, withIntermediateDirectories: false)

        let importer = views.appendingPathComponent("UserView.swift")
        try "import UserModel\nstruct UserView {}".write(to: importer, atomically: true, encoding: .utf8)

        let result = DependencyImpactScanner.scan(
            modifiedPaths: [modified.standardizedFileURL.path],
            rootURL: dir
        )

        XCTAssertEqual(result[importer.standardizedFileURL.path], "Imports UserModel.swift (modified)")
    }

    func testScanSkipsNodeModules() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let modified = dir.appendingPathComponent("Util.swift")
        try "struct Util {}".write(to: modified, atomically: true, encoding: .utf8)

        let nodeModules = dir.appendingPathComponent("node_modules")
        try FileManager.default.createDirectory(at: nodeModules, withIntermediateDirectories: false)

        let skipped = nodeModules.appendingPathComponent("lib.ts")
        try "import Util from './Util'".write(to: skipped, atomically: true, encoding: .utf8)

        let result = DependencyImpactScanner.scan(
            modifiedPaths: [modified.standardizedFileURL.path],
            rootURL: dir
        )

        XCTAssertNil(result[skipped.standardizedFileURL.path])
    }

    func testInlineCommentNotMatched() {
        // An inline // comment containing "import" should not trigger a match
        let content = "let x = 1 // import Foo\nstruct Bar {}"
        XCTAssertFalse(DependencyImpactScanner.containsImport(content: content, stem: "Foo"))
    }

    func testImportantKeywordNotMatched() {
        // "important" contains "import" as a substring — should not match as import keyword
        let content = "// This is important\nimport Foundation\nlet x = 1"
        // "important" in comment is skipped; "Foundation" doesn't match "important"
        XCTAssertFalse(DependencyImpactScanner.containsImport(content: content, stem: "important"))
    }

    }

    // MARK: - scanDependentsMap tests

    func testScanDependentsMapEmptyModifiedPaths() {
        let rootURL = URL(fileURLWithPath: "/tmp")
        let result = DependencyImpactScanner.scanDependentsMap(modifiedPaths: [], rootURL: rootURL)
        XCTAssertTrue(result.isEmpty)
    }

    func testScanDependentsMapSingleDependent() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let modified = dir.appendingPathComponent("UserModel.swift")
        try "struct UserModel {}".write(to: modified, atomically: true, encoding: .utf8)

        let importer = dir.appendingPathComponent("UserView.swift")
        try "import UserModel\nstruct UserView {}".write(to: importer, atomically: true, encoding: .utf8)

        let unrelated = dir.appendingPathComponent("Other.swift")
        try "struct Other {}".write(to: unrelated, atomically: true, encoding: .utf8)

        let result = DependencyImpactScanner.scanDependentsMap(
            modifiedPaths: [modified.standardizedFileURL.path],
            rootURL: dir
        )

        let dependents = result[modified.standardizedFileURL.path] ?? []
        XCTAssertEqual(dependents, [importer.standardizedFileURL.path])
        // Modified file itself must not appear as a dependent
        XCTAssertFalse(dependents.contains(modified.standardizedFileURL.path))
        XCTAssertFalse(dependents.contains(unrelated.standardizedFileURL.path))
    }

    func testScanDependentsMapMultipleImporters() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let modified = dir.appendingPathComponent("Util.swift")
        try "struct Util {}".write(to: modified, atomically: true, encoding: .utf8)

        let importerA = dir.appendingPathComponent("ViewA.swift")
        try "import Util\nstruct ViewA {}".write(to: importerA, atomically: true, encoding: .utf8)

        let importerB = dir.appendingPathComponent("ViewB.swift")
        try "import Util\nstruct ViewB {}".write(to: importerB, atomically: true, encoding: .utf8)

        let result = DependencyImpactScanner.scanDependentsMap(
            modifiedPaths: [modified.standardizedFileURL.path],
            rootURL: dir
        )

        let dependents = Set(result[modified.standardizedFileURL.path] ?? [])
        XCTAssertEqual(dependents, [importerA.standardizedFileURL.path, importerB.standardizedFileURL.path])
    }

    func testScanDependentsMapMultipleModifiedFiles() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let modA = dir.appendingPathComponent("Alpha.swift")
        try "struct Alpha {}".write(to: modA, atomically: true, encoding: .utf8)

        let modB = dir.appendingPathComponent("Beta.swift")
        try "struct Beta {}".write(to: modB, atomically: true, encoding: .utf8)

        let importerA = dir.appendingPathComponent("ViewA.swift")
        try "import Alpha\nstruct ViewA {}".write(to: importerA, atomically: true, encoding: .utf8)

        let importerBoth = dir.appendingPathComponent("ViewBoth.swift")
        try "import Alpha\nimport Beta\nstruct ViewBoth {}".write(to: importerBoth, atomically: true, encoding: .utf8)

        let result = DependencyImpactScanner.scanDependentsMap(
            modifiedPaths: [modA.standardizedFileURL.path, modB.standardizedFileURL.path],
            rootURL: dir
        )

        let alphaDepends = Set(result[modA.standardizedFileURL.path] ?? [])
        XCTAssertTrue(alphaDepends.contains(importerA.standardizedFileURL.path))
        XCTAssertTrue(alphaDepends.contains(importerBoth.standardizedFileURL.path))

        let betaDepends = Set(result[modB.standardizedFileURL.path] ?? [])
        XCTAssertTrue(betaDepends.contains(importerBoth.standardizedFileURL.path))
        XCTAssertFalse(betaDepends.contains(importerA.standardizedFileURL.path))
    }

    func testScanDependentsMapNoDependents() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let modified = dir.appendingPathComponent("Isolated.swift")
        try "struct Isolated {}".write(to: modified, atomically: true, encoding: .utf8)

        let unrelated = dir.appendingPathComponent("Other.swift")
        try "struct Other {}".write(to: unrelated, atomically: true, encoding: .utf8)

        let result = DependencyImpactScanner.scanDependentsMap(
            modifiedPaths: [modified.standardizedFileURL.path],
            rootURL: dir
        )

        XCTAssertNil(result[modified.standardizedFileURL.path])
    }

    func testScanDependentsMapReturnsEmptyForNonSourceModified() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let modified = dir.appendingPathComponent("config.json")
        try "{}".write(to: modified, atomically: true, encoding: .utf8)

        let result = DependencyImpactScanner.scanDependentsMap(
            modifiedPaths: [modified.standardizedFileURL.path],
            rootURL: dir
        )

        XCTAssertTrue(result.isEmpty)
    }

    // MARK: - Helpers

    private func makeTempDir() throws -> URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("DependencyImpactScannerTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
