import Foundation

enum ScannedGradedOutcome: Equatable, Sendable {
    case bound(GradedVariant)
    case unpricedGrade
    case unmatchedProduct
    case unavailable
}

protocol ScannedGradedResolving: Sendable {
    func resolve(
        card: IdentifiedCard,
        slab: GradedSlabEvidence,
        pokemonPrintRun: PokemonPrintRun?
    ) async -> ScannedGradedOutcome
}

/// Keeps the resolver's credential gate, timeout, and response mapping
/// testable without keychain state or a live network transport.
protocol ScannedGradedLookupClient: Sendable {
    func lookup(
        identity: GradedCardIdentity,
        game: CardGame,
        companies: Set<GradingCompany>,
        grades: Set<String>,
        lane: JustTCGRequestLane
    ) async throws -> GradedVariantLookupResult
}

extension JustTCGV2GradedClient: ScannedGradedLookupClient {}

/// Bounded interactive lookup used by the camera surface. A slow or absent
/// vendor response degrades to an unbound slab; it never blocks the card from
/// being added and it never turns a raw quote into a graded quote.
struct ScannedGradedResolver: ScannedGradedResolving, Sendable {
    private struct TimeoutError: Error {}

    private let client: any ScannedGradedLookupClient
    private let timeout: Duration
    private let credentialsAvailable: Bool?

    init(
        client: any ScannedGradedLookupClient = JustTCGV2GradedClient(transport: .shared),
        timeout: Duration = .seconds(2.5),
        credentialsAvailable: Bool? = nil
    ) {
        self.client = client
        self.timeout = timeout
        self.credentialsAvailable = credentialsAvailable
    }

    func resolve(
        card: IdentifiedCard,
        slab: GradedSlabEvidence,
        pokemonPrintRun: PokemonPrintRun?
    ) async -> ScannedGradedOutcome {
        guard credentialsAvailable ?? PriceVendorCredentials.hasKey else { return .unavailable }

        let identity = GradedCardIdentity(card, pokemonPrintRun: pokemonPrintRun)
        let gradeFilter = slab.grade.value ?? slab.grade.label

        do {
            let result = try await withThrowingTaskGroup(of: GradedVariantLookupResult.self) { group in
                group.addTask {
                    try await client.lookup(
                        identity: identity,
                        game: card.game,
                        companies: [slab.company],
                        grades: gradeFilter.map { [$0] } ?? [],
                        lane: .interactive
                    )
                }
                group.addTask {
                    try await Task.sleep(for: timeout)
                    throw TimeoutError()
                }
                defer { group.cancelAll() }
                return try await group.next()!
            }

            switch result {
            case let .matched(variants):
                guard let exact = Self.matchingVariant(in: variants, for: slab) else {
                    return .unpricedGrade
                }
                return .bound(exact)
            case .cardFoundWithoutGradedVariants:
                return .unpricedGrade
            case .noProductMatch:
                return .unmatchedProduct
            }
        } catch is CancellationError {
            return .unavailable
        } catch {
            return .unavailable
        }
    }

    /// Match company, numeric grade, and qualifier first. The app and vendor
    /// author those labels independently (and v2 often omits the vendor label),
    /// so label equality is only a tie-breaker for variants that share the
    /// stable grade axis, such as BGS 10 and BGS 10 Black Label.
    static func matchingVariant(
        in variants: [GradedVariant],
        for slab: GradedSlabEvidence
    ) -> GradedVariant? {
        let candidates = variants.filter { variant in
            variant.company == slab.company
                && normalized(variant.grade.value) == normalized(slab.grade.value)
                && normalized(variant.grade.qualifier) == normalized(slab.grade.qualifier)
        }
        guard !candidates.isEmpty else { return nil }

        if let exactLabel = candidates.first(where: {
            normalized($0.grade.label) == normalized(slab.grade.label)
        }) {
            return exactLabel
        }
        return candidates.count == 1 ? candidates[0] : nil
    }

    private static func normalized(_ value: String?) -> String? {
        value?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }
}
