import Foundation

/// Describes a known instruction file type that the Copilot CLI reads.
struct InstructionFileSpec: Identifiable {
    let id: String
    let relativePath: String
    let description: String
    let template: String

    /// Known instruction file types recognized by the Copilot CLI.
    static let knownFiles: [InstructionFileSpec] = [
        InstructionFileSpec(
            id: "copilot-instructions",
            relativePath: ".github/copilot-instructions.md",
            description: "Project-wide instructions for GitHub Copilot",
            template: """
            # Copilot Instructions

            <!-- Add project-specific instructions for GitHub Copilot here. -->
            <!-- These instructions apply to all Copilot interactions in this project. -->

            ## Project Overview

            <!-- Describe what this project does and its key technologies. -->

            ## Coding Conventions

            <!-- List coding style preferences, naming conventions, etc. -->

            ## Architecture

            <!-- Describe the project structure and key design patterns. -->
            """
        ),
        InstructionFileSpec(
            id: "agents-md",
            relativePath: "AGENTS.md",
            description: "Custom agent definitions and project context",
            template: """
            # AGENTS.md

            <!-- Instructions for AI coding agents working in this repository. -->

            ## Project Overview

            <!-- Describe what this project does. -->

            ## Build & Test

            <!-- How to build and test this project. -->

            ## Code Style

            <!-- Key conventions agents should follow. -->
            """
        ),
        InstructionFileSpec(
            id: "claude-md",
            relativePath: "CLAUDE.md",
            description: "Instructions for Claude-based agents",
            template: """
            # CLAUDE.md

            <!-- Instructions for Claude when working in this repository. -->

            ## Project Overview

            <!-- Describe what this project does. -->

            ## Build & Test

            <!-- How to build and test this project. -->

            ## Code Style

            <!-- Key conventions to follow. -->
            """
        ),
        InstructionFileSpec(
            id: "gemini-md",
            relativePath: "GEMINI.md",
            description: "Instructions for Gemini-based agents",
            template: """
            # GEMINI.md

            <!-- Instructions for Gemini when working in this repository. -->

            ## Project Overview

            <!-- Describe what this project does. -->

            ## Build & Test

            <!-- How to build and test this project. -->
            """
        ),
        InstructionFileSpec(
            id: "copilot-md",
            relativePath: "COPILOT.md",
            description: "General Copilot instructions",
            template: """
            # COPILOT.md

            <!-- General instructions for Copilot in this repository. -->

            ## Project Overview

            <!-- Describe what this project does. -->

            ## Conventions

            <!-- Key conventions to follow. -->
            """
        ),
    ]
}

/// Represents the detected state of an instruction file in the project.
struct InstructionFile: Identifiable {
    let id: String
    let spec: InstructionFileSpec
    let exists: Bool
    let url: URL?
    /// First few lines of content for preview, if the file exists.
    let preview: String?
    /// File size in bytes, if the file exists.
    let fileSize: Int?
}

/// Scans a project directory for Copilot CLI instruction files.
enum InstructionsProvider {

    /// Scans the project root for known instruction files and returns their status.
    static func scan(rootURL: URL) -> [InstructionFile] {
        let fm = FileManager.default
        return InstructionFileSpec.knownFiles.map { spec in
            let fileURL = rootURL.appendingPathComponent(spec.relativePath)
            let path = fileURL.path
            var exists = false
            var preview: String?
            var fileSize: Int?

            if fm.fileExists(atPath: path) {
                exists = true
                if let attrs = try? fm.attributesOfItem(atPath: path) {
                    fileSize = (attrs[.size] as? NSNumber)?.intValue
                }
                // Read first ~500 chars for preview
                if let data = fm.contents(atPath: path),
                   let content = String(data: data, encoding: .utf8) {
                    let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmed.count > 500 {
                        preview = String(trimmed.prefix(500)) + "…"
                    } else {
                        preview = trimmed
                    }
                }
            }

            return InstructionFile(
                id: spec.id,
                spec: spec,
                exists: exists,
                url: exists ? fileURL : nil,
                preview: preview,
                fileSize: fileSize
            )
        }
    }

    /// Scans for additional .instructions.md files under .github/instructions/.
    static func scanCustomInstructions(rootURL: URL) -> [InstructionFile] {
        let fm = FileManager.default
        let instructionsDir = rootURL.appendingPathComponent(".github/instructions")
        guard fm.fileExists(atPath: instructionsDir.path) else { return [] }

        var results: [InstructionFile] = []
        if let enumerator = fm.enumerator(
            at: instructionsDir,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) {
            for case let url as URL in enumerator {
                guard url.pathExtension == "md",
                      url.lastPathComponent.hasSuffix(".instructions.md") else { continue }
                let relPath = url.path.replacingOccurrences(
                    of: rootURL.path + "/",
                    with: ""
                )
                var preview: String?
                var fileSize: Int?
                if let attrs = try? fm.attributesOfItem(atPath: url.path) {
                    fileSize = (attrs[.size] as? NSNumber)?.intValue
                }
                if let data = fm.contents(atPath: url.path),
                   let content = String(data: data, encoding: .utf8) {
                    let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
                    preview = trimmed.count > 500 ? String(trimmed.prefix(500)) + "…" : trimmed
                }
                let spec = InstructionFileSpec(
                    id: relPath,
                    relativePath: relPath,
                    description: "Custom instruction file",
                    template: ""
                )
                results.append(InstructionFile(
                    id: relPath,
                    spec: spec,
                    exists: true,
                    url: url,
                    preview: preview,
                    fileSize: fileSize
                ))
            }
        }
        return results
    }

    /// Creates an instruction file from its template.
    /// Returns the URL of the created file, or nil if the file already exists or on failure.
    @discardableResult
    static func create(spec: InstructionFileSpec, rootURL: URL) -> URL? {
        let fm = FileManager.default
        let fileURL = rootURL.appendingPathComponent(spec.relativePath)
        let dir = fileURL.deletingLastPathComponent()

        // Never overwrite an existing file
        guard !fm.fileExists(atPath: fileURL.path) else { return nil }

        do {
            if !fm.fileExists(atPath: dir.path) {
                try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            }
            try spec.template.write(to: fileURL, atomically: true, encoding: .utf8)
            return fileURL
        } catch {
            return nil
        }
    }
}
