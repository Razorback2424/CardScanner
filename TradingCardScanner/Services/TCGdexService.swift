import Foundation

enum TCGdexError: LocalizedError, Sendable {
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

/// Which TCGdex language edition a request is addressed to.
///
/// Japanese-exclusive sets exist only under `ja`, and are 404 on `en`. That
/// edition carries full identity — names, numbering, artwork — and Cardmarket
/// pricing, but no TCGplayer pricing, since these printings are not TCGplayer
/// products. A price for them therefore arrives in euros or not at all.
enum TCGdexLocale: String, Sendable {
    case en
    case ja
}

struct TCGdexService: Sendable {
    func fetchSetDirectory(locale: TCGdexLocale = .en) async throws -> [CatalogSetReference] {
        guard let url = URL(string: "https://api.tcgdex.net/v2/\(locale.rawValue)/sets") else {
            throw TCGdexError.invalidURL
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
            throw TCGdexError.badResponse
        }
        return try JSONDecoder().decode([CatalogSetReference].self, from: data)
    }

    func fetchCard(
        setID: String,
        localID: String,
        ignoringCache: Bool = false,
        timeout: TimeInterval = 8
    ) async throws -> TCGdexCard {
        guard let url = URL(string: "https://api.tcgdex.net/v2/en/sets/\(setID)/\(localID)") else {
            throw TCGdexError.invalidURL
        }
        return try await fetch(url, ignoringCache: ignoringCache, timeout: timeout)
    }

    func fetchSet(id: String, locale: TCGdexLocale = .en) async throws -> TCGdexSetCatalog {
        guard let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://api.tcgdex.net/v2/\(locale.rawValue)/sets/\(encoded)") else {
            throw TCGdexError.invalidURL
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
            throw TCGdexError.badResponse
        }
        return try JSONDecoder().decode(TCGdexSetCatalog.self, from: data)
    }

    /// Direct lookup by catalog id, used when refreshing a card the collection
    /// already owns. There is no identifier to re-validate in that case — the
    /// record is the thing being refreshed.
    func fetchCard(
        id: String,
        locale: TCGdexLocale = .en,
        ignoringCache: Bool = false,
        timeout: TimeInterval = 8
    ) async throws -> TCGdexCard {
        guard let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://api.tcgdex.net/v2/\(locale.rawValue)/cards/\(encoded)") else {
            throw TCGdexError.invalidURL
        }
        return try await fetch(url, ignoringCache: ignoringCache, timeout: timeout)
    }

    private func fetch(
        _ url: URL,
        ignoringCache: Bool = false,
        timeout: TimeInterval = 8
    ) async throws -> TCGdexCard {
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout

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

/// Small secondary Pokémon catalog client. Exact set/number lookup is used only
/// by the scanner when TCGdex is unavailable; artwork lookup remains limited to
/// records whose identity was already established elsewhere.
struct PokemonTCGAPIService: Sendable {
    /// Exact set/number lookup used when TCGdex is unavailable. The response is
    /// still validated by the scanner before it becomes an identified card; this
    /// service only narrows the secondary provider's result set.
    func fetchCard(
        setID: String,
        cardNumber: String,
        timeout: TimeInterval = 4
    ) async throws -> PokemonTCGAPICard? {
        let number = CatalogIdentityNormalization.localNumber(cardNumber)
        let providerID = Self.providerID(setID: setID, cardNumber: cardNumber)
        guard let encodedID = providerID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://api.pokemontcg.io/v2/cards/\(encodedID)") else {
            throw TCGdexError.invalidURL
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        request.setValue("TradingCardScanner/0.1 (iOS)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        guard let data = try await Self.dataRetryingTransientFailures(for: request) else {
            return nil
        }
        let card = try JSONDecoder().decode(PokemonTCGAPISingleResponse.self, from: data).data
        guard CatalogIdentityNormalization.localNumber(card.number) == number,
              card.set.id?.caseInsensitiveCompare(setID) == .orderedSame else {
            return nil
        }
        return card
    }

    /// This provider's card ids use the *unpadded* local number: `me1-25` is a
    /// card and `me1-025` is a 404.
    ///
    /// TCGdex hands modern cards a zero-padded `localId`, and the scanner passes
    /// that straight through. Building the id from the printed number therefore
    /// asked for a record that cannot exist, so the fallback silently never
    /// fired for exactly the cards most likely to be scanned.
    static func providerID(setID: String, cardNumber: String) -> String {
        "\(setID)-\(CatalogIdentityNormalization.localNumber(cardNumber))"
    }

    /// Attempt budget for one fallback lookup. This provider returned 5xx on
    /// roughly two of every five requests when measured, and the same id
    /// alternated 200 and 500 seconds apart — so one attempt throws away a
    /// provider that usually works on the next try. Three attempts and short
    /// backoffs keep the worst case inside a few seconds, because the fallback
    /// runs while someone is holding a card in front of the camera.
    private static let retryBackoff: [Duration] = [.milliseconds(250), .milliseconds(750)]

    /// The response body, or `nil` when the provider says 404.
    ///
    /// 404 is terminal and never retried: a definitive "this provider does not
    /// have that card" must not be churned into a looser answer. Only 5xx and
    /// transport errors are worth a second look.
    private static func dataRetryingTransientFailures(
        for request: URLRequest
    ) async throws -> Data? {
        var lastError: Error = TCGdexError.badResponse

        for attempt in 0...retryBackoff.count {
            if attempt > 0 {
                try await Task.sleep(for: retryBackoff[attempt - 1])
            }
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse else {
                    throw TCGdexError.badResponse
                }
                if http.statusCode == 404 { return nil }
                guard (200..<300).contains(http.statusCode) else {
                    throw TCGdexError.badResponse
                }
                return data
            } catch {
                // Cancellation is the caller withdrawing the question, not the
                // provider failing to answer it.
                if error is CancellationError { throw error }
                if Task.isCancelled { throw error }
                lastError = error
            }
        }

        throw lastError
    }

    func fetchArtwork(
        name: String,
        setName: String,
        cardNumber: String
    ) async throws -> PokemonTCGAPICard? {
        guard var components = URLComponents(string: "https://api.pokemontcg.io/v2/cards") else {
            throw TCGdexError.invalidURL
        }
        let escapedName = name.replacingOccurrences(of: "\"", with: "\\\"")
        let escapedSet = setName.replacingOccurrences(of: "\"", with: "\\\"")
        let number = CatalogIdentityNormalization.localNumber(cardNumber)
        components.queryItems = [
            URLQueryItem(
                name: "q",
                value: "name:\"\(escapedName)\" set.name:\"\(escapedSet)\" number:\"\(number)\""
            ),
            URLQueryItem(name: "pageSize", value: "20"),
            URLQueryItem(name: "select", value: "id,name,number,set,images")
        ]
        guard let url = components.url else { throw TCGdexError.invalidURL }
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.setValue("TradingCardScanner/0.1 (iOS)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else { throw TCGdexError.badResponse }
        let cards = try JSONDecoder().decode(PokemonTCGAPIResponse.self, from: data).data
        let matches = cards.filter {
            CatalogIdentityNormalization.localNumber($0.number) == number
                && CatalogIdentityNormalization.namesMatch(imported: name, catalog: $0.name)
                && CatalogIdentityNormalization.canonicalSetName($0.set.name, game: .pokemon)
                    == CatalogIdentityNormalization.canonicalSetName(setName, game: .pokemon)
        }
        return matches.count == 1 ? matches[0] : nil
    }
}

enum ScryfallError: LocalizedError {
    case invalidURL
    case cardNotFound
    /// The provider answered, but the requested non-card endpoint does not
    /// exist. Keeping this distinct lets card endpoints translate the same HTTP
    /// status into catalog evidence while directory/collection endpoints fail
    /// closed as provider availability, rather than falling into JSON decoding
    /// and scanner retry logic.
    case endpointNotFound
    case badResponse
    case rateLimited(retryAfter: TimeInterval?)
    case providerUnavailable
    case unsupportedPrinting
    case identityMismatch

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Could not build the Scryfall request."
        case .cardNotFound: return "That identifier did not match a Magic card in Scryfall."
        case .endpointNotFound: return "Scryfall did not provide the requested endpoint."
        case .badResponse: return "Scryfall returned an unexpected response."
        case let .rateLimited(retryAfter):
            if let retryAfter {
                return "Scryfall asked us to wait \(Int(retryAfter.rounded(.up))) seconds."
            }
            return "Scryfall asked us to wait before trying again."
        case .providerUnavailable: return "Scryfall is temporarily unavailable."
        case .unsupportedPrinting: return "This printing is not one the scanner supports yet."
        case .identityMismatch: return "Scryfall returned a different card identity."
        }
    }
}

struct ScryfallService: Sendable {
    private static let childSetCache = ScryfallChildSetCache()
    private let breaker: TCGdexCircuitBreaker

    init(breaker: TCGdexCircuitBreaker = .scryfallShared) {
        self.breaker = breaker
    }
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
        let (data, _) = try await requestData(for: request(for: url))

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

    /// Every set that holds tokens or art cards, keyed by the parent code the
    /// cards actually print.
    ///
    /// Deliberately derived from the directory rather than from a naming rule.
    /// `"t" + parent` is right for 188 of 206 token sets, but the 18 exceptions
    /// are Substitute Cards and regional promo tokens — different products that
    /// a prefix rule would happily return instead.
    func fetchChildSets() async throws -> [String: [MagicChildSet]] {
        try await Self.childSetCache.value {
            try await self.fetchChildSetsFromNetwork()
        }
    }

    private func fetchChildSetsFromNetwork() async throws -> [String: [MagicChildSet]] {
        guard let url = URL(string: "https://api.scryfall.com/sets") else {
            throw ScryfallError.invalidURL
        }
        let (data, _) = try await requestData(for: request(for: url))

        let directory = try JSONDecoder().decode(ScryfallSetDirectory.self, from: data)
        var result: [String: [MagicChildSet]] = [:]
        for set in directory.data {
            guard !set.digital,
                  let parent = set.parentSetCode?.uppercased(),
                  let setType = set.setType else { continue }
            // Art series sets are `memorabilia`, not `art_series` — that string
            // is a card *layout* and is not a set type at all. Matching on it
            // would return nothing, which is exactly what the old exclusion list
            // has been doing.
            let kind: MagicContentKind
            switch setType {
            case "token": kind = .token
            case "memorabilia" where set.name.localizedCaseInsensitiveContains("Art Series"):
                kind = .artCard
            default: continue
            }
            result[parent, default: []].append(
                MagicChildSet(
                    code: set.code.uppercased(),
                    name: set.name,
                    parentCode: parent,
                    setType: setType,
                    contentKind: kind
                )
            )
        }
        return result
    }

    /// The child set a printed marker resolves to, or nil when it cannot be
    /// decided.
    ///
    /// Where a parent has several children of one kind, the main set is
    /// preferred: the alternatives are Substitute Cards (`S*`) and Japanese or
    /// Southeast Asia promo tokens (`W*`, `PT*`), which are separate products a
    /// booster-pack scan is not. Preferring the main set serves the common case
    /// without ever silently returning a promo set in its place.
    nonisolated static func childSet(
        for kind: MagicContentKind,
        parentCode: String,
        in directory: [String: [MagicChildSet]]
    ) -> MagicChildSet? {
        let candidates = (directory[parentCode.uppercased()] ?? [])
            .filter { $0.contentKind == kind }
        if candidates.count == 1 { return candidates[0] }
        guard candidates.count > 1 else { return nil }
        // The main token set is conventionally the parent code prefixed with T.
        // Used only to break a tie between known children, never to invent a
        // set code that the directory has not confirmed exists.
        return candidates.first { $0.code == "T" + parentCode.uppercased() }
    }

    func fetchSetDirectory() async throws -> [CatalogSetReference] {
        guard let url = URL(string: "https://api.scryfall.com/sets") else {
            throw ScryfallError.invalidURL
        }
        let (data, _) = try await requestData(for: request(for: url))
        let directory = try JSONDecoder().decode(ScryfallSetDirectory.self, from: data)
        return directory.data.compactMap { set in
            guard !set.digital else { return nil }
            return CatalogSetReference(id: set.code, name: set.name, cardCount: nil)
        }
    }

    func fetchCards(identifiers: [ScryfallCardIdentifier]) async throws -> [ScryfallCard] {
        guard !identifiers.isEmpty,
              identifiers.count <= 75,
              let url = URL(string: "https://api.scryfall.com/cards/collection") else {
            throw ScryfallError.invalidURL
        }
        var request = request(for: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(ScryfallCollectionRequest(identifiers: identifiers))
        let (data, _) = try await requestData(for: request)
        return try JSONDecoder().decode(ScryfallCollectionResponse.self, from: data).data
    }

    /// Direct lookup by Scryfall id, for refreshing an owned printing.
    func fetchCard(id: String, ignoringCache: Bool = false) async throws -> ScryfallCard {
        guard let encoded = Self.encodedPathSegment(id),
              let url = URL(string: "https://api.scryfall.com/cards/\(encoded)") else {
            throw ScryfallError.invalidURL
        }
        do {
            let (data, _) = try await requestData(
                for: request(for: url, ignoringCache: ignoringCache)
            )
            return try JSONDecoder().decode(ScryfallCard.self, from: data)
        } catch ScryfallError.endpointNotFound {
            throw ScryfallError.cardNotFound
        }
    }

    func fetchCard(
        setCode: String,
        collectorNumber: String,
        language: String,
        ignoringCache: Bool = false,
        requiresScannableCard: Bool = true
    ) async throws -> ScryfallCard {
        let normalizedSet = setCode.lowercased()
        let normalizedLanguage = language.lowercased()
        guard let url = Self.cardLookupURL(
            setCode: normalizedSet,
            collectorNumber: collectorNumber,
            language: normalizedLanguage
        ) else {
            throw ScryfallError.invalidURL
        }
        let data: Data
        do {
            (data, _) = try await requestData(
                for: request(for: url, ignoringCache: ignoringCache)
            )
        } catch ScryfallError.endpointNotFound {
            throw ScryfallError.cardNotFound
        }

        let card = try JSONDecoder().decode(ScryfallCard.self, from: data)
        guard card.setCode.lowercased() == normalizedSet,
              Self.canonicalProviderCollectorNumber(card.collectorNumber)
                == Self.canonicalScannedCollectorNumber(collectorNumber),
              card.language.lowercased() == normalizedLanguage,
              !card.digital else {
            throw ScryfallError.identityMismatch
        }
        if requiresScannableCard {
            try validateSupported(card)
        }
        return card
    }

    /// A single guarded transport seam keeps every Scryfall endpoint behind the
    /// same circuit. A 429 uses the server's Retry-After value when present;
    /// 5xx and transport failures use the exponential provider breaker.
    private func requestData(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        guard await breaker.permitsRequest() else {
            throw ScryfallError.providerUnavailable
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                await breaker.recordFailure(.unreachable)
                throw ScryfallError.providerUnavailable
            }
            // A missing card is definitive catalog evidence, but a missing
            // directory/collection endpoint is provider availability trouble
            // from the caller's point of view. The two card endpoints translate
            // this shared transport error to `cardNotFound`; every other
            // endpoint keeps `endpointNotFound` so it cannot become a decoding
            // error and re-enter scanner retry logic.
            if http.statusCode == 404 {
                await breaker.recordSuccess()
                throw ScryfallError.endpointNotFound
            }
            if http.statusCode == 429 {
                let serverRetryAfter = Self.retryAfter(
                    from: http.value(forHTTPHeaderField: "Retry-After"),
                    now: .now
                )
                // A zero/expired header is still a rate-limit signal. Keep a
                // small provider-specific floor so a fleet of newly presented
                // cards cannot turn that response into a tight retry loop.
                let retryAfter = max(
                    serverRetryAfter ?? TCGdexCircuitBreaker.Failure.rateLimited.base,
                    TCGdexCircuitBreaker.Failure.rateLimited.base
                )
                await breaker.recordFailure(
                    .rateLimited,
                    cooldownOverride: retryAfter
                )
                throw ScryfallError.rateLimited(retryAfter: retryAfter)
            }
            guard (200..<300).contains(http.statusCode) else {
                await breaker.recordFailure(.serverError)
                throw ScryfallError.providerUnavailable
            }
            await breaker.recordSuccess()
            return (data, http)
        } catch let error as ScryfallError {
            throw error
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            await breaker.recordFailure(.unreachable)
            throw ScryfallError.providerUnavailable
        }
    }

    nonisolated private static func retryAfter(from value: String?, now: Date) -> TimeInterval? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else { return nil }
        if let seconds = TimeInterval(value), seconds >= 0 { return seconds }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return formatter.date(from: value).map { max($0.timeIntervalSince(now), 0) }
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

    /// Constructs a lookup URL from path segments rather than interpolating
    /// collector text into a raw URL. This matters for literal Scryfall values
    /// such as `★`, spaces inserted by OCR, and any future collector-number
    /// punctuation that must not become a second path segment.
    static func cardLookupURL(
        setCode: String,
        collectorNumber: String,
        language: String
    ) -> URL? {
        guard let set = encodedPathSegment(setCode.lowercased()),
              let number = encodedPathSegment(collectorNumber),
              let language = encodedPathSegment(language.lowercased()) else {
            return nil
        }
        return URL(string: "https://api.scryfall.com/cards/\(set)/\(number)/\(language)")
    }

    private static func encodedPathSegment(_ value: String) -> String? {
        let allowed = CharacterSet.urlPathAllowed.subtracting(
            CharacterSet(charactersIn: "/?#")
        )
        return value.addingPercentEncoding(withAllowedCharacters: allowed)
    }

    /// Canonicalises text produced by OCR. O/I/L are the known numeric
    /// confusions, so they are corrected only on this side of the identity
    /// comparison.
    static func canonicalScannedCollectorNumber(_ value: String) -> String {
        canonicalNumber(value, correctingOCR: true)
    }

    /// Canonicalises Scryfall's authoritative collector number without applying
    /// OCR corrections. Leading zeroes and case are presentation differences;
    /// O/I/L in the provider value are data and must remain data.
    static func canonicalProviderCollectorNumber(_ value: String) -> String {
        canonicalNumber(value, correctingOCR: false)
    }

    private static func canonicalNumber(_ value: String, correctingOCR: Bool) -> String {
        let compact = value.filter { !$0.isWhitespace }
        guard !compact.isEmpty else { return compact }

        let numericCharacters = correctingOCR
            ? Set("0123456789OILoil")
            : Set("0123456789")
        var numericText = ""
        for character in compact {
            guard numericCharacters.contains(character) else { break }
            numericText.append(character)
        }
        guard !numericText.isEmpty else {
            return compact.lowercased()
        }

        let numeric = correctingOCR
            ? ScanText.normalizedInteger(numericText.uppercased())
            : Int(numericText)
        guard let numeric else { return compact.lowercased() }
        return String(numeric) + compact.dropFirst(numericText.count).lowercased()
    }
}

/// Session-scoped, coalescing cache for Scryfall's relatively static set
/// directory. The actor prevents a burst of token/art-card scans from starting
/// one `/sets` request per identifier.
private actor ScryfallChildSetCache {
    private let lifetime: TimeInterval = 60 * 60
    private var cached: [String: [MagicChildSet]]?
    private var fetchedAt: Date?
    private var inFlight: Task<[String: [MagicChildSet]], Error>?

    func value(
        loader: @escaping @Sendable () async throws -> [String: [MagicChildSet]]
    ) async throws -> [String: [MagicChildSet]] {
        if let cached, let fetchedAt, Date.now.timeIntervalSince(fetchedAt) < lifetime {
            return cached
        }
        if let inFlight { return try await inFlight.value }

        let task = Task { try await loader() }
        inFlight = task
        defer { inFlight = nil }
        let value = try await task.value
        cached = value
        fetchedAt = .now
        return value
    }
}

struct CatalogSetReference: Decodable, Sendable {
    let id: String
    let name: String
    /// Present in TCGdex's set directory and absent in Scryfall's. Existing
    /// name-based consumers deliberately ignore it; historical scan candidacy
    /// uses `official` because that is the denominator printed on the card.
    let cardCount: TCGdexCardCount?
}

struct PokemonCatalogCardIdentity: Equatable, Hashable, Sendable {
    let providerID: String
    let setID: String
    let setName: String
    let localID: String
    let name: String
}

enum PokemonHistoricalIdentityResolution: Equatable, Sendable {
    case unique(PokemonCatalogCardIdentity)
    case ambiguous([PokemonCatalogCardIdentity])
    case unsupported
}

/// Pure, strict historical matching policy. Network and caching live outside
/// this type so every collision can be tested with deterministic fixtures.
enum PokemonHistoricalIdentityResolver {
    /// Subset denominators describe a gallery or holo sequence rather than the
    /// containing set. They therefore cannot be derived from `cardCount` and
    /// remain an explicit numbering-scheme mapping.
    private static let subsetCandidateSets: [String: [Int: [String]]] = [
        "H": [32: ["ecard2", "ecard3"]],
        "TG": [30: ["swsh9tg", "swsh10tg", "swsh11tg", "swsh12tg"]],
        "GG": [70: ["swsh12.5gg"]],
        "RC": [25: ["bw11"], 32: ["g1"]]
    ]

    /// Whether the printed numbering shape is one this resolver understands.
    /// Ordinary denominators remain open-ended; the live directory decides
    /// whether any sets actually publish that official count.
    static func canAttempt(_ number: PokemonPrintedNumberEvidence) -> Bool {
        switch number.scheme {
        case .officialSet:
            return true
        case let .subset(prefix):
            return subsetCandidateSets[prefix]?[number.denominator] != nil
        }
    }

    static func candidateSetIDs(
        for evidence: PokemonHistoricalScanEvidence,
        in directory: [CatalogSetReference]
    ) -> [String] {
        candidateSetIDs(for: evidence.number, in: directory)
    }

    static func candidateSetIDs(
        for number: PokemonPrintedNumberEvidence,
        in directory: [CatalogSetReference]
    ) -> [String] {
        let ids: [String]
        switch number.scheme {
        case .officialSet:
            ids = directory.compactMap { set in
                set.cardCount?.official == number.denominator ? set.id : nil
            }
        case let .subset(prefix):
            ids = subsetCandidateSets[prefix]?[number.denominator] ?? []
        }
        return Array(Set(ids.map { $0.lowercased() })).sorted()
    }

    static func resolve(
        _ evidence: PokemonHistoricalScanEvidence,
        candidateSetIDs: [String],
        in cards: [PokemonCatalogCardIdentity]
    ) -> PokemonHistoricalIdentityResolution {
        let setIDs = Set(candidateSetIDs.map { $0.lowercased() })
        guard !setIDs.isEmpty else { return .unsupported }

        let localID = canonicalLocalID(evidence.number.localID)
        let titles = Set(evidence.titleCandidates)
        let matches = cards.filter { card in
            setIDs.contains(card.setID.lowercased())
                && canonicalLocalID(card.localID) == localID
                && titles.contains(CatalogIdentityNormalization.canonicalText(card.name))
        }
        let unique = Dictionary(
            matches.map { ($0.providerID, $0) },
            uniquingKeysWith: { first, _ in first }
        ).values.sorted {
            if $0.setID != $1.setID { return $0.setID < $1.setID }
            return $0.providerID < $1.providerID
        }

        switch unique.count {
        case 1: return .unique(unique[0])
        case 2...: return .ambiguous(unique)
        default: return .unsupported
        }
    }

    static func identities(in catalogs: [TCGdexSetCatalog]) -> [PokemonCatalogCardIdentity] {
        catalogs.flatMap { set in
            set.cards.map { card in
                PokemonCatalogCardIdentity(
                    providerID: card.id,
                    setID: set.id,
                    setName: set.name,
                    localID: card.localId,
                    name: card.name
                )
            }
        }
    }

    static func canonicalLocalID(_ raw: String) -> String {
        let compact = raw.uppercased().filter { !$0.isWhitespace }
        let prefix = compact.prefix { $0.isLetter }
        let suffix = compact.dropFirst(prefix.count)
        guard let number = Int(suffix) else { return compact }
        return "\(prefix)\(number)"
    }
}

/// One entry in a Scryfall `/cards/collection` request.
///
/// Scryfall accepts either `set` + `collector_number` or `set` + `name`. The
/// second form exists here for sets whose printed collector numbers are not what
/// Scryfall files them under — The List numbers its cards `MM2-48`, carrying the
/// original set's code, while every marketplace export writes plain `48`.
struct ScryfallCardIdentifier: Encodable, Hashable, Sendable {
    /// Scryfall's collection endpoint accepts an exact card id as well as the
    /// set/collector-number form. Exact ids are the only safe identifier for
    /// the treatment migration: set plus number can still name more than one
    /// printing across Magic's history.
    let id: String?
    let set: String?
    let collectorNumber: String?
    let name: String?

    init(set: String, collectorNumber: String) {
        self.id = nil
        self.set = set
        self.collectorNumber = collectorNumber
        self.name = nil
    }

    init(set: String, name: String) {
        self.id = nil
        self.set = set
        self.collectorNumber = nil
        self.name = name
    }

    init(id: String) {
        self.id = id
        self.set = nil
        self.collectorNumber = nil
        self.name = nil
    }

    enum CodingKeys: String, CodingKey {
        case id
        case set
        case collectorNumber = "collector_number"
        case name
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if let id {
            try container.encode(id, forKey: .id)
            return
        }
        guard let set else {
            throw EncodingError.invalidValue(
                self,
                EncodingError.Context(
                    codingPath: encoder.codingPath,
                    debugDescription: "A Scryfall collection identifier needs an id or set"
                )
            )
        }
        try container.encode(set, forKey: .set)
        try container.encodeIfPresent(collectorNumber, forKey: .collectorNumber)
        try container.encodeIfPresent(name, forKey: .name)
    }
}

private struct ScryfallCollectionRequest: Encodable {
    let identifiers: [ScryfallCardIdentifier]
}

private struct ScryfallCollectionResponse: Decodable {
    let data: [ScryfallCard]
}

private struct ScryfallSetDirectory: Decodable {
    let data: [ScryfallSet]
}

private struct ScryfallSet: Decodable {
    let code: String
    let name: String
    let digital: Bool
    let setType: String?
    let releasedAt: String?
    let printedSize: Int?
    /// The set whose footer is printed on these cards.
    ///
    /// Tokens and art cards never print their own Scryfall code. A Clue token
    /// from Marvel Super Heroes reads `T 0017 MSH EN` — the *parent's* code —
    /// while Scryfall files it under `tmsh`. Without this field there is no way
    /// to get from what is printed to what is stored.
    let parentSetCode: String?

    enum CodingKeys: String, CodingKey {
        case code, name, digital
        case setType = "set_type"
        case releasedAt = "released_at"
        case printedSize = "printed_size"
        case parentSetCode = "parent_set_code"
    }
}

/// One Scryfall set that holds tokens or art cards for a parent set.
///
/// Built from the same directory response the scanner already fetches, so
/// supporting tokens costs no extra request.
struct MagicChildSet: Equatable, Sendable {
    let code: String
    let name: String
    let parentCode: String
    let setType: String
    let contentKind: MagicContentKind
}
