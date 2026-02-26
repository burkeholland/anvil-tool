import XCTest
@testable import Anvil

final class TestResultParserTests: XCTestCase {

    // MARK: - Swift / XCTest

    func testXCTestPassedSummary() {
        let output = """
        Test Suite 'AllTests' started at 2024-01-01 00:00:00.000
        Test Suite 'MyTests' started at 2024-01-01 00:00:00.001
        Test Case '-[MyTests testFoo]' started.
        Test Case '-[MyTests testFoo]' passed (0.001 seconds).
        Test Case '-[MyTests testBar]' started.
        Test Case '-[MyTests testBar]' passed (0.001 seconds).
        Test Suite 'MyTests' passed at 2024-01-01 00:00:00.003.
             Executed 2 tests, with 0 failures (0 unexpected) in 0.002 (0.003) seconds
        Test Suite 'AllTests' passed at 2024-01-01 00:00:00.004.
             Executed 2 tests, with 0 failures (0 unexpected) in 0.002 (0.004) seconds
        """
        let result = TestResultParser.parse(output)
        XCTAssertEqual(result.totalPassed, 2)
        XCTAssertTrue(result.failedTests.isEmpty)
    }

    func testXCTestFailedSummary() {
        let output = """
        Test Case '-[MyTests testBad]' started.
        Test Case '-[MyTests testBad]' failed (0.001 seconds).
        Test Case '-[MyTests testGood]' started.
        Test Case '-[MyTests testGood]' passed (0.001 seconds).
        Executed 2 tests, with 1 failure (0 unexpected) in 0.002 (0.003) seconds
        """
        let result = TestResultParser.parse(output)
        XCTAssertEqual(result.totalPassed, 1)
        XCTAssertEqual(result.failedTests.count, 1)
        XCTAssertTrue(result.failedTests[0].contains("testBad"))
    }

    // MARK: - Cargo / rustc

    func testCargoAllPassed() {
        let output = """
        running 3 tests
        test math::test_add ... ok
        test math::test_sub ... ok
        test math::test_mul ... ok
        test result: ok. 3 passed; 0 failed; 0 ignored; 0 measured; 0 filtered out
        """
        let result = TestResultParser.parse(output)
        XCTAssertEqual(result.totalPassed, 3)
        XCTAssertTrue(result.failedTests.isEmpty)
    }

    func testCargoSomeFailed() {
        let output = """
        running 3 tests
        test math::test_add ... ok
        test math::test_sub ... FAILED
        test math::test_mul ... ok
        test result: FAILED. 2 passed; 1 failed; 0 ignored; 0 measured; 0 filtered out
        """
        let result = TestResultParser.parse(output)
        XCTAssertEqual(result.totalPassed, 2)
        XCTAssertEqual(result.failedTests, ["math::test_sub"])
    }

    // MARK: - pytest

    func testPytestAllPassed() {
        let output = """
        ============================= test session starts ==============================
        collected 4 items

        test_math.py ....

        ============================== 4 passed in 0.05s ===============================
        """
        let result = TestResultParser.parse(output)
        XCTAssertEqual(result.totalPassed, 4)
        XCTAssertTrue(result.failedTests.isEmpty)
    }

    func testPytestSomeFailed() {
        let output = """
        FAILED test_math.py::test_add - AssertionError: assert 1 == 2
        FAILED test_math.py::test_sub - AssertionError
        ========================= 2 failed, 3 passed in 0.06s ==========================
        """
        let result = TestResultParser.parse(output)
        XCTAssertEqual(result.totalPassed, 3)
        XCTAssertEqual(result.failedTests, ["test_math.py::test_add", "test_math.py::test_sub"])
    }

    // MARK: - Go test

    func testGoTestAllPassed() {
        let output = """
        --- PASS: TestAdd (0.00s)
        --- PASS: TestSub (0.00s)
        --- PASS: TestMul (0.00s)
        PASS
        ok      mypackage       0.001s
        """
        let result = TestResultParser.parse(output)
        XCTAssertEqual(result.totalPassed, 3)
        XCTAssertTrue(result.failedTests.isEmpty)
    }

    func testGoTestSomeFailed() {
        let output = """
        --- PASS: TestAdd (0.00s)
        --- FAIL: TestSub (0.00s)
        --- PASS: TestMul (0.00s)
        FAIL
        FAIL    mypackage       0.001s
        """
        let result = TestResultParser.parse(output)
        XCTAssertEqual(result.totalPassed, 2)
        XCTAssertEqual(result.failedTests, ["TestSub"])
    }

    // MARK: - Swift Testing (swift-testing package)

    func testSwiftTestingAllPassed() {
        let output = """
        ◇ Test testAdd() started.
        ✔ Test testAdd() passed after 0.001 seconds.
        ◇ Test testSub() started.
        ✔ Test testSub() passed after 0.001 seconds.
        """
        let result = TestResultParser.parse(output)
        XCTAssertEqual(result.totalPassed, 2)
        XCTAssertTrue(result.failedTests.isEmpty)
    }

    func testSwiftTestingSomeFailed() {
        let output = """
        ◇ Test testAdd() started.
        ✔ Test testAdd() passed after 0.001 seconds.
        ◇ Test testBad() started.
        ✗ Test testBad() failed after 0.001 seconds.
        """
        let result = TestResultParser.parse(output)
        XCTAssertEqual(result.totalPassed, 1)
        XCTAssertEqual(result.failedTests.count, 1)
        XCTAssertTrue(result.failedTests[0].contains("testBad"))
    }

    // MARK: - Jest / Mocha

    func testJestSummary() {
        let output = """
        Tests:   1 failed, 4 passed, 5 total
        Test Suites: 1 failed, 2 passed, 3 total
        """
        let result = TestResultParser.parse(output)
        XCTAssertEqual(result.totalPassed, 4)
    }

    func testMochaSummary() {
        let output = """
          5 passing (2s)
          1 failing
        """
        let result = TestResultParser.parse(output)
        XCTAssertEqual(result.totalPassed, 5)
    }
}
