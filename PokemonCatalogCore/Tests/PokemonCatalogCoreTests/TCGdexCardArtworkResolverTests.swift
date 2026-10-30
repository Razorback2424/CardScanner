import Foundation
import XCTest
@testable import PokemonCatalogCore

final class TCGdexCardArtworkResolverTests: XCTestCase {
    private static let png = Data(base64Encoded:
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=")!

    func testRecoversExactArtworkAcrossSeriesAndLanguages() async throws {
        for (language, series, set, number) in [
            ("en", "sv", "svp", "196"), ("en", "me", "mep", "027"),
            ("en", "base", "base1", "1"), ("ja", "SV", "SV8a", "014")
        ] {
            let prefix = "https://assets.tcgdex.net/\(language)/\(series)/\(set)/\(number)/"
            let resolver = PokemonCatalogTCGdexCardArtworkResolver { request in
                XCTAssertTrue(request.url!.absoluteString.hasPrefix(prefix))
                return Self.response(request, data: Self.png)
            }
            let artwork = await resolver.resolve(language: language, seriesID: series,
                setID: set, cardID: set + "-" + number, localID: number)
            XCTAssertEqual(artwork?.imageURL, prefix + "high.png")
            XCTAssertEqual(artwork?.thumbnailURL, prefix + "low.png")
            XCTAssertEqual(artwork?.source, .tcgdexCDNProbe)
        }
    }

    func testRejectsHTTPFailuresHTMLCorruptionAndRedirects() async {
        for failure in ["404", "500", "html", "corrupt", "empty", "redirect"] {
            let resolver = PokemonCatalogTCGdexCardArtworkResolver { request in
                let url = failure == "redirect" ? URL(string: "https://other.example/card.png")! : request.url!
                let response = HTTPURLResponse(url: url,
                    statusCode: Int(failure) ?? 200, httpVersion: nil,
                    headerFields: ["Content-Type": failure == "html" ? "text/html" : "image/png"])!
                let data = failure == "corrupt" ? Data("not an image".utf8)
                    : failure == "empty" ? Data() : Self.png
                return (data, response)
            }
            let artwork = await resolver.resolve(seriesID: "sv", setID: "svp",
                cardID: "svp-196", localID: "196")
            XCTAssertNil(artwork, failure)
        }
    }

    func testTriesWebPAndUsesOneHealthySizeWhenOtherSizeIsAbsent() async {
        let resolver = PokemonCatalogTCGdexCardArtworkResolver { request in
            Self.response(request, data: Self.png,
                status: request.url!.path.hasSuffix("/low.webp") ? 200 : 404)
        }
        let artwork = await resolver.resolve(seriesID: "sv", setID: "svp",
            cardID: "svp-196", localID: "196")
        XCTAssertEqual(artwork?.imageURL, "https://assets.tcgdex.net/en/sv/svp/196/low.webp")
        XCTAssertEqual(artwork?.thumbnailURL, artwork?.imageURL)
    }

    func testMalformedOrMismatchedIdentityNeverMakesARequest() async {
        let resolver = PokemonCatalogTCGdexCardArtworkResolver { _ in
            XCTFail("Invalid identities must not probe the CDN")
            throw URLError(.badURL)
        }
        for (series, set, card, local) in [
            ("", "svp", "svp-196", "196"), ("sv", "svp", "svp-197", "196"),
            ("sv", "../svp", "../svp-196", "196"), ("sv", "svp", "svp-..", ".."),
            ("sv", "svp", "svp-196/other", "196/other")
        ] {
            let result = await resolver.resolve(seriesID: series, setID: set, cardID: card, localID: local)
            XCTAssertNil(result)
        }
    }

    func testPublisherProbesEveryMissingCardAndPreservesRawFingerprint() async throws {
        let briefs: [PokemonCatalogProviderCardBrief] = [
            .init(id: "svp-196", localID: "196", name: "Charizard ex"),
            .init(id: "svp-199", localID: "199", name: "Zarude"),
            .init(id: "svp-200", localID: "200", name: "Eevee"),
            .init(id: "svp-001", localID: "001", name: "Sprigatito", image: "https://assets.tcgdex.net/en/sv/svp/001")
        ]
        let raw = PokemonCatalogProviderSet(id: "svp", name: "SVP Black Star Promos", cards: briefs,
            logo: "https://example.test/logo.png", symbol: "https://example.test/symbol.png",
            serie: .init(id: "sv"))
        let details = Dictionary(uniqueKeysWithValues: briefs.map {
            ($0.id, PokemonCatalogProviderCard(id: $0.id, localID: $0.localID,
                name: $0.name, image: $0.image, setID: "svp"))
        })
        let resolver = PokemonCatalogTCGdexCardArtworkResolver { request in
            XCTAssertFalse(request.url!.path.contains("/001/"), "Existing provider artwork must win")
            return Self.response(request, data: Self.png,
                status: request.url!.path.contains("/199/") ? 404 : 200)
        }
        let result = await PokemonCatalogArtworkEnricher(cardArtworkResolver: resolver).enrich(raw,
            cardDetails: details, directoryRow: .init(id: raw.id, name: raw.name))
        let recovered = result.providerSet.resolvedCardArtworkByLocalID
        XCTAssertEqual(Set(recovered?.keys.map { $0 } ?? []), ["196", "200"])
        XCTAssertEqual(recovered?["196"]?.source, .tcgdexCDNProbe)
        XCTAssertEqual(result.providerSet.cards, raw.cards)
        XCTAssertEqual(PokemonCatalogProviderFingerprint.v1(providerSet: result.providerSet, cardDetails: details),
                       PokemonCatalogProviderFingerprint.v1(providerSet: raw, cardDetails: details))
        XCTAssertTrue(result.providerSet.resolvedArtworkSource?.contains("cards:tcgdexCDNProbe:196,200") == true)
    }

    func testRecoveredArtworkIsIncludedInPublishedDescriptorAndChecklist() async throws {
        let brief = PokemonCatalogProviderCardBrief(id: "future-001", localID: "001", name: "Future Card")
        let raw = PokemonCatalogProviderSet(id: "future", name: "Future Set", cards: [brief],
            logo: "https://assets.tcgdex.net/en/sv/future/logo.png",
            symbol: "https://assets.tcgdex.net/univ/sv/future/symbol.png",
            releaseDate: "2026-09-16", cardCount: .init(total: 1, official: 1),
            serie: .init(id: "sv"), abbreviation: .init(official: "FTR"))
        let row = PokemonCatalogProviderDirectoryRow(id: raw.id, name: raw.name,
            cardCount: raw.cardCount, releaseDate: raw.releaseDate)
        let enriched = await PokemonCatalogArtworkEnricher(cardArtworkResolver: .init { request in
            Self.response(request, data: Self.png)
        }).enrich(raw, directoryRow: row)
        let detail = PokemonCatalogProviderCard(id: brief.id, localID: brief.localID, name: brief.name, setID: raw.id)
        let built = try PokemonCatalogBuilder().build(.init(
            fixture: .init(directory: [row], sets: [enriched.providerSet], cards: [detail]),
            humanInputs: [], revision: 1, generatedAt: Date(timeIntervalSince1970: 1_800_000_000)))
        let artwork = try XCTUnwrap(built.release.sets.first?.cardArtwork?.first)
        XCTAssertEqual(artwork.imageURL, "https://assets.tcgdex.net/en/sv/future/001/high.png")
        XCTAssertEqual(artwork.thumbnailURL, "https://assets.tcgdex.net/en/sv/future/001/low.png")
        XCTAssertEqual(built.snapshot.checklists["future"]?.first?.imageURL, artwork.imageURL)
        XCTAssertTrue(built.report.sets.first?.artworkSource?.contains("cards:tcgdexCDNProbe:001") == true)
    }

    func testLiveManifestOmissionsWhenRequested() async throws {
        guard ProcessInfo.processInfo.environment["POKEMON_LIVE_ARTWORK_TESTS"] == "1" else {
            throw XCTSkip("Opt-in live CDN verification")
        }
        for (series, set, number) in [("sv", "svp", "196"), ("me", "mep", "027"), ("tcgp", "P-A", "084")] {
            let artwork = await PokemonCatalogTCGdexCardArtworkResolver().resolve(
                seriesID: series, setID: set, cardID: set + "-" + number, localID: number)
            XCTAssertNotNil(artwork, set + "-" + number)
        }
        // Audit every currently missing image in both supported English promo
        // families, including cards with no CDN file that must stay unresolved.
        for (setID, expectedRecoveredID) in [("svp", "196"), ("mep", "027")] {
            let (data, response) = try await URLSession.shared.data(from:
                URL(string: "https://api.tcgdex.net/v2/en/sets/" + setID)!)
            XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
            let raw = try JSONDecoder().decode(PokemonCatalogProviderSet.self, from: data)
            let result = await PokemonCatalogArtworkEnricher().enrich(raw,
                directoryRow: .init(id: raw.id, name: raw.name))
            let recovered = result.providerSet.resolvedCardArtworkByLocalID ?? [:]
            let missing = raw.cards.filter { $0.image == nil }.count
            XCTAssertNotNil(recovered[expectedRecoveredID])
            XCTAssertEqual(result.providerSet.cards, raw.cards)
            print("Artwork audit \(setID): \(missing) missing metadata, \(recovered.count) recovered from CDN, \(missing - recovered.count) still unavailable")
        }
    }

    private static func response(_ request: URLRequest, data: Data, status: Int = 200) -> (Data, HTTPURLResponse) {
        (data, HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil,
            headerFields: ["Content-Type": "image/png"])!)
    }
}
