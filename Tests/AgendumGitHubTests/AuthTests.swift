@testable import AgendumGitHub
import Foundation
import Testing

@Suite("GhCLITokenProvider")
struct AuthTests {

    @Test
    func tokenCachesAfterFirstRead() async throws {
        let calls = CallCounter()
        let provider = GhCLITokenProvider {
            await calls.bump()
            return ("ghu_validtoken\n", "", 0)
        }
        let first = try await provider.token()
        let second = try await provider.token()
        #expect(first == "ghu_validtoken")
        #expect(second == "ghu_validtoken")
        let count = await calls.value
        #expect(count == 1, "expected runner to be called once; was \(count)")
    }

    @Test
    func invalidateForcesReRead() async throws {
        let calls = CallCounter()
        let provider = GhCLITokenProvider {
            await calls.bump()
            return ("ghu_v\(await calls.value)\n", "", 0)
        }
        let first = try await provider.token()
        await provider.invalidate()
        let second = try await provider.token()
        #expect(first == "ghu_v1")
        #expect(second == "ghu_v2")
    }

    @Test
    func nonZeroExitThrowsGhCLIFailed() async throws {
        let provider = GhCLITokenProvider {
            ("", "you are not logged into any GitHub hosts", 4)
        }
        do {
            _ = try await provider.token()
            Issue.record("expected throw")
        } catch GitHubAuthError.ghCLIFailed(let stderr, let exit) {
            #expect(stderr.contains("not logged into"))
            #expect(exit == 4)
        }
    }

    @Test
    func emptyTokenIsRejected() async throws {
        let provider = GhCLITokenProvider { ("   \n", "", 0) }
        do {
            _ = try await provider.token()
            Issue.record("expected throw")
        } catch GitHubAuthError.emptyToken {
            // expected
        }
    }

    @Test
    func enoentMapsToGhCLINotFound() async throws {
        let provider = GhCLITokenProvider { throw POSIXError(.ENOENT) }
        do {
            _ = try await provider.token()
            Issue.record("expected throw")
        } catch GitHubAuthError.ghCLINotFound {
            // expected
        }
    }

    @Test
    func timeoutThrowsGhCLITimedOut() async throws {
        let provider = GhCLITokenProvider { throw GhCLITokenProvider.GhRunnerTimeout() }
        do {
            _ = try await provider.token()
            Issue.record("expected throw")
        } catch GitHubAuthError.ghCLITimedOut {
            // expected
        }
    }

    @Test
    func runProcessWithDeadlineActuallyTimesOut() async throws {
        // Use `/bin/sleep 5` with a 200ms deadline — the watchdog should
        // terminate the process and surface GhRunnerTimeout.
        let start = ContinuousClock.now
        do {
            _ = try await GhCLITokenProvider.runProcessWithDeadline(
                executableURL: URL(fileURLWithPath: "/bin/sleep"),
                arguments: ["5"],
                deadline: .milliseconds(200)
            )
            Issue.record("expected GhRunnerTimeout")
        } catch is GhCLITokenProvider.GhRunnerTimeout {
            let elapsed = ContinuousClock.now - start
            #expect(elapsed < .seconds(2), "expected ~200ms to terminate, took \(elapsed)")
        }
    }
}

actor CallCounter {
    private(set) var value: Int = 0
    func bump() { value += 1 }
}
