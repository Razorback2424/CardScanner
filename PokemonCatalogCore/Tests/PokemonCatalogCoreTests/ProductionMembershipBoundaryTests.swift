import Foundation
import XCTest
@testable import PokemonCatalogCore

private final class MembershipBoundaryURLProtocol: URLProtocol {
    nonisolated(unsafe) static var responses: [String: Data] = [:]

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url,
              let data = Self.responses[url.path],
              let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil,
                                             headerFields: ["Content-Type": "application/json"]) else {
            client?.urlProtocol(self, didFailWithError: URLError(.resourceUnavailable))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

final class ProductionMembershipBoundaryTests: XCTestCase {
    private let generatedAt = Date(timeIntervalSince1970: 1_792_368_000)

    func testProductionInputBuildsOrdinaryCandidateWithoutAdmittingPartialCelebrationsMembership() async throws {
        let inputs = try load(PokemonCatalogHumanInputFile.self, path: "publisher/catalog-input.json")
        let policy = try load(PokemonCatalogDiscoveryPolicy.self, path: "publisher/discovery-policy.json")
        let ordinaryInput = try XCTUnwrap(inputs.sets.first { $0.providerSetID == "sv01" })
        let ordinaryCount = 198
        XCTAssertEqual(ordinaryInput.claimedOfficialCount, ordinaryCount)
        XCTAssertTrue(policy.ignoredHistoricalIDs.contains("cel25cc"))

        // A complete historical inventory is available to the transport. It
        // must remain outside signed discovery while its scan membership is
        // partial. The ordinary expansion has a complete synthetic checklist.
        let celebrations = try celebrationsSet()
        XCTAssertEqual(celebrations.cards.count, 25)
        XCTAssertTrue(celebrations.cards.contains { $0.id == "cel25cc-CC008" })
        let ordinary = PokemonCatalogProviderSet(
            id: "sv01", name: "Scarlet & Violet",
            cards: (1...ordinaryCount).map { number in
                let localID = String(format: "%03d", number)
                return .init(id: "sv01-\(localID)", localID: localID, name: "Fixture card \(localID)")
            },
            releaseDate: "2023-03-31",
            cardCount: .init(total: ordinaryCount, official: ordinaryCount),
            abbreviation: .init(official: "SVI")
        )
        let sets = [ordinary, celebrations]
        let directory = sets.map { set in
            PokemonCatalogProviderDirectoryRow(id: set.id, name: set.name,
                cardCount: set.cardCount, releaseDate: set.releaseDate)
        }
        let boundedIDs = Set(directory.map(\.id))
        let boundedInputs = inputs.sets.filter { boundedIDs.contains($0.providerSetID.lowercased()) }

        // Follow the live CLI's authority boundary: explicit inputs are
        // authorized even if an ID is in the ignored-historical policy. Thus
        // restoring the old 24-row cel25cc override exercises the real builder
        // failure; this is not just an assertion that the input row is absent.
        let overrideIDs = Set(inputs.sets.map { $0.providerSetID.lowercased() })
        let boundary = try date(policy.automaticDiscoveryStartDate)
        let dueIDs = try directory.compactMap { row -> String? in
            guard !row.isUnsupportedProduct,
                  !policy.ignoredHistoricalIDs.contains(row.id.lowercased()),
                  let rawDate = row.releaseDate else { return nil }
            let released = try date(rawDate)
            return released >= boundary && released <= generatedAt ? row.id.lowercased() : nil
        }
        let authorizedIDs = overrideIDs.union(dueIDs)

        var responses: [String: Data] = [:]
        for set in sets {
            responses["/v2/en/sets/\(set.id)"] = try JSONEncoder().encode(set)
            for card in details(for: set) {
                responses["/v2/en/cards/\(card.id)"] = try JSONEncoder().encode(card)
            }
        }
        MembershipBoundaryURLProtocol.responses = responses
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MembershipBoundaryURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer {
            session.invalidateAndCancel()
            MembershipBoundaryURLProtocol.responses = [:]
        }
        // These fixtures have no series or secondary artwork source, so the
        // enrichment path cannot launch per-card CDN probes.
        let client = PokemonCatalogTCGdexProviderClient(
            session: session,
            baseURL: try XCTUnwrap(URL(string: "https://publisher-fixture.invalid/v2/en")),
            artworkResolver: .init { _ in throw URLError(.unsupportedURL) }
        )
        let fetched = try await client.fetchFixture(directory: directory, authorizedSetIDs: authorizedIDs)
        let result = try PokemonCatalogBuilder().build(.init(
            fixture: fetched, humanInputs: boundedInputs, revision: 1, generatedAt: generatedAt
        ))
        try PokemonCatalogCandidateValidator.validate(result)

        XCTAssertEqual(Set(fetched.directory.map(\.id)), ["sv01"])
        XCTAssertEqual(fetched.cards.count, ordinaryCount)
        XCTAssertEqual(result.release.sets.map(\.providerSetID), ["sv01"])
        XCTAssertEqual(result.release.sets.first?.recognitionKind, .expansion)
        XCTAssertEqual(result.release.sets.first?.printedCode, "SVI")
        XCTAssertEqual(result.snapshot.checklists["sv01"]?.count, ordinaryCount)
    }

    func testReviewedPartialMembershipStillFailsCompleteProviderCoverage() throws {
        let review = try celebrationsReview()
        let set = try celebrationsSet()
        let members = try review.cards.filter(\.membershipEnabled).map { card in
            PokemonCatalogMembershipRecognition.Member(
                providerCardID: card.providerID, canonicalName: card.canonicalName,
                printedLocalID: card.printedLocalID,
                printedDenominator: try XCTUnwrap(card.printedDenominator)
            )
        }
        XCTAssertEqual(members.count, 24)
        XCTAssertEqual(set.cards.count, 25)
        let input = PokemonCatalogHumanInput(
            providerSetID: "cel25cc", recognitionKind: .notScannable, scanEnabled: false,
            membershipRecognition: .init(members: members)
        )
        let fixture = PokemonCatalogProviderFixture(
            directory: [.init(id: set.id, name: set.name, cardCount: set.cardCount,
                              releaseDate: set.releaseDate)],
            sets: [set], cards: details(for: set)
        )

        XCTAssertThrowsError(try PokemonCatalogBuilder().build(.init(
            fixture: fixture, humanInputs: [input], revision: 1, generatedAt: generatedAt
        ))) { error in
            guard case let PokemonCatalogBuildError.membershipCoverageMismatch(setID, expected, received) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(setID, "cel25cc")
            XCTAssertEqual(expected, 25)
            XCTAssertEqual(received, 24)
        }
    }

    private struct CelebrationsReview: Decodable {
        struct Card: Decodable {
            let providerID: String
            let providerLocalID: String
            let providerName: String
            let canonicalName: String
            let printedLocalID: String
            let printedDenominator: Int?
            let membershipEnabled: Bool
        }
        let cards: [Card]
    }

    private func celebrationsReview() throws -> CelebrationsReview {
        try load(CelebrationsReview.self,
                 path: "TestFixtures/TradingCards/PokemonCatalogCoverageAudit/celebrations-classic-membership-review.json")
    }

    private func celebrationsSet() throws -> PokemonCatalogProviderSet {
        let review = try celebrationsReview()
        return PokemonCatalogProviderSet(
            id: "cel25cc", name: "Celebrations Classic Collection",
            cards: review.cards.map {
                .init(id: $0.providerID, localID: $0.providerLocalID, name: $0.providerName)
            },
            releaseDate: "2021-10-08", cardCount: .init(total: 25, official: 25)
        )
    }

    private func details(for set: PokemonCatalogProviderSet) -> [PokemonCatalogProviderCard] {
        set.cards.map {
            .init(id: $0.id, localID: $0.localID, name: $0.name, setID: set.id)
        }
    }

    private func load<Value: Decodable>(_ type: Value.Type, path: String) throws -> Value {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try JSONDecoder().decode(type, from: Data(contentsOf: root.appendingPathComponent(path)))
    }

    private func date(_ raw: String) throws -> Date {
        try XCTUnwrap(ISO8601DateFormatter().date(from: raw + "T00:00:00Z"))
    }
}
