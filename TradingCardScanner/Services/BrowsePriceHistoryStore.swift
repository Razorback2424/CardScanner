import Foundation

enum BrowsePriceHistoryStoreError: Error, LocalizedError, Sendable {
    case invalidSetIdentity
    case encodeFailed
    case writeFailed

    var errorDescription: String? {
        switch self {
        case .invalidSetIdentity: return "Browse history has no valid set identity."
        case .encodeFailed: return "Browse history could not be encoded."
        case .writeFailed: return "Browse history could not be saved."
        }
    }
}

/// Device-local Browse history. This actor intentionally has no SwiftData,
/// CloudKit, portfolio, or owned-card pricing dependencies.
actor BrowsePriceHistoryStore {
    static let shared = BrowsePriceHistoryStore()

    private static let retentionDays = 90
    private let root: URL
    private let now: @Sendable () -> Date
    private var corruptFileRecoveryCount = 0
    private var skippedTimestampWrites = 0
    private var deduplicatedObservationCount = 0
    private var unmappedVariantCount = 0
    private var pokemonShadowCoverageSummary = "No shadow comparison is active."

    init(
        root: URL? = nil,
        now: @escaping @Sendable () -> Date = { .now }
    ) {
        self.root = root ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent("ScanStash", isDirectory: true)
            .appendingPathComponent("BrowsePriceHistory", isDirectory: true)
            .appendingPathComponent("v1", isDirectory: true)
        self.now = now
        try? FileManager.default.createDirectory(at: self.root, withIntermediateDirectories: true)
        Self.excludeFromBackup(self.root)
    }

    /// Record a batch from one explicitly opened set. Grouping by set keeps
    /// this API safe for callers that collect several page results together.
    func record(_ quotes: [BrowsePriceQuote], game: CardGame) throws {
        let grouped = Dictionary(grouping: quotes, by: \.setID)
        for (setID, setQuotes) in grouped {
            try record(setQuotes, game: game, setID: setID)
        }
    }

    func record(_ quote: BrowsePriceQuote, game: CardGame) throws {
        try record([quote], game: game, setID: quote.setID)
    }

    func series(
        game: CardGame,
        setID: String,
        printingID: String? = nil
    ) -> [BrowsePricePersistedSeries] {
        guard let file = loadFile(game: game, setID: setID) else { return [] }
        guard let printingID else { return file.series }
        return file.series.filter { $0.key.printingID == printingID }
    }

    func deleteHistory(game: CardGame, setID: String) {
        try? FileManager.default.removeItem(at: fileURL(game: game, setID: setID))
    }

    /// Exposed for deterministic persistence tests and diagnostics tooling.
    func storageURL(game: CardGame, setID: String) -> URL {
        fileURL(game: game, setID: setID)
    }

    func recordSkippedTimestamp() {
        skippedTimestampWrites += 1
    }

    func recordUnmappedVariant() {
        unmappedVariantCount += 1
    }

    func setPokemonShadowCoverageSummary(_ summary: String) {
        pokemonShadowCoverageSummary = summary
    }

    func diagnostics() -> BrowsePriceHistoryDiagnostics {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        var setCount = 0
        var totalBytes = 0
        var days: [BrowsePriceDay] = []

        for url in files where url.pathExtension == "json" {
            let values = try? url.resourceValues(forKeys: [.fileSizeKey])
            totalBytes += values?.fileSize ?? 0
            guard let file = decodeFile(at: url), !file.series.isEmpty else { continue }
            setCount += 1
            days.append(contentsOf: file.series.flatMap { $0.points.map(\.day) })
        }

        return BrowsePriceHistoryDiagnostics(
            setCount: setCount,
            totalBytes: totalBytes,
            oldestProviderDay: days.min(),
            newestProviderDay: days.max(),
            corruptFileRecoveryCount: corruptFileRecoveryCount,
            skippedTimestampWrites: skippedTimestampWrites,
            deduplicatedObservationCount: deduplicatedObservationCount,
            pokemonShadowCoverageSummary: pokemonShadowCoverageSummary,
            unmappedVariantCount: unmappedVariantCount
        )
    }

    private func record(
        _ quotes: [BrowsePriceQuote],
        game: CardGame,
        setID: String
    ) throws {
        let cleanSetID = setID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanSetID.isEmpty else { throw BrowsePriceHistoryStoreError.invalidSetIdentity }

        var file = loadFile(game: game, setID: cleanSetID)
            ?? BrowsePriceHistorySetFile(game: game, setID: cleanSetID)
        for quote in quotes {
            guard quote.setID.trimmingCharacters(in: .whitespacesAndNewlines) == cleanSetID,
                  let key = quote.seriesKey else {
                unmappedVariantCount += 1
                continue
            }
            let point = quote.historyPoint
            if let seriesIndex = file.series.firstIndex(where: { $0.key == key }) {
                var series = file.series[seriesIndex]
                if let pointIndex = series.points.firstIndex(where: { $0.day == point.day }) {
                    let incumbent = series.points[pointIndex]
                    if incumbent.providerUpdatedAt == point.providerUpdatedAt,
                       incumbent.amountUSD == point.amountUSD,
                       incumbent.transportProvider == point.transportProvider {
                        deduplicatedObservationCount += 1
                    } else if point.providerUpdatedAt > incumbent.providerUpdatedAt {
                        series.points[pointIndex] = point
                    }
                } else {
                    series.points.append(point)
                }
                series.points.sort { $0.day < $1.day }
                file.series[seriesIndex] = series
            } else {
                file.series.append(
                    BrowsePricePersistedSeries(key: key, points: [point])
                )
            }
        }

        let newestDay = file.series
            .flatMap { $0.points.map(\.day) }
            .max()
        if let newestDay {
            let cutoff = newestDay.adding(days: -(Self.retentionDays - 1))
            file.series = file.series.compactMap { series in
                let points = series.points.filter { $0.day >= cutoff }
                guard !points.isEmpty else { return nil }
                return BrowsePricePersistedSeries(key: series.key, points: points)
            }
        }
        file.lastAccessedAt = now()
        try write(file, to: fileURL(game: game, setID: cleanSetID))
    }

    private func loadFile(game: CardGame, setID: String) -> BrowsePriceHistorySetFile? {
        let url = fileURL(game: game, setID: setID)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        guard let file = decodeFile(at: url),
              file.schemaVersion == BrowsePriceHistorySetFile.currentSchemaVersion,
              file.game == game,
              file.setID == setID else {
            quarantineCorruptFile(at: url)
            return nil
        }
        return file
    }

    private func decodeFile(at url: URL) -> BrowsePriceHistorySetFile? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(BrowsePriceHistorySetFile.self, from: data)
    }

    private func quarantineCorruptFile(at url: URL) {
        corruptFileRecoveryCount += 1
        let quarantine = url.deletingPathExtension()
            .appendingPathExtension("corrupt-\(UUID().uuidString).json")
        try? FileManager.default.moveItem(at: url, to: quarantine)
    }

    private func write(_ value: BrowsePriceHistorySetFile, to url: URL) throws {
        let data: Data
        do {
            data = try JSONEncoder().encode(value)
        } catch {
            throw BrowsePriceHistoryStoreError.encodeFailed
        }
        let directory = url.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            Self.excludeFromBackup(directory)
            let temporary = directory.appendingPathComponent(
                ".\(url.lastPathComponent).\(UUID().uuidString).tmp"
            )
            FileManager.default.createFile(atPath: temporary.path, contents: nil)
            let handle = try FileHandle(forWritingTo: temporary)
            try handle.write(contentsOf: data)
            try handle.synchronize()
            try handle.close()
            if FileManager.default.fileExists(atPath: url.path) {
                _ = try FileManager.default.replaceItemAt(url, withItemAt: temporary)
            } else {
                try FileManager.default.moveItem(at: temporary, to: url)
            }
        } catch {
            throw BrowsePriceHistoryStoreError.writeFailed
        }
    }

    private func fileURL(game: CardGame, setID: String) -> URL {
        root.appendingPathComponent(filename(for: "\(game.rawValue)|\(setID)"))
    }

    private func filename(for value: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(hash, radix: 16) + ".json"
    }

    private static func excludeFromBackup(_ url: URL) {
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var target = url
        try? target.setResourceValues(values)
    }
}
