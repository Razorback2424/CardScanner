import Foundation

struct BoundedCache<Key: Hashable, Value> {
    private struct Entry {
        var value: Value
        var previous: Key?
        var next: Key?
    }

    private let capacity: Int
    private var storage: [Key: Entry] = [:]
    private var oldest: Key?
    private var newest: Key?

    init(capacity: Int) {
        self.capacity = max(capacity, 1)
    }

    var count: Int { storage.count }

    mutating func removeAll() {
        storage.removeAll(keepingCapacity: true)
        oldest = nil
        newest = nil
    }

    @discardableResult
    mutating func removeValue(forKey key: Key) -> Value? {
        guard let entry = storage.removeValue(forKey: key) else { return nil }
        unlink(entry)
        return entry.value
    }

    /// Keys whose entries match, without changing recency.
    func keys(where predicate: (Key, Value) throws -> Bool) rethrows -> [Key] {
        try storage.compactMap { try predicate($0.key, $0.value.value) ? $0.key : nil }
    }

    mutating func removeAll(where predicate: (Key, Value) throws -> Bool) rethrows {
        for key in try keys(where: predicate) {
            removeValue(forKey: key)
        }
    }

    subscript(key: Key) -> Value? {
        mutating get {
            guard let entry = storage[key] else { return nil }
            if key != newest {
                unlink(entry)
                append(key, value: entry.value)
            }
            return entry.value
        }
        set {
            guard let newValue else {
                removeValue(forKey: key)
                return
            }
            if let entry = storage[key] {
                if key == newest {
                    storage[key]?.value = newValue
                    return
                }
                unlink(entry)
            }
            append(key, value: newValue)
            if storage.count > capacity, let oldest {
                removeValue(forKey: oldest)
            }
        }
    }

    // The dictionary owns both the values and the links, so copies of the
    // cache preserve independent eviction order without sharing mutable nodes.
    private mutating func append(_ key: Key, value: Value) {
        if let newest {
            storage[newest]?.next = key
        } else {
            oldest = key
        }
        storage[key] = Entry(value: value, previous: newest, next: nil)
        newest = key
    }

    private mutating func unlink(_ entry: Entry) {
        if let previous = entry.previous {
            storage[previous]?.next = entry.next
        } else {
            oldest = entry.next
        }
        if let next = entry.next {
            storage[next]?.previous = entry.previous
        } else {
            newest = entry.previous
        }
    }
}
