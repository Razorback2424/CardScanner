import XCTest
@testable import TradingCardScanner

final class ScannedGradedResolverTests: XCTestCase {
    func testKnownAmbiguousFinishCannotBeInferredFromTheOnlyPublishedSlab() async throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "pokemon-yellow-a-product-proof", withExtension: "json",
            subdirectory: "TradingCards/SetPricingAudit"))
        let document = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let entries = try XCTUnwrap(document["cases"] as? [[String: Any]])
        let entry = try XCTUnwrap(entries.first { ($0["products"] as? [Any])?.count == 2 })
        let source = try JSONDecoder().decode(TCGdexCard.self,
            from: JSONSerialization.data(withJSONObject: XCTUnwrap(entry["source"])))
        let card = IdentifiedCard.pokemon(source, setCode: "")
        XCTAssertEqual(Set(card.variantEvidence.catalogVariants), [.normal, .holo])
        let candidate = GradedVariant(id: "only-published-holo", company: .psa,
            grade: .init(value: "10"), printing: "Holofoil", marketPriceUSD: 123, updatedAt: nil)
        let recorder = GradedIdentityRecorder()
        let resolver = ScannedGradedResolver(client: StubLookupClient(result: .matched([candidate]), identityRecorder: recorder),
            credentialsAvailable: true)
        let unknown = await resolver.resolve(card: card, slab: slab(company: .psa, value: "10"), pokemonPrintRun: nil)
        XCTAssertEqual(unknown, .unavailable)
        let before = await recorder.lastIdentity
        XCTAssertNil(before)
        let known = await resolver.resolve(card: card, slab: .init(company: .psa, grade: .init(value: "10"),
            certificationNumber: nil, labelCardText: [], printedFinish: .holo), pokemonPrintRun: nil)
        XCTAssertEqual(known, .bound(candidate))
    }

    func testLabelPrintRunIsUsedWithoutTreatingItsLegacyFlagAsAnotherFinish() async throws {
        let source = try JSONDecoder().decode(TCGdexCard.self, from: Data(#"{"id":"base1-4","localId":"4","name":"Charizard","set":{"id":"base1","name":"Base Set","cardCount":{"total":102,"official":102}},"variants":{"normal":false,"holo":true,"reverse":false,"firstEdition":true}}"#.utf8))
        let card = IdentifiedCard.pokemon(source, setCode: "BS")
        XCTAssertEqual(Set(card.variantEvidence.catalogVariants), [.holo, .firstEdition])
        let candidate = GradedVariant(id: "first-edition-holo", company: .psa,
            grade: .init(value: "10"), printing: "1st Edition Holofoil", marketPriceUSD: 123, updatedAt: nil)
        let recorder = GradedIdentityRecorder()
        let resolver = ScannedGradedResolver(client: StubLookupClient(result: .matched([candidate]), identityRecorder: recorder),
            credentialsAvailable: true)
        let evidence = GradedSlabEvidence(company: .psa, grade: .init(value: "10"),
            certificationNumber: nil, labelCardText: [], printedPrintRun: .firstEdition)
        let result = await resolver.resolve(card: card, slab: evidence, pokemonPrintRun: nil)
        XCTAssertEqual(result, .bound(candidate))
        let identity = await recorder.lastIdentity
        XCTAssertEqual(identity?.pokemonPrintRun, .firstEdition)
        let unlimited = GradedVariant(id: "unlimited", company: .psa, grade: .init(value: "10"),
            printing: "Unlimited Holofoil", marketPriceUSD: 5, updatedAt: nil)
        XCTAssertNil(ScannedGradedResolver.matchingVariant(in: [unlimited], for: evidence))
    }

    func testOwnedNormalCGC10RejectsReverseHoloAndMissingFinish() {
        let evidence = GradedSlabEvidence(company: .cgc,
            grade: CardGrade(value: "10", label: "Gem Mint"), certificationNumber: "SYNTHETIC-001",
            labelCardText: [], printedFinish: .normal)
        for printing: String? in ["Reverse Holofoil", nil] {
            let candidate = GradedVariant(id: "synthetic-reverse", company: .cgc,
                grade: evidence.grade, printing: printing, marketPriceUSD: 40, updatedAt: nil)
            XCTAssertNil(ScannedGradedResolver.matchingVariant(in: [candidate], for: evidence))
        }
    }

    func testDisabledGradedCapabilityStopsBeforeVendorLookup() async {
        let recorder = GradedIdentityRecorder()
        let resolver = ScannedGradedResolver(
            client: StubLookupClient(result: .matched([]), identityRecorder: recorder),
            credentialsAvailable: true, gameRegistry: CardGameRegistry(descriptors: [])
        )
        let outcome = await resolver.resolve(card: card, slab: slab(company: .psa, value: "10"),
                                             pokemonPrintRun: nil)
        XCTAssertEqual(outcome, .unavailable)
        let identity = await recorder.lastIdentity
        XCTAssertNil(identity)
    }

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

    func testMatchingNormalizesGraderLabelSynonyms() {
        let aliases = [
            (vendor: "GEM MT", scanned: "Gem Mint"),
            (vendor: "NM-MT", scanned: "NM MT"),
            (vendor: "EX-MT", scanned: "EX MT"),
            (vendor: "VG-EXCELLENT", scanned: "VG EX"),
            (vendor: "MINT PLUS", scanned: "MINT+")
        ]

        for (index, labels) in aliases.enumerated() {
            let vendorVariant = variant(
                id: "label-alias-\(index)",
                company: .psa,
                grade: CardGrade(value: "9", label: labels.vendor)
            )
            XCTAssertEqual(
                ScannedGradedResolver.matchingVariant(
                    in: [vendorVariant],
                    for: slab(company: .psa, value: "9", label: labels.scanned)
                ),
                vendorVariant,
                "\(labels.vendor) should match \(labels.scanned)"
            )
        }
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

    func testMatchingNormalizesNumericGradeFormatting() {
        let vendorVariant = variant(
            id: "psa-10",
            company: .psa,
            grade: CardGrade(value: "10")
        )

        let match = ScannedGradedResolver.matchingVariant(
            in: [vendorVariant],
            for: slab(company: .psa, value: "10.0")
        )

        XCTAssertEqual(match, vendorVariant)
    }

    func testConflictingVendorLabelIsNotUsedAsAFallbackMatch() {
        let vendorVariant = variant(
            id: "psa-pristine",
            company: .psa,
            grade: CardGrade(value: "10", label: "Pristine")
        )

        XCTAssertNil(ScannedGradedResolver.matchingVariant(
            in: [vendorVariant],
            for: slab(company: .psa, value: "10", label: "Gem Mint")
        ))
    }

    func testBlackLabelCannotMatchAnUnlabeledOrDifferentLabelRead() {
        let blackLabel = variant(
            id: "bgs-black-label",
            company: .bgs,
            grade: CardGrade(value: "10", label: "Black Label")
        )

        XCTAssertNil(ScannedGradedResolver.matchingVariant(
            in: [blackLabel],
            for: slab(company: .bgs, value: "10", label: "Gem Mint")
        ))
        XCTAssertNil(ScannedGradedResolver.matchingVariant(
            in: [blackLabel],
            for: slab(company: .bgs, value: "10")
        ))
    }

    func testResolverMapsVendorOutcomesAndCredentialGate() async {
        let noListings = await resolve(.cardFoundWithoutGradedVariants)
        XCTAssertEqual(
            noListings,
            .noGradedListings(GradedMarketCoverage(status: .noGradedListings))
        )

        let unmatched = await resolve(.noProductMatch)
        XCTAssertEqual(unmatched, .cardNotTracked(GradedMarketCoverage(status: .cardNotTracked)))

        let noKey = await ScannedGradedResolver(
            client: StubLookupClient(result: .matched([])),
            credentialsAvailable: false
        ).resolve(card: card, slab: slab(company: .psa, value: "10"), pokemonPrintRun: nil)
        XCTAssertEqual(noKey, .unavailable)
    }

    func testMissingGradeRetainsOtherJustTCGGradesWithoutFilteringTheRequest() async throws {
        // Prices and grades below are from the Charizard graded response
        // summarized for this task. A CGC 10 must remain unpriced even though
        // nearby PSA and CGC grades are listed.
        let variants = [
            variant(id: "psa-8", company: .psa, grade: CardGrade(value: "8"), priceUSD: 1_479.99),
            variant(id: "psa-7", company: .psa, grade: CardGrade(value: "7"), priceUSD: 725),
            variant(id: "cgc-7", company: .cgc, grade: CardGrade(value: "7"), priceUSD: 650),
            variant(id: "cgc-6", company: .cgc, grade: CardGrade(value: "6"), priceUSD: 519.99),
            variant(id: "cgc-5", company: .cgc, grade: CardGrade(value: "5"), priceUSD: 500),
            variant(id: "psa-3", company: .psa, grade: CardGrade(value: "3"), priceUSD: 300),
            variant(id: "cgc-2_5", company: .cgc, grade: CardGrade(value: "2.5"), priceUSD: 270)
        ]
        let recorder = GradedLookupRequestRecorder()
        let resolver = ScannedGradedResolver(
            client: StubLookupClient(result: .matched(variants), requestRecorder: recorder),
            timeout: .seconds(1),
            credentialsAvailable: true
        )

        let outcome = await resolver.resolve(
            card: card,
            slab: slab(company: .cgc, value: "10", label: "Gem Mint"),
            pokemonPrintRun: nil
        )

        guard case let .gradeNotTracked(coverage) = outcome else {
            return XCTFail("Expected the missing CGC 10 to be classified as unlisted")
        }
        XCTAssertEqual(coverage.status, .gradeNotListed)
        XCTAssertEqual(coverage.listedGrades.count, 7)
        XCTAssertEqual(coverage.listedGrades.first?.displayName, "PSA 8")
        XCTAssertEqual(coverage.listedGrades.first?.marketPriceUSD, 1_479.99)
        let filters = await recorder.snapshot()
        XCTAssertTrue(filters.companies.isEmpty)
        XCTAssertTrue(filters.grades.isEmpty)
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

    func testResolverPassesTheResolvedPrintRunIntoTheVendorIdentity() async {
        let recorder = GradedIdentityRecorder()
        let resolver = ScannedGradedResolver(
            client: StubLookupClient(
                result: .matched([]),
                identityRecorder: recorder
            ),
            timeout: .seconds(1),
            credentialsAvailable: true
        )

        _ = await resolver.resolve(
            card: card,
            slab: slab(company: .psa, value: "10"),
            pokemonPrintRun: .firstEdition
        )

        let identity = await recorder.lastIdentity
        XCTAssertEqual(identity?.pokemonPrintRun, .firstEdition)
    }

    func testResolvedPrintRunSelectsTheEditionSpecificVendorSetSlug() {
        let directory = ProductSetDirectory(sets: [
            (id: "base-set-pokemon", name: "Base Set"),
            (id: "base-set-shadowless-pokemon", name: "Base Set — Shadowless")
        ])
        let identity = GradedCardIdentity(
            name: "Charizard",
            setName: "Base Set",
            collectorNumber: "4",
            catalogID: "base1-4",
            pokemonPrintRun: .firstEdition
        )

        XCTAssertEqual(
            JustTCGV2GradedClient.resolvedSetSlug(
                identity: identity,
                game: .pokemon,
                directory: directory
            ),
            "base-set-shadowless-pokemon"
        )
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

    private func variant(
        id: String,
        company: GradingCompany,
        grade: CardGrade,
        priceUSD: Double? = 125
    ) -> GradedVariant {
        GradedVariant(
            id: id,
            cardID: "vendor-card",
            company: company,
            grade: grade,
            printing: "Normal",
            marketPriceUSD: priceUSD,
            updatedAt: nil
        )
    }
}

private struct StubLookupClient: ScannedGradedLookupClient {
    enum StubError: Error, Sendable { case failed }

    let result: GradedVariantLookupResult
    let delayNanoseconds: UInt64
    let throwsError: Bool
    let identityRecorder: GradedIdentityRecorder?
    let requestRecorder: GradedLookupRequestRecorder?

    init(
        result: GradedVariantLookupResult = .matched([]),
        delayNanoseconds: UInt64 = 0,
        throwsError: Bool = false,
        identityRecorder: GradedIdentityRecorder? = nil,
        requestRecorder: GradedLookupRequestRecorder? = nil
    ) {
        self.result = result
        self.delayNanoseconds = delayNanoseconds
        self.throwsError = throwsError
        self.identityRecorder = identityRecorder
        self.requestRecorder = requestRecorder
    }

    func lookup(
        identity: GradedCardIdentity,
        game: CardGame,
        companies: Set<GradingCompany>,
        grades: Set<String>,
        lane: JustTCGRequestLane
    ) async throws -> GradedVariantLookupResult {
        await identityRecorder?.record(identity)
        await requestRecorder?.record(companies: companies, grades: grades)
        if delayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: delayNanoseconds)
        }
        if throwsError { throw StubError.failed }
        return result
    }
}

private actor GradedIdentityRecorder {
    private(set) var lastIdentity: GradedCardIdentity?

    func record(_ identity: GradedCardIdentity) {
        lastIdentity = identity
    }
}

private actor GradedLookupRequestRecorder {
    private(set) var companies = Set<GradingCompany>()
    private(set) var grades = Set<String>()

    func record(companies: Set<GradingCompany>, grades: Set<String>) {
        self.companies = companies
        self.grades = grades
    }

    func snapshot() -> (companies: Set<GradingCompany>, grades: Set<String>) {
        (companies, grades)
    }
}
