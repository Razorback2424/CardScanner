import Foundation
import OSLog

enum YuGiOhEdition: String, CaseIterable, Codable, Sendable {
    case first = "yugioh1stEdition", unlimited = "yugiohUnlimited", limited = "yugiohLimited"
    var tcgplayerSubtype: String {
        switch self { case .first: "1st Edition"; case .unlimited: "Unlimited"; case .limited: "Limited" }
    }
}

struct YuGiOhCatalog: Sendable {
    struct SetInfo: Hashable, Sendable { let groupID: Int; let name: String; let abbreviation: String; let releaseDate: Date? }
    struct Card: Hashable, Sendable { let id: UUID; let name: String; let passcodes: Set<Int> }
    struct Printing: Hashable, Sendable {
        /// Printing-family coverage only. Edition membership and coverage stay
        /// independent. This value travels inside the hashed/signed catalog.
        struct FamilyEvidence: Hashable, Decodable, Sendable {
            let rule: String; let url: String; let sha256: String; let count: Int
            let capturedAt: String; let productsSHA256: String
            let groupID: Int; let codePrefix: String; let language: String; let rarities: [String]
            var isReviewed: Bool {
                guard rule == "konami-release-family-v1", count > 0, groupID > 0, language == "en",
                      !rarities.isEmpty, Set(rarities).count == rarities.count, rarities.allSatisfy({ !$0.isEmpty }),
                      codePrefix.range(of: "^[A-Z0-9]{2,4}-(?:EN|E)?$", options: .regularExpression) != nil,
                      [sha256, productsSHA256].allSatisfy({ $0.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil }),
                      let source = URLComponents(string: url), source.scheme == "https", source.host == "www.db.yugioh-card.com",
                      source.user == nil, source.password == nil, source.port == nil, source.fragment == nil,
                      source.path == "/yugiohdb/card_search.action" else { return false }
                let queries = source.queryItems ?? []
                guard Set(queries.map(\.name)).count == queries.count else { return false }
                let values = Dictionary(uniqueKeysWithValues: queries.map { ($0.name, $0.value ?? "") })
                return values["ope"] == "1" && values["request_locale"] == "en" && values["rp"] == "99999"
                    && values["pid"]?.range(of: "^[0-9]+$", options: .regularExpression) != nil
            }
        }
        struct Membership: Hashable, Decodable, Sendable {
            let e: YuGiOhEdition; let t: String; let q: Double?; let h: String?; let s: String?; let st: String?
        }
        let id: UUID; let code: String; let set: SetInfo; let card: Card
        let rarity: String; let artLabel: String?
        let productID: Int; let productName: String
        let editions: [YuGiOhEdition]; let coverageVerified: Bool; let editionEvidence: String?
        let pricedEditions: [YuGiOhEdition]
        let membership: [Membership]
        let identityReason: String?
        let canonicalLinkStatus: String?
        let familyEvidence: FamilyEvidence?
        var explicitSelectionSupported: Bool {
            identityReason == nil && !editions.isEmpty && (coverageVerified || !membership.isEmpty)
        }
        let thumbnailURL: URL?; let imageURL: URL?
        var idString: String { id.uuidString.lowercased() }
    }
    enum LoadError: Error { case missingResource, invalidSchema, invalidRow(String) }

    /// Decoded, validated catalog data. Every copy of a catalog shares one
    /// instance, so the bundled seed is decoded at most once per process.
    struct Contents: Sendable {
        let generation: String
        let capturedAt: Date
        let printingsByCode: [String: [Printing]]
        let printingByID: [UUID: Printing]
        let incompleteCodes: Set<String>
        let autoEligibleCodes: Set<String>
        let setsByGroupID: [Int: SetInfo]

        /// Fail-closed data for a bundled handle whose deferred load failed:
        /// lookups find nothing and collection writes are rejected.
        static let empty = Contents(generation: "", capturedAt: .distantPast, printingsByCode: [:], printingByID: [:],
            incompleteCodes: [], autoEligibleCodes: [], setsByGroupID: [:])

        private init(generation: String, capturedAt: Date, printingsByCode: [String: [Printing]],
                     printingByID: [UUID: Printing], incompleteCodes: Set<String>, autoEligibleCodes: Set<String>,
                     setsByGroupID: [Int: SetInfo]) {
            self.generation = generation; self.capturedAt = capturedAt; self.printingsByCode = printingsByCode
            self.printingByID = printingByID; self.incompleteCodes = incompleteCodes
            self.autoEligibleCodes = autoEligibleCodes; self.setsByGroupID = setsByGroupID
        }

        init(data: Data) throws {
            let seed = try JSONDecoder().decode(Seed.self, from: data)
            let iso = ISO8601DateFormatter()
            let plainISO = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let date = iso.date(from: seed.capturedAt) ?? plainISO.date(from: seed.capturedAt)
            let sourceDates = Set(seed.printings.flatMap { ($0.m ?? []).compactMap(\.s) })
            let validSourceDates = Set(sourceDates.filter { plainISO.date(from: $0) != nil || iso.date(from: $0) != nil })
            guard seed.schemaVersion == 1, seed.generation.hasPrefix("yugioh-en-"), seed.generation.count > 10,
                  let date, Set(seed.incompleteCodes).isDisjoint(with: seed.autoEligibleCodes) else { throw LoadError.invalidSchema }
            var sets: [Int: SetInfo] = [:]
            for row in seed.sets {
                guard sets[row.g] == nil else { throw LoadError.invalidRow("duplicate group") }
                sets[row.g] = .init(groupID: row.g, name: row.n, abbreviation: row.a,
                    releaseDate: plainISO.date(from: row.d + "T00:00:00Z"))
            }
            var cards: [Card] = [], cardIDs: Set<UUID> = []
            for row in seed.cards {
                guard let id = UUID(uuidString: row.id), id.uuidString.lowercased() == row.id,
                      cardIDs.insert(id).inserted else { throw LoadError.invalidRow("card") }
                cards.append(.init(id: id, name: row.n, passcodes: Set(row.pc)))
            }
            var byID: [UUID: Printing] = [:], byCode: [String: [Printing]] = [:], products: Set<Int> = []
            for row in seed.printings {
                guard let id = UUID(uuidString: row.id), id.uuidString.lowercased() == row.id, byID[id] == nil,
                      products.insert(row.p).inserted, row.p > 0, cards.indices.contains(row.k), let set = sets[row.g],
                      (YuGiOhCatalog.validCode(row.c) || (row.ir == "unsupportedCode" && !row.c.isEmpty && row.e.isEmpty)), !row.r.isEmpty, !row.pn.isEmpty,
                      Set(row.e).count == row.e.count, Set(row.pe).count == row.pe.count,
                      Set((row.m ?? []).map(\.e)).count == (row.m ?? []).count,
                      row.ec || row.m == nil || Set(row.e) == Set((row.m ?? []).map(\.e)),
                      (row.m ?? []).allSatisfy({ m in
                          row.e.contains(m.e) && ["providerMarket", "providerListing", "independentlyReviewed"].contains(m.t)
                          && m.h.map({ $0.utf8.count == 64 && $0.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) } }) == true
                          && validSourceDates.contains(m.s ?? "")
                          && (m.q.map { $0.isFinite && $0 >= 0 } ?? true)
                          && (m.t != "providerListing" || m.q == nil || m.q == 0)
                      }),
                      !row.ec || (!row.e.isEmpty && row.ee?.isEmpty == false) else {
                    throw LoadError.invalidRow(row.id)
                }
                let printing = Printing(id: id, code: row.c, set: set, card: cards[row.k], rarity: row.r, artLabel: row.art,
                    productID: row.p, productName: row.pn, editions: row.e.sorted { YuGiOhCatalog.editionPriority($0) < YuGiOhCatalog.editionPriority($1) },
                    coverageVerified: row.ec, editionEvidence: row.ee, pricedEditions: row.pe,
                    membership: row.m ?? [], identityReason: row.ir, canonicalLinkStatus: row.canonicalLink, familyEvidence: row.pf,
                    thumbnailURL: row.img.flatMap(URL.init(string:)),
                    imageURL: row.img.flatMap { URL(string: $0.replacingOccurrences(of: "_200w", with: "_in_1000x1000")) })
                byID[id] = printing; byCode[row.c, default: []].append(printing)
            }
            for printing in byID.values where printing.familyEvidence != nil {
                guard let authority = printing.familyEvidence, authority.isReviewed,
                      let captured = plainISO.date(from: authority.capturedAt), captured <= date,
                      printing.set.groupID == authority.groupID, printing.code.hasPrefix(authority.codePrefix), authority.rarities.contains(printing.rarity),
                      printing.artLabel == nil, printing.identityReason == nil, printing.canonicalLinkStatus == "linked",
                      byCode[printing.code]?.count == 1, !seed.incompleteCodes.contains(printing.code) else {
                    throw LoadError.invalidRow("printing family authority")
                }
            }
            for code in seed.autoEligibleCodes {
                guard let family = byCode[code], family.count == 1,
                      family[0].coverageVerified || family[0].familyEvidence != nil, family[0].explicitSelectionSupported,
                      family[0].artLabel == nil else { throw LoadError.invalidRow("automatic eligibility") }
            }
            generation = seed.generation; capturedAt = date; setsByGroupID = sets
            printingByID = byID; printingsByCode = byCode
            incompleteCodes = Set(seed.incompleteCodes); autoEligibleCodes = Set(seed.autoEligibleCodes)
        }
    }

    private let data: LoadOnce<Result<Contents, any Error>>
    /// Supplied by the per-build launch cache so registering the bundled
    /// catalog never forces a decode just to read its generation.
    private let knownGeneration: String?
    var publicationRevision: Int? = nil

    private var contents: Contents { (try? data.get().get()) ?? .empty }
    var generation: String { knownGeneration ?? contents.generation }
    var capturedAt: Date { contents.capturedAt }
    var printingsByCode: [String: [Printing]] { contents.printingsByCode }
    var printingByID: [UUID: Printing] { contents.printingByID }
    var incompleteCodes: Set<String> { contents.incompleteCodes }
    var autoEligibleCodes: Set<String> { contents.autoEligibleCodes }
    var setsByGroupID: [Int: SetInfo] { contents.setsByGroupID }
    /// Whether the data has been decoded. Only the bundled launch handle can
    /// start unloaded; every other catalog decodes during construction.
    var isLoaded: Bool { data.isLoaded }

    var historicalPricingNotice: String {
        let source = publicationRevision == nil ? "a bundled snapshot" : "a verified periodic snapshot"
        return "Yu-Gi-Oh! current quotes use \(source) captured \(capturedAt.formatted(date: .abbreviated, time: .omitted)). Prices keep their source dates. Live per-card quote refresh is unavailable."
    }
    static var bundledPricingNotice: String {
        (try? bundled.get().historicalPricingNotice) ?? "Yu-Gi-Oh! live pricing is unavailable."
    }
    static let unavailablePricingNotice = "Yu-Gi-Oh! pricing source is unavailable. Live per-card refresh is unavailable."

    private struct Seed: Decodable {
        let schemaVersion: Int; let generation: String; let capturedAt: String
        let sets: [SetRow]; let cards: [CardRow]; let printings: [PrintingRow]
        let incompleteCodes: [String]; let autoEligibleCodes: [String]
    }
    private struct SetRow: Decodable { let g: Int; let n: String; let a: String; let d: String }
    private struct CardRow: Decodable { let id: String; let n: String; let pc: [Int] }
    private struct PrintingRow: Decodable {
        let id: String; let c: String; let g: Int; let k: Int; let r: String; let art: String?
        let p: Int; let pn: String; let e: [YuGiOhEdition]; let ec: Bool; let ee: String?
        let pe: [YuGiOhEdition]; let img: String?
        let m: [Printing.Membership]?; let ir: String?
        let canonicalLink: String?
        let pf: Printing.FamilyEvidence?
    }
    init(data: Data) throws {
        let contents = try Contents(data: data)
        self.data = LoadOnce(value: .success(contents))
        knownGeneration = nil
    }

    /// A catalog whose data is decoded on first read. `knownGeneration` must
    /// be the generation `load` produces.
    init(knownGeneration: String?, load: @escaping @Sendable () throws -> Contents) {
        data = LoadOnce { Result { try load() } }
        self.knownGeneration = knownGeneration
    }

    /// Returns this catalog after its data has been decoded, or the load error.
    func loaded() throws -> Self {
        _ = try data.get().get()
        return self
    }

    /// Decodes off the caller's thread so a later synchronous read finds the
    /// data ready instead of decoding on, for example, the main thread.
    func warm() async {
        let data = self.data
        await Task.detached(priority: .utility) { _ = data.get() }.value
    }

    /// Same language as `^[A-Z0-9]{2,4}-(?:(?:EN|E)[A-Z0-9]{3}|[0-9]{3})$`
    /// plus the four `IOC-SE` codes. A byte scan instead of a regex because
    /// the bundled seed checks every one of its ~46,000 printings.
    static func validCode(_ code: String) -> Bool {
        if specialCodes.contains(code) { return true }
        let bytes = Array(code.utf8)
        guard let dash = bytes.firstIndex(of: UInt8(ascii: "-")), (2...4).contains(dash),
              bytes[..<dash].allSatisfy(isUpperAlphanumeric) else { return false }
        let suffix = bytes[(dash + 1)...]
        let E = UInt8(ascii: "E"), N = UInt8(ascii: "N")
        switch suffix.count {
        case 3: return suffix.allSatisfy { (UInt8(ascii: "0")...UInt8(ascii: "9")).contains($0) }
        case 4: return suffix.first == E && suffix.dropFirst().allSatisfy(isUpperAlphanumeric)
        case 5: return suffix.first == E && suffix.dropFirst().first == N && suffix.dropFirst(2).allSatisfy(isUpperAlphanumeric)
        default: return false
        }
    }
    private static let specialCodes: Set<String> = ["IOC-SE1", "IOC-SE2", "IOC-SE3", "IOC-SE4"]
    private static func isUpperAlphanumeric(_ byte: UInt8) -> Bool {
        (UInt8(ascii: "A")...UInt8(ascii: "Z")).contains(byte) || (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte)
    }

    /// The one bundled-seed catalog for the process. It is created without
    /// decoding; the first read of its data loads and validates the seed for
    /// every copy, including those already registered in a runtime.
    static let bundledHandle = YuGiOhCatalog(knownGeneration: YuGiOhBundledLaunch.cachedManifest()?.generation) {
        let interval = PerformanceSignpost.beginInterval(
            "YuGiOh.catalogLoad", id: PerformanceSignpost.makeID(), "main=\(Thread.isMainThread ? 1 : 0)"
        )
        defer { PerformanceSignpost.endInterval("YuGiOh.catalogLoad", interval, "") }
        do {
            return try YuGiOhBundledLaunch.loadSeed()
        } catch {
            // A seed rejected after this launch registered it from the cache
            // must take the eager path, and be marked unavailable, next time.
            YuGiOhBundledLaunch.clear()
            Logger(subsystem: Bundle.main.bundleIdentifier ?? "CardScanner", category: "CatalogBootstrap")
                .error("Yu-Gi-Oh! bundled seed rejected on deferred load; lookups are disabled for this session")
            throw error
        }
    }
    static var bundled: Result<Self, Error> { Result { try bundledHandle.loaded() } }
    private static func editionPriority(_ edition: YuGiOhEdition) -> Int {
        switch edition { case .first: 0; case .unlimited: 1; case .limited: 2 }
    }
}

/// Facts a normal launch needs about the bundled seed before the seed itself.
/// They are cached per app build, so registering Yu-Gi-Oh does not decode the
/// 33 MB catalog. A new build or a changed seed file misses the cache and
/// takes the eager, fully validated path once.
enum YuGiOhBundledLaunch {
    struct Manifest: Codable, Equatable {
        let buildKey: String
        let generation: String
        let capabilities: Int
    }
    static let defaultsKey = "yugioh.bundledLaunchManifest"

    static func seedURL(bundle: Bundle = .main) -> URL? {
        bundle.url(forResource: "catalog", withExtension: "json", subdirectory: "YuGiOhCatalogSeed")
    }

    static func buildKey(bundle: Bundle = .main) -> String? {
        guard let url = seedURL(bundle: bundle),
              let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
              let size = values.fileSize else { return nil }
        let info = bundle.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? ""
        let build = info["CFBundleVersion"] as? String ?? ""
        let modified = values.contentModificationDate?.timeIntervalSince1970 ?? 0
        return "\(version)|\(build)|\(size)|\(modified)"
    }

    static func cachedManifest(defaults: UserDefaults = .standard, bundle: Bundle = .main) -> Manifest? {
        guard let key = buildKey(bundle: bundle), let data = defaults.data(forKey: defaultsKey),
              let manifest = try? JSONDecoder().decode(Manifest.self, from: data),
              manifest.buildKey == key, !manifest.generation.isEmpty, manifest.capabilities != 0 else { return nil }
        return manifest
    }

    static func store(generation: String, capabilities: CardGameCapabilities,
                      defaults: UserDefaults = .standard, bundle: Bundle = .main) {
        guard !capabilities.isEmpty, let key = buildKey(bundle: bundle),
              let data = try? JSONEncoder().encode(Manifest(buildKey: key, generation: generation,
                                                            capabilities: capabilities.rawValue)) else { return }
        defaults.set(data, forKey: defaultsKey)
    }

    static func clear(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: defaultsKey)
    }

    static func loadSeed(bundle: Bundle = .main) throws -> YuGiOhCatalog.Contents {
        guard let url = seedURL(bundle: bundle) else { throw YuGiOhCatalog.LoadError.missingResource }
        return try YuGiOhCatalog.Contents(data: Data(contentsOf: url, options: .mappedIfSafe))
    }
}
