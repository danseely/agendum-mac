import Foundation

/// Bounded concurrency gate. Mirrors Python `asyncio.Semaphore(N)` semantics:
/// at most `value` `acquire()` calls can be outstanding at once; further
/// callers suspend until a holder calls `release()`.
///
/// Use the `withPermit { … }` convenience to guarantee balanced acquire/release
/// even on early-exit or thrown errors.
///
/// **Cancellation**: if a task is cancelled while suspended in `acquire()`, the
/// waiter is removed from the queue and `acquire()` throws `CancellationError`.
/// `release()` skips cancelled waiters so a future `release` reliably wakes a
/// live waiter — no permit leakage.
public actor AsyncSemaphore {
    private struct Waiter {
        let id: UUID
        let continuation: CheckedContinuation<Void, any Error>
    }

    private let capacity: Int
    private var available: Int
    private var waiters: [Waiter] = []

    public init(value: Int) {
        precondition(value > 0, "AsyncSemaphore value must be > 0")
        self.capacity = value
        self.available = value
    }

    /// Acquires one permit, suspending until one is available.
    /// Throws `CancellationError` if the awaiting task is cancelled mid-suspension.
    public func acquire() async throws {
        try Task.checkCancellation()
        if available > 0 {
            available -= 1
            return
        }
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                waiters.append(Waiter(id: id, continuation: continuation))
            }
        } onCancel: {
            Task { await self.cancelWaiter(id: id) }
        }
    }

    /// Releases one permit, waking the longest-waiting `acquire()` if any.
    public func release() {
        if let next = waiters.first {
            waiters.removeFirst()
            next.continuation.resume()
            return
        }
        if available < capacity {
            available += 1
        }
    }

    /// Convenience: acquire, run the body, release. Releases even if `body` throws.
    /// Propagates `CancellationError` from `acquire()` without invoking `body`.
    public func withPermit<T: Sendable>(_ body: @Sendable () async throws -> T) async throws -> T {
        try await acquire()
        do {
            let result = try await body()
            release()
            return result
        } catch {
            release()
            throw error
        }
    }

    // MARK: - Private

    private func cancelWaiter(id: UUID) {
        guard let idx = waiters.firstIndex(where: { $0.id == id }) else { return }
        let waiter = waiters.remove(at: idx)
        waiter.continuation.resume(throwing: CancellationError())
    }
}
