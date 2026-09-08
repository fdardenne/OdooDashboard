import Foundation

/// Ports packages/server/src/cache.ts -- in-memory only (lost on relaunch,
/// same as the original), with in-flight de-duplication so concurrent
/// callers for the same key await one fetch instead of triggering several.
actor TtlCache<Key: Hashable & Sendable, Value: Sendable> {
    private struct Entry {
        let value: Value
        let expiresAt: Date
    }

    private var store: [Key: Entry] = [:]
    private var inFlight: [Key: Task<Value, Never>] = [:]
    private let ttl: TimeInterval

    init(ttl: TimeInterval) {
        self.ttl = ttl
    }

    func getOrFetch(_ key: Key, _ fetch: @escaping @Sendable () async -> Value) async -> Value {
        if let cached = store[key], cached.expiresAt > Date() {
            return cached.value
        }
        if let pending = inFlight[key] {
            return await pending.value
        }
        let task = Task<Value, Never> { await fetch() }
        inFlight[key] = task
        let value = await task.value
        store[key] = Entry(value: value, expiresAt: Date().addingTimeInterval(ttl))
        inFlight[key] = nil
        return value
    }

    func invalidate(_ key: Key) {
        store[key] = nil
    }
}
