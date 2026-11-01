import XCTest
@testable import TradingCardScanner

private actor MarketRefreshProgressProbe {
    private var samples: [(checked: Int, requests: Int)] = []

    func record(_ report: MarketRefreshReport, requests: Int) {
        samples.append((report.targetsChecked, requests))
    }

    func snapshot() -> [(checked: Int, requests: Int)] { samples }
}

private actor EditionPriceProbe {
    var prices: [String: Double] = [:]
    func record(_ variant: JustTCGVariant, owners: [MarketPriceTarget]) {
        for owner in owners { prices[owner.priceKey] = variant.price }
    }
}

/// Slice 1: the wire contract, pinned against fixtures.
///
/// These exist because the expensive mistakes in this layer are silent ones — a
/// batch item with two identifiers, a response correlated by position, a delta
/// omission read as "no price". None of those throw; they just produce wrong
/// numbers in someone's collection.
final class JustTCGContractTests: XCTestCase {
    func testRawDirectProductLookupKeepsJapanesePrintingSeparateFromEnglish() throws {
        let response = try JSONDecoder().decode(JustTCGBatchResponse.self, from: Data(#"{"data":[{"uuid":"synthetic-card","tcgplayerId":"123","variants":[{"uuid":"en","condition":"Near Mint","printing":"Holofoil","language":"English","price":999},{"uuid":"ja","condition":"Near Mint","printing":"Holofoil - Japanese","language":"Japanese","price":40}]}]}"#.utf8))
        func target(_ id: String, japanese: Bool? = nil) -> MarketPriceTarget {
            .init(priceKey: id, game: .pokemon, printingID: id, variantID: "holo", itemKind: .rawCard,
                marketVariantID: nil, lookupCandidates: [.tcgplayerID("123")], currentAmount: nil,
                lastCheckedAt: nil, isJapanese: japanese)
        }
        for owner in [target("M2-001"), target("csv:synthetic-jp", japanese: true), target("sv03.5-001")] {
            guard case let .matched(_, listing) = JustTCGRefreshCoordinator.exactListing(lookup: .tcgplayerID("123"),
                owners: [owner], response: response) else { return XCTFail("Expected exact language lane") }
            XCTAssertEqual(listing.variantId, owner.isJapanese ? "ja" : "en")
        }
        if case .matched = JustTCGRefreshCoordinator.exactListing(lookup: .tcgplayerID("123"),
            owners: [target("M2-001"), target("sv03.5-001")], response: response) { XCTFail("Mixed languages must not share a listing") }
    }

    func testReviewedCosmosGradedLookupRequiresTheExactPublicFamilyProduct() async throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "reported-parallel-review",
            withExtension: "json", subdirectory: "TradingCards/PokemonCatalogCoverageAudit"))
        let proof = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let family = try XCTUnwrap(proof["boundedRetailFamily"] as? [String: Any])
        let members = try XCTUnwrap(family["members"] as? [[String: Any]])
        let cases = try XCTUnwrap(proof["cases"] as? [[String: Any]])
        let client = try gradedFixtureClient(directory: ProductSetDirectoryProvider())
        for member in members {
            let id = try XCTUnwrap(member["catalogID"] as? String)
            let productID = String(try XCTUnwrap(member["productID"] as? Int))
            let entry = try XCTUnwrap(cases.first { $0["catalogID"] as? String == id })
            let source = try JSONDecoder().decode(TCGdexCard.self,
                from: JSONSerialization.data(withJSONObject: XCTUnwrap(entry["source"])))
            let product = try XCTUnwrap(entry["product"] as? [String: Any])
            let number = try XCTUnwrap(((product["extendedData"] as? [[String: Any]])?.first { $0["name"] as? String == "Number" })?["value"] as? String)
            let identity = GradedCardIdentity(name: source.name, setName: source.set.name,
                collectorNumber: source.localId, catalogID: id, finish: .pokemonFoilPattern("cosmos"))
            let base: [String: Any] = ["id": "synthetic-cosmos-card", "name": product["name"]!, "number": number,
                "game": ["id": "pokemon"], "set": ["id": "blister-exclusives-pokemon", "name": "Blister Exclusives"],
                "external_ids": ["tcgplayer": productID], "variants": [["id": "synthetic-cosmos-10", "type": "graded",
                    "printing": "Holofoil", "language": "English", "grading": ["company": "CGC", "grade": 10, "grade_label": "Gem Mint"],
                    "markets": [["region": "NA", "currency": "USD", "price": 40]]]]]
            func lookup(_ card: [String: Any]) async throws -> GradedVariantLookupResult {
                RecordingURLProtocol.reset(body: String(decoding: try JSONSerialization.data(withJSONObject: ["data": [card]]), as: UTF8.self))
                return try await client.lookup(identity: identity, game: .pokemon, companies: [.cgc], grades: ["10"])
            }
            guard case let .matched(variants) = try await lookup(base), let exact = variants.first else { return XCTFail("Exact Cosmos product must be admitted") }
            XCTAssertEqual(exact.verifiedProductID, productID)
            let owned = GradedSlabEvidence(company: .cgc, grade: .init(value: "10", label: "Gem Mint"),
                certificationNumber: nil, labelCardText: [], printedFinish: .pokemonFoilPattern("cosmos"))
            XCTAssertEqual(ScannedGradedResolver.matchingVariant(in: variants, for: owned, catalogID: id), exact)
            XCTAssertNil(ScannedGradedResolver.matchingVariant(in: variants, for: owned))
            XCTAssertNil(ScannedGradedResolver.matchingVariant(in: variants, for: owned, catalogID: "me03-999"))
            for wrongProduct in ["675909", "704797", "684431", "685555", "686505"] {
                var wrong = base; wrong["external_ids"] = ["tcgplayer": wrongProduct]
                if case .matched = try await lookup(wrong) { XCTFail("Ordinary/stamped product admitted for \(id)") }
            }
            for (field, value) in [("name", source.name + " (GameStop)"), ("number", "999/999")] {
                var wrong = base; wrong[field] = value
                if case .matched = try await lookup(wrong) { XCTFail("Contradictory product metadata admitted") }
            }
            var wrong = base
            var lanes = try XCTUnwrap(wrong["variants"] as? [[String: Any]])
            lanes[0]["language"] = "Japanese"; wrong["variants"] = lanes
            let wrongLanguage = try await lookup(wrong)
            XCTAssertEqual(wrongLanguage, .localIdentityUnresolved)
            let request = try XCTUnwrap(RecordingURLProtocol.recorded().first)
            let query = URLComponents(url: request, resolvingAgainstBaseURL: false)?.queryItems
            XCTAssertEqual(query?.first { $0.name == "tcgplayer_id" }?.value, productID)
            XCTAssertNil(query?.first { $0.name == "q" })
            XCTAssertNil(query?.first { $0.name == "set" })
        }
    }

    func testV2JapaneseLanguageSurvivesLookupAndRejectsForeignOrMissingEvidence() async throws {
        let directory = ProductSetDirectoryProvider()
        _ = try await directory.directory(for: .pokemonJapan) {
            ProductSetDirectory(sets: [(id: "m2-pokemon-japan", name: "M2")])
        }
        let client = try gradedFixtureClient(directory: directory)
        let identity = GradedCardIdentity(name: "Pikachu", setName: "M2", collectorNumber: "001",
            catalogID: "M2-001", finish: .holo)
        for language: String? in ["Japanese", "English", "Korean", nil] {
            let field = language.map { ",\"language\":\"\($0)\"" } ?? ""
            RecordingURLProtocol.reset(body: """
            {"data":[{"id":"synthetic-ja","name":"Pikachu","number":"001","game":{"id":"pokemon-japan"},
             "set":{"id":"m2-pokemon-japan","name":"M2"},"variants":[{"id":"synthetic-ja-10","type":"graded",
             "printing":"Holofoil"\(field),"grading":{"company":"CGC","grade":10,"grade_label":"Gem Mint"},
             "markets":[{"region":"NA","currency":"USD","price":40}]}]}]}
            """)
            let result = try await client.lookup(identity: identity, game: .pokemon)
            if language == "Japanese" {
                guard case let .matched(variants) = result, let variant = variants.first else { return XCTFail("Expected exact Japanese slab") }
                XCTAssertEqual(variant.language, "Japanese")
                XCTAssertEqual(variant.printing, "Holofoil")
                XCTAssertEqual(variant.persistedPrinting, "Holofoil - Japanese")
                XCTAssertTrue(GradedCardIdentity.matchesFinish(.holo, printing: variant.persistedPrinting, isJapanese: true))
                XCTAssertFalse(GradedCardIdentity.matchesFinish(.holo, printing: variant.persistedPrinting))
                let slab = GradedSlabEvidence(company: .cgc, grade: .init(value: "10", label: "Gem Mint"),
                    certificationNumber: nil, labelCardText: [], printedFinish: .holo)
                XCTAssertEqual(ScannedGradedResolver.matchingVariant(in: variants, for: slab, isJapanese: true), variant)
                XCTAssertNil(ScannedGradedResolver.matchingVariant(in: variants, for: slab, isJapanese: false))
            } else {
                XCTAssertEqual(result, .localIdentityUnresolved, "Foreign/missing language is not provider absence")
            }
            let request = try XCTUnwrap(RecordingURLProtocol.recorded().last)
            let query = URLComponents(url: request, resolvingAgainstBaseURL: false)?.queryItems
            XCTAssertEqual(query?.first { $0.name == "language" }?.value, "Japanese")
        }
    }

    @MainActor
    func testGradedPickerRetriesTransientAndIncompleteSearchesWithoutRetryingTerminalResults() async throws {
        let previousKey = PriceVendorCredentials.key
        defer {
            if let previousKey { try? PriceVendorCredentials.store(previousKey) }
            else { PriceVendorCredentials.remove() }
        }
        try PriceVendorCredentials.store("graded-picker-fixture-key")
        let suite = "GradedPickerRetry-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RecordingURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        var settings = JustTCGTransport.Configuration()
        settings.baseURL = URL(string: "https://justtcg.test")!
        settings.minimumRequestInterval = 0
        let model = GradedVariantModel(transport: .init(configuration: settings, session: session,
            ledger: .init(defaults: defaults), pacer: .init(), apiKeyOverride: "fixture-key"))
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "pokemon-subset-product-proof",
            withExtension: "json", subdirectory: "TradingCards/SetPricingAudit"))
        let document = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let entry = try XCTUnwrap((document["cases"] as? [[String: Any]])?.first)
        let source = try JSONDecoder().decode(TCGdexCard.self,
            from: JSONSerialization.data(withJSONObject: XCTUnwrap(entry["source"])))
        let identity = GradedCardIdentity(name: source.name, setName: source.set.name,
            collectorNumber: source.localId, catalogID: source.id, finish: .holo)
        var vendor = try XCTUnwrap(entry["vendor"] as? [String: Any])
        vendor["variants"] = [["id": "retry-slab", "type": "graded", "printing": "Holofoil",
            "grading": ["company": "PSA", "grade": 10],
            "markets": [["region": "NA", "currency": "USD", "price": 50]]]]
        func body() throws -> String {
            String(decoding: try JSONSerialization.data(withJSONObject: ["data": [vendor]]), as: UTF8.self)
        }

        RecordingURLProtocol.reset(status: 503)
        await model.load(identity: identity, game: .pokemon)
        XCTAssertTrue(model.canRetry)
        XCTAssertNotNil(model.errorMessage)
        XCTAssertFalse(model.isLoading)

        RecordingURLProtocol.reset(body: try body())
        async let first: Void = model.load(identity: identity, game: .pokemon)
        async let second: Void = model.load(identity: identity, game: .pokemon)
        _ = await (first, second)
        XCTAssertEqual(model.variants.map(\.id), ["retry-slab"])
        XCTAssertEqual(RecordingURLProtocol.recorded().count, 1, "Overlapping loads share the model's loading guard")
        XCTAssertNil(model.errorMessage)
        XCTAssertFalse(model.canRetry)

        RecordingURLProtocol.reset(headers: ["Link": "<https://justtcg.test/v2/cards?cursor=repeated>; rel=\"next\""])
        await model.load(identity: identity, game: .pokemon)
        XCTAssertTrue(model.canRetry)
        XCTAssertTrue(model.variants.isEmpty)

        vendor["variants"] = []
        RecordingURLProtocol.reset(body: try body())
        await model.load(identity: identity, game: .pokemon)
        XCTAssertFalse(model.canRetry)
        XCTAssertEqual(model.errorMessage, "No graded prices are published for this card yet.")
        RecordingURLProtocol.reset()
        await model.load(identity: identity, game: .pokemon)
        XCTAssertFalse(model.canRetry)
        XCTAssertEqual(model.errorMessage, "Couldn't find this card at the pricing vendor.")

        let canceled = Task { await model.load(identity: identity, game: .pokemon) }
        canceled.cancel()
        await canceled.value
        XCTAssertNil(model.errorMessage)
        XCTAssertFalse(model.canRetry)
        XCTAssertFalse(model.isLoading)
    }

    @MainActor
    func testClassicPikachuHistoryFetchesExactModernProductAndRejectsOtherListings() async throws {
        let suite = "ClassicHistory-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        defer { try? FileManager.default.removeItem(at: root) }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [RecordingURLProtocol.self]
        var settings = JustTCGTransport.Configuration()
        settings.baseURL = URL(string: "https://justtcg.test")!
        settings.minimumRequestInterval = 0
        let service = CardMarketHistoryService(transport: .init(configuration: settings,
            session: URLSession(configuration: config), ledger: .init(defaults: defaults),
            pacer: .init(), apiKeyOverride: "fixture-key"), root: root)
        let card = CollectedCard(collectionKey: "30th-c-014#holo", game: .pokemon, providerID: "30th-c-014",
            name: "Pikachu", setName: "30th Classic Collection", setCode: "30C", cardNumber: "58",
            rarity: nil, imageURL: nil, thumbnailURL: nil, variant: .holo, variantResolution: .userConfirmed)
        card.justTCGVariantID = "stale-listing"
        let request = CardMarketHistoryRequest(card: card)
        let now = Date.now
        var legacy = request
        legacy.exactProductID = nil
        legacy.providerPrinting = nil
        legacy.marketVariantID = "stale-listing"
        legacy.lookups = []
        RecordingURLProtocol.reset(body: #"{"data":[]}"#)
        do {
            _ = try await service.history(for: legacy, now: now)
            XCTFail("Seed the old lookup's cached miss")
        } catch CardMarketHistoryService.HistoryError.noListing { }
        for wrong in [
            #""printing":"Normal","condition":"Near Mint""#,
            #""printing":"Holofoil","condition":"Damaged""#,
            #""printing":"Holofoil","condition":"Near Mint","language":"Japanese""#,
            #""printing":"Holofoil","condition":"Near Mint","currency":"EUR""#,
            #""printing":"Holofoil","condition":"Near Mint","type":"graded""#
        ] {
            RecordingURLProtocol.reset(body: """
            {"data":[{"tcgplayerId":"4240","variants":[{"printing":"Holofoil","condition":"Near Mint","priceHistory":[{"p":999,"t":1700000000}]}]},
            {"tcgplayerId":"716194","variants":[{\(wrong),"priceHistory":[{"p":888,"t":1700000000}]},
            {"printing":"Holofoil","condition":"Near Mint","language":"English","currency":"USD","type":"raw","priceHistory":[{"p":20.09,"t":1700000000},{"p":21,"t":1700100000}]}]}]}
            """)
            let points = try await service.history(for: request, now: now)
            XCTAssertEqual(points.map(\.p), [20.09, 21])
            let query = URLComponents(url: try XCTUnwrap(RecordingURLProtocol.recorded().first),
                resolvingAgainstBaseURL: false)?.queryItems
            XCTAssertEqual(query?.first(where: { $0.name == "tcgplayerId" })?.value, "716194")
            XCTAssertNil(query?.first(where: { $0.name == "variantId" }))
            XCTAssertEqual(query?.first(where: { $0.name == "priceHistoryDuration" })?.value, "1y")
            try? FileManager.default.removeItem(at: root)
        }
        RecordingURLProtocol.reset(body: #"{"data":[{"tcgplayerId":"4240","variants":[{"printing":"Holofoil","condition":"Near Mint","priceHistory":[{"p":999,"t":1700000000}]}]}]}"#)
        do {
            _ = try await service.history(for: request)
            XCTFail("The original Base Set Pikachu must not supply Classic history")
        } catch CardMarketHistoryService.HistoryError.noListing { }

        // An explicitly saved Unlimited marker must not trigger a name search
        // when a reviewed stamped product already fixes the modern release.
        let stamped = try XCTUnwrap(PokemonStampedReleaseCatalog.entries.first)
        card.providerID = stamped.providerID
        card.variantID = stamped.variant.id
        card.pokemonPrintRunRaw = PokemonPrintRun.unlimited.rawValue
        card.tcgplayerProductID = "original-expansion-product"
        RecordingURLProtocol.reset(body: """
        {"data":[{"tcgplayerId":"\(stamped.tcgplayerProductID)","variants":[{"printing":"\(stamped.printing)","condition":"Near Mint","priceHistory":[{"p":1.25,"t":1700000000}]}]}]}
        """)
        let stampedPoints = try await service.history(for: .init(card: card))
        XCTAssertEqual(stampedPoints.map(\.p), [1.25])
        XCTAssertEqual(RecordingURLProtocol.recorded().count, 1, "An exact product needs no search request")
    }

    func testSystematicBundledSetDirectoryConcordance() throws {
        struct Inventory: Decodable {
            struct Group: Decodable { let game, id, name: String }
            let upstreamBuild: String
            let groups: [Group]
        }
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "vendor-groups", withExtension: "json",
            subdirectory: "TradingCards/SetPricingAudit"))
        let inventory = try JSONDecoder().decode(Inventory.self, from: Data(contentsOf: url))
        var requested: [(game: CardGame, id: String, name: String)] = []
        // Count every bundled Browse descriptor, including unresolved ones.
        // This is a set-name concordance audit, not a live JustTCG coverage claim.
        for set in MagicCatalogRegistry.bundledSeed.descriptors where set.browseEnabled {
            requested.append((.magic, set.code, set.displayName))
        }
        let manifestURL = try XCTUnwrap(Bundle.main.url(forResource: "manifest", withExtension: "json",
            subdirectory: "PokemonChecklistSnapshot"))
        let manifest = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL)) as? [String: Any])
        let entries = try XCTUnwrap(manifest["entries"] as? [[String: Any]])
        var seen = Set<String>()
        for entry in entries {
            let id = try XCTUnwrap(entry["providerID"] as? String)
            guard seen.insert(id).inserted else { continue }
            let resource = try XCTUnwrap(entry["resource"] as? String)
            let cards = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf:
                manifestURL.deletingLastPathComponent().appendingPathComponent(resource))) as? [[String: Any]])
            let first = try XCTUnwrap(cards.first)
            var name = try XCTUnwrap(first["setName"] as? String)
            // Snapshot rows decorate Browse titles with their declared print
            // run. Detail pricing receives the underlying TCGdex set name;
            // the print run is supplied independently to the graded client.
            if let set = entry["set"] as? [String: Any], let identity = set["catalogID"] as? [String: Any],
               let raw = identity["pokemonPrintRun"] as? String, let run = PokemonPrintRun(rawValue: raw) {
                let suffix = " — " + run.label
                if name.hasSuffix(suffix) { name.removeLast(suffix.count) }
            }
            requested.append((.pokemon, id, name))
        }
        var rows: [[String: String]] = [], regressions: [String] = []
        for game in [CardGame.pokemon, .magic] {
            let groups = inventory.groups.filter { $0.game == game.rawValue }
            let names = Dictionary(uniqueKeysWithValues: groups.map { ($0.id, $0.name) })
            // Deliberately use opaque TCGplayer IDs here. This proves name
            // resolution without inventing a JustTCG slug from a group name.
            let directory = ProductSetDirectory(sets: groups.map { (id: $0.id, name: Optional($0.name)) })
            let vendorGame: ProductCatalogIdentity.Game = game == .magic ? .magic : .pokemon
            for set in requested.filter({ $0.game == game }).sorted(by: { $0.id < $1.id }) {
                let id = ProductCatalogIdentity.setSlug(setName: set.name, japaneseSetID: nil,
                    game: vendorGame, directory: directory)
                let vendorName = id.flatMap { names[$0] }
                var status = "unresolved"
                if let id, let vendorName {
                    let identity = GradedCardIdentity(name: "Audit card", setName: set.name, collectorNumber: "1")
                    let data = try JSONSerialization.data(withJSONObject: ["name": "Audit card", "number": "1",
                        "game": ["id": vendorGame.rawValue], "set": ["id": id, "name": vendorName]])
                    let card = try JSONDecoder().decode(JustTCGV2Card.self, from: data)
                    status = identity.matches(card, game: game, expectedSetSlug: id) ? "resolved" : "resolvedButRejected"
                    if status == "resolvedButRejected" { regressions.append("\(set.id): \(set.name) → \(vendorName)") }
                }
                rows.append(["game": game.rawValue, "catalogID": set.id, "catalogName": set.name,
                    "vendorGroupID": id ?? "", "vendorName": vendorName ?? "", "status": status])
            }
        }
        let report: [String: Any] = ["schemaVersion": 1, "upstreamBuild": inventory.upstreamBuild,
            "boundary": "Bundled Browse sets against captured TCGplayer group names; unresolved is not proof of vendor absence. No JustTCG slug or graded availability certification.",
            "rows": rows]
        let reportData = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
        let reportURL = FileManager.default.temporaryDirectory.appendingPathComponent("set-pricing-concordance.json")
        try reportData.write(to: reportURL, options: .atomic)
        print("SET_AUDIT_REPORT: \(reportURL.path)")
        let attachment = XCTAttachment(data: reportData, uniformTypeIdentifier: "public.json")
        attachment.name = "set-pricing-concordance.json"
        attachment.lifetime = .keepAlways
        add(attachment)
        let resolvedCount = rows.filter { $0["status"] == "resolved" }.count
        let unresolvedCount = rows.filter { $0["status"] == "unresolved" }.count
        print("SET_AUDIT: \(rows.count) sets, \(resolvedCount) resolved, \(unresolvedCount) unresolved, \(regressions.count) rejected")
        XCTAssertEqual(regressions, [], "A directory-resolved set must not fail graded matching on its display name")
    }

    func testResolvedGradedSetIDSurvivesDisplayAliasesWithoutWeakeningIdentity() throws {
        for (game, catalogID, vendorGame, catalogName, vendorName) in [
            (CardGame.pokemon, "xy6-1", "pokemon", "Roaring Skies", "XY - Roaring Skies"),
            (.magic, "fixture", "magic-the-gathering", "The Big Score", "Outlaws of Thunder Junction: The Big Score"),
            (.pokemon, "SV8a-001", "pokemon-japan", "Terastal Festival ex", "SV8a: Terastal Fest ex")
        ] {
            let identity = GradedCardIdentity(name: "Audit card", setName: catalogName,
                collectorNumber: "001/100", catalogID: catalogID)
            func card(setID: String?, gameID: String?, name: String = "Audit card", number: String = "1/100") throws -> JustTCGV2Card {
                var set: [String: String] = ["name": vendorName]
                if let setID { set["id"] = setID }
                var object: [String: Any] = ["name": name, "number": number, "set": set]
                if let gameID { object["game"] = ["id": gameID] }
                return try JSONDecoder().decode(JustTCGV2Card.self, from: JSONSerialization.data(withJSONObject: object))
            }
            XCTAssertTrue(identity.matches(try card(setID: "reviewed-set", gameID: vendorGame),
                game: game, expectedSetSlug: "reviewed-set"), catalogName)
            for wrong in [
                try card(setID: "other-set", gameID: vendorGame),
                try card(setID: nil, gameID: vendorGame),
                try card(setID: "reviewed-set", gameID: "other-game"),
                try card(setID: "reviewed-set", gameID: nil),
                try card(setID: "reviewed-set", gameID: vendorGame, name: "Unrelated card"),
                try card(setID: "reviewed-set", gameID: vendorGame, number: "2/100"),
                try card(setID: "reviewed-set", gameID: vendorGame, number: "1/101")
            ] {
                XCTAssertFalse(identity.matches(wrong, game: game, expectedSetSlug: "reviewed-set"), catalogName)
            }
            XCTAssertFalse(identity.matches(try card(setID: "reviewed-set", gameID: vendorGame), game: game),
                "An unresolved fallback still requires a matching display set")
        }
    }

    func testKnownJapaneseGradedFinishUsesTrustedCatalogLanguage() throws {
        for (catalogID, printing, gameID, accepted) in [
            ("M2-001", "Holofoil - Japanese", "pokemon-japan", true),
            ("M2-001", "Normal - Japanese", "pokemon-japan", false),
            ("M2-001", "Holofoil", "pokemon-japan", false),
            ("M2-001", "Holofoil - Japanese", "pokemon", false),
            ("ex7-78", "Holofoil", "pokemon", true),
            ("ex7-78", "Holofoil - Japanese", "pokemon", false)
        ] {
            let card = try JSONDecoder().decode(JustTCGCard.self, from: Data("""
                {"id":"fixture","name":"Imported","number":"1","game":"\(gameID)",
                 "set_name":"Fixture Set","variants":[{"id":"graded","type":"graded",
                 "printing":"\(printing)","grading":{"company":"CGC","grade":10}}]}
                """.utf8))
            let identity = GradedCardIdentity(name: "Imported", setName: "Fixture Set", collectorNumber: "1",
                catalogID: catalogID, finish: .holo)
            XCTAssertEqual(identity.matches(card, variant: try XCTUnwrap(card.variants?.first), game: .pokemon), accepted)
        }
    }

    @MainActor
    func testHistoryCancelsOnlyWhenItsLastConsumerLeaves() async throws {
        for keepSecondConsumer in [false, true] {
            let suite = "HistoryConsumers-\(UUID().uuidString)"
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
            defer { try? FileManager.default.removeItem(at: root) }
            let config = URLSessionConfiguration.ephemeral
            config.protocolClasses = [RecordingURLProtocol.self]
            let pacer = JustTCGPacer()
            try await pacer.wait(lane: .interactive, minimumInterval: 0)
            var settings = JustTCGTransport.Configuration()
            settings.baseURL = URL(string: "https://justtcg.test")!
            settings.minimumRequestInterval = 0.5
            let transport = JustTCGTransport(configuration: settings,
                session: URLSession(configuration: config), ledger: .init(defaults: defaults),
                pacer: pacer, apiKeyOverride: "fixture-key")
            let service = CardMarketHistoryService(transport: transport, root: root)
            let card = CollectedCard(collectionKey: "history-test", game: .magic, providerID: "test-printing",
                name: "Test", setName: "Test", setCode: "tst", cardNumber: "1",
                rarity: nil, imageURL: nil, thumbnailURL: nil, variant: .nonfoil,
                variantResolution: .userConfirmed)
            card.justTCGVariantID = "normal-nm"
            let request = CardMarketHistoryRequest(card: card)
            RecordingURLProtocol.reset(body: #"{"data":[{"variants":[{"uuid":"normal-nm","printing":"Normal","priceHistory":[{"p":20,"t":1700000000}]}]}]}"#)
            let first = Task { try await service.history(for: request) }
            let second = Task { try await service.history(for: request) }
            try await Task.sleep(for: .milliseconds(50))
            first.cancel()
            if !keepSecondConsumer { second.cancel() }
            switch await first.result {
            case .success: XCTFail("A cancelled consumer must not publish history")
            case let .failure(error): XCTAssertTrue(error is CancellationError)
            }
            if keepSecondConsumer {
                let points = try await second.value
                XCTAssertEqual(points.map(\.p), [20])
                XCTAssertEqual(RecordingURLProtocol.recorded().count, 1)
            } else {
                switch await second.result {
                case .success: XCTFail("The last cancelled consumer must not publish history")
                case let .failure(error): XCTAssertTrue(error is CancellationError)
                }
                XCTAssertTrue(RecordingURLProtocol.recorded().isEmpty)
                let snapshot = await transport.snapshot()
                XCTAssertEqual(snapshot.usedToday, 0)
                let cached = await service.cached(request)
                XCTAssertTrue(cached.isEmpty)
                // The cancelled task must not remain attached to a new visit.
                let retried = try await service.history(for: request)
                XCTAssertEqual(retried.map(\.p), [20])
                XCTAssertEqual(RecordingURLProtocol.recorded().count, 1)
            }
        }
    }

    @MainActor
    func testDetailFetchesFullProviderHistoryAndCachesItWithoutOwnershipCutoff() async throws {
        let suite = "MarketHistory-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        defer { try? FileManager.default.removeItem(at: root) }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [RecordingURLProtocol.self]
        var settings = JustTCGTransport.Configuration()
        settings.baseURL = URL(string: "https://justtcg.test")!
        settings.minimumRequestInterval = 0
        let service = CardMarketHistoryService(transport: .init(configuration: settings,
            session: URLSession(configuration: config), ledger: .init(defaults: defaults),
            pacer: .init(), apiKeyOverride: "fixture-key"), root: root)
        let card = CollectedCard(collectionKey: "history-test", game: .magic, providerID: "test-printing",
                                 name: "Test", setName: "Test", setCode: "tst", cardNumber: "1",
                                 rarity: nil, imageURL: nil, thumbnailURL: nil, variant: .nonfoil,
                                 variantResolution: .userConfirmed)
        card.justTCGVariantID = "normal-nm"
        card.dateAdded = .now
        let request = CardMarketHistoryRequest(card: card)
        RecordingURLProtocol.reset(body: #"{"data":[{"tcgplayerId":"12345","variants":[{"uuid":"foil-nm","printing":"Foil","priceHistory":[{"p":900,"t":1700000000}]},{"uuid":"normal-nm","printing":"Normal","priceHistory":[{"p":25,"t":1700200000},{"p":20,"t":1700000000},{"p":-1,"t":1700300000},{"p":22,"t":1700200000},{"p":999,"t":9999999999}]}]}]}"#)
        let points = try await service.history(for: request)
        XCTAssertEqual(points.map(\.p), [20, 22])
        XCTAssertTrue(points.allSatisfy { Date(timeIntervalSince1970: $0.t) < card.dateAdded })
        let url = try XCTUnwrap(RecordingURLProtocol.recorded().first)
        let query = Dictionary(uniqueKeysWithValues: URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!.map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(query["variantId"], "normal-nm")
        XCTAssertEqual(query["include_price_history"], "true")
        XCTAssertEqual(query["priceHistoryDuration"], "1y")
        XCTAssertNil(query["updated_after"])
        let repeated = try await service.history(for: request)
        XCTAssertEqual(repeated, points)
        XCTAssertEqual(RecordingURLProtocol.recorded().count, 1)

        // A later rolling window must retain older downloaded points for ALL.
        RecordingURLProtocol.reset(body: #"{"data":[{"tcgplayerId":"12345","variants":[{"uuid":"normal-nm","priceHistory":[{"p":24,"t":1700400000}]}]}]}"#)
        let later = Date.now.addingTimeInterval(7 * 3600)
        async let first = service.history(for: request, now: later)
        async let second = service.history(for: request, now: later)
        let (merged, parallel) = try await (first, second)
        XCTAssertEqual(merged.map(\.p), [20, 22, 24])
        XCTAssertEqual(parallel, merged, "Concurrent callers must receive the complete merged history")
        XCTAssertEqual(RecordingURLProtocol.recorded().count, 1)
        card.justTCGVariantID = "newly-resolved-handle"
        let retained = await service.cached(CardMarketHistoryRequest(card: card))
        XCTAssertEqual(retained, merged, "Resolving a vendor handle must not discard earlier history")
        card.justTCGVariantID = "foil-nm"
        card.variantID = PhysicalVariant.foil.id
        let otherFinish = await service.cached(CardMarketHistoryRequest(card: card))
        XCTAssertTrue(otherFinish.isEmpty)
        card.variantID = PhysicalVariant.nonfoil.id
        let restoredFinish = await service.cached(CardMarketHistoryRequest(card: card))
        XCTAssertEqual(restoredFinish, merged)
        card.game = CardGame.pokemon.rawValue
        let otherGame = await service.cached(CardMarketHistoryRequest(card: card))
        XCTAssertTrue(otherGame.isEmpty, "Physical identifiers do not share history across games")

        card.game = CardGame.magic.rawValue
        card.tcgplayerProductID = "12345"
        let reopened = CardMarketHistoryService(transport: .init(configuration: settings,
            session: URLSession(configuration: config), ledger: .init(defaults: defaults),
            pacer: .init(), apiKeyOverride: "fixture-key"), root: root)
        let reboundRequest = CardMarketHistoryRequest(card: card)
        let rebound = await reopened.cached(reboundRequest)
        XCTAssertEqual(rebound, merged, "Binding the product the provider returned must recover this printing's saved history across launches")
        let reused = try await reopened.history(for: reboundRequest, now: later)
        XCTAssertEqual(reused, merged)
        XCTAssertEqual(RecordingURLProtocol.recorded().count, 1, "A fresh recovered cache must not fetch again")
        card.tcgplayerProductID = "67890"
        let changedProduct = await reopened.cached(CardMarketHistoryRequest(card: card))
        XCTAssertTrue(changedProduct.isEmpty, "A product correction must not inherit the earlier product's history")

        RecordingURLProtocol.reset(status: 403)
        do {
            _ = try await reopened.history(for: reboundRequest, now: later.addingTimeInterval(7 * 3600))
            XCTFail("The failed refresh should throw")
        } catch { }
        let afterFailure = await reopened.cached(reboundRequest)
        XCTAssertEqual(afterFailure, merged, "A failed refresh must preserve the complete saved series")
    }

    /// A provider answer of "no matching listing" is remembered for a bounded
    /// interval, so reopening the card does not spend shared daily quota again.
    @MainActor
    func testProviderNoListingIsNotRequestedAgainUntilItsRetryInterval() async throws {
        let suite = "MarketHistoryMiss-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        defer { try? FileManager.default.removeItem(at: root) }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [RecordingURLProtocol.self]
        var settings = JustTCGTransport.Configuration()
        settings.baseURL = URL(string: "https://justtcg.test")!
        settings.minimumRequestInterval = 0
        func makeService() -> CardMarketHistoryService {
            CardMarketHistoryService(transport: .init(configuration: settings,
                session: URLSession(configuration: config), ledger: .init(defaults: defaults),
                pacer: .init(), apiKeyOverride: "fixture-key"), root: root)
        }
        let service = makeService()
        let card = CollectedCard(collectionKey: "history-miss", game: .magic, providerID: "history-miss",
                                 name: "Test", setName: "Test", setCode: "tst", cardNumber: "1",
                                 rarity: nil, imageURL: nil, thumbnailURL: nil, variant: .nonfoil,
                                 variantResolution: .userConfirmed)
        card.justTCGVariantID = "missing-normal"
        let request = CardMarketHistoryRequest(card: card)
        let now = Date.now
        // The provider answers, but not with the requested listing.
        let miss = #"{"data":[{"tcgplayerId":"12345","variants":[{"uuid":"other-foil","printing":"Foil","condition":"Near Mint","priceHistory":[{"p":90,"t":1700000000}]}]}]}"#
        func expectNoListing(_ service: CardMarketHistoryService, _ request: CardMarketHistoryRequest,
                             at date: Date, _ message: String) async {
            do {
                _ = try await service.history(for: request, now: date)
                XCTFail("\(message): expected no listing")
            } catch CardMarketHistoryService.HistoryError.noListing {
            } catch { XCTFail("\(message): \(error)") }
        }

        RecordingURLProtocol.reset(body: miss)
        await expectNoListing(service, request, at: now, "first open")
        XCTAssertEqual(RecordingURLProtocol.recorded().count, 1)
        await expectNoListing(service, request, at: now.addingTimeInterval(3600), "reopen")
        await expectNoListing(makeService(), request, at: now.addingTimeInterval(7 * 3600), "relaunch")
        XCTAssertEqual(RecordingURLProtocol.recorded().count, 1, "A recent provider miss must not spend another request")

        // A newly bound vendor listing is new input and is requested at once.
        card.justTCGVariantID = "bound-normal"
        let rebound = CardMarketHistoryRequest(card: card)
        RecordingURLProtocol.reset(body: #"{"data":[{"tcgplayerId":"12345","variants":[{"uuid":"bound-normal","printing":"Normal","condition":"Near Mint","priceHistory":[{"p":20,"t":1700000000}]}]}]}"#)
        let found = try await service.history(for: rebound, now: now.addingTimeInterval(7 * 3600))
        XCTAssertEqual(found.map(\.p), [20])
        XCTAssertEqual(RecordingURLProtocol.recorded().count, 1, "Changed lookup input must not wait out the miss")

        // A listing that later disappears keeps its saved series without
        // asking again until the retry interval passes.
        RecordingURLProtocol.reset(body: miss)
        card.justTCGVariantID = "bound-normal"
        await expectNoListing(service, rebound, at: now.addingTimeInterval(14 * 3600), "withdrawn listing")
        await expectNoListing(service, rebound, at: now.addingTimeInterval(15 * 3600), "withdrawn reopen")
        XCTAssertEqual(RecordingURLProtocol.recorded().count, 1)
        let retained = await service.cached(rebound)
        XCTAssertEqual(retained.map(\.p), [20], "A provider miss must not discard saved history")

        await expectNoListing(service, rebound, at: now.addingTimeInterval(39 * 3600), "after retry interval")
        XCTAssertEqual(RecordingURLProtocol.recorded().count, 2, "An expired miss asks the provider again")
    }

    /// An unbound lookup records which product it actually resolved. A later
    /// exact binding to a different product must neither adopt nor merge it.
    @MainActor
    func testFirstExactBindingNeverAdoptsAnotherProductsHistory() async throws {
        let suite = "MarketHistoryBinding-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        defer { try? FileManager.default.removeItem(at: root) }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [RecordingURLProtocol.self]
        var settings = JustTCGTransport.Configuration()
        settings.baseURL = URL(string: "https://justtcg.test")!
        settings.minimumRequestInterval = 0
        func makeService() -> CardMarketHistoryService {
            CardMarketHistoryService(transport: .init(configuration: settings,
                session: URLSession(configuration: config), ledger: .init(defaults: defaults),
                pacer: .init(), apiKeyOverride: "fixture-key"), root: root)
        }
        func cacheFile(for request: CardMarketHistoryRequest) throws -> URL {
            let identity = try JSONEncoder().encode(request.historyIdentity).base64EncodedString()
            return try XCTUnwrap(FileManager.default.contentsOfDirectory(at: root,
                includingPropertiesForKeys: nil).first { url in
                let entry = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
                return entry?["requestData"] as? String == identity
            })
        }
        let now = Date.now
        let later = now.addingTimeInterval(7 * 3600)
        let cases: [(String, CardGame, String?)] = [
            ("first-binding-magic", .magic, "11111"),
            ("first-binding-pokemon", .pokemon, "11111"),
            ("missing-provenance", .magic, nil),
            ("legacy-on-disk", .magic, "11111")
        ]

        for (key, game, productA) in cases {
            let service = makeService()
            let card = CollectedCard(collectionKey: key, game: game, providerID: key,
                                     name: "Test", setName: "Test", setCode: "tst", cardNumber: "1",
                                     rarity: nil, imageURL: nil, thumbnailURL: nil, variant: .nonfoil,
                                     variantResolution: .userConfirmed)
            card.quantity = 3
            card.dateAdded = now
            // The unbound lookup resolves product A's Normal listing.
            card.justTCGVariantID = "\(key)-a-normal"
            let unbound = CardMarketHistoryRequest(card: card)
            let productField = productA.map { #""tcgplayerId":"\#($0)","# } ?? ""
            RecordingURLProtocol.reset(body: #"{"data":[{\#(productField)"variants":[{"uuid":"\#(key)-a-normal","printing":"Normal","condition":"Near Mint","priceHistory":[{"p":10,"t":1700000000},{"p":11,"t":1700100000}]}]}]}"#)
            let pointsA = try await service.history(for: unbound, now: now)
            XCTAssertEqual(pointsA, [.init(p: 10, t: 1700000000), .init(p: 11, t: 1700100000)], key)
            let fileA = try cacheFile(for: unbound)
            if key == "legacy-on-disk" {
                // Exercise decoding an actual pre-provenance disk entry.
                var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: fileA)) as? [String: Any])
                legacy.removeValue(forKey: "sourceProductID")
                try JSONSerialization.data(withJSONObject: legacy).write(to: fileA, options: .atomic)
            }
            let savedFiles = try Dictionary(uniqueKeysWithValues:
                FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
                    .map { ($0, try Data(contentsOf: $0)) })
            let reopened = makeService()
            if let productA, key != "legacy-on-disk" {
                var matching = unbound
                matching.exactProductID = productA
                let reusedA = try await reopened.history(for: matching, now: now)
                XCTAssertEqual(reusedA, pointsA, "\(key): trustworthy matching provenance permits reuse")
                XCTAssertEqual(RecordingURLProtocol.recorded().count, 1, "\(key): reuse must not fetch again")
            }

            // A correction binds the same local printing/finish to product B.
            card.tcgplayerProductID = "22222"
            card.justTCGVariantID = "\(key)-b-normal"
            let bound = CardMarketHistoryRequest(card: card)
            XCTAssertEqual(bound.exactProductID, "22222")
            XCTAssertEqual(bound.printingID, unbound.printingID)
            XCTAssertEqual(bound.variantID, unbound.variantID)
            let cachedB = await reopened.cached(bound)
            XCTAssertTrue(cachedB.isEmpty, "\(key): product B must not display product A's saved history")

            RecordingURLProtocol.reset(status: 403)
            do {
                _ = try await reopened.history(for: bound, now: now)
                XCTFail("\(key): a failed B refresh must not return A's or unverified history")
            } catch JustTCGTransport.TransportError.badResponse(let status) {
                XCTAssertEqual(status, 403)
            }
            let afterFailure = await makeService().cached(bound)
            XCTAssertTrue(afterFailure.isEmpty, "\(key): failure must not persist history under B")
            XCTAssertEqual(RecordingURLProtocol.recorded().count, 1)

            RecordingURLProtocol.reset(body: #"{"data":[{"tcgplayerId":"22222","variants":[{"uuid":"\#(key)-b-normal","printing":"Normal","condition":"Near Mint","priceHistory":[{"p":50,"t":1700200000}]}]}]}"#)
            let pointsB = try await reopened.history(for: bound, now: now)
            XCTAssertEqual(pointsB, [.init(p: 50, t: 1700200000)], "\(key): a fresh exact fetch must not merge product A's points")
            XCTAssertEqual(RecordingURLProtocol.recorded().count, 1, "\(key): product B must fetch its own history")
            let query = URLComponents(url: try XCTUnwrap(RecordingURLProtocol.recorded().first),
                resolvingAgainstBaseURL: false)?.queryItems
            XCTAssertEqual(query?.first(where: { $0.name == "variantId" })?.value, "\(key)-b-normal")

            RecordingURLProtocol.reset(body: #"{"data":[{"tcgplayerId":"22222","variants":[{"uuid":"\#(key)-b-normal","printing":"Normal","condition":"Near Mint","priceHistory":[{"p":51,"t":1700300000}]}]}]}"#)
            let refreshedB = try await makeService().history(for: bound, now: later)
            XCTAssertEqual(refreshedB, [.init(p: 50, t: 1700200000), .init(p: 51, t: 1700300000)],
                "\(key): B retains only its own rolling history")
            let restoredB = try await makeService().history(for: bound, now: later)
            XCTAssertEqual(restoredB, refreshedB)
            XCTAssertEqual(RecordingURLProtocol.recorded().count, 1, "\(key): reloaded B history must be reused")
            let persistedB = try XCTUnwrap(JSONSerialization.jsonObject(with:
                Data(contentsOf: cacheFile(for: bound))) as? [String: Any])
            XCTAssertEqual(persistedB["sourceProductID"] as? String, "22222")

            // Product A's series stays under its original unbound identity.
            card.tcgplayerProductID = nil
            card.justTCGVariantID = "\(key)-a-normal"
            let retainedA = await makeService().cached(CardMarketHistoryRequest(card: card))
            XCTAssertEqual(retainedA, pointsA, "\(key): the unbound history is retained, not relabelled")
            for (url, data) in savedFiles {
                XCTAssertEqual(try Data(contentsOf: url), data, "\(key): existing cache entries must remain unchanged")
            }
            XCTAssertEqual(card.quantity, 3)
            XCTAssertEqual(card.dateAdded, now)
            XCTAssertEqual(card.collectionKey, key)
        }
    }

    @MainActor
    func testOnePieceSealedHistoryUsesExactVariantAndReusesPersistedCache() async throws {
        try await assertSealedHistory(game: .onePiece)
    }

    @MainActor
    func testLorcanaSealedHistoryUsesExactVariantAndReusesPersistedCache() async throws {
        try await assertSealedHistory(game: .lorcana)
    }

    @MainActor
    private func assertSealedHistory(game: CardGame) async throws {
        let suite = "SealedHistory-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        defer { try? FileManager.default.removeItem(at: root) }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [RecordingURLProtocol.self]
        var settings = JustTCGTransport.Configuration()
        settings.baseURL = URL(string: "https://justtcg.test")!
        settings.minimumRequestInterval = 0
        let transport = JustTCGTransport(configuration: settings,
            session: URLSession(configuration: config), ledger: .init(defaults: defaults),
            pacer: .init(), apiKeyOverride: "fixture-key")
        let service = CardMarketHistoryService(transport: transport, root: root)
        let card = CollectedCard(collectionKey: "sealed-history", game: game, providerID: "sealed-history",
            name: "Fixture Booster Box", setName: "Fixture Set", setCode: "", cardNumber: "",
            rarity: nil, imageURL: nil, thumbnailURL: nil, variant: nil, variantResolution: .userConfirmed)
        // Match the vendor identities persisted by CollectionStore.addSealed.
        card.itemKindRaw = CollectionItemKind.sealedProduct.rawValue
        card.catalogProviderID = "vendor-box"
        card.justTCGCardID = "vendor-box"
        card.justTCGVariantID = "vendor-exact"
        card.tcgplayerProductID = "12345"
        let request = CardMarketHistoryRequest(card: card)
        let resolved = await request.resolvingMarketMapping(in: nil)
        XCTAssertEqual(resolved, request, "Sealed listings do not require a raw-printing UUID")
        RecordingURLProtocol.reset(body: #"{"data":[{"uuid":"vendor-box","tcgplayerId":"12345","variants":[{"uuid":"raw","condition":"Near Mint","priceHistory":[{"p":1,"t":1700000000}]},{"uuid":"vendor-other","condition":"Sealed","priceHistory":[{"p":999,"t":1700000000}]},{"uuid":"vendor-exact","condition":"Sealed","priceHistory":[{"p":99,"t":1700000000}]}]}]}"#)
        let points = try await service.history(for: request)
        XCTAssertEqual(points.map(\.p), [99])
        let url = try XCTUnwrap(RecordingURLProtocol.recorded().first)
        let query = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        XCTAssertEqual(query.first(where: { $0.name == "variantId" })?.value, "vendor-exact")
        XCTAssertEqual(query.first(where: { $0.name == "include_price_history" })?.value, "true")
        XCTAssertEqual(query.first(where: { $0.name == "priceHistoryDuration" })?.value, "1y")
        let reopened = CardMarketHistoryService(transport: transport, root: root)
        let cached = await reopened.cached(request)
        XCTAssertEqual(cached, points)
        let reused = try await reopened.history(for: request)
        XCTAssertEqual(reused, points)
        XCTAssertEqual(RecordingURLProtocol.recorded().count, 1, "Fresh disk cache avoids another provider request")
        card.justTCGVariantID = "vendor-other"
        let differentListing = await reopened.cached(.init(card: card))
        XCTAssertTrue(differentListing.isEmpty, "A different exact sealed listing cannot reuse the old series")
    }

    @MainActor
    func testGradedHistoryUsesV2ExactVariantAndUSDMarket() async throws {
        let suite = "GradedHistory-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        defer { try? FileManager.default.removeItem(at: root) }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [RecordingURLProtocol.self]
        var settings = JustTCGTransport.Configuration()
        settings.baseURL = URL(string: "https://justtcg.test")!
        settings.minimumRequestInterval = 0
        let service = CardMarketHistoryService(transport: .init(configuration: settings,
            session: URLSession(configuration: config), ledger: .init(defaults: defaults),
            pacer: .init(), apiKeyOverride: "fixture-key"), root: root)
        let card = CollectedCard(collectionKey: "graded-history-test", game: .pokemon,
            providerID: "test-printing", name: "Test", setName: "Test", setCode: "tst", cardNumber: "1",
            rarity: nil, imageURL: nil, thumbnailURL: nil, variant: .holo, variantResolution: .userConfirmed)
        card.itemKindRaw = CollectionItemKind.gradedCard.rawValue
        card.justTCGVariantID = "psa10"
        RecordingURLProtocol.reset(body: #"{"data":[{"id":"card","variants":[{"id":"psa9","type":"graded","markets":[{"currency":"USD","price_history":[{"t":1700000000,"p":50}]}]},{"id":"psa10","type":"graded","markets":[{"currency":"EUR","price_history":[{"t":1700000000,"p":90}]},{"currency":"USD","price_history":[{"t":1700000000,"p":100}]}]}]}]}"#)
        let points = try await service.history(for: .init(card: card))
        XCTAssertEqual(points.map(\.p), [100])
        let url = try XCTUnwrap(RecordingURLProtocol.recorded().first)
        XCTAssertEqual(url.path, "/v2/cards")
        let query = Dictionary(uniqueKeysWithValues: URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!.map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(query["variant_id"], "psa10")
        XCTAssertEqual(query["include"], "price_history.1y")
        XCTAssertEqual(query["regions"], "NA")
        card.justTCGVariantID = "psa9"
        let otherGrade = await service.cached(.init(card: card))
        XCTAssertTrue(otherGrade.isEmpty)
    }

    func testProviderHistoryDecodesBothSchemasWithoutRelabelingForeignCurrency() throws {
        let v1 = try JSONDecoder().decode(JustTCGVariant.self, from: Data(#"{"currency":"EUR","priceHistory":[{"t":1700000000,"p":15}]}"#.utf8))
        XCTAssertTrue(v1.historyUSD.isEmpty)
        let v2 = try JSONDecoder().decode(JustTCGVariant.self, from: Data(#"{"markets":[{"currency":"EUR","price_history":[{"t":1700000000,"p":15}]},{"currency":"USD","price_history":[{"t":1700000000,"p":20}]}]}"#.utf8))
        XCTAssertEqual(v2.historyUSD.map(\.p), [20])
    }

    func testOnePieceSealedWireParametersAndPaginationUseVendorIdentities() async throws {
        let suite = "OnePieceSealedWire-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [RecordingURLProtocol.self]
        var settings = JustTCGTransport.Configuration()
        settings.baseURL = URL(string: "https://justtcg.test")!
        settings.minimumRequestInterval = 0
        let client = JustTCGV1Client(transport: .init(configuration: settings, session: URLSession(configuration: config),
            ledger: .init(defaults: defaults), pacer: .init(), apiKeyOverride: "fixture-key"))
        RecordingURLProtocol.reset(body: #"{"data":[{"uuid":"vendor-box","name":"Booster box","tcgplayerId":"12345","variants":[{"uuid":"vendor-sealed","condition":"Sealed","price":99.25},{"uuid":"raw","condition":"Near Mint","price":1}]}],"meta":{"total":101,"offset":100,"limit":100,"hasMore":false}}"#)
        let page = try await client.searchSealedProducts(game: .onePiece, setID: "vendor-op-set", query: "box", offset: 100)
        let url = try XCTUnwrap(RecordingURLProtocol.recorded().first)
        let query = Dictionary(uniqueKeysWithValues: try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems).map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(query["game"], "one-piece-card-game")
        XCTAssertEqual(query["condition"], "Sealed")
        XCTAssertEqual(query["set"], "vendor-op-set")
        XCTAssertEqual(query["offset"], "100")
        XCTAssertEqual(query["q"], "box")
        XCTAssertEqual(page.items.first?.id, "vendor-box")
        XCTAssertEqual(page.items.first?.variantID, "vendor-sealed")
        XCTAssertEqual(page.items.first?.marketPriceUSD, 99.25)
        XCTAssertFalse(page.hasMore)
        let lorcanaSets = try await client.sealedSets(game: .lorcana)
        XCTAssertEqual(lorcanaSets.reduce(0) { $0 + $1.sealedCount }, 177)
        XCTAssertEqual(RecordingURLProtocol.recorded().count, 1,
                       "Bundled Lorcana discovery must not use JustTCG transport")
        do { _ = try await client.sealedSets(game: CardGame(rawValue: "future-unsupported-game")); XCTFail("Unsupported game must fail before transport") }
        catch is CardGameSupportError { }
        XCTAssertEqual(RecordingURLProtocol.recorded().count, 1)
        let stoppedLedger = JustTCGRequestLedger(defaults: defaults)
        stoppedLedger.recordRateLimit(until: .now.addingTimeInterval(60))
        let stopped = JustTCGV1Client(transport: .init(configuration: settings, session: URLSession(configuration: config),
            ledger: stoppedLedger, pacer: .init(), apiKeyOverride: "fixture-key"))
        do { _ = try await stopped.searchSealedProducts(game: .onePiece, offset: 0); XCTFail("Rate limit must stop discovery") }
        catch JustTCGTransport.TransportError.rateLimited { }
        XCTAssertEqual(RecordingURLProtocol.recorded().count, 1, "Paused requests must not reach the provider")
    }

    func testMarketplaceArtworkUsesTheCanonicalProductCDN() {
        XCTAssertEqual(
            JustTCGV1Client.productImageURL(tcgplayerID: "515661")?.absoluteString,
            "https://tcgplayer-cdn.tcgplayer.com/product/515661_400w.jpg"
        )
        XCTAssertNil(JustTCGV1Client.productImageURL(tcgplayerID: "  "))
        XCTAssertEqual(
            JustTCGV1Client.migratedProductImageURL(
                from: "https://product-images.tcgplayer.com/fit-in/1000x1000/515661.jpg"
            )?.absoluteString,
            "https://tcgplayer-cdn.tcgplayer.com/product/515661_400w.jpg"
        )
    }


    // MARK: - Batch request encoding

    /// Each item carries exactly one identifier. The enum makes two impossible,
    /// but the *encoding* has to prove it too.
    func testEachBatchItemEncodesExactlyOneIdentifier() throws {
        let items: [JustTCGBatchLookup] = [
            .variantID("v-1"),
            .tcgplayerID("12345"),
            .scryfallID("abc-def")
        ]
        let data = try JSONEncoder().encode(
            JustTCGBatchRequest(items: items, includePriceHistory: false, updatedAfter: nil)
        )
        let decoded = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [[String: String]]
        )

        XCTAssertEqual(decoded.count, 3)
        for object in decoded {
            XCTAssertEqual(object.count, 1, "one identifier per item: \(object)")
        }
        // The *request* key is `variantId`, even though the *response* field
        // carrying the same value is `uuid`. The asymmetry is the vendor's, and
        // conflating the two is what made the first contract run send nothing.
        XCTAssertEqual(decoded[0], ["variantId": "v-1"])
        XCTAssertEqual(decoded[1], ["tcgplayerId": "12345"])
        XCTAssertEqual(decoded[2], ["scryfallId": "abc-def"])
    }

    /// The vendor's documented precedence, fastest first.
    func testIdentifierPrecedenceFollowsTheVendorOrder() {
        let ordered: [JustTCGBatchLookup] = [
            .variantID("a"), .tcgplayerSKUID("b"), .tcgplayerID("c"),
            .mtgjsonID("d"), .scryfallID("e"), .cardID("f")
        ]
        XCTAssertEqual(ordered.map(\.precedence), [0, 1, 2, 3, 4, 5])

        // Given a choice, the variant id always wins: it is the only identifier
        // at the same granularity the app prices at.
        let best = JustTCGBatchLookup.best(from: [
            .cardID("f"), .scryfallID("e"), .variantID("a")
        ])
        XCTAssertEqual(best, .variantID("a"))
    }

    /// Routine collection pricing must never ask for history — it is an order of
    /// magnitude more data for a number the collection does not show.
    func testRoutineRefreshNeverRequestsHistory() {
        let request = JustTCGBatchRequest(
            items: [.variantID("v-1")],
            includePriceHistory: false,
            updatedAfter: nil
        )
        let query = Dictionary(uniqueKeysWithValues: request.queryItems)

        XCTAssertEqual(query["include_price_history"], "false")
        XCTAssertNil(query["updated_after"])
    }

    func testDeltaCutoffIsSentAsUnixSeconds() {
        let cutoff = Date(timeIntervalSince1970: 1_700_000_000)
        let request = JustTCGBatchRequest(
            items: [.variantID("v-1")],
            includePriceHistory: false,
            updatedAfter: cutoff
        )
        let query = Dictionary(uniqueKeysWithValues: request.queryItems)

        XCTAssertEqual(query["updated_after"], "1700000000")
    }

    /// Pinned from a live response.
    ///
    /// The request *parameter* is called `variantId`; the response *field* is
    /// called `uuid`. Decoding the parameter name finds nothing, which is
    /// exactly what happened on the first contract run — every batch would have
    /// had nothing to send.
    func testVariantIdentifierComesFromUUIDNotVariantId() throws {
        let json = """
        { "data": [ { "id": "card-slug", "uuid": "card-uuid", "variants": [
            { "id": "variant-slug", "uuid": "variant-uuid",
              "condition": "Near Mint", "printing": "Holofoil", "price": 106.39,
              "tcgplayerSkuId": "1247795" } ] } ] }
        """
        let response = try JSONDecoder().decode(
            JustTCGBatchResponse.self, from: Data(json.utf8)
        )
        let variant = try XCTUnwrap(response.data.first?.variants?.first)

        XCTAssertEqual(variant.uuid, "variant-uuid")
        XCTAssertEqual(variant.variantId, "variant-uuid", "the UUID is what batches send")
        XCTAssertEqual(variant.tcgplayerSkuId, "1247795")
        XCTAssertNotNil(response.variantsByID["variant-uuid"])
    }

    /// Sealed products carry the literal string `N/A` as their number. Treating
    /// that as a collector number would make every sealed product compare equal.
    func testSealedProductNumberNAIsNotACollectorNumber() throws {
        let json = """
        { "data": [ { "id": "box", "uuid": "box-uuid", "number": "N/A",
            "set_name": "Legendary Treasures", "variants": [] } ] }
        """
        let card = try XCTUnwrap(
            JSONDecoder().decode(JustTCGBatchResponse.self, from: Data(json.utf8)).data.first
        )

        XCTAssertNil(card.printedNumber)
        XCTAssertEqual(card.setName, "Legendary Treasures")
    }

    // MARK: - Response correlation

    private let batchFixture = """
    { "data": [
      { "id": "card-1", "name": "Trevenant", "set": "trick-or-trade-2023",
        "number": "017/196",
        "variants": [
          { "uuid": "v-nm-holo", "condition": "Near Mint",
            "printing": "Holofoil", "price": 0.16, "lastUpdated": 1700000000 },
          { "uuid": "v-hp-holo", "condition": "Heavily Played",
            "printing": "Holofoil", "price": 0.35 }
        ] },
      { "id": "card-2", "name": "Legendary Treasures Booster Box",
        "set": "legendary-treasures",
        "variants": [
          { "uuid": "v-sealed", "condition": "Sealed", "price": 184.99 }
        ] }
    ] }
    """

    /// Correlation is by identifier, never by array position — the vendor is not
    /// obliged to preserve request order, and matching by index would attach one
    /// card's price to another.
    func testVariantsAreCorrelatedByIDNotPosition() throws {
        let response = try JSONDecoder().decode(
            JustTCGBatchResponse.self, from: Data(batchFixture.utf8)
        )
        let byID = response.variantsByID

        XCTAssertEqual(byID["v-nm-holo"]?.variant.price, 0.16)
        XCTAssertEqual(byID["v-hp-holo"]?.variant.price, 0.35)
        XCTAssertEqual(byID["v-nm-holo"]?.card.name, "Trevenant")
        XCTAssertNil(byID["not-requested"])
    }

    /// Sealed products live in the same `/cards` dataset, distinguished by the
    /// condition. That is what lets one batch path price a booster box and a
    /// single with the same code.
    func testSealedProductsAreIdentifiedByCondition() throws {
        let response = try JSONDecoder().decode(
            JustTCGBatchResponse.self, from: Data(batchFixture.utf8)
        )
        let sealed = try XCTUnwrap(response.variantsByID["v-sealed"])

        XCTAssertTrue(sealed.variant.isSealed)
        XCTAssertEqual(sealed.variant.price, 184.99)
        XCTAssertFalse(try XCTUnwrap(response.variantsByID["v-nm-holo"]).variant.isSealed)
    }

    /// A null price is a real answer — "no reliable market price" — and must not
    /// decode as zero, which would read as a free card.
    func testNullPriceDecodesAsAbsentNotZero() throws {
        let json = """
        { "data": [ { "id": "c", "variants": [
            { "uuid": "v", "condition": "Near Mint", "price": null } ] } ] }
        """
        let response = try JSONDecoder().decode(
            JustTCGBatchResponse.self, from: Data(json.utf8)
        )

        XCTAssertNil(response.variantsByID["v"]?.variant.price)
    }

    // MARK: - Graded shape (v2 beta)

    func testGradedVariantsDecodeGraderGradeAndQualifier() throws {
        let json = """
        { "data": [ { "id": "card-1", "variants": [
          { "uuid": "g-psa10", "price": 500.0,
            "grading": { "company": "PSA", "grade": 10 } },
          { "uuid": "g-psa10oc", "price": 300.0,
            "grading": { "company": "PSA", "grade": 10, "qualifier": "OC" } },
          { "uuid": "g-bgs10bl", "price": 2500.0,
            "grading": { "company": "BGS", "grade": 10, "label": "Black Label" } },
          { "uuid": "g-auth", "price": 40.0,
            "grading": { "company": "CGC", "grade": null, "label": "Authentic" } }
        ] } ] }
        """
        let response = try JSONDecoder().decode(
            JustTCGBatchResponse.self, from: Data(json.utf8)
        )
        let byID = response.variantsByID

        let psa10 = try XCTUnwrap(byID["g-psa10"]?.variant.grading)
        XCTAssertEqual(psa10.gradingCompany, .psa)
        XCTAssertEqual(psa10.gradeText, "10", "a 10 must not render as 10.0")
        XCTAssertEqual(psa10.cardGrade.display(company: .psa), "PSA 10")

        // A qualifier makes a different object, not a footnote on the same one.
        let oc = try XCTUnwrap(byID["g-psa10oc"]?.variant.grading)
        XCTAssertEqual(oc.cardGrade.display(company: .psa), "PSA 10 OC")
        XCTAssertNotEqual(oc.cardGrade.identityFragment, psa10.cardGrade.identityFragment)

        let blackLabel = try XCTUnwrap(byID["g-bgs10bl"]?.variant.grading)
        XCTAssertEqual(blackLabel.cardGrade.display(company: .bgs), "BGS 10 Black Label")

        // Authentic has no number, and the vendor models that rather than
        // inventing one.
        let authentic = try XCTUnwrap(byID["g-auth"]?.variant.grading)
        XCTAssertNil(authentic.gradeText)
        XCTAssertEqual(authentic.cardGrade.display(company: .cgc), "CGC Authentic")
    }

    func testHalfGradesSurvive() throws {
        let json = """
        { "data": [ { "id": "c", "variants": [ { "uuid": "v",
            "grading": { "company": "BGS", "grade": 9.5 } } ] } ] }
        """
        let response = try JSONDecoder().decode(
            JustTCGBatchResponse.self, from: Data(json.utf8)
        )

        XCTAssertEqual(response.variantsByID["v"]?.variant.grading?.gradeText, "9.5")
    }

    // MARK: - Quota arithmetic

    /// The whole justification for the refactor: twenty variants, one request.
    func testTwentyVariantsCostOneRequest() {
        XCTAssertEqual(JustTCGQuota.requestsNeeded(forVariants: 20), 1)
        XCTAssertEqual(JustTCGQuota.requestsNeeded(forVariants: 1), 1)
        XCTAssertEqual(JustTCGQuota.requestsNeeded(forVariants: 21), 2)
        XCTAssertEqual(JustTCGQuota.requestsNeeded(forVariants: 100), 5)
        XCTAssertEqual(JustTCGQuota.requestsNeeded(forVariants: 500), 25)
        XCTAssertEqual(JustTCGQuota.requestsNeeded(forVariants: 2_000), 100)
        XCTAssertEqual(JustTCGQuota.requestsNeeded(forVariants: 0), 0)
    }

    func testChunkingNeverExceedsThePlanBatchSize() {
        let lookups = (0..<47).map { JustTCGBatchLookup.variantID("v-\($0)") }
        let chunks = lookups.chunked(into: JustTCGQuota.batchSize)

        XCTAssertEqual(chunks.count, 3)
        XCTAssertTrue(chunks.allSatisfy { $0.count <= JustTCGQuota.batchSize })
        XCTAssertEqual(chunks.flatMap { $0 }.count, 47, "nothing may be dropped")
    }

    // MARK: - Deduplication

    /// Eight owned copies of one printing are one lookup. Quantities never
    /// multiply requests.
    func testDuplicateCopiesCollapseToOneLookup() {
        let targets = (0..<8).map { index in
            MarketPriceTarget(
                priceKey: "key-\(index)",
                game: .pokemon,
                printingID: "sv08.5-001",
                variantID: "normal",
                itemKind: .rawCard,
                marketVariantID: "shared-variant",
                lookupCandidates: [],
                currentAmount: nil,
                lastCheckedAt: nil
            )
        }

        let (batched, lookupOrder, unresolved) = JustTCGRefreshCoordinator.deduplicate(targets)

        XCTAssertEqual(batched.count, 1, "one variant, one lookup")
        XCTAssertEqual(batched[.variantID("shared-variant")]?.count, 8)
        XCTAssertEqual(lookupOrder, [.variantID("shared-variant")])
        XCTAssertTrue(unresolved.isEmpty)
    }

    /// A target with no usable identifier is reported, not silently dropped:
    /// "never asked" and "vendor has nothing" are different diagnoses.
    func testTargetsWithoutAnIdentifierAreReportedNotDropped() {
        let resolvable = MarketPriceTarget(
            priceKey: "a", game: .magic, printingID: "p", variantID: nil,
            itemKind: .rawCard, marketVariantID: nil,
            lookupCandidates: [.scryfallID("s-1")],
            currentAmount: nil, lastCheckedAt: nil
        )
        let unresolvable = MarketPriceTarget(
            priceKey: "b", game: .magic, printingID: "q", variantID: nil,
            itemKind: .rawCard, marketVariantID: nil,
            lookupCandidates: [],
            currentAmount: nil, lastCheckedAt: nil
        )

        let (batched, lookupOrder, unresolved) = JustTCGRefreshCoordinator.deduplicate([resolvable, unresolvable])

        XCTAssertEqual(batched.count, 1)
        XCTAssertEqual(lookupOrder, [.scryfallID("s-1")])
        XCTAssertEqual(unresolved.map(\.priceKey), ["b"])
    }

    func testDeduplicatePreservesFirstSeenLookupOrder() {
        func target(_ key: String, lookup: JustTCGBatchLookup) -> MarketPriceTarget {
            MarketPriceTarget(
                priceKey: key,
                game: .pokemon,
                printingID: key,
                variantID: nil,
                itemKind: .rawCard,
                marketVariantID: nil,
                lookupCandidates: [lookup],
                currentAmount: nil,
                lastCheckedAt: nil
            )
        }

        let first = JustTCGBatchLookup.scryfallID("first")
        let second = JustTCGBatchLookup.cardID("second")
        let (_, lookupOrder, _) = JustTCGRefreshCoordinator.deduplicate([
            target("first-row", lookup: first),
            target("second-row", lookup: second),
            target("first-duplicate", lookup: first)
        ])

        XCTAssertEqual(lookupOrder, [first, second])
    }

    func testUnmappedExplicitFinishDoesNotBorrowAnUnqualifiedListing() throws {
        let json = """
        { "data": [ { "uuid": "card-1", "variants": [
          { "uuid": "variant-1", "condition": "Near Mint", "printing": "Normal", "price": 1.0 }
        ] } ] }
        """
        let response = try JSONDecoder().decode(
            JustTCGBatchResponse.self,
            from: Data(json.utf8)
        )
        let target = MarketPriceTarget(
            priceKey: "key",
            game: .pokemon,
            printingID: "sv01-001",
            variantID: PhysicalVariant.masterBall.id,
            itemKind: .rawCard,
            marketVariantID: nil,
            lookupCandidates: [.cardID("card-1")],
            currentAmount: nil,
            lastCheckedAt: nil
        )

        guard case .noExactListing = JustTCGRefreshCoordinator.exactListing(
            lookup: .cardID("card-1"),
            owners: [target],
            response: response
        ) else {
            return XCTFail("an unmapped explicit finish must not inherit Normal")
        }
    }

    func testTreatmentQualifiedVendorListingRequiresAUsableDirectHandle() throws {
        let json = """
        { "data": [ { "uuid": "card-1", "variants": [
          { "uuid": "variant-1", "condition": "Near Mint", "printing": "Foil", "price": 8.0 }
        ] } ] }
        """
        let response = try JSONDecoder().decode(
            JustTCGBatchResponse.self,
            from: Data(json.utf8)
        )
        func target(treatmentIDs: [String]) -> MarketPriceTarget {
            MarketPriceTarget(
                priceKey: "key",
                game: .magic,
                printingID: "printing",
                variantID: PhysicalVariant.foil.id,
                itemKind: .rawCard,
                marketVariantID: nil,
                lookupCandidates: [.cardID("card-1")],
                currentAmount: nil,
                lastCheckedAt: nil,
                magicTreatmentIDsRaw: treatmentIDs
            )
        }

        guard case .matched = JustTCGRefreshCoordinator.exactListing(
            lookup: .cardID("card-1"),
            owners: [target(treatmentIDs: ["surgefoil"])],
            response: response
        ) else {
            return XCTFail("a direct vendor card handle should answer the exact treated printing")
        }

        let noHandle = MarketPriceTarget(
            priceKey: "key",
            game: .magic,
            printingID: "printing",
            variantID: PhysicalVariant.foil.id,
            itemKind: .rawCard,
            marketVariantID: nil,
            lookupCandidates: [],
            currentAmount: nil,
            lastCheckedAt: nil,
            magicTreatmentIDsRaw: ["surgefoil"]
        )
        guard case .noExactListing = JustTCGRefreshCoordinator.exactListing(
            lookup: .cardID("card-1"),
            owners: [noHandle],
            response: response
        ) else {
            return XCTFail("a handle-less treatment must not be answered by a search result")
        }

        guard case .matched = JustTCGRefreshCoordinator.exactListing(
            lookup: .cardID("card-1"),
            owners: [target(treatmentIDs: [])],
            response: response
        ) else {
            return XCTFail("the same ordinary Foil listing should remain usable")
        }
    }

    func testDirectPokemonListingRespectsExplicitEnglishEdition() throws {
        let response = try JSONDecoder().decode(JustTCGBatchResponse.self, from: Data(#"{"data":[{"uuid":"jungle-holo","variants":[{"uuid":"first","condition":"Near Mint","printing":"1st Edition Holofoil","price":480},{"uuid":"unlimited","condition":"Near Mint","printing":"Unlimited Holofoil","price":96}]}]}"#.utf8))
        for (run, expected) in [(PokemonPrintRun.unlimited, "unlimited"), (.firstEdition, "first")] {
            let target = MarketPriceTarget(priceKey: run.rawValue, game: .pokemon, printingID: "jungle-holo",
                variantID: PhysicalVariant.holo.id, itemKind: .rawCard, marketVariantID: nil,
                lookupCandidates: [.cardID("jungle-holo")], currentAmount: nil, lastCheckedAt: nil,
                pokemonPrintRun: run)
            guard case let .matched(_, variant) = JustTCGRefreshCoordinator.exactListing(
                lookup: .cardID("jungle-holo"), owners: [target], response: response) else {
                XCTFail("edition-qualified listing was lost"); continue
            }
            XCTAssertEqual(variant.variantId, expected)
        }
    }

    @MainActor
    func testSharedCardBatchKeepsEditionOwnersSeparate() async throws {
        let suite = "EditionOwners.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        RecordingURLProtocol.reset(body: #"{"data":[{"uuid":"jungle-holo","variants":[{"uuid":"first","condition":"Near Mint","printing":"1st Edition Holofoil","price":480},{"uuid":"unlimited","condition":"Near Mint","printing":"Unlimited Holofoil","price":96}]}]}"#)
        let targets = [PokemonPrintRun.unlimited, .firstEdition].map { run in
            MarketPriceTarget(priceKey: run.rawValue, game: .pokemon, printingID: "jungle-holo",
                variantID: PhysicalVariant.holo.id, itemKind: .rawCard, marketVariantID: nil,
                lookupCandidates: [.cardID("jungle-holo")], currentAmount: nil, lastCheckedAt: nil,
                pokemonPrintRun: run)
        }
        let (coordinator, _) = makeCoordinator(defaults: defaults)
        let probe = EditionPriceProbe()
        let report = await coordinator.refresh(targets, game: .pokemon, apply: { _, variant, owners in
            await probe.record(variant, owners: owners)
            return true
        }, checkpoint: { true })
        let prices = await probe.prices
        XCTAssertEqual(prices[PokemonPrintRun.unlimited.rawValue], 96)
        XCTAssertEqual(prices[PokemonPrintRun.firstEdition.rawValue], 480)
        XCTAssertEqual(RecordingURLProtocol.recorded().count, 1)
        XCTAssertEqual(report.targetsChecked, 2)
    }

    func testNamedPokemonParallelCanUseOnlyItsExactPhysicalProductAndSingleNearMintListing() throws {
        func response(_ variants: String) throws -> JustTCGBatchResponse {
            try JSONDecoder().decode(JustTCGBatchResponse.self, from: Data("""
            {"data":[{"uuid":"cosmos-product","tcgplayerId":"694692","variants":[\(variants)]}]}
            """.utf8))
        }
        let nearMint = #"{"uuid":"nm","condition":"Near Mint","printing":"Holofoil","price":2.34}"#
        let played = #"{"uuid":"lp","condition":"Lightly Played","printing":"Holofoil","price":1.20}"#
        var target = MarketPriceTarget(priceKey: "cosmos", game: .pokemon, printingID: "mep-078",
            variantID: PhysicalVariant.pokemonFoilPattern("cosmos").id, itemKind: .rawCard,
            marketVariantID: nil, lookupCandidates: [.tcgplayerID("694692")], currentAmount: nil,
            lastCheckedAt: nil, exactPhysicalProductID: "694692")
        guard case let .matched(_, variant) = JustTCGRefreshCoordinator.exactListing(
            lookup: .tcgplayerID("694692"), owners: [target], response: try response(played + "," + nearMint)
        ) else { return XCTFail("Exact Cosmos product should be priceable") }
        XCTAssertEqual(variant.variantId, "nm")

        let anotherNM = #"{"uuid":"other-nm","condition":"Near Mint","printing":"Normal","price":99}"#
        guard case .noExactListing = JustTCGRefreshCoordinator.exactListing(
            lookup: .tcgplayerID("694692"), owners: [target], response: try response(nearMint + "," + anotherNM)
        ) else { return XCTFail("Multiple NM listings are ambiguous") }
        target.exactPhysicalProductID = "999999"
        guard case .noExactListing = JustTCGRefreshCoordinator.exactListing(
            lookup: .tcgplayerID("694692"), owners: [target], response: try response(nearMint)
        ) else { return XCTFail("A different product must never answer this parallel") }
        target.exactPhysicalProductID = nil
        guard case .noExactListing = JustTCGRefreshCoordinator.exactListing(
            lookup: .tcgplayerID("694692"), owners: [target], response: try response(nearMint)
        ) else { return XCTFail("A stored generic handle alone cannot authorize a named parallel") }
    }

    // MARK: - Which identifier the vendor can actually resolve

    /// Verified live, one batch, two identifiers:
    ///
    ///     scryfallId  -> returned nothing
    ///     tcgplayerId -> returned the card
    ///
    /// The Scryfall id is a documented request parameter, but the vendor does
    /// not hold the mapping. Sending it produced an empty result, and because an
    /// absent variant is deliberately left alone rather than cleared, the whole
    /// failure was silent.
    func testScryfallIDIsNotAResolvableIdentifierForThisVendor() {
        // Still encodable — the parameter exists and other catalogues use it —
        // but nothing in the app may choose it for a batch.
        let lookup = JustTCGBatchLookup.scryfallID("9b74f022-3e1d-481d-b822-cd86060a9901")
        XCTAssertEqual(lookup.wireKey, "scryfallId")

        // The marketplace id outranks it, so a card carrying both never sends
        // the one that cannot be resolved.
        XCTAssertEqual(
            JustTCGBatchLookup.best(from: [lookup, .tcgplayerID("696977")]),
            .tcgplayerID("696977")
        )
    }

    /// Scryfall publishes `tcgplayer_id` on the exact printing object. Art cards
    /// and tokens — the entire fall-through population — can come back null, so
    /// they have no keyed route and must resolve by search exactly once.
    func testArtCardsAndTokensCarryNoMarketplaceIdentifier() throws {
        let ordinary = """
        { "id": "x", "name": "Cloud, Midgar Mercenary", "set": "fin",
          "set_name": "Final Fantasy", "collector_number": "10", "lang": "en",
          "digital": false, "layout": "normal", "tcgplayer_id": 630870 }
        """
        let artCard = """
        { "id": "y", "name": "Forest // Forest", "set": "amsh",
          "set_name": "MSH Art Series", "collector_number": "17", "lang": "en",
          "digital": false, "layout": "art_series" }
        """

        let decoder = JSONDecoder()
        XCTAssertEqual(
            try decoder.decode(ScryfallCard.self, from: Data(ordinary.utf8)).tcgplayerID,
            630870
        )
        XCTAssertNil(
            try decoder.decode(ScryfallCard.self, from: Data(artCard.utf8)).tcgplayerID,
            "an art card has no marketplace id to batch by"
        )
    }

    // MARK: - Freshness

    func testMissingPriceIsAlwaysEligibleRegardlessOfProviderClock() {
        XCTAssertTrue(
            MarketFreshness.needsRefresh(
                amount: nil,
                checkedAt: .now,
                providerUpdatedAt: Date.distantPast
            )
        )
    }

    func testFreshPriceIsNotRefetched() {
        XCTAssertFalse(
            MarketFreshness.needsRefresh(
                amount: 1.23,
                checkedAt: Date.now.addingTimeInterval(-60 * 60),
                providerUpdatedAt: nil
            )
        )
    }

    /// Past six hours, the provider's own clock decides: if the game has not
    /// been repriced since the last check, another request buys the same number.
    func testStalePriceDefersToTheProviderClock() {
        let checkedAt = Date.now.addingTimeInterval(-7 * 60 * 60)

        XCTAssertFalse(
            MarketFreshness.needsRefresh(
                amount: 1.23,
                checkedAt: checkedAt,
                providerUpdatedAt: checkedAt.addingTimeInterval(-60)
            ),
            "provider has not repriced since the last check"
        )
        XCTAssertTrue(
            MarketFreshness.needsRefresh(
                amount: 1.23,
                checkedAt: checkedAt,
                providerUpdatedAt: checkedAt.addingTimeInterval(60)
            )
        )
    }

    // MARK: - Sync safety

    /// `updated_after` is only safe once a complete pass has succeeded. Before
    /// that, a variant absent from a delta is indistinguishable from one that
    /// was never fetched.
    func testDeltaSyncIsRefusedUntilAFullPassSucceeds() throws {
        let suite = "JustTCGContractTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let ledger = JustTCGSyncLedger(defaults: defaults)

        XCTAssertNil(ledger.deltaCutoff(game: .pokemon, apiVersion: "v1"))

        ledger.recordCompleteSync(game: .pokemon, apiVersion: "v1")
        XCTAssertNotNil(ledger.deltaCutoff(game: .pokemon, apiVersion: "v1"))
        // Versions are tracked separately: a v1 pass says nothing about v2.
        XCTAssertNil(ledger.deltaCutoff(game: .pokemon, apiVersion: "v2"))
        XCTAssertNil(ledger.deltaCutoff(game: .magic, apiVersion: "v1"))
    }

    // MARK: - Quota lanes

    /// Background work stops at 75 so the last 15 remain for whatever the user
    /// asks for directly.
    func testBackgroundStopsShortSoInteractiveWorkStillFits() throws {
        let suite = "JustTCGContractTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let ledger = JustTCGRequestLedger(defaults: defaults)
        for _ in 0..<JustTCGQuota.backgroundDailyCeiling {
            XCTAssertEqual(ledger.reserve(lane: .background), .allowed)
        }
        guard case .dailyReached = ledger.reserve(lane: .background) else {
            return XCTFail("background must stop at its ceiling")
        }
        // The reserve is still spendable by the user.
        XCTAssertEqual(ledger.reserve(lane: .interactive), .allowed)
    }

    func testMonthlyCeilingBlocksBothLanes() throws {
        let suite = "JustTCGContractTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(JustTCGQuota.monthlyHardLimit, forKey: "justTCGRequestsUsedThisMonth")
        // UTC, matching the ledger. Seeding with the local calendar makes the
        // ledger see a different month, roll over, and zero the counter — which
        // is the ledger behaving correctly and the test lying.
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        defaults.set(
            calendar.dateInterval(of: .month, for: .now)?.start,
            forKey: "justTCGBudgetMonth"
        )
        let ledger = JustTCGRequestLedger(defaults: defaults)

        guard case .monthlyReached = ledger.reserve(lane: .interactive) else {
            return XCTFail("the monthly ceiling must stop even interactive work")
        }
    }

    /// Being told to wait is not a request the user got value from, so it must
    /// not consume an allowance.
    func testRateLimitBlocksWithoutSpendingAllowance() throws {
        let suite = "JustTCGContractTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let ledger = JustTCGRequestLedger(defaults: defaults)
        let retryAt = Date.now.addingTimeInterval(600)
        ledger.recordRateLimit(until: retryAt)

        XCTAssertEqual(ledger.reserve(lane: .interactive), .rateLimited(retryAt: retryAt))
        XCTAssertEqual(ledger.snapshot().usedToday, 0)
    }

    /// One allowance, not two.
    ///
    /// A refresh spends from both paths: batched pricing goes through the
    /// transport, identity resolution through `ProductFallbackBudget`. When
    /// those kept separate counters they each allowed 90 a day against a real
    /// limit of 100, and the overspend arrived as 429s rather than as an honest
    /// "budget reached".
    func testBothRefreshPathsSpendFromTheSameAllowance() async throws {
        let suite = "JustTCGContractTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let ledger = JustTCGRequestLedger(defaults: defaults)
        let identityBudget = ProductFallbackBudget(defaults: defaults)
        // Spend the whole day through the batched path.
        for _ in 0..<JustTCGQuota.dailyHardLimit {
            XCTAssertEqual(ledger.reserve(lane: .interactive), .allowed)
        }

        // The identity path must now find nothing left, not a fresh 90.
        let reservation = await identityBudget.reserveRequest()
        guard case .budgetReached = reservation else {
            return XCTFail("identity resolution must share the batched path's allowance")
        }
    }

    /// The app's counter starts at zero on a fresh install while the account may
    /// already have spent most of the day. The vendor reports the truth on every
    /// response, so the local number defers to it.
    func testLocalCountCorrectsItselfAgainstTheServer() throws {
        let suite = "JustTCGContractTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let ledger = JustTCGRequestLedger(defaults: defaults)
        XCTAssertEqual(ledger.snapshot().usedToday, 0, "a fresh install knows nothing")

        // Shaped exactly like the live `_metadata` block.
        ledger.syncFromServer(
            JustTCGQuotaMetadata(
                apiPlan: "Free Tier",
                apiDailyLimit: 100,
                apiDailyRequestsUsed: 70,
                apiDailyRequestsRemaining: 30,
                apiRequestLimit: 1_000,
                apiRequestsUsed: 70,
                apiRequestsRemaining: 930
            )
        )

        XCTAssertEqual(ledger.snapshot().usedToday, 70)
        XCTAssertEqual(ledger.snapshot().remainingToday, JustTCGQuota.dailyHardLimit - 70)
    }

    /// Never revise the count *down* to the server's: if the app believes it has
    /// spent more than the server has recorded yet, trusting the lower number
    /// would overshoot the real limit.
    func testServerSyncNeverLowersTheLocalCount() throws {
        let suite = "JustTCGContractTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let ledger = JustTCGRequestLedger(defaults: defaults)
        for _ in 0..<50 { _ = ledger.reserve(lane: .interactive) }

        ledger.syncFromServer(
            JustTCGQuotaMetadata(
                apiPlan: "Free Tier", apiDailyLimit: 100,
                apiDailyRequestsUsed: 10, apiDailyRequestsRemaining: 90,
                apiRequestLimit: 1_000, apiRequestsUsed: 10, apiRequestsRemaining: 990
            )
        )

        XCTAssertEqual(ledger.snapshot().usedToday, 50, "must not revise downward")
    }

    func testProviderRenewalDoesNotInflateOrResetCalendarSpendingBudget() throws {
        let suite = "JustTCGContractTests.monthly.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let ledger = JustTCGRequestLedger(defaults: defaults)
        let start = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-10-14T12:00:00Z"))
        for _ in 0..<10 { XCTAssertEqual(ledger.reserve(lane: .interactive, now: start), .allowed) }
        func metadata(_ used: Int) -> JustTCGQuotaMetadata {
            JustTCGQuotaMetadata(
                apiPlan: "Free", apiDailyLimit: 100,
                apiDailyRequestsUsed: nil, apiDailyRequestsRemaining: nil,
                apiRequestLimit: 1_000, apiRequestsUsed: used,
                apiRequestsRemaining: 1_000 - used
            )
        }
        ledger.syncFromServer(metadata(950), now: start)
        XCTAssertEqual(ledger.snapshot(now: start).usedThisMonth, 10)
        let renewal = start.addingTimeInterval(24 * 60 * 60)
        ledger.syncFromServer(metadata(1), now: renewal)
        XCTAssertEqual(ledger.reserve(lane: .interactive, now: renewal), .allowed)
        // A late pre-renewal response cannot import the old billing period.
        ledger.syncFromServer(metadata(950), now: renewal)
        let restarted = JustTCGRequestLedger(defaults: defaults)
        XCTAssertEqual(restarted.snapshot(now: renewal).usedThisMonth, 11)
        let november = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-11-01T00:00:00Z"))
        XCTAssertEqual(restarted.snapshot(now: november).usedThisMonth, 0)
        restarted.syncFromServer(metadata(500), now: november)
        XCTAssertEqual(restarted.reserve(lane: .interactive, now: november), .allowed)
        XCTAssertEqual(restarted.snapshot(now: november).usedThisMonth, 1)
    }

    func testLegacyMonthlySpendingIsPreservedUntilCalendarRollover() throws {
        let suite = "JustTCGContractTests.legacyMonthly.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let october = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-10-01T00:00:00Z"))
        defaults.set(october, forKey: "justTCGBudgetMonth")
        defaults.set(900, forKey: "justTCGRequestsUsedThisMonth")
        let ledger = JustTCGRequestLedger(defaults: defaults)
        guard case .monthlyReached = ledger.reserve(lane: .interactive, now: october) else {
            return XCTFail("Legacy spending must not be silently cleared")
        }
        XCTAssertEqual(ledger.reserve(lane: .interactive, now: october.addingTimeInterval(31 * 86400)), .allowed)
    }

    func testConcurrentMonthlyReservationsRetainTheSpendingCeiling() throws {
        let suite = "JustTCGContractTests.concurrentMonthly.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-10-01T00:00:00Z"))
        defaults.set(now, forKey: "justTCGBudgetMonth")
        defaults.set(850, forKey: "justTCGRequestsUsedThisMonth")
        let ledger = JustTCGRequestLedger(defaults: defaults)
        DispatchQueue.concurrentPerform(iterations: 100) { _ in
            _ = ledger.reserve(lane: .interactive, now: now)
        }
        let snapshot = ledger.snapshot(now: now)
        XCTAssertEqual(snapshot.usedThisMonth, 900)
        XCTAssertEqual(snapshot.usedToday, 50)
        guard case .monthlyReached = ledger.reserve(lane: .background, now: now) else {
            return XCTFail("The monthly cap covers both lanes")
        }
    }

    /// When the allowance is gone the user is told when it comes back, and that
    /// moment must be in the future rather than a stale timestamp.
    func testBudgetExhaustionReportsAFutureResetTime() throws {
        let suite = "JustTCGContractTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let ledger = JustTCGRequestLedger(defaults: defaults)
        for _ in 0..<JustTCGQuota.dailyHardLimit { _ = ledger.reserve(lane: .interactive) }

        guard case let .dailyReached(resetAt) = ledger.reserve(lane: .interactive) else {
            return XCTFail("expected the daily ceiling to stop this")
        }
        XCTAssertGreaterThan(resetAt, .now)
        XCTAssertLessThanOrEqual(resetAt.timeIntervalSinceNow, 24 * 60 * 60 + 1)
        XCTAssertEqual(ledger.snapshot().remainingToday, 0)
    }

    func testRetryAfterAcceptsSecondsAndHTTPDate() {
        let now = Date(timeIntervalSince1970: 1_000_000)

        XCTAssertEqual(
            JustTCGTransport.retryDate(from: "120", now: now),
            now.addingTimeInterval(120)
        )
        XCTAssertNotNil(
            JustTCGTransport.retryDate(from: "Wed, 21 Oct 2015 07:28:00 GMT", now: now)
        )
        XCTAssertNil(JustTCGTransport.retryDate(from: nil, now: now))
        for value in ["inf", "Infinity", "1e999", "NaN", "-1"] {
            XCTAssertNil(JustTCGTransport.retryDate(from: value, now: now), value)
        }
    }

    func testDirectScryfallRefreshRequiresTheRequestedPrintingID() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RecordingURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let service = ScryfallService(breaker: TCGdexCircuitBreaker(), session: session)
        let requestedID = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
        for returnedID in [requestedID, "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"] {
            RecordingURLProtocol.reset(body: """
                {"id":"\(returnedID)","name":"Fixture","set":"tst","set_name":"Test Set",
                 "collector_number":"1","lang":"en","digital":false,"finishes":["nonfoil"]}
                """)
            do {
                let card = try await service.fetchCard(id: requestedID.uppercased(), ignoringCache: true)
                XCTAssertEqual(returnedID, requestedID, "A different printing must be rejected")
                XCTAssertEqual(card.id, requestedID)
            } catch ScryfallError.identityMismatch {
                XCTAssertNotEqual(returnedID, requestedID)
            }
        }
    }

    func testDeltaCutoffConvertsDeviceClockAheadOrBehindToServerTime() {
        let cutoff = Date(timeIntervalSince1970: 1_700_000_000)

        XCTAssertEqual(
            JustTCGServerClock.deltaRequestCutoff(for: cutoff, serverClockOffset: 10 * 60),
            cutoff.addingTimeInterval(-5 * 60),
            "when the server is 10 minutes ahead, send the cutoff in server time"
        )
        XCTAssertEqual(
            JustTCGServerClock.deltaRequestCutoff(for: cutoff, serverClockOffset: -10 * 60),
            cutoff.addingTimeInterval(-25 * 60),
            "when the device is 10 minutes ahead, move the cutoff earlier"
        )
        XCTAssertEqual(
            JustTCGServerClock.deltaRequestCutoff(for: cutoff, serverClockOffset: nil),
            cutoff.addingTimeInterval(-15 * 60),
            "without a known offset, keep the safety margin"
        )
    }

    // MARK: - Namespaced identity

    /// A slab never shares a row, a quantity or a price with the raw copy of the
    /// same printing.
    func testGradedAndSealedKeysCannotCollideWithRawKeys() {
        let raw = PriceRecord.key(game: .pokemon, printingID: "sv08.5-001", variantID: "holo")
        let graded = CollectedCard.gradedCollectionKey(
            game: .pokemon, underlyingPrintingID: "sv08.5-001", variantUUID: "g-1"
        )
        let sealed = CollectedCard.sealedCollectionKey(
            game: .pokemon, productUUID: "p-1", variantUUID: "v-1"
        )

        XCTAssertNotEqual(raw, graded)
        XCTAssertNotEqual(raw, sealed)
        XCTAssertTrue(graded.hasPrefix("graded:"))
        XCTAssertTrue(sealed.hasPrefix("sealed:"))
    }

    /// Two slabs with certificates are two objects even at the same grade.
    func testCertifiedSlabsDoNotMerge() {
        let first = CollectedCard.gradedCollectionKey(
            game: .pokemon, underlyingPrintingID: "p", variantUUID: "g",
            certificationNumber: "12345678"
        )
        let second = CollectedCard.gradedCollectionKey(
            game: .pokemon, underlyingPrintingID: "p", variantUUID: "g",
            certificationNumber: "87654321"
        )
        let uncertified = CollectedCard.gradedCollectionKey(
            game: .pokemon, underlyingPrintingID: "p", variantUUID: "g",
            certificationNumber: nil
        )

        XCTAssertNotEqual(first, second)
        XCTAssertNotEqual(first, uncertified)
    }

    func testSealedProductsNeverCountTowardSetCompletion() {
        XCTAssertFalse(CollectionItemKind.sealedProduct.countsTowardSetCompletion)
        XCTAssertTrue(CollectionItemKind.rawCard.countsTowardSetCompletion)
        XCTAssertTrue(CollectionItemKind.gradedCard.countsTowardSetCompletion)
    }

    // MARK: - Identifier spellings

    /// The regression that made every fallback refresh re-pay for a search.
    ///
    /// `ProductVariant` is what the identity-resolution pass decodes, and it was
    /// asking for `variantId` — the request parameter's name, which the response
    /// does not use. It therefore never captured a variant handle, nothing was
    /// ever persisted as batchable, and the "search once, batch forever after"
    /// design never engaged.
    func testProductVariantReadsTheVariantHandleFromUUID() throws {
        let json = """
        { "uuid": "variant-uuid", "id": "variant-slug", "condition": "Near Mint",
          "printing": "Holofoil", "price": 12.5, "lastUpdated": 1700000000 }
        """
        let variant = try JSONDecoder().decode(ProductVariant.self, from: Data(json.utf8))

        XCTAssertEqual(variant.variantId, "variant-uuid", "the uuid is the handle batches send")
        XCTAssertEqual(variant.updatedAt, Date(timeIntervalSince1970: 1_700_000_000))
    }

    /// The slug still identifies the variant when no uuid is published, which is
    /// better than storing nothing and searching again next time.
    func testProductVariantFallsBackToTheSlug() throws {
        let json = """
        { "id": "variant-slug", "condition": "Near Mint", "price": 1 }
        """
        let variant = try JSONDecoder().decode(ProductVariant.self, from: Data(json.utf8))

        XCTAssertEqual(variant.variantId, "variant-slug")
    }

    /// `cardId=<slug>` is verified against the live API to return the card, so
    /// the slug remains the handle. The uuid is decoded alongside it.
    func testProductCardHandlePrefersTheVerifiedSlug() throws {
        let json = """
        { "id": "card-slug", "uuid": "card-uuid", "name": "Trevenant",
          "set": "trick-or-trade-2023", "number": "017/196", "variants": [] }
        """
        let card = try JSONDecoder().decode(ProductCard.self, from: Data(json.utf8))

        XCTAssertEqual(card.vendorID, "card-slug")
        XCTAssertEqual(card.uuid, "card-uuid")
    }

    /// The card object mixes conventions — `set_name` is snake_case while the
    /// nested variant's `tcgplayerSkuId` is camelCase, both pinned from live
    /// responses. Nothing pins the marketplace ids, and a wrong guess is silent:
    /// sealed products simply show a placeholder instead of artwork.
    func testMarketplaceIdentifiersDecodeUnderEitherSpelling() throws {
        let camel = """
        { "data": [ { "id": "box", "uuid": "box-uuid", "tcgplayerId": "610553",
            "set_name": "Legendary Treasures", "variants": [] } ] }
        """
        let snake = """
        { "data": [ { "id": "box", "uuid": "box-uuid", "tcgplayer_id": 610553,
            "setName": "Legendary Treasures", "variants": [] } ] }
        """

        for payload in [camel, snake] {
            let card = try XCTUnwrap(
                JSONDecoder().decode(JustTCGBatchResponse.self, from: Data(payload.utf8)).data.first
            )
            XCTAssertEqual(card.tcgplayerId, "610553")
            XCTAssertEqual(card.setName, "Legendary Treasures")
        }
    }

    // MARK: - v2 graded beta

    /// Pinned from a live v2 response. v2 is a different schema from v1, not a
    /// newer version of it: the price moves into `markets`, and the grade label
    /// is `grade_label`. Decoding v2 with v1's field names left every graded
    /// variant with no price at all.
    func testV2GradedVariantPriceComesFromTheMarketsBlock() throws {
        let json = """
        { "id": "v2-variant", "type": "graded", "condition": null,
          "printing": "Holofoil", "language": "English",
          "grading": { "company": "PSA", "grade": 10, "grade_label": "GEM MT",
                       "qualifier": null, "canonical": "PSA 10" },
          "markets": [ { "region": "US", "currency": "USD", "price": 3999.99,
                         "updated_at": 1784585831 } ] }
        """
        let variant = try JSONDecoder().decode(JustTCGVariant.self, from: Data(json.utf8))

        XCTAssertNil(variant.price, "v2 publishes no flat price")
        XCTAssertEqual(variant.type, "graded")
        XCTAssertEqual(variant.marketPriceUSD, 3999.99)
        XCTAssertEqual(variant.updatedAt, Date(timeIntervalSince1970: 1_784_585_831))
        XCTAssertEqual(variant.variantId, "v2-variant")
        XCTAssertEqual(variant.grading?.label, "GEM MT")
        XCTAssertEqual(variant.grading?.canonical, "PSA 10")
        XCTAssertEqual(variant.grading?.gradeText, "10")
    }

    func testAuthenticUsesCanonicalWhenVendorOmitsTheGradeLabel() throws {
        let json = """
        { "company": "CGC", "grade": null, "canonical": "CGC Authentic" }
        """
        let grading = try JSONDecoder().decode(
            JustTCGGrading.self,
            from: Data(json.utf8)
        )

        XCTAssertEqual(grading.cardGrade.display(company: .cgc), "CGC Authentic")
        let variant = GradedVariant(
            id: "authentic",
            company: .cgc,
            grade: grading.cardGrade,
            canonical: grading.canonical,
            marketPriceUSD: 40,
            updatedAt: nil
        )
        XCTAssertEqual(variant.displayName, "CGC Authentic")
    }

    /// v1's flat price keeps working; the two schemas share one type.
    func testV1FlatPriceStillReads() throws {
        let json = """
        { "uuid": "v1-variant", "condition": "Near Mint", "printing": "Holofoil",
          "price": 106.39, "lastUpdated": 1700000000 }
        """
        let variant = try JSONDecoder().decode(JustTCGVariant.self, from: Data(json.utf8))

        XCTAssertEqual(variant.marketPriceUSD, 106.39)
        XCTAssertEqual(variant.updatedAt, Date(timeIntervalSince1970: 1_700_000_000))
    }

    func testForeignCurrencyIsNotExposedAsUSD() throws {
        let json = """
        { "uuid": "eur-variant", "price": 106.39, "currency": "EUR",
          "lastUpdated": 1700000000 }
        """
        let variant = try JSONDecoder().decode(JustTCGVariant.self, from: Data(json.utf8))

        XCTAssertEqual(variant.marketPrice?.currency, "EUR")
        XCTAssertNil(variant.marketPriceUSD)
        XCTAssertNil(variant.updatedAt)
    }

    func testMarketPriceChoosesTheExplicitUSDMarket() throws {
        let json = """
        { "uuid": "mixed-variant", "markets": [
          { "currency": "EUR", "price": 90.00, "updated_at": 1700000000 },
          { "currency": "USD", "price": 100.00, "updated_at": 1700000100 }
        ] }
        """
        let variant = try JSONDecoder().decode(JustTCGVariant.self, from: Data(json.utf8))

        XCTAssertEqual(variant.marketPriceUSD, 100.00)
        XCTAssertEqual(variant.updatedAt, Date(timeIntervalSince1970: 1_700_000_100))
    }

    /// v2 does not reject an identifier it does not recognise — it silently
    /// browses instead, returning arbitrary graded cards for the game. The app
    /// sends a catalog id, which v2 has never heard of, so the picker was
    /// offering slabs of unrelated cards.
    func testGradedIdentityRejectsACardTheBrowseHandedBack() throws {
        let json = """
        { "id": "other", "name": "Charizard Star (Delta Species)",
          "number": "100/101", "set_name": "EX Dragon Frontiers", "variants": [] }
        """
        let returned = try JSONDecoder().decode(JustTCGCard.self, from: Data(json.utf8))
        let asked = GradedCardIdentity(
            name: "Charizard", setName: "Base Set", collectorNumber: "4/102"
        )

        XCTAssertFalse(asked.matches(returned, game: .pokemon))
    }

    func testGradedIdentityRequiresTheSetAndFullCollectorNumberToMatch() throws {
        let wrongSet = try JSONDecoder().decode(
            JustTCGCard.self,
            from: Data("""
            { "id": "wrong-set", "name": "Charizard", "number": "4/102",
              "set_name": "Base Set 2", "variants": [] }
            """.utf8)
        )
        let wrongDenominator = try JSONDecoder().decode(
            JustTCGCard.self,
            from: Data("""
            { "id": "wrong-number", "name": "Charizard", "number": "4/130",
              "set_name": "Base Set", "variants": [] }
            """.utf8)
        )
        let asked = GradedCardIdentity(
            name: "Charizard", setName: "Base Set", collectorNumber: "004/102"
        )

        XCTAssertFalse(asked.matches(wrongSet, game: .pokemon))
        XCTAssertFalse(asked.matches(wrongDenominator, game: .pokemon))
    }

    func testGradedIdentityRejectsAnAmbiguousMissingCollectorNumber() throws {
        let returned = try JSONDecoder().decode(
            JustTCGCard.self,
            from: Data("""
            { "id": "missing-number", "name": "Charizard",
              "set_name": "Base Set", "variants": [] }
            """.utf8)
        )
        let asked = GradedCardIdentity(
            name: "Charizard", setName: "Base Set", collectorNumber: "4/102"
        )

        XCTAssertFalse(asked.matches(returned, game: .pokemon))
    }

    func testGradedIdentityProjectionNamesMatchStoredProperties() {
        let identity = GradedCardIdentity(
            name: "Charizard",
            setName: "Base Set",
            collectorNumber: "004/102",
            catalogID: "base1-4",
            pokemonPrintRun: .firstEdition
        )

        let stored = Set(Mirror(reflecting: identity).children.compactMap(\.label))
        let projected = Set(Mirror(reflecting: identity.exhaustiveProjection).children.compactMap(\.label))
        XCTAssertEqual(stored, projected)

        for value in identity.exhaustiveProjection.values {
            XCTAssertTrue(
                identity.groupingKey(game: .pokemon).contains(value.lowercased()),
                "groupingKey dropped projection value \(value)"
            )
        }
    }

    func testGradedVendorProductMustMatchGameSetAndPrintRunBeforeBinding() throws {
        let identity = GradedCardIdentity(
            name: "Charizard",
            setName: "Base Set",
            collectorNumber: "004/102",
            catalogID: "base1-4",
            pokemonPrintRun: .firstEdition
        )
        let rightCard = try JSONDecoder().decode(
            JustTCGCard.self,
            from: Data("""
            { "id": "right", "game": "pokemon", "set": "base-set-shadowless-pokemon",
              "name": "Charizard", "number": "004/102", "set_name": "Base Set",
              "variants": [{ "id": "right-variant", "type": "graded",
                "printing": "1st Edition Holofoil",
                "grading": { "company": "PSA", "grade": 10 } }] }
            """.utf8)
        )
        let rightVariant = try XCTUnwrap(rightCard.variants?.first)
        XCTAssertTrue(
            identity.matches(
                rightCard,
                variant: rightVariant,
                game: .pokemon,
                expectedSetSlug: "base-set-shadowless-pokemon"
            )
        )

        let wrongGame = try JSONDecoder().decode(
            JustTCGCard.self,
            from: Data("""
            { "id": "wrong-game", "game": "magic-the-gathering",
              "set": "base-set-shadowless-pokemon", "name": "Charizard", "number": "004/102",
              "set_name": "Base Set", "variants": [{ "id": "wrong-game-variant", "type": "graded",
                "printing": "1st Edition Holofoil", "grading": { "company": "PSA", "grade": 10 } }] }
            """.utf8)
        )
        let wrongSet = try JSONDecoder().decode(
            JustTCGCard.self,
            from: Data("""
            { "id": "wrong-set", "game": "pokemon", "set": "base-set-pokemon",
              "name": "Charizard", "number": "004/102", "set_name": "Base Set",
              "variants": [{ "id": "wrong-set-variant", "type": "graded",
                "printing": "1st Edition Holofoil", "grading": { "company": "PSA", "grade": 10 } }] }
            """.utf8)
        )
        let wrongPrinting = try JSONDecoder().decode(
            JustTCGCard.self,
            from: Data("""
            { "id": "wrong-printing", "game": "pokemon", "set": "base-set-shadowless-pokemon",
              "name": "Charizard", "number": "004/102", "set_name": "Base Set",
              "variants": [{ "id": "wrong-printing-variant", "type": "graded",
                "printing": "Holofoil", "grading": { "company": "PSA", "grade": 10 } }] }
            """.utf8)
        )

        XCTAssertFalse(
            identity.matches(
                wrongGame,
                variant: try XCTUnwrap(wrongGame.variants?.first),
                game: .pokemon,
                expectedSetSlug: "base-set-shadowless-pokemon"
            )
        )
        XCTAssertFalse(
            identity.matches(
                wrongSet,
                variant: try XCTUnwrap(wrongSet.variants?.first),
                game: .pokemon,
                expectedSetSlug: "base-set-shadowless-pokemon"
            )
        )
        XCTAssertFalse(
            identity.matches(
                wrongPrinting,
                variant: try XCTUnwrap(wrongPrinting.variants?.first),
                game: .pokemon,
                expectedSetSlug: "base-set-shadowless-pokemon"
            )
        )
    }

    func testGradedIdentityAcceptsTheCardItAskedFor() throws {
        let json = """
        { "id": "right", "name": "Charizard", "number": "4/102",
          "set_name": "Base Set", "variants": [] }
        """
        let returned = try JSONDecoder().decode(JustTCGCard.self, from: Data(json.utf8))
        let asked = GradedCardIdentity(
            name: "Charizard", setName: "Base Set", collectorNumber: "004/102"
        )

        XCTAssertTrue(asked.matches(returned, game: .pokemon))
    }

    func testGradedIdentityUsesTheRequestedGameSetNormalization() throws {
        let json = """
        { "id": "right", "name": "The One Ring",
          "set_name": "The Lord of the Rings Commander", "variants": [] }
        """
        let returned = try JSONDecoder().decode(JustTCGCard.self, from: Data(json.utf8))
        let asked = GradedCardIdentity(
            name: "The One Ring", setName: "Commander: The Lord of the Rings", collectorNumber: ""
        )

        XCTAssertTrue(asked.matches(returned, game: .magic))
        XCTAssertFalse(asked.matches(returned, game: .pokemon))
    }

    func testGradedRequestUsesTheResolvedVendorSetName() throws {
        let identity = GradedCardIdentity(
            name: "The One Ring",
            setName: "Commander: The Lord of the Rings",
            collectorNumber: ""
        )
        let directory = ProductSetDirectory(sets: [
            (
                id: "the-lord-of-the-rings-commander-magic-the-gathering",
                name: "The Lord of the Rings Commander"
            )
        ])

        let setSlug = try XCTUnwrap(
            JustTCGV2GradedClient.resolvedSetSlug(
                identity: identity,
                game: .magic,
                directory: directory
            )
        )
        XCTAssertEqual(
            setSlug,
            "the-lord-of-the-rings-commander-magic-the-gathering"
        )

        let query = JustTCGV2GradedClient.requestQuery(
            identity: identity,
            game: .magic,
            setSlug: setSlug
        )
        XCTAssertEqual(
            query.first { $0.0 == "set" }?.1,
            "the-lord-of-the-rings-commander-magic-the-gathering"
        )
        XCTAssertEqual(
            query.first { $0.0 == "limit" }?.1,
            String(JustTCGQuota.maximumPageSize)
        )
        XCTAssertNotEqual(
            query.first { $0.0 == "set" }?.1,
            "commander-the-lord-of-the-rings-magic-the-gathering"
        )
    }

    func testGradedRequestOmitsSetWhenTheDirectoryCannotResolveIt() {
        let identity = GradedCardIdentity(
            name: "The One Ring",
            setName: "Commander: The Lord of the Rings",
            collectorNumber: ""
        )
        let directory = ProductSetDirectory(sets: [
            (id: "unrelated-set-magic-the-gathering", name: "Unrelated Set")
        ])

        XCTAssertNil(
            JustTCGV2GradedClient.resolvedSetSlug(
                identity: identity,
                game: .magic,
                directory: directory
            )
        )
        let query = JustTCGV2GradedClient.requestQuery(
            identity: identity,
            game: .magic,
            setSlug: nil
        )
        XCTAssertNil(query.first { $0.0 == "set" })
        XCTAssertEqual(query.first { $0.0 == "game" }?.1, "magic-the-gathering")
    }

    func testGradedRequestUsesDocumentedCompanyAndNumericGradeTokens() {
        let identity = GradedCardIdentity(
            name: "Charizard",
            setName: "Base Set",
            collectorNumber: "004/102"
        )

        let normalized = JustTCGV2GradedClient.requestQuery(
            identity: identity,
            game: .pokemon,
            setSlug: nil,
            companies: [.psa],
            grades: ["10.0"]
        )
        XCTAssertEqual(normalized.first { $0.0 == "grading_company" }?.1, "PSA")
        XCTAssertEqual(normalized.first { $0.0 == "grade" }?.1, "10")
        XCTAssertEqual(normalized.first { $0.0 == "graded" }?.1, "only")
        XCTAssertEqual(normalized.first { $0.0 == "regions" }?.1, "NA")
        XCTAssertNil(normalized.first { $0.0 == "include_price_history" })

        let malformedGrade = JustTCGV2GradedClient.requestQuery(
            identity: identity,
            game: .pokemon,
            setSlug: nil,
            companies: [.psa],
            grades: ["PSA 10"]
        )
        XCTAssertNil(malformedGrade.first { $0.0 == "grade" })

        let authentic = JustTCGV2GradedClient.requestQuery(
            identity: identity,
            game: .pokemon,
            setSlug: nil,
            companies: [.cgc],
            grades: ["Authentic"]
        )
        XCTAssertNil(authentic.first { $0.0 == "grade" })

        let tag = JustTCGV2GradedClient.requestQuery(
            identity: identity,
            game: .pokemon,
            setSlug: nil,
            companies: [.tag],
            grades: ["10"]
        )
        XCTAssertNil(tag.first { $0.0 == "grading_company" })
        XCTAssertNil(tag.first { $0.0 == "grade" })

        let gradeList = JustTCGV2GradedClient.requestQuery(
            identity: identity,
            game: .pokemon,
            setSlug: nil,
            companies: [.psa],
            grades: ["10.0", "9"]
        )
        XCTAssertEqual(gradeList.first { $0.0 == "grade" }?.1, "9,10")
    }

    func testGradedRequestRoutesJapanesePokemonThroughItsOwnGameAndSet() throws {
        let identity = GradedCardIdentity(
            name: "Inferno X Card",
            setName: "Inferno X",
            collectorNumber: "001",
            catalogID: "M2-001"
        )
        let directory = ProductSetDirectory(sets: [
            (id: "m2-inferno-x-pokemon-japan", name: nil)
        ])

        let setSlug = try XCTUnwrap(
            JustTCGV2GradedClient.resolvedSetSlug(
                identity: identity,
                game: .pokemon,
                directory: directory
            )
        )
        let query = JustTCGV2GradedClient.requestQuery(
            identity: identity,
            game: .pokemon,
            setSlug: setSlug
        )

        XCTAssertEqual(query.first { $0.0 == "game" }?.1, "pokemon-japan")
        XCTAssertEqual(
            query.first { $0.0 == "set" }?.1,
            "m2-inferno-x-pokemon-japan"
        )
    }

    func testGradedRequestUsesTheShadowlessSetForBaseSetFirstEdition() throws {
        let identity = GradedCardIdentity(
            name: "Charizard",
            setName: "Base Set",
            collectorNumber: "004",
            catalogID: "base1-004",
            pokemonPrintRun: .firstEdition
        )
        let directory = ProductSetDirectory(sets: [
            (id: "base-set-pokemon", name: "Base Set"),
            (id: "base-set-shadowless-pokemon", name: "Base Set Shadowless")
        ])

        let setSlug = try XCTUnwrap(
            JustTCGV2GradedClient.resolvedSetSlug(
                identity: identity,
                game: .pokemon,
                directory: directory
            )
        )
        let query = JustTCGV2GradedClient.requestQuery(
            identity: identity,
            game: .pokemon,
            setSlug: setSlug
        )

        XCTAssertEqual(
            query.first { $0.0 == "set" }?.1,
            "base-set-shadowless-pokemon"
        )
    }

    /// One request must serve every owned grade of one card, or a shelf of PSA
    /// 8/9/10 copies costs three requests where it should cost one.
    func testEveryGradeOfOneCardSharesARequest() {
        let psa9 = GradedCardIdentity(
            name: "Charizard", setName: "Base Set", collectorNumber: "004/102"
        )
        let psa10 = GradedCardIdentity(
            name: "Charizard", setName: "Base Set", collectorNumber: "004/102"
        )
        let other = GradedCardIdentity(
            name: "Blastoise", setName: "Base Set", collectorNumber: "002/102"
        )

        XCTAssertEqual(psa9.groupingKey(game: .pokemon), psa10.groupingKey(game: .pokemon))
        XCTAssertNotEqual(psa9.groupingKey(game: .pokemon), other.groupingKey(game: .pokemon))
    }

    func testDifferentPokemonPrintRunsDoNotShareAGradedLookupGroup() {
        let firstEdition = GradedCardIdentity(
            name: "Charizard",
            setName: "Base Set",
            collectorNumber: "004/102",
            pokemonPrintRun: .firstEdition
        )
        let unlimited = GradedCardIdentity(
            name: "Charizard",
            setName: "Base Set",
            collectorNumber: "004/102",
            pokemonPrintRun: .unlimited
        )

        XCTAssertNotEqual(
            firstEdition.groupingKey(game: .pokemon),
            unlimited.groupingKey(game: .pokemon)
        )
    }

    /// Mirrors the published `/v2/cards` response shape: card `id` is the UUID,
    /// game and set are objects, and the variant price is nested in `markets`.
    func testGradedCardResponseYieldsPricedVariants() throws {
        let json = """
        { "data": [ { "id": "9b2e4d1a-1111-5v5v-aaaa-000000000000",
            "slug": "pokemon-base-set-charizard-holo-rare", "name": "Charizard",
            "game": { "id": "pokemon", "name": "Pokemon" },
            "set": { "id": "base-set-pokemon", "name": "Base Set" },
            "number": "4", "rarity": "Rare Holo", "variants": [
              { "id": "d41f-psa10-uuid", "slug": "d41f-psa10-uuid",
                "type": "graded", "condition": null, "printing": "Holofoil",
                "language": null,
                "grading": { "company": "PSA", "grade": 10, "grade_label": null,
                  "qualifier": null, "canonical": "PSA 10" },
                "markets": [ { "region": "NA", "currency": "USD", "price": 4570.00,
                  "updated_at": 1765630000 } ] } ] } ] }
        """
        let response = try JSONDecoder().decode(JustTCGV2CardsResponse.self, from: Data(json.utf8))
        let card = try XCTUnwrap(response.data.first)
        let variant = try XCTUnwrap(card.variants?.first)
        let asked = GradedCardIdentity(
            name: "Charizard", setName: "Base Set", collectorNumber: "4/102"
        )

        XCTAssertTrue(asked.matches(card, game: .pokemon, expectedSetSlug: "base-set-pokemon"))
        XCTAssertTrue(asked.matches(
            card,
            variant: variant,
            game: .pokemon,
            expectedSetSlug: "base-set-pokemon"
        ))
        XCTAssertEqual(card.id, "9b2e4d1a-1111-5v5v-aaaa-000000000000")
        XCTAssertEqual(card.slug, "pokemon-base-set-charizard-holo-rare")
        XCTAssertEqual(variant.variantId, "d41f-psa10-uuid")
        XCTAssertEqual(variant.marketPriceUSD, 4570.00)
        XCTAssertEqual(variant.grading?.gradingCompany, .psa)
        XCTAssertEqual(variant.grading?.gradeText, "10")
    }

    // MARK: - Shared transport pacing

    /// A request that is abandoned while queued for the shared pacer must not
    /// consume quota. This exercises the transport boundary, rather than only
    /// the pacer's cancellation behavior, so a future reorder of `perform` is
    /// caught by the test.
    func testCancellationWhilePacingDoesNotReserveQuota() async throws {
        let suite = "JustTCGContractTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let ledger = JustTCGRequestLedger(defaults: defaults)
        let pacer = JustTCGPacer()
        try await pacer.wait(lane: .background, minimumInterval: 0)

        var configuration = JustTCGTransport.Configuration()
        configuration.baseURL = URL(string: "http://127.0.0.1:1")!
        configuration.minimumRequestInterval = 1
        let transport = JustTCGTransport(
            configuration: configuration,
            session: URLSession(configuration: .ephemeral),
            ledger: ledger,
            pacer: pacer,
            apiKeyOverride: "justtcg-test-key"
        )

        let request = Task {
            try await transport.get(
                "/test",
                lane: .background,
                as: EmptyJustTCGResponse.self
            )
        }
        try await Task.sleep(for: .milliseconds(20))
        request.cancel()

        do {
            _ = try await request.value
            XCTFail("a cancelled paced request must not succeed")
        } catch is CancellationError {
            // Expected: the request was cancelled while waiting for its slot.
        }

        let snapshot = await transport.snapshot()
        XCTAssertEqual(snapshot.usedToday, 0)
        XCTAssertEqual(snapshot.usedThisMonth, 0)
    }

    /// Interactive work is selected ahead of an already queued background
    /// waiter, so a long refresh cannot make a user-triggered lookup wait for
    /// the entire refresh queue.
    func testInteractivePacingPreemptsQueuedBackgroundWork() async throws {
        let pacer = JustTCGPacer()
        try await pacer.wait(lane: .background, minimumInterval: 0)

        let background = Task {
            try await pacer.wait(lane: .background, minimumInterval: 0.2)
            return Date.now
        }
        await Task.yield()
        try await Task.sleep(for: .milliseconds(20))

        let interactive = Task {
            try await pacer.wait(lane: .interactive, minimumInterval: 0.2)
            return Date.now
        }

        let interactiveGrantedAt = try await interactive.value
        let backgroundGrantedAt = try await background.value
        XCTAssertLessThan(
            interactiveGrantedAt,
            backgroundGrantedAt,
            "interactive work must not sit behind queued background work"
        )
    }

    /// Pacing must not change the transport's existing budget error mapping.
    func testBudgetReachedStillSurfacesAfterPacing() async throws {
        let suite = "JustTCGContractTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let ledger = JustTCGRequestLedger(defaults: defaults)
        for _ in 0..<JustTCGQuota.backgroundDailyCeiling {
            XCTAssertEqual(ledger.reserve(lane: .background), .allowed)
        }

        var configuration = JustTCGTransport.Configuration()
        configuration.baseURL = URL(string: "http://127.0.0.1:1")!
        configuration.minimumRequestInterval = 0
        let transport = JustTCGTransport(
            configuration: configuration,
            session: URLSession(configuration: .ephemeral),
            ledger: ledger,
            pacer: JustTCGPacer(),
            apiKeyOverride: "justtcg-test-key"
        )

        do {
            _ = try await transport.get(
                "/test",
                lane: .background,
                as: EmptyJustTCGResponse.self
            )
            XCTFail("an exhausted background budget must reject the request")
        } catch JustTCGTransport.TransportError.budgetReached {
            // Expected.
        }

        XCTAssertEqual(ledger.snapshot().usedToday, JustTCGQuota.backgroundDailyCeiling)
    }

    private struct EmptyJustTCGResponse: Decodable {}

    private func rfc1123Header(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
        return formatter.string(from: date)
    }

    func testSuccessfulTransportResponseUpdatesServerClockAndMissingHeaderKeepsIt() async throws {
        let suite = "JustTCGServerClock.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let deviceNow = Date.now
        let serverClock = JustTCGServerClock()
        RecordingURLProtocol.reset(
            headers: [
                "Content-Type": "application/json",
                "Date": rfc1123Header(for: deviceNow.addingTimeInterval(10 * 60))
            ]
        )

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RecordingURLProtocol.self]
        var transportConfiguration = JustTCGTransport.Configuration()
        transportConfiguration.baseURL = URL(string: "https://justtcg.test")!
        transportConfiguration.minimumRequestInterval = 0
        let transport = JustTCGTransport(
            configuration: transportConfiguration,
            session: URLSession(configuration: configuration),
            ledger: JustTCGRequestLedger(defaults: defaults),
            pacer: JustTCGPacer(),
            apiKeyOverride: "justtcg-test-key",
            serverClock: serverClock
        )

        _ = try await transport.get(
            "/clock",
            lane: .interactive,
            as: EmptyJustTCGResponse.self
        )

        let observedOffset = try XCTUnwrap(serverClock.serverClockOffset)
        XCTAssertEqual(observedOffset, 10 * 60, accuracy: 2)

        serverClock.observe(serverDateHeader: nil)
        XCTAssertEqual(serverClock.serverClockOffset, observedOffset)
        serverClock.observe(serverDateHeader: "not a date")
        XCTAssertEqual(serverClock.serverClockOffset, observedOffset)
    }

    func testGradedZapdos202LookupResolves151AndReturnsOnlyTheRequestedPrinting() async throws {
        let directory = ProductSetDirectoryProvider()
        let slug = "sv-scarlet-violet-151-pokemon"
        _ = try await directory.directory(for: .pokemon) {
            ProductSetDirectory(sets: [(id: slug, name: "SV: Scarlet & Violet 151")])
        }
        // Same name, three collector numbers: only the SIR in the screenshot
        // may supply slab handles or prices. Prices and handles are synthetic.
        let cards = [
            (number: "145/165", set: slug, game: "pokemon", handle: "wrong-art"),
            (number: "202/165", set: "other-set-pokemon", game: "pokemon", handle: "wrong-set"),
            (number: "202/165", set: slug, game: "pokemon-japan", handle: "wrong-game"),
            (number: "202/166", set: slug, game: "pokemon", handle: "wrong-total"),
            (number: "192/165", set: slug, game: "pokemon", handle: "wrong-rarity"),
            (number: "202/165", set: slug, game: "pokemon", handle: "fixture-psa10")
        ].map { row in
            """
            {"id":"\(row.handle)-card","name":"Zapdos ex - \(row.number)","number":"\(row.number)",
             "game":{"id":"\(row.game)"},"set":{"id":"\(row.set)","name":"SV: Scarlet & Violet 151"},
             "variants":[{"id":"\(row.handle)","type":"graded","printing":"Holofoil",
             "grading":{"company":"PSA","grade":10},
             "markets":[{"region":"NA","currency":"USD","price":123}]}]}
            """
        }
        RecordingURLProtocol.reset(body: "{\"data\":[\(cards.joined(separator: ","))]}")
        let client = try gradedFixtureClient(directory: directory)
        let result = try await client.lookup(identity: GradedCardIdentity(
            name: "Zapdos ex", setName: "151", collectorNumber: "202/165", catalogID: "sv03.5-202"
        ), game: .pokemon)

        guard case let .matched(variants) = result else {
            return XCTFail("The vendor's longer 151 set name must not become a card-not-found result: \(result)")
        }
        XCTAssertEqual(variants.map(\.id), ["fixture-psa10"])
        XCTAssertEqual(variants.first?.marketPriceUSD, 123)
        let requests = RecordingURLProtocol.recorded()
        XCTAssertEqual(requests.count, 1)
        let url = try XCTUnwrap(requests.first)
        XCTAssertEqual(url.path, "/v2/cards")
        let query = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        XCTAssertEqual(query.first { $0.name == "set" }?.value, slug)
        XCTAssertEqual(query.first { $0.name == "q" }?.value, "Zapdos ex")
        XCTAssertEqual(query.first { $0.name == "graded" }?.value, "only")
    }

    func testGradedSetNameSampleAcrossEightPokemonSets() async throws {
        // Catalog names/card identities come from the bundled checklist. Vendor
        // display names were checked against TCGplayer's published set pages.
        // Handles and prices are synthetic; this tests matching, not coverage.
        let samples: [(catalog: String, vendor: String, slug: String, card: String, id: String)] = [
            ("Sword & Shield", "SWSH01: Sword & Shield Base Set", "swsh01-sword-shield-base-set-pokemon", "Celebi V", "swsh1-1"),
            ("Evolving Skies", "SWSH07: Evolving Skies", "swsh07-evolving-skies-pokemon", "Pinsir", "swsh7-1"),
            ("Sun & Moon", "SM Base Set", "sm-base-set-pokemon", "Caterpie", "sm1-1"),
            ("Cosmic Eclipse", "SM - Cosmic Eclipse", "sm-cosmic-eclipse-pokemon", "Venusaur & Snivy GX", "sm12-1"),
            ("Paldea Evolved", "SV02: Paldea Evolved", "sv02-paldea-evolved-pokemon", "Hoppip", "sv02-001"),
            ("XY", "XY Base Set", "xy-base-set-pokemon", "Venusaur EX", "xy1-1"),
            ("Dragon", "EX Dragon", "ex-dragon-pokemon", "Absol", "ex3-1"),
            ("Prismatic Evolutions", "SV: Prismatic Evolutions", "sv-prismatic-evolutions-pokemon", "Exeggcute", "sv08.5-001")
        ]
        let directory = ProductSetDirectoryProvider()
        let sets = samples.map { (id: $0.slug, name: Optional($0.vendor)) }
        let published = try await directory.directory(for: .pokemon) {
            ProductSetDirectory(sets: sets)
        }
        let client = try gradedFixtureClient(directory: directory)
        var failures: [String] = []
        for sample in samples {
            let label = "\(sample.catalog) → \(sample.vendor)"
            let identity = GradedCardIdentity(name: sample.card, setName: sample.catalog,
                collectorNumber: "001", catalogID: sample.id)
            if JustTCGV2GradedClient.resolvedSetSlug(
                identity: identity, game: .pokemon, directory: published
            ) != sample.slug {
                failures.append("\(label): set did not resolve")
            }
            let body: [String: Any] = ["data": [[
                "id": "fixture-card", "name": sample.card, "number": "1",
                "game": ["id": "pokemon"], "set": ["id": sample.slug, "name": sample.vendor],
                "variants": [["id": "fixture-psa10", "type": "graded", "printing": "Holofoil",
                    "grading": ["company": "PSA", "grade": 10],
                    "markets": [["region": "NA", "currency": "USD", "price": 123]]]]
            ]]]
            let data = try JSONSerialization.data(withJSONObject: body)
            RecordingURLProtocol.reset(body: try XCTUnwrap(String(data: data, encoding: .utf8)))
            let result = try await client.lookup(identity: identity, game: .pokemon)
            guard case let .matched(variants) = result else {
                failures.append("\(label): \(result)")
                continue
            }
            XCTAssertEqual(variants.map(\.id), ["fixture-psa10"], label)
            XCTAssertEqual(variants.first?.marketPriceUSD, 123, label)
            let requests = RecordingURLProtocol.recorded()
            XCTAssertEqual(requests.count, 1, label)
            let query = try XCTUnwrap(URLComponents(url: XCTUnwrap(requests.first),
                resolvingAgainstBaseURL: false)?.queryItems)
            XCTAssertEqual(query.first { $0.name == "set" }?.value, sample.slug, label)
        }
        XCTAssertEqual(failures, [], "Every sampled set must resolve and accept its own graded listing")
    }

    func testGradedSetNameSampleAcrossFourMagicSets() async throws {
        // Scryfall names are pinned in MagicTreatmentSnapshot; vendor display
        // names were checked on TCGplayer. Prices and handles are synthetic.
        let samples: [(catalog: String, vendor: String, slug: String, card: String)] = [
            ("Forgotten Realms Commander", "Commander: Adventures in the Forgotten Realms",
             "commander-adventures-in-the-forgotten-realms-magic-the-gathering", "Galea, Kindler of Hope"),
            ("Warhammer 40,000 Commander", "Universes Beyond: Warhammer 40,000",
             "universes-beyond-warhammer-40000-magic-the-gathering", "Szarekh, the Silent King"),
            ("Tales of Middle-earth Commander", "Commander: The Lord of the Rings: Tales of Middle-earth",
             "commander-the-lord-of-the-rings-tales-of-middle-earth-magic-the-gathering", "Éowyn, Shieldmaiden"),
            ("Fallout", "Universes Beyond: Fallout", "universes-beyond-fallout-magic-the-gathering",
             "Caesar, Legion's Emperor")
        ]
        let directory = ProductSetDirectoryProvider()
        let sets = samples.map { (id: $0.slug, name: Optional($0.vendor)) }
        let published = try await directory.directory(for: .magic) { ProductSetDirectory(sets: sets) }
        let client = try gradedFixtureClient(directory: directory)
        var failures: [String] = []
        for sample in samples {
            let label = "\(sample.catalog) → \(sample.vendor)"
            let identity = GradedCardIdentity(name: sample.card, setName: sample.catalog, collectorNumber: "1")
            if JustTCGV2GradedClient.resolvedSetSlug(identity: identity, game: .magic, directory: published) != sample.slug {
                failures.append("\(label): set did not resolve")
            }
            let body: [String: Any] = ["data": [[
                "id": "fixture-card", "name": sample.card, "number": "1",
                "game": ["id": "magic-the-gathering"], "set": ["id": sample.slug, "name": sample.vendor],
                "variants": [["id": "fixture-psa10", "type": "graded", "printing": "Foil",
                    "grading": ["company": "PSA", "grade": 10],
                    "markets": [["region": "NA", "currency": "USD", "price": 123]]]]
            ]]]
            let bytes = try JSONSerialization.data(withJSONObject: body)
            RecordingURLProtocol.reset(body: try XCTUnwrap(String(data: bytes, encoding: .utf8)))
            let result = try await client.lookup(identity: identity, game: .magic)
            guard case let .matched(variants) = result else {
                failures.append("\(label): \(result)"); continue
            }
            XCTAssertEqual(variants.map(\.id), ["fixture-psa10"], label)
            XCTAssertEqual(variants.first?.marketPriceUSD, 123, label)
            let requests = RecordingURLProtocol.recorded()
            XCTAssertEqual(requests.count, 1, label)
            let query = try XCTUnwrap(URLComponents(url: XCTUnwrap(requests.first),
                resolvingAgainstBaseURL: false)?.queryItems)
            XCTAssertEqual(query.first { $0.name == "set" }?.value, sample.slug, label)
        }
        XCTAssertEqual(failures, [], "Every sampled Magic set must resolve and match its own graded listing")
    }

    func testGradedSearchFindsSpinarakOnLaterPage() async throws {
        let directory = ProductSetDirectoryProvider()
        _ = try await directory.directory(for: .pokemon) {
            ProductSetDirectory(sets: [(id: "team-rocket-returns-pokemon", name: "Team Rocket Returns")])
        }
        RecordingURLProtocol.reset(headers: ["Link": "<https://api.justtcg.com/v2/cards?cursor=page2>; rel=\"next\""])
        RecordingURLProtocol.laterPageBody = Data(#"{"data":[{"id":"fixture-card","name":"Spinarak","number":"78","game":{"id":"pokemon"},"set":{"id":"team-rocket-returns-pokemon","name":"Team Rocket Returns"},"variants":[{"id":"fixture-cgc10","type":"graded","printing":"Normal","grading":{"company":"CGC","grade":10,"grade_label":"Gem Mint"},"markets":[{"region":"NA","currency":"USD","price":40}]}]}]}"#.utf8)
        let sessionConfig = URLSessionConfiguration.ephemeral
        sessionConfig.protocolClasses = [RecordingURLProtocol.self]
        var config = JustTCGTransport.Configuration()
        config.minimumRequestInterval = 0
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "pagination-fixture-\(UUID())"))
        let client = JustTCGV2GradedClient(transport: JustTCGTransport(configuration: config,
            session: URLSession(configuration: sessionConfig), ledger: JustTCGRequestLedger(defaults: defaults),
            pacer: JustTCGPacer(), apiKeyOverride: "synthetic-key"), setDirectoryProvider: directory)
        let result = try await client.lookup(identity: GradedCardIdentity(name: "Spinarak",
            setName: "Team Rocket Returns", collectorNumber: "78", catalogID: "ex7-78"), game: .pokemon)
        guard case let .matched(values) = result else { return XCTFail("A first-page miss is not a complete search") }
        XCTAssertEqual(values.map(\.id), ["fixture-cgc10"])
        XCTAssertEqual(RecordingURLProtocol.recorded().count, 2)
    }

    func testGradedPaginationIncompleteAndLocalFailureAreNotCardMisses() async throws {
        let identity = GradedCardIdentity(name: "Spinarak", setName: "Team Rocket Returns",
            collectorNumber: "78", catalogID: "ex7-78", pokemonPrintRun: .unlimited, finish: .normal)
        for maximumPages in [1, 3] {
            let directory = ProductSetDirectoryProvider()
            _ = try await directory.directory(for: .pokemon) {
                ProductSetDirectory(sets: [(id: "team-rocket-returns-pokemon", name: "Team Rocket Returns")])
            }
            // The same cursor on every page models an upstream pagination loop.
            RecordingURLProtocol.reset(headers: ["Link": "<https://api.justtcg.com/v2/cards?cursor=repeated>; rel=\"next\""])
            let client = try gradedFixtureClient(directory: directory, maximumPages: maximumPages)
            let result = try await client.lookup(identity: identity, game: .pokemon)
            XCTAssertEqual(result, .incompleteSearch)
            XCTAssertEqual(RecordingURLProtocol.recorded().count, maximumPages == 1 ? 1 : 2)
        }
        let directory = ProductSetDirectoryProvider()
        _ = try await directory.directory(for: .pokemon) { ProductSetDirectory(sets: []) }
        RecordingURLProtocol.reset()
        let client = try gradedFixtureClient(directory: directory)
        let result = try await client.lookup(identity: identity, game: .pokemon)
        XCTAssertEqual(result, .localIdentityUnresolved)
        XCTAssertTrue(RecordingURLProtocol.recorded().isEmpty)
    }

    func testGradedNextLinksOnlyContributeAValidatedCursor() throws {
        XCTAssertEqual(try JustTCGV2GradedClient.nextCursor(from:
            "<https://api.justtcg.com/v2/cards?q=untrusted&cursor=page2>; rel = \"next\""), "page2")
        for url in ["https://evil.test/v2/cards?cursor=x", "http://api.justtcg.com/v2/cards?cursor=x",
                    "https://api.justtcg.com/v1/cards?cursor=x", "https://api.justtcg.com/v2/cards?cursor=x&cursor=y",
                    "https://user@api.justtcg.com/v2/cards?cursor=x"] {
            XCTAssertThrowsError(try JustTCGV2GradedClient.nextCursor(from: "<\(url)>; rel=\"next\""))
        }
    }

    func testGradedBudgetExhaustionDoesNotBecomeProviderAbsence() async throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "graded-budget-fixture-\(UUID())"))
        let ledger = JustTCGRequestLedger(defaults: defaults)
        for _ in 0..<JustTCGQuota.dailyHardLimit { _ = ledger.reserve(lane: .interactive) }
        RecordingURLProtocol.reset()
        let sessionConfig = URLSessionConfiguration.ephemeral
        sessionConfig.protocolClasses = [RecordingURLProtocol.self]
        var config = JustTCGTransport.Configuration()
        config.minimumRequestInterval = 0
        let client = JustTCGV2GradedClient(transport: JustTCGTransport(configuration: config,
            session: URLSession(configuration: sessionConfig), ledger: ledger, pacer: JustTCGPacer(),
            apiKeyOverride: "synthetic-key"), setDirectoryProvider: ProductSetDirectoryProvider())
        let result = try await client.lookup(identity: GradedCardIdentity(name: "Spinarak",
            setName: "Team Rocket Returns", collectorNumber: "78", catalogID: "ex7-78"), game: .pokemon)
        XCTAssertEqual(result, .incompleteSearch)
        XCTAssertTrue(RecordingURLProtocol.recorded().isEmpty)
    }

    func testEveryReviewedUnownAndFutsalCardUsesItsOwnExactGradedProduct() async throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "pokemon-subset-product-proof", withExtension: "json",
            subdirectory: "TradingCards/SetPricingAudit"))
        let document = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let cases = try XCTUnwrap(document["cases"] as? [[String: Any]])
        XCTAssertEqual(cases.count, 33)
        var sourceIDs = Set<String>()
        for entry in cases {
            let source = try JSONDecoder().decode(TCGdexCard.self,
                from: JSONSerialization.data(withJSONObject: XCTUnwrap(entry["source"])))
            sourceIDs.insert(source.id)
            XCTAssertEqual(source.catalogVariants, [.holo])
            var vendor = try XCTUnwrap(entry["vendor"] as? [String: Any])
            let product = try XCTUnwrap((vendor["external_ids"] as? [String: String])?["tcgplayer"])
            XCTAssertEqual(CardPricing.tcgplayerProductID(for: .pokemon(source, setCode: ""),
                variant: .holo, printRun: .unlimited).map(String.init), product)
            vendor["variants"] = [["id": "reviewed-holo-slab", "type": "graded", "printing": "Holofoil",
                "grading": ["company": "PSA", "grade": 10],
                "markets": [["region": "NA", "currency": "USD", "price": 123]]]]
            let body = String(decoding: try JSONSerialization.data(withJSONObject: ["data": [vendor]]), as: UTF8.self)
            for run: PokemonPrintRun? in [nil, .unlimited] {
                RecordingURLProtocol.reset(body: body)
                let client = try gradedFixtureClient(directory: ProductSetDirectoryProvider())
                let identity = GradedCardIdentity(name: source.name, setName: source.set.name,
                    collectorNumber: source.localId, catalogID: source.id, pokemonPrintRun: run, finish: .holo)
                let result = try await client.lookup(identity: identity, game: .pokemon)
                guard case let .matched(variants) = result else { XCTFail("\(source.id): \(result)"); continue }
                XCTAssertEqual(variants.map(\.id), ["reviewed-holo-slab"], source.id)
                XCTAssertEqual(variants.first?.cardID, vendor["id"] as? String, source.id)
                XCTAssertEqual(RecordingURLProtocol.recorded().count, 1, "Reviewed subsets skip name/set lookup")
                let query = try XCTUnwrap(URLComponents(url: XCTUnwrap(RecordingURLProtocol.recorded().first), resolvingAgainstBaseURL: false)?.queryItems)
                XCTAssertEqual(query.first { $0.name == "tcgplayer_id" }?.value, product, source.id)
                XCTAssertEqual(query.first { $0.name == "game" }?.value, "pokemon", source.id)
                XCTAssertNil(query.first { $0.name == "q" })
                XCTAssertNil(query.first { $0.name == "set" })
            }
        }
        XCTAssertEqual(sourceIDs, ReviewedPokemonProductIdentity.catalogIDs.filter { !$0.hasPrefix("xya-") })
    }

    func testReviewedPokemonSubsetRefusesWrongMetadataEditionAndFinish() async throws {
        let valid = GradedCardIdentity(name: "Unown", setName: "Unseen Forces Unown Collection",
            collectorNumber: "A/28", catalogID: "exu-A", pokemonPrintRun: .unlimited, finish: .holo)
        XCTAssertNotNil(try ReviewedPokemonProductIdentity(identity: valid))
        let invalid = [
            GradedCardIdentity(name: "Unown", setName: valid.setName, collectorNumber: "B/28", catalogID: "exu-A"),
            GradedCardIdentity(name: "Unown", setName: valid.setName, collectorNumber: "A/29", catalogID: "exu-A"),
            GradedCardIdentity(name: "Pikachu", setName: valid.setName, collectorNumber: "A", catalogID: "exu-A"),
            GradedCardIdentity(name: "Unown", setName: "Unseen Forces", collectorNumber: "A", catalogID: "exu-A"),
            GradedCardIdentity(name: "Unown", setName: valid.setName, collectorNumber: "A", catalogID: "exu-A", pokemonPrintRun: .firstEdition),
            GradedCardIdentity(name: "Unown", setName: valid.setName, collectorNumber: "A", catalogID: "exu-A", pokemonPrintRun: .shadowless),
            GradedCardIdentity(name: "Unown", setName: valid.setName, collectorNumber: "A", catalogID: "exu-A", finish: .reverse),
            GradedCardIdentity(name: "Unown", setName: valid.setName, collectorNumber: "A", catalogID: "exu-A", finish: .normal)
        ]
        let client = try gradedFixtureClient(directory: ProductSetDirectoryProvider())
        for identity in invalid {
            RecordingURLProtocol.reset()
            let result = try await client.lookup(identity: identity, game: .pokemon)
            XCTAssertEqual(result, .localIdentityUnresolved)
            XCTAssertTrue(RecordingURLProtocol.recorded().isEmpty)
        }
        XCTAssertNil(try ReviewedPokemonProductIdentity(identity: .init(name: "Unown",
            setName: valid.setName, collectorNumber: "A", catalogID: "exu-not-reviewed")))
        XCTAssertNotEqual(CatalogIdentityNormalization.canonicalSetName(valid.setName, game: .pokemon),
            CatalogIdentityNormalization.canonicalSetName("Unseen Forces", game: .pokemon))
        XCTAssertNotEqual(CatalogIdentityNormalization.canonicalSetName("Pokémon Futsal 2020", game: .pokemon),
            CatalogIdentityNormalization.canonicalSetName("Miscellaneous Cards & Products", game: .pokemon))
    }

    func testEncodedUnownQuestionMarkIsScopedToItsReviewedProviderIdentity() throws {
        for number in ["%3F", "%3f/28", "?", "?/28"] {
            let context = try XCTUnwrap(ReviewedPokemonProductIdentity(identity: .init(name: "Unown",
                setName: "Unseen Forces Unown Collection", collectorNumber: number, catalogID: "exu-%3F")))
            XCTAssertEqual(context.productIDs, ["90167"])
        }
        for number in ["%3F/29", "?/29", "%3Q", "A", "%253F"] {
            XCTAssertThrowsError(try ReviewedPokemonProductIdentity(identity: .init(name: "Unown",
                setName: "Unseen Forces Unown Collection", collectorNumber: number, catalogID: "exu-%3F")))
        }
        XCTAssertFalse(ProductCatalogIdentity.numbersMatch("%3F", "?"), "Printed numbers are not globally URL-decoded")
    }

    func testReviewedPokemonExactProductRejectsOtherLettersLanguagesAndFinishes() throws {
        let context = try XCTUnwrap(ReviewedPokemonProductIdentity(identity: .init(name: "Unown",
            setName: "Unseen Forces Unown Collection", collectorNumber: "A", catalogID: "exu-A")))
        var card: [String: Any] = ["id": "card", "name": "Unown (A)", "number": "A/28",
            "game": ["id": "pokemon"], "external_ids": ["tcgplayer": "90168"]]
        func matches(_ card: [String: Any]) throws -> Bool {
            context.matches(try JSONDecoder().decode(JustTCGV2Card.self, from: JSONSerialization.data(withJSONObject: card)))
        }
        XCTAssertTrue(try matches(card))
        card["external_ids"] = ["tcgplayer": "90169"]
        XCTAssertFalse(try matches(card), "Unown B cannot price Unown A even with A's printed number")
        card["external_ids"] = ["tcgplayer": "90168"]; card["game"] = ["id": "pokemon-japan"]
        XCTAssertFalse(try matches(card))
        for (printing, type, language, admitted) in [
            ("Holofoil", "graded", "en", true), ("Holofoil", "graded", "Japanese", false),
            ("Reverse Holofoil", "graded", "en", false), ("Normal", "graded", "en", false),
            ("1st Edition Holofoil", "graded", "en", false), ("Holofoil", "raw", "en", false)
        ] {
            let variant = try JSONDecoder().decode(JustTCGVariant.self, from: JSONSerialization.data(withJSONObject:
                ["id": "slab", "type": type, "printing": printing, "language": language]))
            XCTAssertEqual(context.admits(variant, productID: "90168", requestedFinish: .holo), admitted, printing)
            XCTAssertFalse(context.admits(variant, productID: "90169", requestedFinish: .holo))
        }
    }

    func testYellowAWholeSetReconcilesGeneratedFinishesAndExactProducts() async throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "pokemon-yellow-a-product-proof", withExtension: "json",
            subdirectory: "TradingCards/SetPricingAudit"))
        let document = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let cases = try XCTUnwrap(document["cases"] as? [[String: Any]])
        XCTAssertEqual(cases.count, 6)
        var seen = Set<String>(), laneCount = 0
        for entry in cases {
            let source = try JSONDecoder().decode(TCGdexCard.self,
                from: JSONSerialization.data(withJSONObject: XCTUnwrap(entry["source"])))
            let card = IdentifiedCard.pokemon(source, setCode: "")
            seen.insert(source.id)
            let products = try XCTUnwrap(entry["products"] as? [[String: Any]])
            let expectedFinishes = products.compactMap { ($0["finish"] as? String).map(PhysicalVariant.resolving) }
            XCTAssertEqual(source.variants?.normal, true, "Retain the upstream generated flag as evidence")
            XCTAssertEqual(Set(source.catalogVariants), Set(expectedFinishes), source.id)
            XCTAssertFalse(source.catalogVariants.contains(.reverse))
            var vendors: [String: [String: Any]] = [:]
            for product in products {
                laneCount += 1
                let finish = PhysicalVariant.resolving(try XCTUnwrap(product["finish"] as? String))
                let printing = try XCTUnwrap(product["printing"] as? String)
                var vendor = try XCTUnwrap(product["vendor"] as? [String: Any])
                let id = try XCTUnwrap((vendor["external_ids"] as? [String: String])?["tcgplayer"])
                XCTAssertEqual(CardPricing.tcgplayerProductID(for: card, variant: finish, printRun: .unlimited).map(String.init), id)
                XCTAssertEqual(TCGplayerLinkBuilder.url(for: card, variant: finish)?.path, "/product/" + id)
                let total = try XCTUnwrap((vendor["number"] as? String)?.split(separator: "/").last.flatMap { Int($0) })
                XCTAssertEqual(card.displayCardNumber, "\(source.localId)/\(total)")
                XCTAssertEqual(card.cardNumber, source.localId)
                vendor["variants"] = [["id": id + "-slab", "type": "graded", "printing": printing,
                    "grading": ["company": "PSA", "grade": 10],
                    "markets": [["region": "NA", "currency": "USD", "price": 123]]],
                    ["id": "wrong-finish", "type": "graded", "printing": printing == "Normal" ? "Holofoil" : "Normal",
                     "grading": ["company": "PSA", "grade": 10]]]
                vendors[id] = vendor
                RecordingURLProtocol.reset(body: String(decoding: try JSONSerialization.data(withJSONObject: ["data": [vendor]]), as: UTF8.self))
                let client = try gradedFixtureClient(directory: ProductSetDirectoryProvider())
                let result = try await client.lookup(identity: .init(name: source.name, setName: source.set.name,
                    collectorNumber: source.localId, catalogID: source.id, pokemonPrintRun: .unlimited, finish: finish), game: .pokemon)
                guard case let .matched(values) = result else { XCTFail("\(source.id) \(finish): \(result)"); continue }
                XCTAssertEqual(values.map(\.id), [id + "-slab"])
                XCTAssertEqual(RecordingURLProtocol.recorded().count, 1)
            }
            let identity = GradedCardIdentity(name: source.name, setName: source.set.name,
                collectorNumber: source.localId, catalogID: source.id)
            let context = try XCTUnwrap(ReviewedPokemonProductIdentity(identity: identity))
            let ordered = context.productIDs.map { vendors[$0]! }
            RecordingURLProtocol.reset(body: String(decoding: try JSONSerialization.data(withJSONObject: ["data": [ordered[0]]]), as: UTF8.self))
            if ordered.count > 1 {
                RecordingURLProtocol.laterPageBody = try JSONSerialization.data(withJSONObject: ["data": [ordered[1]]])
            }
            let client = try gradedFixtureClient(directory: ProductSetDirectoryProvider())
            let result = try await client.lookup(identity: identity, game: .pokemon)
            guard case let .matched(values) = result else { XCTFail("Whole finish discovery: \(source.id)"); continue }
            XCTAssertEqual(Set(values.map(\.id)), Set(context.productIDs.map { $0 + "-slab" }))
            XCTAssertEqual(RecordingURLProtocol.recorded().count, products.count)
            XCTAssertNil(CardPricing.tcgplayerProductID(for: card, variant: .reverse, printRun: nil))
            if products.count == 1 {
                XCTAssertTrue(PokemonVariantRules.requiresPhysicalReview(cardID: source.id, variant: .normal))
                guard case .unavailable = CardPricing.price(for: card, variant: .normal, magicTreatments: []) else {
                    XCTFail("Generated Normal must not price a reviewed EX Holofoil")
                    continue
                }
                var conflicting = try XCTUnwrap(entry["source"] as? [String: Any])
                var detail = try XCTUnwrap((conflicting["variants_detailed"] as? [[String: Any]])?.first)
                detail["pricing"] = ["tcgplayer": ["normal": ["productId": Int(context.productIDs[0])!, "marketPrice": 999]]]
                conflicting["variants_detailed"] = [detail]
                let stale = try JSONDecoder().decode(TCGdexCard.self, from: JSONSerialization.data(withJSONObject: conflicting))
                guard case .unavailable = CardPricing.price(for: .pokemon(stale, setCode: ""), variant: .normal, magicTreatments: []) else {
                    XCTFail("A conflicting detailed quote cannot override the reviewed physical finish")
                    continue
                }
            }
        }
        XCTAssertEqual(laneCount, 8)
        XCTAssertEqual(seen, ReviewedPokemonProductIdentity.catalogIDs.filter { $0.hasPrefix("xya-") })
    }

    func testYellowANumberReconciliationPreservesSuffixAndActualPrintedTotal() throws {
        for number in ["24a", "024a", "24a/119", "024a/119"] {
            let identity = GradedCardIdentity(name: "M Manectric-EX", setName: "Yellow A Alternate",
                collectorNumber: number, catalogID: "xya-24a", finish: .holo)
            XCTAssertEqual(try ReviewedPokemonProductIdentity(identity: identity)?.productIDs, ["131696"])
        }
        for number in ["24", "24b", "24a/6", "24a/120"] {
            XCTAssertThrowsError(try ReviewedPokemonProductIdentity(identity: .init(name: "M Manectric-EX",
                setName: "Yellow A Alternate", collectorNumber: number, catalogID: "xya-24a", finish: .holo)))
        }
        XCTAssertThrowsError(try ReviewedPokemonProductIdentity(identity: .init(name: "M Manectric-EX",
            setName: "Yellow A Alternate", collectorNumber: "24a", catalogID: "xya-24a", finish: .normal)))
        XCTAssertFalse(ProductCatalogIdentity.numbersMatch("24a", "024a"), "No global suffix-number relaxation")
        XCTAssertNil(PokemonVariantRules.reviewedVariants(cardID: "xya-999"))
    }

    func testExactMagicProductLookupAcrossAllReviewedReleaseFamilies() async throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "magic-direct-product-proof", withExtension: "json",
            subdirectory: "TradingCards/SetPricingAudit"))
        let document = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let cases = try XCTUnwrap(document["cases"] as? [[String: Any]])
        XCTAssertEqual(cases.count, 103)
        XCTAssertEqual(Set(cases.compactMap { $0["code"] as? String }).count, 52)
        for entry in cases {
            let source = try JSONDecoder().decode(ScryfallCard.self, from: JSONSerialization.data(withJSONObject: XCTUnwrap(entry["source"])))
            var vendor = try XCTUnwrap(entry["vendor"] as? [String: Any])
            let finish = try XCTUnwrap(source.finishes?.first)
            let printing = finish == "foil" ? "Foil" : finish == "etched" ? "Etched Foil" : "Normal"
            vendor["variants"] = [["id": "fixture-slab", "type": "graded", "printing": printing,
                "grading": ["company": "PSA", "grade": 10],
                "markets": [["region": "NA", "currency": "USD", "price": 123]]]]
            let body = try JSONSerialization.data(withJSONObject: ["data": [vendor]])
            RecordingURLProtocol.reset(body: try XCTUnwrap(String(data: body, encoding: .utf8)))
            let client = try gradedFixtureClient(directory: ProductSetDirectoryProvider(), magicCardLoader: { id in
                guard id == source.id else { throw ScryfallError.identityMismatch }
                return source
            })
            let identity = GradedCardIdentity(name: source.name, setName: source.setName,
                collectorNumber: source.collectorNumber, catalogID: source.id, finish: .resolving(finish))
            let result = try await client.lookup(identity: identity, game: .magic, companies: [.psa], grades: ["10"])
            guard case let .matched(variants) = result else {
                XCTFail("\(entry["code"] ?? ""): \(source.name) \(source.collectorNumber): \(result)"); continue
            }
            XCTAssertEqual(variants.map(\.id), ["fixture-slab"], source.name)
            XCTAssertEqual(variants.first?.marketPriceUSD, 123, source.name)
            let requests = RecordingURLProtocol.recorded()
            XCTAssertEqual(requests.count, 1, "Exact product lookup must skip the set directory")
            let query = try XCTUnwrap(URLComponents(url: XCTUnwrap(requests.first), resolvingAgainstBaseURL: false)?.queryItems)
            XCTAssertEqual(query.first { $0.name == "tcgplayer_id" }?.value, source.tcgplayerID.map(String.init))
            XCTAssertNil(query.first { $0.name == "q" })
            XCTAssertNil(query.first { $0.name == "set" })
            XCTAssertEqual(query.first { $0.name == "graded" }?.value, "only")
            XCTAssertEqual(query.first { $0.name == "grading_company" }?.value, "PSA")
            XCTAssertEqual(query.first { $0.name == "grade" }?.value, "10")
        }
    }

    func testMagicProductIdentityRejectsConflictingCatalogEvidence() throws {
        let fixture = try directMagicFixture()
        let source = try decodeMagicSource(fixture.source)
        let identity = GradedCardIdentity(name: source.name, setName: source.setName,
            collectorNumber: source.collectorNumber, catalogID: source.id)
        _ = try MagicGradedProductIdentity(identity: identity, card: source)
        let changes: [(String, Any)] = [
            ("id", UUID().uuidString), ("object", "not-card"), ("name", "Another card"),
            ("set_name", "Another release"), ("collector_number", "999wrong"),
            ("lang", "ja"), ("digital", true), ("games", ["arena"]), ("oversized", true),
            ("layout", "vanguard"), ("layout", "token"), ("released_at", "2999-01-01"),
            ("finishes", []), ("finishes", ["foil", "foil"]), ("finishes", ["unknown"])
        ]
        for (key, value) in changes {
            var changed = fixture.source; changed[key] = value
            XCTAssertThrowsError(try MagicGradedProductIdentity(identity: identity, card: decodeMagicSource(changed)), key)
        }
        XCTAssertThrowsError(try MagicGradedProductIdentity(identity: .init(name: source.name,
            setName: source.setName, collectorNumber: source.collectorNumber, catalogID: source.id,
            pokemonPrintRun: .unlimited), card: source))
        let unavailable = source.finishes?.contains("etched") == true ? "nonexistent" : "etched"
        XCTAssertThrowsError(try MagicGradedProductIdentity(identity: .init(name: source.name,
            setName: source.setName, collectorNumber: source.collectorNumber, catalogID: source.id,
            finish: .resolving(unavailable)), card: source))
    }

    func testMagicProductIdentityRequiresReturnedProductGameAndSourceAgreement() throws {
        let fixture = try directMagicFixture()
        let source = try decodeMagicSource(fixture.source)
        let context = try MagicGradedProductIdentity(identity: .init(name: source.name,
            setName: source.setName, collectorNumber: source.collectorNumber, catalogID: source.id), card: source)
        func matches(_ vendor: [String: Any]) throws -> Bool {
            context.matches(try JSONDecoder().decode(JustTCGV2Card.self,
                from: JSONSerialization.data(withJSONObject: vendor)))
        }
        XCTAssertTrue(try matches(fixture.vendor))
        for (key, value) in [("external_ids", ["tcgplayer": "wrong"] as Any),
                             ("external_ids", NSNull()), ("game", ["id": "pokemon"]),
                             ("game", NSNull()), ("name", "Another card"), ("id", "")] {
            var changed = fixture.vendor; changed[key] = value
            XCTAssertFalse(try matches(changed), key)
        }
        var changed = fixture.vendor
        changed["external_ids"] = ["tcgplayer": context.productID!, "scryfall": UUID().uuidString]
        XCTAssertFalse(try matches(changed))
        changed["external_ids"] = ["tcgplayer": source.tcgplayerID!, "scryfall": source.id] as [String: Any]
        XCTAssertTrue(try matches(changed), "Numeric wire product IDs still bind the exact product")
        changed["number"] = "vendor-number-convention"
        changed["set"] = ["id": "shared-promos", "name": "Shared vendor group"]
        XCTAssertTrue(try matches(changed), "Verified product identity outranks vendor display conventions")
    }

    func testMagicProductVariantAdmissionPreservesLanguageFinishAndGradedType() throws {
        let fixture = try directMagicFixture()
        let source = try decodeMagicSource(fixture.source)
        let context = try MagicGradedProductIdentity(identity: .init(name: source.name,
            setName: source.setName, collectorNumber: source.collectorNumber, catalogID: source.id), card: source)
        let finish = try XCTUnwrap(source.finishes?.first)
        let printing = finish == "foil" ? "Foil" : finish == "etched" ? "Etched Foil" : "Normal"
        func admits(_ values: [String: Any]) throws -> Bool {
            context.admits(try JSONDecoder().decode(JustTCGVariant.self,
                from: JSONSerialization.data(withJSONObject: values)), requestedFinish: .resolving(finish))
        }
        let valid: [String: Any] = ["id": "slab", "type": "graded", "printing": printing]
        XCTAssertTrue(try admits(valid))
        XCTAssertEqual(finish, "nonfoil")
        let legacy = try MagicGradedProductIdentity(identity: .init(name: source.name, setName: source.setName,
            collectorNumber: source.collectorNumber, catalogID: source.id, finish: .normal), card: source)
        XCTAssertEqual(legacy.productIDs, context.productIDs, "Legacy Normal is the same Magic nonfoil finish")
        for (key, value) in [("type", "raw"), ("language", "Japanese"), ("printing", "Unknown"),
                             ("printing", finish == "foil" ? "Normal" : "Foil")] {
            var changed = valid; changed[key] = value
            XCTAssertFalse(try admits(changed), key)
        }
    }

    func testExactMagicProductCannotFallBackToAnUnverifiedReturnedCard() async throws {
        let fixture = try directMagicFixture()
        let source = try decodeMagicSource(fixture.source)
        let identity = GradedCardIdentity(name: source.name, setName: source.setName,
            collectorNumber: source.collectorNumber, catalogID: source.id)
        var vendor = fixture.vendor
        vendor["name"] = source.name; vendor["number"] = source.collectorNumber
        vendor["set"] = ["id": "same-set", "name": source.setName]
        vendor["external_ids"] = ["tcgplayer": "wrong-product"]
        RecordingURLProtocol.reset(body: String(decoding: try JSONSerialization.data(withJSONObject: ["data": [vendor]]), as: UTF8.self))
        let client = try gradedFixtureClient(directory: ProductSetDirectoryProvider(), magicCardLoader: { _ in source })
        let rejected = try await client.lookup(identity: identity, game: .magic)
        XCTAssertEqual(rejected, .noProductMatch)
        vendor["external_ids"] = ["tcgplayer": String(source.tcgplayerID!)]
        RecordingURLProtocol.reset(body: String(decoding: try JSONSerialization.data(withJSONObject: ["data": [vendor, vendor]]), as: UTF8.self))
        let ambiguous = try await client.lookup(identity: identity, game: .magic)
        XCTAssertEqual(ambiguous, .incompleteSearch)
        XCTAssertEqual(RecordingURLProtocol.recorded().count, 1)
        vendor["variants"] = Array(repeating: ["id": "same-slab", "type": "graded", "printing": "Normal",
            "grading": ["company": "PSA", "grade": 10]] as [String: Any], count: 2)
        RecordingURLProtocol.reset(body: String(decoding: try JSONSerialization.data(withJSONObject: ["data": [vendor]]), as: UTF8.self))
        let duplicateVariant = try await client.lookup(identity: identity, game: .magic)
        XCTAssertEqual(duplicateVariant, .incompleteSearch)
    }

    func testUnresolvedMagicCatalogEvidenceDoesNotRequestVendorData() async throws {
        let fixture = try directMagicFixture()
        let source = try decodeMagicSource(fixture.source)
        let identity = GradedCardIdentity(name: "Conflicting imported name", setName: source.setName,
            collectorNumber: source.collectorNumber, catalogID: source.id)
        RecordingURLProtocol.reset()
        let client = try gradedFixtureClient(directory: ProductSetDirectoryProvider(), magicCardLoader: { _ in source })
        let result = try await client.lookup(identity: identity, game: .magic)
        XCTAssertEqual(result, .localIdentityUnresolved)
        XCTAssertTrue(RecordingURLProtocol.recorded().isEmpty)
    }

    func testMagicWithoutSourceProductIDRetainsStrictNameSetNumberFallback() async throws {
        let fixture = try directMagicFixture()
        var values = fixture.source; values["tcgplayer_id"] = NSNull()
        let source = try decodeMagicSource(values)
        let directory = ProductSetDirectoryProvider()
        _ = try await directory.directory(for: .magic) {
            ProductSetDirectory(sets: [(id: "source-set", name: source.setName)])
        }
        var vendor = fixture.vendor
        vendor["number"] = source.collectorNumber
        vendor["name"] = source.name
        vendor["set"] = ["id": "source-set", "name": source.setName]
        RecordingURLProtocol.reset(body: String(decoding: try JSONSerialization.data(withJSONObject: ["data": [vendor]]), as: UTF8.self))
        let client = try gradedFixtureClient(directory: directory, magicCardLoader: { _ in source })
        let result = try await client.lookup(identity: .init(name: source.name, setName: source.setName,
            collectorNumber: source.collectorNumber, catalogID: source.id), game: .magic)
        XCTAssertEqual(result, .cardFoundWithoutGradedVariants)
        let query = try XCTUnwrap(URLComponents(url: XCTUnwrap(RecordingURLProtocol.recorded().first), resolvingAgainstBaseURL: false)?.queryItems)
        XCTAssertNil(query.first { $0.name == "tcgplayer_id" })
        XCTAssertEqual(query.first { $0.name == "set" }?.value, "source-set")
    }

    func testAllFortyTimeshiftPrintingsKeepEtchedAndFoilProductsSeparate() async throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "magic-direct-product-proof", withExtension: "json",
            subdirectory: "TradingCards/SetPricingAudit"))
        let document = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let entries = try XCTUnwrap(document["etchedCases"] as? [[String: Any]])
        XCTAssertEqual(entries.count, 40)
        for entry in entries {
            let source = try decodeMagicSource(XCTUnwrap(entry["source"] as? [String: Any]))
            let raw = IdentifiedCard.magic(source)
            for (finish, product) in [(PhysicalVariant.foil, source.tcgplayerID!), (.etched, source.tcgplayerEtchedID!)] {
                XCTAssertEqual(CardPricing.tcgplayerProductID(for: raw, variant: finish, printRun: nil), product)
                XCTAssertEqual(PriceFallbackQuoteResolver.directLookups(card: raw, variant: finish), [.tcgplayerID(String(product))])
                XCTAssertEqual(CardMarketHistoryRequest(card: raw, variant: finish, printRun: nil).exactProductID, String(product))
                let link = try XCTUnwrap(TCGplayerLinkBuilder.url(for: raw, variant: finish))
                XCTAssertEqual(link.path, "/product/\(product)")
                let row = CollectedCard(card: raw, resolved: .init(variant: finish, resolution: .userConfirmed))
                XCTAssertEqual(TCGplayerLinkBuilder.url(for: row), link)
                row.tcgplayerURL = "https://www.tcgplayer.com/product/incorrect"
                row.applyCatalogMetadata(from: raw)
                XCTAssertEqual(TCGplayerLinkBuilder.url(for: row), link)
            }
            XCTAssertTrue(PriceFallbackQuoteResolver.directLookups(card: raw, variant: nil).isEmpty)
            XCTAssertNil(TCGplayerLinkBuilder.url(for: raw, variant: nil))
            var foil = try XCTUnwrap(entry["vendor"] as? [String: Any])
            var etched = try XCTUnwrap(entry["etchedVendor"] as? [String: Any])
            func slab(_ id: String, printing: String) -> [String: Any] {
                ["id": id, "type": "graded", "printing": printing,
                 "grading": ["company": "PSA", "grade": 10],
                 "markets": [["region": "NA", "currency": "USD", "price": 123]]]
            }
            // Put an incorrect finish under each product too. A source-level
            // finish list cannot authorize another product's etched/foil slab.
            foil["variants"] = [slab("foil", printing: "Foil"), slab("wrong-etched", printing: "Etched Foil")]
            etched["variants"] = [slab("etched", printing: "Etched Foil"), slab("wrong-foil", printing: "Foil")]
            let identity = GradedCardIdentity(name: source.name, setName: source.setName,
                collectorNumber: source.collectorNumber, catalogID: source.id)
            let context = try MagicGradedProductIdentity(identity: identity, card: source)
            XCTAssertEqual(context.productIDs.count, 2)
            let etchedSlab = try JSONDecoder().decode(JustTCGVariant.self,
                from: JSONSerialization.data(withJSONObject: slab("etched", printing: "Etched Foil")))
            XCTAssertFalse(context.admits(etchedSlab, productID: String(source.tcgplayerID!), requestedFinish: .etched))
            let products = [String(source.tcgplayerID!): foil, String(source.tcgplayerEtchedID!): etched]
            let ordered = context.productIDs.map { products[$0]! }
            RecordingURLProtocol.reset(body: String(decoding: try JSONSerialization.data(withJSONObject: ["data": [ordered[0]]]), as: UTF8.self))
            RecordingURLProtocol.laterPageBody = try JSONSerialization.data(withJSONObject: ["data": [ordered[1]]])
            let client = try gradedFixtureClient(directory: ProductSetDirectoryProvider(), magicCardLoader: { _ in source })
            let result = try await client.lookup(identity: identity, game: .magic)
            guard case let .matched(variants) = result else { XCTFail("\(source.name): \(result)"); continue }
            XCTAssertEqual(Set(variants.map(\.id)), ["foil", "etched"], source.name)
            let requested = try RecordingURLProtocol.recorded().map { url in
                try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "tcgplayer_id" }?.value)
            }
            XCTAssertEqual(requested, context.productIDs)

            RecordingURLProtocol.reset(body: String(decoding: try JSONSerialization.data(withJSONObject: ["data": [etched]]), as: UTF8.self))
            let selected = try await client.lookup(identity: .init(name: source.name, setName: source.setName,
                collectorNumber: source.collectorNumber, catalogID: source.id, finish: .resolving("etched")), game: .magic)
            guard case let .matched(etchedOnly) = selected else { XCTFail("Etched selection: \(source.name)"); continue }
            XCTAssertEqual(etchedOnly.map(\.id), ["etched"])
            let query = try XCTUnwrap(URLComponents(url: XCTUnwrap(RecordingURLProtocol.recorded().first), resolvingAgainstBaseURL: false)?.queryItems)
            XCTAssertEqual(query.first { $0.name == "tcgplayer_id" }?.value, String(source.tcgplayerEtchedID!))
            XCTAssertEqual(RecordingURLProtocol.recorded().count, 1)
        }
    }

    func testExactMagic404IsAProductMissAndCatalogOutageIsNot() async throws {
        let fixture = try directMagicFixture()
        let source = try decodeMagicSource(fixture.source)
        let identity = GradedCardIdentity(name: source.name, setName: source.setName,
            collectorNumber: source.collectorNumber, catalogID: source.id)
        RecordingURLProtocol.reset(status: 404)
        let client = try gradedFixtureClient(directory: ProductSetDirectoryProvider(), magicCardLoader: { _ in source })
        let missing = try await client.lookup(identity: identity, game: .magic)
        XCTAssertEqual(missing, .noProductMatch)
        XCTAssertEqual(RecordingURLProtocol.recorded().count, 1)
        RecordingURLProtocol.reset()
        let unavailable = try gradedFixtureClient(directory: ProductSetDirectoryProvider(), magicCardLoader: { _ in
            throw ScryfallError.providerUnavailable
        })
        do {
            _ = try await unavailable.lookup(identity: identity, game: .magic)
            XCTFail("Catalog outage cannot become an ordinary vendor miss")
        } catch ScryfallError.providerUnavailable { }
        XCTAssertTrue(RecordingURLProtocol.recorded().isEmpty)
    }

    func testUnboundMagicIdentityDoesNotTrustImportedProductMetadata() async throws {
        RecordingURLProtocol.reset()
        let directory = ProductSetDirectoryProvider()
        _ = try await directory.directory(for: .magic) { ProductSetDirectory(sets: []) }
        let client = try gradedFixtureClient(directory: directory, magicCardLoader: { _ in
            XCTFail("An arbitrary imported identifier must not authorize a source product lookup")
            throw ScryfallError.identityMismatch
        })
        let result = try await client.lookup(identity: .init(name: "Card", setName: "Set", collectorNumber: "1",
            catalogID: "csv:untrusted-product-123"), game: .magic)
        XCTAssertEqual(result, .noProductMatch)
        let query = try XCTUnwrap(URLComponents(url: XCTUnwrap(RecordingURLProtocol.recorded().first), resolvingAgainstBaseURL: false)?.queryItems)
        XCTAssertNil(query.first { $0.name == "tcgplayer_id" })
    }

    private func decodeMagicSource(_ values: [String: Any]) throws -> ScryfallCard {
        try JSONDecoder().decode(ScryfallCard.self, from: JSONSerialization.data(withJSONObject: values))
    }

    private func directMagicFixture() throws -> (source: [String: Any], vendor: [String: Any]) {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "magic-direct-product-proof", withExtension: "json",
            subdirectory: "TradingCards/SetPricingAudit"))
        let document = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let first = try XCTUnwrap((document["cases"] as? [[String: Any]])?.first)
        return (try XCTUnwrap(first["source"] as? [String: Any]), try XCTUnwrap(first["vendor"] as? [String: Any]))
    }

    private func gradedFixtureClient(directory: ProductSetDirectoryProvider, maximumPages: Int = 3,
                                     magicCardLoader: JustTCGV2GradedClient.MagicCardLoader? = nil) throws -> JustTCGV2GradedClient {
        let sessionConfig = URLSessionConfiguration.ephemeral
        sessionConfig.protocolClasses = [RecordingURLProtocol.self]
        var config = JustTCGTransport.Configuration()
        config.minimumRequestInterval = 0
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "graded-fixture-\(UUID())"))
        return JustTCGV2GradedClient(transport: JustTCGTransport(configuration: config,
            session: URLSession(configuration: sessionConfig), ledger: JustTCGRequestLedger(defaults: defaults),
            pacer: JustTCGPacer(), apiKeyOverride: "synthetic-key"), setDirectoryProvider: directory,
            maximumPages: maximumPages, magicCardLoader: magicCardLoader)
    }

    // MARK: - Delta safety

    @MainActor
    func testBatchProgressCountsOwnersBeforeTheWholeGameCompletes() async throws {
        let suite = "JustTCGProgress.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        RecordingURLProtocol.reset()
        let (coordinator, _) = makeCoordinator(defaults: defaults)
        let probe = MarketRefreshProgressProbe()
        var targets = (0..<21).map {
            target(key: "owner-\($0)", variant: "variant-\($0)", requiresFullResponse: true)
        }
        targets.append(target(key: "another-owner", variant: "variant-0", requiresFullResponse: true))

        let report = await coordinator.refresh(targets, game: .pokemon,
            onProgress: { report in
                await probe.record(report, requests: RecordingURLProtocol.recorded().count)
            }, checkpoint: { true })

        let samples = await probe.snapshot()
        XCTAssertEqual(samples.map(\.checked), [0, 21, 22],
            "Progress counts every owner, including owners sharing one network lookup")
        XCTAssertEqual(samples.map(\.requests), [0, 1, 2],
            "The first batch must publish before the second request runs")
        XCTAssertEqual(report.variantsRequested, 21, "Network lookup accounting stays deduplicated")
        XCTAssertEqual(report.targetsChecked, targets.count)
        XCTAssertTrue(report.completedFully)
    }

    /// Records every outbound request so a test can assert on `updated_after`.
    private final class RecordingURLProtocol: URLProtocol, @unchecked Sendable {
        nonisolated(unsafe) static var requestedURLs: [URL] = []
        nonisolated(unsafe) static var body = Data(#"{"data":[]}"#.utf8)
        nonisolated(unsafe) static var laterPageBody: Data?
        nonisolated(unsafe) static var responseStatus = 200
        nonisolated(unsafe) static var responseHeaders: [String: String] = [
            "Content-Type": "application/json"
        ]
        private static let lock = NSLock()

        static func reset(
            body newBody: String = #"{"data":[]}"#,
            headers newHeaders: [String: String] = ["Content-Type": "application/json"],
            status: Int = 200
        ) {
            lock.lock(); defer { lock.unlock() }
            requestedURLs = []
            laterPageBody = nil
            responseStatus = status
            body = Data(newBody.utf8)
            responseHeaders = newHeaders
        }

        static func recorded() -> [URL] {
            lock.lock(); defer { lock.unlock() }
            return requestedURLs
        }

        private static func responseHeadersSnapshot() -> [String: String] {
            lock.lock(); defer { lock.unlock() }
            return requestedURLs.count > 1 && laterPageBody != nil ? [:] : responseHeaders
        }

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
            if let url = request.url {
                Self.lock.lock()
                Self.requestedURLs.append(url)
                Self.lock.unlock()
            }
            let response = HTTPURLResponse(
                url: request.url ?? URL(string: "https://example.invalid")!,
                statusCode: Self.responseStatus,
                httpVersion: nil,
                headerFields: Self.responseHeadersSnapshot()
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            Self.lock.lock()
            let payload = Self.requestedURLs.count > 1 ? (Self.laterPageBody ?? Self.body) : Self.body
            Self.lock.unlock()
            client?.urlProtocol(self, didLoad: payload)
            client?.urlProtocolDidFinishLoading(self)
        }

        override func stopLoading() {}
    }

    @MainActor
    private func makeCoordinator(
        defaults: UserDefaults,
        serverClock: JustTCGServerClock = .shared
    ) -> (JustTCGRefreshCoordinator, JustTCGSyncLedger) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RecordingURLProtocol.self]

        var transportConfiguration = JustTCGTransport.Configuration()
        transportConfiguration.baseURL = URL(string: "https://justtcg.test")!
        transportConfiguration.minimumRequestInterval = 0

        let transport = JustTCGTransport(
            configuration: transportConfiguration,
            session: URLSession(configuration: configuration),
            ledger: JustTCGRequestLedger(defaults: defaults),
            pacer: JustTCGPacer(),
            apiKeyOverride: "justtcg-test-key",
            serverClock: serverClock
        )
        let syncLedger = JustTCGSyncLedger(defaults: defaults)
        return (
            JustTCGRefreshCoordinator(
                client: JustTCGV1Client(transport: transport),
                syncLedger: syncLedger,
                serverClock: serverClock
            ),
            syncLedger
        )
    }

    private func target(
        key: String,
        variant: String,
        requiresFullResponse: Bool,
        justTCGFetchedAt: Date? = nil,
        itemKind: CollectionItemKind = .rawCard
    ) -> MarketPriceTarget {
        MarketPriceTarget(
            priceKey: key,
            game: .pokemon,
            printingID: "sv08.5-001",
            variantID: "normal",
            itemKind: itemKind,
            marketVariantID: variant,
            lookupCandidates: [],
            currentAmount: nil,
            lastCheckedAt: nil,
            justTCGFetchedAt: justTCGFetchedAt,
            requiresFullResponse: requiresFullResponse
        )
    }

    /// The delta clock is per game, but it is advanced by whatever narrow pass
    /// happened to succeed. A row that has never had a complete answer must
    /// therefore still be asked with a full request, or "absent" and "never
    /// fetched" become the same response — the exact ambiguity `updated_after`
    /// is documented as unsafe under.
    @MainActor
    func testChunkCarryingAnUnansweredRowAsksForAFullResponse() async throws {
        let suite = "JustTCGDelta.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        RecordingURLProtocol.reset()

        let (coordinator, syncLedger) = makeCoordinator(defaults: defaults)
        syncLedger.recordCompleteSync(game: .pokemon, apiVersion: JustTCGV1Client.apiVersion)
        XCTAssertNotNil(
            syncLedger.deltaCutoff(game: .pokemon, apiVersion: JustTCGV1Client.apiVersion),
            "precondition: the clock is set, so delta is available"
        )

        _ = await coordinator.refresh(
            [
                target(key: "priced", variant: "variant-priced", requiresFullResponse: false),
                target(key: "never-answered", variant: "variant-new", requiresFullResponse: true)
            ],
            game: .pokemon,
            useDelta: true,
            apply: { _, _, _ in true },
            checkpoint: { true }
        )

        let urls = RecordingURLProtocol.recorded()
        XCTAssertEqual(urls.count, 1, "both lookups fit one chunk")
        XCTAssertFalse(
            urls[0].query?.contains("updated_after") ?? false,
            "one row with nothing to compare against makes the whole chunk ask in full"
        )
    }

    /// The delta is still used where it is safe, so the gate above cannot be
    /// satisfied by simply never sending one.
    @MainActor
    func testChunkOfAlreadyAnsweredRowsStillUsesTheDelta() async throws {
        let suite = "JustTCGDelta.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        RecordingURLProtocol.reset()

        let (coordinator, syncLedger) = makeCoordinator(defaults: defaults)
        let watermark = Date(timeIntervalSince1970: 1_700_000_000)
        syncLedger.recordCompleteSync(
            game: .pokemon,
            apiVersion: JustTCGV1Client.apiVersion,
            at: watermark
        )

        _ = await coordinator.refresh(
            [target(
                key: "priced",
                variant: "variant-priced",
                requiresFullResponse: false,
                justTCGFetchedAt: watermark.addingTimeInterval(1)
            )],
            game: .pokemon,
            useDelta: true,
            apply: { _, _, _ in true },
            checkpoint: { true }
        )

        let urls = RecordingURLProtocol.recorded()
        XCTAssertEqual(urls.count, 1)
        XCTAssertTrue(
            urls[0].query?.contains("updated_after") ?? false,
            "a row that already holds a value can be asked for changes only"
        )
    }

    @MainActor
    func testDeltaRequestUsesTheServerAdjustedCutoff() async throws {
        let suite = "JustTCGDelta.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        RecordingURLProtocol.reset()

        let watermark = Date(timeIntervalSince1970: 1_700_000_040)
        let serverClock = JustTCGServerClock()
        serverClock.observe(
            serverDateHeader: rfc1123Header(for: watermark.addingTimeInterval(10 * 60)),
            deviceNow: watermark
        )
        let (coordinator, syncLedger) = makeCoordinator(
            defaults: defaults,
            serverClock: serverClock
        )
        syncLedger.recordCompleteSync(
            game: .pokemon,
            apiVersion: JustTCGV1Client.apiVersion,
            at: watermark
        )

        _ = await coordinator.refresh(
            [target(
                key: "priced",
                variant: "variant-priced",
                requiresFullResponse: false,
                justTCGFetchedAt: watermark.addingTimeInterval(1)
            )],
            game: .pokemon,
            useDelta: true,
            apply: { _, _, _ in true },
            checkpoint: { true }
        )

        let url = try XCTUnwrap(RecordingURLProtocol.recorded().first)
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let sentCutoff = try XCTUnwrap(
            components.queryItems?.first(where: { $0.name == "updated_after" })?.value
        )
        XCTAssertEqual(
            sentCutoff,
            String(Int(watermark.addingTimeInterval(-5 * 60).timeIntervalSince1970)),
            "the server offset is applied only to the outbound delta cutoff"
        )
    }

    @MainActor
    func testPricedRowOlderThanDeltaWatermarkAsksForFullResponse() async throws {
        let suite = "JustTCGDelta.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        RecordingURLProtocol.reset()

        let (coordinator, syncLedger) = makeCoordinator(defaults: defaults)
        let watermark = Date(timeIntervalSince1970: 1_700_000_000)
        syncLedger.recordCompleteSync(
            game: .pokemon,
            apiVersion: JustTCGV1Client.apiVersion,
            at: watermark
        )

        _ = await coordinator.refresh(
            [target(
                key: "priced",
                variant: "variant-priced",
                requiresFullResponse: false,
                justTCGFetchedAt: watermark.addingTimeInterval(-1)
            )],
            game: .pokemon,
            useDelta: true,
            apply: { _, _, _ in true },
            checkpoint: { true }
        )

        let urls = RecordingURLProtocol.recorded()
        XCTAssertEqual(urls.count, 1)
        XCTAssertFalse(
            urls[0].query?.contains("updated_after") ?? false,
            "a price older than the vendor watermark must be refreshed in full"
        )
    }

    /// A full response that carries no listing for the requested variant is a
    /// real answer and must be reported. Without it a sealed row waiting on
    /// artwork never learns the vendor has none, stays permanently stale, and
    /// spends one request on every refresh for the life of the collection.
    @MainActor
    func testFullResponseMissIsReportedSoArtworkCanBecomeTerminal() async throws {
        let suite = "JustTCGDelta.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        RecordingURLProtocol.reset()

        let (coordinator, _) = makeCoordinator(defaults: defaults)
        var missed: [MarketPriceTarget] = []

        _ = await coordinator.refresh(
            [
                target(
                    key: "sealed",
                    variant: "variant-sealed",
                    requiresFullResponse: true,
                    itemKind: .sealedProduct
                )
            ],
            game: .pokemon,
            useDelta: false,
            apply: { _, _, _ in true },
            unmatched: { missed.append(contentsOf: $0) },
            checkpoint: { true }
        )

        XCTAssertEqual(missed.map(\.priceKey), ["sealed"])
    }

    /// The mirror image: absence from a *delta* response means "unchanged", not
    /// "the vendor has nothing", and must never be reported as an answer.
    @MainActor
    func testDeltaResponseMissIsNotReported() async throws {
        let suite = "JustTCGDelta.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        RecordingURLProtocol.reset()

        let (coordinator, syncLedger) = makeCoordinator(defaults: defaults)
        let watermark = Date(timeIntervalSince1970: 1_700_000_000)
        syncLedger.recordCompleteSync(
            game: .pokemon,
            apiVersion: JustTCGV1Client.apiVersion,
            at: watermark
        )
        var missed: [MarketPriceTarget] = []

        _ = await coordinator.refresh(
            [
                target(
                    key: "sealed",
                    variant: "variant-sealed",
                    requiresFullResponse: false,
                    justTCGFetchedAt: watermark.addingTimeInterval(1),
                    itemKind: .sealedProduct
                )
            ],
            game: .pokemon,
            useDelta: true,
            apply: { _, _, _ in true },
            unmatched: { missed.append(contentsOf: $0) },
            checkpoint: { true }
        )

        XCTAssertTrue(missed.isEmpty, "unchanged is not an answer about artwork")
    }

    @MainActor
    func testFailedCheckpointIsReportedAndDoesNotAdvanceDelta() async throws {
        let suite = "JustTCGDelta.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        RecordingURLProtocol.reset()

        let (coordinator, syncLedger) = makeCoordinator(defaults: defaults)
        let report = await coordinator.refresh(
            [target(key: "priced", variant: "variant-priced", requiresFullResponse: false)],
            game: .pokemon,
            apply: { _, _, _ in true },
            checkpoint: { false }
        )

        XCTAssertEqual(report.targetsChecked, 0, "A failed checkpoint cannot count planned targets as checked")
        XCTAssertTrue(report.persistenceFailed)
        XCTAssertFalse(report.completedFully)
        XCTAssertNil(
            syncLedger.deltaCutoff(game: .pokemon, apiVersion: JustTCGV1Client.apiVersion),
            "a failed save must leave the delta checkpoint eligible for retry"
        )
    }

    @MainActor
    func testDeferredBatchCheckpointNeedsADurableFinalSaveBeforeAdvancingDelta() async throws {
        let suite = "JustTCGDelta.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        RecordingURLProtocol.reset()

        let (coordinator, syncLedger) = makeCoordinator(defaults: defaults)
        let deferred = await coordinator.refresh(
            [target(key: "priced", variant: "variant-priced", requiresFullResponse: false)],
            game: .pokemon,
            apply: { _, _, _ in true },
            checkpoint: { true },
            finalCheckpoint: { false }
        )

        XCTAssertTrue(deferred.persistenceFailed)
        XCTAssertFalse(deferred.completedFully)
        XCTAssertNil(
            syncLedger.deltaCutoff(game: .pokemon, apiVersion: JustTCGV1Client.apiVersion),
            "a deferred batch must not advance the clock before the final save"
        )

        let committed = await coordinator.refresh(
            [target(key: "priced", variant: "variant-priced", requiresFullResponse: false)],
            game: .pokemon,
            apply: { _, _, _ in true },
            checkpoint: { true },
            finalCheckpoint: { true }
        )

        XCTAssertTrue(committed.completedFully)
        XCTAssertNotNil(
            syncLedger.deltaCutoff(game: .pokemon, apiVersion: JustTCGV1Client.apiVersion)
        )
    }
}
