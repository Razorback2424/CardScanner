import Foundation
import CryptoKit

/// Devices consume the app's server-ingested feeds. Upstream TCGCSV is only
/// contacted by the daily publisher, never by a user-facing app or a redirect.
enum TCGCSVPriceMirror {
    static let refreshAfter: TimeInterval = 6 * 3600
    static let maxDownloadAge: TimeInterval = 7 * 86_400

    /// Set for a collection refresh: an older cached group may stand in only
    /// after the revalidation fails, never while a newer build is downloading,
    /// so a refresh is not recorded as a successful check of stale data.
    @TaskLocal static var awaitsRevalidation = false

    @TaskLocal static var explicitBuildRecheck: TCGCSVMirrorBuildMarker.Recheck?

    static func isWithinAge(_ date: Date, now: Date, maxAge: TimeInterval) -> Bool {
        let age = now.timeIntervalSince(date)
        return age >= 0 && age < maxAge
    }

    static func timestamp(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }

    static func hasValidCapture(source: PriceSource?, capturedAt: Date?, now: Date = .now) -> Bool {
        guard source == .tcgCSV else { return true }
        return capturedAt.map { $0 <= now } ?? false
    }

    static var baseURL: URL? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "TCGCSV_PRICE_BASE_URL") as? String,
              let url = URL(string: value), isPermitted(url),
              ["catalog.scan-stash.com", "scanstash-catalog-prod.web.app", "catalog-staging.scan-stash.com"].contains(url.host?.lowercased() ?? ""),
              ["/market-prices/v1", "/market-prices/v2"].contains(url.path) else { return nil }
        return url
    }

    static func isPermitted(_ url: URL) -> Bool {
        guard url.scheme == "https", let host = url.host?.lowercased(),
              !host.isEmpty, host != "tcgcsv.com", !host.hasSuffix(".tcgcsv.com"),
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
              url.port == nil || url.port == 443 else { return false }
        return true
    }

    private final class NoRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
        func urlSession(_ session: URLSession, task: URLSessionTask,
                        willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest,
                        completionHandler: @escaping (URLRequest?) -> Void) {
            completionHandler(nil)
        }
    }
    static let session = URLSession(configuration: .default, delegate: NoRedirects(), delegateQueue: nil)

    static func download(_ request: URLRequest, session: URLSession, interval: StaticString)
        async throws -> (Data, HTTPURLResponse) {
        let signpost = PerformanceSignpost.beginInterval(interval, id: PerformanceSignpost.makeID(), "")
        var byteCount = 0
        var status = 0
        defer { PerformanceSignpost.endInterval(interval, signpost, "bytes=\(byteCount) status=\(status)") }
        let (data, response) = try await session.data(for: request)
        byteCount = data.count
        guard let http = response as? HTTPURLResponse, http.url == request.url else {
            throw PriceQuoteError.providerUnavailable
        }
        status = http.statusCode
        return (data, http)
    }

    /// The server's original capture time survives CDN fetches and app relaunch.
    /// Matching daily-build markers prevent independently cached files mixing.
    static func captureDate(products: Data, prices: Data, expectedBuild: String? = nil,
                            now: Date = .now, maxAge: TimeInterval = maxDownloadAge) throws -> Date {
        struct Metadata: Decodable { let sourceBuild: String; let sourceFetchedAt: String }
        guard let product = try? JSONDecoder().decode(Metadata.self, from: products),
              let price = try? JSONDecoder().decode(Metadata.self, from: prices),
              product.sourceBuild == price.sourceBuild,
              expectedBuild.map({ $0 == price.sourceBuild }) ?? true,
              let build = timestamp(price.sourceBuild), let captured = timestamp(price.sourceFetchedAt),
              let productCaptured = timestamp(product.sourceFetchedAt),
              build <= captured, build <= productCaptured,
              isWithinAge(captured, now: now, maxAge: maxAge),
              isWithinAge(productCaptured, now: now, maxAge: maxAge) else {
            throw PriceQuoteError.providerUnavailable
        }
        return captured
    }
}

/// PR #65/#70: a build is immutable; the manifest binds every relative path
/// to its exact byte count and SHA-256. Never follow a URL from the manifest.
struct TCGCSVPriceManifest: Codable, Sendable {
    struct File: Codable, Sendable {
        let path: String
        let sha256: String
        let byteCount: Int
    }
    let schemaVersion: Int
    let sourceBuild: String
    let build: String
    let files: [File]

    static let maxPointerBytes = 4 * 1_024 * 1_024
    static let maxFileBytes = 8 * 1_024 * 1_024
    static let maxFileCount = 20_000
    static let maxBuildBytes = 512 * 1_024 * 1_024

    static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func isHash(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }

    func validate(now: Date) throws {
        let required: Set<String> = ["index.json", "last-updated.txt", "scopes/one-piece.json", "scopes/yugioh.json"]
        guard schemaVersion == 2, Self.isHash(build), let date = TCGCSVPriceMirror.timestamp(sourceBuild),
              date <= now, (6...Self.maxFileCount).contains(files.count) else { throw PriceQuoteError.providerUnavailable }
        var paths = Set<String>()
        var groupPaths = Set<String>()
        var total = 0
        for file in files {
            let path = file.path
            let isScope = path.range(of: #"\Ascopes/[a-z0-9][a-z0-9-]*\.json\z"#,
                                     options: .regularExpression) != nil
            let isGroup = path.range(of: #"\Atcgplayer/[1-9][0-9]*/[1-9][0-9]*/(products|prices)\z"#,
                                     options: .regularExpression) != nil
            guard (required.contains(path) || isScope || isGroup), paths.insert(path).inserted,
                  Self.isHash(file.sha256) else { throw PriceQuoteError.providerUnavailable }
            if isGroup { groupPaths.insert(path) }
            let limit = path == "index.json" ? Self.maxPointerBytes :
                (isScope ? 4 * 1_024 * 1_024 : Self.maxFileBytes)
            guard file.byteCount > 0, file.byteCount <= limit else { throw PriceQuoteError.providerUnavailable }
            total += file.byteCount
        }
        guard required.isSubset(of: paths), files.map(\.path) == paths.sorted(),
              total <= Self.maxBuildBytes else { throw PriceQuoteError.providerUnavailable }
        guard !groupPaths.isEmpty, groupPaths.allSatisfy({ path in
            let prefix = String(path.dropLast(path.hasSuffix("/products") ? 8 : 6))
            return groupPaths.contains(prefix + (path.hasSuffix("/products") ? "prices" : "products"))
        }) else { throw PriceQuoteError.providerUnavailable }
        // The publisher hashes canonical UTF-8 JSON, sorted keys, compact
        // separators, no escaped slashes, and exactly one trailing newline.
        struct Core: Encodable {
            let schemaVersion: Int
            let sourceBuild: String
            let files: [File]
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        var canonical = try encoder.encode(Core(schemaVersion: schemaVersion, sourceBuild: sourceBuild, files: files))
        canonical.append(10)
        guard Self.sha256(canonical) == build else { throw PriceQuoteError.providerUnavailable }
    }

    func file(path: String) throws -> File {
        guard let entry = files.first(where: { $0.path == path }) else {
            throw PriceQuoteError.providerUnavailable
        }
        return entry
    }
}

struct TCGCSVPricePublication: Sendable {
    let sourceBuild: String
    let manifest: TCGCSVPriceManifest?

    func matches(sourceBuild: String?, verifiedBuildID: String?) -> Bool {
        self.sourceBuild == sourceBuild && manifest?.build == verifiedBuildID
    }

    func matches(_ other: Self) -> Bool {
        matches(sourceBuild: other.sourceBuild, verifiedBuildID: other.manifest?.build)
    }
}

/// Large provider group files are replaceable. Individual quotes live in
/// PriceStore and ReferenceQuoteStore, outside this eviction policy.
struct TCGCSVSnapshotFiles {
    let directory: URL
    let legacyDirectory: URL?
    let byteLimit: Int

    static func live(_ name: String, byteLimit: Int) -> Self {
        let files = FileManager.default
        return Self(directory: files.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(name, isDirectory: true),
            legacyDirectory: files.urls(for: .cachesDirectory, in: .userDomainMask)[0]
                .appendingPathComponent(name, isDirectory: true), byteLimit: byteLimit)
    }

    func read<Value: Decodable>(_ name: String, maxBytes: Int, validating: (Value) -> Bool) -> Value? {
        let destination = directory.appendingPathComponent(name)
        let legacy = legacyDirectory?.appendingPathComponent(name)
        let files = FileManager.default
        let source = !files.fileExists(atPath: destination.path) ? (legacy ?? destination) : destination
        guard let handle = try? FileHandle(forReadingFrom: source) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: maxBytes + 1), data.count <= maxBytes,
              let value = try? JSONDecoder().decode(Value.self, from: data), validating(value) else { return nil }
        if source == destination {
            touch(name)
        } else {
            save(data, as: name)
        }
        return value
    }

    /// Marks a group as recently used for the LRU eviction in `save`. Throttled
    /// so frequent in-memory hits do not turn into a file write per request.
    func touch(_ name: String) {
        let url = directory.appendingPathComponent(name)
        guard let lastAccess = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
              Date.now.timeIntervalSince(lastAccess) >= TCGCSVPriceMirror.refreshAfter else { return }
        try? FileManager.default.setAttributes([.modificationDate: Date.now], ofItemAtPath: url.path)
    }

    @discardableResult
    func save(_ data: Data, as name: String) -> Bool {
        guard data.count <= byteLimit else { return false }
        let files = FileManager.default
        let destination = directory.appendingPathComponent(name)
        do {
            var root = directory
            try files.createDirectory(at: root, withIntermediateDirectories: true)
            if legacyDirectory != nil {
                var attributes = URLResourceValues()
                attributes.isExcludedFromBackup = true
                try root.setResourceValues(attributes)
            }
            try data.write(to: destination, options: .atomic)
        } catch { return false }
        if let legacyDirectory { try? files.removeItem(at: legacyDirectory.appendingPathComponent(name)) }
        guard byteLimit != .max else { return true }
        let keys: Set<URLResourceKey> = [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey]
        let entries = (try? files.contentsOfDirectory(at: directory, includingPropertiesForKeys: Array(keys),
            options: .skipsHiddenFiles)) ?? []
        let snapshots = entries.compactMap { url -> (url: URL, size: Int, accessed: Date)? in
            guard url.pathExtension == "json", let values = try? url.resourceValues(forKeys: keys),
                  values.isRegularFile == true, let size = values.fileSize else { return nil }
            return (url, size, values.contentModificationDate ?? .distantPast)
        }
        var total = snapshots.reduce(0) { $0 + $1.size }
        guard total > byteLimit else { return true }
        for entry in snapshots.sorted(by: { ($0.accessed, $0.url.lastPathComponent) < ($1.accessed, $1.url.lastPathComponent) })
            where entry.url != destination {
            if (try? files.removeItem(at: entry.url)) != nil { total -= entry.size }
            if total <= byteLimit { break }
        }
        return true
    }
}

actor TCGCSVMirrorBuildMarker {
    static let shared = TCGCSVMirrorBuildMarker(baseURL: TCGCSVPriceMirror.baseURL,
        session: TCGCSVPriceMirror.session, defaultsKey: "TCGCSVMirrorBuildMarker.v1")

    /// All mirrored groups in one user action share the same marker check.
    actor Recheck {
        private var checks: [ObjectIdentifier: Task<TCGCSVPricePublication, Error>] = [:]

        func build(using marker: TCGCSVMirrorBuildMarker) async throws -> TCGCSVPricePublication {
            let id = ObjectIdentifier(marker)
            if let check = checks[id] { return try await check.value }
            let check = Task { try await marker.currentPublication(forceRefresh: true) }
            checks[id] = check
            return try await check.value
        }
    }

    private struct Check: Codable, Sendable {
        let value: String
        let checkedAt: Date
        let etag: String?
        var manifest: TCGCSVPriceManifest? = nil
        var publication: TCGCSVPricePublication { .init(sourceBuild: value, manifest: manifest) }
    }

    private let baseURL: URL?
    private let session: URLSession
    private let now: @Sendable () -> Date
    private let legacyDefaultsKey: String?
    private let storageFileURL: URL?
    private let excludesStorageFromBackup: Bool
    private var check: Check?
    private var pending: Task<Check, Error>?

    private static let maxPersistedCheckBytes = TCGCSVPriceManifest.maxPointerBytes + 64 * 1_024

    private static func defaultStorageDirectory() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TCGCSVMirrorBuildMarker-v1", isDirectory: true)
    }

    private static func decodeValidatedCheck(_ bytes: Data, now: Date) -> Check? {
        guard bytes.count <= maxPersistedCheckBytes,
              let restored = try? JSONDecoder().decode(Check.self, from: bytes),
              restored.manifest.map({ (try? $0.validate(now: now)) != nil && $0.sourceBuild == restored.value }) ?? true else {
            return nil
        }
        return restored
    }

    private static func readPersistedCheck(at url: URL, now: Date) -> Check? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let bytes = try? handle.read(upToCount: maxPersistedCheckBytes + 1),
              bytes.count <= maxPersistedCheckBytes else { return nil }
        return decodeValidatedCheck(bytes, now: now)
    }

    @discardableResult
    private static func writePersistedCheck(_ bytes: Data, to url: URL, excludeFromBackup: Bool) -> Bool {
        guard bytes.count <= maxPersistedCheckBytes else { return false }
        let directory = url.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            if excludeFromBackup {
                var root = directory
                var values = URLResourceValues()
                values.isExcludedFromBackup = true
                try root.setResourceValues(values)
            }
            try bytes.write(to: url, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    init(baseURL: URL?, session: URLSession, now: @escaping @Sendable () -> Date = { .now },
         defaultsKey: String? = nil, storageDirectory: URL? = nil) {
        self.baseURL = baseURL
        self.session = session
        self.now = now
        let scopedKey = defaultsKey.map { "\($0)|\(baseURL?.absoluteString ?? "")" }
        self.legacyDefaultsKey = scopedKey
        self.excludesStorageFromBackup = storageDirectory == nil
        if let scopedKey {
            let directory = storageDirectory ?? Self.defaultStorageDirectory()
            let fileURL = directory.appendingPathComponent("\(TCGCSVPriceManifest.sha256(Data(scopedKey.utf8))).json")
            self.storageFileURL = fileURL
            let currentNow = now()
            if let restored = Self.readPersistedCheck(at: fileURL, now: currentNow) {
                check = restored
                if UserDefaults.standard.object(forKey: scopedKey) != nil {
                    UserDefaults.standard.removeObject(forKey: scopedKey)
                }
            } else if let legacyBytes = UserDefaults.standard.data(forKey: scopedKey) {
                if let restored = Self.decodeValidatedCheck(legacyBytes, now: currentNow) {
                    check = restored
                    if Self.writePersistedCheck(legacyBytes, to: fileURL, excludeFromBackup: excludesStorageFromBackup) {
                        UserDefaults.standard.removeObject(forKey: scopedKey)
                    }
                } else {
                    UserDefaults.standard.removeObject(forKey: scopedKey)
                }
            }
        } else {
            self.storageFileURL = nil
        }
    }

    func lastKnownBuild() -> String? { check?.value }
    func lastKnownPublication() -> TCGCSVPricePublication? { check?.publication }

    func currentBuild(forceRefresh: Bool = false) async throws -> String {
        try await currentPublication(forceRefresh: forceRefresh).sourceBuild
    }

    func currentPublication(forceRefresh: Bool = false) async throws -> TCGCSVPricePublication {
        guard let baseURL, TCGCSVPriceMirror.isPermitted(baseURL) else {
            throw PriceQuoteError.providerUnavailable
        }
        if let pending { return try await pending.value.publication }
        if !forceRefresh, let check, TCGCSVPriceMirror.isWithinAge(check.checkedAt,
            now: now(), maxAge: TCGCSVPriceMirror.refreshAfter) { return check.publication }

        let task = Task {
            defer { self.pending = nil }
            let previous = self.check
            let updated: Check
            if baseURL.path == "/market-prices/v2" {
                var request = URLRequest(url: baseURL.appendingPathComponent("latest.json"),
                    cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 12)
                request.setValue("ScanStash/1.0 (iOS; market build check)", forHTTPHeaderField: "User-Agent")
                if let previous, previous.manifest != nil, let etag = previous.etag {
                    request.setValue(etag, forHTTPHeaderField: "If-None-Match")
                }
                let (body, response) = try await TCGCSVPriceMirror.download(request, session: self.session, interval: "mirror.marker")
                if response.statusCode == 304, let previous, let manifest = previous.manifest, previous.etag != nil {
                    updated = Check(value: previous.value, checkedAt: self.now(),
                        etag: response.value(forHTTPHeaderField: "ETag") ?? previous.etag, manifest: manifest)
                } else if response.statusCode == 404, previous?.manifest == nil {
                    // Bootstrap compatibility before v2 is deployed on the
                    // production hostname. After accepting v2, never downgrade
                    // on a missing, invalid, or unavailable pointer.
                    updated = try await self.readLegacy(baseURL.deletingLastPathComponent().appendingPathComponent("v1"),
                                                        previous: previous)
                } else {
                    guard response.statusCode == 200, body.count <= TCGCSVPriceManifest.maxPointerBytes,
                          let manifest = try? JSONDecoder().decode(TCGCSVPriceManifest.self, from: body) else {
                        throw PriceQuoteError.providerUnavailable
                    }
                    try manifest.validate(now: self.now())
                    if let previous, let old = TCGCSVPriceMirror.timestamp(previous.value),
                       let new = TCGCSVPriceMirror.timestamp(manifest.sourceBuild), new < old {
                        throw PriceQuoteError.providerUnavailable
                    }
                    updated = Check(value: manifest.sourceBuild, checkedAt: self.now(),
                        etag: response.value(forHTTPHeaderField: "ETag"), manifest: manifest)
                }
            } else {
                updated = try await self.readLegacy(baseURL, previous: previous)
            }
            self.check = updated
            if let fileURL = self.storageFileURL, let bytes = try? JSONEncoder().encode(updated) {
                Self.writePersistedCheck(bytes, to: fileURL, excludeFromBackup: self.excludesStorageFromBackup)
                if let legacyKey = self.legacyDefaultsKey, UserDefaults.standard.object(forKey: legacyKey) != nil {
                    UserDefaults.standard.removeObject(forKey: legacyKey)
                }
            }
            return updated
        }
        pending = task
        return try await task.value.publication
    }

    private func readLegacy(_ baseURL: URL, previous: Check?) async throws -> Check {
        var request = URLRequest(url: baseURL.appendingPathComponent("last-updated.txt"),
            cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 12)
        request.setValue("ScanStash/1.0 (iOS; market build check)", forHTTPHeaderField: "User-Agent")
        if let etag = previous?.etag { request.setValue(etag, forHTTPHeaderField: "If-None-Match") }
        let (body, response) = try await TCGCSVPriceMirror.download(request, session: session, interval: "mirror.marker")
        if response.statusCode == 304, let previous, previous.etag != nil {
            return Check(value: previous.value, checkedAt: now(),
                etag: response.value(forHTTPHeaderField: "ETag") ?? previous.etag)
        }
        guard response.statusCode == 200, body.count <= 1_024,
              let value = String(data: body, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              value.count < 100, ISO8601DateFormatter().date(from: value) != nil else {
            throw PriceQuoteError.providerUnavailable
        }
        return Check(value: value, checkedAt: now(), etag: response.value(forHTTPHeaderField: "ETag"))
    }
}

/// Product-level USD market observations. No condition-specific SKU is claimed.
actor TCGCSVProductPriceSource {
    static let shared = TCGCSVProductPriceSource()
    private struct Response<Row: Decodable>: Decodable {
        let success: Bool
        let errors: [String]
        let results: [Row]
        let totalItems: Int?
        let sourceBuild: String
    }
    struct Product: Codable, Sendable {
        struct Field: Codable, Sendable { let name: String; let value: String }
        let productId: Int; let categoryId: Int; let groupId: Int
        let name: String; let extendedData: [Field]
    }
    struct Price: Codable, Sendable {
        let productId: Int; let subTypeName: String; let marketPrice: Double?
    }
    struct Snapshot: Codable, Sendable {
        let products: [Product]; let prices: [Price]; let fetchedAt: Date
        var sourceBuild: String? = nil
        var validatedAt: Date? = nil
        var verifiedBuildID: String? = nil
        // An upgrade can keep dated positive quotes from an older set cache.
        // It has no complete provider response or evidence of absence.
        var legacyPositiveOnly: Bool? = nil

        func isNewer(than other: Self) -> Bool {
            // A complete provider response always outranks a positive-only
            // legacy import, whatever their timestamps say.
            let legacy = legacyPositiveOnly == true, otherLegacy = other.legacyPositiveOnly == true
            if legacy != otherLegacy { return otherLegacy }
            if fetchedAt != other.fetchedAt { return fetchedAt > other.fetchedAt }
            guard sourceBuild != other.sourceBuild else { return false }
            let build = sourceBuild.flatMap(TCGCSVPriceMirror.timestamp)
            let otherBuild = other.sourceBuild.flatMap(TCGCSVPriceMirror.timestamp)
            return (build ?? .distantPast) > (otherBuild ?? .distantPast)
        }
    }
    private let session: URLSession
    private let baseURL: URL?
    private let files: TCGCSVSnapshotFiles
    private let now: @Sendable () -> Date
    private let marker: TCGCSVMirrorBuildMarker
    private let spacing: TimeInterval
    private struct GroupKey: Hashable { let category: Int; let group: Int }
    private struct CacheKey: Hashable {
        let group: GroupKey
        let minimumFetchedAt: Date?
    }
    private struct LaneKey: Hashable {
        let productID: Int
        let lane: String
    }
    /// Decoded groups kept in memory, bounded by count. An evicted group is
    /// reloaded from disk on its next use, without a network request.
    private struct RecentSnapshots {
        let limit: Int
        private var values: [GroupKey: Snapshot] = [:]
        private var lastUse: [GroupKey: UInt64] = [:]
        private var clock: UInt64 = 0
        init(limit: Int) { self.limit = max(1, limit) }
        var count: Int { values.count }
        subscript(key: GroupKey) -> Snapshot? {
            mutating get {
                guard let value = values[key] else { return nil }
                clock += 1; lastUse[key] = clock
                return value
            }
            set {
                clock += 1
                values[key] = newValue
                lastUse[key] = newValue == nil ? nil : clock
                while values.count > limit, let oldest = lastUse.min(by: { $0.value < $1.value })?.key {
                    values[oldest] = nil; lastUse[oldest] = nil
                }
            }
        }
    }
    private var snapshots: RecentSnapshots
    /// Test and diagnostics hook: how many decoded groups are resident.
    var residentGroupCount: Int { snapshots.count }
    private struct PendingSnapshot {
        let task: Task<Snapshot, Error>
        let forced: Bool
    }
    private var pending: [CacheKey: PendingSnapshot] = [:]
    private var failures: [CacheKey: Date] = [:]
    private var nextRequestAt = Date.distantPast
    init(baseURL: URL? = TCGCSVPriceMirror.baseURL,
         session: URLSession = TCGCSVPriceMirror.session,
         cacheDirectory: URL? = nil,
         now: @escaping @Sendable () -> Date = { .now }, marker: TCGCSVMirrorBuildMarker? = nil,
         spacing: TimeInterval = 0.1, memoryGroupLimit: Int = 64) {
        self.session = session; self.baseURL = baseURL
        self.snapshots = RecentSnapshots(limit: memoryGroupLimit)
        self.files = cacheDirectory.map { TCGCSVSnapshotFiles(directory: $0, legacyDirectory: nil, byteLimit: .max) }
            ?? .live("TCGCSVProductPrices-v1", byteLimit: 128 * 1_024 * 1_024)
        self.now = now
        self.spacing = spacing
        self.marker = marker ?? (baseURL == TCGCSVPriceMirror.baseURL && session === TCGCSVPriceMirror.session
            ? .shared : TCGCSVMirrorBuildMarker(baseURL: baseURL, session: session, now: now))
    }

    func groupSnapshot(category: Int, group: Int, retry: Bool,
                       loadLegacy: @Sendable () -> Snapshot?, retireLegacy: @Sendable () -> Void) async throws -> Snapshot {
        let key = GroupKey(category: category, group: group)
        let name = "\(category)-\(group).json"
        if snapshots[key] == nil {
            if let disk = load(group: key, name: name) {
                snapshots[key] = disk
                retireLegacy()
            } else if let legacy = loadLegacy() {
                if isServable(legacy), (try? validate(legacy, group: key)) != nil {
                    snapshots[key] = legacy
                    if let data = try? JSONEncoder().encode(legacy), files.save(data, as: name) { retireLegacy() }
                } else {
                    // Unusable imports are removed, including any migrated copy.
                    retireLegacy()
                }
            }
        }
        // Set projections are keyed to a feed build; a cache file written
        // before builds were recorded cannot stand in for one.
        let rechecking = retry || TCGCSVPriceMirror.explicitBuildRecheck != nil
        let result = try await snapshot(group: key, minimumFetchedAt: nil, forceRefresh: rechecking,
                                          waitForKnownBuild: true) { !rechecking && $0.sourceBuild != nil }
        let received = result.value
        return snapshots[key].flatMap { $0.sourceBuild != nil && $0.verifiedBuildID == received.verifiedBuildID && $0.isNewer(than: received) ? $0 : nil } ?? received
    }

    func quote(category: Int, group: Int, productID: Int, name: String, number: String?,
               lane: String, minimumFetchedAt: Date?, allowsMissingNumber: Bool = false,
               allowsStaleFallback: Bool = true) async throws -> PriceLookup {
        guard category > 0, group > 0, productID > 0, !name.isEmpty, number != "",
              ["Normal", "Foil", "Cold Foil", "Holofoil", "Reverse Holofoil", "1st Edition", "Unlimited", "Limited"]
                .contains(lane) else { throw PriceQuoteError.identityMismatch }
        let groupKey = GroupKey(category: category, group: group)
        func matchesProduct(_ snapshot: Snapshot) -> Bool {
            guard let product = snapshot.products.first(where: { $0.productId == productID }),
                  product.categoryId == category, product.groupId == group, product.name == name else { return false }
            let numbers = product.extendedData.filter { $0.name == "Number" }.map(\.value)
            return numbers == (number.map { [$0] } ?? []) || (allowsMissingNumber && numbers.isEmpty)
        }
        let rechecking = TCGCSVPriceMirror.explicitBuildRecheck != nil
        // Browse keeps the last displayed amount on a failed check. Collection
        // may also recover a saved amount, attaching its existing failure flag.
        let canRetainQuote = allowsStaleFallback && (!rechecking || TCGCSVPriceMirror.awaitsRevalidation)
        let result = try await snapshot(group: groupKey, minimumFetchedAt: minimumFetchedAt,
                                        forceRefresh: rechecking) { cached in
            canRetainQuote && cached.legacyPositiveOnly != true && matchesProduct(cached) && cached.prices.contains {
                $0.productId == productID && $0.subTypeName == lane && $0.marketPrice != nil
            }
        }
        try Task.checkCancellation()
        let fetched = result.value
        let snapshot = snapshots[groupKey].flatMap { $0.verifiedBuildID == fetched.verifiedBuildID && $0.isNewer(than: fetched) ? $0 : nil } ?? fetched
        guard snapshot.legacyPositiveOnly != true, isServable(snapshot) else { throw PriceQuoteError.providerUnavailable }
        let hasCurrentCapture = PriceDisplay.freshness(asOf: snapshot.fetchedAt, now: now()) == .current
        guard matchesProduct(snapshot) else { throw PriceQuoteError.identityMismatch }
        let rows = snapshot.prices.filter { $0.productId == productID && $0.subTypeName == lane }
        guard rows.count <= 1 else { throw PriceQuoteError.identityMismatch }
        guard let amount = rows.first?.marketPrice else {
            guard hasCurrentCapture, !result.revalidationFailed else { throw PriceQuoteError.providerUnavailable }
            return .unavailable(.tcgCSV)
        }
        guard amount.isFinite, amount >= 0 else { throw PriceQuoteError.providerUnavailable }
        return .price(.init(unitMarketPriceUSD: amount, currencyCode: "USD", source: .tcgCSV,
            sourceVariantID: "tcgplayer:\(productID):\(lane)", sourceUpdatedAt: nil, fetchedAt: snapshot.fetchedAt,
            retainedAfterRefreshFailure: TCGCSVPriceMirror.awaitsRevalidation && result.revalidationFailed ? true : nil))
    }

    private func load(group: GroupKey, name: String) -> Snapshot? {
        files.read(name, maxBytes: 16 * 1_024 * 1_024) { (try? validate($0, group: group)) != nil }
    }

    private typealias SnapshotResult = (value: Snapshot, revalidationFailed: Bool)

    private func snapshot(group: GroupKey, minimumFetchedAt: Date?, forceRefresh: Bool = false,
                          waitForKnownBuild: Bool = false,
                          canUseFallback: (Snapshot) -> Bool) async throws -> SnapshotResult {
        let knownBuild = await marker.lastKnownPublication()
        try Task.checkCancellation()
        // A withdrawal starts a new request cohort. It must not join a fetch
        // that began before its watermark. Each caller verifies the exact lane
        // against its current mapping before the shared group can yield a price.
        let key = CacheKey(group: group, minimumFetchedAt: minimumFetchedAt)
        let name = "\(group.category)-\(group.group).json"
        if snapshots[group] == nil { snapshots[group] = load(group: group, name: name) } else { files.touch(name) }
        let cached = snapshots[group].flatMap { value in
            (minimumFetchedAt.map { value.fetchedAt > $0 } ?? true)
                ? value : nil
        }
        if !forceRefresh, let cached, cached.legacyPositiveOnly != true, let sourceBuild = cached.sourceBuild,
           TCGCSVPriceMirror.isWithinAge(cached.validatedAt ?? cached.fetchedAt, now: now(),
               maxAge: TCGCSVPriceMirror.refreshAfter), isServable(cached),
           (canUseFallback(cached) || isWithinDownloadAge(cached)),
           knownBuild.map({ $0.matches(sourceBuild: sourceBuild, verifiedBuildID: cached.verifiedBuildID) })
                ?? (baseURL?.path != "/market-prices/v2" || cached.verifiedBuildID != nil) { return (cached, false) }
        let servable = cached.flatMap { isServable($0) && canUseFallback($0) ? $0 : nil }
        let immediateFallback = minimumFetchedAt == nil && !forceRefresh
            && !TCGCSVPriceMirror.awaitsRevalidation && (!waitForKnownBuild
            || knownBuild == nil || knownBuild?.matches(sourceBuild: cached?.sourceBuild, verifiedBuildID: cached?.verifiedBuildID) == true
            || cached.map({ !TCGCSVPriceMirror.isWithinAge($0.validatedAt ?? $0.fetchedAt,
                now: now(), maxAge: TCGCSVPriceMirror.refreshAfter) }) == true)
        if let request = pending[key] {
            if forceRefresh && !request.forced {
                _ = try? await request.task.valueForCurrentWaiter()
                try Task.checkCancellation()
                return try await snapshot(group: group, minimumFetchedAt: minimumFetchedAt, forceRefresh: true,
                                          waitForKnownBuild: waitForKnownBuild, canUseFallback: canUseFallback)
            }
            if immediateFallback, let servable { return (servable, false) }
            return try await waitForSnapshot(request.task, key: key, canUseFallback: canUseFallback)
        }
        if !forceRefresh, let failure = failures[key], TCGCSVPriceMirror.isWithinAge(failure, now: now(), maxAge: 900) {
            if let servable { return (servable, true) }
            throw PriceQuoteError.providerUnavailable
        }
        let task = Task<Snapshot, Error> {
            defer { self.pending[key] = nil }
            let value: Snapshot
            do {
                let build: TCGCSVPricePublication
                if let recheck = TCGCSVPriceMirror.explicitBuildRecheck {
                    build = try await recheck.build(using: self.marker)
                } else {
                    build = try await self.marker.currentPublication(forceRefresh: forceRefresh)
                }
                if var cached, cached.legacyPositiveOnly != true,
                   build.matches(sourceBuild: cached.sourceBuild, verifiedBuildID: cached.verifiedBuildID),
                   self.isWithinDownloadAge(cached) {
                    try await self.requireCurrentV2(build)
                    if let latest = self.snapshots[group], latest.verifiedBuildID == cached.verifiedBuildID,
                       latest.isNewer(than: cached) { return latest }
                    if self.snapshots[group]?.fetchedAt == cached.fetchedAt,
                       self.snapshots[group]?.sourceBuild == cached.sourceBuild,
                       self.snapshots[group]?.verifiedBuildID == cached.verifiedBuildID {
                        cached.validatedAt = self.now()
                        self.snapshots[group] = cached
                    }
                    self.failures[key] = nil
                    return cached
                }
                value = try await self.download(group: group, build: build)
                if let active = await self.marker.lastKnownPublication(), active.manifest != nil,
                   !active.matches(sourceBuild: value.sourceBuild, verifiedBuildID: value.verifiedBuildID) {
                    throw PriceQuoteError.providerUnavailable
                }
                guard minimumFetchedAt.map({ value.fetchedAt > $0 }) ?? true else {
                    throw PriceQuoteError.providerUnavailable
                }
            } catch {
                // Transport interruption stays retryable; rejected provider
                // responses retain the existing cooldown.
                if !(error is CancellationError), !(error is URLError) { self.failures[key] = self.now() }
                throw error
            }
            self.failures[key] = nil
            // A slower, older request must not replace a newer observation.
            if let latest = self.snapshots[group], latest.verifiedBuildID == value.verifiedBuildID,
               latest.isNewer(than: value) { return latest }
            self.snapshots[group] = value
            if let bytes = try? JSONEncoder().encode(value) {
                self.files.save(bytes, as: name)
            }
            return value
        }
        pending[key] = PendingSnapshot(task: task, forced: forceRefresh)
        // The unstructured task owns the revalidation even if no caller waits.
        if immediateFallback, let servable { return (servable, false) }
        return try await waitForSnapshot(task, key: key, canUseFallback: canUseFallback)
    }

    /// The group files were readable but stamped for a different build than the marker.
    private struct BuildMismatch: Error {}

    private func requireCurrentV2(_ publication: TCGCSVPricePublication) async throws {
        // Different request cohorts may complete out of order. Do not let an
        // earlier immutable build overwrite a newer publication's cache.
        if let active = await marker.lastKnownPublication(), active.manifest != nil,
           !active.matches(publication) { throw PriceQuoteError.providerUnavailable }
    }

    private func download(group: GroupKey, build: TCGCSVPricePublication) async throws -> Snapshot {
        do {
            return try await downloadGroup(group, expectedBuild: build)
        } catch is BuildMismatch {
            // The publication can advance between the marker and either group file.
            guard build.manifest == nil else { throw PriceQuoteError.providerUnavailable }
            let latest = try await marker.currentPublication(forceRefresh: true)
            guard !latest.matches(build) else { throw PriceQuoteError.providerUnavailable }
            do {
                return try await downloadGroup(group, expectedBuild: latest)
            } catch is BuildMismatch {
                throw PriceQuoteError.providerUnavailable
            }
        }
    }

    private func downloadGroup(_ group: GroupKey, expectedBuild: TCGCSVPricePublication) async throws -> Snapshot {
        let productsData = try await fetch(group: group, resource: "products", publication: expectedBuild)
        let pricesData = try await fetch(group: group, resource: "prices", publication: expectedBuild)
        // Only a build-stamp problem suggests a rollover worth rechecking the
        // marker for; an HTTP failure from fetch() is an ordinary outage.
        let fetchedAt: Date
        do {
            fetchedAt = try TCGCSVPriceMirror.captureDate(products: productsData, prices: pricesData,
                expectedBuild: expectedBuild.sourceBuild, now: now())
        } catch {
            throw BuildMismatch()
        }
        let products = try JSONDecoder().decode(Response<Product>.self, from: productsData)
        let prices = try JSONDecoder().decode(Response<Price>.self, from: pricesData)
        guard products.success, products.errors.isEmpty, prices.success, prices.errors.isEmpty,
              products.totalItems.map({ $0 == products.results.count }) ?? true,
              prices.totalItems.map({ $0 == prices.results.count }) ?? true else {
            throw PriceQuoteError.providerUnavailable
        }
        let value = Snapshot(products: products.results, prices: prices.results, fetchedAt: fetchedAt,
            sourceBuild: prices.sourceBuild, validatedAt: now(), verifiedBuildID: expectedBuild.manifest?.build)
        try validate(value, group: group)
        return value
    }

    private func isServable(_ snapshot: Snapshot) -> Bool {
        TCGCSVPriceMirror.hasValidCapture(source: .tcgCSV, capturedAt: snapshot.fetchedAt, now: now())
    }

    private func isWithinDownloadAge(_ snapshot: Snapshot) -> Bool {
        TCGCSVPriceMirror.isWithinAge(snapshot.fetchedAt, now: now(), maxAge: TCGCSVPriceMirror.maxDownloadAge)
    }

    private func waitForSnapshot(_ task: Task<Snapshot, Error>, key: CacheKey,
                                 canUseFallback: (Snapshot) -> Bool) async throws -> SnapshotResult {
        do {
            return (try await task.valueForCurrentWaiter(), false)
        } catch {
            try Task.checkCancellation()
            // Another cohort may have replaced or withdrawn the lane while
            // this request was failing. Recheck the latest snapshot now.
            if !(error is CancellationError), (error as? URLError)?.code != .cancelled,
               let fallback = snapshots[key.group], isServable(fallback),
               key.minimumFetchedAt.map({ fallback.fetchedAt > $0 }) ?? true, canUseFallback(fallback) {
                return (fallback, true)
            }
            throw error
        }
    }

    /// Reject invalid group responses before either cache can retain them for
    /// a day. Apply the same contract to disk snapshots from older app versions.
    private func validate(_ snapshot: Snapshot, group: GroupKey) throws {
        guard snapshot.products.allSatisfy({ $0.categoryId == group.category && $0.groupId == group.group }),
              Set(snapshot.products.map(\.productId)).count == snapshot.products.count,
              Set(snapshot.prices.map { LaneKey(productID: $0.productId, lane: $0.subTypeName) }).count == snapshot.prices.count else {
            throw PriceQuoteError.identityMismatch
        }
        guard snapshot.prices.allSatisfy({ row in
            guard let amount = row.marketPrice else { return true }
            return amount >= 0 && Money(rounding: amount) != nil
        }) else { throw PriceQuoteError.providerUnavailable }
    }

    private func fetch(group: GroupKey, resource: String, publication: TCGCSVPricePublication) async throws -> Data {
        guard let baseURL, TCGCSVPriceMirror.isPermitted(baseURL) else { throw PriceQuoteError.providerUnavailable }
        let start = max(nextRequestAt, .now)
        nextRequestAt = start.addingTimeInterval(spacing)
        if start.timeIntervalSinceNow > 0 { try await Task.sleep(for: .seconds(start.timeIntervalSinceNow)) }
        let path = "tcgplayer/\(group.category)/\(group.group)/\(resource)"
        let entry = try publication.manifest?.file(path: path)
        let url: URL
        if let manifest = publication.manifest {
            url = baseURL.appendingPathComponent("builds/\(manifest.build)/\(path)")
        } else {
            let legacy = baseURL.path == "/market-prices/v2"
                ? baseURL.deletingLastPathComponent().appendingPathComponent("v1") : baseURL
            url = legacy.appendingPathComponent(path)
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("ScanStash/1.0 (iOS; daily product market pricing)", forHTTPHeaderField: "User-Agent")
        request.cachePolicy = .reloadRevalidatingCacheData
        let (data, http) = try await TCGCSVPriceMirror.download(request, session: session, interval: "mirror.group")
        guard http.statusCode == 200,
              data.count <= 8 * 1_024 * 1_024 else { throw PriceQuoteError.providerUnavailable }
        if let entry, (data.count != entry.byteCount || TCGCSVPriceManifest.sha256(data) != entry.sha256) {
            throw PriceQuoteError.providerUnavailable
        }
        return data
    }
}
