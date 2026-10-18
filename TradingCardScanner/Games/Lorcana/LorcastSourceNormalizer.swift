import CryptoKit
import Foundation

/// Receipt for retained public JSON. The digest associates the bytes with this
/// observation; it is not a signature or permission to publish a catalog.
struct LorcastResponseReceipt: Codable, Equatable, Sendable {
    let requestedURL: URL
    let responseURL: URL
    let receivedAt: Date
    let statusCode: Int
    let contentType: String
    let paginationHeaders: [String: String]
    let bodySHA256: String
}

struct LorcastSetReference: Decodable, Equatable, Sendable {
    let id: String
    let code: String
    let name: String
}

/// Provider observations intentionally have no printed denominator/marker,
/// physical UUID, supported finishes or market authority. Those need review.
struct LorcastCardObservation: Decodable, Equatable, Sendable {
    let id: String
    let name: String
    let version: String?
    let layout: String
    let releasedAt: String
    let collectorNumber: String
    let language: String
    let rarity: String
    let set: LorcastSetReference

    var sourceAlias: LorcanaSourceAlias { .init(provider: "lorcast", id: id) }

    private enum CodingKeys: String, CodingKey {
        case id, name, version, layout, rarity, set
        case releasedAt = "released_at"
        case collectorNumber = "collector_number"
        case language = "lang"
    }
}

struct LorcastSetObservation: Decodable, Equatable, Sendable {
    let id: String
    let code: String
    let name: String
    let releasedAt: String
    let prereleasedAt: String?

    private enum CodingKeys: String, CodingKey {
        case id, code, name
        case releasedAt = "released_at"
        case prereleasedAt = "prereleased_at"
    }
}

struct LorcastSourceBatch<Observation: Sendable>: Sendable {
    let receipt: LorcastResponseReceipt
    let observations: [Observation]
}

/// Offline ingestion only. Neither an all-print search nor a set directory
/// establishes a complete physical universe, footer mapping or finish policy.
enum LorcastSourceNormalizer {
    enum ValidationError: Error, Equatable {
        case invalidRequest
        case invalidReceipt
        case responseTooLarge
        case unsupportedEnvelope
        case tooManyResults
        case invalidObservation
        case duplicateProviderID
        case conflictingSet
    }

    static let maximumResponseBytes = 2 * 1_024 * 1_024
    static let maximumCardResults = 5_000
    static let maximumSetResults = 512
    static let setsURL = URL(string: "https://api.lorcast.com/v0/sets")!

    static func searchURL(query: String) throws -> URL {
        guard validText(query, limit: 512) else { throw ValidationError.invalidRequest }
        var components = URLComponents(string: "https://api.lorcast.com/v0/cards/search")!
        components.queryItems = [.init(name: "q", value: query), .init(name: "unique", value: "prints")]
        guard let url = components.url else { throw ValidationError.invalidRequest }
        return url
    }

    static func cards(data: Data, receipt: LorcastResponseReceipt) throws -> LorcastSourceBatch<LorcastCardObservation> {
        try validate(data, receipt: receipt, cards: true)
        let rows = try JSONDecoder().decode(ResultEnvelope<LorcastCardObservation>.self, from: data).results
        guard rows.count <= maximumCardResults else { throw ValidationError.tooManyResults }
        var ids: Set<String> = []
        var setsByID: [String: LorcastSetReference] = [:]
        var setIDsByCode: [String: String] = [:]
        for row in rows {
            guard validText(row.id, limit: 256), validText(row.name),
                  row.version == nil || validText(row.version!, allowEmpty: true),
                  validText(row.layout, limit: 64), validDate(row.releasedAt),
                  validText(row.collectorNumber, limit: 64), validText(row.language, limit: 32),
                  validText(row.rarity, limit: 64), validSet(row.set) else {
                throw ValidationError.invalidObservation
            }
            guard ids.insert(row.id).inserted else { throw ValidationError.duplicateProviderID }
            if let prior = setsByID[row.set.id], prior != row.set { throw ValidationError.conflictingSet }
            if let priorID = setIDsByCode[row.set.code], priorID != row.set.id { throw ValidationError.conflictingSet }
            setsByID[row.set.id] = row.set
            setIDsByCode[row.set.code] = row.set.id
        }
        return .init(receipt: receipt, observations: rows.sorted { $0.id < $1.id })
    }

    static func sets(data: Data, receipt: LorcastResponseReceipt) throws -> LorcastSourceBatch<LorcastSetObservation> {
        try validate(data, receipt: receipt, cards: false)
        let rows = try JSONDecoder().decode(ResultEnvelope<LorcastSetObservation>.self, from: data).results
        guard rows.count <= maximumSetResults else { throw ValidationError.tooManyResults }
        var ids: Set<String> = []
        var codes: Set<String> = []
        for row in rows {
            guard validSet(.init(id: row.id, code: row.code, name: row.name)), validDate(row.releasedAt),
                  row.prereleasedAt == nil || validDate(row.prereleasedAt!) else {
                throw ValidationError.invalidObservation
            }
            guard ids.insert(row.id).inserted else { throw ValidationError.duplicateProviderID }
            guard codes.insert(row.code).inserted else { throw ValidationError.conflictingSet }
        }
        return .init(receipt: receipt, observations: rows.sorted { $0.id < $1.id })
    }

    static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func validate(_ data: Data, receipt: LorcastResponseReceipt, cards: Bool) throws {
        guard data.count <= maximumResponseBytes else { throw ValidationError.responseTooLarge }
        guard let components = URLComponents(url: receipt.requestedURL, resolvingAgainstBaseURL: false),
              components.scheme == "https", components.host == "api.lorcast.com",
              components.port == nil, components.user == nil, components.password == nil, components.fragment == nil,
              components.path == (cards ? "/v0/cards/search" : "/v0/sets") else {
            throw ValidationError.invalidRequest
        }
        if cards {
            let items = components.queryItems ?? []
            guard items.count == 2, items.filter({ $0.name == "unique" && $0.value == "prints" }).count == 1,
                  items.filter({ $0.name == "q" && validText($0.value ?? "", limit: 512) }).count == 1 else {
                throw ValidationError.invalidRequest
            }
        } else if components.percentEncodedQuery != nil {
            throw ValidationError.invalidRequest
        }
        guard receipt.responseURL == receipt.requestedURL, receipt.statusCode == 200,
              receipt.receivedAt.timeIntervalSince1970.isFinite, receipt.receivedAt.timeIntervalSince1970 > 0,
              receipt.contentType.split(separator: ";", maxSplits: 1).first?
                .trimmingCharacters(in: .whitespaces).lowercased() == "application/json",
              receipt.bodySHA256 == digest(data) else { throw ValidationError.invalidReceipt }
        guard receipt.paginationHeaders.isEmpty else { throw ValidationError.unsupportedEnvelope }
    }

    private static func validSet(_ set: LorcastSetReference) -> Bool {
        validText(set.id, limit: 256) && validText(set.code, limit: 64) && validText(set.name)
    }

    private static func validText(_ value: String, limit: Int = 512, allowEmpty: Bool = false) -> Bool {
        (allowEmpty || !value.isEmpty) && value.count <= limit
            && value == value.trimmingCharacters(in: .whitespacesAndNewlines)
            && value.rangeOfCharacter(from: .controlCharacters) == nil
    }

    private static func validDate(_ value: String) -> Bool {
        guard LorcanaPrintedIdentity.matches(value, "[0-9]{4}-[0-9]{2}-[0-9]{2}") else { return false }
        let parts = value.split(separator: "-").compactMap { Int($0) }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let components = DateComponents(year: parts[0], month: parts[1], day: parts[2])
        guard parts[0] > 0, let date = calendar.date(from: components) else { return false }
        let actual = calendar.dateComponents([.year, .month, .day], from: date)
        return actual.year == parts[0] && actual.month == parts[1] && actual.day == parts[2]
    }

    private struct EnvelopeKey: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }

    private struct ResultEnvelope<Row: Decodable>: Decodable {
        let results: [Row]
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: EnvelopeKey.self)
            // The reviewed v0 contract has only `results`. Fail closed on any
            // new continuation, total, warning or envelope semantics, even null.
            guard Set(container.allKeys.map(\.stringValue)) == ["results"] else {
                throw ValidationError.unsupportedEnvelope
            }
            results = try container.decode([Row].self, forKey: EnvelopeKey(stringValue: "results")!)
        }
    }
}
