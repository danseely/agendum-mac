import Foundation

/// Bounded concurrency gate. Mirrors Python `asyncio.Semaphore(N)` semantics:
/// at most `value` `acquire()` calls can be outstanding at once; further
/// callers suspend until a holder calls `release()`.
///
/// Use the `withPermit { … }` convenience to guarantee balanced acquire/release
/// even on early-exit or thrown errors.
///
/// Implementation: pure actor; no continuations leak across actor boundaries
/// once `release()` has woken the next waiter.
public actor AsyncSemaphore {
    private let capacity: Int
    private var available: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []

    public init(value: Int) {
        precondition(value > 0, "AsyncSemaphore value must be > 0")
        self.capacity = value
        self.available = value
    }

    /// Acquires one permit, suspending until one is available.
    public func acquire() async {
        if available > 0 {
            available -= 1
            return
        }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            waiters.append(continuation)
        }
    }

    /// Releases one permit, waking the longest-waiting `acquire()` if any.
    public func release() {
        if !waiters.isEmpty {
            let next = waiters.removeFirst()
            next.resume()
            return
        }
        if available < capacity {
            available += 1
        }
    }

    /// Convenience: acquire, run the body, release. Releases even if `body` throws.
    public func withPermit<T: Sendable>(_ body: @Sendable () async throws -> T) async rethrows -> T {
        await acquire()
        do {
            let result = try await body()
            release()
            return result
        } catch {
            release()
            throw error
        }
    }
}
