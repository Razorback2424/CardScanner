import Foundation

/// Readers share the value and wait for the first computation to finish.
final class LoadOnce<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value?
    private var make: (@Sendable () -> Value)?

    init(_ make: @escaping @Sendable () -> Value) { self.make = make }
    init(value: Value) { self.value = value }

    var isLoaded: Bool { lock.withLock { value != nil } }

    func get() -> Value {
        lock.withLock {
            if let value { return value }
            let made = make!()
            value = made
            make = nil
            return made
        }
    }
}
