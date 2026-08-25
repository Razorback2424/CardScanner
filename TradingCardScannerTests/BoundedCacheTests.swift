import XCTest
@testable import TradingCardScanner

/// The scan session cache is keyed by `ScanIdentifier`, and a historical
/// identifier carries every title observation — so one physical card produces a
/// new key on almost every frame. Keyed correctly (two cards sharing a printed
/// number must not share a cache entry) but unbounded, that grows with OCR noise
/// rather than with the number of cards scanned.
final class BoundedCacheTests: XCTestCase {
    func testKeepsTheMostRecentEntriesAndDropsTheOldest() {
        var cache = BoundedCache<Int, String>(capacity: 3)
        for value in 1...5 { cache[value] = "card-\(value)" }

        XCTAssertNil(cache[1], "oldest evicted")
        XCTAssertNil(cache[2])
        XCTAssertEqual(cache[3], "card-3")
        XCTAssertEqual(cache[4], "card-4")
        XCTAssertEqual(cache[5], "card-5")
        XCTAssertEqual(cache.count, 3)
    }

    /// Re-inserting an existing key must not grow the cache or evict anything.
    func testOverwritingAKeyDoesNotEvict() {
        var cache = BoundedCache<Int, String>(capacity: 2)
        cache[1] = "a"
        cache[2] = "b"
        cache[1] = "a-again"

        XCTAssertEqual(cache.count, 2)
        XCTAssertEqual(cache[1], "a-again")
        XCTAssertEqual(cache[2], "b")
    }

    /// A hit keeps an entry alive; the least recently *used* is what goes.
    func testReadingAnEntryKeepsIt() {
        var cache = BoundedCache<Int, String>(capacity: 2)
        cache[1] = "a"
        cache[2] = "b"
        _ = cache[1]
        cache[3] = "c"

        XCTAssertEqual(cache[1], "a", "recently read, so kept")
        XCTAssertNil(cache[2], "least recently used")
        XCTAssertEqual(cache[3], "c")
    }
}
