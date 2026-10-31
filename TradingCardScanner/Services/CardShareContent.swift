import Foundation

// The facts a shared card image may state. Everything here is built from data
// the app already holds for the card or product; nothing is estimated, and a
// fact the app does not have is left off rather than filled in.

/// What the recipient needs to identify the exact item.
struct CardShareIdentity: Equatable, Sendable {
    enum Badge: Equatable, Sendable {
        /// A printed finish worth calling out, such as Holo or Reverse.
        case finish(String)
        /// A grader and grade, such as PSA 10.
        case grade(String)

        var text: String {
            switch self {
            case let .finish(text), let .grade(text): return text
            }
        }
    }

    let name: String
    let setCode: String?
    let setName: String?
    let number: CardShareNumber?
    let badge: Badge?

    init(name: String, setCode: String?, setName: String?, number: CardShareNumber?, badge: Badge?) {
        self.name = name
        self.setCode = setCode?.trimmingCharacters(in: .whitespaces).nilIfEmpty
        self.setName = setName?.trimmingCharacters(in: .whitespaces).nilIfEmpty
        self.number = number
        self.badge = badge
    }

    /// The finish badge is only worth space when it says something: the
    /// standard printing is what a recipient assumes without being told.
    static func finishBadge(for variant: PhysicalVariant?) -> Badge? {
        guard let variant,
              variant.id != PhysicalVariant.normal.id,
              variant.id != PhysicalVariant.nonfoil.id,
              let label = variant.label.trimmingCharacters(in: .whitespaces).nilIfEmpty else { return nil }
        return .finish(label)
    }
}

/// A collector number split so the share image can emphasise the card's own
/// number and quiet the set total: `087` and `/165`.
struct CardShareNumber: Equatable, Sendable {
    let primary: String
    let total: String?

    init?(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        if let slash = trimmed.firstIndex(of: "/") {
            let head = trimmed[..<slash].trimmingCharacters(in: .whitespaces)
            let tail = trimmed[trimmed.index(after: slash)...].trimmingCharacters(in: .whitespaces)
            guard !head.isEmpty else { return nil }
            primary = head
            total = tail.isEmpty ? nil : "/" + tail
        } else {
            primary = trimmed
            total = nil
        }
    }

    var text: String { primary + (total ?? "") }
}

/// One market price as the share image states it: the amount, what kind of
/// price it is, and where and when it came from.
struct CardSharePrice: Equatable, Sendable {
    let amount: Double
    let currencyCode: String
    /// `Near Mint market`, `PSA 10 market`, `Market price`.
    let basis: String
    let source: String?
    let asOf: Date?

    init(amount: Double, currencyCode: String, basis: String, source: String?, asOf: Date?) {
        self.amount = amount
        self.currencyCode = currencyCode
        self.basis = basis
        self.source = source
        self.asOf = asOf
    }

    /// Nil when there is no usable amount: a share image never shows a price
    /// the detail screen would not.
    init?(display: PriceDisplay, basis: String) {
        guard let amount = display.amount, amount.isFinite, amount > 0 else { return nil }
        self.init(
            amount: amount,
            currencyCode: display.currencyCode,
            basis: basis,
            source: display.source.map(Self.shortSourceLabel),
            asOf: display.effectiveAsOf
        )
    }

    /// The app does not record the condition of a raw copy, so a raw price is
    /// labelled with the condition the provider prices, never the copy's own.
    static func basis(itemKind: CollectionItemKind, gradeLabel: String?, source: PriceSource?) -> String {
        switch itemKind {
        case .gradedCard:
            return gradeLabel.map { "\($0) market" } ?? "Graded market"
        case .sealedProduct:
            return "Market price"
        case .rawCard:
            switch source {
            case .tcgplayer, .tcgCSV, .justTCG: return "Near Mint market"
            default: return "Market price"
            }
        }
    }

    static func shortSourceLabel(_ source: PriceSource) -> String {
        source == .tcgCSV ? PriceSource.tcgplayer.label : source.label
    }

    func formattedAmount(locale: Locale = .current) -> String {
        amount.formatted(.currency(code: currencyCode).precision(.fractionLength(2)).locale(locale))
    }

    /// `TCGplayer · Oct 31`. Nil when neither fact is known.
    func sourceLine(now: Date = .now, calendar: Calendar = .current, locale: Locale = .current) -> String? {
        let date = asOf.map { CardShareFormat.shortDate($0, now: now, calendar: calendar, locale: locale) }
        let parts = [source, date].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

/// Which way a market price has moved over the share window, stated only when
/// there is enough history to say it honestly.
struct CardShareTrend: Equatable, Sendable {
    enum Direction: Equatable, Sendable {
        case up
        case down
        case flat
    }

    enum Position: Equatable, Sendable {
        case atHigh
        case nearHigh
        case nearLow
        case atLow
    }

    struct Sample: Equatable, Sendable {
        let date: Date
        let amount: Double
    }

    /// Long enough to show recent momentum, short enough not to bury it.
    static let window: TimeInterval = 90 * 86_400
    /// Fewer observations than this, or a shorter span, and the chart and the
    /// trend sentence are left off rather than guessed.
    static let minimumSamples = 5
    static let minimumSpan: TimeInterval = 14 * 86_400
    /// History that starts within this of the window's start still counts as
    /// covering the whole window.
    static let coverageTolerance: TimeInterval = 7 * 86_400

    let samples: [Sample]
    let direction: Direction
    /// Absolute change, rounded to a whole percent.
    let percentChange: Int
    let low: Double
    let high: Double
    let position: Position?
    let coversFullWindow: Bool

    var start: Date { samples.first?.date ?? .distantPast }
    var end: Date { samples.last?.date ?? .distantPast }

    static func make(points: [JustTCGHistoryPoint], now: Date = .now) -> CardShareTrend? {
        let windowStart = now.addingTimeInterval(-window)
        let samples = points
            .filter { $0.p.isFinite && $0.p > 0 && $0.t.isFinite }
            .map { Sample(date: Date(timeIntervalSince1970: $0.t), amount: $0.p) }
            .filter { $0.date >= windowStart && $0.date <= now.addingTimeInterval(86_400) }
            .sorted { $0.date < $1.date }
        guard samples.count >= minimumSamples,
              let first = samples.first,
              let last = samples.last,
              last.date.timeIntervalSince(first.date) >= minimumSpan else { return nil }

        let change = (last.amount - first.amount) / first.amount
        let percent = Int((abs(change) * 100).rounded())
        let direction: Direction = percent == 0 ? .flat : (change > 0 ? .up : .down)
        let amounts = samples.map(\.amount)
        let low = amounts.min() ?? last.amount
        let high = amounts.max() ?? last.amount

        let position: Position?
        let spread = high - low
        if spread <= max(0.01, high * 0.005) {
            position = nil
        } else if last.amount >= high {
            position = .atHigh
        } else if last.amount <= low {
            position = .atLow
        } else {
            let ratio = (last.amount - low) / spread
            position = ratio >= 0.9 ? .nearHigh : (ratio <= 0.1 ? .nearLow : nil)
        }

        return CardShareTrend(
            samples: samples,
            direction: direction,
            percentChange: percent,
            low: low,
            high: high,
            position: position,
            coversFullWindow: first.date.timeIntervalSince(windowStart) <= coverageTolerance
        )
    }

    /// `Up 12% in 3 months`, `Down 4% since Sep 12`, `Flat over 3 months`.
    func headline(now: Date = .now, calendar: Calendar = .current, locale: Locale = .current) -> String {
        let since = CardShareFormat.shortDate(start, now: now, calendar: calendar, locale: locale)
        switch direction {
        case .flat:
            return coversFullWindow ? "Flat over 3 months" : "Flat since \(since)"
        case .up, .down:
            let verb = direction == .up ? "Up" : "Down"
            return coversFullWindow
                ? "\(verb) \(percentChange)% in 3 months"
                : "\(verb) \(percentChange)% since \(since)"
        }
    }

    /// `At its 3-month high`, `Near its low since Sep 12`. Nil when today's
    /// price sits mid-range, where saying anything would be noise.
    func positionText(now: Date = .now, calendar: Calendar = .current, locale: Locale = .current) -> String? {
        guard let position else { return nil }
        let since = CardShareFormat.shortDate(start, now: now, calendar: calendar, locale: locale)
        let words: (qualifier: String, extreme: String) = switch position {
        case .atHigh: ("At", "high")
        case .nearHigh: ("Near", "high")
        case .nearLow: ("Near", "low")
        case .atLow: ("At", "low")
        }
        let qualifier = words.qualifier
        let extreme = words.extreme
        return coversFullWindow
            ? "\(qualifier) its 3-month \(extreme)"
            : "\(qualifier) its \(extreme) since \(since)"
    }
}

/// An asking price the user typed, compared with the market price.
struct CardShareAsk: Equatable, Sendable {
    enum Comparison: Equatable, Sendable {
        case under(Int)
        case over(Int)
        case atMarket
    }

    let amount: Double
    let comparison: Comparison

    init?(text: String, market: Double, locale: Locale = .current) {
        guard let amount = Self.parse(text, locale: locale), market > 0 else { return nil }
        self.amount = amount
        let percent = Int((abs(market - amount) / market * 100).rounded())
        if percent == 0 {
            comparison = .atMarket
        } else {
            comparison = amount < market ? .under(percent) : .over(percent)
        }
    }

    /// Accepts what a decimal pad produces in the user's locale, plus pasted
    /// currency symbols and grouping separators.
    static func parse(_ text: String, locale: Locale = .current) -> Double? {
        let decimal = locale.decimalSeparator ?? "."
        let grouping = locale.groupingSeparator ?? ","
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if grouping != decimal {
            cleaned = cleaned.replacingOccurrences(of: grouping, with: "")
        }
        cleaned = cleaned.replacingOccurrences(of: decimal, with: ".")
        cleaned = String(cleaned.filter { $0.isASCII && ($0.isNumber || $0 == ".") })
        guard !cleaned.isEmpty, let value = Double(cleaned), value.isFinite,
              value > 0, value < 10_000_000 else { return nil }
        return value
    }

    var comparisonText: String {
        switch comparison {
        case let .under(percent): return "\(percent)% under market"
        case let .over(percent): return "\(percent)% over market"
        case .atMarket: return "At market"
        }
    }
}

/// The plain text sent alongside the image, so the recipient can copy the
/// card's name into a search and still read the facts where images load slowly.
enum CardShareSummary {
    static func text(
        identity: CardShareIdentity,
        price: CardSharePrice?,
        trend: CardShareTrend? = nil,
        ask: CardShareAsk? = nil,
        now: Date = .now,
        calendar: Calendar = .current,
        locale: Locale = .current
    ) -> String {
        let printed = [identity.setCode, identity.number?.text]
            .compactMap { $0 }
            .joined(separator: " ")
        let designation = [identity.setName, printed.nilIfEmpty]
            .compactMap { $0 }
            .joined(separator: " ")
        let firstLine = [identity.name, designation.nilIfEmpty, identity.badge?.text]
            .compactMap { $0 }
            .joined(separator: " · ")

        var lines = [firstLine]
        if let price {
            var line = "\(price.formattedAmount(locale: locale)) \(price.basis)"
            if let source = price.sourceLine(now: now, calendar: calendar, locale: locale) {
                line += " (\(source.replacingOccurrences(of: " · ", with: ", ")))"
            }
            lines.append(line)
        }
        if let trend {
            lines.append(trend.headline(now: now, calendar: calendar, locale: locale))
        }
        if let ask, let price {
            let askAmount = CardSharePrice(
                amount: ask.amount,
                currencyCode: price.currencyCode,
                basis: "",
                source: nil,
                asOf: nil
            ).formattedAmount(locale: locale)
            lines.append("Asking \(askAmount) · \(ask.comparisonText)")
        }
        return lines.joined(separator: "\n")
    }
}

enum CardShareFormat {
    /// `Oct 31`, or `Oct 31, 2025` when the date is not in the current year.
    static func shortDate(_ date: Date, now: Date = .now, calendar: Calendar = .current, locale: Locale = .current) -> String {
        var style = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
            .month(.abbreviated)
            .day()
        if calendar.component(.year, from: date) != calendar.component(.year, from: now) {
            style = style.year()
        }
        return date.formatted(style)
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
