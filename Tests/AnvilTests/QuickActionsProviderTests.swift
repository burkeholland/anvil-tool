import XCTest
@testable import Anvil

final class QuickActionsProviderTests: XCTestCase {

    // MARK: - Helpers

    private var tmp: URL!

    override func setUp() {
        super.setUp()
        tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tmp)
        super.tearDown()
    }

    private func write(_ content: String, to relativePath: String) {
        let url = tmp.appendingPathComponent(relativePath)
        let dir = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? content.write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: - Custom actions (.anvil/actions.json)

    func testLoadCustom_returnsActionsFromJSON() {
        let json = """
        [
            {"name": "Build", "command": "npm run build", "keybinding": "⌘⇧B", "icon": "hammer"},
            {"name": "Test",  "command": "npm test"}
        ]
        """
        write(json, to: ".anvil/actions.json")

        let actions = QuickActionsProvider.loadCustom(rootURL: tmp)
        XCTAssertEqual(actions.count, 2)

        XCTAssertEqual(actions[0].name, "Build")
        XCTAssertEqual(actions[0].command, "npm run build")
        XCTAssertEqual(actions[0].keybinding, "⌘⇧B")
        XCTAssertEqual(actions[0].icon, "hammer")

        XCTAssertEqual(actions[1].name, "Test")
        XCTAssertEqual(actions[1].command, "npm test")
        XCTAssertNil(actions[1].keybinding)
        XCTAssertEqual(actions[1].icon, "terminal") // default icon
    }

    func testLoadCustom_returnsEmptyWhenNoFile() {
        let actions = QuickActionsProvider.loadCustom(rootURL: tmp)
        XCTAssertTrue(actions.isEmpty)
    }

    func testLoadCustom_skipsEntriesMissingRequiredFields() {
        let json = """
        [
            {"name": "Good", "command": "echo ok"},
            {"name": "NoCommand"},
            {"command": "echo noname"},
            {"name": "", "command": "echo empty-name"}
        ]
        """
        write(json, to: ".anvil/actions.json")
        let actions = QuickActionsProvider.loadCustom(rootURL: tmp)
        XCTAssertEqual(actions.count, 1)
        XCTAssertEqual(actions[0].name, "Good")
    }

    func testLoadCustom_malformedJSONReturnsEmpty() {
        write("not json at all", to: ".anvil/actions.json")
        let actions = QuickActionsProvider.loadCustom(rootURL: tmp)
        XCTAssertTrue(actions.isEmpty)
    }

    // MARK: - load() prefers custom over auto-detected

    func testLoad_prefersCustomOverAutoDetected() {
        // Create package.json so auto-detect would normally fire
        write("""
        {"scripts": {"build": "webpack", "test": "jest"}}
        """, to: "package.json")

        // Also create custom actions
        write("""
        [{"name": "My Build", "command": "custom build"}]
        """, to: ".anvil/actions.json")

        let actions = QuickActionsProvider.load(rootURL: tmp)
        XCTAssertEqual(actions.count, 1)
        XCTAssertEqual(actions[0].name, "My Build")
    }

    func testLoad_fallsBackToAutoDetectWhenNoCustomFile() {
        write("""
        {"scripts": {"build": "webpack"}}
        """, to: "package.json")

        let actions = QuickActionsProvider.load(rootURL: tmp)
        XCTAssertFalse(actions.isEmpty)
        XCTAssertTrue(actions.contains(where: { $0.command == "npm run build" }))
    }

    // MARK: - package.json detection

    func testDetectPackageJSON_basicScripts() {
        write("""
        {"scripts": {"build": "webpack", "test": "jest", "lint": "eslint ."}}
        """, to: "package.json")

        let actions = QuickActionsProvider.detectPackageJSON(rootURL: tmp)
        let commands = Set(actions.map(\.command))
        XCTAssertTrue(commands.contains("npm run build"))
        XCTAssertTrue(commands.contains("npm run test"))
        XCTAssertTrue(commands.contains("npm run lint"))
    }

    func testDetectPackageJSON_sortedAlphabetically() {
        write("""
        {"scripts": {"z-script": "z", "a-script": "a", "m-script": "m"}}
        """, to: "package.json")

        let actions = QuickActionsProvider.detectPackageJSON(rootURL: tmp)
        XCTAssertEqual(actions.map(\.command), ["npm run a-script", "npm run m-script", "npm run z-script"])
    }

    func testDetectPackageJSON_missingScriptsSection() {
        write("""
        {"name": "my-app", "version": "1.0.0"}
        """, to: "package.json")
        XCTAssertTrue(QuickActionsProvider.detectPackageJSON(rootURL: tmp).isEmpty)
    }

    func testDetectPackageJSON_noFile() {
        XCTAssertTrue(QuickActionsProvider.detectPackageJSON(rootURL: tmp).isEmpty)
    }

    func testDetectPackageJSON_iconForBuildScript() {
        write("""
        {"scripts": {"build": "tsc"}}
        """, to: "package.json")
        let actions = QuickActionsProvider.detectPackageJSON(rootURL: tmp)
        XCTAssertEqual(actions.first?.icon, "hammer")
    }

    func testDetectPackageJSON_iconForTestScript() {
        write("""
        {"scripts": {"test": "jest"}}
        """, to: "package.json")
        let actions = QuickActionsProvider.detectPackageJSON(rootURL: tmp)
        XCTAssertEqual(actions.first?.icon, "checkmark.seal")
    }

    func testDetectPackageJSON_iconForStartScript() {
        write("""
        {"scripts": {"start": "node index.js"}}
        """, to: "package.json")
        let actions = QuickActionsProvider.detectPackageJSON(rootURL: tmp)
        XCTAssertEqual(actions.first?.icon, "play")
    }

    // MARK: - Makefile detection

    func testDetectMakefile_basicTargets() {
        write("""
        build:
        \tgo build ./...

        test:
        \tgo test ./...

        clean:
        \trm -rf dist/
        """, to: "Makefile")

        let actions = QuickActionsProvider.detectMakefile(rootURL: tmp)
        let commands = actions.map(\.command)
        XCTAssertTrue(commands.contains("make build"))
        XCTAssertTrue(commands.contains("make test"))
        XCTAssertTrue(commands.contains("make clean"))
    }

    func testDetectMakefile_skipsHiddenAndPercent() {
        write("""
        .PHONY: build
        %suffix:
        \techo suffix
        build:
        \techo build
        """, to: "Makefile")

        let targets = QuickActionsProvider.parseMakefileTargets(
            """
            .PHONY: build
            %suffix:
            \techo suffix
            build:
            \techo build
            """
        )
        XCTAssertFalse(targets.contains(".PHONY"))
        XCTAssertFalse(targets.contains("%suffix"))
        XCTAssertTrue(targets.contains("build"))
    }

    func testDetectMakefile_skipsVariableAssignments() {
        let content = """
        CC = gcc
        CFLAGS = -O2
        build:
        \t$(CC) main.c
        """
        let targets = QuickActionsProvider.parseMakefileTargets(content)
        XCTAssertEqual(targets, ["build"])
    }

    func testDetectMakefile_noFile() {
        XCTAssertTrue(QuickActionsProvider.detectMakefile(rootURL: tmp).isEmpty)
    }

    // MARK: - Cargo.toml detection (Rust)

    func testDetectCargoToml_returnsRustActions() {
        write("[package]\nname = \"my-crate\"", to: "Cargo.toml")
        let actions = QuickActionsProvider.detectCargoToml(rootURL: tmp)
        let commands = Set(actions.map(\.command))
        XCTAssertTrue(commands.contains("cargo build"))
        XCTAssertTrue(commands.contains("cargo test"))
        XCTAssertTrue(commands.contains("cargo run"))
        XCTAssertTrue(commands.contains("cargo clippy"))
        XCTAssertTrue(commands.contains("cargo fmt"))
    }

    func testDetectCargoToml_noFile() {
        XCTAssertTrue(QuickActionsProvider.detectCargoToml(rootURL: tmp).isEmpty)
    }

    // MARK: - Package.swift detection (Swift / SPM)

    func testDetectPackageSwift_returnsSwiftActions() {
        write("// swift-tools-version:5.9\n", to: "Package.swift")
        let actions = QuickActionsProvider.detectPackageSwift(rootURL: tmp)
        let commands = actions.map(\.command)
        XCTAssertTrue(commands.contains("swift build"))
        XCTAssertTrue(commands.contains("swift test"))
        XCTAssertTrue(commands.contains("swift run"))
    }

    func testDetectPackageSwift_noFile() {
        XCTAssertTrue(QuickActionsProvider.detectPackageSwift(rootURL: tmp).isEmpty)
    }

    // MARK: - go.mod detection

    func testDetectGoMod_returnsGoActions() {
        write("module example.com/mymodule\n\ngo 1.21\n", to: "go.mod")
        let actions = QuickActionsProvider.detectGoMod(rootURL: tmp)
        let commands = Set(actions.map(\.command))
        XCTAssertTrue(commands.contains("go build ./..."))
        XCTAssertTrue(commands.contains("go test ./..."))
        XCTAssertTrue(commands.contains("go vet ./..."))
        XCTAssertTrue(commands.contains("go run ."))
    }

    func testDetectGoMod_noFile() {
        XCTAssertTrue(QuickActionsProvider.detectGoMod(rootURL: tmp).isEmpty)
    }

    // MARK: - detectDefaults aggregation

    func testDetectDefaults_multipleProjectFiles() {
        // Both package.json and Makefile present — both should contribute actions
        write("""
        {"scripts": {"build": "webpack"}}
        """, to: "package.json")
        write("deploy:\n\techo deploy\n", to: "Makefile")

        let actions = QuickActionsProvider.detectDefaults(rootURL: tmp)
        let commands = Set(actions.map(\.command))
        XCTAssertTrue(commands.contains("npm run build"))
        XCTAssertTrue(commands.contains("make deploy"))
    }

    func testDetectDefaults_emptyProject() {
        XCTAssertTrue(QuickActionsProvider.detectDefaults(rootURL: tmp).isEmpty)
    }

    // MARK: - Unique IDs

    func testCustomActionsHaveUniqueIDs() {
        write("""
        [
            {"name": "Build", "command": "npm run build"},
            {"name": "Test",  "command": "npm test"},
            {"name": "Lint",  "command": "npm run lint"}
        ]
        """, to: ".anvil/actions.json")

        let actions = QuickActionsProvider.loadCustom(rootURL: tmp)
        let ids = actions.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "All action IDs must be unique")
    }

    func testCustomActionsWithDuplicateNamesHaveUniqueIDs() {
        // Two actions with the same name but different commands must still have unique IDs.
        write("""
        [
            {"name": "Run", "command": "npm start"},
            {"name": "Run", "command": "yarn start"}
        ]
        """, to: ".anvil/actions.json")

        let actions = QuickActionsProvider.loadCustom(rootURL: tmp)
        let ids = actions.map(\.id)
        XCTAssertEqual(ids.count, 2)
        XCTAssertEqual(Set(ids).count, ids.count, "Duplicate names must still produce unique IDs")
    }
