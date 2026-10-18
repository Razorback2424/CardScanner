import Foundation
import XCTest
@testable import TradingCardScanner

final class LorcastSourceNormalizerTests: XCTestCase {
    private func fixture(_ stem: String) throws -> (Data, LorcastResponseReceipt) {
        let bundle = Bundle(for: Self.self)
        let body = try Data(contentsOf: XCTUnwrap(bundle.url(forResource: stem, withExtension: "json", subdirectory: "Lorcana")))
        let receiptData = try Data(contentsOf: XCTUnwrap(bundle.url(forResource: "\(stem).receipt", withExtension: "json", subdirectory: "Lorcana")))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (body, try decoder.decode(LorcastResponseReceipt.self, from: receiptData))
    }

    private func receipt(_ data: Data, url: URL? = nil, responseURL: URL? = nil, status: Int = 200,
                         contentType: String = "application/json", pagination: [String: String] = [:],
                         digest: String? = nil, receivedAt: Date = Date(timeIntervalSince1970: 1_700_000_000)) throws -> LorcastResponseReceipt {
        let requestURL = try url ?? LorcastSourceNormalizer.searchURL(query: "fixture")
        return .init(requestedURL: requestURL, responseURL: responseURL ?? requestURL, receivedAt: receivedAt,
                     statusCode: status, contentType: contentType, paginationHeaders: pagination,
                     bodySHA256: digest ?? LorcastSourceNormalizer.digest(data))
    }

    private func row(_ id: String = "fixture-1", number: Any = "207", language: String = "en",
                     setID: String = "fixture-set", setCode: String = "TFC", name: String = "Fixture Elsa",
                     releasedAt: String = "2023-08-18") -> [String: Any] {
        ["id": id, "name": name, "version": NSNull(), "layout": "normal", "released_at": releasedAt,
         "collector_number": number, "lang": language, "rarity": "future-rarity",
         "set": ["id": setID, "code": setCode, "name": "Fixture Set"]]
    }

    private func data(_ rows: [[String: Any]], extra: [String: Any] = [:]) throws -> Data {
        var envelope: [String: Any] = ["results": rows]
        envelope.merge(extra) { _, new in new }
        return try JSONSerialization.data(withJSONObject: envelope, options: [.sortedKeys])
    }

    func testCapturedOrdinaryAndPremiumPrintsRetainSeparateProviderAliases() throws {
        let (body, receipt) = try fixture("cards-01")
        let batch = try LorcastSourceNormalizer.cards(data: body, receipt: receipt)
        let elsa = batch.observations.filter { $0.name == "Elsa" && $0.version == "Spirit of Winter" }
        XCTAssertEqual(batch.observations.count, 5)
        XCTAssertEqual(Set(elsa.map(\.collectorNumber)), ["42", "207"])
        XCTAssertEqual(Set(elsa.map(\.sourceAlias)).count, 2)
        XCTAssertTrue(elsa.allSatisfy { $0.set.code == "1" && $0.language == "en" })
        XCTAssertEqual(batch.receipt, receipt)
        XCTAssertEqual(LorcastSourceNormalizer.digest(body), receipt.bodySHA256)
    }

    func testCapturedSearchKeepsCrossSetReprintsAndDoesNotGuessExactNameMembership() throws {
        let (body, receipt) = try fixture("cards-02")
        let batch = try LorcastSourceNormalizer.cards(data: body, receipt: receipt)
        let distract = batch.observations.filter { $0.name == "Distract" }
        XCTAssertEqual(Set(distract.map { $0.set.code }), ["3", "11"])
        XCTAssertEqual(Set(distract.map(\.collectorNumber)), ["159", "164"])
        XCTAssertEqual(batch.observations.count, 4)
        XCTAssertEqual(batch.observations.filter { $0.name == "Donald Duck" }.count, 2)
    }

    func testCapturedLocationsAndSetInventoryAreProviderMetadataOnly() throws {
        let (body, receipt) = try fixture("cards-03")
        let locations = try LorcastSourceNormalizer.cards(data: body, receipt: receipt).observations
        XCTAssertEqual(locations.count, 22)
        XCTAssertTrue(locations.allSatisfy { $0.layout == "landscape" && $0.set.code == "3" })
        let (setBody, setReceipt) = try fixture("sets")
        let sets = try LorcastSourceNormalizer.sets(data: setBody, receipt: setReceipt).observations
        XCTAssertEqual(sets.count, 26)
        XCTAssertTrue(sets.contains { $0.code == "P1" })
        XCTAssertTrue(sets.contains { $0.code == "D23" })
        XCTAssertEqual(Set(sets.map(\.id)).count, sets.count)
    }

    func testStringCollectorNumbersUnknownMetadataAndNullVersionsStayLiteral() throws {
        var first = row(number: "007a", language: "fr")
        first["layout"] = "future-special-layout"
        first["prices"] = ["usd": "1.20", "usd_foil": 120]
        first["image_uris"] = ["digital": ["normal": "https://example.test/art.avif"]]
        let body = try data([first])
        let normalized = try LorcastSourceNormalizer.cards(data: body, receipt: receipt(body)).observations[0]
        XCTAssertEqual(normalized.collectorNumber, "007a")
        XCTAssertEqual(normalized.language, "fr")
        XCTAssertEqual(normalized.set.code, "TFC")
        XCTAssertEqual(normalized.rarity, "future-rarity")
        XCTAssertEqual(normalized.layout, "future-special-layout")
        XCTAssertNil(normalized.version)
        // Public price/image fields are retained in raw bytes, never promoted
        // into supported physical finishes, ownership or market mappings.
        first.removeValue(forKey: "prices")
        first.removeValue(forKey: "image_uris")
        let withoutPrices = try data([first])
        XCTAssertEqual(normalized, try LorcastSourceNormalizer.cards(data: withoutPrices, receipt: receipt(withoutPrices)).observations[0])
    }

    func testAllPrintRequestIsRequiredAndUnsafeOrChangedRequestsAreRejected() throws {
        let query = "name:\"Belle's House\" set:3"
        let url = try LorcastSourceNormalizer.searchURL(query: query)
        XCTAssertEqual(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first?.value, query)
        for invalid in ["", " fixture", "fixture\nother", String(repeating: "x", count: 513)] {
            XCTAssertThrowsError(try LorcastSourceNormalizer.searchURL(query: invalid))
        }
        let body = try data([row()])
        for string in ["https://api.lorcast.com/v0/cards/search?q=fixture",
                       "https://api.lorcast.com/v0/cards/search?q=fixture&unique=cards",
                       "https://api.lorcast.com/v0/cards/search?q=fixture&unique=prints&unique=prints",
                       "https://api.lorcast.com/v0/cards/search?q=fixture&unique=prints&page=1",
                       "http://api.lorcast.com/v0/cards/search?q=fixture&unique=prints",
                       "https://elsewhere.test/v0/cards/search?q=fixture&unique=prints",
                       "https://api.lorcast.com/v0/cards/1/207",
                       "https://user:secret@api.lorcast.com/v0/cards/search?q=fixture&unique=prints",
                       "https://api.lorcast.com/v0/cards/search?q=fixture&unique=prints#fragment"] {
            XCTAssertThrowsError(try LorcastSourceNormalizer.cards(data: body, receipt: receipt(body, url: URL(string: string)!))) {
                XCTAssertEqual($0 as? LorcastSourceNormalizer.ValidationError, .invalidRequest)
            }
        }
    }

    func testPaginationTotalsWarningsAndFutureEnvelopeFieldsFailClosed() throws {
        for extra: [String: Any] in [["has_more": true], ["has_more": false], ["next_page": NSNull()],
                                    ["next_cursor": "token"], ["total": 2], ["warnings": []], ["future": 1]] {
            let body = try data([row()], extra: extra)
            XCTAssertThrowsError(try LorcastSourceNormalizer.cards(data: body, receipt: receipt(body))) {
                XCTAssertEqual($0 as? LorcastSourceNormalizer.ValidationError, .unsupportedEnvelope)
            }
        }
        let body = try data([row()])
        for header in ["link", "content-range", "x-next-page"] {
            XCTAssertThrowsError(try LorcastSourceNormalizer.cards(data: body, receipt: receipt(body, pagination: [header: "next"]))) {
                XCTAssertEqual($0 as? LorcastSourceNormalizer.ValidationError, .unsupportedEnvelope)
            }
        }
    }

    func testReceiptRejectsTamperedBytesRedirectsFailuresAndInvalidTime() throws {
        let body = try data([row()])
        let valid = try receipt(body, contentType: "application/json; charset=utf-8")
        XCTAssertNoThrow(try LorcastSourceNormalizer.cards(data: body, receipt: valid))
        let invalidReceipts = try [receipt(body, digest: String(repeating: "0", count: 64)),
                                   receipt(body, responseURL: LorcastSourceNormalizer.searchURL(query: "other")),
                                   receipt(body, status: 429), receipt(body, contentType: "text/html"),
                                   receipt(body, receivedAt: Date(timeIntervalSince1970: .infinity)),
                                   receipt(body, receivedAt: Date(timeIntervalSince1970: 0))]
        for invalid in invalidReceipts {
            XCTAssertThrowsError(try LorcastSourceNormalizer.cards(data: body, receipt: invalid)) {
                XCTAssertEqual($0 as? LorcastSourceNormalizer.ValidationError, .invalidReceipt)
            }
        }
        XCTAssertThrowsError(try LorcastSourceNormalizer.cards(data: body + Data(" ".utf8), receipt: valid))
    }

    func testDuplicateIDsFailButDistinctAliasesSharingCollectorEvidenceRemainSeparate() throws {
        let duplicate = try data([row(), row()])
        XCTAssertThrowsError(try LorcastSourceNormalizer.cards(data: duplicate, receipt: receipt(duplicate))) {
            XCTAssertEqual($0 as? LorcastSourceNormalizer.ValidationError, .duplicateProviderID)
        }
        let distinct = try data([row("fixture-standard"), row("fixture-special")])
        XCTAssertEqual(try LorcastSourceNormalizer.cards(data: distinct, receipt: receipt(distinct)).observations.count, 2)
    }

    func testConflictingSetIDCodeOrNameCannotSilentlyMerge() throws {
        var changedName = row("second")
        changedName["set"] = ["id": "fixture-set", "code": "TFC", "name": "Conflicting Set"]
        for second in [row("second", setCode: "OTHER"), row("second", setID: "other-set"), changedName] {
            let body = try data([row(), second])
            XCTAssertThrowsError(try LorcastSourceNormalizer.cards(data: body, receipt: receipt(body))) {
                XCTAssertEqual($0 as? LorcastSourceNormalizer.ValidationError, .conflictingSet)
            }
        }
    }

    func testOneMalformedRowRejectsWholeResponseRatherThanDroppingCandidate() throws {
        var missingLanguage = row("bad")
        missingLanguage.removeValue(forKey: "lang")
        for bad in [missingLanguage, row("bad", number: 207), row("bad", name: " "),
                    row("bad", releasedAt: "2023-02-29"), row("bad", number: String(repeating: "1", count: 65))] {
            let body = try data([row(), bad])
            XCTAssertThrowsError(try LorcastSourceNormalizer.cards(data: body, receipt: receipt(body)))
        }
        for literal in ["[]", "{}", "{\"results\":null}", "{\"results\":[]"] {
            let body = Data(literal.utf8)
            XCTAssertThrowsError(try LorcastSourceNormalizer.cards(data: body, receipt: receipt(body)))
        }
        let empty = try data([])
        XCTAssertTrue(try LorcastSourceNormalizer.cards(data: empty, receipt: receipt(empty)).observations.isEmpty)
    }

    func testNormalizationOrderIsStableAndByteAndCardCountBoundsAreEnforced() throws {
        let forward = try data([row("a"), row("b")]), reversed = try data([row("b"), row("a")])
        XCTAssertEqual(try LorcastSourceNormalizer.cards(data: forward, receipt: receipt(forward)).observations,
                       try LorcastSourceNormalizer.cards(data: reversed, receipt: receipt(reversed)).observations)
        let oversized = Data(repeating: 32, count: LorcastSourceNormalizer.maximumResponseBytes + 1)
        XCTAssertThrowsError(try LorcastSourceNormalizer.cards(data: oversized, receipt: receipt(oversized))) {
            XCTAssertEqual($0 as? LorcastSourceNormalizer.ValidationError, .responseTooLarge)
        }
        let many = try data((0...LorcastSourceNormalizer.maximumCardResults).map { row("id-\($0)") })
        XCTAssertThrowsError(try LorcastSourceNormalizer.cards(data: many, receipt: receipt(many))) {
            XCTAssertEqual($0 as? LorcastSourceNormalizer.ValidationError, .tooManyResults)
        }
    }

    func testSetDirectoryRejectsDuplicatesPaginationBadDatesAndSearchReceipts() throws {
        let set: [String: Any] = ["id": "set-1", "code": "P9", "name": "Fixture Promos", "released_at": "2024-02-29", "prereleased_at": NSNull()]
        let body = try data([set])
        let batch = try LorcastSourceNormalizer.sets(data: body, receipt: receipt(body, url: LorcastSourceNormalizer.setsURL))
        XCTAssertNil(batch.observations.first?.prereleasedAt)
        XCTAssertThrowsError(try LorcastSourceNormalizer.sets(data: body, receipt: receipt(body)))
        var duplicateCode = set
        duplicateCode["id"] = "set-2"
        var badDate = set
        badDate["released_at"] = "2024-13-01"
        for invalid in [try data([set, set]), try data([set, duplicateCode]), try data([badDate]),
                        try data([set], extra: ["next": NSNull()]),
                        try data(Array(repeating: set, count: LorcastSourceNormalizer.maximumSetResults + 1))] {
            XCTAssertThrowsError(try LorcastSourceNormalizer.sets(data: invalid, receipt: receipt(invalid, url: LorcastSourceNormalizer.setsURL)))
        }
    }
}
