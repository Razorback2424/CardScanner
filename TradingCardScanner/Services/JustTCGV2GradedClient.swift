import Foundation

/// Graded slab pricing, from the `/v2/cards` beta.
///
/// Isolated behind its own type on purpose. v2 is in public beta and its schema
/// may move; keeping its decoding here means a breaking change lands in one file
/// rather than across the collection layer. It is also the reason graded prices
/// are labelled as beta wherever they are shown.
///
/// ## Why this does not batch yet
///
/// The batching research establishes `POST /v1/cards` for v1 variants. It does
/// **not** establish that a v2 graded variant UUID may be passed as `variantId`
/// to that endpoint, nor that `/v2/cards` exposes its own POST batching. Until
/// the contract slice answers that, graded refresh groups by underlying card and
/// asks once per card with `graded=only`.
///
/// The interface deliberately hides which of those it is doing, so moving graded
/// work onto batching later changes this file and nothing else.
struct JustTCGV2GradedClient: Sendable {
    static let apiVersion = "v2"

    private let transport: JustTCGTransport

    init(transport: JustTCGTransport) {
        self.transport = transport
    }

    /// Every graded variant of one card, narrowed to what the user actually owns.
    ///
    /// `graded=only` rather than `graded=include`: including raw results costs a
    /// surcharge and returns data the raw path already has. Filtering to the
    /// owned graders and grades keeps the response small — a card can have well
    /// over a hundred grader/grade permutations, almost none of them owned.
    func gradedVariants(
        cardID: String,
        game: CardGame,
        companies: Set<GradingCompany> = [],
        grades: Set<String> = [],
        lane: JustTCGRequestLane = .interactive
    ) async throws -> [GradedVariant] {
        var query: [(String, String)] = [
            // Verified against the live API: without this, v2 rejects the call
            // with "A browse request requires a game or set filter." A `cardId`
            // alone is not enough to stop it being treated as a browse.
            ("game", JustTCGV1Client.gameSlug(for: game)),
            ("cardId", cardID),
            ("graded", "only"),
            // Routine pricing never asks for history.
            ("include_price_history", "false")
        ]
        if !companies.isEmpty {
            query.append(("company", companies.map(\.rawValue).sorted().joined(separator: ",")))
        }
        if !grades.isEmpty {
            query.append(("grade", grades.sorted().joined(separator: ",")))
        }

        let response: GradedResponse = try await transport.get(
            "v2/cards",
            query: query,
            lane: lane
        )

        return response.data.flatMap { card in
            (card.variants ?? []).compactMap { variant -> GradedVariant? in
                guard let id = variant.variantId,
                      let grading = variant.grading,
                      let company = grading.gradingCompany else {
                    return nil
                }
                return GradedVariant(
                    id: id,
                    company: company,
                    grade: grading.cardGrade,
                    // `null` is a real answer: the vendor does not manufacture a
                    // number for every grader/grade permutation, and an absent
                    // price must read as "no reliable market price" rather than
                    // as zero.
                    marketPriceUSD: variant.price,
                    updatedAt: variant.updatedAt
                )
            }
        }
    }

    /// The graders and grades a set of owned slabs covers, so a refresh asks
    /// only about those.
    static func ownedFilters(
        for cards: [CollectedCard]
    ) -> (companies: Set<GradingCompany>, grades: Set<String>) {
        var companies: Set<GradingCompany> = []
        var grades: Set<String> = []
        for card in cards where card.itemKind == .gradedCard {
            if let company = card.gradingCompany { companies.insert(company) }
            if let grade = card.gradeRaw { grades.insert(grade) }
        }
        return (companies, grades)
    }

    private struct GradedResponse: Decodable {
        let data: [JustTCGCard]
        let metadata: JustTCGQuotaMetadata?

        enum CodingKeys: String, CodingKey {
            case data
            case metadata = "_metadata"
        }
    }
}
