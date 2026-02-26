import Foundation

/// Detects the project's build system and runs the build command in the background.
/// Publishes build status so the task completion banner can show pass/fail feedback.
final class BuildVerifier: ObservableObject {

    enum Status: Equatable {
        case idle
        case running
        case passed
        case failed(output: String)
    }

    @Published private(set) var status: Status = .idle
    /// Structured diagnostics parsed from the most recent failed build output.
    @Published private(set) var diagnostics: [BuildDiagnostic] = []

    private var buildProcess: Process?
    private let workQueue = DispatchQueue(label: "dev.anvil.build-verifier", qos: .userInitiated)

    func run(at rootURL: URL) {
        guard let cmd = detectBuildCommand(at: rootURL) else {
            // No recognised build system — stay idle.
            return
        }

        cancel()
        DispatchQueue.main.async { self.status = .running }

        workQueue.async { [weak self] in
            guard let self else { return }

            let process = Process()
            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()

            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = cmd
            process.currentDirectoryURL = rootURL
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe
            // Inherit the user's PATH so toolchains installed via Homebrew/asdf etc. are found.
            var env = ProcessInfo.processInfo.environment
            if env["PATH"] == nil {
                env["PATH"] = "/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
            }
            process.environment = env

            self.buildProcess = process

            do {
                try process.run()
            } catch {
                DispatchQueue.main.async { self.status = .failed(output: error.localizedDescription) }
                return
            }

            // Read stdout + stderr before waitUntilExit to avoid pipe deadlock.
            let outData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            let errData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()

            guard self.buildProcess === process else { return } // cancelled

            let combinedOutput = [
                String(data: outData, encoding: .utf8) ?? "",
                String(data: errData, encoding: .utf8) ?? ""
            ].joined()
                .trimmingCharacters(in: .whitespacesAndNewlines)

            let succeeded = process.terminationStatus == 0

            DispatchQueue.main.async {
                self.status = succeeded ? .passed : .failed(output: combinedOutput)
                if succeeded {
                    self.diagnostics = []
                } else {
                    self.diagnostics = BuildDiagnosticParser.parse(combinedOutput)
                }
            }
        }
    }

    func cancel() {
        buildProcess?.terminate()
        buildProcess = nil
        status = .idle
        diagnostics = []
    }

    // MARK: - Build System Detection

    /// Returns the `/usr/bin/env` argument list for the detected build system, or nil if none found.
    private func detectBuildCommand(at rootURL: URL) -> [String]? {
        let fm = FileManager.default
        func exists(_ name: String) -> Bool {
            fm.fileExists(atPath: rootURL.appendingPathComponent(name).path)
        }

        if exists("Package.swift") {
            return ["swift", "build"]
        }
        if exists("package.json") {
            return ["npm", "run", "build"]
        }
        if exists("Cargo.toml") {
            return ["cargo", "build"]
        }
        if exists("Makefile") || exists("makefile") || exists("GNUmakefile") {
            return ["make"]
        }
        return nil
    }
}
