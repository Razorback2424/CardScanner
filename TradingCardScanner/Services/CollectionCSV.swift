import Foundation
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct CollectionCSVDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.commaSeparatedText] }

    let text: String

    init(text: String) {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents,
              let text = String(data: data, encoding: .utf8) else {
            throw CollectionCSVError.unreadableFile
        }
        self.text = text
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}

struct CollectionCSVImportPlan: Sendable {
    var entries: [CollectionCSVEntry]
    let skippedRows: Int
    let skippedCSVText: String?

    var totalQuantity: Int { entries.reduce(0) { $0 + $1.quantity } }
}

struct CollectionCSVImportResult: Sendable {
    let insertedEntries: Int
    let mergedEntries: Int
    let totalQuantity: Int
    let skippedRows: Int
}

struct CollectionCSVEntry: Sendable {
    let collectionKey: String
    let game: CardGame
    let providerID: String
    let name: String
    let setName: String
    let setCode: String
    let cardNumber: String
    let rarity: String?
    let imageURL: String?
    let thumbnailURL: String?
    let variant: PhysicalVariant?
    let importedMarketPriceUSD: Double?
    let importedPriceAsOf: Date?
    var quantity: Int
    let dateAdded: Date
    /// Raw card, graded slab or sealed product. Defaulted so every existing
    /// construction site keeps meaning what it meant.
    var itemKind: CollectionItemKind = .rawCard
    var gradingCompany: GradingCompany?
    var grade: CardGrade?
}

enum CollectionCSVError: LocalizedError {
    case unreadableFile
    case missingColumns
    case noCards

    var errorDescription: String? {
        switch self {
        case .unreadableFile:
            return "The CSV file could not be read."
        case .missingColumns:
            return "The CSV does not include enough card information."
        case .noCards:
            return "No importable cards were found in this CSV."
        }
    }
}

enum CollectionCSV {
    /// Appended, never reordered. A file exported by an older build still
    /// imports, and a file exported by this one opens in anything that reads the
    /// original columns.
    private static let exportHeaders = [
        "game", "provider_id", "card_name", "set_name", "set_code",
        "card_number", "finish", "finish_name", "quantity", "rarity",
        "image_url", "thumbnail_url", "date_added",
        "item_kind", "justtcg_card_id", "justtcg_variant_id",
        "justtcg_api_version", "grading_company", "grade", "grade_label",
        "grading_qualifier", "certification_number", "market_region"
    ]

    static func export(_ cards: [CollectedCard]) -> CollectionCSVDocument {
        let formatter = ISO8601DateFormatter()
        let rows = cards.sorted { left, right in
            if left.game != right.game { return left.game < right.game }
            if left.setCode != right.setCode { return left.setCode < right.setCode }
            if left.cardNumber != right.cardNumber { return left.cardNumber < right.cardNumber }
            return (left.variantID ?? "") < (right.variantID ?? "")
        }.map { card in
            [
                card.game,
                card.catalogProviderID ?? card.providerID,
                card.name,
                card.setName,
                card.setCode,
                card.cardNumber,
                card.variantID ?? "",
                card.variantLabel ?? "",
                String(card.quantity),
                card.rarity ?? "",
                card.imageURL ?? "",
                card.thumbnailURL ?? "",
                formatter.string(from: card.dateAdded),
                // Rows written before item kinds existed export as raw cards,
                // which is what they are.
                card.itemKind.rawValue,
                card.justTCGCardID ?? "",
                card.justTCGVariantID ?? "",
                card.justTCGAPIVersion ?? "",
                card.gradingCompanyRaw ?? "",
                card.gradeRaw ?? "",
                card.gradeLabel ?? "",
                card.gradingQualifier ?? "",
                card.certificationNumber ?? "",
                card.marketRegionRaw ?? ""
            ]
        }

        let text = ([exportHeaders] + rows)
            .map { $0.map(escape).joined(separator: ",") }
            .joined(separator: "\n") + "\n"
        return CollectionCSVDocument(text: text)
    }

    /// A compact, support-oriented export of cards that still have no exact
    /// variant price after import/refresh. It includes resolution state rather
    /// than making someone infer the failure from a blank dollar column.
    static func exportUnpriced(
        _ cards: [CollectedCard],
        priceRecords: [PriceRecord]
    ) -> CollectionCSVDocument {
        let recordsByKey = Dictionary(
            priceRecords.map { ($0.key, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        return diagnosticExport(
            cards.filter { card in
                recordsByKey[card.priceKey]?.unitMarketPriceUSD == nil
            },
            priceRecords: priceRecords,
            diagnostic: unpricedReason
        )
    }

    /// Entries whose stored model has no usable artwork URL. A remote image that
    /// is temporarily offline is deliberately not classified as missing data.
    static func exportMissingArtwork(
        _ cards: [CollectedCard],
        priceRecords: [PriceRecord]
    ) -> CollectionCSVDocument {
        diagnosticExport(
            cards.filter { $0.highImageURL == nil },
            priceRecords: priceRecords,
            diagnostic: artworkReason
        )
    }

    private static func diagnosticExport(
        _ cards: [CollectedCard],
        priceRecords: [PriceRecord],
        diagnostic: (CollectedCard, PriceRecord?) -> String
    ) -> CollectionCSVDocument {
        let formatter = ISO8601DateFormatter()
        let recordsByKey = Dictionary(
            priceRecords.map { ($0.key, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let headers = [
            "game", "local_provider_id", "catalog_provider_id", "card_name",
            "set_name", "set_code", "card_number", "finish", "finish_name",
            "quantity", "diagnostic", "price_status", "price_usd", "price_source",
            "price_listing", "last_price_check", "price_refresh_failed",
            "image_url", "thumbnail_url", "catalog_metadata_checked_at"
        ]
        let rows = cards.sorted(by: diagnosticSort).map { card -> [String] in
            let record = recordsByKey[card.priceKey]
            return [
                card.game,
                card.providerID,
                card.catalogProviderID ?? "",
                card.name,
                card.setName,
                card.setCode,
                card.cardNumber,
                card.variantID ?? "",
                card.variantLabel ?? "",
                String(card.quantity),
                diagnostic(card, record),
                priceStatus(record),
                record?.unitMarketPriceUSD.map { String($0) } ?? "",
                record?.source?.label ?? "",
                record?.sourceVariantID ?? "",
                record?.lastCheckedAt.map { formatter.string(from: $0) } ?? "",
                record?.lastFailureAt == nil ? "false" : "true",
                card.imageURL ?? "",
                card.thumbnailURL ?? "",
                card.catalogMetadataCheckedAt.map { formatter.string(from: $0) } ?? ""
            ]
        }
        let text = ([headers] + rows)
            .map { $0.map(escape).joined(separator: ",") }
            .joined(separator: "\n") + "\n"
        return CollectionCSVDocument(text: text)
    }

    private static func diagnosticSort(_ left: CollectedCard, _ right: CollectedCard) -> Bool {
        if left.game != right.game { return left.game < right.game }
        if left.setName != right.setName { return left.setName < right.setName }
        if left.cardNumber != right.cardNumber { return left.cardNumber < right.cardNumber }
        if left.name != right.name { return left.name < right.name }
        return (left.variantID ?? "") < (right.variantID ?? "")
    }

    private static func priceStatus(_ record: PriceRecord?) -> String {
        guard let record, record.lastCheckedAt != nil else { return "never_checked" }
        if record.lastFailureAt != nil { return "refresh_failed" }
        return record.unitMarketPriceUSD == nil ? "unavailable" : "priced"
    }

    /// Why one row still has no price.
    ///
    /// The value of this column is that each answer points somewhere different:
    /// a matching problem is a code fix, a budget stop is a wait, an unavailable
    /// price is the honest end of the road. Collapsing them into "unpriced" is
    /// what hid a starvation bug for as long as it did.
    private static func unpricedReason(_ card: CollectedCard, _ record: PriceRecord?) -> String {
        guard let record, record.lastCheckedAt != nil else { return "not_checked" }

        if card.catalogProviderID != nil,
           record.lastFailureAt != nil,
           let metadataCheckedAt = card.catalogMetadataCheckedAt,
           metadataCheckedAt > (record.lastCheckedAt ?? .distantPast) {
            return "identity_resolved_after_failed_check"
        }

        switch card.itemKind {
        case .sealedProduct:
            // A sealed row exists only because it was added from the vendor's
            // own catalogue, so a missing price is the product being unlisted
            // rather than unmatched.
            return card.justTCGVariantID == nil
                ? "sealed_product_unmatched"
                : "no_exact_variant_price"

        case .gradedCard:
            if card.justTCGVariantID == nil { return "graded_variant_unavailable" }
            // The vendor does not manufacture a number for every grader/grade
            // permutation; a null price is a real answer.
            return record.lastFailureAt != nil
                ? "provider_request_failed"
                : "graded_market_price_null"

        case .rawCard:
            if record.lastFailureAt != nil { return "provider_request_failed" }
            // Identity was never established with the market provider, so the
            // card has never been asked about by a stable handle.
            if card.justTCGVariantID == nil, card.justTCGCardID != nil {
                return "justtcg_variant_unresolved"
            }
            return "no_exact_variant_price"
        }
    }

    private static func artworkReason(_ card: CollectedCard, _ record: PriceRecord?) -> String {
        if card.catalogMetadataCheckedAt == nil { return "not_checked" }
        if card.catalogProviderID == nil { return "catalog_identity_not_resolved" }
        return "provider_has_no_artwork"
    }

    static func parse(_ data: Data) throws -> CollectionCSVImportPlan {
        guard var text = String(data: data, encoding: .utf8) else {
            throw CollectionCSVError.unreadableFile
        }
        if text.first == "\u{feff}" { text.removeFirst() }

        let delimiter = delimiter(in: text)
        let table = parseRows(text, delimiter: delimiter)
        guard let rawHeaders = table.first, !rawHeaders.isEmpty else {
            throw CollectionCSVError.missingColumns
        }

        let headers = rawHeaders.map(normalizeHeader)
        let isPortfolioExport = headers.contains("category")
            && headers.contains("product_name")
            && headers.contains("card_number")
            && headers.contains("quantity")
        let hasProviderID = headers.contains("provider_id") || headers.contains("scryfall_uuid") || headers.contains("tcgdex_id")
        let hasIdentity = headers.contains("card_name") || headers.contains("name")
        guard (hasProviderID && hasIdentity) || isPortfolioExport else {
            throw CollectionCSVError.missingColumns
        }

        var entriesByKey: [String: CollectionCSVEntry] = [:]
        var skippedRows = 0
        var skippedValues: [[String]] = []

        for values in table.dropFirst() {
            var row: [String: String] = [:]
            for (index, header) in headers.enumerated() where row[header] == nil {
                row[header] = index < values.count
                    ? values[index].trimmingCharacters(in: .whitespacesAndNewlines)
                    : ""
            }

            if let exportType = value(["export_type"], in: row),
               !exportType.isEmpty,
               exportType.lowercased() != "card" {
                skippedRows += 1
                skippedValues.append(values)
                continue
            }

            let parsed = entries(from: row)
            if parsed.isEmpty {
                skippedRows += 1
                skippedValues.append(values)
                continue
            }

            for entry in parsed {
                if var existing = entriesByKey[entry.collectionKey] {
                    existing.quantity += entry.quantity
                    entriesByKey[entry.collectionKey] = existing
                } else {
                    entriesByKey[entry.collectionKey] = entry
                }
            }
        }

        guard !entriesByKey.isEmpty else { throw CollectionCSVError.noCards }
        return CollectionCSVImportPlan(
            entries: entriesByKey.values.sorted { $0.collectionKey < $1.collectionKey },
            skippedRows: skippedRows,
            skippedCSVText: skippedValues.isEmpty
                ? nil
                : csvText(headers: rawHeaders, rows: skippedValues)
        )
    }

    @MainActor
    static func apply(_ plan: CollectionCSVImportPlan, to context: ModelContext) throws -> CollectionCSVImportResult {
        let storedCards = try context.fetch(FetchDescriptor<CollectedCard>())
        var cardsByKey = Dictionary(uniqueKeysWithValues: storedCards.map { ($0.collectionKey, $0) })
        let priceStore = PriceStore(context: context)
        var inserted = 0
        var merged = 0

        for entry in plan.entries {
            if let existing = cardsByKey[entry.collectionKey] {
                existing.quantity += entry.quantity
                existing.dateAdded = max(existing.dateAdded, entry.dateAdded)
                if existing.imageURL == nil { existing.imageURL = entry.imageURL }
                if existing.thumbnailURL == nil { existing.thumbnailURL = entry.thumbnailURL }
                merged += 1
            } else {
                let card = CollectedCard(
                    collectionKey: entry.collectionKey,
                    game: entry.game,
                    providerID: entry.providerID,
                    name: entry.name,
                    setName: entry.setName,
                    setCode: entry.setCode,
                    cardNumber: entry.cardNumber,
                    rarity: entry.rarity,
                    imageURL: entry.imageURL,
                    thumbnailURL: entry.thumbnailURL,
                    variant: entry.variant,
                    variantResolution: .imported,
                    identityResolution: .imported,
                    quantity: entry.quantity,
                    dateAdded: entry.dateAdded
                )
                // What kind of object this is, and — for a slab — the grade the
                // export stated. The vendor's variant UUID is not known from a
                // CSV and is adopted later, when pricing resolves it.
                card.itemKindRaw = entry.itemKind.rawValue
                card.gradingCompanyRaw = entry.gradingCompany?.rawValue
                card.gradeRaw = entry.grade?.value
                card.gradeLabel = entry.grade?.label
                card.gradingQualifier = entry.grade?.qualifier
                context.insert(card)
                cardsByKey[entry.collectionKey] = card
                inserted += 1
            }

            if let amount = entry.importedMarketPriceUSD {
                priceStore.storeImported(
                    amount: amount,
                    sourceUpdatedAt: entry.importedPriceAsOf,
                    game: entry.game,
                    printingID: entry.providerID,
                    variantID: entry.variant?.id
                )
            }
        }

        try context.save()
        return CollectionCSVImportResult(
            insertedEntries: inserted,
            mergedEntries: merged,
            totalQuantity: plan.totalQuantity,
            skippedRows: plan.skippedRows
        )
    }

    private static func entries(from row: [String: String]) -> [CollectionCSVEntry] {
        if row["category"] != nil {
            return portfolioEntries(from: row)
        }

        guard let providerID = value(["provider_id", "scryfall_uuid", "tcgdex_id"], in: row), !providerID.isEmpty,
              let name = value(["card_name", "name", "english_card_name"], in: row), !name.isEmpty else {
            return []
        }

        let isScryfallExport = !(row["scryfall_uuid"] ?? "").isEmpty
        let game = CardGame(rawValue: value(["game"], in: row)?.lowercased() ?? "")
            ?? (isScryfallExport ? .magic : .pokemon)
        guard isSupportedLanguage(value(["language", "lang"], in: row)) else { return [] }
        let setName = value(["set_name"], in: row) ?? "Unknown Set"
        let setCode = value(["set_code", "set"], in: row) ?? ""
        let cardNumber = value(["card_number", "collector_number", "local_id"], in: row) ?? ""
        let rarity = nonempty(value(["rarity"], in: row))
        let importedDate = value(["date_added"], in: row).flatMap { ISO8601DateFormatter().date(from: $0) } ?? .now
        let suppliedImage = nonempty(value(["image_url"], in: row))
        let suppliedThumbnail = nonempty(value(["thumbnail_url"], in: row))
        let imageURL = suppliedImage ?? scryfallImageURL(id: providerID, version: "normal", game: game)
        let thumbnailURL = suppliedThumbnail ?? scryfallImageURL(id: providerID, version: "small", game: game)

        if isScryfallExport {
            var result: [CollectionCSVEntry] = []
            let nonfoilQuantity = positiveInt(value(["quantity"], in: row))
            let foilQuantity = positiveInt(value(["foil_quantity"], in: row))
            if nonfoilQuantity > 0 {
                result.append(makeEntry(
                    game: game, providerID: providerID, name: name, setName: setName,
                    setCode: setCode, cardNumber: cardNumber, rarity: rarity,
                    imageURL: imageURL, thumbnailURL: thumbnailURL,
                    variant: .nonfoil, quantity: nonfoilQuantity, dateAdded: importedDate
                ))
            }
            if foilQuantity > 0 {
                result.append(makeEntry(
                    game: game, providerID: providerID, name: name, setName: setName,
                    setCode: setCode, cardNumber: cardNumber, rarity: rarity,
                    imageURL: imageURL, thumbnailURL: thumbnailURL,
                    variant: .foil, quantity: foilQuantity, dateAdded: importedDate
                ))
            }
            return result
        }

        let quantity = positiveInt(value(["quantity"], in: row))
        guard quantity > 0 else { return [] }
        let variant = importedVariant(
            id: value(["finish", "variant_id"], in: row),
            label: value(["finish_name", "variant", "finish_label"], in: row)
        )
        return [makeEntry(
            game: game, providerID: providerID, name: name, setName: setName,
            setCode: setCode, cardNumber: cardNumber, rarity: rarity,
            imageURL: imageURL, thumbnailURL: thumbnailURL,
            variant: variant, quantity: quantity, dateAdded: importedDate
        )]
    }

    private static func portfolioEntries(from row: [String: String]) -> [CollectionCSVEntry] {
        let category = value(["category"], in: row)?.lowercased()
        let game: CardGame
        switch category {
        case "pokemon": game = .pokemon
        case "magic: the gathering", "magic": game = .magic
        default: return []
        }

        guard positiveInt(value(["quantity"], in: row)) > 0,
              value(["watchlist"], in: row)?.lowercased() != "true" else {
            return []
        }

        // Graded slabs used to be dropped here. That was correct when the app
        // had no way to represent one — importing them would have produced raw
        // rows claiming to be something they are not — but it no longer is.
        let rawGrade = value(["grade"], in: row)
        let graded = ImportedGradeParser.isGraded(rawGrade)
            ? rawGrade.flatMap(ImportedGradeParser.parse)
            : nil
        // A grade string that cannot be read is still a graded card, and
        // importing it as a raw one would silently merge a slab into the raw
        // copy's quantity. Skipping keeps it visible in the skipped-rows export.
        if ImportedGradeParser.isGraded(rawGrade), graded == nil { return [] }

        guard let rawName = value(["product_name"], in: row),
              let setName = value(["set"], in: row) else {
            return []
        }
        guard !isUnsupportedPortfolioLanguage(
            game: game,
            setName: setName,
            productName: rawName
        ) else { return [] }
        let cardNumber = value(["card_number"], in: row) ?? ""
        let isSealed = isSealedOrAccessory(rawName, cardNumber: cardNumber)

        let name = cleanedPortfolioName(rawName, cardNumber: cardNumber, game: game)
        let variant = portfolioVariant(
            value(["variance"], in: row),
            productName: rawName,
            game: game
        )
        let providerID = syntheticProviderID(
            game: game,
            setName: setName,
            cardNumber: cardNumber,
            name: name
        )
        let quantity = positiveInt(value(["quantity"], in: row))
        let importedPrice = portfolioMarketPrice(in: row)

        return [makeEntry(
            game: game,
            providerID: providerID,
            name: name,
            setName: setName,
            setCode: setName,
            cardNumber: cardNumber,
            rarity: nil,
            imageURL: nil,
            thumbnailURL: nil,
            // A slab has no raw finish and a sealed box has no finish at all.
            // Carrying one would put a "Reverse Holo" badge on a booster box.
            variant: (graded != nil || isSealed) ? nil : variant,
            importedMarketPriceUSD: importedPrice?.amount,
            importedPriceAsOf: importedPrice?.asOf,
            quantity: quantity,
            dateAdded: .now,
            itemKind: graded != nil ? .gradedCard : (isSealed ? .sealedProduct : .rawCard),
            gradingCompany: graded?.company,
            grade: graded?.grade
        )]
    }

    private static func makeEntry(
        game: CardGame,
        providerID: String,
        name: String,
        setName: String,
        setCode: String,
        cardNumber: String,
        rarity: String?,
        imageURL: String?,
        thumbnailURL: String?,
        variant: PhysicalVariant?,
        importedMarketPriceUSD: Double? = nil,
        importedPriceAsOf: Date? = nil,
        quantity: Int,
        dateAdded: Date,
        itemKind: CollectionItemKind = .rawCard,
        gradingCompany: GradingCompany? = nil,
        grade: CardGrade? = nil
    ) -> CollectionCSVEntry {
        let baseKey = game == .magic ? "magic:\(providerID)" : providerID
        let key: String
        switch itemKind {
        case .rawCard:
            // Unchanged. Every row imported before this existed keeps its key.
            key = variant.map { "\(baseKey)#\($0.id)" } ?? baseKey

        case .gradedCard:
            // A CSV has no vendor variant UUID, so the key is built from what
            // the export actually states: grader, grade, label and qualifier.
            // Enough to keep a PSA 10 apart from a PSA 10 OC and from the raw
            // copy — and the UUID is adopted later when pricing resolves it.
            let fragment = gradingCompany.map { company in
                "\(company.rawValue)|\(grade?.identityFragment ?? "")"
            } ?? "unknown"
            key = "graded:\(baseKey)#\(fragment)"

        case .sealedProduct:
            // No collector number to work with, so set plus product name is the
            // identity. The namespace is what stops a booster box from ever
            // sharing a row with a card of the same name.
            key = "sealed:\(baseKey)"
        }

        return CollectionCSVEntry(
            collectionKey: key,
            game: game,
            providerID: providerID,
            name: name,
            setName: setName,
            setCode: setCode,
            cardNumber: cardNumber,
            rarity: rarity,
            imageURL: imageURL,
            thumbnailURL: thumbnailURL,
            variant: variant,
            importedMarketPriceUSD: importedMarketPriceUSD,
            importedPriceAsOf: importedPriceAsOf,
            quantity: quantity,
            dateAdded: dateAdded,
            itemKind: itemKind,
            gradingCompany: gradingCompany,
            grade: grade
        )
    }

    private static func importedVariant(id: String?, label: String?) -> PhysicalVariant? {
        let raw = nonempty(id) ?? nonempty(label)
        guard let raw else { return nil }
        let normalized = raw.lowercased().replacingOccurrences(of: " ", with: "")
        switch normalized {
        case "normal": return .normal
        case "nonfoil", "non-foil": return .nonfoil
        case "foil": return .foil
        case "holo", "holofoil": return .holo
        case "reverse", "reverseholo", "reverseholofoil": return .reverse
        case "etched", "etchedfoil": return .etched
        case "firstedition", "1stedition": return .firstEdition
        case "pokeball", "pokéball": return .pokeBall
        case "masterball": return .masterBall
        default:
            return PhysicalVariant(id: raw, label: nonempty(label) ?? raw.capitalized)
        }
    }

    private static func scryfallImageURL(id: String, version: String, game: CardGame) -> String? {
        guard game == .magic else { return nil }
        return "https://api.scryfall.com/cards/\(id)?format=image&version=\(version)"
    }

    private static func portfolioVariant(
        _ value: String?,
        productName: String,
        game: CardGame
    ) -> PhysicalVariant? {
        let lowerName = productName.lowercased()
        if lowerName.contains("master ball pattern") { return .masterBall }
        if lowerName.contains("master ball)") { return .masterBall }
        if lowerName.contains("poke ball pattern") || lowerName.contains("poke ball)") { return .pokeBall }
        if lowerName.contains("dusk ball)") { return PhysicalVariant(id: "duskBall", label: "Dusk Ball") }
        if lowerName.contains("friend ball)") { return PhysicalVariant(id: "friendBall", label: "Friend Ball") }
        if lowerName.contains("quick ball)") { return PhysicalVariant(id: "quickBall", label: "Quick Ball") }
        if lowerName.contains("love ball)") { return PhysicalVariant(id: "loveBall", label: "Love Ball") }

        let normalized = value?.lowercased().replacingOccurrences(of: " ", with: "") ?? ""
        switch (game, normalized) {
        case (.magic, "normal"): return .nonfoil
        case (.magic, "foil"): return .foil
        case (.magic, "etched"), (.magic, "etchedfoil"): return .etched
        case (.pokemon, "normal"): return .normal
        case (.pokemon, "holofoil"), (.pokemon, "foil"): return .holo
        case (.pokemon, "reverseholofoil"): return .reverse
        case (.pokemon, "pokeballreverseholo"): return .pokeBall
        case (.pokemon, "1stedition"): return .firstEdition
        default:
            return importedVariant(id: value, label: value)
        }
    }

    private static func cleanedPortfolioName(_ value: String, cardNumber: String, game: CardGame) -> String {
        guard game == .pokemon else { return value }
        // These treatments are promoted into first-class variants above. Leave
        // every other parenthetical exactly as the source supplied it.
        let name = [
            " (Poke Ball Pattern)", " (Master Ball Pattern)",
            " (Poke Ball)", " (Master Ball)", " (Dusk Ball)",
            " (Friend Ball)", " (Quick Ball)", " (Love Ball)"
        ]
            .reduce(value) { name, suffix in name.replacingOccurrences(of: suffix, with: "") }
        return name.replacingOccurrences(of: " - \(cardNumber)", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func syntheticProviderID(
        game: CardGame,
        setName: String,
        cardNumber: String,
        name: String
    ) -> String {
        let identity = [game.rawValue, setName.lowercased(), cardNumber.lowercased(), name.lowercased()]
            .joined(separator: "|")
        return "csv:\(Data(identity.utf8).base64EncodedString())"
    }

    private static func isSealedOrAccessory(_ name: String, cardNumber: String) -> Bool {
        guard cardNumber.isEmpty else { return false }
        let lower = name.lowercased()
        let productTerms = [
            "elite trainer box", "booster", "bundle", " collection",
            "battle deck", "mini tin", "token"
        ]
        return productTerms.contains { lower.contains($0) }
    }

    private static func isSupportedLanguage(_ value: String?) -> Bool {
        guard let value = nonempty(value)?.lowercased() else { return true }
        return ["en", "eng", "english"].contains(value)
    }

    private static func isUnsupportedPortfolioLanguage(
        game: CardGame,
        setName: String,
        productName: String
    ) -> Bool {
        let combined = "\(setName) \(productName)".lowercased()
        return combined.contains("japanese") || combined.contains("japan import")
    }

    // A list of Japanese-exclusive Pokémon sets used to be excluded here —
    // Inferno X, Terastal Festival ex, Mega Brave and the rest. That was right
    // while the app could not identify them: importing produced rows it could
    // never resolve or price.
    //
    // It is not right any more. Those are exactly the sets the catalog
    // normalizer now routes to TCGdex's `ja` edition, where they resolve to real
    // cards with artwork and numbering and carry Cardmarket prices. Excluding
    // them here meant the app supported a set it refused to let anyone import.

    private static func canonicalImportText(_ value: String) -> String {
        let folded = value.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: .current
        )
        let cleaned = folded.unicodeScalars.reduce(into: "") { result, scalar in
            if CharacterSet.alphanumerics.contains(scalar) {
                result.unicodeScalars.append(scalar)
            } else {
                result.append(" ")
            }
        }
        return cleaned.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    private static func portfolioMarketPrice(
        in row: [String: String]
    ) -> (amount: Double, asOf: Date?)? {
        guard let field = row.first(where: { $0.key.hasPrefix("market_price") }),
              let amount = currencyAmount(field.value),
              amount > 0 else {
            return nil
        }
        return (amount, dateEmbedded(in: field.key))
    }

    private static func currencyAmount(_ value: String) -> Double? {
        let cleaned = value.filter { $0.isNumber || $0 == "." || $0 == "-" }
        return Double(cleaned)
    }

    private static func dateEmbedded(in value: String) -> Date? {
        guard let match = value.range(
            of: #"\d{4}_\d{2}_\d{2}"#,
            options: .regularExpression
        ) else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy_MM_dd"
        return formatter.date(from: String(value[match]))
    }

    private static func positiveInt(_ value: String?) -> Int {
        max(0, Int(value ?? "") ?? 0)
    }

    private static func nonempty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }

    private static func value(_ names: [String], in row: [String: String]) -> String? {
        for name in names {
            if let value = row[name], !value.isEmpty { return value }
        }
        return nil
    }

    private static func normalizeHeader(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")
    }

    private static func delimiter(in text: String) -> Character {
        let firstLine = text.prefix { $0 != "\n" && $0 != "\r" }
        let candidates: [Character] = [";", ",", "\t"]
        return candidates.max { left, right in
            firstLine.filter { $0 == left }.count < firstLine.filter { $0 == right }.count
        } ?? ","
    }

    private static func parseRows(_ text: String, delimiter: Character) -> [[String]] {
        let characters = Array(text)
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var index = 0

        while index < characters.count {
            let character = characters[index]
            if inQuotes {
                if character == "\"" {
                    if index + 1 < characters.count, characters[index + 1] == "\"" {
                        field.append("\"")
                        index += 1
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.append(character)
                }
            } else if character == "\"" {
                inQuotes = true
            } else if character == delimiter {
                row.append(field)
                field = ""
            } else if character == "\n" {
                row.append(field)
                if row.contains(where: { !$0.isEmpty }) { rows.append(row) }
                row = []
                field = ""
            } else if character != "\r" {
                field.append(character)
            }
            index += 1
        }

        if !field.isEmpty || !row.isEmpty {
            row.append(field)
            if row.contains(where: { !$0.isEmpty }) { rows.append(row) }
        }
        return rows
    }

    private static func escape(_ value: String) -> String {
        guard value.contains(",") || value.contains("\"") || value.contains("\n") || value.contains("\r") else {
            return value
        }
        return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    private static func csvText(headers: [String], rows: [[String]]) -> String {
        ([headers] + rows)
            .map { $0.map(escape).joined(separator: ",") }
            .joined(separator: "\n") + "\n"
    }
}
