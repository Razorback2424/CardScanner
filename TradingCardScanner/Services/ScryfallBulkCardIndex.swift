import Foundation
import zlib

/// Scryfall's description of one daily bulk file
/// (https://scryfall.com/docs/api/bulk-data).
struct ScryfallBulkDataMetadata: Decodable, Sendable {
    let type: String
    let updatedAt: Date
    let downloadURL: URL
    let compressedSize: Int

    enum CodingKeys: String, CodingKey {
        case type
        case updatedAt = "updated_at"
        case downloadURL = "jsonl_download_uri"
        case compressedSize = "compressed_size"
    }

    init(type: String, updatedAt: Date, downloadURL: URL, compressedSize: Int) {
        self.type = type
        self.updatedAt = updatedAt
        self.downloadURL = downloadURL
        self.compressedSize = compressedSize
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        type = try values.decode(String.self, forKey: .type)
        downloadURL = try values.decode(URL.self, forKey: .downloadURL)
        compressedSize = try values.decode(Int.self, forKey: .compressedSize)
        let raw = try values.decode(String.self, forKey: .updatedAt)
        guard let date = Self.parseTimestamp(raw) else {
            throw DecodingError.dataCorruptedError(forKey: .updatedAt, in: values,
                                                   debugDescription: "Unrecognized bulk timestamp")
        }
        updatedAt = date
    }

    static func parseTimestamp(_ raw: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: raw) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: raw)
    }

    /// Bulk files are served from Scryfall's unmetered file origin. Refuse
    /// anything else so a changed response cannot redirect a 77 MB download.
    func validated(expectedType: String) throws -> Self {
        guard type == expectedType else {
            throw ScryfallBulkDataError.invalidMetadata("expected \(expectedType), received \(type)")
        }
        guard downloadURL.scheme == "https",
              let host = downloadURL.host?.lowercased(),
              host == "scryfall.io" || host.hasSuffix(".scryfall.io") else {
            throw ScryfallBulkDataError.invalidMetadata("download is not hosted on scryfall.io")
        }
        guard compressedSize > 0, compressedSize <= Self.maximumCompressedSize else {
            throw ScryfallBulkDataError.invalidMetadata("implausible file size \(compressedSize) bytes")
        }
        return self
    }

    /// Default Cards was 77 MB in November 2026. A generous ceiling catches a
    /// metadata error before it becomes a runaway download.
    static let maximumCompressedSize = 1_024 * 1_024 * 1_024
}

enum ScryfallBulkDataError: LocalizedError, Equatable {
    case invalidMetadata(String)
    case incompleteDownload(expected: Int, received: Int)
    case corrupt(String)

    var errorDescription: String? {
        switch self {
        case let .invalidMetadata(reason): "Scryfall bulk data description was rejected (\(reason))."
        case let .incompleteDownload(expected, received):
            "Scryfall bulk data download was incomplete (\(received) of \(expected) bytes)."
        case let .corrupt(reason): "Scryfall bulk data could not be read (\(reason))."
        }
    }
}

/// English, non-digital paper printings from Scryfall's Default Cards bulk
/// file, grouped by set code.
///
/// The decompressed file is several hundred megabytes, so cards are never
/// held in memory together. Building streams the archive once and spools a
/// compact re-encoding of each kept printing to disk; `cards(inSet:)` reads
/// back one set at a time. A built index records a manifest last, so it can
/// be reopened for the same Scryfall `updated_at` without downloading again.
final class ScryfallBulkCardIndex: Sendable {
    struct Slot: Codable, Sendable {
        let offset: UInt64
        let length: Int
    }

    private struct Manifest: Codable {
        static let currentVersion = 1
        let version: Int
        let updatedAt: Date
        let printingCount: Int
        let spoolSize: UInt64
        let slots: [String: [Slot]]
    }

    private static let manifestName = "manifest.json"
    private static let spoolName = "printings.jsonl"

    /// When Scryfall built the file. Prices in it are no newer than this, so it
    /// is the honest observation time for every price the export reads.
    let updatedAt: Date
    let printingCount: Int
    private let spool: URL
    private let directory: URL
    private let slots: [String: [Slot]]
    private let removesDirectoryOnRelease: Bool

    var setCodes: Set<String> { Set(slots.keys) }

    private init(updatedAt: Date, spool: URL, directory: URL, slots: [String: [Slot]], printingCount: Int,
                 removesDirectoryOnRelease: Bool) {
        self.updatedAt = updatedAt
        self.spool = spool
        self.directory = directory
        self.slots = slots
        self.printingCount = printingCount
        self.removesDirectoryOnRelease = removesDirectoryOnRelease
    }

    deinit {
        if removesDirectoryOnRelease { try? FileManager.default.removeItem(at: directory) }
    }

    /// Reopens an index built by `build(..., persistent: true)`. Returns nil
    /// unless its manifest matches `updatedAt` and the spool is intact, so a
    /// build interrupted before its manifest was written is never trusted.
    static func openPersisted(directory: URL, updatedAt: Date) -> ScryfallBulkCardIndex? {
        let spool = directory.appendingPathComponent(spoolName)
        guard let data = try? Data(contentsOf: directory.appendingPathComponent(manifestName)),
              let manifest = try? JSONDecoder().decode(Manifest.self, from: data),
              manifest.version == Manifest.currentVersion,
              manifest.updatedAt == updatedAt, manifest.printingCount > 0,
              let size = (try? FileManager.default.attributesOfItem(atPath: spool.path))?[.size] as? UInt64,
              size == manifest.spoolSize else { return nil }
        return ScryfallBulkCardIndex(updatedAt: manifest.updatedAt, spool: spool, directory: directory,
                                     slots: manifest.slots, printingCount: manifest.printingCount,
                                     removesDirectoryOnRelease: false)
    }

    /// Printings for one Scryfall set code, in collector-number order.
    func cards(inSet code: String) throws -> [ScryfallCard] {
        guard let slots = slots[code.lowercased()], !slots.isEmpty else { return [] }
        let handle = try FileHandle(forReadingFrom: spool)
        defer { try? handle.close() }
        let decoder = JSONDecoder()
        var cards: [ScryfallCard] = []
        cards.reserveCapacity(slots.count)
        for slot in slots {
            try handle.seek(toOffset: slot.offset)
            guard let data = try handle.read(upToCount: slot.length), data.count == slot.length else {
                throw ScryfallBulkDataError.corrupt("spooled record was truncated")
            }
            cards.append(try decoder.decode(ScryfallCard.self, from: data))
        }
        return cards.sorted {
            let order = $0.collectorNumber.localizedStandardCompare($1.collectorNumber)
            return order == .orderedSame ? $0.id < $1.id : order == .orderedAscending
        }
    }

    /// Streams a gzipped JSONL bulk file into a new index under `directory`,
    /// which the index then owns. Any undecodable record, repeated printing,
    /// or truncated archive fails the whole build: a partial index would make
    /// missing printings look like a complete set.
    ///
    /// A `persistent` index writes its manifest last and keeps its directory
    /// when released; otherwise the directory is removed with the index.
    static func build(gzipFile: URL, updatedAt: Date, directory: URL,
                      persistent: Bool = false) throws -> ScryfallBulkCardIndex {
        let manager = FileManager.default
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        let spool = directory.appendingPathComponent(spoolName)
        guard manager.createFile(atPath: spool.path, contents: nil) else {
            throw ScryfallBulkDataError.corrupt("could not create the spool file")
        }
        do {
            let writer = try FileHandle(forWritingTo: spool)
            defer { try? writer.close() }
            let decoder = JSONDecoder()
            let encoder = JSONEncoder()
            var slots: [String: [Slot]] = [:]
            var seen = Set<String>()
            var buffer = Data()
            var offset: UInt64 = 0
            var record = 0
            try GzipLineReader.forEachLine(in: gzipFile) { line in
                record += 1
                if record.isMultiple(of: 2_000) { try Task.checkCancellation() }
                let card: ScryfallCard
                do {
                    card = try decoder.decode(ScryfallCard.self, from: line)
                } catch {
                    throw ScryfallBulkDataError.corrupt("record \(record) is not a card object")
                }
                guard card.language == "en", !card.digital, card.games?.contains("paper") == true else { return }
                guard seen.insert(card.id.lowercased()).inserted else {
                    throw ScryfallBulkDataError.corrupt("printing \(card.id) appears more than once")
                }
                let encoded = try encoder.encode(card)
                slots[card.setCode.lowercased(), default: []].append(Slot(offset: offset, length: encoded.count))
                buffer.append(encoded)
                buffer.append(0x0A)
                offset += UInt64(encoded.count + 1)
                if buffer.count >= 4 * 1_024 * 1_024 {
                    try writer.write(contentsOf: buffer)
                    buffer.removeAll(keepingCapacity: true)
                }
            }
            try writer.write(contentsOf: buffer)
            try writer.synchronize()
            guard !seen.isEmpty else { throw ScryfallBulkDataError.corrupt("no English paper printings") }
            if persistent {
                let manifest = Manifest(version: Manifest.currentVersion, updatedAt: updatedAt,
                                        printingCount: seen.count, spoolSize: offset, slots: slots)
                try JSONEncoder().encode(manifest)
                    .write(to: directory.appendingPathComponent(manifestName), options: .atomic)
            }
            return ScryfallBulkCardIndex(updatedAt: updatedAt, spool: spool, directory: directory,
                                         slots: slots, printingCount: seen.count,
                                         removesDirectoryOnRelease: !persistent)
        } catch {
            try? manager.removeItem(at: directory)
            throw error
        }
    }
}

/// Streams the lines of a gzip file without decompressing it to disk or
/// holding it in memory. zlib verifies each member's CRC and length, so a
/// truncated or damaged archive throws rather than ending early.
enum GzipLineReader {
    static let maximumLineLength = 16 * 1_024 * 1_024

    static func forEachLine(in file: URL, chunkSize: Int = 1 << 20, _ body: (Data) throws -> Void) throws {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var stream = z_stream()
        // 15 window bits + 16 selects gzip framing with header and CRC checks.
        guard inflateInit2_(&stream, 15 + 16, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else {
            throw ScryfallBulkDataError.corrupt("could not start decompression")
        }
        defer { inflateEnd(&stream) }

        var output = [UInt8](repeating: 0, count: chunkSize)
        var pending = Data()
        var memberComplete = false
        var sawInput = false

        func emitLines() throws {
            var start = pending.startIndex
            while let newline = pending[start...].firstIndex(of: 0x0A) {
                var line = pending[start..<newline]
                if line.last == 0x0D { line = line.dropLast() }
                if !line.isEmpty { try body(Data(line)) }
                start = pending.index(after: newline)
            }
            pending = Data(pending[start...])
            if pending.count > maximumLineLength {
                throw ScryfallBulkDataError.corrupt("a record exceeds \(maximumLineLength) bytes")
            }
        }

        while let input = try handle.read(upToCount: chunkSize), !input.isEmpty {
            sawInput = true
            try input.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
                guard let base = raw.bindMemory(to: Bytef.self).baseAddress else { return }
                stream.next_in = UnsafeMutablePointer(mutating: base)
                stream.avail_in = uInt(raw.count)
                while stream.avail_in > 0 {
                    if memberComplete {
                        // Concatenated gzip members are valid; start the next.
                        guard inflateReset(&stream) == Z_OK else {
                            throw ScryfallBulkDataError.corrupt("could not continue to the next gzip member")
                        }
                        memberComplete = false
                    }
                    let before = stream.avail_in
                    let produced: Int = try output.withUnsafeMutableBufferPointer { out in
                        stream.next_out = out.baseAddress
                        stream.avail_out = uInt(out.count)
                        let status = inflate(&stream, Z_NO_FLUSH)
                        switch status {
                        case Z_OK, Z_BUF_ERROR: break
                        case Z_STREAM_END: memberComplete = true
                        default: throw ScryfallBulkDataError.corrupt("gzip data is damaged (zlib \(status))")
                        }
                        return out.count - Int(stream.avail_out)
                    }
                    if produced > 0 {
                        pending.append(contentsOf: output[0..<produced])
                        try emitLines()
                    } else if stream.avail_in == before, !memberComplete {
                        throw ScryfallBulkDataError.corrupt("decompression stopped making progress")
                    }
                }
            }
        }
        // Drain output zlib buffered after consuming the final input bytes.
        while sawInput, !memberComplete {
            let produced: Int = try output.withUnsafeMutableBufferPointer { out in
                stream.next_in = nil
                stream.avail_in = 0
                stream.next_out = out.baseAddress
                stream.avail_out = uInt(out.count)
                let status = inflate(&stream, Z_NO_FLUSH)
                switch status {
                case Z_OK: break
                case Z_STREAM_END: memberComplete = true
                case Z_BUF_ERROR: throw ScryfallBulkDataError.corrupt("gzip archive is truncated")
                default: throw ScryfallBulkDataError.corrupt("gzip data is damaged (zlib \(status))")
                }
                return out.count - Int(stream.avail_out)
            }
            if produced > 0 {
                pending.append(contentsOf: output[0..<produced])
                try emitLines()
            } else if !memberComplete {
                throw ScryfallBulkDataError.corrupt("gzip archive is truncated")
            }
        }
        guard sawInput else { throw ScryfallBulkDataError.corrupt("the archive is empty") }
        if !pending.isEmpty {
            var line = pending
            if line.last == 0x0D { line = line.dropLast() }
            if !line.isEmpty { try body(Data(line)) }
        }
    }
}

/// Supplies Catalog Health's full-catalog Magic enumeration from one daily
/// bulk download instead of one paced `/cards/search` sequence per set.
///
/// Scryfall requires bulk files for large lookups. One metadata request plus
/// an unmetered file download replaces roughly 750 search requests, so a full
/// report can no longer trip the 2-per-second search limit.
actor CatalogHealthMagicBulkSource {
    typealias Entry = (CatalogCardSummary, CatalogCardDetails)

    static let metadataURL = URL(string: "https://api.scryfall.com/bulk-data/default-cards")!
    private static let workDirectoryPrefix = "ScryfallBulk-"
    /// One cached index generation, reused until Scryfall publishes a newer
    /// file (about once a day). Caches may be purged by the system at any time.
    static let cacheDirectoryName = "ScryfallBulkIndex"

    private let session: URLSession
    private let pacer: ScryfallRequestPacer
    private let cachesDirectory: URL
    private let progress: @MainActor (String) -> Void
    private let summarize: @Sendable (ScryfallCard, CatalogSet) -> CatalogCardSummary
    private var state: Result<ScryfallBulkCardIndex, CatalogHealthScryfallFailure>?

    init(session: URLSession, pacer: ScryfallRequestPacer = .shared,
         cachesDirectory: URL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0],
         progress: @escaping @MainActor (String) -> Void,
         summarize: @escaping @Sendable (ScryfallCard, CatalogSet) -> CatalogCardSummary) {
        self.session = session
        self.pacer = pacer
        self.cachesDirectory = cachesDirectory
        self.progress = progress
        self.summarize = summarize
    }

    func entries(for set: CatalogSet) async throws -> [Entry] {
        let index = try await loadedIndex()
        let cards: [ScryfallCard]
        do {
            cards = try index.cards(inSet: set.providerID)
        } catch {
            throw CatalogHealthScryfallFailure(reason: "bulk data spool could not be read; no retry",
                                              defersProvider: true)
        }
        guard !cards.isEmpty else {
            // Scoped to this set: not evidence of a wider provider outage.
            throw CatalogHealthScryfallFailure(
                reason: "Scryfall bulk data (\(index.updatedAt.ISO8601Format())) lists no English paper printings for this set",
                defersProvider: false, setScoped: true)
        }
        return cards.map { card in
            (summarize(card, set), CatalogCardDetails(card: .magic(card), set: set, retrievedAt: index.updatedAt))
        }
    }

    private func loadedIndex() async throws -> ScryfallBulkCardIndex {
        if let state { return try state.get() }
        do {
            let index = try await buildIndex()
            state = .success(index)
            return index
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch let failure as CatalogHealthScryfallFailure {
            state = .failure(failure)
            throw failure
        } catch {
            let failure = CatalogHealthScryfallFailure(
                reason: "bulk data unavailable: \(error.localizedDescription) No retry", defersProvider: true)
            state = .failure(failure)
            throw failure
        }
    }

    private func buildIndex() async throws -> ScryfallBulkCardIndex {
        removeAbandonedWorkDirectories()
        await progress("Magic: reading Scryfall bulk data directory…")
        let metadata = try await fetchMetadata()
        let manager = FileManager.default
        let cacheRoot = cachesDirectory.appendingPathComponent(Self.cacheDirectoryName)
        let generation = String(Int64((metadata.updatedAt.timeIntervalSince1970 * 1_000).rounded()))
        let cached = cacheRoot.appendingPathComponent(generation)
        if let index = ScryfallBulkCardIndex.openPersisted(directory: cached, updatedAt: metadata.updatedAt) {
            await progress("Magic: using cached Scryfall card data…")
            return index
        }
        let size = ByteCountFormatter.string(fromByteCount: Int64(metadata.compressedSize), countStyle: .file)
        await progress("Magic: downloading Scryfall card data (\(size))…")
        let directory = cachesDirectory.appendingPathComponent(Self.workDirectoryPrefix + UUID().uuidString)
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: directory) }
        let archive = try await download(metadata, into: directory)
        await progress("Magic: indexing Scryfall card data…")
        let staging = directory.appendingPathComponent("index")
        let builder = Task.detached(priority: .utility) {
            defer { try? FileManager.default.removeItem(at: archive) }
            // Built and released here only to validate; the cache copy below
            // is reopened from its manifest.
            _ = try ScryfallBulkCardIndex.build(gzipFile: archive, updatedAt: metadata.updatedAt,
                                                directory: staging, persistent: true)
        }
        try await withTaskCancellationHandler {
            try await builder.value
        } onCancel: {
            builder.cancel()
        }
        try Task.checkCancellation()
        // Keep exactly one generation: the file just built replaces older ones.
        try? manager.removeItem(at: cacheRoot)
        try manager.createDirectory(at: cacheRoot, withIntermediateDirectories: true)
        try manager.moveItem(at: staging, to: cached)
        guard let index = ScryfallBulkCardIndex.openPersisted(directory: cached, updatedAt: metadata.updatedAt) else {
            try? manager.removeItem(at: cached)
            throw ScryfallBulkDataError.corrupt("the cached index could not be reopened")
        }
        return index
    }

    private func fetchMetadata() async throws -> ScryfallBulkDataMetadata {
        var request = URLRequest(url: Self.metadataURL)
        request.timeoutInterval = 12
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("TradingCardScanner/0.1 (iOS)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await pacer.data(for: request, session: session)
        } catch ScryfallError.rateLimited {
            throw CatalogHealthScryfallFailure(reason: "provider cooldown is still active; request skipped",
                                              defersProvider: true)
        }
        guard let http = response as? HTTPURLResponse else {
            throw CatalogHealthScryfallFailure(reason: "bulk data directory returned a non-HTTP response",
                                              defersProvider: true)
        }
        guard (200..<300).contains(http.statusCode) else {
            throw CatalogHealthScryfallFailure(reason: "bulk data directory returned HTTP \(http.statusCode); no retry",
                                              defersProvider: true, httpStatus: http.statusCode)
        }
        do {
            return try JSONDecoder().decode(ScryfallBulkDataMetadata.self, from: data)
                .validated(expectedType: "default_cards")
        } catch let error as ScryfallBulkDataError {
            throw error
        } catch {
            throw ScryfallBulkDataError.invalidMetadata("response could not be decoded")
        }
    }

    private func download(_ metadata: ScryfallBulkDataMetadata, into directory: URL) async throws -> URL {
        var request = URLRequest(url: metadata.downloadURL)
        request.timeoutInterval = 60
        request.setValue("TradingCardScanner/0.1 (iOS)", forHTTPHeaderField: "User-Agent")
        let (temporary, response) = try await session.download(for: request)
        let archive = directory.appendingPathComponent("default-cards.jsonl.gz")
        try FileManager.default.moveItem(at: temporary, to: archive)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode
            throw CatalogHealthScryfallFailure(
                reason: "bulk data download returned \(status.map { "HTTP \($0)" } ?? "a non-HTTP response"); no retry",
                defersProvider: true, httpStatus: status)
        }
        let received = (try? FileManager.default.attributesOfItem(atPath: archive.path)[.size] as? Int) ?? -1
        guard received == metadata.compressedSize else {
            throw ScryfallBulkDataError.incompleteDownload(expected: metadata.compressedSize, received: received)
        }
        return archive
    }

    /// An export interrupted by termination leaves its work directory behind.
    private func removeAbandonedWorkDirectories() {
        let manager = FileManager.default
        guard let names = try? manager.contentsOfDirectory(atPath: cachesDirectory.path) else { return }
        for name in names where name.hasPrefix(Self.workDirectoryPrefix) {
            try? manager.removeItem(at: cachesDirectory.appendingPathComponent(name))
        }
    }
}
