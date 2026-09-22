import Foundation
import os

/// The record of every `printing + finish` this app was asked to price and
/// could not price in dollars.
///
/// This exists because the alternative to a euro figure is not silence. When a
/// finish has no USD quote, that is a fact about this app's sources, not about
/// the card, and it is fixable — a different provider, a per-object listing, a
/// vendor variant id the identity layer has not learned yet. A gap nobody can
/// see is a gap nobody closes, so every unpriced finish lands here the moment
/// the user looks at it, and the set of gaps is readable from Settings.
///
/// Deliberately in-memory and bounded. These are diagnostics about the current
/// session's browsing, not user data: persisting them would mean carrying a
/// growing list of provider shortcomings across launches for no added ability
/// to act on them, since the next lookup re-records anything still missing.
final class PriceCoverageGapLog: @unchecked Sendable {
    static let shared = PriceCoverageGapLog()

    /// One unpriced physical object, keyed so that repeatedly rendering the
    /// same card cannot inflate the count.
    struct Gap: Hashable, Identifiable, Sendable {
        let game: CardGame
        let providerID: String
        let setCode: String
        let cardNumber: String
        let variantID: String
        /// The source that answered "nothing for this variant", or `nil` when
        /// no source could be consulted at all. The two are different problems:
        /// the first is a coverage gap at a provider we already use, the second
        /// means the card carries no pricing object whatsoever.
        let consultedSource: PriceSource?
        let firstSeenAt: Date
        /// Mutated only under the log's lock when the same gap is seen again.
        fileprivate(set) var lastSeenAt: Date
        fileprivate(set) var observationCount: Int

        var id: String { "\(game.rawValue):\(providerID):\(variantID)" }

        /// A one-line description for the diagnostics list.
        var summary: String {
            let source = consultedSource?.label ?? "no pricing source"
            return "\(setCode) \(cardNumber) · \(variantID) — \(source)"
        }

        static func == (lhs: Gap, rhs: Gap) -> Bool { lhs.id == rhs.id }
        func hash(into hasher: inout Hasher) { hasher.combine(id) }
    }

    /// Enough to characterize what is missing across a browsing session without
    /// letting a pathological set pin an unbounded amount of memory.
    private static let capacity = 500

    private static let logger = Logger(
        subsystem: "com.scan-stash.TradingCardScanner",
        category: "priceCoverage"
    )

    private let lock = NSLock()
    private var gaps: [String: Gap] = [:]
    /// Insertion order, so eviction drops the oldest gap rather than an
    /// arbitrary dictionary element.
    private var order: [String] = []

    func record(
        game: CardGame,
        providerID: String,
        setCode: String,
        cardNumber: String,
        variantID: String,
        consultedSource: PriceSource?,
        at now: Date = .now
    ) {
        let gap = Gap(
            game: game,
            providerID: providerID,
            setCode: setCode,
            cardNumber: cardNumber,
            variantID: variantID,
            consultedSource: consultedSource,
            firstSeenAt: now,
            lastSeenAt: now,
            observationCount: 1
        )
        lock.lock()
        defer { lock.unlock() }
        if var existing = gaps[gap.id] {
            existing.lastSeenAt = now
            existing.observationCount += 1
            gaps[gap.id] = existing
            return
        }
        gaps[gap.id] = gap
        order.append(gap.id)
        // Log only the first sighting. A repeat is the same defect seen again,
        // and emitting it on every render would bury the distinct ones.
        Self.logger.info(
            """
            No USD quote: game=\(game.rawValue, privacy: .public) \
            set=\(setCode, privacy: .public) card=\(cardNumber, privacy: .public) \
            variant=\(variantID, privacy: .public) \
            source=\(consultedSource?.rawValue ?? "none", privacy: .public)
            """
        )
        while order.count > Self.capacity {
            gaps.removeValue(forKey: order.removeFirst())
        }
    }

    /// Most recently seen first, which is the order someone investigating a
    /// card they just looked at wants.
    func currentGaps() -> [Gap] {
        lock.lock()
        defer { lock.unlock() }
        return order.reversed().compactMap { gaps[$0] }
    }

    func gapCount() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return order.count
    }

    func reset() {
        lock.lock()
        defer { lock.unlock() }
        gaps.removeAll()
        order.removeAll()
    }
}
