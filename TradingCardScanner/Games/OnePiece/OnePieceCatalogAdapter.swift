import Foundation
import OnePieceCatalogCore

struct OnePieceCatalogAdapter: GameCatalogAdapter {
    let registry: OnePieceCatalogRegistry
    var game: CardGame { .onePiece }
    var generation: String { registry.generation }

    func resolution(forPrintingID id: UUID) throws -> CardCatalog.CatalogResolution {
        guard let printing = registry.printingByID[id], printing.status == .verified,
              printing.language == "en",
              let canonical = registry.canonicalByID[printing.canonicalCardID] else {
            throw CatalogLookupError.invalidPrintingChoice
        }
        return try resolution(for: printing, canonical: canonical)
    }

    func validateVariantCorrection(printingID: String, variantID: String?) throws {
        guard let id = UUID(uuidString: printingID), id.uuidString.lowercased() == printingID else {
            throw CatalogLookupError.invalidPrintingChoice
        }
        let resolved = try resolution(forPrintingID: id)
        guard let variantID,
              resolved.card.variantEvidence.catalogVariants.contains(where: { $0.id == variantID }) else {
            throw CatalogLookupError.invalidPrintingChoice
        }
    }

    func identifierForRetry(_ identifier: ScanIdentifier) throws -> ScanIdentifier {
        _ = try validatedFields(for: identifier)
        return try .init(game: game, namespace: identifier.namespace, fields: identifier.fields,
            displayIdentifier: identifier.displayIdentifier, suppressionIdentity: identifier.suppressionIdentity,
            catalogGeneration: generation)
    }

    /// The same payload contract applies to live evidence and persisted retries.
    /// Rebasing only changes the generation; it cannot reinterpret future fields
    /// or repair an inconsistent language/suppression identity silently.
    private func validatedFields(for identifier: ScanIdentifier) throws -> [String: String] {
        let fields = Dictionary(uniqueKeysWithValues: identifier.fields.map { ($0.key, $0.value) })
        guard identifier.game == game, identifier.namespace == "numbered-card",
              Set(fields.keys).isSubset(of: ["number", "language", "languageConfirmation"]),
              let number = fields["number"], OnePieceTextNormalization.printedNumber(number) == number,
              fields["language"] == nil || fields["language"] == "unknown" || fields["language"] == "en",
              fields["languageConfirmation"] == nil || fields["languageConfirmation"] == "unconfirmed"
                || fields["languageConfirmation"] == "user-confirmed",
              fields["languageConfirmation"] != "user-confirmed" || fields["language"] == "en",
              identifier.suppressionIdentity == "number:\(number)" else {
            throw CatalogLookupError.invalidAdapterOutcome
        }
        return fields
    }

    func lookup(_ identifier: ScanIdentifier) async throws -> CatalogLookupOutcome {
        let card = try canonical(for: identifier)
        guard let card else { return .catalogIncomplete(nil) }
        let summary = CanonicalCardSummary(id: card.id, game: game, name: card.name,
            printedIdentifier: card.printedNumber, language: card.language)
        let all = registry.printingsByCanonicalID[card.id] ?? []
        let eligible = all.filter { $0.status == .verified }
        guard !eligible.isEmpty else { return .catalogIncomplete(summary) }
        // Match the other games: a picker supplies a distinction between
        // available verified printings, not confirmation of a single option.
        // Coverage metadata and OCR language do not create additional choices;
        // provisional/conflicted records remain ineligible for ownership.
        if eligible.count == 1 {
            return .resolved(try resolution(for: eligible[0], canonical: card))
        }
        return .needsPrintingChoice(canonical: summary, candidates: eligible.map { candidate($0, canonical: card) })
    }

    func resolve(_ candidate: PhysicalPrintingCandidate, for identifier: ScanIdentifier) async throws -> CardCatalog.CatalogResolution {
        guard let card = try canonical(for: identifier), candidate.catalogGeneration == generation,
              let printingID = UUID(uuidString: candidate.id), let printing = registry.printingByID[printingID],
              printing.status == .verified, printing.canonicalCardID == card.id,
              candidate == self.candidate(printing, canonical: card,
                includeAdditionalDetails: candidate.artworkID != nil || candidate.distinctionLabels != nil) else {
            throw CatalogLookupError.invalidPrintingChoice
        }
        return try resolution(for: printing, canonical: card)
    }

    private func canonical(for identifier: ScanIdentifier) throws -> OnePieceCanonicalCard? {
        guard identifier.catalogGeneration == generation else {
            throw CatalogLookupError.staleCatalog
        }
        let fields = try validatedFields(for: identifier)
        return fields["number"].flatMap { registry.canonicalByPrintedNumber[$0] }
    }

    private func candidate(_ printing: OnePiecePhysicalPrinting, canonical: OnePieceCanonicalCard,
                           includeAdditionalDetails: Bool = true) -> PhysicalPrintingCandidate {
        let product = printing.releaseID.flatMap { registry.productsByID[$0] }
        return .init(id: printing.id.uuidString.lowercased(), game: game, canonicalCardID: canonical.id,
            language: printing.language, catalogGeneration: generation, name: canonical.name,
            printedIdentifier: canonical.printedNumber,
            releaseLabel: ["English", product?.label].compactMap { $0 }.joined(separator: " · "),
            treatmentLabel: printing.treatment, distributionLabel: [printing.distributionLabel, printing.stamp].compactMap { $0 }.joined(separator: " · "),
            releaseDate: product?.releaseDate.flatMap(OnePieceTextNormalization.releaseDate),
            thumbnailURL: registry.artworkURLByID[printing.artworkID],
            artworkID: includeAdditionalDetails ? printing.artworkID.uuidString.lowercased() : nil,
            distinctionLabels: includeAdditionalDetails ? [
                printing.region.map { "Region: \($0)" },
                printing.blockText.map { "Block: \($0)" },
                printing.copyrightText.map { "Copyright: \($0)" }
            ].compactMap { $0 } : nil)
    }

    private func resolution(for printing: OnePiecePhysicalPrinting, canonical: OnePieceCanonicalCard) throws -> CardCatalog.CatalogResolution {
        let product = printing.releaseID.flatMap { registry.productsByID[$0] }
        let image = registry.artworkURLByID[printing.artworkID]
        let card = try ResolvedCatalogCard(game: game, physicalPrintingID: printing.id.uuidString.lowercased(),
            canonicalCardID: canonical.id, language: printing.language, name: canonical.name,
            setName: product?.label ?? printing.distributionLabel ?? "One Piece", setCode: OnePieceTextNormalization.prefix(of: canonical.printedNumber) ?? "",
            cardNumber: canonical.printedNumber, printedIdentifier: canonical.printedNumber,
            displayImageURL: image, thumbnailImageURL: image,
            setReleaseOrder: product?.releaseDate.flatMap(OnePieceTextNormalization.releaseDate)
                .map { Int($0.timeIntervalSince1970 / 86_400) } ?? 0,
            variantEvidence: .init(game: game, setID: printing.releaseID ?? "one-piece-distribution",
                cardNumber: canonical.printedNumber, catalogVariants: printing.supportedVariantIDs.compactMap { id in
                    registry.variantsByID[id].map { PhysicalVariant(id: $0.id, label: $0.label) }
                }))
        return .init(card, retrievedAt: registry.retrievedAt, path: .cacheHit)
    }

}
