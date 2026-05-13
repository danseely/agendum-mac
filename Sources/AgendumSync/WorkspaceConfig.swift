import Foundation

public struct WorkspaceRuntimePaths: Equatable, Sendable {
    public var workspaceRoot: URL
    public var configPath: URL
    public var dbPath: URL
    public var ghConfigDir: URL

    public var configDir: URL { workspaceRoot }

    public init(workspaceRoot: URL) {
        let root = workspaceRoot.expandingTildeInPath()
        self.workspaceRoot = root
        self.configPath = root.appendingPathComponent("config.toml")
        self.dbPath = root.appendingPathComponent("agendum.db")
        self.ghConfigDir = root.appendingPathComponent("gh")
    }

    public static func defaultBaseDirectory() -> URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".agendum")
    }

    public static func workspace(
        namespace: String?,
        baseDirectory: URL = defaultBaseDirectory()
    ) throws -> WorkspaceRuntimePaths {
        let base = baseDirectory.expandingTildeInPath()
        guard let normalized = try normalizeNamespace(namespace) else {
            return WorkspaceRuntimePaths(workspaceRoot: base)
        }
        return WorkspaceRuntimePaths(
            workspaceRoot: base
                .appendingPathComponent("workspaces")
                .appendingPathComponent(normalized.lowercased())
        )
    }

    public static func normalizeNamespace(_ namespace: String?) throws -> String? {
        guard let namespace else { return nil }
        let normalized = namespace.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.isEmpty { return nil }
        if normalized.contains("/") {
            throw WorkspaceConfigError.invalidNamespace("enter a GitHub owner name, not owner/repo")
        }
        if normalized.rangeOfCharacter(from: .alphanumerics) == nil {
            throw WorkspaceConfigError.invalidNamespace("enter at least one letter or number")
        }
        if normalized.contains("--") || !isGitHubOwnerName(normalized) {
            throw WorkspaceConfigError.invalidNamespace("enter a valid GitHub owner name")
        }
        return normalized
    }
}

public struct WorkspaceConfig: Equatable, Sendable {
    public var orgs: [String]
    public var repos: [String]
    public var excludeRepos: [String]
    public var syncInterval: Int
    public var seenDelay: Int

    public init(
        orgs: [String] = [],
        repos: [String] = [],
        excludeRepos: [String] = [],
        syncInterval: Int = 120,
        seenDelay: Int = 3
    ) {
        self.orgs = orgs
        self.repos = repos
        self.excludeRepos = excludeRepos
        self.syncInterval = syncInterval
        self.seenDelay = seenDelay
    }

    public var repoConfig: WorkspaceRepoConfig {
        WorkspaceRepoConfig(
            repos: repos,
            orgs: orgs,
            excludeRepos: Set(excludeRepos)
        )
    }

    public static func load(from url: URL) throws -> WorkspaceConfig {
        let fileURL = url.expandingTildeInPath()
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return WorkspaceConfig()
        }
        let text = try String(contentsOf: fileURL, encoding: .utf8)
        return try parse(text)
    }

    /// Creates a missing workspace config, then loads it. Mirrors Python
    /// `ensure_workspace_config`: base workspaces get empty defaults; namespace
    /// workspaces seed `orgs` with that namespace unless an existing config
    /// already has non-empty `orgs` or `repos`.
    public static func ensure(
        paths: WorkspaceRuntimePaths,
        namespace: String? = nil
    ) throws -> WorkspaceConfig {
        let normalizedNamespace = try WorkspaceRuntimePaths.normalizeNamespace(namespace)
        let root = paths.workspaceRoot.expandingTildeInPath()
        let configPath = paths.configPath.expandingTildeInPath()
        try createPrivateDirectory(root)

        if FileManager.default.fileExists(atPath: configPath.path) {
            let config = try load(from: configPath)
            if !config.orgs.isEmpty || !config.repos.isEmpty || normalizedNamespace == nil {
                return config
            }
            let seeded = defaultWorkspaceConfig(namespace: normalizedNamespace, seed: config)
            try write(config: seeded, to: configPath)
            return try load(from: configPath)
        }

        let config = defaultWorkspaceConfig(namespace: normalizedNamespace, seed: nil)
        try write(config: config, to: configPath)
        return try load(from: configPath)
    }

    public static func parse(_ text: String) throws -> WorkspaceConfig {
        var config = WorkspaceConfig()
        var section = ""

        for logicalLine in try logicalConfigLines(text) {
            let lineNumber = logicalLine.line
            let line = logicalLine.text
            if line.hasPrefix("[") {
                guard line.hasSuffix("]"), line.count > 2 else {
                    throw WorkspaceConfigError.invalidSyntax(line: lineNumber, message: "Invalid section header.")
                }
                section = String(line.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
                continue
            }

            let parts = line.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else {
                throw WorkspaceConfigError.invalidSyntax(line: lineNumber, message: "Expected key = value.")
            }

            let key = String(parts[0]).trimmingCharacters(in: .whitespacesAndNewlines)
            let value = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)

            switch (section, key) {
            case ("github", "orgs"):
                config.orgs = try parseStringArray(value, line: lineNumber, key: key)
            case ("github", "repos"):
                config.repos = try parseStringArray(value, line: lineNumber, key: key)
            case ("github", "exclude_repos"):
                config.excludeRepos = try parseStringArray(value, line: lineNumber, key: key)
            case ("sync", "interval"):
                config.syncInterval = try parseInt(value, line: lineNumber, key: key)
            case ("display", "seen_delay"):
                config.seenDelay = try parseInt(value, line: lineNumber, key: key)
            default:
                continue
            }
        }

        return config
    }
}

private func defaultWorkspaceConfig(namespace: String?, seed: WorkspaceConfig?) -> WorkspaceConfig {
    let seed = seed ?? WorkspaceConfig()
    guard let namespace else { return seed }
    return WorkspaceConfig(
        orgs: [namespace],
        repos: [],
        excludeRepos: [],
        syncInterval: seed.syncInterval,
        seenDelay: seed.seenDelay
    )
}

private func write(config: WorkspaceConfig, to url: URL) throws {
    let fileURL = url.expandingTildeInPath()
    try createPrivateDirectory(fileURL.deletingLastPathComponent())
    let text = try render(config: config)
    try text.write(to: fileURL, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
}

private func createPrivateDirectory(_ url: URL) throws {
    let directory = url.expandingTildeInPath()
    try FileManager.default.createDirectory(
        at: directory,
        withIntermediateDirectories: true,
        attributes: [.posixPermissions: 0o700]
    )
    try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
}

private func render(config: WorkspaceConfig) throws -> String {
    try [
        "[github]",
        "# GitHub org(s) to scan",
        "orgs = \(renderArray(config.orgs))",
        "",
        #"# Explicit repo whitelist ("owner/repo" format)."#,
        "# If set, only these repos are synced - org-wide discovery is skipped.",
        "repos = \(renderArray(config.repos))",
        "",
        #"# Repos to exclude (optional, "owner/repo" format)"#,
        "exclude_repos = \(renderArray(config.excludeRepos))",
        "",
        "[sync]",
        "# Poll interval in seconds",
        "interval = \(config.syncInterval)",
        "",
        "[display]",
        "# Seconds after focus before marking items seen",
        "seen_delay = \(config.seenDelay)",
        "",
    ].joined(separator: "\n")
}

private func renderArray(_ values: [String]) throws -> String {
    let data = try JSONEncoder().encode(values)
    return String(decoding: data, as: UTF8.self)
}

private struct LogicalConfigLine {
    var line: Int
    var text: String
}

public enum WorkspaceConfigError: Error, Equatable, Sendable, LocalizedError {
    case invalidSyntax(line: Int, message: String)
    case invalidValue(line: Int, key: String, expected: String)
    case invalidNamespace(String)

    public var errorDescription: String? {
        switch self {
        case .invalidSyntax(let line, let message):
            return "Invalid workspace config at line \(line): \(message)"
        case .invalidValue(let line, let key, let expected):
            return "Invalid workspace config value for \(key) at line \(line): expected \(expected)."
        case .invalidNamespace(let message):
            return "Invalid workspace namespace: \(message)."
        }
    }
}

private func isGitHubOwnerName(_ value: String) -> Bool {
    let scalars = Array(value.unicodeScalars)
    guard (1...39).contains(scalars.count),
          isGitHubOwnerEdge(scalars[0]),
          isGitHubOwnerEdge(scalars[scalars.count - 1]) else {
        return false
    }
    return scalars.allSatisfy { scalar in
        isGitHubOwnerEdge(scalar) || scalar == "-"
    }
}

private func isGitHubOwnerEdge(_ scalar: UnicodeScalar) -> Bool {
    (65...90).contains(scalar.value)
        || (97...122).contains(scalar.value)
        || (48...57).contains(scalar.value)
}

private func parseInt(_ raw: String, line: Int, key: String) throws -> Int {
    guard let value = Int(raw) else {
        throw WorkspaceConfigError.invalidValue(line: line, key: key, expected: "integer")
    }
    return value
}

private func parseStringArray(_ raw: String, line: Int, key: String) throws -> [String] {
    let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard value.hasPrefix("["), value.hasSuffix("]") else {
        throw WorkspaceConfigError.invalidValue(line: line, key: key, expected: "array of strings")
    }

    let body = String(value.dropFirst().dropLast())
    var result: [String] = []
    var index = body.startIndex

    func skipWhitespace() {
        while index < body.endIndex, body[index].isWhitespace {
            index = body.index(after: index)
        }
    }

    skipWhitespace()
    while index < body.endIndex {
        let quote = body[index]
        guard quote == "\"" || quote == "'" else {
            throw WorkspaceConfigError.invalidValue(line: line, key: key, expected: "array of strings")
        }
        index = body.index(after: index)

        var item = ""
        var closed = false
        while index < body.endIndex {
            let char = body[index]
            index = body.index(after: index)

            if char == quote {
                closed = true
                break
            }
            if quote == "\"", char == "\\", index < body.endIndex {
                let escaped = body[index]
                index = body.index(after: index)
                item.append(escaped)
            } else {
                item.append(char)
            }
        }
        guard closed else {
            throw WorkspaceConfigError.invalidValue(line: line, key: key, expected: "array of strings")
        }
        result.append(item)

        skipWhitespace()
        if index == body.endIndex { break }
        guard body[index] == "," else {
            throw WorkspaceConfigError.invalidValue(line: line, key: key, expected: "array of strings")
        }
        index = body.index(after: index)
        skipWhitespace()
    }

    return result
}

private func logicalConfigLines(_ text: String) throws -> [LogicalConfigLine] {
    var lines: [LogicalConfigLine] = []
    var buffer = ""
    var bufferStartLine: Int?

    for (offset, rawLine) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
        let lineNumber = offset + 1
        let stripped = stripComment(String(rawLine)).trimmingCharacters(in: .whitespacesAndNewlines)
        if stripped.isEmpty { continue }

        if bufferStartLine == nil {
            bufferStartLine = lineNumber
        }
        buffer += buffer.isEmpty ? stripped : " \(stripped)"

        if bracketBalance(buffer) <= 0 {
            lines.append(LogicalConfigLine(line: bufferStartLine ?? lineNumber, text: buffer))
            buffer = ""
            bufferStartLine = nil
        }
    }

    if !buffer.isEmpty {
        throw WorkspaceConfigError.invalidSyntax(
            line: bufferStartLine ?? 1,
            message: "Unterminated array value."
        )
    }

    return lines
}

private func bracketBalance(_ line: String) -> Int {
    var balance = 0
    var quote: Character?
    var escaped = false

    for char in line {
        if escaped {
            escaped = false
            continue
        }
        if quote == "\"", char == "\\" {
            escaped = true
            continue
        }
        if char == "\"" || char == "'" {
            if quote == char {
                quote = nil
            } else if quote == nil {
                quote = char
            }
            continue
        }
        guard quote == nil else { continue }
        if char == "[" { balance += 1 }
        if char == "]" { balance -= 1 }
    }

    return balance
}

private func stripComment(_ line: String) -> String {
    var output = ""
    var quote: Character?
    var escaped = false

    for char in line {
        if escaped {
            output.append(char)
            escaped = false
            continue
        }
        if quote == "\"", char == "\\" {
            output.append(char)
            escaped = true
            continue
        }
        if char == "\"" || char == "'" {
            if quote == char {
                quote = nil
            } else if quote == nil {
                quote = char
            }
            output.append(char)
            continue
        }
        if char == "#", quote == nil {
            break
        }
        output.append(char)
    }

    return output
}

private extension URL {
    func expandingTildeInPath() -> URL {
        guard path.hasPrefix("~/") else { return self }
        return URL(fileURLWithPath: NSString(string: path).expandingTildeInPath)
    }
}
