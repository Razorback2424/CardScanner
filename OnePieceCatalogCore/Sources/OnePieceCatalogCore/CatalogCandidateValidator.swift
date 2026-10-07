import Foundation

public struct OnePieceCatalogValidationIssue: Codable, Equatable, Sendable {
    public let code: String
    public let context: String
}

public struct OnePieceCatalogValidationError: Error, Sendable {
    public let issues: [OnePieceCatalogValidationIssue]
}

public enum OnePieceCatalogCandidateValidator {
    public static func validate(_ release: OnePieceCatalogRelease,
                                previous: OnePieceCatalogRelease? = nil) throws {
        let issues = issues(in: release, previous: previous)
        if !issues.isEmpty { throw OnePieceCatalogValidationError(issues: issues) }
    }

    public static func issues(in release: OnePieceCatalogRelease,
                              previous: OnePieceCatalogRelease? = nil) -> [OnePieceCatalogValidationIssue] {
        var issues: [OnePieceCatalogValidationIssue] = []
        func fail(_ code: String, _ context: String) { issues.append(.init(code: code, context: context)) }
        func unique<T: Hashable>(_ values: [T], _ code: String) {
            if Set(values).count != values.count { fail(code, "duplicate values") }
        }
        let timestamp = ISO8601DateFormatter()
        let fractionalTimestamp = ISO8601DateFormatter()
        fractionalTimestamp.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var timestampValidity: [String: Bool] = [:]
        func validTimestamp(_ value: String) -> Bool {
            if let valid = timestampValidity[value] { return valid }
            let valid = timestamp.date(from: value) != nil || fractionalTimestamp.date(from: value) != nil
            timestampValidity[value] = valid
            return valid
        }
        let state = release.registry
        if release.schemaVersion != OnePieceCatalogContract.schemaVersion ||
            state.schemaVersion != OnePieceCatalogContract.schemaVersion ||
            release.rulesVersion != OnePieceCatalogContract.rulesVersion ||
            release.catalogKind != OnePieceCatalogContract.catalogKind { fail("unsupportedContract", release.catalogKind) }
        if release.revision < 1 { fail("invalidRevision", String(release.revision)) }
        if !validTimestamp(release.generatedAt) { fail("invalidTimestamp", release.generatedAt) }
        unique(state.canonicalCards.map(\.id), "duplicateCanonicalID")
        unique(state.artworks.map(\.id), "duplicateArtworkID")
        unique(state.printings.map(\.id), "duplicatePrintingID")
        unique(state.variants.map(\.id), "duplicateVariantID")
        unique(state.products.map(\.id), "duplicateProductID")
        unique(state.corrections.map(\.id), "duplicateCorrectionID")
        unique(release.observations.map(\.id), "duplicateObservationID")
        unique(state.appearances.map { "\($0.printingID)|\($0.productID)" }, "duplicateProductAppearance")
        // Do not use trapping Dictionary(uniqueKeysWithValues:) on candidate input.
        let cards = Dictionary(state.canonicalCards.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let artworks = Dictionary(state.artworks.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let printings = Dictionary(state.printings.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let variants = Set(state.variants.map(\.id))
        let products = Set(state.products.map(\.id))
        let observations = Dictionary(release.observations.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        // Index the full candidate once. Repeated linear scans here made every
        // app launch quadratic in the number of physical printings/evidence.
        // Retain all languages for an alias, including duplicate observations.
        var observationLanguagesByAlias: [OnePieceSourceAlias: Set<String>] = [:]
        for observation in release.observations {
            observationLanguagesByAlias[observation.alias, default: []].insert(observation.language)
        }
        func finishIDs(_ observation: OnePieceSourceObservation) -> Set<String>? {
            let single = observation.printedEvidence["finishVariantID"]
            let multiple = observation.printedEvidence["finishVariantIDs"]
            if let single {
                guard multiple == nil, OnePieceTextNormalization.nonempty(single) else { return nil }
                return [single]
            }
            guard let multiple, let values = try? JSONDecoder().decode([String].self, from: Data(multiple.utf8)),
                  !values.isEmpty, Set(values).count == values.count else { return nil }
            return Set(values)
        }
        func validReview(_ review: OnePieceReview?, required: Set<OnePieceEvidenceKind>, context: String) {
            guard let review, OnePieceTextNormalization.nonempty(review.reference), !review.evidence.isEmpty else {
                fail("missingReview", context); return
            }
            let kinds = Set(review.evidence.map(\.kind))
            if !required.isSubset(of: kinds) { fail("missingDistinctionEvidence", context) }
            for evidence in review.evidence {
                if observations[evidence.observationID] == nil || !OnePieceTextNormalization.nonempty(evidence.detail) {
                    fail("invalidEvidenceReference", context)
                }
            }
        }
        func validAlias(_ alias: OnePieceSourceAlias) -> Bool {
            OnePieceTextNormalization.nonempty(alias.provider) && alias.provider == alias.provider.lowercased()
                && alias.provider == alias.provider.trimmingCharacters(in: .whitespacesAndNewlines)
                && OnePieceTextNormalization.nonempty(alias.sourceID)
                && alias.sourceID == alias.sourceID.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        for card in state.canonicalCards {
            if OnePieceTextNormalization.printedNumber(card.printedNumber) != card.printedNumber ||
                card.language != card.language.lowercased() || card.language.contains(":") ||
                !OnePieceTextNormalization.nonempty(card.language) || !OnePieceTextNormalization.nonempty(card.name) ||
                card.id != "one-piece:\(card.language):\(card.printedNumber)" { fail("invalidCanonicalIdentity", card.id) }
            if card.printingCoverageComplete && !(card.coverageReviewReference.map(OnePieceTextNormalization.nonempty) ?? false) {
                fail("unreviewedCompleteness", card.id)
            }
        }
        for variant in state.variants {
            if !OnePieceTextNormalization.nonempty(variant.id) || variant.id.contains("#") ||
                variant.id != variant.id.trimmingCharacters(in: .whitespacesAndNewlines) ||
                !OnePieceTextNormalization.nonempty(variant.label) { fail("invalidVariant", variant.id) }
        }
        for product in state.products {
            if !OnePieceTextNormalization.nonempty(product.id) ||
                product.id != product.id.trimmingCharacters(in: .whitespacesAndNewlines) ||
                !OnePieceTextNormalization.nonempty(product.label) ||
                product.releaseDate.map({ OnePieceTextNormalization.releaseDate($0) == nil }) == true {
                fail("invalidProduct", product.id)
            }
        }
        for observation in release.observations {
            if !validAlias(observation.alias) || !OnePieceTextNormalization.nonempty(observation.id) ||
                observation.sourceURL.scheme != "https" || observation.sourceURL.host == nil ||
                !OnePieceTextNormalization.isSHA256(observation.payloadSHA256) ||
                !validTimestamp(observation.observedAt) ||
                !OnePieceTextNormalization.nonempty(observation.language) { fail("invalidObservation", observation.id) }
            if let hash = observation.imageSHA256, !OnePieceTextNormalization.isSHA256(hash) { fail("invalidImageHash", observation.id) }
            if let hash = observation.perceptualHash,
               hash.version < 1 || !OnePieceTextNormalization.nonempty(hash.algorithm) || !OnePieceTextNormalization.nonempty(hash.value) {
                fail("invalidPerceptualHash", observation.id)
            }
        }
        for artwork in state.artworks {
            if artwork.observationIDs.isEmpty || artwork.observationIDs.contains(where: { observations[$0] == nil }) {
                fail("invalidArtworkEvidence", artwork.id.uuidString)
            }
            if let hash = artwork.imageSHA256, !OnePieceTextNormalization.isSHA256(hash) { fail("invalidImageHash", artwork.id.uuidString) }
            if let url = artwork.referenceImageURL, url.scheme != "https" || url.host == nil { fail("invalidImageURL", artwork.id.uuidString) }
        }
        var aliases: [OnePieceSourceAlias: UUID] = [:]
        var mappings: [OnePieceMarketMapping.QuoteIdentity: OnePieceMarketMapping] = [:]
        for printing in state.printings {
            let context = printing.id.uuidString
            if cards[printing.canonicalCardID] == nil { fail("missingCanonicalReference", context) }
            if artworks[printing.artworkID] == nil { fail("missingArtworkReference", context) }
            if cards[printing.canonicalCardID]?.language != printing.language { fail("printingLanguageMismatch", context) }
            if let product = printing.releaseID, !products.contains(product) { fail("missingReleaseReference", context) }
            unique(printing.supportedVariantIDs, "duplicatePrintingVariant")
            // Unknown finish is truthful review state, not a synthetic variant.
            // Only verified physical identities can enter acquisition paths.
            if (printing.status == .verified && printing.supportedVariantIDs.isEmpty) ||
                !Set(printing.supportedVariantIDs).isSubset(of: variants) {
                fail("invalidPrintingVariants", context)
            }
            if printing.status == .verified {
                validReview(printing.review, required: printing.requiredEvidenceKinds, context: context)
                let artwork = artworks[printing.artworkID]
                var reviewedFinishes: Set<String> = []
                for evidence in printing.review?.evidence ?? [] {
                    guard let observation = observations[evidence.observationID] else { continue }
                    let agrees: Bool
                    switch evidence.kind {
                    case .printedIdentity: agrees = observation.printedEvidence["number"] == cards[printing.canonicalCardID]?.printedNumber
                    case .language: agrees = observation.language == printing.language
                    case .artwork: agrees = artwork?.imageSHA256 != nil && observation.imageSHA256 == artwork?.imageSHA256
                    case .release: agrees = printing.releaseID.map { observation.productEvidence.contains($0) } ?? false
                    case .distribution: agrees = printing.distributionLabel != nil && observation.printedEvidence["distribution"] == printing.distributionLabel
                    case .treatment: agrees = printing.treatment != nil && observation.printedEvidence["treatment"] == printing.treatment
                    case .stamp: agrees = printing.stamp != nil && observation.printedEvidence["stamp"] == printing.stamp
                    case .footer:
                        agrees = (printing.blockText == nil || observation.printedEvidence["blockText"] == printing.blockText)
                            && (printing.copyrightText == nil || observation.printedEvidence["copyrightText"] == printing.copyrightText)
                    case .finish:
                        let ids = finishIDs(observation) ?? []
                        agrees = observation.kind == .catalog && !ids.isEmpty &&
                            ids.isSubset(of: Set(printing.supportedVariantIDs)) &&
                            observation.language == printing.language &&
                            observation.printedEvidence["number"] == cards[printing.canonicalCardID]?.printedNumber &&
                            (printing.releaseID.map { observation.productEvidence.contains($0) } ?? true) &&
                            observation.printedEvidence["sourceRole"] != "watermarked-digital-render" &&
                            observation.printedEvidence["sourceRole"] != "photograph-of-physical-card"
                        if agrees { reviewedFinishes.formUnion(ids) }
                    case .marketIdentity: agrees = false
                    }
                    if !agrees { fail("contradictoryReviewedEvidence", context) }
                }
                if !Set(printing.supportedVariantIDs).isSubset(of: reviewedFinishes) {
                    fail("missingFinishEvidence", context)
                }
            }
            for alias in printing.sourceAliases {
                if !validAlias(alias) { fail("invalidAlias", context) }
                if aliases.updateValue(printing.id, forKey: alias) != nil { fail("duplicateSourceAlias", context) }
                if observationLanguagesByAlias[alias]?.contains(printing.language) != true {
                    fail("missingAliasObservation", context)
                }
            }
            for mapping in printing.marketMappings {
                if mapping.printingID != printing.id || !printing.supportedVariantIDs.contains(mapping.variantID) ||
                    !OnePieceTextNormalization.nonempty(mapping.provider) || mapping.provider != mapping.provider.lowercased() ||
                    !OnePieceTextNormalization.nonempty(mapping.productID) || !OnePieceTextNormalization.nonempty(mapping.market) ||
                    !OnePieceTextNormalization.nonempty(mapping.condition) ||
                    mapping.market != mapping.market.lowercased() || mapping.condition != mapping.condition.lowercased() ||
                    mapping.providerVariantID.map({ !OnePieceTextNormalization.nonempty($0) }) == true ||
                    mapping.qualifiers.contains(where: { !OnePieceTextNormalization.nonempty($0.key) || !OnePieceTextNormalization.nonempty($0.value) }) ||
                    mapping.currency.range(of: "^[A-Z]{3}$", options: .regularExpression) == nil { fail("invalidMarketMapping", context) }
                if let old = mappings.updateValue(mapping, forKey: mapping.quoteIdentity), old != mapping {
                    fail("conflictingMarketMapping", context)
                }
                if mapping.status == .exact {
                    if printing.status != .verified { fail("unverifiedExactMarketPrinting", context) }
                    validReview(mapping.review, required: [.printedIdentity, .marketIdentity], context: context)
                    for evidence in mapping.review?.evidence ?? [] {
                        guard let observation = observations[evidence.observationID] else { continue }
                        if evidence.kind == .printedIdentity &&
                            (observation.printedEvidence["number"] != cards[printing.canonicalCardID]?.printedNumber ||
                             observation.language != printing.language) { fail("marketIdentityMismatch", context) }
                        if evidence.kind == .marketIdentity {
                            let fields = observation.printedEvidence
                            if observation.kind != .market || observation.alias.provider != mapping.provider ||
                                fields["marketProductID"] != mapping.productID || fields["marketVariantID"] != mapping.providerVariantID ||
                                fields["finishVariantID"] != mapping.variantID || fields["market"] != mapping.market ||
                                fields["currency"] != mapping.currency || fields["condition"] != mapping.condition ||
                                mapping.qualifiers.contains(where: { fields["qualifier:\($0.key)"] != $0.value }) ||
                                (printing.releaseID.map { !observation.productEvidence.contains($0) } ?? false) ||
                                (printing.stamp.map { fields["stamp"] != $0 } ?? false) ||
                                (printing.treatment.map { fields["treatment"] != $0 } ?? false) ||
                                (printing.distributionLabel.map { fields["distribution"] != $0 } ?? false) {
                                fail("marketIdentityMismatch", context)
                            }
                        }
                    }
                    if printing.supportedVariantIDs.count > 1 && mapping.providerVariantID == nil && mapping.qualifiers["finish"] == nil {
                        fail("missingMarketFinishQualifier", context)
                    }
                }
            }
            unique(printing.marketMappings, "duplicateMarketMapping")
            unique(printing.supersedes, "duplicateSupersession")
            if printing.status == .superseded && !state.printings.contains(where: { $0.supersedes.contains(printing.id) }) {
                fail("orphanSupersededPrinting", context)
            }
            for oldID in printing.supersedes {
                if oldID == printing.id || printings[oldID]?.status != .superseded { fail("invalidSupersession", context) }
                if !state.corrections.contains(where: { $0.fromPrintingIDs.contains(oldID) && $0.toPrintingIDs.contains(printing.id) && $0.kind != .aliasReassignment }) {
                    fail("unreviewedSupersession", context)
                }
            }
        }
        for observation in release.observations where observation.kind == .catalog {
            guard let rawNumber = observation.printedEvidence["number"],
                  let number = OnePieceTextNormalization.printedNumber(rawNumber) else { continue }
            let canonicalID = "one-piece:\(observation.language):\(number)"
            guard let canonical = cards[canonicalID] else { fail("unregisteredCanonicalObservation", observation.id); continue }
            if canonical.printingCoverageComplete && aliases[observation.alias] == nil {
                fail("unreconciledCanonicalObservation", observation.id)
            }
        }
        // Graph traversal also catches cycles that an individual row cannot detect.
        var visited: Set<UUID> = [], visiting: Set<UUID> = []
        func visit(_ id: UUID) {
            guard !visited.contains(id) else { return }
            if visiting.contains(id) { fail("supersessionCycle", id.uuidString); return }
            visiting.insert(id)
            for next in printings[id]?.supersedes ?? [] { visit(next) }
            visiting.remove(id); visited.insert(id)
        }
        for id in printings.keys { visit(id) }
        for correction in state.corrections {
            validReview(correction.review, required: [.printedIdentity], context: correction.id)
            if correction.fromPrintingIDs.isEmpty || correction.toPrintingIDs.isEmpty ||
                !Set(correction.fromPrintingIDs + correction.toPrintingIDs).isSubset(of: Set(printings.keys)) ||
                !Set(correction.fromPrintingIDs).isDisjoint(with: correction.toPrintingIDs) { fail("invalidCorrection", correction.id) }
            if correction.kind == .split && (correction.fromPrintingIDs.count != 1 || correction.toPrintingIDs.count < 2) {
                fail("invalidSplit", correction.id)
            }
            if correction.kind == .merge && (correction.fromPrintingIDs.count < 2 || correction.toPrintingIDs.count != 1) {
                fail("invalidMerge", correction.id)
            }
            if correction.kind != .aliasReassignment {
                if correction.fromPrintingIDs.contains(where: { printings[$0]?.status != .superseded }) ||
                    correction.toPrintingIDs.contains(where: { newID in
                        !Set(correction.fromPrintingIDs).isSubset(of: Set(printings[newID]?.supersedes ?? []))
                    }) { fail("correctionGraphMismatch", correction.id) }
            }
        }
        for appearance in state.appearances {
            if printings[appearance.printingID] == nil || !products.contains(appearance.productID) ||
                appearance.observationIDs.isEmpty || appearance.observationIDs.contains(where: { observations[$0] == nil }) {
                fail("invalidProductAppearance", appearance.productID)
            }
            if !appearance.observationIDs.contains(where: { id in
                guard let printing = printings[appearance.printingID],
                      let observation = observations[id] else { return false }
                return observation.kind == .catalog && observation.productEvidence.contains(appearance.productID)
                    && observation.language == printing.language
                    && observation.printedEvidence["number"] == cards[printing.canonicalCardID]?.printedNumber
                    // Explicit retained identity review also anchors historical
                    // appearances after a reviewed source-alias reassignment.
                    && (printing.sourceAliases.contains(observation.alias)
                        || printing.review?.evidence.contains(where: {
                            $0.kind == .printedIdentity && $0.observationID == id
                        }) == true)
            }) { fail("missingProductAppearanceEvidence", appearance.productID) }
        }
        for inventory in release.inventories {
            unique(inventory.observationIDs, "duplicateInventoryObservation")
            if !OnePieceTextNormalization.nonempty(inventory.snapshotID) || inventory.observationIDs.contains(where: {
                observations[$0]?.alias.provider != inventory.provider
            }) { fail("invalidInventory", inventory.snapshotID) }
        }
        unique(release.inventories.map { "\($0.provider)|\($0.snapshotID)" }, "duplicateInventorySnapshot")
        let inventoriedIDs = Set(release.inventories.flatMap(\.observationIDs))
        if !Set(observations.keys).isSubset(of: inventoriedIDs) { fail("missingObservationInventory", "observations") }
        if release.indexes != OnePieceCatalogIndexes(registry: state) { fail("invalidCandidateIndexes", "indexes disagree with registry") }
        if release.inventories.contains(where: { !$0.paginationComplete }) && !release.indexes.automaticCandidateIDsByCanonicalID.isEmpty {
            fail("incompleteSourceInventory", "automatic authority requires complete discovery inventories")
        }
        if let previous {
            if release.revision <= previous.revision { fail("nonMonotonicRevision", String(release.revision)) }
            for old in previous.registry.printings {
                guard let current = printings[old.id] else { fail("removedPermanentPrinting", old.id.uuidString); continue }
                if current.canonicalCardID != old.canonicalCardID || current.artworkID != old.artworkID || current.language != old.language ||
                    current.region != old.region || current.releaseID != old.releaseID || current.distributionLabel != old.distributionLabel ||
                    current.treatment != old.treatment || current.stamp != old.stamp || current.blockText != old.blockText ||
                    current.copyrightText != old.copyrightText { fail("mutatedPermanentIdentity", old.id.uuidString) }
                for alias in old.sourceAliases where aliases[alias] != old.id {
                    guard let newID = aliases[alias], state.corrections.contains(where: {
                        $0.fromPrintingIDs.contains(old.id) && $0.toPrintingIDs.contains(newID) && $0.movedAliases.contains(alias)
                    }) else { fail("unreviewedAliasChange", alias.sourceID); continue }
                }
            }
            for correction in previous.registry.corrections where !state.corrections.contains(correction) {
                fail("removedCorrectionHistory", correction.id)
            }
        }
        return issues.sorted { ($0.code, $0.context) < ($1.code, $1.context) }
    }
}
