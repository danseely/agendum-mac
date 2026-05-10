@testable import AgendumGitHub
import Foundation
import Testing

@Suite("AsyncSemaphore — concurrency throttle")
struct AsyncSemaphoreTests {

    @Test
    func semaphoreCapsConcurrentHolders() async throws {
        // Capacity 3: with 10 tasks racing through `withPermit`, never more than
        // 3 should be inside the critical section at any moment.
        let semaphore = AsyncSemaphore(value: 3)
        let counter = ConcurrencyCounter()

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<10 {
                group.addTask {
                    await semaphore.withPermit {
                        await counter.enter()
                        try? await Task.sleep(nanoseconds: 5_000_000) // 5ms
                        await counter.leave()
                    }
                }
            }
        }

        let peak = await counter.peak
        #expect(peak <= 3, "peak concurrency was \(peak), expected ≤ 3")
        #expect(peak >= 2, "expected the semaphore to allow concurrency, observed peak \(peak)")
    }

    @Test
    func releaseFiresWaitersInFIFOOrder() async throws {
        let semaphore = AsyncSemaphore(value: 1)
        await semaphore.acquire() // hold the only permit

        let order = OrderRecorder()
        async let first: Void = {
            await semaphore.acquire()
            await order.record("A")
            await semaphore.release()
        }()
        // Yield to ensure A is queued before B.
        try await Task.sleep(nanoseconds: 2_000_000)
        async let second: Void = {
            await semaphore.acquire()
            await order.record("B")
            await semaphore.release()
        }()
        // Release the original permit; FIFO waiters resume in order.
        try await Task.sleep(nanoseconds: 2_000_000)
        await semaphore.release()
        _ = await (first, second)

        let recorded = await order.values
        #expect(recorded == ["A", "B"])
    }

    @Test
    func withPermitReleasesEvenOnThrow() async throws {
        let semaphore = AsyncSemaphore(value: 1)
        struct Boom: Error {}
        do {
            try await semaphore.withPermit {
                throw Boom()
            }
            Issue.record("expected throw")
        } catch is Boom {
            // expected
        }
        // The permit should be released and immediately re-acquirable.
        await semaphore.acquire()
        await semaphore.release()
    }
}

actor ConcurrencyCounter {
    private var current = 0
    private(set) var peak = 0
    func enter() { current += 1; if current > peak { peak = current } }
    func leave() { current -= 1 }
}

actor OrderRecorder {
    private(set) var values: [String] = []
    func record(_ s: String) { values.append(s) }
}
