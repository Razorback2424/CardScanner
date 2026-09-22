import Foundation

protocol ScryfallDatasetStampProviding: Sendable {
    func datasetUpdatedAt() async -> Date?
}
/// Small device-local cache for Scryfall's approximate bulk-dataset update date.
/// It is deliberately separate from the current-card response cache and is
/// never used as the current price source.
actor ScryfallDatasetStampCache: ScryfallDatasetStampProviding {
    static let shared = ScryfallDatasetStampCache()

    private static let maxAge: TimeInterval = 24 * 60 * 60
    private let url: URL
    private var loaded = false
    private var fetchedAt: Date?
    private var updatedAt: Date?

    init(root: URL? = nil) {
        let directory = root ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent("ScanStash", isDirectory: true)
        self.url = directory.appendingPathComponent("ScryfallDatasetStampCache.json")
    }

    func datasetUpdatedAt() async -> Date? {
        loadPersistedIfNeeded()
        if let fetchedAt,
           Date.now.timeIntervalSince(fetchedAt) >= 0,
           Date.now.timeIntervalSince(fetchedAt) < Self.maxAge {
            return updatedAt
        }

        guard let requestURL = URL(string: "https://api.scryfall.com/bulk-data") else {
            return updatedAt
        }
        var request = URLRequest(url: requestURL)
        request.timeoutInterval = 8
        request.setValue("TradingCardScanner/0.1 (iOS)", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode) else {
                return updatedAt
            }
            let decoded = try JSONDecoder().decode(ScryfallBulkDataResponse.self, from: data)
            let candidate = decoded.data.first {
                $0.type == "default_cards"
            } ?? decoded.data.first {
                $0.type == "unique_cards"
            }
            fetchedAt = .now
            updatedAt = candidate?.updatedAt.flatMap(FlexibleDate.parse)
            storePersisted()
            return updatedAt
        } catch {
            return updatedAt
        }
    }

    private func loadPersistedIfNeeded() {
        guard !loaded else { return }
        loaded = true
        guard let data = try? Data(contentsOf: url),
              let envelope = try? JSONDecoder().decode(
                ScryfallDatasetStampEnvelope.self,
                from: data
              ) else { return }
        fetchedAt = envelope.fetchedAt
        updatedAt = envelope.updatedAt
    }

    private func storePersisted() {
        let envelope = ScryfallDatasetStampEnvelope(
            fetchedAt: fetchedAt ?? .now,
            updatedAt: updatedAt
        )
        guard let data = try? JSONEncoder().encode(envelope) else { return }
        let directory = url.deletingLastPathComponent()
        guard (try? FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )) != nil else { return }
        try? data.write(to: url, options: .atomic)
    }
}

private struct ScryfallBulkDataResponse: Decodable, Sendable {
    let data: [ScryfallBulkDataEntry]
}

private struct ScryfallBulkDataEntry: Decodable, Sendable {
    let type: String
    let updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case type
        case updatedAt = "updated_at"
    }
}

private struct ScryfallDatasetStampEnvelope: Codable, Sendable {
    let fetchedAt: Date
    let updatedAt: Date?
}
