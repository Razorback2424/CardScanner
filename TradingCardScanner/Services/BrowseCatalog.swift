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
    private var setCache: [CardGame: [CatalogSet]] = [:]
    private var detailCache: [String: CatalogCardDetails] = [:]
    private var pokemonSetDetails: [String: TCGdexSetCatalog] = [:]

    func sets(for game: CardGame) async throws -> [CatalogSet] {
        if let cached = setCache[game] { return cached }
        let loaded: [CatalogSet]
        switch game {
        case .pokemon: loaded = try await pokemonSets()
        case .magic: loaded = try await magicSets()
        }
        setCache[game] = loaded
        return loaded
    }

    func cards(in set: CatalogSet, cursor: String?) async throws -> CatalogPage<CatalogCardSummary> {
        switch set.game {
        case .pokemon:
            let catalog = try await pokemonSet(id: set.providerID)
            return CatalogPage(items: catalog.cards.map { pokemonSummary($0, set: enriched(set, catalog: catalog)) }, nextCursor: nil)
        case .magic:
            return try await magicCards(query: "e:\(set.providerID) lang:en game:paper", cursor: cursor)
        }
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

    private func pokemonSets() async throws -> [CatalogSet] {
        guard let url = URL(string: "https://api.tcgdex.net/v2/en/sets?sort:field=releaseDate&sort:order=DESC") else {
            throw BrowseCatalogError.invalidURL
        }
        let (data, response) = try await URLSession.shared.data(for: request(url))
        try validate(response)
        let rows = try JSONDecoder().decode([TCGdexBrowseSet].self, from: data)
        let pocketIDs = (try? await pokemonPocketSetIDs()) ?? []
        let sets = rows.enumerated().compactMap { pair -> CatalogSet? in
            let index = pair.offset
            let row = pair.element
            guard !pocketIDs.contains(row.id.lowercased()) else { return nil }
            return CatalogSet(
                catalogID: CatalogSetID(game: .pokemon, providerID: row.id),
                name: row.name,
                code: row.tcgOnline?.uppercased()
                    ?? SetCodeMap.printedCode(forTCGdexSetID: row.id)
                    ?? row.id.uppercased(),
                logoURL: assetURL(row.logo, suffix: ".png"),
                symbolURL: assetURL(row.symbol, suffix: ".png"),
                cardCount: row.cardCount?.total,
                releaseDate: nil,
                sortRank: rows.count - index
            )
        }
        PokemonCatalogReleaseOrder.install(
            Dictionary(uniqueKeysWithValues: sets.map { ($0.providerID.lowercased(), $0.sortRank) })
        )
        return sets
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
        let summaries = cards.compactMap { card -> CatalogCardSummary? in
            guard let set = directory
                .filter({ card.id.hasPrefix($0.providerID + "-") })
                .max(by: { $0.providerID.count < $1.providerID.count }) else { return nil }
            return pokemonSummary(card, set: set)
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
            name: catalog.name,
            code: catalog.tcgOnline?.uppercased() ?? set.code,
            logoURL: assetURL(catalog.logo, suffix: ".png") ?? set.logoURL,
            symbolURL: assetURL(catalog.symbol, suffix: ".png") ?? set.symbolURL,
            cardCount: catalog.cardCount?.total ?? set.cardCount,
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

private struct TCGdexBrowseSet: Decodable {
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
