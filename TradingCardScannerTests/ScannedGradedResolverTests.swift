import XCTest
@testable import TradingCardScanner

final class ScannedGradedResolverTests: XCTestCase {
    func testResolverBindsSingleGradeWhenVendorLabelUsesDifferentVocabulary() async {
        let vendorVariant = variant(
            id: "vendor-gem-mt",
            company: .psa,
            grade: CardGrade(value: "10", label: "GEM MT")
        )
        let resolver = ScannedGradedResolver(
            client: StubLookupClient(result: .matched([vendorVariant])),
            timeout: .seconds(1),
            credentialsAvailable: true
        )

        let outcome = await resolver.resolve(
            card: card,
            slab: slab(company: .psa, value: "10", label: "Gem Mint"),
            pokemonPrintRun: nil
        )

        XCTAssertEqual(outcome, .bound(vendorVariant))
    }

    func testMatchingUsesLabelOnlyToBreakAStableGradeAxisTie() {
        let blackLabel = variant(
            id: "black-label",
            company: .bgs,
            grade: CardGrade(value: "10", label: "Black Label")
        )
        let gemMint = variant(
            id: "gem-mint",
            company: .bgs,
            grade: CardGrade(value: "10", label: "GEM MT")
        )

        let match = ScannedGradedResolver.matchingVariant(
            in: [gemMint, blackLabel],
            for: slab(company: .bgs, value: "10", label: "Black Label")
        )

        XCTAssertEqual(match, blackLabel)
    }

    func testResolverMapsVendorOutcomesAndCredentialGate() async {
        let unpriced = await resolve(.cardFoundWithoutGradedVariants)
        XCTAssertEqual(unpriced, .unpricedGrade)

        let unmatched = await resolve(.noProductMatch)
        XCTAssertEqual(unmatched, .unmatchedProduct)

        let noKey = await ScannedGradedResolver(
            client: StubLookupClient(result: .matched([])),
            credentialsAvailable: false
        ).resolve(card: card, slab: slab(company: .psa, value: "10"), pokemonPrintRun: nil)
        XCTAssertEqual(noKey, .unavailable)
    }

    func testResolverTreatsTransportAndTimeoutAsUnavailable() async {
        let thrown = await ScannedGradedResolver(
            client: StubLookupClient(throwsError: true),
            timeout: .seconds(1),
            credentialsAvailable: true
        ).resolve(card: card, slab: slab(company: .psa, value: "10"), pokemonPrintRun: nil)
        XCTAssertEqual(thrown, .unavailable)

        let timedOut = await ScannedGradedResolver(
            client: StubLookupClient(
                result: .matched([]),
                delayNanoseconds: 200_000_000
            ),
            timeout: .milliseconds(10),
            credentialsAvailable: true
        ).resolve(card: card, slab: slab(company: .psa, value: "10"), pokemonPrintRun: nil)
        XCTAssertEqual(timedOut, .unavailable)
    }

    private func resolve(_ result: GradedVariantLookupResult) async -> ScannedGradedOutcome {
        await ScannedGradedResolver(
            client: StubLookupClient(result: result),
            timeout: .seconds(1),
            credentialsAvailable: true
        ).resolve(card: card, slab: slab(company: .psa, value: "10"), pokemonPrintRun: nil)
    }

    private var card: IdentifiedCard {
        .pokemon(
            TCGdexCard(
                id: "sv10-085",
                localId: "085",
                name: "Example Pokémon",
                image: nil,
                rarity: nil,
                set: TCGdexSetBrief(
                    id: "sv10",
                    name: "Destined Rivals",
                    cardCount: TCGdexCardCount(total: 182, official: 182)
                ),
                variants: nil,
                pricing: nil,
                variantsDetailed: nil
            ),
            setCode: "DRI"
        )
    }

    private func slab(
        company: GradingCompany,
        value: String,
        label: String? = nil,
        qualifier: String? = nil
    ) -> GradedSlabEvidence {
        GradedSlabEvidence(
            company: company,
            grade: CardGrade(value: value, label: label, qualifier: qualifier),
            certificationNumber: nil,
            labelCardText: []
        )
    }

    private func variant(id: String, company: GradingCompany, grade: CardGrade) -> GradedVariant {
        GradedVariant(
            id: id,
            cardID: "vendor-card",
            company: company,
            grade: grade,
            marketPriceUSD: 125,
            updatedAt: nil
        )
    }
}

private struct StubLookupClient: ScannedGradedLookupClient {
    enum StubError: Error, Sendable { case failed }

    let result: GradedVariantLookupResult
    let delayNanoseconds: UInt64
    let throwsError: Bool

    init(
        result: GradedVariantLookupResult = .matched([]),
        delayNanoseconds: UInt64 = 0,
        throwsError: Bool = false
    ) {
        self.result = result
        self.delayNanoseconds = delayNanoseconds
        self.throwsError = throwsError
    }

    func lookup(
        identity: GradedCardIdentity,
        game: CardGame,
        companies: Set<GradingCompany>,
        grades: Set<String>,
        lane: JustTCGRequestLane
    ) async throws -> GradedVariantLookupResult {
        if delayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: delayNanoseconds)
        }
        if throwsError { throw StubError.failed }
        return result
    }
}
