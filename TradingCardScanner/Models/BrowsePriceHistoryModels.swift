import Foundation

/// The market sources that are allowed to create device-local Browse history.
/// This deliberately is not the unrestricted `PriceSource` enum used by the
/// owned-card pricing system.
enum BrowsePriceMarketSource: String, Codable, Hashable, Sendable {
    case tcgplayer
    case scryfall
}

/// The transport that delivered a market quote. It is observation provenance,
/// not part of a visible series identity, so a future provider cutover can keep
/// one continuous series for the same card and finish.
enum BrowsePriceTransport: String, Codable, Hashable, Sendable {
    case scryfall
    case pokemonTCGIO
    case tcgdex
}

/// A provider-day represented in UTC. Keeping the raw value date-only makes
/// equality and retention independent of the device's local timezone.
struct BrowsePriceDay: RawRepresentable, Codable, Hashable, Comparable, Sendable {
    let rawValue: String

    init?(rawValue: String) {
        let pieces = rawValue.split(separator: "-", omittingEmptySubsequences: false)
        guard pieces.count == 3,
              pieces[0].count == 4,
              pieces[1].count == 2,
              pieces[2].count == 2,
              let year = Int(pieces[0]),
              let month = Int(pieces[1]),
              let day = Int(pieces[2]) else {
            return nil
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        var components = DateComponents()
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        components.year = year
        components.month = month
        components.day = day
        guard let date = calendar.date(from: components),
              calendar.dateComponents([.year, .month, .day], from: date).year == year,
              calendar.dateComponents([.year, .month, .day], from: date).month == month,
              calendar.dateComponents([.year, .month, .day], from: date).day == day else {
            return nil
        }
        self.rawValue = rawValue
    }

    init(date: Date) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        self.rawValue = String(
            format: "%04ld-%02ld-%02ld",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }

    var date: Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let pieces = rawValue.split(separator: "-")
        var components = DateComponents()
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        components.year = Int(pieces[0])
        components.month = Int(pieces[1])
        components.day = Int(pieces[2])
        return calendar.date(from: components) ?? .distantPast
    }

    func adding(days: Int) -> BrowsePriceDay {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let date = calendar.date(byAdding: .day, value: days, to: self.date) ?? self.date
        return BrowsePriceDay(date: date)
    }

    static func < (lhs: BrowsePriceDay, rhs: BrowsePriceDay) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Explicit persistence identity for a physical finish/parallel. Never replace
/// this with synthesized `PhysicalVariant` Codable: the runtime model may gain
/// presentation fields without changing the persisted Browse series identity.
struct BrowsePriceVariantDescriptor: Codable, Hashable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let value: String
}

struct BrowsePriceSeriesKey: Codable, Hashable, Sendable {
    let printingID: String
    let variantDescriptor: BrowsePriceVariantDescriptor
    let marketSource: BrowsePriceMarketSource
}

struct BrowsePriceHistoryPoint: Codable, Hashable, Sendable {
    let day: BrowsePriceDay
    let amountUSD: Double
    let providerUpdatedAt: Date
    let transportProvider: BrowsePriceTransport
}

struct BrowsePricePersistedSeries: Codable, Hashable, Sendable {
    let key: BrowsePriceSeriesKey
    var points: [BrowsePriceHistoryPoint]
}

struct BrowsePriceHistorySetFile: Codable, Hashable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let game: CardGame
    let setID: String
    var lastAccessedAt: Date
    var series: [BrowsePricePersistedSeries]

    init(
        game: CardGame,
        setID: String,
        lastAccessedAt: Date = .now,
        series: [BrowsePricePersistedSeries] = []
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.game = game
        self.setID = setID
        self.lastAccessedAt = lastAccessedAt
        self.series = series
    }
}

/// A normalized price that is eligible for Browse history. Construction fails
/// closed for unsupported sources, non-USD amounts, missing provider dates, and
/// unrepresentable physical variants.
struct BrowsePriceQuote: Sendable, Hashable {
    let printingID: String
    let setID: String
    let variant: PhysicalVariant
    let amountUSD: Double
    let marketSource: BrowsePriceMarketSource
    let transportProvider: BrowsePriceTransport
    let providerUpdatedAt: Date
    let quoteDay: BrowsePriceDay

    init?(
        printingID: String,
        setID: String,
        variant: PhysicalVariant,
        amountUSD: Double,
        marketSource: BrowsePriceMarketSource,
        transportProvider: BrowsePriceTransport,
        providerUpdatedAt: Date
    ) {
        let cleanPrintingID = printingID.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanSetID = setID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanPrintingID.isEmpty,
              !cleanSetID.isEmpty,
              amountUSD.isFinite,
              amountUSD >= 0,
              variant.browsePriceHistoryDescriptorV1 != nil else {
            return nil
        }
        self.printingID = cleanPrintingID
        self.setID = cleanSetID
        self.variant = variant
        self.amountUSD = amountUSD
        self.marketSource = marketSource
        self.transportProvider = transportProvider
        self.providerUpdatedAt = providerUpdatedAt
        self.quoteDay = BrowsePriceDay(date: providerUpdatedAt)
    }

    var seriesKey: BrowsePriceSeriesKey? {
        guard let descriptor = variant.browsePriceHistoryDescriptorV1 else { return nil }
        return BrowsePriceSeriesKey(
            printingID: printingID,
            variantDescriptor: descriptor,
            marketSource: marketSource
        )
    }

    var historyPoint: BrowsePriceHistoryPoint {
        BrowsePriceHistoryPoint(
            day: quoteDay,
            amountUSD: amountUSD,
            providerUpdatedAt: providerUpdatedAt,
            transportProvider: transportProvider
        )
    }

    static func from(
        normalizedPrice: NormalizedPrice,
        printingID: String,
        setID: String,
        variant: PhysicalVariant,
        transportProvider: BrowsePriceTransport,
        providerUpdatedAt: Date? = nil
    ) -> BrowsePriceQuote? {
        let source: BrowsePriceMarketSource
        switch normalizedPrice.source {
        case .tcgplayer: source = .tcgplayer
        case .scryfall: source = .scryfall
        case .cardmarket, .justTCG, .importedCSV:
            return nil
        }
        guard normalizedPrice.currencyCode.caseInsensitiveCompare("USD") == .orderedSame else {
            return nil
        }
        guard let resolvedProviderUpdatedAt = providerUpdatedAt ?? normalizedPrice.sourceUpdatedAt else {
            return nil
        }
        return BrowsePriceQuote(
            printingID: printingID,
            setID: setID,
            variant: variant,
            amountUSD: normalizedPrice.unitMarketPriceUSD,
            marketSource: source,
            transportProvider: transportProvider,
            providerUpdatedAt: resolvedProviderUpdatedAt
        )
    }
}

/// A v1 descriptor is a deliberately closed vocabulary. Unknown dynamic
/// variants return nil, making the history path fail closed until its
/// persistence contract is extended.
extension PhysicalVariant {
    var browsePriceHistoryDescriptorV1: BrowsePriceVariantDescriptor? {
        let value: String?
        switch id {
        case PhysicalVariant.normal.id: value = "pokemon.normal"
        case PhysicalVariant.holo.id: value = "pokemon.holo"
        case PhysicalVariant.reverse.id: value = "pokemon.reverse"
        case PhysicalVariant.firstEdition.id: value = "pokemon.first-edition"
        case PhysicalVariant.pokeBall.id: value = "pokemon.poke-ball"
        case PhysicalVariant.masterBall.id: value = "pokemon.master-ball"
        case PhysicalVariant.duskBall.id: value = "pokemon.dusk-ball"
        case PhysicalVariant.friendBall.id: value = "pokemon.friend-ball"
        case PhysicalVariant.quickBall.id: value = "pokemon.quick-ball"
        case PhysicalVariant.loveBall.id: value = "pokemon.love-ball"
        case PhysicalVariant.nonfoil.id: value = "magic.nonfoil"
        case PhysicalVariant.foil.id: value = "magic.foil"
        case PhysicalVariant.etched.id: value = "magic.etched"
        default:
            if let stamped = PokemonStampedReleaseCatalog.entry(variantID: id) {
                value = "pokemon.stamped-release.\(stamped.year).\(stableBrowseToken(stamped.printing))"
            } else if let decoded = PokemonCatalogStampVariant.decode(id),
                      let base = decoded.base.browsePriceHistoryDescriptorV1,
                      let stamps = decoded.stamps
                        .map(stableBrowseToken)
                        .sorted()
                        .nilIfEmpty {
                let subtype = decoded.subtype.map(stableBrowseToken) ?? "none"
                value = "pokemon.stamp.v1|base:\(base.value)|stamps:\(stamps.joined(separator: "+"))|subtype:\(subtype)"
            } else {
                value = nil
            }
        }
        guard let value else { return nil }
        return BrowsePriceVariantDescriptor(
            schemaVersion: BrowsePriceVariantDescriptor.currentSchemaVersion,
            value: value
        )
    }
}

private func stableBrowseToken(_ raw: String) -> String {
    raw.trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()
        .replacingOccurrences(of: " ", with: "-")
        .replacingOccurrences(of: "|", with: "-")
}

private extension Array {
    var nilIfEmpty: [Element]? { isEmpty ? nil : self }
}

struct BrowsePriceHistoryDiagnostics: Equatable, Sendable {
    let setCount: Int
    let totalBytes: Int
    let oldestProviderDay: BrowsePriceDay?
    let newestProviderDay: BrowsePriceDay?
    let corruptFileRecoveryCount: Int
    let skippedTimestampWrites: Int
    let deduplicatedObservationCount: Int
    let pokemonShadowCoverageSummary: String
    let unmappedVariantCount: Int

    static let empty = BrowsePriceHistoryDiagnostics(
        setCount: 0,
        totalBytes: 0,
        oldestProviderDay: nil,
        newestProviderDay: nil,
        corruptFileRecoveryCount: 0,
        skippedTimestampWrites: 0,
        deduplicatedObservationCount: 0,
        pokemonShadowCoverageSummary: "No shadow comparison is active.",
        unmappedVariantCount: 0
    )
}
