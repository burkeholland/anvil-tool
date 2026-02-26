import XCTest
@testable import Anvil

final class BrokenReferenceScannerTests: XCTestCase {

    // MARK: - Helpers

    private func makeFile(
        _ relativePath: String,
        status: GitFileStatus = .modified
    ) -> ChangedFile {
        ChangedFile(
            url: URL(fileURLWithPath: "/proj/\(relativePath)"),
            relativePath: relativePath,
            status: status,
            staging: .unstaged
        )
    }

    // MARK: - No removed paths → no findings

    func testNoRemovedFilesProducesNoFindings() {
        let files = [makeFile("src/Foo.swift"), makeFile("src/Bar.swift")]
        let result = BrokenReferenceScanner.scan(files: files)
        for file in files {
            XCTAssertEqual(result[file.url], [])
        }
    }

    // MARK: - JS/TS import extraction

    func testExtractJSImportFromDoubleQuote() {
        let content = #"import { foo } from "./utils/helper""#
        let paths = BrokenReferenceScanner.extractJSImportPaths(from: content)
        XCTAssertEqual(paths, ["./utils/helper"])
    }

    func testExtractJSImportFromSingleQuote() {
        let content = "import bar from '../lib/bar'"
        let paths = BrokenReferenceScanner.extractJSImportPaths(from: content)
        XCTAssertEqual(paths, ["../lib/bar"])
    }

    func testExtractRequireCall() {
        let content = #"const x = require('./config')"#
        let paths = BrokenReferenceScanner.extractJSImportPaths(from: content)
        XCTAssertEqual(paths, ["./config"])
    }

    func testExtractMultipleJSImports() {
        let content = """
        import A from './a'
        import { B } from './b'
        const C = require('./c')
        """
        let paths = BrokenReferenceScanner.extractJSImportPaths(from: content)
        XCTAssertEqual(Set(paths), Set(["./a", "./b", "./c"]))
    }

    func testThirdPartyImportIsIgnored() {
        let content = #"import React from "react""#
        let paths = BrokenReferenceScanner.extractJSImportPaths(from: content)
        // "react" is extracted but resolveRelativePath will return nil for it
        // since it doesn't start with ./ or ../
        XCTAssertEqual(paths, ["react"])
        let resolved = BrokenReferenceScanner.resolveRelativePath(
            "react", from: URL(fileURLWithPath: "/proj/src/index.ts"),
            rootURL: URL(fileURLWithPath: "/proj"),
            extensions: ["ts", "js"]
        )
        XCTAssertNil(resolved)
    }

    // MARK: - Python import extraction

    func testExtractPythonRelativeImport() {
        let content = "from .utils import helper"
        let paths = BrokenReferenceScanner.extractPythonImportPaths(from: content)
        XCTAssertEqual(paths, [".utils"])
    }

    func testExtractPythonParentRelativeImport() {
        let content = "from ..models.user import User"
        let paths = BrokenReferenceScanner.extractPythonImportPaths(from: content)
        XCTAssertEqual(paths, ["..models.user"])
    }

    func testAbsolutePythonImportIsNotExtracted() {
        let content = "from os import path"
        let paths = BrokenReferenceScanner.extractPythonImportPaths(from: content)
        XCTAssertTrue(paths.isEmpty)
    }

    // MARK: - Path resolution

    func testRelativePathResolution() {
        let fileURL = URL(fileURLWithPath: "/proj/src/components/Button.ts")
        let rootURL = URL(fileURLWithPath: "/proj")
        let resolved = BrokenReferenceScanner.resolveRelativePath(
            "../utils/helper",
            from: fileURL,
            rootURL: rootURL,
            extensions: ["ts"]
        )
        // resolves to /proj/src/utils/helper → "src/utils/helper"
        XCTAssertEqual(resolved, "src/utils/helper")
    }

    func testResolutionWithExtensionAppended() {
        let fileURL = URL(fileURLWithPath: "/proj/src/index.ts")
        let rootURL = URL(fileURLWithPath: "/proj")
        let resolved = BrokenReferenceScanner.resolveRelativePath(
            "./lib/math",
            from: fileURL,
            rootURL: rootURL,
            extensions: ["ts", "js"]
        )
        // resolves to src/lib/math; extension-less path is tried first,
        // then src/lib/math.ts, then src/lib/math.js
        XCTAssertNotNil(resolved)
        XCTAssertTrue(resolved!.contains("src/lib/math"))
    }

    func testNonRelativePathReturnsNil() {
        let fileURL = URL(fileURLWithPath: "/proj/src/index.ts")
        let rootURL = URL(fileURLWithPath: "/proj")
        let resolved = BrokenReferenceScanner.resolveRelativePath(
            "react",
            from: fileURL,
            rootURL: rootURL,
            extensions: ["ts"]
        )
        XCTAssertNil(resolved)
    }

    // MARK: - End-to-end: deleted file referenced by another file

    func testJsFileImportingDeletedFileGetsFinding() {
        // Set up temp directory with a JS file that imports a now-deleted helper.
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("BRScannerTests_\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let srcDir = tmp.appendingPathComponent("src")
        try! FileManager.default.createDirectory(at: srcDir, withIntermediateDirectories: true)

        let indexContent = """
        import { helper } from './helper'
        console.log(helper())
        """
        let indexURL = srcDir.appendingPathComponent("index.js")
        try! indexContent.write(to: indexURL, atomically: true, encoding: .utf8)

        // index.js is modified, helper.js was deleted.
        let indexFile = ChangedFile(url: indexURL, relativePath: "src/index.js",
                                    status: .modified, staging: .unstaged)
        let helperFile = ChangedFile(url: tmp.appendingPathComponent("src/helper.js"),
                                     relativePath: "src/helper.js",
                                     status: .deleted, staging: .unstaged)

        let result = BrokenReferenceScanner.scan(files: [indexFile, helperFile], rootURL: tmp)

        let findings = result[indexURL] ?? []
        XCTAssertFalse(findings.isEmpty, "Expected a broken-reference finding for index.js")
        // The reason may use the full relative path ("src/helper.js") or just the filename
        // depending on whether rootURL-relative resolution succeeds; both forms are acceptable.
        XCTAssertTrue(
            findings.contains { $0.reason.contains("src/helper.js") || $0.reason.contains("helper.js") },
            "Finding reason should mention the deleted file"
        )
    }

    func testFileImportingNonDeletedFileHasNoFinding() {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("BRScannerTests_\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let srcDir = tmp.appendingPathComponent("src")
        try! FileManager.default.createDirectory(at: srcDir, withIntermediateDirectories: true)

        let content = "import { x } from './alive'"
        let fileURL = srcDir.appendingPathComponent("main.ts")
        try! content.write(to: fileURL, atomically: true, encoding: .utf8)

        let mainFile = ChangedFile(url: fileURL, relativePath: "src/main.ts",
                                   status: .modified, staging: .unstaged)
        // "alive.ts" is also modified (not deleted).
        let aliveURL = srcDir.appendingPathComponent("alive.ts")
        let aliveFile = ChangedFile(url: aliveURL, relativePath: "src/alive.ts",
                                    status: .modified, staging: .unstaged)

        let result = BrokenReferenceScanner.scan(files: [mainFile, aliveFile], rootURL: tmp)
        XCTAssertEqual(result[fileURL] ?? [], [])
    }

    // MARK: - Config file scanner

    func testConfigFileReferencingDeletedPathGetsFinding() {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("BRScannerTests_\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let configContent = """
        {
          "main": "src/removed.js",
          "scripts": { "start": "node src/removed.js" }
        }
        """
        let configURL = tmp.appendingPathComponent("package.json")
        try! configContent.write(to: configURL, atomically: true, encoding: .utf8)

        let configFile = ChangedFile(url: configURL, relativePath: "package.json",
                                     status: .modified, staging: .unstaged)
        let deletedFile = ChangedFile(url: tmp.appendingPathComponent("src/removed.js"),
                                      relativePath: "src/removed.js",
                                      status: .deleted, staging: .unstaged)

        let result = BrokenReferenceScanner.scan(files: [configFile, deletedFile], rootURL: tmp)
        let findings = result[configURL] ?? []
        XCTAssertFalse(findings.isEmpty, "Expected a finding in package.json for deleted path")
    }

    func testNonConfigFileNotFlaggedForPathLiterals() {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("BRScannerTests_\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        // A Swift file containing "src/removed.swift" as a literal should NOT be flagged
        // via the config-file path, only via the Swift scanner (pathLiteralFindings).
        let swiftContent = """
        // This file references "src/removed.swift"
        let path = "src/removed.swift"
        """
        let swiftURL = tmp.appendingPathComponent("Main.swift")
        try! swiftContent.write(to: swiftURL, atomically: true, encoding: .utf8)

        let swiftFile = ChangedFile(url: swiftURL, relativePath: "Main.swift",
                                    status: .modified, staging: .unstaged)
        let deletedFile = ChangedFile(url: tmp.appendingPathComponent("src/removed.swift"),
                                      relativePath: "src/removed.swift",
                                      status: .deleted, staging: .unstaged)

        let result = BrokenReferenceScanner.scan(files: [swiftFile, deletedFile], rootURL: tmp)
        // Swift path-literal scan should catch this.
        let findings = result[swiftURL] ?? []
        XCTAssertFalse(findings.isEmpty, "Swift path-literal scanner should flag the deleted-path reference")
    }

    // MARK: - Renamed files are treated as removed

    func testFileImportingRenamedFileGetsFinding() {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("BRScannerTests_\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let srcDir = tmp.appendingPathComponent("src")
        try! FileManager.default.createDirectory(at: srcDir, withIntermediateDirectories: true)

        let content = "import { x } from './oldName'"
        let fileURL = srcDir.appendingPathComponent("consumer.ts")
        try! content.write(to: fileURL, atomically: true, encoding: .utf8)

        let consumerFile = ChangedFile(url: fileURL, relativePath: "src/consumer.ts",
                                       status: .modified, staging: .unstaged)
        // oldName.ts was renamed; git shows it as .renamed status.
        let renamedFile = ChangedFile(url: srcDir.appendingPathComponent("oldName.ts"),
                                      relativePath: "src/oldName.ts",
                                      status: .renamed, staging: .staged)

        let result = BrokenReferenceScanner.scan(files: [consumerFile, renamedFile], rootURL: tmp)
        let findings = result[fileURL] ?? []
        XCTAssertFalse(findings.isEmpty, "Expected a finding when importing a renamed file")
    }

    // MARK: - Deleted file itself produces no findings

    func testDeletedFileProducesNoFindings() {
        let deletedFile = makeFile("src/gone.ts", status: .deleted)
        let result = BrokenReferenceScanner.scan(files: [deletedFile])
        XCTAssertEqual(result[deletedFile.url], [])
    }
}
