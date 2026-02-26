import XCTest
@testable import Anvil

final class SensitiveFileClassifierTests: XCTestCase {

    // MARK: - CI/CD configs

    func testGitHubWorkflow() {
        XCTAssertTrue(SensitiveFileClassifier.isSensitive(".github/workflows/ci.yml"))
        XCTAssertTrue(SensitiveFileClassifier.isSensitive(".github/workflows/release.yaml"))
    }

    func testGitLabCI() {
        XCTAssertTrue(SensitiveFileClassifier.isSensitive(".gitlab-ci.yml"))
    }

    func testJenkinsfile() {
        XCTAssertTrue(SensitiveFileClassifier.isSensitive("Jenkinsfile"))
    }

    // MARK: - Dependency manifests

    func testPackageJson() {
        XCTAssertTrue(SensitiveFileClassifier.isSensitive("package.json"))
    }

    func testPackageLockJson() {
        XCTAssertTrue(SensitiveFileClassifier.isSensitive("package-lock.json"))
    }

    func testPackageSwift() {
        XCTAssertTrue(SensitiveFileClassifier.isSensitive("Package.swift"))
    }

    func testPodfile() {
        XCTAssertTrue(SensitiveFileClassifier.isSensitive("Podfile"))
        XCTAssertTrue(SensitiveFileClassifier.isSensitive("Podfile.lock"))
    }

    func testRequirementsTxt() {
        XCTAssertTrue(SensitiveFileClassifier.isSensitive("requirements.txt"))
    }

    func testGoMod() {
        XCTAssertTrue(SensitiveFileClassifier.isSensitive("go.mod"))
        XCTAssertTrue(SensitiveFileClassifier.isSensitive("go.sum"))
    }

    func testCargoToml() {
        XCTAssertTrue(SensitiveFileClassifier.isSensitive("Cargo.toml"))
        XCTAssertTrue(SensitiveFileClassifier.isSensitive("Cargo.lock"))
    }

    // MARK: - Docker

    func testDockerfileRootLevel() {
        XCTAssertTrue(SensitiveFileClassifier.isSensitive("Dockerfile"))
    }

    func testDockerfileVariant() {
        XCTAssertTrue(SensitiveFileClassifier.isSensitive("Dockerfile.prod"))
    }

    func testDockerfileInSubdirectory() {
        XCTAssertTrue(SensitiveFileClassifier.isSensitive("docker/Dockerfile"))
        XCTAssertTrue(SensitiveFileClassifier.isSensitive("services/api/Dockerfile"))
    }

    func testDockerCompose() {
        XCTAssertTrue(SensitiveFileClassifier.isSensitive("docker-compose.yml"))
        XCTAssertTrue(SensitiveFileClassifier.isSensitive("docker-compose.prod.yml"))
    }

    // MARK: - Environment files

    func testEnvFile() {
        XCTAssertTrue(SensitiveFileClassifier.isSensitive(".env"))
        XCTAssertTrue(SensitiveFileClassifier.isSensitive(".env.local"))
        XCTAssertTrue(SensitiveFileClassifier.isSensitive(".env.production"))
    }

    func testEnvInSubdirectory() {
        XCTAssertTrue(SensitiveFileClassifier.isSensitive("config/.env"))
        XCTAssertTrue(SensitiveFileClassifier.isSensitive("services/api/.env.local"))
    }

    // MARK: - Makefile

    func testMakefile() {
        XCTAssertTrue(SensitiveFileClassifier.isSensitive("Makefile"))
        XCTAssertTrue(SensitiveFileClassifier.isSensitive("GNUmakefile"))
    }

    // MARK: - Security-related paths

    func testSecurityDirectory() {
        XCTAssertTrue(SensitiveFileClassifier.isSensitive("Sources/auth/LoginManager.swift"))
        XCTAssertTrue(SensitiveFileClassifier.isSensitive("src/security/Validator.ts"))
        XCTAssertTrue(SensitiveFileClassifier.isSensitive("app/credentials/KeychainHelper.swift"))
    }

    func testCertificateFiles() {
        XCTAssertTrue(SensitiveFileClassifier.isSensitive("certs/server.pem"))
        XCTAssertTrue(SensitiveFileClassifier.isSensitive("keys/api.key"))
        XCTAssertTrue(SensitiveFileClassifier.isSensitive("certificates/client.p12"))
    }

    // MARK: - Shell scripts

    func testShellScripts() {
        XCTAssertTrue(SensitiveFileClassifier.isSensitive("deploy.sh"))
        XCTAssertTrue(SensitiveFileClassifier.isSensitive("scripts/bootstrap.sh"))
    }

    // MARK: - Non-sensitive files

    func testRegularSwiftFile() {
        XCTAssertFalse(SensitiveFileClassifier.isSensitive("Sources/Anvil/ContentView.swift"))
    }

    func testRegularTypeScriptFile() {
        XCTAssertFalse(SensitiveFileClassifier.isSensitive("src/components/Button.tsx"))
    }

    func testRegularTestFile() {
        XCTAssertFalse(SensitiveFileClassifier.isSensitive("Tests/AnvilTests/CommitMessageTests.swift"))
    }

    func testReadmeFile() {
        XCTAssertFalse(SensitiveFileClassifier.isSensitive("README.md"))
    }

    // MARK: - Pattern matching helpers

    func testExactPatternMatch() {
        XCTAssertTrue(SensitiveFileClassifier.patternMatches("Makefile", path: "Makefile"))
        XCTAssertFalse(SensitiveFileClassifier.patternMatches("Makefile", path: "makefile"))
    }

    func testSingleStarWildcard() {
        XCTAssertTrue(SensitiveFileClassifier.patternMatches(".github/workflows/*", path: ".github/workflows/ci.yml"))
        XCTAssertFalse(SensitiveFileClassifier.patternMatches(".github/workflows/*", path: ".github/actions/ci.yml"))
    }

    func testDoubleStarWildcard() {
        XCTAssertTrue(SensitiveFileClassifier.patternMatches("**/Dockerfile", path: "Dockerfile"))
        XCTAssertTrue(SensitiveFileClassifier.patternMatches("**/Dockerfile", path: "docker/Dockerfile"))
        XCTAssertTrue(SensitiveFileClassifier.patternMatches("**/Dockerfile", path: "a/b/c/Dockerfile"))
    }

    func testDoubleStarInMiddle() {
        XCTAssertTrue(SensitiveFileClassifier.patternMatches("**/auth/**", path: "Sources/auth/Login.swift"))
        XCTAssertTrue(SensitiveFileClassifier.patternMatches("**/auth/**", path: "auth/api/Token.swift"))
    }

    func testGlobExtension() {
        XCTAssertTrue(SensitiveFileClassifier.patternMatches("*.tf", path: "main.tf"))
        XCTAssertTrue(SensitiveFileClassifier.patternMatches("*.tf", path: "variables.tf"))
        XCTAssertFalse(SensitiveFileClassifier.patternMatches("*.tf", path: "dir/main.tf"))
    }

    func testDotEnvWithSuffix() {
        XCTAssertTrue(SensitiveFileClassifier.patternMatches(".env.*", path: ".env.local"))
        XCTAssertTrue(SensitiveFileClassifier.patternMatches(".env.*", path: ".env.production"))
    }
}
