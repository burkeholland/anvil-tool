import Foundation

/// Classifies changed files as sensitive based on their relative paths.
/// Sensitive files are those that commonly require careful review before committing,
/// such as CI/CD configs, dependency manifests, Dockerfiles, environment configs,
/// and security-related files.
enum SensitiveFileClassifier {

    /// Glob-style patterns for files that require careful review.
    /// Each entry is a pattern where `*` matches any segment within a path component
    /// and `**` matches across multiple path components.
    static let sensitivePatterns: [String] = [
        // CI/CD configs
        ".github/workflows/*",
        ".gitlab-ci.yml",
        ".circleci/config.yml",
        "Jenkinsfile",
        ".travis.yml",
        "azure-pipelines.yml",
        ".buildkite/*",
        "bitbucket-pipelines.yml",

        // Dependency manifests
        "package.json",
        "package-lock.json",
        "yarn.lock",
        "Package.swift",
        "Podfile",
        "Podfile.lock",
        "Gemfile",
        "Gemfile.lock",
        "Pipfile",
        "Pipfile.lock",
        "requirements.txt",
        "pyproject.toml",
        "setup.py",
        "setup.cfg",
        "go.mod",
        "go.sum",
        "Cargo.toml",
        "Cargo.lock",
        "pom.xml",
        "build.gradle",
        "build.gradle.kts",
        "*.gemspec",

        // Dockerfiles and container configs
        "Dockerfile",
        "Dockerfile.*",
        "**/Dockerfile",
        "**/Dockerfile.*",
        "docker-compose.yml",
        "docker-compose.*.yml",
        ".dockerignore",

        // Environment and secrets
        ".env",
        ".env.*",
        "**/.env",
        "**/.env.*",

        // Makefiles and build scripts
        "Makefile",
        "GNUmakefile",
        "makefile",

        // Infrastructure as code
        "*.tf",
        "*.tfvars",
        "terraform.tfvars",

        // Security-related paths
        "**/auth/**",
        "**/security/**",
        "**/credentials/**",
        "**/secrets/**",
        "**/*.pem",
        "**/*.key",
        "**/*.p12",
        "**/*.pfx",
        "**/*.cer",
        "**/*.crt",

        // Nginx / server configs
        "nginx.conf",
        "**/nginx/**",

        // Shell scripts
        "*.sh",
        "*.bash",
    ]

    /// Returns `true` if the given relative path matches any sensitive pattern.
    static func isSensitive(_ relativePath: String) -> Bool {
        let normalized = relativePath.hasPrefix("/") ? String(relativePath.dropFirst()) : relativePath
        return sensitivePatterns.contains { patternMatches($0, path: normalized) }
    }

    /// Lightweight glob match that supports `*` (within a path segment) and `**` (across segments).
    static func patternMatches(_ pattern: String, path: String) -> Bool {
        // Fast-path: exact match
        if pattern == path { return true }

        let patternParts = pattern.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        let pathParts    = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)

        return matchParts(patternParts[...], pathParts[...])
    }

    private static func matchParts(_ pattern: ArraySlice<String>, _ path: ArraySlice<String>) -> Bool {
        var pat = pattern
        var pth = path

        while !pat.isEmpty {
            let head = pat.removeFirst()

            if head == "**" {
                // `**` matches zero or more path segments
                if pat.isEmpty { return true }
                // Try matching the rest of the pattern against every possible suffix of `pth`
                for i in pth.startIndex...pth.endIndex {
                    if matchParts(pat, pth[i...]) { return true }
                }
                return false
            }

            guard !pth.isEmpty else { return false }
            let pathHead = pth.removeFirst()
            if !segmentMatches(head, pathHead) { return false }
        }

        return pth.isEmpty
    }

    /// Matches a single path segment against a pattern segment that may contain `*` wildcards.
    private static func segmentMatches(_ pattern: String, _ segment: String) -> Bool {
        if pattern == "*" { return true }
        if !pattern.contains("*") { return pattern == segment }

        // Convert the segment pattern to a regex by escaping special chars and replacing `*`
        var regexStr = "^"
        for ch in pattern {
            switch ch {
            case "*":  regexStr += ".*"
            case ".":  regexStr += "\\."
            case "^", "$", "+", "?", "(", ")", "[", "]", "{", "}", "|", "\\":
                       regexStr += "\\\(ch)"
            default:   regexStr += String(ch)
            }
        }
        regexStr += "$"

        return (try? NSRegularExpression(pattern: regexStr))
            .map { regex in
                let range = NSRange(segment.startIndex..., in: segment)
                return regex.firstMatch(in: segment, range: range) != nil
            } ?? false
    }
}
