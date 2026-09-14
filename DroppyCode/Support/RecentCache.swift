import Foundation

/// A bounded cache that keeps what was used recently and lets the rest go a generation at
/// a time. Entries live in the current generation; once it fills, it becomes the previous
/// one and a fresh generation starts. A hit in the previous generation moves the entry
/// forward. So filling the cache never drops everything at once: a run of fresh keys (a
/// streaming reply parsing on every flush) pushes out the oldest entries first and the
/// ones still in use stay, and no operation costs more than two dictionary lookups.
struct RecentCache<Key: Hashable, Value> {
    private var current: [Key: Value] = [:]
    private var previous: [Key: Value] = [:]
    private let limit: Int

    /// - Parameter limit: entries per generation; the cache holds at most twice this many.
    init(limit: Int) {
        self.limit = max(1, limit)
        current.reserveCapacity(self.limit)
    }

    mutating func value(for key: Key) -> Value? {
        if let hit = current[key] { return hit }
        guard let hit = previous.removeValue(forKey: key) else { return nil }
        insert(hit, for: key)
        return hit
    }

    mutating func insert(_ value: Value, for key: Key) {
        if current.count >= limit, current[key] == nil {
            previous = current
            current = [:]
            current.reserveCapacity(limit)
        }
        current[key] = value
    }
}
