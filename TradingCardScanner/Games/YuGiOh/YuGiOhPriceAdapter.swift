import Foundation

protocol YuGiOhMarketPriceSource: Sendable {
    func quote(printing: YuGiOhCatalog.Printing, edition: YuGiOhEdition, generation: String, minimumFetchedAt: Date?) async throws -> PriceLookup
}
/// Offline snapshot consumption only. Daily ingestion belongs on the existing
/// publisher host; a device cache does not authorize direct TCGCSV requests.
struct YuGiOhBundledPriceSource: YuGiOhMarketPriceSource {
    func quote(printing p: YuGiOhCatalog.Printing, edition: YuGiOhEdition, generation: String, minimumFetchedAt: Date?) async throws -> PriceLookup {
        try Task.checkCancellation()
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let m = p.membership.first(where: { $0.e == edition }), let amount = m.q,
              let date = m.s.flatMap({ ISO8601DateFormatter().date(from: $0) ?? formatter.date(from: $0) }) else {
            // Historical membership without a quote is not a current negative
            // provider answer, including refreshes without a freshness watermark.
            throw PriceQuoteError.providerUnavailable
        }
        guard minimumFetchedAt.map({ date > $0 }) ?? true else { throw PriceQuoteError.providerUnavailable }
        return .price(.init(unitMarketPriceUSD: amount, currencyCode: "USD", source: .tcgCSV,
            sourceVariantID: "tcgplayer:\(p.productID):\(edition.tcgplayerSubtype)",
            sourceUpdatedAt: m.st == "providerSnapshot" ? date : nil, fetchedAt: date))
    }
}

/// Current quotes use the same server-ingested daily feeds as other reviewed
/// games. Offline initial valuation may reuse the bundle, with its original date.
struct YuGiOhDailyPriceSource: YuGiOhMarketPriceSource {
    var transport: TCGCSVProductPriceSource = .shared
    func quote(printing: YuGiOhCatalog.Printing, edition: YuGiOhEdition, generation: String,
               minimumFetchedAt: Date?) async throws -> PriceLookup {
        do {
            return try await transport.quote(category: 2, group: printing.set.groupID,
                productID: printing.productID, name: printing.productName, number: printing.code,
                lane: edition.tcgplayerSubtype, generation: generation, minimumFetchedAt: minimumFetchedAt)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch PriceQuoteError.identityMismatch {
            throw PriceQuoteError.identityMismatch
        } catch {
            try Task.checkCancellation()
            return try await YuGiOhBundledPriceSource().quote(printing: printing, edition: edition,
                generation: generation, minimumFetchedAt: minimumFetchedAt)
        }
    }
}

struct YuGiOhPriceAdapter: GamePriceAdapter {
    let catalog: YuGiOhCatalog
    var source: any YuGiOhMarketPriceSource = YuGiOhDailyPriceSource()
    var coordinator: YuGiOhCatalogCoordinator? = nil
    var game: CardGame { .yuGiOh }
    var allowsProviderFallback: Bool { false }
    var supportsStoredPrintingRefresh: Bool { true }
    static func mappingIdentity(_ p: YuGiOhCatalog.Printing, _ edition: YuGiOhEdition) -> String {
        "tcgcsv:2:\(p.set.groupID):\(p.productID):\(edition.tcgplayerSubtype)"
    }
    /// Deferred so binding Yu-Gi-Oh at launch does not decode a lazily loaded
    /// bundled catalog; the mappings are built once, on first read.
    static func priceAuthority(_ catalog: YuGiOhCatalog) -> GameCatalogPriceAuthority {
        .init(game: .yuGiOh, managedSources: [.tcgCSV], deferredIdentities: { identities(catalog) })
    }
    private static func identities(_ catalog: YuGiOhCatalog) -> [String: String] {
        var identities: [String: String] = [:]
        let adapter = YuGiOhCatalogAdapter(catalog: catalog)
        for family in catalog.printingsByCode.values {
            let evidence = PhysicalPrintingCandidate.selectionEvidenceByID(among: family.map(adapter.candidate))
            for p in family where p.explicitSelectionSupported && evidence[p.idString] != .insufficient {
                for edition in p.editions {
                    identities[PriceRecord.key(game: .yuGiOh, printingID: p.idString, variantID: edition.rawValue)] = mappingIdentity(p, edition)
                }
            }
        }
        return identities
    }
    func refreshStoredPrinting(_ printingID: String, variant: PhysicalVariant?) async throws -> PriceLookup {
        try await refreshStoredPrinting(printingID, variant: variant, minimumFetchedAt: nil)
    }
    func refreshStoredPrinting(_ printingID: String, variant: PhysicalVariant?, minimumFetchedAt: Date?) async throws -> PriceLookup {
        if let coordinator {
            let current = await coordinator.catalog()
            return try await YuGiOhPriceAdapter(catalog: current, source: source)
                .refreshStoredPrinting(printingID, variant: variant, minimumFetchedAt: minimumFetchedAt)
        }
        let card = try exactCard(printingID)
        return try await refresh(.init(identity: .legacy(card), variant: variant, pokemonPrintRun: nil,
            catalogRefreshOverride: nil, minimumFetchedAt: minimumFetchedAt))
    }
    private func exactCard(_ id: String) throws -> ResolvedCatalogCard {
        guard let uuid = UUID(uuidString: id), uuid.uuidString.lowercased() == id,
              let card = try? YuGiOhCatalogAdapter(catalog: catalog).resolutionForExistingHolding(uuid).card else { throw PriceQuoteError.identityMismatch }
        return card
    }
    func refresh(_ request: GamePriceRequest) async throws -> PriceLookup {
        if let coordinator {
            let current = await coordinator.catalog()
            return try await YuGiOhPriceAdapter(catalog: current, source: source).refresh(request)
        }
        guard request.identity.game == game, request.pokemonPrintRun == nil else { throw PriceQuoteError.identityMismatch }
        let card = try exactCard(request.identity.printingID)
        guard request.identity.matches(.legacy(card)), let variant = request.variant,
              let edition = YuGiOhEdition(rawValue: variant.id), let id = UUID(uuidString: card.physicalPrintingID),
              let p = catalog.printingByID[id], p.editions.contains(edition) else { throw PriceQuoteError.identityMismatch }
        // pe is build evidence only. Valid physical mappings always reach the
        // existing transport, so a newly available quote is discoverable.
        let quote = try await source.quote(printing: p, edition: edition, generation: catalog.generation, minimumFetchedAt: request.minimumFetchedAt)
        try Task.checkCancellation()
        if case var .price(price) = quote {
            guard price.source == .tcgCSV, price.currencyCode == "USD", price.unitMarketPriceUSD.isFinite,
                  price.unitMarketPriceUSD >= 0, request.minimumFetchedAt.map({ price.fetchedAt > $0 }) ?? true else { throw PriceQuoteError.providerUnavailable }
            price.catalogIdentity = Self.mappingIdentity(p, edition)
            return .price(price)
        }
        return quote
    }
}
