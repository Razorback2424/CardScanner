import Foundation

enum TCGdexError: LocalizedError {
    case invalidURL
    case cardNotFound
    case badResponse
    case identityMismatch

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Could not build the TCGdex request."
        case .cardNotFound: return "That identifier did not match a card in TCGdex."
        case .badResponse: return "TCGdex returned an unexpected response."
        case .identityMismatch: return "TCGdex returned a different card identity."
        }
    }
}

struct TCGdexService {
    func fetchCard(setID: String, localID: String) async throws -> TCGdexCard {
        guard let url = URL(string: "https://api.tcgdex.net/v2/en/sets/\(setID)/\(localID)") else {
            throw TCGdexError.invalidURL
        }
        return try await fetch(url)
    }

    /// Direct lookup by catalog id, used when refreshing a card the collection
    /// already owns. There is no identifier to re-validate in that case — the
    /// record is the thing being refreshed.
    func fetchCard(id: String, ignoringCache: Bool = false) async throws -> TCGdexCard {
        guard let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://api.tcgdex.net/v2/en/cards/\(encoded)") else {
            throw TCGdexError.invalidURL
        }
        return try await fetch(url, ignoringCache: ignoringCache)
    }

    private func fetch(_ url: URL, ignoringCache: Bool = false) async throws -> TCGdexCard {
        var request = URLRequest(url: url)
        request.timeoutInterval = 8

        // Respect normal HTTP cache validation. Unlike returnCacheDataElseLoad,
        // this allows mutable pricing data to refresh when the server says it should.
        // An explicit price refresh skips the cache entirely: telling the user the
        // prices were checked means they were actually checked.
        request.cachePolicy = ignoringCache ? .reloadIgnoringLocalCacheData : .useProtocolCachePolicy

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw TCGdexError.badResponse
        }

        if http.statusCode == 404 {
            throw TCGdexError.cardNotFound
        }

        guard (200..<300).contains(http.statusCode) else {
            throw TCGdexError.badResponse
        }

        return try JSONDecoder().decode(TCGdexCard.self, from: data)
    }
}

enum ScryfallError: LocalizedError {
    case invalidURL
    case cardNotFound
    case badResponse
    case unsupportedPrinting
    case identityMismatch

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Could not build the Scryfall request."
        case .cardNotFound: return "That identifier did not match a Magic card in Scryfall."
        case .badResponse: return "Scryfall returned an unexpected response."
        case .unsupportedPrinting: return "This printing is not one the scanner supports yet."
        case .identityMismatch: return "Scryfall returned a different card identity."
        }
    }
}

struct ScryfallService {
    /// Magic 2015 introduced the printed collector-number footer this scanner
    /// reads. Before it there is no printed identifier to have read, so an older
    /// printing cannot be what is in front of the camera.
    private static let modernFooterStart = "2014-07-18"

    /// Scryfall groups things that are not collectible card faces under their own
    /// set codes. None of these are ever printed in a card footer, and every one
    /// of them added to the OCR vocabulary is another chance for a false match.
    private static let unprintedSetTypes: Set<String> = [
        "token", "memorabilia", "minigame", "art_series"
    ]

    /// Layouts that are not a single scannable card. Denied rather than allowed,
    /// so a layout Scryfall adds later is supported by default instead of being
    /// silently rejected.
    private static let unsupportedLayouts: Set<String> = [
        "token", "double_faced_token", "emblem", "art_series",
        "vanguard", "scheme", "planar", "augment", "host"
    ]

    func fetchSupportedSets() async throws -> [MagicSetDefinition] {
        guard let url = URL(string: "https://api.scryfall.com/sets") else {
            throw ScryfallError.invalidURL
        }
        let (data, response) = try await URLSession.shared.data(for: request(for: url))
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw ScryfallError.badResponse
        }

        let directory = try JSONDecoder().decode(ScryfallSetDirectory.self, from: data)
        return directory.data.compactMap { set in
            let code = set.code.uppercased()
            // Three characters is the common printed footer code, but not the
            // only one: The List prints PLST and Mystery Booster playtest cards
            // print CMB1/CMB2. Restricting to exactly three made those
            // unscannable for no reason. The set-type filter above is what keeps
            // the wider length from flooding the vocabulary with Scryfall's
            // internal token and art-series codes.
            guard !set.digital,
                  (set.releasedAt ?? "") >= Self.modernFooterStart,
                  !Self.unprintedSetTypes.contains(set.setType ?? ""),
                  (3...4).contains(code.count),
                  code.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) }) else {
                return nil
            }
            return MagicSetDefinition(code: code, printedSize: set.printedSize)
        }
        .sorted { $0.code < $1.code }
    }

    /// Direct lookup by Scryfall id, for refreshing an owned printing.
    func fetchCard(id: String, ignoringCache: Bool = false) async throws -> ScryfallCard {
        guard let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://api.scryfall.com/cards/\(encoded)") else {
            throw ScryfallError.invalidURL
        }
        let (data, response) = try await URLSession.shared.data(for: request(for: url, ignoringCache: ignoringCache))
        guard let http = response as? HTTPURLResponse else { throw ScryfallError.badResponse }
        if http.statusCode == 404 { throw ScryfallError.cardNotFound }
        guard (200..<300).contains(http.statusCode) else { throw ScryfallError.badResponse }
        return try JSONDecoder().decode(ScryfallCard.self, from: data)
    }

    func fetchCard(setCode: String, collectorNumber: String, language: String) async throws -> ScryfallCard {
        let normalizedSet = setCode.lowercased()
        let normalizedLanguage = language.lowercased()
        guard let url = URL(string: "https://api.scryfall.com/cards/\(normalizedSet)/\(collectorNumber)/\(normalizedLanguage)") else {
            throw ScryfallError.invalidURL
        }
        let (data, response) = try await URLSession.shared.data(for: request(for: url))
        guard let http = response as? HTTPURLResponse else { throw ScryfallError.badResponse }
        if http.statusCode == 404 { throw ScryfallError.cardNotFound }
        guard (200..<300).contains(http.statusCode) else { throw ScryfallError.badResponse }

        let card = try JSONDecoder().decode(ScryfallCard.self, from: data)
        guard card.setCode.lowercased() == normalizedSet,
              canonicalNumber(card.collectorNumber) == canonicalNumber(collectorNumber),
              card.language.lowercased() == normalizedLanguage,
              !card.digital else {
            throw ScryfallError.identityMismatch
        }
        try validateSupported(card)
        return card
    }

    /// What the scanner is prepared to record, stated explicitly.
    ///
    /// This used to be `frame == "2015"`, which rejected any printing whose frame
    /// metadata differed — including retro-frame reprints and other modern
    /// treatments that carry exactly the printed footer the scanner just read.
    /// Rejecting a card the scanner correctly identified, because of a cosmetic
    /// field, is not accuracy. What actually matters is that the printing has the
    /// modern collector-number footer and is a real single card.
    private func validateSupported(_ card: ScryfallCard) throws {
        if let released = card.releasedAt, released < Self.modernFooterStart {
            throw ScryfallError.unsupportedPrinting
        }
        if let layout = card.layout, Self.unsupportedLayouts.contains(layout) {
            throw ScryfallError.unsupportedPrinting
        }
    }

    private func request(for url: URL, ignoringCache: Bool = false) -> URLRequest {
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        request.cachePolicy = ignoringCache ? .reloadIgnoringLocalCacheData : .useProtocolCachePolicy
        request.setValue("TradingCardScanner/0.1 (iOS)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        return request
    }

    private func canonicalNumber(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return Int(trimmed).map(String.init) ?? trimmed
    }
}

private struct ScryfallSetDirectory: Decodable {
    let data: [ScryfallSet]
}

private struct ScryfallSet: Decodable {
    let code: String
    let digital: Bool
    let setType: String?
    let releasedAt: String?
    let printedSize: Int?

    enum CodingKeys: String, CodingKey {
        case code, digital
        case setType = "set_type"
        case releasedAt = "released_at"
        case printedSize = "printed_size"
    }
}
