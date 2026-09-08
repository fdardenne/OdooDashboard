import Foundation

/// A small lock-protected box for mutable state shared across closures that
/// Swift's strict concurrency checker can't otherwise prove safe (readability
/// handlers, memoization caches) -- the lock is the actual safety mechanism;
/// this just satisfies the compiler about it.
final class Locked<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: T

    init(_ value: T) { self.value = value }

    @discardableResult
    func withLock<R>(_ body: (inout T) -> R) -> R {
        lock.lock()
        defer { lock.unlock() }
        return body(&value)
    }
}
