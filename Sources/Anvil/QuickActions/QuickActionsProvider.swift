import Foundation

/// A single quick action that can be executed in the terminal from the command palette.
struct QuickAction: Identifiable {
    let id: String
    let name: String
    let command: String
    /// Optional keyboard shortcut hint to display in the palette (e.g. "⌘⇧B").
    let keybinding: String?
    /// SF Symbol name for the row icon (falls back to "terminal" when nil).
    let icon: String

    init(id: String, name: String, command: String, keybinding: String? = nil, icon: String = "terminal") {
        self.id = id
        self.name = name
        self.command = command
        self.keybinding = keybinding
        self.icon = icon
    }
}

/// Loads quick actions for a project.
///
/// Priority:
/// 1. Custom actions from `.anvil/actions.json` (if present).
/// 2. Auto-detected defaults from project files (`package.json`, `Makefile`,
///    `Cargo.toml`, `Package.swift`, `go.mod`).
///
/// When `.anvil/actions.json` exists it completely replaces auto-detection so
/// teams can lock down exactly which actions appear.
enum QuickActionsProvider {

    // MARK: - Public API

    /// Returns quick actions for the given project root.
    /// If `.anvil/actions.json` is present its contents are returned as-is;
    /// otherwise auto-detected defaults are returned.
    static func load(rootURL: URL) -> [QuickAction] {
        let custom = loadCustom(rootURL: rootURL)
        if !custom.isEmpty {
            return custom
        }
        return detectDefaults(rootURL: rootURL)
    }

    // MARK: - Custom actions (.anvil/actions.json)

    /// Loads custom actions from `.anvil/actions.json`.
    /// Each entry may have: "name" (required), "command" (required),
    /// "keybinding" (optional), "icon" (optional).
    static func loadCustom(rootURL: URL) -> [QuickAction] {
        let fileURL = rootURL
            .appendingPathComponent(".anvil")
            .appendingPathComponent("actions.json")
        guard let data = try? Data(contentsOf: fileURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [[String: String]]
        else { return [] }

        return json.enumerated().compactMap { index, dict in
            guard let name = dict["name"], !name.isEmpty,
                  let command = dict["command"], !command.isEmpty
            else { return nil }
            return QuickAction(
                id: "custom-\(index)-\(name)",
                name: name,
                command: command,
                keybinding: dict["keybinding"],
                icon: dict["icon"] ?? "terminal"
            )
        }
    }

    // MARK: - Auto-detection

    /// Detects build / test / lint commands from well-known project files.
    static func detectDefaults(rootURL: URL) -> [QuickAction] {
        var actions: [QuickAction] = []

        actions += detectPackageJSON(rootURL: rootURL)
        actions += detectMakefile(rootURL: rootURL)
        actions += detectCargoToml(rootURL: rootURL)
        actions += detectPackageSwift(rootURL: rootURL)
        actions += detectGoMod(rootURL: rootURL)

        return actions
    }

    // MARK: - package.json

    static func detectPackageJSON(rootURL: URL) -> [QuickAction] {
        let fileURL = rootURL.appendingPathComponent("package.json")
        guard let data = try? Data(contentsOf: fileURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let scripts = json["scripts"] as? [String: String]
        else { return [] }

        // Stable ordering: sort alphabetically so results are deterministic.
        return scripts.keys.sorted().map { name in
            QuickAction(
                id: "npm-\(name)",
                name: "npm run \(name)",
                command: "npm run \(name)",
                icon: iconForScript(name)
            )
        }
    }

    // MARK: - Makefile

    static func detectMakefile(rootURL: URL) -> [QuickAction] {
        for filename in ["Makefile", "makefile", "GNUmakefile"] {
            let fileURL = rootURL.appendingPathComponent(filename)
            guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }
            let targets = parseMakefileTargets(content)
            if !targets.isEmpty {
                return targets.map { target in
                    QuickAction(
                        id: "make-\(target)",
                        name: "make \(target)",
                        command: "make \(target)",
                        icon: iconForScript(target)
                    )
                }
            }
        }
        return []
    }

    // MARK: - Cargo.toml (Rust)

    static func detectCargoToml(rootURL: URL) -> [QuickAction] {
        let fileURL = rootURL.appendingPathComponent("Cargo.toml")
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        return [
            QuickAction(id: "cargo-build",   name: "cargo build",         command: "cargo build",         icon: "hammer"),
            QuickAction(id: "cargo-test",    name: "cargo test",          command: "cargo test",          icon: "checkmark.seal"),
            QuickAction(id: "cargo-run",     name: "cargo run",           command: "cargo run",           icon: "play"),
            QuickAction(id: "cargo-clippy",  name: "cargo clippy",        command: "cargo clippy",        icon: "exclamationmark.triangle"),
            QuickAction(id: "cargo-fmt",     name: "cargo fmt",           command: "cargo fmt",           icon: "text.alignleft"),
        ]
    }

    // MARK: - Package.swift (Swift / SPM)

    static func detectPackageSwift(rootURL: URL) -> [QuickAction] {
        let fileURL = rootURL.appendingPathComponent("Package.swift")
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        return [
            QuickAction(id: "swift-build",  name: "swift build",  command: "swift build",  icon: "hammer"),
            QuickAction(id: "swift-test",   name: "swift test",   command: "swift test",   icon: "checkmark.seal"),
            QuickAction(id: "swift-run",    name: "swift run",    command: "swift run",    icon: "play"),
        ]
    }

    // MARK: - go.mod (Go)

    static func detectGoMod(rootURL: URL) -> [QuickAction] {
        let fileURL = rootURL.appendingPathComponent("go.mod")
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        return [
            QuickAction(id: "go-build",  name: "go build ./...",  command: "go build ./...",  icon: "hammer"),
            QuickAction(id: "go-test",   name: "go test ./...",   command: "go test ./...",   icon: "checkmark.seal"),
            QuickAction(id: "go-vet",    name: "go vet ./...",    command: "go vet ./...",    icon: "exclamationmark.triangle"),
            QuickAction(id: "go-run",    name: "go run .",        command: "go run .",        icon: "play"),
        ]
    }

    // MARK: - Private helpers

    /// Parses explicit Makefile targets (lines of the form `target:`) from content,
    /// excluding special targets (those starting with `.` or `%`) and variables.
    static func parseMakefileTargets(_ content: String) -> [String] {
        var targets: [String] = []
        let lines = content.components(separatedBy: .newlines)
        for line in lines {
            // Target lines: non-whitespace start, contain ":", not a variable assignment
            guard !line.isEmpty,
                  !line.hasPrefix("\t"),
                  !line.hasPrefix(" "),
                  !line.hasPrefix("#"),
                  line.contains(":"),
                  !line.contains("=")
            else { continue }

            let targetPart = line.components(separatedBy: ":").first ?? ""
            let target = targetPart.trimmingCharacters(in: .whitespaces)

            // Skip special targets and empty strings
            guard !target.isEmpty,
                  !target.hasPrefix("."),
                  !target.hasPrefix("%"),
                  !target.contains(" ")
            else { continue }

            targets.append(target)
        }
        return targets
    }

    /// Returns an appropriate SF Symbol for a script name.
    private static func iconForScript(_ name: String) -> String {
        let n = name.lowercased()
        if n.contains("build") || n.contains("compile") || n.contains("bundle") { return "hammer" }
        if n.contains("test") || n.contains("spec") || n.contains("check") { return "checkmark.seal" }
        if n.contains("lint") || n.contains("format") || n.contains("fmt") { return "text.alignleft" }
        if n.contains("deploy") || n.contains("publish") || n.contains("release") { return "arrow.up.circle" }
        if n.contains("start") || n.contains("run") || n.contains("serve") || n.contains("dev") { return "play" }
        if n.contains("clean") { return "trash" }
        if n.contains("install") || n.contains("setup") { return "arrow.down.circle" }
        return "terminal"
    }
}
