import SwiftData
import XCTest
@testable import TradingCardScanner

final class CardGameForwardCompatibilityTests: XCTestCase {
    private struct FixtureCatalogAdapter: GameCatalogAdapter {
        let game = CardGame.onePiece
        let generation = "reviewed-generation-1"
        let cards: [ResolvedCatalogCard]
        var lookupCanonical: CanonicalCardSummary {
            .init(id: "one-piece:en:OP01-120", game: game, name: "Shanks", printedIdentifier: "OP01-120", language: "en")
        }
        func lookup(_ identifier: ScanIdentifier) async throws -> CatalogLookupOutcome {
            guard !cards.isEmpty else { return .catalogIncomplete(lookupCanonical) }
            return .needsPrintingChoice(canonical: lookupCanonical, candidates: cards.enumerated().map { index, card in
                .init(id: card.physicalPrintingID, game: game, canonicalCardID: lookupCanonical.id,
                      language: "en", catalogGeneration: generation, name: card.name,
                      printedIdentifier: "OP01-120", releaseLabel: "Reviewed release \(index + 1)",
                      treatmentLabel: nil, distributionLabel: nil, releaseDate: nil, thumbnailURL: nil)
            })
        }
        func resolve(_ candidate: PhysicalPrintingCandidate, for identifier: ScanIdentifier) async throws -> CardCatalog.CatalogResolution {
            guard let card = cards.first(where: { $0.physicalPrintingID == candidate.id }) else {
                throw CatalogLookupError.invalidPrintingChoice
            }
            return .init(card, retrievedAt: Date(timeIntervalSince1970: 12345), path: .cacheHit)
        }
    }

    private func futureIdentifier(generation: String = "reviewed-generation-1") throws -> ScanIdentifier {
        try .init(game: .onePiece, namespace: "numbered-card", fields: [.init(key: "number", value: "OP01-120")],
                  displayIdentifier: "OP01-120", suppressionIdentity: "OP01-120", catalogGeneration: generation)
    }

    func testCatalogAdapterKeepsPrintingChoiceAndDifferentCopiesIndependent() async throws {
        let adapter = FixtureCatalogAdapter(cards: [try futureCard(), try futureCard(printingID: "second-uuid")])
        let runtime = CardGameRuntime(
            descriptor: .init(game: .onePiece, displayName: "One Piece fixture", sortOrder: 0, capabilities: [.scan]),
            variantPolicy: FutureVariantPolicy(), catalog: adapter
        )
        let catalog = try CardGameRuntimeContainer(runtimes: [runtime]).makeCardCatalog()
        let identifier = try futureIdentifier()
        guard case let .needsPrintingChoice(canonical, candidates) = try await catalog.lookupOutcome(for: identifier) else {
            return XCTFail("Canonical number must retain both physical choices")
        }
        XCTAssertEqual(canonical.id, "one-piece:en:OP01-120")
        XCTAssertEqual(candidates.count, 2)
        do {
            _ = try await catalog.resolution(for: identifier)
            XCTFail("Single-card API must not choose a physical printing")
        } catch CatalogLookupError.printingChoiceRequired {} catch { XCTFail("Unexpected error: \(error)") }
        let first = try await catalog.resolvePrintingChoice(candidates[0], for: identifier)
        let second = try await catalog.resolvePrintingChoice(candidates[1], for: identifier)
        XCTAssertNotEqual(first.card.physicalPrintingID, second.card.physicalPrintingID)
        XCTAssertEqual(first.retrievedAt, Date(timeIntervalSince1970: 12345))
        XCTAssertEqual(first.path, .cacheHit)
        XCTAssertFalse(first.isPersistable)
        guard case let .needsPrintingChoice(_, laterCandidates) = try await catalog.lookupOutcome(for: identifier) else {
            return XCTFail("User choice must not become a global canonical-number default")
        }
        XCTAssertEqual(laterCandidates, candidates)
        do {
            _ = try await catalog.resolvePrintingChoice(candidates[0], for: futureIdentifier(generation: "new-generation"))
            XCTFail("Stale choice must not mix generations")
        } catch CatalogLookupError.staleCatalog {} catch { XCTFail("Unexpected error: \(error)") }
    }

    func testCatalogAdapterIncompleteCanonicalDoesNotBecomeOwnedPrinting() async throws {
        let adapter = FixtureCatalogAdapter(cards: [])
        let catalog = CardCatalog(gameCatalogAdapters: try .init(adapters: [adapter]))
        guard case let .catalogIncomplete(canonical) = try await catalog.lookupOutcome(for: futureIdentifier()) else {
            return XCTFail("Known canonical card without verified physical identity stays incomplete")
        }
        XCTAssertEqual(canonical?.id, "one-piece:en:OP01-120")
        do {
            _ = try await catalog.resolution(for: futureIdentifier())
            XCTFail("Incomplete catalog cannot return an exact printing")
        } catch CatalogLookupError.catalogIncomplete {} catch { XCTFail("Unexpected error: \(error)") }
        XCTAssertThrowsError(try GameCatalogAdapterRegistry(adapters: [adapter, adapter]))
    }

    func testCatalogAdapterRejectsDuplicatePhysicalIDsAndUnlistedChoices() async throws {
        let card = try futureCard()
        let duplicateCatalog = CardCatalog(gameCatalogAdapters: try .init(adapters: [FixtureCatalogAdapter(cards: [card, card])]))
        do {
            _ = try await duplicateCatalog.lookupOutcome(for: futureIdentifier())
            XCTFail("Duplicate physical identities must not enter the choice UI")
        } catch CatalogLookupError.invalidAdapterOutcome {} catch { XCTFail("Unexpected error: \(error)") }

        let oneCandidateCatalog = CardCatalog(gameCatalogAdapters: try .init(adapters: [FixtureCatalogAdapter(cards: [card])]))
        guard case let .needsPrintingChoice(_, candidates) = try await oneCandidateCatalog.lookupOutcome(for: futureIdentifier()) else {
            return XCTFail("One reviewed candidate alone must not manufacture automatic resolution")
        }
        XCTAssertEqual(candidates.count, 1)
        let otherAdapter = FixtureCatalogAdapter(cards: [try futureCard(printingID: "foreign-uuid")])
        guard case let .needsPrintingChoice(_, foreign) = try await otherAdapter.lookup(futureIdentifier()) else {
            return XCTFail("Expected fixture choice")
        }
        do {
            _ = try await oneCandidateCatalog.resolvePrintingChoice(foreign[0], for: futureIdentifier())
            XCTFail("Candidate from another lookup must not resolve")
        } catch CatalogLookupError.invalidPrintingChoice {} catch { XCTFail("Unexpected error: \(error)") }
    }

    private func futureCard(printingID: String = "physical-uuid", variants: [PhysicalVariant] = [.foil]) throws -> ResolvedCatalogCard {
        try .init(game: .onePiece, physicalPrintingID: printingID,
                  canonicalCardID: "one-piece:en:OP01-120", language: "en", name: "Shanks",
                  setName: "Reviewed release", setCode: "OP01", cardNumber: "OP01-120",
                  printedIdentifier: "OP01-120", variantEvidence: .init(
                    game: .onePiece, setID: "reviewed-release", cardNumber: "OP01-120", catalogVariants: variants
                  ))
    }

    func testGenericResolvedCardPreservesExactPrintingAcrossVariantCatalogChanges() throws {
        let first = try futureCard(variants: [.foil])
        let expanded = try futureCard(variants: [.foil, .nonfoil])
        let other = try futureCard(printingID: "different-physical-uuid")
        XCTAssertNil(first.legacyIdentity)
        XCTAssertEqual(first.game, .onePiece)
        XCTAssertEqual(first.canonicalCardID, other.canonicalCardID)
        XCTAssertNotEqual(first.id, other.id)
        XCTAssertEqual(first.collectionKey(variant: .foil), "one-piece:physical-uuid#foil")
        XCTAssertEqual(first.collectionKey(variant: .foil), expanded.collectionKey(variant: .foil))
        XCTAssertNotEqual(first.collectionKey(variant: .foil), other.collectionKey(variant: .foil))
        XCTAssertEqual(GamePriceIdentity.legacy(first).printingID, "physical-uuid")
        XCTAssertEqual(GamePriceIdentity.legacy(first).language, "en")
        XCTAssertEqual(CardPricing.price(for: first, variant: .foil, magicTreatments: []), .unavailable(nil))
        XCTAssertNil(TCGplayerLinkBuilder.url(for: first, variant: .foil, pokemonPrintRun: nil))
    }

    func testGenericResolvedCardRejectsMismatchedPhysicalVariantEvidence() {
        XCTAssertThrowsError(try futureCard(variants: [.foil, .foil]))
        XCTAssertThrowsError(try futureCard(printingID: "bad#identity"))
        XCTAssertThrowsError(try ResolvedCatalogCard(
            game: .onePiece, physicalPrintingID: "physical-uuid", canonicalCardID: "one-piece:en:OP01-120",
            language: "en", name: "Shanks", setName: "Release", setCode: "OP01", cardNumber: "OP01-120",
            printedIdentifier: "OP01-120", variantEvidence: .init(
                game: .pokemon, setID: "OP01", cardNumber: "OP01-120", catalogVariants: [.holo]
            )
        ))
    }

    func testGenericResolvedCardCreatesLosslessCollectionMetadata() throws {
        let card = try futureCard()
        let row = CollectedCard(card: card, resolved: .init(variant: .foil, resolution: .userConfirmed),
                                identityResolution: .userSelectedPrinting)
        XCTAssertEqual(row.game, "one-piece")
        XCTAssertEqual(row.providerID, "physical-uuid")
        XCTAssertEqual(row.collectionKey, "one-piece:physical-uuid#foil")
        XCTAssertEqual(row.cardNumber, "OP01-120")
        XCTAssertEqual(row.variantID, "foil")
        XCTAssertEqual(row.identityResolution, .userSelectedPrinting)
    }

    private actor RecordingPriceAdapter: GamePriceAdapter {
        nonisolated let game: CardGame
        private(set) var requests: [GamePriceRequest] = []
        init(game: CardGame) { self.game = game }
        func refresh(_ request: GamePriceRequest) async throws -> PriceLookup {
            requests.append(request)
            return .unavailable(nil)
        }
    }

    private actor RejectingBulkPriceSource: PokemonTCGCSVPriceSource {
        private(set) var requestCount = 0
        func snapshot(setID: String, retry: Bool) async throws -> PokemonTCGCSVSnapshot {
            requestCount += 1
            throw PriceQuoteError.providerUnavailable
        }
    }

    @MainActor
    func testBackgroundRefreshPreservesUnknownGameRowsWithoutPriceObservations() async throws {
        let container = try ModelContainer(for: CollectionStorageModelSchema.full,
                                          configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        let game = CardGame(rawValue: "future-game")
        for kind in [CollectionItemKind.rawCard, .gradedCard] {
            let row = CollectedCard(collectionKey: "future:" + kind.rawValue, game: game,
                                    providerID: "physical-uuid", name: "Test", setName: "Test", setCode: "OP01",
                                    cardNumber: "OP01-120", rarity: nil, imageURL: nil, thumbnailURL: nil,
                                    variant: .foil, variantResolution: .userConfirmed)
            row.itemKindRaw = kind.rawValue
            row.justTCGVariantID = "previous-vendor-handle"
            container.mainContext.insert(row)
        }
        try container.mainContext.save()
        let source = RejectingBulkPriceSource()
        let actor = PriceRefreshModelActor(modelContainer: container)
        await actor.setTCGCSVSourceForTesting(source)
        await actor.setPokemonFetchOverrideForTesting { _ in
            XCTFail("Unknown game reached primary provider")
            throw PriceQuoteError.pricingUnsupported
        }
        _ = await actor.run(.init(usesPriceFallback: true, includeImported: true,
                                  forceUnsupportedRetry: true, sortOldestFirst: false,
                                  maximumTargetCount: nil, markRecentlyCheckedIfEmpty: false),
                            progress: { _ in }, shouldContinue: nil)
        let count = await source.requestCount
        XCTAssertEqual(count, 0)
        let context = ModelContext(container)
        XCTAssertTrue(try context.fetch(FetchDescriptor<PriceRecord>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<ProductIdentity>()).isEmpty)
        let rows = try context.fetch(FetchDescriptor<CollectedCard>())
        XCTAssertEqual(rows.count, 2)
        XCTAssertTrue(rows.allSatisfy { $0.game == game.rawValue && $0.quantity == 1 })
    }

    @MainActor
    func testDisabledPricingStopsStoredCardFallbackBeforeProviderOrObservation() async throws {
        let container = try ModelContainer(for: CollectionStorageModelSchema.full,
                                          configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        let source = RejectingBulkPriceSource()
        let resolver = PriceFallbackQuoteResolver(context: container.mainContext, tcgCSVSource: source,
                                                  gameRegistry: CardGameRegistry(descriptors: []))
        let card = CollectedCard(collectionKey: "30th-c-014", game: .pokemon,
                                 providerID: "30th-c-014", name: "Test", setName: "Test", setCode: "30C",
                                 cardNumber: "014", rarity: nil, imageURL: nil, thumbnailURL: nil,
                                 variant: .holo, variantResolution: .userConfirmed)
        let result = await resolver.resolve(card: card, variant: .holo, pokemonPrintRun: nil)
        XCTAssertEqual(result, .failed(.unsupportedGame))
        let count = await source.requestCount
        XCTAssertEqual(count, 0)
        XCTAssertTrue(try container.mainContext.fetch(FetchDescriptor<PriceRecord>()).isEmpty)
        XCTAssertTrue(try container.mainContext.fetch(FetchDescriptor<ProductIdentity>()).isEmpty)
    }

    func testPricingDispatchPreservesExactPrintingAndVariant() async throws {
        let game = CardGame(rawValue: "future-game")
        let adapter = RecordingPriceAdapter(game: game)
        let registry = CardGameRegistry(descriptors: [
            .init(game: game, displayName: "Future", sortOrder: 0, capabilities: [.pricing])
        ])
        let service = PriceQuoteService(registry: registry,
                                       adapters: try GamePriceAdapterRegistry(adapters: [adapter]))
        let identity = GamePriceIdentity(game: game, printingID: UUID().uuidString,
                                        setID: "release", displaySetCode: "OP01",
                                        cardNumber: "OP01-120", language: "en")
        let result = try await service.refresh(.init(identity: identity, variant: .foil,
                                                    pokemonPrintRun: nil, catalogRefreshOverride: nil))
        XCTAssertEqual(result, .unavailable(nil))
        let requests = await adapter.requests
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests.first?.identity, identity)
        XCTAssertEqual(requests.first?.variant, .foil)
        XCTAssertNil(requests.first?.pokemonPrintRun)
    }

    func testAbsentAdapterOrCapabilityMakesNoPricingRequests() async throws {
        let game = CardGame(rawValue: "future-game")
        let adapter = RecordingPriceAdapter(game: game)
        for capability in [CardGameCapabilities.pricing, []] {
            let registry = CardGameRegistry(descriptors: [
                .init(game: game, displayName: "Future", sortOrder: 0, capabilities: capability)
            ])
            let adapters: [any GamePriceAdapter] = capability.isEmpty ? [adapter] : []
            let service = PriceQuoteService(registry: registry,
                                           adapters: try GamePriceAdapterRegistry(adapters: adapters))
            XCTAssertFalse(service.supportsPricing(for: game))
            do {
                _ = try await service.refresh(.init(
                    identity: .init(game: game, printingID: "exact-uuid", setID: "release",
                                    displaySetCode: "OP01", cardNumber: "OP01-120", language: "en"),
                    variant: .foil, pokemonPrintRun: nil,
                    catalogRefreshOverride: { XCTFail("Unsupported game invoked provider override"); return .unavailable(nil) }
                ))
                XCTFail("Expected terminal unsupported pricing")
            } catch PriceQuoteError.pricingUnsupported {} catch { XCTFail("Unexpected error: \(error)") }
        }
        let requests = await adapter.requests
        XCTAssertTrue(requests.isEmpty)
        XCTAssertThrowsError(try GamePriceAdapterRegistry(adapters: [adapter, adapter]))
    }

    func testRuntimeRejectsPricingAdapterForAnotherGame() {
        let runtime = CardGameRuntime(descriptor: PokemonGameRuntime.descriptor,
                                      variantPolicy: PokemonVariantPolicy(), pricing: MagicPriceAdapter())
        XCTAssertThrowsError(try CardGameRuntimeContainer(runtimes: [runtime])) { error in
            XCTAssertEqual(error as? CardGameRuntimeContainer.RegistrationError, .pricingGameMismatch(.pokemon))
        }
    }

    private struct FutureVariantPolicy: GameVariantPolicy {
        var selectableVariants: [PhysicalVariant] { [.init(id: "future-finish", label: "Future finish")] }
    }

    func testRuntimeRegistrationRoutesFutureVariantPolicyWithoutCentralCases() throws {
        let game = CardGame(rawValue: "future-game")
        let runtime = CardGameRuntime(
            descriptor: .init(game: game, displayName: "Future Game", sortOrder: 5, capabilities: [.scan]),
            variantPolicy: FutureVariantPolicy()
        )
        let container = try CardGameRuntimeContainer(runtimes: [runtime])
        XCTAssertEqual(container.runtime(for: game)?.descriptor.displayName, "Future Game")
        XCTAssertEqual(PhysicalVariant.selectable(for: game, registry: container.registry).map(\.id), ["future-finish"])
        XCTAssertEqual(VariantLock.selectable(for: game, registry: container.registry).map(\.id), ["future-finish"])
        XCTAssertThrowsError(try CardGameRuntimeContainer(runtimes: [runtime, runtime]))
        XCTAssertNil(container.runtime(for: .pokemon))
        XCTAssertFalse(container.registry.supports(game, .collectionWrite))
        XCTAssertEqual(container.registry.variantLockMenu.first?.displayName, "Future Game")
        XCTAssertEqual(container.registry.variantLockMenu.first?.options.map(\.id), ["future-finish"])
    }

    @MainActor
    func testScannerLocksUseInjectedPolicyAndRejectUnavailableGame() {
        let game = CardGame(rawValue: "future-game")
        let policy = FutureVariantPolicy()
        let registry = CardGameRegistry(
            descriptors: [.init(game: game, displayName: "Future Game", sortOrder: 0, capabilities: [.scan])],
            variantPolicies: [game: policy]
        )
        let model = ScannerViewModel(gameRegistry: registry)
        let lock = VariantLock(finish: policy.selectableVariants[0])
        model.setFinishLock(lock, for: game)
        XCTAssertEqual(model.finishLocks[game], lock)
        model.setFinishLock(VariantLock(finish: .foil), for: game)
        XCTAssertEqual(model.finishLocks[game], lock)
        model.setFinishLock(VariantLock(finish: .normal), for: .pokemon)
        XCTAssertNil(model.finishLocks[.pokemon])
        model.setFinishLock(nil, for: game)
        XCTAssertNil(model.finishLocks[game])
    }

    func testExistingRuntimeKeepsCoordinatorAndPolicyIdentity() throws {
        let coordinator = PokemonCatalogCoordinator()
        let module = PokemonGameRuntime(coordinator: coordinator)
        let container = try CardGameRuntimeContainer(runtimes: [module.runtime])
        XCTAssertTrue(container.runtime(for: .pokemon)?.legacyCatalogBindings.pokemon === coordinator)
        XCTAssertEqual(container.registry.games(supporting: .scan), [.pokemon])
        XCTAssertEqual(VariantLock.selectable(for: .pokemon, registry: container.registry),
                       VariantLock.selectable(for: .pokemon))
        XCTAssertEqual(PhysicalVariant.selectable(for: .pokemon), [
            .normal, .holo, .reverse, .pokeBall, .masterBall, .duskBall,
            .friendBall, .quickBall, .loveBall, .firstEdition
        ])
        XCTAssertEqual(PhysicalVariant.selectable(for: .magic), [.nonfoil, .foil, .etched])
    }

    func testFutureGameDecodesAndKeepsStringWireFormat() throws {
        let decoder = JSONDecoder()
        let original = Data(#""future-game""#.utf8)
        let game = try decoder.decode(CardGame.self, from: original)
        XCTAssertEqual(game.rawValue, "future-game")
        XCTAssertEqual(try JSONEncoder().encode(game), original)
        XCTAssertNotEqual(game, .pokemon)
    }

    func testKnownGameWireValuesRemainCompatible() throws {
        for game in [CardGame.pokemon, .magic] {
            XCTAssertEqual(try JSONDecoder().decode(CardGame.self, from: JSONEncoder().encode(game)), game)
        }
        XCTAssertEqual(CardGame(rawValue: " One-Piece \n"), .onePiece)
    }

    func testEnumerationUsesCapabilitiesAndKeepsDisabledDescriptor() {
        let registry = CardGameRegistry.standard
        XCTAssertEqual(registry.games(supporting: .scan), [.pokemon, .magic])
        XCTAssertEqual(registry.games(supporting: .sealed), [.pokemon, .magic])
        XCTAssertEqual(registry.descriptor(for: .onePiece)?.displayName, "One Piece")
        XCTAssertFalse(registry.supports(.onePiece, .collectionWrite))
        XCTAssertFalse(registry.supports(CardGame(rawValue: "future-game"), .pricing))
    }

    func testExplicitUnknownCSVGameIsPreservedAndNamespaced() throws {
        let plan = try CollectionCSV.parse(Data("game,provider_id,card_name,set_name,set_code,card_number,quantity\nfuture-game,printing-1,Card,Set,SET,1,1\n".utf8))
        let entry = try XCTUnwrap(plan.entries.first)
        XCTAssertEqual(entry.game.rawValue, "future-game")
        XCTAssertEqual(entry.collectionKey, "future-game:printing-1")
    }

    func testAbsentAndBlankCSVGamesRetainLegacyFormatInference() throws {
        let inferred = try CollectionCSV.parse(Data("provider_id,card_name,quantity\nid,Card,1\n".utf8))
        XCTAssertEqual(inferred.entries.first?.game, .pokemon)
        let blank = try CollectionCSV.parse(Data("game,provider_id,card_name,quantity\n,id,Card,1\n".utf8))
        XCTAssertEqual(blank.entries.first?.game, .pokemon)
        XCTAssertEqual(blank.entries.first?.collectionKey, inferred.entries.first?.collectionKey)
    }

    func testUnsupportedGameCannotBecomeJustTCGIdentity() {
        let game = CardGame(rawValue: "future-game")
        XCTAssertNil(ProductCatalogIdentity.game(for: game, catalogID: "printing-1"))
        XCTAssertThrowsError(try JustTCGV1Client.gameSlug(for: game))
        XCTAssertTrue(PhysicalVariant.selectable(for: game).isEmpty)
    }

    func testGenericFieldsHaveCanonicalOrderAndPresentationDoesNotChangeIdentity() throws {
        let first = try ScanIdentifier(game: .onePiece, namespace: "numbered-card",
            fields: [.init(key: "number", value: "OP01-120"), .init(key: "language", value: "en")],
            displayIdentifier: "Shanks", suppressionIdentity: "OP01-120")
        let second = try ScanIdentifier(game: .onePiece, namespace: "numbered-card",
            fields: first.fields.reversed(), displayIdentifier: "OP01-120", suppressionIdentity: "OP01-120")
        XCTAssertEqual(first, second)
        XCTAssertEqual(Set([first, second]).count, 1)
        XCTAssertEqual(first.fields.map(\.key), ["language", "number"])
        XCTAssertThrowsError(try ScanIdentifier(game: .onePiece, namespace: "numbered-card",
            fields: [.init(key: "number", value: "OP01-120"), .init(key: "number", value: "P-001")],
            displayIdentifier: "", suppressionIdentity: ""))
        let snapshot = ScanIdentifierSnapshot(identifier: first)
        let restored = try JSONDecoder().decode(ScanIdentifierSnapshot.self,
            from: JSONEncoder().encode(snapshot)).identifier()
        XCTAssertEqual(restored, first)
    }

    @MainActor
    func testUnknownCollectionIdentitySurvivesWithoutPokemonFallback() {
        let game = CardGame(rawValue: "future-game")
        let card = CollectedCard(
            collectionKey: "future-game:printing-1", game: game, providerID: "printing-1",
            name: "Card", setName: "Set", setCode: "SET", cardNumber: "1",
            rarity: nil, imageURL: nil, thumbnailURL: nil, variant: nil,
            variantResolution: .catalogSilent
        )
        XCTAssertEqual(card.game, "future-game")
        XCTAssertEqual(card.cardGame, game)
    }

    @MainActor
    func testUnknownCSVImportCannotWriteSyncedCollectionOrLedger() throws {
        let container = try ModelContainer(
            for: CollectionStorageModelSchema.full,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        let context = ModelContext(container)
        let plan = try CollectionCSV.parse(Data("game,provider_id,card_name,quantity\nfuture-game,printing-1,Card,1\n".utf8))
        let result = try CollectionCSV.apply(plan, to: context)
        XCTAssertEqual(result.failedRows.count, 1)
        XCTAssertTrue(try context.fetch(FetchDescriptor<CollectedCard>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<InventoryEvent>()).isEmpty)
        XCTAssertEqual(plan.entries.first?.game.rawValue, "future-game")
    }

    @MainActor
    func testUnsupportedStoreAddRejectsSavedAndStagedTransactions() throws {
        let container = try ModelContainer(for: CollectionStorageModelSchema.full,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        let context = ModelContext(container)
        let store = CollectionStore(context: context)
        for savesChanges in [true, false] {
            XCTAssertThrowsError(try store.add(futureCard(),
                resolved: .init(variant: .foil, resolution: .userConfirmed), savesChanges: savesChanges))
            XCTAssertFalse(context.hasChanges)
            XCTAssertTrue(try context.fetch(FetchDescriptor<CollectedCard>()).isEmpty)
            XCTAssertTrue(try context.fetch(FetchDescriptor<InventoryEvent>()).isEmpty)
            XCTAssertTrue(try context.fetch(FetchDescriptor<CollectionActivity>()).isEmpty)
        }
    }

    @MainActor
    func testUnsupportedSyncedRowCannotChangeQuantityRemoveRestoreOrCorrect() throws {
        let container = try ModelContainer(for: CollectionStorageModelSchema.full,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        let context = ModelContext(container)
        let row = CollectedCard(card: try futureCard(),
            resolved: .init(variant: .foil, resolution: .userConfirmed))
        context.insert(row)
        try context.save() // Simulates a row received from another client.
        let key = row.collectionKey
        let store = CollectionStore(context: context)
        XCTAssertThrowsError(try store.setQuantity(2, forCollectionKey: key, expectedCurrent: 1))
        XCTAssertThrowsError(try store.remove(collectionKey: key))
        XCTAssertThrowsError(try store.restore(RemovedCardSnapshot(card: row)))
        XCTAssertThrowsError(try store.recordVariantCorrection(for: row,
            to: .init(variant: .nonfoil, resolution: .userConfirmed), activityID: UUID(), quantity: 1))
        XCTAssertThrowsError(try store.deleteAll())
        let retained = try XCTUnwrap(context.fetch(FetchDescriptor<CollectedCard>()).first)
        XCTAssertEqual(retained.collectionKey, key)
        XCTAssertEqual(retained.quantity, 1)
        XCTAssertEqual(retained.variant, .foil)
        XCTAssertFalse(context.hasChanges)
        XCTAssertTrue(try context.fetch(FetchDescriptor<InventoryEvent>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<CollectionActivity>()).isEmpty)
    }

    @MainActor
    func testContainerWritePolicyAllowsFixtureThenRejectsUndoAfterPolicyWithdrawal() throws {
        let container = try ModelContainer(for: CollectionStorageModelSchema.full,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        let context = ModelContext(container)
        let writable = CardGameRegistry(descriptors: [
            .init(game: .onePiece, displayName: "One Piece", sortOrder: 0, capabilities: [.collectionWrite])
        ])
        CollectionStore.configureGames(writable, for: container)
        let store = CollectionStore(context: context, gameRegistry: writable)
        let mutation = try store.add(futureCard(),
            resolved: .init(variant: .foil, resolution: .userConfirmed))
        let eventCount = try context.fetchCount(FetchDescriptor<InventoryEvent>())
        CollectionStore.configureGames(.standard, for: container)
        XCTAssertThrowsError(try store.undo(mutation))
        XCTAssertThrowsError(try CollectionStore(context: context, gameRegistry: writable)
            .setQuantity(2, forCollectionKey: mutation.collectionKey, expectedCurrent: 1))
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<InventoryEvent>()), eventCount)
        XCTAssertEqual(try context.fetch(FetchDescriptor<CollectedCard>()).first?.quantity, 1)
        XCTAssertFalse(context.hasChanges)
    }

    @MainActor
    func testHistoryBackfillLeavesUnsupportedSyncedRowUntouched() throws {
        let container = try ModelContainer(for: CollectionStorageModelSchema.full,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        let context = ModelContext(container)
        let row = CollectedCard(card: try futureCard(),
            resolved: .init(variant: .foil, resolution: .userConfirmed))
        context.insert(row)
        try context.save()
        try CollectionStore(context: context).backfillExistingCollectionIfNeeded()
        XCTAssertEqual(row.activityBackfillVersion, 0)
        XCTAssertNil(row.activityBackfillAnchor)
        XCTAssertTrue(try context.fetch(FetchDescriptor<CollectionActivity>()).isEmpty)
        XCTAssertFalse(context.hasChanges)
    }

    @MainActor
    func testBlankGameHistoryCannotMutateUnsupportedOwnershipAndRepeatedBackfillIsQuiet() throws {
        let container = try ModelContainer(for: CollectionStorageModelSchema.full,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        let context = ModelContext(container)
        let card = CollectedCard(card: try futureCard(), resolved: .init(variant: .foil, resolution: .userConfirmed))
        let activity = CollectionActivity(card: card, source: .scan)
        activity.gameRaw = ""; activity.kindRaw = ""; activity.deltaQuantity = 0
        context.insert(card); context.insert(activity); try context.save()
        let suite = "UnsupportedBackfill-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = CollectionStore(context: context)
        for _ in 0..<3 {
            try store.backfillExistingCollectionIfNeeded(defaults: defaults)
            XCTAssertEqual(activity.kindRaw, "")
            XCTAssertEqual(activity.deltaQuantity, 0)
            XCTAssertNil(card.activityBackfillAnchor)
            XCTAssertFalse(context.hasChanges)
        }
        activity.quantity = 2
        XCTAssertThrowsError(try store.validatePendingGameWrites())
        context.rollback()
        XCTAssertFalse(context.hasChanges)
        // Inspect persisted state independently of SwiftData's retained object.
        let reopened = ModelContext(container)
        let savedActivities = try reopened.fetch(FetchDescriptor<CollectionActivity>())
        XCTAssertEqual(savedActivities.count, 1)
        XCTAssertEqual(savedActivities.first?.quantity, 1)
    }

    @MainActor
    func testInventoryOnlyWritesRequireWritableRawGradedAndSealedOwnership() throws {
        let container = try ModelContainer(for: CollectionStorageModelSchema.full,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        let context = ModelContext(container)
        let store = CollectionStore(context: context)
        for key in ["one-piece:printing", "future-game:printing", "graded:future-game:printing", "sealed:one-piece:product"] {
            context.insert(InventoryEvent(operationID: UUID(), leg: nil, kind: .recordExisting, source: .scan,
                collectionKey: key, priceStorageKey: key, deltaQuantity: 1, occurredAt: .now, valuation: .unpriced))
            XCTAssertThrowsError(try store.validatePendingGameWrites(), key)
            context.rollback()
            XCTAssertFalse(context.hasChanges)
        }
        XCTAssertTrue(try context.fetch(FetchDescriptor<InventoryEvent>()).isEmpty)
    }

    @MainActor
    func testUnsupportedLegacyArtworkCanBeOverriddenLocallyWithoutChangingSyncedBridge() throws {
        let container = try ModelContainer(for: CollectionStorageModelSchema.full,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        let context = ModelContext(container)
        let card = CollectedCard(card: try futureCard(), resolved: .init(variant: .foil, resolution: .userConfirmed))
        card.userArtworkFilename = "legacy.image"
        context.insert(card); try context.save()
        try CollectionArtworkStore.migrateLegacyMappings(in: context)
        XCTAssertEqual(card.userArtworkFilename, "legacy.image")
        XCTAssertFalse(context.hasChanges)
        try CollectionArtworkStore.set(filename: "local.image", for: card.collectionKey, in: context)
        try CollectionStore(context: context).validatePendingGameWrites()
        try context.save()
        XCTAssertEqual(CollectionArtworkStore.filename(for: card.collectionKey, legacyFilename: card.userArtworkFilename, in: context), "local.image")
        try CollectionArtworkStore.set(filename: nil, for: card.collectionKey, in: context, suppressLegacyFallback: true)
        try CollectionStore(context: context).validatePendingGameWrites()
        try context.save()
        let relaunched = ModelContext(container)
        XCTAssertNil(CollectionArtworkStore.filename(for: card.collectionKey, legacyFilename: card.userArtworkFilename, in: relaunched))
        XCTAssertEqual(card.userArtworkFilename, "legacy.image")
    }
}
