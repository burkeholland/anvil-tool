import Foundation

/// Detects the project's test system and runs the test suite in the background.
/// Publishes test status so the task completion banner can show pass/fail feedback.
final class TestRunner: ObservableObject {

    enum Status: Equatable {
        case idle
        case running
        /// Tests ran and all passed. `total` is the number of tests executed.
        case passed(total: Int)
        /// Tests ran and at least one failed. `failedTests` is a list of failed test names
        /// (may be empty if the runner output is unparseable). `output` is the raw combined
        /// output, suitable for sending to the agent as a fix request.
        case failed(failedTests: [String], output: String)
    }

    @Published private(set) var status: Status = .idle

    private var testProcess: Process?
    private let workQueue = DispatchQueue(label: "dev.anvil.test-runner", qos: .userInitiated)

    func run(at rootURL: URL) {
        guard let cmd = detectTestCommand(at: rootURL) else {
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
            var env = ProcessInfo.processInfo.environment
            if env["PATH"] == nil {
                env["PATH"] = "/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
            }
            process.environment = env

            self.testProcess = process

            do {
                try process.run()
            } catch {
                DispatchQueue.main.async { self.status = .failed(failedTests: [], output: error.localizedDescription) }
                return
            }

            // Read stdout + stderr before waitUntilExit to avoid pipe deadlock.
            let outData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            let errData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()

            guard self.testProcess === process else { return } // cancelled

            let combinedOutput = [
                String(data: outData, encoding: .utf8) ?? "",
                String(data: errData, encoding: .utf8) ?? ""
            ].joined()
                .trimmingCharacters(in: .whitespacesAndNewlines)

            let succeeded = process.terminationStatus == 0
            let result = TestResultParser.parse(combinedOutput)

            DispatchQueue.main.async {
                if succeeded {
                    self.status = .passed(total: result.totalPassed)
                } else {
                    self.status = .failed(failedTests: result.failedTests, output: combinedOutput)
                }
            }
        }
    }

    func cancel() {
        testProcess?.terminate()
        testProcess = nil
        status = .idle
    }

    // MARK: - Test System Detection

    /// Returns the `/usr/bin/env` argument list for the detected test system, or nil if none found.
    private func detectTestCommand(at rootURL: URL) -> [String]? {
        let fm = FileManager.default
        func exists(_ name: String) -> Bool {
            fm.fileExists(atPath: rootURL.appendingPathComponent(name).path)
        }

        if exists("Package.swift") {
            return ["swift", "test"]
        }
        if exists("package.json") {
            // --passWithNoTests prevents failure in projects that have no tests yet.
            return ["npm", "test", "--", "--passWithNoTests"]
        }
        if exists("Cargo.toml") {
            return ["cargo", "test"]
        }
        if exists("go.mod") {
            return ["go", "test", "./..."]
        }
        if exists("pytest.ini") || exists("pyproject.toml") || exists("setup.py") {
            return ["python", "-m", "pytest", "--tb=short", "-q"]
        }
        if exists("Makefile") || exists("makefile") || exists("GNUmakefile") {
            return ["make", "test"]
        }
        return nil
    }
}

// MARK: - Test Result Parser

/// Parses raw test output from multiple test tool formats into pass/fail counts and names.
///
/// Supported formats:
/// - Swift / XCTest:       `Test Suite '…' passed/failed … executed N tests, with F failures`
///                         `Test Case '…' started.`  /  `Test Case '…' failed.`
/// - Swift Testing:        `✔ Test …` / `✗ Test …` (swift-testing package)
/// - Cargo/rustc:          `test module::name ... ok` / `test module::name ... FAILED`
///                         `test result: ok. N passed; F failed;`
/// - pytest:               `N passed` / `N failed` in summary; `FAILED test_file.py::test_name`
/// - Jest/Mocha:           `✓ description` / `✗ description` / `N passing` / `N failing`
/// - Go test:              `--- PASS: TestName` / `--- FAIL: TestName`
enum TestResultParser {

    struct ParsedResult {
        var totalPassed: Int = 0
        var failedTests: [String] = []
    }

    static func parse(_ output: String) -> ParsedResult {
        var result = ParsedResult()

        // Try each format; use the first that yields concrete numbers.
        if parseSwiftXCTest(output, into: &result) { return result }
        if parseSwiftTesting(output, into: &result) { return result }
        if parseCargoRust(output, into: &result) { return result }
        if parsePytest(output, into: &result) { return result }
        if parseGoTest(output, into: &result) { return result }
        if parseJest(output, into: &result) { return result }

        // Fallback: collect individual failed test names without counts.
        parseFailedTestNames(output, into: &result)
        return result
    }

    // MARK: Swift / XCTest

    // "Test Suite '...' passed at ... executed 5 tests, with 0 failures"
    // "Test Case '-[…SomeTests testSomething]' failed (0.001 seconds)."
    private static let reXCSuiteSummary = try! NSRegularExpression(
        pattern: #"executed (\d+) tests?, with (\d+) failures?"#
    )
    private static let reXCCaseFailed = try! NSRegularExpression(
        pattern: #"Test Case '(.+?)' failed"#
    )

    @discardableResult
    private static func parseSwiftXCTest(_ output: String, into result: inout ParsedResult) -> Bool {
        var found = false
        for line in output.components(separatedBy: "\n") {
            if let m = reXCSuiteSummary.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
               m.numberOfRanges == 3,
               let totalStr = captureGroup(line, m, 1),
               let failStr  = captureGroup(line, m, 2),
               let total    = Int(totalStr),
               let fails    = Int(failStr) {
                result.totalPassed = max(total - fails, 0)
                found = true
            }
            if let m = reXCCaseFailed.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
               m.numberOfRanges == 2,
               let name = captureGroup(line, m, 1) {
                result.failedTests.append(name)
            }
        }
        return found
    }

    // MARK: Swift Testing (swift-testing package)

    // "✔ Test testSomething() passed after 0.001 seconds."
    // "✗ Test testBadCase() failed after 0.001 seconds."
    // These use Unicode checkmark/cross characters emitted by the swift-testing runner.
    private static let reSwiftTestingPass = try! NSRegularExpression(
        pattern: "✔ Test (.+?) (?:passed|started)"
    )
    private static let reSwiftTestingFail = try! NSRegularExpression(
        pattern: "✗ Test (.+?) failed"
    )

    @discardableResult
    private static func parseSwiftTesting(_ output: String, into result: inout ParsedResult) -> Bool {
        var passCount = 0
        var found = false
        for line in output.components(separatedBy: "\n") {
            if reSwiftTestingPass.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil {
                passCount += 1
                found = true
            }
            if let m = reSwiftTestingFail.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
               m.numberOfRanges == 2,
               let name = captureGroup(line, m, 1) {
                result.failedTests.append(name)
                found = true
            }
        }
        if found { result.totalPassed = passCount }
        return found
    }

    // MARK: Cargo / rustc

    // "test result: ok. 5 passed; 0 failed;"
    // "test result: FAILED. 4 passed; 1 failed;"
    // "test module::test_name ... FAILED"
    private static let reCargoSummary = try! NSRegularExpression(
        pattern: #"test result: (?:ok|FAILED)\. (\d+) passed; (\d+) failed"#
    )
    private static let reCargoFailed = try! NSRegularExpression(
        pattern: #"^test (.+?) \.\.\. FAILED$"#
    )

    @discardableResult
    private static func parseCargoRust(_ output: String, into result: inout ParsedResult) -> Bool {
        var found = false
        for line in output.components(separatedBy: "\n") {
            if let m = reCargoSummary.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
               m.numberOfRanges == 3,
               let passStr = captureGroup(line, m, 1),
               let passed  = Int(passStr) {
                result.totalPassed = passed
                found = true
            }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let m = reCargoFailed.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
               m.numberOfRanges == 2,
               let name = captureGroup(trimmed, m, 1) {
                result.failedTests.append(name)
            }
        }
        return found
    }

    // MARK: pytest

    // Summary line: "5 passed, 1 failed in 0.12s" or "3 passed" or "2 failed"
    // Failed line:  "FAILED test_file.py::test_something - AssertionError"
    private static let rePytestSummary = try! NSRegularExpression(
        pattern: #"(\d+) passed"#
    )
    private static let rePytestFailed = try! NSRegularExpression(
        pattern: #"^FAILED (.+?) -"#
    )

    @discardableResult
    private static func parsePytest(_ output: String, into result: inout ParsedResult) -> Bool {
        var found = false
        for line in output.components(separatedBy: "\n") {
            if let m = rePytestSummary.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
               m.numberOfRanges == 2,
               let passStr = captureGroup(line, m, 1),
               let passed  = Int(passStr) {
                result.totalPassed = passed
                found = true
            }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let m = rePytestFailed.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
               m.numberOfRanges == 2,
               let name = captureGroup(trimmed, m, 1) {
                result.failedTests.append(name)
            }
        }
        return found
    }

    // MARK: Go test

    // "--- PASS: TestSomething (0.00s)"
    // "--- FAIL: TestSomething (0.00s)"
    private static let reGoPass = try! NSRegularExpression(
        pattern: #"^--- PASS: (\S+)"#
    )
    private static let reGoFail = try! NSRegularExpression(
        pattern: #"^--- FAIL: (\S+)"#
    )

    @discardableResult
    private static func parseGoTest(_ output: String, into result: inout ParsedResult) -> Bool {
        var passCount = 0
        var found = false
        for line in output.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if reGoPass.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)) != nil {
                passCount += 1
                found = true
            }
            if let m = reGoFail.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
               m.numberOfRanges == 2,
               let name = captureGroup(trimmed, m, 1) {
                result.failedTests.append(name)
                found = true
            }
        }
        if found { result.totalPassed = passCount }
        return found
    }

    // MARK: Jest / Mocha

    // "  5 passing (2s)"  /  "  2 failing"
    // Jest: "Tests:   1 failed, 4 passed, 5 total"
    private static let reJestSummary = try! NSRegularExpression(
        pattern: #"Tests:\s+(?:\d+ failed,\s*)?(\d+) passed"#
    )
    private static let reMochaPassing = try! NSRegularExpression(
        pattern: #"^\s+(\d+) passing"#
    )

    @discardableResult
    private static func parseJest(_ output: String, into result: inout ParsedResult) -> Bool {
        for line in output.components(separatedBy: "\n") {
            if let m = reJestSummary.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
               m.numberOfRanges == 2,
               let passStr = captureGroup(line, m, 1),
               let passed  = Int(passStr) {
                result.totalPassed = passed
                return true
            }
            if let m = reMochaPassing.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
               m.numberOfRanges == 2,
               let passStr = captureGroup(line, m, 1),
               let passed  = Int(passStr) {
                result.totalPassed = passed
                return true
            }
        }
        return false
    }

    // MARK: Fallback: collect failed test names by common patterns

    private static let reGenericFail = try! NSRegularExpression(
        pattern: #"(?:FAIL(?:ED)?|✗|×)\s+(.+)"#
    )

    private static func parseFailedTestNames(_ output: String, into result: inout ParsedResult) {
        for line in output.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let m = reGenericFail.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
               m.numberOfRanges == 2,
               let name = captureGroup(trimmed, m, 1) {
                let cleaned = name.trimmingCharacters(in: .whitespaces)
                if !cleaned.isEmpty {
                    result.failedTests.append(cleaned)
                }
            }
        }
    }

    // MARK: Helpers

    private static func captureGroup(_ s: String, _ m: NSTextCheckingResult, _ index: Int) -> String? {
        let r = m.range(at: index)
        guard r.location != NSNotFound, let range = Range(r, in: s) else { return nil }
        return String(s[range])
    }
}
