import Foundation

enum BrowseCatalogError: LocalizedError {
    case invalidURL
    case badResponse
    case unknownSet

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Could not build the catalog request."
        case .badResponse: return "The card catalog returned an unexpected response."
        case .unknownSet: return "The card's set could not be identified."
        }
    }
}

enum BrowseRequestBuilder {
    static func pokemonSearchURL(query: String, page: Int) -> URL? {
        var components = URLComponents(string: "https://api.tcgdex.net/v2/en/cards")
        components?.queryItems = [
            URLQueryItem(name: "name", value: query),
            URLQueryItem(name: "pagination:page", value: String(page)),
            URLQueryItem(name: "pagination:itemsPerPage", value: "60")
        ]
        return components?.url
    }

    static func scryfallSearchURL(query: String) -> URL? {
        var components = URLComponents(string: "https://api.scryfall.com/cards/search")
        components?.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "unique", value: "prints"),
            URLQueryItem(name: "order", value: "released"),
            URLQueryItem(name: "dir", value: "desc")
        ]
        return components?.url
    }
}

actor BrowseCatalog: BrowseCatalogProviding {
    private let tcgdex = TCGdexService()
    private let scryfall = ScryfallService()
    private let cache: CatalogCacheStore
    private var setCache: [CardGame: [CatalogSet]] = [:]
    private var detailCache: [String: CatalogCardDetails] = [:]
    private var pokemonSetDetails: [String: TCGdexSetCatalog] = [:]
    /// Expanding one Pokémon set costs a card request per numbered card, and the
    /// same expansion is asked for again every time the set is reopened, by each
    /// virtual print run of a WotC set, and by an in-set search. Keyed by the
    /// full catalog ID because print run changes which cards are excluded.
    private var pokemonSetSummaries: [String: [CatalogCardSummary]] = [:]
    private var sortPriceCache: [String: Double] = [:]
    private var resolvedSortPrices: Set<String> = []
    private var refreshingSetDirectories: Set<CardGame> = []

    init(cache: CatalogCacheStore = .shared) {
        self.cache = cache
    }

    func sets(for game: CardGame) async throws -> [CatalogSet] {
        if let cached = setCache[game] { return cached }
        if let saved = await cache.sets(for: game) {
            setCache[game] = saved.value
            installPokemonReleaseOrder(from: saved.value, game: game)
            if !saved.isFresh { scheduleSetDirectoryRefresh(for: game) }
            return saved.value
        }
        return try await loadSetDirectory(for: game)
    }

    private func loadSetDirectory(for game: CardGame) async throws -> [CatalogSet] {
        let loaded: [CatalogSet]
        switch game {
        case .pokemon: loaded = try await pokemonSets()
        case .magic: loaded = try await magicSets()
        }
        setCache[game] = loaded
        await cache.storeSets(loaded, for: game)
        return loaded
    }

    private func scheduleSetDirectoryRefresh(for game: CardGame) {
        guard refreshingSetDirectories.insert(game).inserted else { return }
        Task { [weak self] in
            guard let self else { return }
            _ = try? await self.loadSetDirectory(for: game)
            await self.finishSetDirectoryRefresh(for: game)
        }
    }

    private func finishSetDirectoryRefresh(for game: CardGame) {
        refreshingSetDirectories.remove(game)
    }

    func cards(in set: CatalogSet, cursor: String?) async throws -> CatalogPage<CatalogCardSummary> {
        let cacheKey = CatalogCacheStore.cardPageKey(for: set, cursor: cursor)
        if let saved = await cache.cardPage(for: cacheKey) { return saved }

        let page: CatalogPage<CatalogCardSummary>
        switch set.game {
        case .pokemon:
            if let cached = pokemonSetSummaries[set.id] {
                return CatalogPage(items: cached, nextCursor: nil)
            }
            let catalog = try await pokemonSet(id: set.providerID)
            let resolvedSet = enriched(set, catalog: catalog)
            let cards = catalog.cards.filter {
                !PokemonMasterSetDefinition.excludes(
                    card: $0,
                    setProviderID: set.providerID,
                    printRun: set.pokemonPrintRun
                )
            }
            let summaries = try await pokemonMasterSetSummaries(cards, set: resolvedSet)
            pokemonSetSummaries[set.id] = summaries
            page = CatalogPage(items: summaries, nextCursor: nil)
        case .magic:
            page = try await magicCards(query: "e:\(set.providerID) lang:en game:paper", cursor: cursor)
        }
        await cache.storeCardPage(page, for: cacheKey)
        return page
    }

    func searchCards(
        named query: String,
        game: CardGame,
        setIDs: Set<CatalogSetID>,
        cursor: String?
    ) async throws -> CatalogPage<CatalogCardSummary> {
        let normalized = CardNameSearch.normalize(query)
        guard normalized.count >= 2 else { return CatalogPage(items: [], nextCursor: nil) }

        switch game {
        case .pokemon:
            let selected = setIDs.filter { $0.game == .pokemon }
            if !selected.isEmpty {
                let directory = try await sets(for: .pokemon)
                var results: [CatalogCardSummary] = []
                for id in selected {
                    guard let set = directory.first(where: { $0.catalogID == id }) else { continue }
                    let page = try await cards(in: set, cursor: nil)
                    results.append(contentsOf: page.items.filter {
                        CardNameSearch.normalize($0.name).contains(normalized)
                    })
                }
                return CatalogPage(items: deduplicated(results), nextCursor: nil)
            }
            return try await searchPokemon(query: normalized, cursor: cursor)

        case .magic:
            let selected = setIDs.filter { $0.game == .magic }.map(\.providerID).sorted()
            let setClause = selected.isEmpty
                ? ""
                : " (\(selected.map { "e:\($0)" }.joined(separator: " or ")))"
            return try await magicCards(
                query: "name:\"\(escapedScryfall(query))\" lang:en game:paper\(setClause)",
                cursor: cursor
            )
        }
    }

    func details(for summary: CatalogCardSummary) async throws -> CatalogCardDetails {
        if let cached = detailCache[summary.id] { return cached }
        let details: CatalogCardDetails
        switch summary.game {
        case .pokemon:
            let catalog = try await pokemonSet(id: summary.setID.providerID)
            let directory = try await sets(for: .pokemon)
            let directorySet = directory.first { $0.catalogID == summary.setID }
            guard let directorySet else { throw BrowseCatalogError.unknownSet }
            let set = enriched(directorySet, catalog: catalog)
            let card = try await tcgdex.fetchCard(id: summary.providerID, locale: .en)
            details = CatalogCardDetails(card: .pokemon(card, setCode: set.code), set: set)
        case .magic:
            let card = try await scryfall.fetchCard(id: summary.providerID)
            let directory = try await sets(for: .magic)
            let directorySet = directory.first { $0.catalogID == summary.setID }
            guard let set = directorySet else { throw BrowseCatalogError.unknownSet }
            details = CatalogCardDetails(card: .magic(card), set: set)
        }
        detailCache[summary.id] = details
        return details
    }

    func sortPrices(for cards: [CatalogCardSummary]) async -> [String: Double] {
        let pending = cards.filter { !resolvedSortPrices.contains($0.id) }
        var iterator = pending.makeIterator()

        await withTaskGroup(of: (id: String, price: Double?, resolved: Bool).self) { group in
            for _ in 0..<min(6, pending.count) {
                guard let card = iterator.next() else { break }
                group.addTask { await self.sortPrice(for: card) }
            }

            while let result = await group.next() {
                if result.resolved { resolvedSortPrices.insert(result.id) }
                if let price = result.price { sortPriceCache[result.id] = price }
                if let next = iterator.next() {
                    group.addTask { await self.sortPrice(for: next) }
                }
            }
        }

        return Dictionary(uniqueKeysWithValues: cards.compactMap { card in
            sortPriceCache[card.id].map { (card.id, $0) }
        })
    }

    private func sortPrice(for summary: CatalogCardSummary) async -> (id: String, price: Double?, resolved: Bool) {
        guard summary.pokemonPrintRun == nil else {
            // The aggregate card price is not edition-specific. Do not use it
            // to sort virtual WotC runs as though it were.
            return (summary.id, nil, true)
        }
        do {
            let details = try await details(for: summary)
            if let variant = summary.masterSetVariant {
                let lookup = CardPricing.price(
                    for: details.card,
                    variant: variant,
                    pokemonPrintRun: summary.pokemonPrintRun
                )
                if case let .price(price) = lookup {
                    return (summary.id, price.unitMarketPriceUSD, true)
                }
                return (summary.id, nil, true)
            }
            return (summary.id, CardPricing.highestPublishedUSDPrice(for: details.card), true)
        } catch {
            return (summary.id, nil, false)
        }
    }

    private func pokemonSets() async throws -> [CatalogSet] {
        guard let url = URL(string: "https://api.tcgdex.net/v2/en/sets?sort:field=releaseDate&sort:order=DESC") else {
            throw BrowseCatalogError.invalidURL
        }
        let (data, response) = try await URLSession.shared.data(for: request(url))
        try validate(response)
        let rows = try JSONDecoder().decode([TCGdexBrowseSet].self, from: data)
        let pocketIDs = (try? await pokemonPocketSetIDs()) ?? []
        let baseSets = rows.enumerated().compactMap { pair -> CatalogSet? in
            let index = pair.offset
            let row = pair.element
            guard !pocketIDs.contains(row.id.lowercased()),
                  PokemonMasterSetDefinition.includesInSetDirectory(row) else { return nil }
            return CatalogSet(
                catalogID: CatalogSetID(game: .pokemon, providerID: row.id),
                name: row.name,
                code: row.tcgOnline?.uppercased()
                    ?? SetCodeMap.printedCode(forTCGdexSetID: row.id)
                    ?? row.id.uppercased(),
                logoURL: assetURL(row.logo, suffix: ".png"),
                symbolURL: assetURL(row.symbol, suffix: ".png"),
                cardCount: row.cardCount.map {
                    PokemonMasterSetDefinition.masterCount(
                        cardCount: $0,
                        setName: row.name,
                        printRun: nil
                    )
                },
                releaseDate: nil,
                sortRank: rows.count - index
            )
        }
        let countsByID = Dictionary(uniqueKeysWithValues: rows.compactMap { row in
            row.cardCount.map { (row.id.lowercased(), $0) }
        })
        let sets = baseSets.flatMap { set in
            PokemonMasterSetDefinition.virtualSets(
                set,
                cardCount: countsByID[set.providerID.lowercased()]
            )
        }
        installPokemonReleaseOrder(from: baseSets, game: .pokemon)
        return sets
    }

    private func installPokemonReleaseOrder(from sets: [CatalogSet], game: CardGame) {
        guard game == .pokemon else { return }
        var values: [String: Int] = [:]
        for set in sets where set.pokemonPrintRun == nil {
            values[set.providerID.lowercased()] = set.sortRank
        }
        PokemonCatalogReleaseOrder.install(values)
    }

    private func pokemonPocketSetIDs() async throws -> Set<String> {
        guard let url = URL(string: "https://api.tcgdex.net/v2/en/series/tcgp") else {
            throw BrowseCatalogError.invalidURL
        }
        let (data, response) = try await URLSession.shared.data(for: request(url))
        try validate(response)
        return Set(try JSONDecoder().decode(TCGdexSeriesSets.self, from: data).sets.map { $0.id.lowercased() })
    }

    private func magicSets() async throws -> [CatalogSet] {
        guard let url = URL(string: "https://api.scryfall.com/sets") else { throw BrowseCatalogError.invalidURL }
        let (data, response) = try await URLSession.shared.data(for: request(url, scryfall: true))
        try validate(response)
        let excluded: Set<String> = ["token", "memorabilia", "minigame", "art_series"]
        let rows = try JSONDecoder().decode(ScryfallBrowseSetList.self, from: data).data.filter {
            !$0.digital && !excluded.contains($0.setType ?? "")
        }
        return rows.sorted { ($0.releasedAt ?? "") > ($1.releasedAt ?? "") }.enumerated().map { index, row in
            CatalogSet(
                catalogID: CatalogSetID(game: .magic, providerID: row.code.lowercased()),
                name: row.name,
                code: row.code.uppercased(),
                logoURL: row.iconSVGURI,
                symbolURL: row.iconSVGURI,
                cardCount: row.cardCount,
                releaseDate: row.releasedAt.flatMap(FlexibleDate.parse),
                sortRank: rows.count - index
            )
        }
    }

    private func searchPokemon(query: String, cursor: String?) async throws -> CatalogPage<CatalogCardSummary> {
        let page = Int(cursor ?? "1") ?? 1
        guard let url = BrowseRequestBuilder.pokemonSearchURL(query: query, page: page) else {
            throw BrowseCatalogError.invalidURL
        }
        let (data, response) = try await URLSession.shared.data(for: request(url))
        try validate(response)
        let cards = try JSONDecoder().decode([TCGdexCardBrief].self, from: data)
        let directory = try await sets(for: .pokemon)
        let summaries = cards.flatMap { card -> [CatalogCardSummary] in
            let matching = directory.filter { card.id.hasPrefix($0.providerID + "-") }
            guard let longestID = matching.map(\.providerID).max(by: { $0.count < $1.count }) else {
                return []
            }
            return matching
                .filter { $0.providerID == longestID }
                .map { pokemonSummary(card, set: $0) }
        }
        return CatalogPage(items: summaries, nextCursor: cards.count == 60 ? String(page + 1) : nil)
    }

    private func magicCards(query: String, cursor: String?) async throws -> CatalogPage<CatalogCardSummary> {
        let url: URL
        if let cursor {
            guard let next = URL(string: cursor), next.host == "api.scryfall.com" else {
                throw BrowseCatalogError.invalidURL
            }
            url = next
        } else {
            guard let built = BrowseRequestBuilder.scryfallSearchURL(query: query) else {
                throw BrowseCatalogError.invalidURL
            }
            url = built
        }
        let (data, response) = try await URLSession.shared.data(for: request(url, scryfall: true))
        if let http = response as? HTTPURLResponse, http.statusCode == 404 {
            return CatalogPage(items: [], nextCursor: nil)
        }
        try validate(response)
        let page = try JSONDecoder().decode(ScryfallBrowseCardPage.self, from: data)
        let directory = try await sets(for: .magic)
        let items = page.data.compactMap { card -> CatalogCardSummary? in
            let id = CatalogSetID(game: .magic, providerID: card.setCode.lowercased())
            guard let set = directory.first(where: { $0.catalogID == id }) else { return nil }
            let summary = CatalogCardSummary(
                game: .magic,
                providerID: card.id,
                setID: id,
                setName: set.name,
                setCode: set.code,
                name: card.name,
                collectorNumber: card.collectorNumber,
                thumbnailURL: card.thumbnailImageURL,
                imageURL: card.displayImageURL
            )
            detailCache[summary.id] = CatalogCardDetails(card: .magic(card), set: set)
            return summary
        }
        return CatalogPage(items: items, nextCursor: page.hasMore ? page.nextPage?.absoluteString : nil)
    }

    private func pokemonSet(id: String) async throws -> TCGdexSetCatalog {
        if let cached = pokemonSetDetails[id] { return cached }
        let loaded = try await tcgdex.fetchSet(id: id)
        pokemonSetDetails[id] = loaded
        return loaded
    }

    private func enriched(_ set: CatalogSet, catalog: TCGdexSetCatalog) -> CatalogSet {
        CatalogSet(
            catalogID: set.catalogID,
            name: set.name,
            code: catalog.tcgOnline?.uppercased() ?? set.code,
            logoURL: assetURL(catalog.logo, suffix: ".png") ?? set.logoURL,
            symbolURL: assetURL(catalog.symbol, suffix: ".png") ?? set.symbolURL,
            cardCount: catalog.cardCount.map {
                PokemonMasterSetDefinition.masterCount(
                    cardCount: $0,
                    setName: catalog.name,
                    printRun: set.pokemonPrintRun
                )
            } ?? set.cardCount,
            releaseDate: catalog.releaseDate.flatMap(FlexibleDate.parse),
            sortRank: set.sortRank
        )
    }

    private func pokemonSummary(_ card: TCGdexCardBrief, set: CatalogSet) -> CatalogCardSummary {
        let base = card.image.flatMap { URL(string: $0) }
        return CatalogCardSummary(
            game: .pokemon,
            providerID: card.id,
            setID: set.catalogID,
            setName: set.name,
            setCode: set.code,
            name: card.name,
            collectorNumber: card.localId,
            thumbnailURL: base.flatMap { URL(string: $0.absoluteString + "/low.png") },
            imageURL: base.flatMap { URL(string: $0.absoluteString + "/high.png") }
        )
    }

    /// Set responses intentionally contain only card briefs. Master-set slots
    /// need the per-card variant flags from the card endpoint, so details are
    /// loaded with a small bounded concurrency window and cached for the detail
    /// screen. One failed card fails the page rather than silently publishing an
    /// incomplete checklist as authoritative.
    private func pokemonMasterSetSummaries(
        _ cards: [TCGdexCardBrief],
        set: CatalogSet
    ) async throws -> [CatalogCardSummary] {
        let service = tcgdex
        var iterator = Array(cards.enumerated()).makeIterator()
        var loaded: [(Int, TCGdexCardBrief, TCGdexCard)] = []
        loaded.reserveCapacity(cards.count)

        try await withThrowingTaskGroup(
            of: (Int, TCGdexCardBrief, TCGdexCard).self
        ) { group in
            for _ in 0..<min(8, cards.count) {
                guard let (index, brief) = iterator.next() else { break }
                group.addTask {
                    (index, brief, try await service.fetchCard(id: brief.id))
                }
            }

            while let result = try await group.next() {
                loaded.append(result)
                if let (index, brief) = iterator.next() {
                    group.addTask {
                        (index, brief, try await service.fetchCard(id: brief.id))
                    }
                }
            }
        }

        return loaded.sorted { $0.0 < $1.0 }.flatMap { _, brief, card in
            let base = pokemonSummary(brief, set: set)
            let details = CatalogCardDetails(card: .pokemon(card, setCode: set.code), set: set)
            return PokemonMasterSetDefinition.requiredVariants(
                for: card
            ).map { requirement in
                var summary = base
                summary.masterSetVariant = requirement.variant
                summary.isExpandedMasterSetVariant = requirement.isExpanded
                summary.isSoleSlotForCard = requirement.isSole
                detailCache[summary.id] = details
                return summary
            }
        }
    }

    private func request(_ url: URL, scryfall: Bool = false) -> URLRequest {
        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.cachePolicy = .useProtocolCachePolicy
        if scryfall {
            request.setValue("TradingCardScanner/0.1 (iOS)", forHTTPHeaderField: "User-Agent")
            request.setValue("application/json;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        }
        return request
    }

    private func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw BrowseCatalogError.badResponse
        }
    }

    private func assetURL(_ value: String?, suffix: String) -> URL? {
        value.flatMap { URL(string: $0 + suffix) }
    }

    private func escapedScryfall(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }

    private func deduplicated(_ values: [CatalogCardSummary]) -> [CatalogCardSummary] {
        var seen: Set<String> = []
        return values.filter { seen.insert($0.id).inserted }
    }
}

/// App-private, local-only Browse cache.
///
/// The collection database is intentionally not used here: catalogue downloads
/// are disposable device state, not user inventory, and must never be uploaded
/// to CloudKit. Set directories are small and protected; viewed card/product
/// pages live under separate LRU byte caps.
actor CatalogCacheStore {
    struct Cached<Value: Sendable>: Sendable {
        let value: Value
        let storedAt: Date
        let isFresh: Bool
    }

    static let shared = CatalogCacheStore()

    private static let setDirectoryMaxAge: TimeInterval = 24 * 60 * 60
    private static let sealedSetDirectoryMaxAge: TimeInterval = 7 * 24 * 60 * 60
    private static let sealedProductMaxAge: TimeInterval = 6 * 60 * 60
    private static let cardPageLimit = 25 * 1_024 * 1_024
    private static let sealedPageLimit = 10 * 1_024 * 1_024

    private let root: URL

    init(root: URL? = nil) {
        if let root {
            self.root = root
        } else {
            self.root = FileManager.default
                .urls(for: .applicationSupportDirectory, in: .userDomainMask)
                .first!
                .appendingPathComponent("BrowseCatalogCache", isDirectory: true)
        }
    }

    func sets(for game: CardGame) -> Cached<[CatalogSet]>? {
        load([CatalogSet].self, from: setDirectoryURL(for: game), maxAge: Self.setDirectoryMaxAge)
    }

    func storeSets(_ sets: [CatalogSet], for game: CardGame) {
        store(sets, at: setDirectoryURL(for: game))
    }

    func cardPage(for key: String) -> CatalogPage<CatalogCardSummary>? {
        let url = cardPagesDirectory.appendingPathComponent(filename(for: key))
        guard let cached = load(CatalogPage<CatalogCardSummary>.self, from: url, maxAge: nil) else {
            return nil
        }
        touch(url)
        return cached.value
    }

    func storeCardPage(_ page: CatalogPage<CatalogCardSummary>, for key: String) {
        store(page, at: cardPagesDirectory.appendingPathComponent(filename(for: key)))
        trim(cardPagesDirectory, maximumBytes: Self.cardPageLimit)
    }

    func sealedSets(for game: CardGame) -> Cached<[SealedSetSummary]>? {
        load([SealedSetSummary].self, from: sealedSetDirectoryURL(for: game), maxAge: Self.sealedSetDirectoryMaxAge)
    }

    func storeSealedSets(_ sets: [SealedSetSummary], for game: CardGame) {
        store(sets, at: sealedSetDirectoryURL(for: game))
    }

    func sealedProductPage(for key: String) -> Cached<CatalogPage<SealedProductSummary>>? {
        let url = sealedPagesDirectory.appendingPathComponent(filename(for: key))
        guard let cached = load(CatalogPage<SealedProductSummary>.self, from: url, maxAge: Self.sealedProductMaxAge) else {
            return nil
        }
        touch(url)
        return cached
    }

    func storeSealedProductPage(_ page: CatalogPage<SealedProductSummary>, for key: String) {
        store(page, at: sealedPagesDirectory.appendingPathComponent(filename(for: key)))
        trim(sealedPagesDirectory, maximumBytes: Self.sealedPageLimit)
    }

    static func cardPageKey(for set: CatalogSet, cursor: String?) -> String {
        "cards|\(set.id)|\(cursor ?? "initial")"
    }

    static func sealedPageKey(game: CardGame, setID: String?, query: String?, offset: Int) -> String {
        "sealed|\(game.rawValue)|\(setID ?? "all")|\(query?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? "")|\(offset)"
    }

    private var cardPagesDirectory: URL { root.appendingPathComponent("CardPages", isDirectory: true) }
    private var sealedPagesDirectory: URL { root.appendingPathComponent("SealedPages", isDirectory: true) }

    private func setDirectoryURL(for game: CardGame) -> URL {
        root.appendingPathComponent("Sets-\(game.rawValue).json")
    }

    private func sealedSetDirectoryURL(for game: CardGame) -> URL {
        root.appendingPathComponent("SealedSets-\(game.rawValue).json")
    }

    private func load<Value: Codable & Sendable>(
        _ type: Value.Type,
        from url: URL,
        maxAge: TimeInterval?
    ) -> Cached<Value>? {
        guard let data = try? Data(contentsOf: url),
              let envelope = try? JSONDecoder().decode(CacheEnvelope<Value>.self, from: data) else {
            return nil
        }
        let isFresh = maxAge.map { Date.now.timeIntervalSince(envelope.storedAt) < $0 } ?? true
        return Cached(value: envelope.value, storedAt: envelope.storedAt, isFresh: isFresh)
    }

    private func store<Value: Codable & Sendable>(_ value: Value, at url: URL) {
        let directory = url.deletingLastPathComponent()
        guard (try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)) != nil,
              let data = try? JSONEncoder().encode(CacheEnvelope(storedAt: .now, value: value)) else {
            return
        }
        try? data.write(to: url, options: .atomic)
    }

    private func touch(_ url: URL) {
        try? FileManager.default.setAttributes([.modificationDate: Date.now], ofItemAtPath: url.path)
    }

    private func trim(_ directory: URL, maximumBytes: Int) {
        let keys: Set<URLResourceKey> = [.fileSizeKey, .contentModificationDateKey]
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        ) else { return }

        let files = urls.compactMap { url -> (url: URL, size: Int, date: Date)? in
            guard let values = try? url.resourceValues(forKeys: keys) else { return nil }
            return (url, values.fileSize ?? 0, values.contentModificationDate ?? .distantPast)
        }.sorted { $0.date < $1.date }

        var total = files.reduce(0) { $0 + $1.size }
        for file in files where total > maximumBytes {
            guard (try? FileManager.default.removeItem(at: file.url)) != nil else { continue }
            total -= file.size
        }
    }

    private func filename(for key: String) -> String {
        // Stable FNV-1a avoids putting long, provider-supplied cursors directly
        // into filesystem paths while keeping cache keys deterministic.
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in key.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(hash, radix: 16) + ".json"
    }
}

private struct CacheEnvelope<Value: Codable>: Codable {
    let storedAt: Date
    let value: Value
}

enum PokemonMasterSetDefinition {
    /// The English sets that were actually printed in two runs, by TCGdex set id.
    ///
    /// Keyed by id rather than by name because names vary between TCGdex and the
    /// printed product — "Expedition" and "Expedition Base Set" needed two
    /// entries in the name-matched version — while ids do not.
    ///
    /// This is a closed historical fact, not a heuristic to keep current: the
    /// 1st Edition stamp ran from Base Set to Neo Destiny and was never used
    /// again, so nothing will ever join this list. Verified against TCGdex's own
    /// `cardCount.firstEd`, which is non-zero for these ten sets and
    /// zero for Base Set 2, Legendary Collection and the whole e-card era.
    ///
    /// The e-card sets used to be listed here, which invented a "Skyridge — 1st
    /// Edition" master set that never existed, split the real set's completion
    /// across two impossible halves, and then asked the price vendor for a
    /// printing no marketplace carries.
    private static let firstEditionSetIDs: Set<String> = [
        "base1", "base2", "base3", "base5",
        "gym1", "gym2",
        "neo1", "neo2", "neo3", "neo4"
    ]

    /// Base Set alone had a third run: the shadowless print that sits between
    /// 1st Edition and the shadowed Unlimited cards.
    private static let shadowlessSetID = "base1"

    static func virtualSets(
        _ set: CatalogSet,
        cardCount: TCGdexCardCount? = nil
    ) -> [CatalogSet] {
        guard set.game == .pokemon else { return [set] }
        let runs = printRuns(forSetProviderID: set.providerID)
        guard !runs.isEmpty else {
            // One run, so no qualifier: the set stands as itself rather than
            // being relabelled "— Unlimited" against nothing.
            return [set]
        }
        return runs.map { run in
            CatalogSet(
                catalogID: CatalogSetID(
                    game: .pokemon,
                    providerID: set.providerID,
                    pokemonPrintRun: run
                ),
                name: "\(set.name) — \(run.label)",
                code: set.code,
                logoURL: set.logoURL,
                symbolURL: set.symbolURL,
                cardCount: cardCount.map {
                    masterCount(cardCount: $0, setName: set.name, printRun: run)
                } ?? set.cardCount.map {
                    adjustedCount($0, setName: set.name, printRun: run)
                },
                releaseDate: set.releaseDate,
                sortRank: set.sortRank
            )
        }
    }

    /// Whether this set was printed in more than one run.
    ///
    /// Public so the collection can repair rows tagged with a run their set
    /// never had, from when the e-card sets were split.
    static func hasSeparatePrintRuns(setProviderID: String) -> Bool {
        !printRuns(forSetProviderID: setProviderID).isEmpty
    }

    /// The single source of truth for every UI that must ask which physical run
    /// a card belongs to. An empty result means there is no question to ask.
    static func printRuns(forSetProviderID setProviderID: String) -> [PokemonPrintRun] {
        let id = setProviderID.lowercased()
        if id == shadowlessSetID {
            return [.firstEdition, .shadowless, .unlimited]
        }
        if firstEditionSetIDs.contains(id) {
            return [.firstEdition, .unlimited]
        }
        return []
    }

    static func includesInSetDirectory(_ set: TCGdexBrowseSet) -> Bool {
        let name = CatalogIdentityNormalization.canonicalText(set.name)
        let id = set.id.lowercased()
        if ["basep", "swshp", "svp"].contains(id) { return false }
        let excludedPhrases = [
            "black star promo", "promos", "promo cards", "pop series",
            "jumbo", "miscellaneous cards", "battle academy", "deck exclusives",
            "trainer kit", "mcdonald s", "southern islands", "box topper"
        ]
        return !excludedPhrases.contains { name.contains($0) }
    }

    /// TCGdex publishes variation counts directly. Normal plus holo is the
    /// pack-pulled base run (including secrets); reverse is the additional full
    /// parallel. `total` is the fallback when an older set response omits the
    /// variation breakdown.
    static func masterCount(
        cardCount: TCGdexCardCount,
        setName: String,
        printRun: PokemonPrintRun?
    ) -> Int {
        let publishedBase: Int
        if cardCount.normal != nil || cardCount.holo != nil {
            publishedBase = (cardCount.normal ?? 0) + (cardCount.holo ?? 0)
        } else {
            publishedBase = cardCount.total
        }
        let base = printRun == .firstEdition
            ? (cardCount.firstEd ?? publishedBase)
            : publishedBase
        return adjustedCount(
            base + (cardCount.reverse ?? 0),
            setName: setName,
            printRun: printRun
        )
    }

    static func excludes(
        card: TCGdexCardBrief,
        setProviderID: String,
        printRun: PokemonPrintRun?
    ) -> Bool {
        // Every English Base Set Machamp is stamped. There is no distinct
        // Unlimited printing, so it cannot complete the Unlimited run.
        setProviderID.caseInsensitiveCompare("base1") == .orderedSame
            && printRun == .unlimited
            && CatalogIdentityNormalization.localNumber(card.localId) == "8"
    }

    /// The required physical slots for one numbered card. Edition is carried
    /// separately by the virtual set, so the legacy first-edition pseudo-finish
    /// never becomes a second slot. Named parallel patterns are marked as the
    /// expanded tier; the standard tier remains normal, holo and reverse.
    static func requiredVariants(
        for card: TCGdexCard
    ) -> [(variant: PhysicalVariant, isExpanded: Bool, isSole: Bool)] {
        var variants = card.catalogVariants.filter {
            $0.id != PhysicalVariant.firstEdition.id
        }

        // Some early cards publish only the edition flag. They still represent
        // one pack-pulled base slot within that edition.
        if variants.isEmpty {
            variants = [.normal]
        }

        var seen = Set<String>()
        let slots = variants.filter { seen.insert($0.id).inserted }
        return slots.map { variant in
            let isStandard = [
                PhysicalVariant.normal.id,
                PhysicalVariant.holo.id,
                PhysicalVariant.reverse.id
            ].contains(variant.id)
            return (variant, !isStandard, slots.count == 1)
        }
    }

    private static func adjustedCount(
        _ count: Int,
        setName: String,
        printRun: PokemonPrintRun?
    ) -> Int {
        // Base Set Unlimited is one card short: every English Machamp is
        // stamped, so there is no Unlimited printing of it to collect.
        CatalogIdentityNormalization.canonicalText(setName) == "base set"
            && printRun == .unlimited
            ? max(count - 1, 0)
            : count
    }
}

struct TCGdexBrowseSet: Decodable {
    let id: String
    let name: String
    let logo: String?
    let symbol: String?
    let cardCount: TCGdexCardCount?
    let tcgOnline: String?
}

private struct TCGdexSeriesSets: Decodable {
    struct Brief: Decodable { let id: String }
    let sets: [Brief]
}

private struct ScryfallBrowseSetList: Decodable { let data: [ScryfallBrowseSet] }
private struct ScryfallBrowseSet: Decodable {
    let code: String
    let name: String
    let digital: Bool
    let setType: String?
    let releasedAt: String?
    let cardCount: Int?
    let iconSVGURI: URL?

    enum CodingKeys: String, CodingKey {
        case code, name, digital
        case setType = "set_type"
        case releasedAt = "released_at"
        case cardCount = "card_count"
        case iconSVGURI = "icon_svg_uri"
    }
}

private struct ScryfallBrowseCardPage: Decodable {
    let data: [ScryfallCard]
    let hasMore: Bool
    let nextPage: URL?

    enum CodingKeys: String, CodingKey {
        case data
        case hasMore = "has_more"
        case nextPage = "next_page"
    }
}
