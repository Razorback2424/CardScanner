import Foundation
import XCTest
@testable import PokemonCatalogCore

private final class ArtworkFingerprintMockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var responder: ((URLRequest) -> (Data, Int))?

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let result = Self.responder?(request),
              let url = request.url,
              let response = HTTPURLResponse(
                  url: url,
                  statusCode: result.1,
                  httpVersion: nil,
                  headerFields: ["Content-Type": "application/json"]
              ) else {
            client?.urlProtocol(
                self,
                didFailWithError: URLError(.badServerResponse)
            )
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: result.0)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

final class ArtworkFingerprintParityTests: XCTestCase {
    private let generatedAt = Date(timeIntervalSince1970: 1_768_000_000)

    func testPublisherFingerprintUsesRawArtworkAcrossAllEnrichmentPaths() async throws {
        let scenarios = [
            Scenario(
                name: "directory fallback",
                rawLogo: nil,
                rawSymbol: nil,
                directoryLogo: "https://catalog.scan-stash.com/logo.png",
                directorySymbol: "https://catalog.scan-stash.com/symbol.png",
                resolverLogo: nil,
                resolverSymbol: nil,
                expectedResolvedLogo: "https://catalog.scan-stash.com/logo.png",
                expectedResolvedSymbol: "https://catalog.scan-stash.com/symbol.png"
            ),
            Scenario(
                name: "CDN probe",
                rawLogo: nil,
                rawSymbol: nil,
                directoryLogo: nil,
                directorySymbol: nil,
                resolverLogo: "https://assets.tcgdex.net/en/me/30th-c/logo.png",
                resolverSymbol: "https://assets.tcgdex.net/en/me/30th-c/symbol.png",
                expectedResolvedLogo: "https://assets.tcgdex.net/en/me/30th-c/logo.png",
                expectedResolvedSymbol: "https://assets.tcgdex.net/en/me/30th-c/symbol.png"
            ),
            Scenario(
                name: "empty provider value",
                rawLogo: "",
                rawSymbol: "",
                directoryLogo: nil,
                directorySymbol: nil,
                resolverLogo: "https://assets.tcgdex.net/en/me/30th-c/logo.png",
                resolverSymbol: "https://assets.tcgdex.net/en/me/30th-c/symbol.png",
                expectedResolvedLogo: "https://assets.tcgdex.net/en/me/30th-c/logo.png",
                expectedResolvedSymbol: "https://assets.tcgdex.net/en/me/30th-c/symbol.png"
            )
        ]

        for scenario in scenarios {
            let brief = PokemonCatalogProviderCardBrief(
                id: "30th-c-001",
                localID: "001",
                name: "Test Card",
                image: "https://assets.tcgdex.net/en/me/30th-c/001"
            )
            let count = PokemonCatalogProviderCardCount(total: 1, official: 1)
            let rawSet = PokemonCatalogProviderSet(
                id: "30th-c",
                name: "30th Classic",
                cards: [brief],
                logo: scenario.rawLogo,
                symbol: scenario.rawSymbol,
                releaseDate: "2026-09-16",
                cardCount: count,
                serie: .init(id: "me"),
                abbreviation: .init(official: "30C")
            )
            let card = PokemonCatalogProviderCard(
                id: brief.id,
                localID: brief.localID,
                name: brief.name,
                image: brief.image,
                setID: "30th-c",
                variants: .init(
                    firstEdition: false,
                    holo: false,
                    normal: true,
                    reverse: false,
                    wPromo: false
                )
            )

            let setData = try JSONEncoder().encode(rawSet)
            let cardData = try JSONEncoder().encode(card)
            ArtworkFingerprintMockURLProtocol.responder = { request in
                let path = request.url?.path ?? ""
                if path.hasSuffix("/sets/30th-c") {
                    return (setData, 200)
                }
                if path.hasSuffix("/cards/30th-c-001") {
                    return (cardData, 200)
                }
                return (Data(), 404)
            }

            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [ArtworkFingerprintMockURLProtocol.self]
            let resolver = PokemonCatalogTCGdexArtworkResolver { request in
                let path = request.url?.path ?? ""
                let isLogo = path.hasSuffix("/logo.png")
                let hasResolvedArtwork = isLogo
                    ? scenario.resolverLogo != nil
                    : scenario.resolverSymbol != nil
                let statusCode = hasResolvedArtwork ? 200 : 404
                let response = HTTPURLResponse(
                    url: try XCTUnwrap(request.url),
                    statusCode: statusCode,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "image/png"]
                )!
                return (Data(), response)
            }
            let client = PokemonCatalogTCGdexProviderClient(
                session: URLSession(configuration: configuration),
                baseURL: URL(string: "https://api.test/v2/en")!,
                artworkResolver: resolver
            )
            let row = PokemonCatalogProviderDirectoryRow(
                id: "30th-c",
                name: "30th Classic",
                logo: scenario.directoryLogo,
                symbol: scenario.directorySymbol,
                cardCount: count,
                releaseDate: "2026-09-16"
            )

            let fixture = try await client.fetchFixture(directory: [row])
            let fetchedSet = try XCTUnwrap(fixture.sets.first)
            XCTAssertEqual(fetchedSet.logo, scenario.rawLogo, scenario.name)
            XCTAssertEqual(fetchedSet.symbol, scenario.rawSymbol, scenario.name)
            XCTAssertEqual(
                fetchedSet.resolvedLogo,
                scenario.expectedResolvedLogo,
                scenario.name
            )
            XCTAssertEqual(
                fetchedSet.resolvedSymbol,
                scenario.expectedResolvedSymbol,
                scenario.name
            )

            let details = Dictionary(uniqueKeysWithValues: fixture.cards.map { ($0.id, $0) })
            let deviceFingerprint = try XCTUnwrap(
                PokemonCatalogProviderFingerprint.v1(
                    providerSet: rawSet,
                    cardDetails: details
                )
            )
            let result = try PokemonCatalogBuilder().build(
                .init(
                    fixture: fixture,
                    humanInputs: [],
                    revision: 1,
                    generatedAt: generatedAt
                )
            )
            let descriptor = try XCTUnwrap(result.release.sets.first)

            XCTAssertEqual(descriptor.providerFingerprint, deviceFingerprint, scenario.name)
            XCTAssertEqual(descriptor.logoURL, scenario.expectedResolvedLogo, scenario.name)
            XCTAssertEqual(
                descriptor.symbolURL,
                scenario.expectedResolvedSymbol,
                scenario.name
            )
        }
    }

    private struct Scenario {
        let name: String
        let rawLogo: String?
        let rawSymbol: String?
        let directoryLogo: String?
        let directorySymbol: String?
        let resolverLogo: String?
        let resolverSymbol: String?
        let expectedResolvedLogo: String?
        let expectedResolvedSymbol: String?
    }
}
