import Foundation

/// Enriches a TCGdex set with non-fingerprinted artwork evidence.
///
/// TCGdex remains the primary provider. Secondary evidence is used only after
/// a whole-directory identity match and a successful image probe; ambiguity or
/// a secondary transport failure produces no artwork rather than a guess.
public struct PokemonCatalogArtworkEnricher: Sendable {
    public typealias SecondaryCardArtworkLoader =
        @Sendable (String, Int) async throws -> [PokemonCatalogSecondaryCard]
    public typealias Logger = @Sendable (String) -> Void

    public struct Result: Sendable {
        public let providerSet: PokemonCatalogProviderSet
        public let ambiguousSecondarySetIDs: [String]

        public init(
            providerSet: PokemonCatalogProviderSet,
            ambiguousSecondarySetIDs: [String] = []
        ) {
            self.providerSet = providerSet
            self.ambiguousSecondarySetIDs = ambiguousSecondarySetIDs
        }
    }

    private let artworkResolver: PokemonCatalogTCGdexArtworkResolver
    private let secondaryArtworkProbe: PokemonCatalogArtworkProbe
    private let secondaryCandidates: [PokemonCatalogSecondarySet]
    private let secondaryCardArtworkLoader: SecondaryCardArtworkLoader?
    private let logger: Logger

    public init(
        artworkResolver: PokemonCatalogTCGdexArtworkResolver = .init(),
        secondaryArtworkProbe: PokemonCatalogArtworkProbe = .init(),
        secondaryCandidates: [PokemonCatalogSecondarySet] = [],
        secondaryCardArtworkLoader: SecondaryCardArtworkLoader? = nil,
        logger: @escaping Logger = { message in print(message) }
    ) {
        self.artworkResolver = artworkResolver
        self.secondaryArtworkProbe = secondaryArtworkProbe
        self.secondaryCandidates = secondaryCandidates
        self.secondaryCardArtworkLoader = secondaryCardArtworkLoader
        self.logger = logger
    }

    public func enrich(
        _ providerSet: PokemonCatalogProviderSet,
        directoryRow: PokemonCatalogProviderDirectoryRow
    ) async -> Result {
        let secondaryOutcome = PokemonCatalogSecondarySetMatcher.match(
            tcgdex: providerSet,
            directoryRow: directoryRow,
            candidates: secondaryCandidates
        )
        let matchedSecondary: PokemonCatalogSecondarySet?
        let ambiguousIDs: [String]
        switch secondaryOutcome {
        case let .matched(candidate):
            matchedSecondary = candidate
            ambiguousIDs = []
        case .none:
            matchedSecondary = nil
            ambiguousIDs = []
        case let .ambiguous(ids):
            matchedSecondary = nil
            ambiguousIDs = ids
            logger("ambiguous secondary artwork matches for \(providerSet.id): \(ids.joined(separator: ", "))")
        }

        let explicitLogo = nonEmpty(providerSet.logo) ?? nonEmpty(directoryRow.logo)
        let explicitSymbol = nonEmpty(providerSet.symbol) ?? nonEmpty(directoryRow.symbol)
        let seriesID = providerSet.serie?.id.trimmingCharacters(in: .whitespacesAndNewlines)
        let setID = providerSet.id.trimmingCharacters(in: .whitespacesAndNewlines)

        let logoResult = await resolve(
            explicit: explicitLogo,
            seriesID: seriesID,
            setID: setID,
            kind: .logo,
            secondaryURL: matchedSecondary?.logoURL,
            secondarySourceID: matchedSecondary?.id
        )
        let symbolResult = await resolve(
            explicit: explicitSymbol,
            seriesID: seriesID,
            setID: setID,
            kind: .symbol,
            secondaryURL: matchedSecondary?.symbolURL,
            secondarySourceID: matchedSecondary?.id
        )

        var cardArtworkURLs: [String]?
        var cardArtworkByLocalID: [String: PokemonCatalogResolvedCardArtwork]?
        var cardArtworkMatchCount = 0
        if let matchedSecondary,
           providerSet.cards.allSatisfy({ nonEmpty($0.image) == nil }) {
            if let secondaryCardArtworkLoader {
                do {
                    let fetched = try await secondaryCardArtworkLoader(
                        matchedSecondary.id,
                        min(max(providerSet.cards.count, 3), 400)
                    )
                    let matchedCards = PokemonCatalogSecondaryCardMatcher.match(
                        tcgdexCards: providerSet.cards,
                        secondaryCards: fetched
                    )
                    let candidatePairs = providerSet.cards
                        .compactMap { brief -> (PokemonCatalogProviderCardBrief, PokemonCatalogSecondaryCard)? in
                            guard let secondary = matchedCards[brief.id],
                                  let thumbnail = nonEmpty(secondary.thumbnailURL),
                                  let image = nonEmpty(secondary.imageURL) else {
                                return nil
                            }
                            return (brief, .init(
                                number: secondary.number,
                                name: secondary.name,
                                thumbnailURL: thumbnail,
                                imageURL: image
                            ))
                        }
                        .sorted { $0.0.localID < $1.0.localID }

                    // A small sample validates the shared CDN template. If
                    // the sample is not healthy, publish no per-card overlay;
                    // a later run can safely retry without signing guesses.
                    let sample = candidatePairs.prefix(3)
                    var sampleAccepted = !sample.isEmpty
                    for (_, card) in sample where sampleAccepted {
                        guard let thumbnail = card.thumbnailURL,
                              let image = card.imageURL,
                              let thumbnailURL = URL(string: thumbnail),
                              let imageURL = URL(string: image),
                              await secondaryArtworkProbe.accepts(thumbnailURL),
                              await secondaryArtworkProbe.accepts(imageURL) else {
                            sampleAccepted = false
                            break
                        }
                    }
                    if sampleAccepted {
                        var resolved: [String: PokemonCatalogResolvedCardArtwork] = [:]
                        for (brief, card) in candidatePairs {
                            guard let thumbnail = nonEmpty(card.thumbnailURL),
                                  let image = nonEmpty(card.imageURL) else { continue }
                            resolved[normalizedLocalID(brief.localID)] =
                                PokemonCatalogResolvedCardArtwork(
                                    thumbnail: thumbnail,
                                    image: image
                                )
                        }
                        if !resolved.isEmpty {
                            cardArtworkByLocalID = resolved
                            cardArtworkMatchCount = resolved.count
                            cardArtworkURLs = candidatePairs
                                .prefix(3)
                                .compactMap { nonEmpty($0.1.imageURL) }
                        }
                    }
                } catch {
                    logger("secondary provider unavailable: \(error)")
                }
            }

            // Keep the original set-tile evidence path for recorded/legacy
            // candidates that predate the per-card response shape.
            if cardArtworkURLs == nil {
                let probedCandidates = await acceptedArtworkURLs(
                    matchedSecondary.cardArtworkURLs,
                    limit: 3
                )
                if !probedCandidates.isEmpty {
                    cardArtworkURLs = probedCandidates
                }
            }
        }

        var sources: [String] = []
        if let source = logoResult.source {
            sources.append("logo:\(source)")
        }
        if let source = symbolResult.source {
            sources.append("symbol:\(source)")
        }
        if let matchedSecondary, cardArtworkMatchCount > 0 {
            sources.append(
                "cards:secondary:\(matchedSecondary.id):\(cardArtworkMatchCount)/\(providerSet.cards.count)"
            )
        } else if let matchedSecondary, cardArtworkURLs != nil {
            sources.append("card:secondary:\(matchedSecondary.id)")
        }
        let source = sources.isEmpty ? nil : sources.joined(separator: ";")
        let enriched = PokemonCatalogProviderSet(
            id: providerSet.id,
            name: providerSet.name,
            cards: providerSet.cards,
            logo: providerSet.logo,
            symbol: providerSet.symbol,
            releaseDate: providerSet.releaseDate,
            tcgOnline: providerSet.tcgOnline,
            cardCount: providerSet.cardCount,
            serie: providerSet.serie,
            abbreviation: providerSet.abbreviation,
            resolvedLogo: logoResult.value,
            resolvedSymbol: symbolResult.value,
            resolvedCardArtworkURLs: cardArtworkURLs,
            resolvedCardArtworkByLocalID: cardArtworkByLocalID,
            resolvedArtworkSource: source
        )
        return Result(
            providerSet: enriched,
            ambiguousSecondarySetIDs: ambiguousIDs
        )
    }

    private struct Resolution {
        let value: String?
        let source: String?
    }

    private func resolve(
        explicit: String?,
        seriesID: String?,
        setID: String,
        kind: PokemonCatalogArtworkKind,
        secondaryURL: String?,
        secondarySourceID: String?
    ) async -> Resolution {
        if let explicit {
            return Resolution(value: explicit, source: nil)
        }
        if let seriesID, !seriesID.isEmpty, !setID.isEmpty,
           let resolved = await artworkResolver.resolve(
               seriesID: seriesID,
               setID: setID,
               kind: kind
           ) {
            return Resolution(value: resolved, source: "tcgdexProbe")
        }
        guard let secondaryURL = nonEmpty(secondaryURL),
              let url = URL(string: secondaryURL) else {
            return Resolution(value: nil, source: nil)
        }
        guard await secondaryArtworkProbe.accepts(url) else {
            return Resolution(value: nil, source: nil)
        }
        return Resolution(
            value: secondaryURL,
            source: "secondary:\(secondarySourceID ?? "unknown")"
        )
    }

    private func acceptedArtworkURLs(_ rawURLs: [String], limit: Int) async -> [String] {
        guard limit > 0 else { return [] }
        var accepted: [String] = []
        for rawURL in rawURLs {
            guard accepted.count < limit,
                  let value = nonEmpty(rawURL),
                  let url = URL(string: value) else { continue }
            guard await secondaryArtworkProbe.accepts(url) else {
                continue
            }
            accepted.append(value)
        }
        return accepted
    }

    private func nonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : value
    }

    private func normalizedLocalID(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }
}
