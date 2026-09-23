import Foundation

enum ScannedGradedOutcome: Equatable, Sendable {
    case bound(GradedVariant)
    case cardNotTracked(GradedMarketCoverage)
    case noGradedListings(GradedMarketCoverage)
    case gradeNotTracked(GradedMarketCoverage)
    case unavailable

    var marketCoverage: GradedMarketCoverage? {
        switch self {
        case let .cardNotTracked(coverage),
             let .noGradedListings(coverage),
             let .gradeNotTracked(coverage):
            return coverage
        case .bound, .unavailable:
            return nil
        }
    }
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
    private let timeoutRetryCount: Int
    private let credentialsAvailable: Bool?

    init(
        client: any ScannedGradedLookupClient = JustTCGV2GradedClient(transport: .shared),
        timeout: Duration = .seconds(60),
        timeoutRetryCount: Int = 1,
        credentialsAvailable: Bool? = nil
    ) {
        self.client = client
        self.timeout = timeout
        self.timeoutRetryCount = max(0, timeoutRetryCount)
        self.credentialsAvailable = credentialsAvailable
    }

    func resolve(
        card: IdentifiedCard,
        slab: GradedSlabEvidence,
        pokemonPrintRun: PokemonPrintRun?
    ) async -> ScannedGradedOutcome {
        guard credentialsAvailable ?? PriceVendorCredentials.hasKey else { return .unavailable }

        // The timeout task is created here, after catalog/label resolution has
        // completed. This covers the cold set-directory request plus the card
        // request at the transport's 25-second timeout and the shared pacer's
        // spacing. The resolver runs after save, so this does not hold scanning.
        let identity = GradedCardIdentity(card, pokemonPrintRun: pokemonPrintRun)
        for attempt in 0...timeoutRetryCount {
            do {
                let result = try await withThrowingTaskGroup(of: GradedVariantLookupResult.self) { group in
                    group.addTask {
                        try await client.lookup(
                            identity: identity,
                            game: card.game,
                            companies: [],
                            grades: [],
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
                        return .gradeNotTracked(GradedMarketCoverage(
                            status: .gradeNotListed,
                            variants: variants,
                            targetCompany: slab.company,
                            targetGrade: slab.grade
                        ))
                    }
                    return .bound(exact)
                case .cardFoundWithoutGradedVariants:
                    return .noGradedListings(GradedMarketCoverage(status: .noGradedListings))
                case .noProductMatch:
                    return .cardNotTracked(GradedMarketCoverage(status: .cardNotTracked))
                }
            } catch is CancellationError {
                return .unavailable
            } catch is TimeoutError {
                guard attempt < timeoutRetryCount, !Task.isCancelled else { return .unavailable }
                // A retry gets a fresh place in the shared pacer. The caller
                // runs this resolver in a post-save task, so waiting here does
                // not delay scanner recognition or collection persistence.
                continue
            } catch let error as URLError where error.code == .timedOut {
                guard attempt < timeoutRetryCount, !Task.isCancelled else { return .unavailable }
                continue
            } catch {
                return .unavailable
            }
        }
        return .unavailable
    }

    /// Match the stable grader/grade/qualifier axis first, then require the
    /// vendor label to agree when it publishes one. A unique unlabeled vendor
    /// variant remains usable; a conflicting Black Label never does.
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
        if candidates.count == 1,
           isBlackLabel(candidates[0].grade.label),
           !isBlackLabel(slab.grade.label) {
            return nil
        }

        let scannedLabel = normalizedLabel(slab.grade.label)
        let exactLabelMatches = candidates.filter {
            normalizedLabel($0.grade.label) == scannedLabel
        }
        if exactLabelMatches.count == 1 { return exactLabelMatches[0] }
        if exactLabelMatches.count > 1 { return nil }

        let unlabeled = candidates.filter { $0.grade.label == nil }
        guard unlabeled.count == 1 else { return nil }
        return unlabeled[0]
    }

    private static func normalizedLabel(_ value: String?) -> String? {
        guard let value else { return nil }
        let tokens = value.uppercased()
            .split { !$0.isLetter && !$0.isNumber && $0 != "+" }
            .map(String.init)
        guard !tokens.isEmpty else { return nil }
        var label = tokens.joined(separator: " ")
        label = label.replacingOccurrences(of: "GEM MT", with: "GEM MINT")
        label = label.replacingOccurrences(of: "NM MINT", with: "NM MT")
        label = label.replacingOccurrences(of: "EX MINT", with: "EX MT")
        label = label.replacingOccurrences(of: "VG EXCELLENT", with: "VG EX")
        label = label.replacingOccurrences(of: "MINT PLUS", with: "MINT+")
        label = label.replacingOccurrences(of: "MINT +", with: "MINT+")
        return label
    }

    private static func isBlackLabel(_ value: String?) -> Bool {
        normalizedLabel(value) == "BLACK LABEL"
    }

    private static func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let number = Double(trimmed), number.isFinite {
            if number == number.rounded(), let integer = Int(exactly: number) {
                return String(integer)
            }
            return String(number)
        }
        return trimmed.uppercased()
    }
}
