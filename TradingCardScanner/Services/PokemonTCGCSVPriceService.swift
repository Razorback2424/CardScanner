import Foundation

enum PokemonTCGCSVError: Error {
    case unsupportedSet, invalidResponse, identityMismatch, retryLater
}

struct PokemonTCGCSVSnapshot: Codable, Sendable {
    let schemaVersion: Int
    let setID: String
    let feedBuild: String
    let fetchedAt: Date
    var validatedAt: Date
    let valuesByCardID: [String: Double]
    var legacyPositiveOnly: Bool? = nil

    func quote(cardID: String, variant: PhysicalVariant?, printRun: PokemonPrintRun?, now: Date = .now) -> PriceLookup? {
        guard PokemonTCGCSVMapping.byCardID[cardID]?.setID == setID,
              variant == .holo, printRun == nil || printRun == .unlimited, fetchedAt <= now else { return nil }
        guard let amount = valuesByCardID[cardID] else {
            return legacyPositiveOnly != true && PriceDisplay.freshness(asOf: fetchedAt, now: now) == .current
                ? .unavailable(.tcgCSV) : nil
        }
        return .price(NormalizedPrice(
            unitMarketPriceUSD: amount, currencyCode: "USD", source: .tcgCSV,
            sourceVariantID: "holofoil", sourceUpdatedAt: nil, fetchedAt: fetchedAt
        ))
    }
}

protocol PokemonTCGCSVPriceSource: Sendable {
    func snapshot(setID: String, retry: Bool) async throws -> PokemonTCGCSVSnapshot
}

/// Projects reviewed Pokémon set prices from the same provider groups used by
/// exact product lookups. Prior installations can import positive set quotes.
struct PokemonTCGCSVPriceService: PokemonTCGCSVPriceSource {
    static let shared = PokemonTCGCSVPriceService(transport: .shared)
    private let transport: TCGCSVProductPriceSource
    private let legacyFiles: TCGCSVSnapshotFiles

    init(transport: TCGCSVProductPriceSource, legacyFiles: TCGCSVSnapshotFiles? = nil) {
        self.transport = transport
        self.legacyFiles = legacyFiles ?? .live("TCGCSV-v1", byteLimit: 8 * 1_024 * 1_024)
    }

    init(session: URLSession = TCGCSVPriceMirror.session, baseURL: URL? = TCGCSVPriceMirror.baseURL,
         cacheDirectory: URL? = nil, now: @escaping @Sendable () -> Date = { .now },
         spacing: TimeInterval = 0.1, marker: TCGCSVMirrorBuildMarker? = nil) {
        self.init(transport: TCGCSVProductPriceSource(baseURL: baseURL, session: session,
            cacheDirectory: cacheDirectory, now: now, marker: marker, spacing: spacing),
            legacyFiles: cacheDirectory.map { .init(directory: $0, legacyDirectory: nil, byteLimit: .max) })
    }

    func snapshot(setID: String, retry: Bool = false) async throws -> PokemonTCGCSVSnapshot {
        let key = setID.lowercased()
        guard let groupID = PokemonTCGCSVMapping.groupID(for: key) else {
            throw PokemonTCGCSVError.unsupportedSet
        }
        let name = key + ".json"
        let raw = try await transport.groupSnapshot(category: 3, group: groupID, retry: retry, loadLegacy: {
            loadLegacy(setID: key, groupID: groupID, name: name)
        }, retireLegacy: {
            try? FileManager.default.removeItem(at: legacyFiles.directory.appendingPathComponent(name))
            if let directory = legacyFiles.legacyDirectory {
                try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
            }
        })
        try Task.checkCancellation()
        guard let build = raw.sourceBuild else { throw PokemonTCGCSVError.invalidResponse }
        var result = try Self.project(products: raw.products, prices: raw.prices, setID: key, groupID: groupID,
                                      feedBuild: build, fetchedAt: raw.fetchedAt)
        result.validatedAt = raw.validatedAt ?? raw.fetchedAt
        result.legacyPositiveOnly = raw.legacyPositiveOnly
        return result
    }

    private func loadLegacy(setID: String, groupID: Int, name: String) -> TCGCSVProductPriceSource.Snapshot? {
        guard let saved: PokemonTCGCSVSnapshot = legacyFiles.read(name, maxBytes: 8 * 1_024 * 1_024, validating: {
            $0.schemaVersion == 1 && $0.setID == setID && TCGCSVPriceMirror.timestamp($0.feedBuild) != nil
                && $0.valuesByCardID.allSatisfy { cardID, amount in
                    PokemonTCGCSVMapping.byCardID[cardID]?.groupID == groupID && amount >= 0 && Money(rounding: amount) != nil
                }
        }) else { return nil }
        // The released v1 set reader admitted these fixed product and finish
        // bindings. Only its positive observations are portable to the shared cache.
        let mappings = PokemonTCGCSVMapping.entries.filter { $0.setID == setID }
        let products = mappings.map {
            TCGCSVProductPriceSource.Product(productId: $0.productID, categoryId: 3, groupId: groupID,
                                            name: $0.productName, extendedData: [.init(name: "Number", value: $0.printedNumber)])
        }
        let prices = mappings.compactMap { mapping -> TCGCSVProductPriceSource.Price? in
            guard let amount = saved.valuesByCardID[mapping.cardID] else { return nil }
            return .init(productId: mapping.productID, subTypeName: "Holofoil", marketPrice: amount)
        }
        return .init(products: products, prices: prices, fetchedAt: saved.fetchedAt,
                     sourceBuild: saved.feedBuild, validatedAt: saved.validatedAt, legacyPositiveOnly: true)
    }

    static func decodeSnapshot(
        products: Data, prices: Data, setID: String, feedBuild: String, fetchedAt: Date
    ) throws -> PokemonTCGCSVSnapshot {
        guard let groupID = PokemonTCGCSVMapping.groupID(for: setID) else {
            throw PokemonTCGCSVError.unsupportedSet
        }
        let productResponse = try JSONDecoder().decode(Response<TCGCSVProductPriceSource.Product>.self, from: products)
        let priceResponse = try JSONDecoder().decode(Response<TCGCSVProductPriceSource.Price>.self, from: prices)
        guard productResponse.success, productResponse.errors.isEmpty,
              priceResponse.success, priceResponse.errors.isEmpty,
              productResponse.totalItems.map({ $0 == productResponse.results.count }) ?? true,
              priceResponse.totalItems.map({ $0 == priceResponse.results.count }) ?? true else {
            throw PokemonTCGCSVError.invalidResponse
        }
        return try project(products: productResponse.results, prices: priceResponse.results, setID: setID,
                           groupID: groupID, feedBuild: feedBuild, fetchedAt: fetchedAt)
    }

    private static func project(products: [TCGCSVProductPriceSource.Product], prices: [TCGCSVProductPriceSource.Price],
                                setID: String, groupID: Int, feedBuild: String, fetchedAt: Date) throws -> PokemonTCGCSVSnapshot {
        let productsByID = Dictionary(grouping: products, by: \.productId)
        let pricesByID = Dictionary(grouping: prices, by: \.productId)
        var values: [String: Double] = [:]
        for mapping in PokemonTCGCSVMapping.entries where mapping.setID == setID {
            guard let matched = productsByID[mapping.productID], matched.count == 1,
                  let product = matched.first, product.categoryId == 3, product.groupId == groupID,
                  matchesProductName(product.name, mapping: mapping),
                  product.extendedData.filter({ $0.name == "Number" }).count == 1,
                  let number = product.extendedData.first(where: { $0.name == "Number" })?.value,
                  normalizedNumber(number) == normalizedNumber(mapping.printedNumber) else {
                throw PokemonTCGCSVError.identityMismatch
            }
            let rows = (pricesByID[mapping.productID] ?? []).filter { $0.subTypeName == "Holofoil" }
            guard rows.count <= 1 else { throw PokemonTCGCSVError.invalidResponse }
            if let amount = rows.first?.marketPrice {
                guard amount.isFinite, amount >= 0 else { throw PokemonTCGCSVError.invalidResponse }
                values[mapping.cardID] = amount
            }
        }
        return PokemonTCGCSVSnapshot(
            schemaVersion: 1, setID: setID, feedBuild: feedBuild,
            fetchedAt: fetchedAt, validatedAt: fetchedAt, valuesByCardID: values
        )
    }

    private static func matchesProductName(_ name: String, mapping: PokemonTCGCSVMapping.Entry) -> Bool {
        let normalized = normalizedName(name)
        return normalized == normalizedName(mapping.productName)
            || (mapping.cardID == "30th-c-021" && mapping.productID == 716202
                && normalized == normalizedName("N (Supporter)"))
    }

    private static func normalizedName(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .replacingOccurrences(of: "&", with: "and")
            .unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.map(String.init).joined()
    }

    private static func normalizedNumber(_ value: String) -> String {
        value.split(separator: "/").map { Int($0).map(String.init) ?? String($0) }.joined(separator: "/")
    }

    private struct Response<T: Decodable>: Decodable {
        let success: Bool
        let errors: [String]
        let totalItems: Int?
        let results: [T]
    }
}

/// Exact TCGplayer bindings from the bundled Pokémon product catalogs.
struct PokemonReviewedMarketProduct: Sendable {
    let setID: String
    let groupID: Int
    let productID: Int
    let cardName: String
    let marketName: String
    let number: String
    let variant: PhysicalVariant
    let printing: String
    let allowsMissingMarketNumber: Bool

    private struct PrizePackResource: Decodable {
        let schemaVersion: Int
        let groupID: Int
        let entries: [Entry]

        struct Entry: Decodable {
            let cardID: String
            let cardName: String
            let number: String
            let variantID: String
            let productID: Int
            let marketName: String
            let printing: String
        }
    }

    private static let prizePacks: [String: [Self]] = {
        guard let url = Bundle.main.url(forResource: "pokemon-prize-pack-printings", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let resource = try? JSONDecoder().decode(PrizePackResource.self, from: data),
              resource.schemaVersion == 1, resource.groupID == 22880,
              Set(resource.entries.map(\.productID)).count == resource.entries.count else { return [:] }
        var entries: [String: [Self]] = [:]
        for entry in resource.entries {
            guard entry.productID > 0, !entry.marketName.isEmpty,
                  let variant = PokemonCatalogStampVariant.resolving(entry.variantID),
                  variant.id == entry.variantID,
                  let separator = entry.cardID.lastIndex(of: "-"),
                  ["Normal", "Holofoil"].contains(entry.printing),
                  entries[entry.cardID]?.contains(where: { $0.variant.id == variant.id }) != true else { return [:] }
            entries[entry.cardID, default: []].append(Self(entry, variant: variant,
                setID: String(entry.cardID[..<separator]), groupID: resource.groupID))
        }
        return entries
    }()

    static func prizePackVariants(for card: TCGdexCard) -> [PhysicalVariant] {
        (prizePacks[card.id] ?? []).filter {
            $0.setID == card.set.id && $0.matches(name: card.name, number: card.localId)
        }.map(\.variant)
    }

    static let setIDs = PokemonBattleDeckFinishCatalog.setIDs.union([PokemonM26Catalog.setID])
        .union(PokemonDeltaReignCatalog.setIDs)

    static func usesReviewedVariantsOnly(cardID: String, setID: String? = nil) -> Bool {
        setID == PokemonM26Catalog.setID || PokemonM26Catalog.entry(cardID: cardID) != nil
            || PokemonDeltaReignCatalog.card(cardID)?.isPromo == true
    }

    static func entry(cardID: String, variantID: String?) -> Self? {
        if let prizePack = prizePacks[cardID]?.first(where: { $0.variant.id == variantID }) { return prizePack }
        if let m26 = PokemonM26Catalog.entry(cardID: cardID), m26.variant.id == variantID { return .init(m26) }
        if let card = PokemonDeltaReignCatalog.card(cardID) { return .init(card, variantID: variantID) }
        return PokemonBattleDeckFinishCatalog.entry(cardID: cardID, variantID: variantID).map(Self.init)
    }

    static func entry(for summary: CatalogCardSummary, variantID: String? = nil) -> Self? {
        if summary.game == .pokemon, summary.pokemonPrintRun == nil,
           let prizePack = prizePacks[summary.providerID]?.first(where: {
               $0.variant.id == (variantID ?? summary.masterSetVariant?.id)
                   && $0.setID == summary.setID.providerID
                   && $0.matches(name: summary.name, number: summary.collectorNumber)
           }) { return prizePack }
        if let m26 = PokemonM26Catalog.entry(for: summary) { return .init(m26) }
        if let card = PokemonDeltaReignCatalog.card(for: summary) {
            return .init(card, variantID: variantID ?? summary.masterSetVariant?.id)
        }
        return PokemonBattleDeckFinishCatalog.entry(for: summary, variantID: variantID).map(Self.init)
    }

    static func entry(for card: TCGdexCard, variantID: String?) -> Self? {
        if let prizePack = prizePacks[card.id]?.first(where: {
            $0.variant.id == variantID && $0.setID == card.set.id
                && $0.matches(name: card.name, number: card.localId)
        }) { return prizePack }
        if let m26 = PokemonM26Catalog.entry(for: card), m26.variant.id == variantID { return .init(m26) }
        if let delta = PokemonDeltaReignCatalog.card(for: card) { return .init(delta, variantID: variantID) }
        return PokemonBattleDeckFinishCatalog.entries(for: card)
            .first { $0.variant.id == variantID }.map(Self.init)
    }

    static func printing(productID: Int, variantID: String?) -> String? {
        prizePacks.values.lazy.flatMap { $0 }.first { $0.productID == productID && $0.variant.id == variantID }?.printing
            ?? PokemonDeltaReignCatalog.printing(productID: productID, variantID: variantID)?.finish.printing
            ?? PokemonBattleDeckFinishCatalog.entry(productID: productID, variantID: variantID)?.printing.rawValue
    }

    func matches(name: String, number: String) -> Bool {
        CatalogIdentityNormalization.canonicalText(name) == CatalogIdentityNormalization.canonicalText(cardName)
            && ProductCatalogIdentity.numbersMatch(self.number, number)
    }

    private init(_ entry: PrizePackResource.Entry, variant: PhysicalVariant, setID: String, groupID: Int) {
        self.setID = setID
        self.groupID = groupID
        productID = entry.productID
        cardName = entry.cardName
        marketName = entry.marketName
        number = entry.number
        self.variant = variant
        printing = entry.printing
        allowsMissingMarketNumber = false
    }

    private init(_ m26: PokemonM26Catalog.Entry) {
        setID = PokemonM26Catalog.setID
        groupID = PokemonM26Catalog.groupID
        productID = m26.productID
        cardName = m26.name
        marketName = m26.name
        number = m26.number
        variant = m26.variant
        printing = m26.printing.rawValue
        allowsMissingMarketNumber = false
    }

    private init(_ deck: PokemonBattleDeckFinishCatalog.Entry) {
        setID = deck.setID
        groupID = deck.groupID
        productID = deck.productID
        cardName = deck.name
        marketName = deck.marketName
        number = deck.printedNumber
        variant = deck.variant
        printing = deck.printing.rawValue
        allowsMissingMarketNumber = false
    }

    private init?(_ card: PokemonDeltaReignCatalog.Card, variantID: String?) {
        guard let finish = card.printings.first(where: { $0.variant.id == variantID }),
              let productID = finish.productID, let marketName = finish.marketName else { return nil }
        setID = card.setID
        groupID = card.groupID
        self.productID = productID
        cardName = card.name
        self.marketName = marketName
        number = card.number
        variant = finish.variant
        printing = finish.finish.printing
        allowsMissingMarketNumber = finish.marketNumberMayBeMissing == true
    }
}

/// Exact-identity fallback policy shared by all price surfaces. No recognition work.
struct PokemonMarketPriceResolver: Sendable {
    let source: any PokemonTCGCSVPriceSource
    private let productSource: TCGCSVProductPriceSource

    init(source: any PokemonTCGCSVPriceSource = PokemonTCGCSVPriceService.shared,
         productSource: TCGCSVProductPriceSource = .shared) {
        self.source = source
        self.productSource = productSource
    }

    /// Share one publication check per set for the whole collection pass,
    /// including a second attempt through its fallback lane.
    func forRefresh(retry: Bool) -> Self {
        Self(source: PokemonTCGCSVRefreshSource(source: source, retry: retry), productSource: productSource)
    }

    func fallback(
        cardID: String, game: CardGame, variant: PhysicalVariant?, printRun: PokemonPrintRun?,
        retry: Bool = false
    ) async throws -> PriceLookup? {
        guard game == .pokemon else { return nil }
        if printRun == nil, let product = PokemonReviewedMarketProduct.entry(cardID: cardID, variantID: variant?.id) {
            return try await quote(for: product)
        }
        guard variant == .holo, printRun == nil || printRun == .unlimited,
              let mapping = PokemonTCGCSVMapping.byCardID[cardID] else { return nil }
        let snapshot = try await source.snapshot(setID: mapping.setID, retry: retry)
        try Task.checkCancellation()
        return snapshot.quote(cardID: cardID, variant: variant, printRun: printRun)
    }

    func quote(for product: PokemonReviewedMarketProduct, minimumFetchedAt: Date? = nil,
               allowsStaleFallback: Bool = true) async throws -> PriceLookup {
        try await productSource.quote(category: 3, group: product.groupID, productID: product.productID,
            name: product.marketName, number: product.number, lane: product.printing,
            minimumFetchedAt: minimumFetchedAt, allowsMissingNumber: product.allowsMissingMarketNumber,
            allowsStaleFallback: allowsStaleFallback)
    }

    func price(for card: IdentifiedCard, variant: PhysicalVariant?, printRun: PokemonPrintRun?) async -> PriceLookup {
        let catalog = CardPricing.price(
            for: card, variant: variant, magicTreatments: card.magicTreatments(for: variant), pokemonPrintRun: printRun
        )
        if case let .price(price) = catalog, price.currencyCode == "USD" { return catalog }
        return (try? await fallback(cardID: card.providerID, game: card.game, variant: variant, printRun: printRun)) ?? catalog
    }
}

private actor PokemonTCGCSVRefreshSource: PokemonTCGCSVPriceSource {
    let source: any PokemonTCGCSVPriceSource
    let retry: Bool
    private var tasks: [String: Task<PokemonTCGCSVSnapshot, Error>] = [:]

    init(source: any PokemonTCGCSVPriceSource, retry: Bool) {
        self.source = source
        self.retry = retry
    }

    func snapshot(setID: String, retry: Bool) async throws -> PokemonTCGCSVSnapshot {
        let key = setID.lowercased()
        let task: Task<PokemonTCGCSVSnapshot, Error>
        if let pending = tasks[key] { task = pending }
        else {
            task = Task { try await source.snapshot(setID: key, retry: self.retry) }
            tasks[key] = task
        }
        return try await task.valueForCurrentWaiter()
    }
}
