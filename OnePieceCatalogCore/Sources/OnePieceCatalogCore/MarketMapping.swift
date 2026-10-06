import Foundation

public enum OnePieceMarketMappingStatus: String, Codable, Hashable, Sendable {
    case provisional, exact, conflicted
}

public struct OnePieceMarketMapping: Codable, Hashable, Sendable {
    public let printingID: UUID
    public let provider: String
    public let productID: String
    public let providerVariantID: String?
    public let variantID: String
    public let market: String
    public let currency: String
    public let condition: String
    public let qualifiers: [String: String]
    public let status: OnePieceMarketMappingStatus
    public let review: OnePieceReview?

    public init(printingID: UUID, provider: String, productID: String, providerVariantID: String? = nil,
                variantID: String, market: String, currency: String, condition: String,
                qualifiers: [String: String] = [:], status: OnePieceMarketMappingStatus = .provisional,
                review: OnePieceReview? = nil) {
        self.printingID = printingID; self.provider = provider; self.productID = productID
        self.providerVariantID = providerVariantID; self.variantID = variantID
        self.market = market; self.currency = currency; self.condition = condition
        self.qualifiers = qualifiers; self.status = status; self.review = review
    }

    /// Structured key avoids delimiter collisions in vendor identifiers.
    public struct QuoteIdentity: Hashable, Sendable {
        let provider: String, productID: String, providerVariantID: String?
        let market: String, currency: String, condition: String
        let qualifiers: [String: String]
    }
    public var quoteIdentity: QuoteIdentity {
        // TCGplayer's numeric product and lane identify one external SKU.
        // Titles/groups are reviewed metadata, not permission to assign that
        // same SKU to another physical printing. Numeric aliases share it too.
        let product = provider == "tcgplayer" ? UInt64(productID).map(String.init) ?? productID : productID
        return .init(provider: provider, productID: product, providerVariantID: providerVariantID,
              market: market, currency: currency, condition: condition,
              qualifiers: provider == "tcgplayer" && providerVariantID != nil ? [:] : qualifiers)
    }
}
