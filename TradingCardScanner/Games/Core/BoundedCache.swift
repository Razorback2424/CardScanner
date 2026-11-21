import Foundation

struct BoundedCache<Key: Hashable, Value> {
    private let capacity: Int
    private var storage: [Key: Value] = [:]
    /// Least recently used first.
    private var usage: [Key] = []

    init(capacity: Int) {
        self.capacity = max(capacity, 1)
    }

    var count: Int { storage.count }

    mutating func removeAll() {
        storage.removeAll(keepingCapacity: true)
        usage.removeAll(keepingCapacity: true)
    }

    @discardableResult
    mutating func removeValue(forKey key: Key) -> Value? {
        guard let value = storage.removeValue(forKey: key) else { return nil }
        usage.removeAll { $0 == key }
        return value
    }

    /// Keys whose entries match, without changing recency.
    func keys(where predicate: (Key, Value) throws -> Bool) rethrows -> [Key] {
        try storage.compactMap { try predicate($0.key, $0.value) ? $0.key : nil }
    }

    mutating func removeAll(where predicate: (Key, Value) throws -> Bool) rethrows {
        let removed = Set(try keys(where: predicate))
        guard !removed.isEmpty else { return }
        for key in removed { storage[key] = nil }
        usage.removeAll { removed.contains($0) }
    }

    subscript(key: Key) -> Value? {
        mutating get {
            guard let value = storage[key] else { return nil }
            touch(key)
            return value
        }
        set {
            guard let newValue else {
                storage[key] = nil
                usage.removeAll { $0 == key }
                return
            }
            storage[key] = newValue
            touch(key)
            while storage.count > capacity, let oldest = usage.first {
                usage.removeFirst()
                storage[oldest] = nil
            }
        }
    }

    private mutating func touch(_ key: Key) {
        usage.removeAll { $0 == key }
        usage.append(key)
    }
}
