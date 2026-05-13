import Foundation
import Testing
@testable import AgendumSync

@Suite struct WorkspaceConfigTests {

    @Test func missingConfigLoadsDefaults() throws {
        let directory = try temporaryDirectory()
        let config = try WorkspaceConfig.load(from: directory.appendingPathComponent("missing.toml"))

        #expect(config == WorkspaceConfig())
    }

    @Test func baseMissingConfigCreatesEmptyDefaults() throws {
        let base = try temporaryDirectory()
        let paths = try WorkspaceRuntimePaths.workspace(namespace: nil, baseDirectory: base)

        let config = try WorkspaceConfig.ensure(paths: paths, namespace: nil)

        #expect(config == WorkspaceConfig())
        #expect(FileManager.default.fileExists(atPath: paths.configPath.path))
        #expect(try String(contentsOf: paths.configPath).contains("orgs = []"))
        #expect(try posixMode(paths.configPath) == 0o600)
    }

    @Test func namespaceMissingConfigSeedsNamespaceOrgAndLoadsIt() throws {
        let base = try temporaryDirectory()
        let paths = try WorkspaceRuntimePaths.workspace(namespace: " Example-Org ", baseDirectory: base)

        let config = try WorkspaceConfig.ensure(paths: paths, namespace: " Example-Org ")

        #expect(paths.workspaceRoot.path.hasSuffix("/workspaces/example-org"))
        #expect(config == WorkspaceConfig(orgs: ["Example-Org"], repos: [], excludeRepos: [], syncInterval: 120, seenDelay: 3))
        #expect(try String(contentsOf: paths.configPath).contains(#"orgs = ["Example-Org"]"#))
        #expect(try posixMode(paths.workspaceRoot) == 0o700)
        #expect(try posixMode(paths.configPath) == 0o600)
    }

    @Test func namespaceExistingConfigWithReposIsPreserved() throws {
        let base = try temporaryDirectory()
        let paths = try WorkspaceRuntimePaths.workspace(namespace: "Example-Org", baseDirectory: base)
        try FileManager.default.createDirectory(at: paths.workspaceRoot, withIntermediateDirectories: true)
        try """
        [github]
        orgs = []
        repos = ["custom/repo"]
        exclude_repos = ["custom/skip"]

        [sync]
        interval = 45

        [display]
        seen_delay = 8
        """.write(to: paths.configPath, atomically: true, encoding: .utf8)

        let config = try WorkspaceConfig.ensure(paths: paths, namespace: "Example-Org")

        #expect(config == WorkspaceConfig(
            orgs: [],
            repos: ["custom/repo"],
            excludeRepos: ["custom/skip"],
            syncInterval: 45,
            seenDelay: 8
        ))
        #expect(try String(contentsOf: paths.configPath).contains(#"repos = ["custom/repo"]"#))
    }

    @Test func namespaceExistingEmptyConfigSeedsOrgButPreservesTimings() throws {
        let base = try temporaryDirectory()
        let paths = try WorkspaceRuntimePaths.workspace(namespace: "Example-Org", baseDirectory: base)
        try FileManager.default.createDirectory(at: paths.workspaceRoot, withIntermediateDirectories: true)
        try """
        [github]
        orgs = []
        repos = []
        exclude_repos = ["old/skip"]

        [sync]
        interval = 45

        [display]
        seen_delay = 8
        """.write(to: paths.configPath, atomically: true, encoding: .utf8)

        let config = try WorkspaceConfig.ensure(paths: paths, namespace: "Example-Org")

        #expect(config == WorkspaceConfig(
            orgs: ["Example-Org"],
            repos: [],
            excludeRepos: [],
            syncInterval: 45,
            seenDelay: 8
        ))
    }

    @Test func parsesDefaultConfigShape() throws {
        let config = try WorkspaceConfig.parse(
            #"""
            [github]
            # GitHub org(s) to scan
            orgs = ["OpenAI", "Example-Org"]
            repos = ["OpenAI/codex"]
            exclude_repos = ["OpenAI/skip"]

            [sync]
            interval = 30

            [display]
            seen_delay = 7
            """#
        )

        #expect(config.orgs == ["OpenAI", "Example-Org"])
        #expect(config.repos == ["OpenAI/codex"])
        #expect(config.excludeRepos == ["OpenAI/skip"])
        #expect(config.syncInterval == 30)
        #expect(config.seenDelay == 7)
        #expect(config.repoConfig == WorkspaceRepoConfig(
            repos: ["OpenAI/codex"],
            orgs: ["OpenAI", "Example-Org"],
            excludeRepos: ["OpenAI/skip"]
        ))
    }

    @Test func preservesDefaultsForMissingSectionsAndIgnoresUnknownKeys() throws {
        let config = try WorkspaceConfig.parse(
            #"""
            [github]
            orgs = ["OpenAI"]
            token = "ignored"

            [unknown]
            repos = ["ignored/repo"]
            """#
        )

        #expect(config.orgs == ["OpenAI"])
        #expect(config.repos.isEmpty)
        #expect(config.excludeRepos.isEmpty)
        #expect(config.syncInterval == 120)
        #expect(config.seenDelay == 3)
    }

    @Test func stripsCommentsOutsideQuotedStrings() throws {
        let config = try WorkspaceConfig.parse(
            #"""
            [github]
            orgs = ["hash#inside"] # trailing comment
            repos = ['single-quoted/repo',]
            exclude_repos = []
            """#
        )

        #expect(config.orgs == ["hash#inside"])
        #expect(config.repos == ["single-quoted/repo"])
    }

    @Test func parsesMultilineStringArrays() throws {
        let config = try WorkspaceConfig.parse(
            #"""
            [github]
            orgs = [
              "OpenAI",
              "Example-Org", # trailing comma allowed
            ]
            repos = [
              'OpenAI/codex'
            ]
            """#
        )

        #expect(config.orgs == ["OpenAI", "Example-Org"])
        #expect(config.repos == ["OpenAI/codex"])
    }

    @Test func rejectsInvalidArrayValue() throws {
        #expect(throws: WorkspaceConfigError.invalidValue(
            line: 2,
            key: "orgs",
            expected: "array of strings"
        )) {
            _ = try WorkspaceConfig.parse(
                #"""
                [github]
                orgs = "OpenAI"
                """#
            )
        }
    }

    @Test func rejectsInvalidIntegerValue() throws {
        #expect(throws: WorkspaceConfigError.invalidValue(
            line: 2,
            key: "interval",
            expected: "integer"
        )) {
            _ = try WorkspaceConfig.parse(
                #"""
                [sync]
                interval = "fast"
                """#
            )
        }
    }

    @Test func derivesBaseWorkspaceRuntimePaths() throws {
        let base = URL(fileURLWithPath: "/tmp/agendum-test")
        let paths = try WorkspaceRuntimePaths.workspace(namespace: nil, baseDirectory: base)

        #expect(paths.workspaceRoot.path == "/tmp/agendum-test")
        #expect(paths.configPath.path == "/tmp/agendum-test/config.toml")
        #expect(paths.dbPath.path == "/tmp/agendum-test/agendum.db")
        #expect(paths.ghConfigDir.path == "/tmp/agendum-test/gh")
    }

    @Test func derivesNamespaceWorkspaceRuntimePaths() throws {
        let base = URL(fileURLWithPath: "/tmp/agendum-test")
        let paths = try WorkspaceRuntimePaths.workspace(namespace: " Example-Org ", baseDirectory: base)

        #expect(paths.workspaceRoot.path == "/tmp/agendum-test/workspaces/example-org")
        #expect(paths.configPath.path == "/tmp/agendum-test/workspaces/example-org/config.toml")
        #expect(try WorkspaceRuntimePaths.normalizeNamespace(" Example-Org ") == "Example-Org")
    }

    @Test func rejectsInvalidNamespaceValues() throws {
        #expect(throws: WorkspaceConfigError.invalidNamespace("enter a GitHub owner name, not owner/repo")) {
            _ = try WorkspaceRuntimePaths.normalizeNamespace("owner/repo")
        }
        #expect(throws: WorkspaceConfigError.invalidNamespace("enter a valid GitHub owner name")) {
            _ = try WorkspaceRuntimePaths.normalizeNamespace("bad--name")
        }
        #expect(throws: WorkspaceConfigError.invalidNamespace("enter a valid GitHub owner name")) {
            _ = try WorkspaceRuntimePaths.normalizeNamespace("-bad")
        }
    }
}

private func temporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("agendum-workspace-config-tests")
        .appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func posixMode(_ url: URL) throws -> Int {
    let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
    return (attrs[.posixPermissions] as? NSNumber)?.intValue ?? 0
}
