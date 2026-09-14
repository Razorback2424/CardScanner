import CryptoKit
import Foundation

enum CollectionStoreManifestStoreError: LocalizedError, Equatable {
    case storageLocationUnavailable
    case corrupt
    case unsupportedNewerVersion(Int)
    case readFailure
    case writeFailure
    case invalidAttachmentTransition(from: CloudAttachmentState, to: CloudAttachmentState)
    case invalidMigrationTransition(from: StoreMigrationState, to: StoreMigrationState)
    case invalidStoreIdentity

    var errorDescription: String? {
        switch self {
        case .storageLocationUnavailable:
            return "The collection storage location is unavailable. No replacement store was opened."
        case .corrupt:
            return "The collection storage manifest is corrupt. The original store was left untouched."
        case let .unsupportedNewerVersion(version):
            return "The collection storage manifest was written by a newer version (format \(version))."
        case .readFailure:
            return "The collection storage manifest could not be read."
        case .writeFailure:
            return "The collection storage manifest could not be written atomically."
        case let .invalidAttachmentTransition(from, to):
            return "The collection storage attachment state cannot move from \(from.rawValue) to \(to.rawValue)."
        case let .invalidMigrationTransition(from, to):
            return "The collection storage migration state cannot move from \(from.rawValue) to \(to.rawValue)."
        case .invalidStoreIdentity:
            return "The collection storage file identity is invalid."
        }
    }
}

struct CollectionStoreManifestStore: Sendable {
    static let manifestFilename = "manifest.json"
    static let storeFileIdentityFilename = "store-file.identity"

    let directoryURL: URL
    let isUsable: Bool

    init(directoryURL: URL, isUsable: Bool = true) {
        self.directoryURL = directoryURL
        self.isUsable = isUsable
    }

    static func production(fileManager: FileManager = .default) -> Self {
        guard let applicationSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            return Self(
                directoryURL: URL(
                    fileURLWithPath: "/__cardscanner_application_support_unavailable__",
                    isDirectory: true
                ),
                isUsable: false
            )
        }
        return Self(
            directoryURL: applicationSupport
                .appendingPathComponent("CardScanner", isDirectory: true)
                .appendingPathComponent("CollectionStorage", isDirectory: true)
        )
    }

    var manifestURL: URL {
        directoryURL.appendingPathComponent(Self.manifestFilename)
    }

    var temporaryManifestURL: URL {
        directoryURL.appendingPathComponent("\(Self.manifestFilename).tmp")
    }

    var storeFileIdentityURL: URL {
        directoryURL.appendingPathComponent(Self.storeFileIdentityFilename)
    }

    func load() throws -> CollectionStoreManifest? {
        guard isUsable else { throw CollectionStoreManifestStoreError.storageLocationUnavailable }
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: manifestURL.path) else { return nil }

        let data: Data
        do {
            data = try Data(contentsOf: manifestURL, options: [.mappedIfSafe])
        } catch {
            throw CollectionStoreManifestStoreError.readFailure
        }

        let manifest: CollectionStoreManifest
        do {
            manifest = try Self.decoder.decode(CollectionStoreManifest.self, from: data)
        } catch {
            throw CollectionStoreManifestStoreError.corrupt
        }
        guard manifest.formatVersion <= CollectionStoreManifest.currentFormatVersion else {
            throw CollectionStoreManifestStoreError.unsupportedNewerVersion(manifest.formatVersion)
        }
        let zeroStoreID = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
        guard manifest.storeID != zeroStoreID, !manifest.storeFileIdentity.contains("/") else {
            throw CollectionStoreManifestStoreError.invalidStoreIdentity
        }
        return manifest
    }

    func save(_ manifest: CollectionStoreManifest) throws {
        guard isUsable else { throw CollectionStoreManifestStoreError.storageLocationUnavailable }
        guard manifest.formatVersion <= CollectionStoreManifest.currentFormatVersion else {
            throw CollectionStoreManifestStoreError.unsupportedNewerVersion(manifest.formatVersion)
        }
        guard !manifest.storeFileIdentity.contains("/") else {
            throw CollectionStoreManifestStoreError.invalidStoreIdentity
        }

        let fileManager = FileManager.default
        do {
            try fileManager.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true,
                attributes: [.protectionKey: FileProtectionType.completeUnlessOpen]
            )
            do {
                if let existing = try load(),
                   existing.formatVersion > manifest.formatVersion {
                    throw CollectionStoreManifestStoreError.unsupportedNewerVersion(existing.formatVersion)
                }
            } catch let error as CollectionStoreManifestStoreError {
                // A corrupt or unreadable manifest is a recovery condition,
                // never permission to overwrite the metadata that protects an
                // existing collection.
                throw error
            }

            let data = try Self.encoder.encode(manifest)
            try data.write(to: temporaryManifestURL, options: .atomic)
            try fileManager.setAttributes(
                [.protectionKey: FileProtectionType.completeUnlessOpen],
                ofItemAtPath: temporaryManifestURL.path
            )

            if fileManager.fileExists(atPath: manifestURL.path) {
                _ = try fileManager.replaceItemAt(
                    manifestURL,
                    withItemAt: temporaryManifestURL,
                    backupItemName: nil,
                    options: .usingNewMetadataOnly
                )
            } else {
                try fileManager.moveItem(at: temporaryManifestURL, to: manifestURL)
            }
        } catch let error as CollectionStoreManifestStoreError {
            try? fileManager.removeItem(at: temporaryManifestURL)
            throw error
        } catch {
            try? fileManager.removeItem(at: temporaryManifestURL)
            throw CollectionStoreManifestStoreError.writeFailure
        }
    }

    /// Returns one stable opaque token for the authoritative local store. The
    /// token is created independently of SQLite content and survives normal
    /// SQLite replacement/compaction.
    func ensureStoreFileIdentity() throws -> String {
        guard isUsable else { throw CollectionStoreManifestStoreError.storageLocationUnavailable }
        let fileManager = FileManager.default
        if let existing = try readStoreFileIdentity() {
            return existing
        }

        let token = SHA256.hash(data: Data(UUID().uuidString.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        do {
            try fileManager.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true,
                attributes: [.protectionKey: FileProtectionType.completeUnlessOpen]
            )
            let temporaryURL = directoryURL.appendingPathComponent("\(Self.storeFileIdentityFilename).tmp")
            try Data(token.utf8).write(to: temporaryURL, options: .atomic)
            try fileManager.setAttributes(
                [.protectionKey: FileProtectionType.completeUnlessOpen],
                ofItemAtPath: temporaryURL.path
            )
            if fileManager.fileExists(atPath: storeFileIdentityURL.path) {
                _ = try fileManager.replaceItemAt(
                    storeFileIdentityURL,
                    withItemAt: temporaryURL,
                    backupItemName: nil,
                    options: .usingNewMetadataOnly
                )
            } else {
                try fileManager.moveItem(at: temporaryURL, to: storeFileIdentityURL)
            }
            return token
        } catch {
            throw CollectionStoreManifestStoreError.writeFailure
        }
    }

    /// Reads the sidecar without creating it. Startup uses this operation to
    /// distinguish a verified existing store from a missing or replaced one;
    /// only a newly opened, explicitly selected store may mint the sidecar.
    func readStoreFileIdentity() throws -> String? {
        guard isUsable else { throw CollectionStoreManifestStoreError.storageLocationUnavailable }
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: storeFileIdentityURL.path) else { return nil }
        do {
            let value = try String(contentsOf: storeFileIdentityURL, encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty, !value.contains("/") else {
                throw CollectionStoreManifestStoreError.invalidStoreIdentity
            }
            return value
        } catch let error as CollectionStoreManifestStoreError {
            throw error
        } catch {
            throw CollectionStoreManifestStoreError.readFailure
        }
    }

    static func validateAttachmentTransition(
        from: CloudAttachmentState,
        to: CloudAttachmentState
    ) throws {
        if from == to { return }
        let allowed: Set<CloudAttachmentState>
        switch from {
        case .neverAttached:
            allowed = [.attached, .suspended, .conflict]
        case .attached:
            allowed = [.suspended, .conflict]
        case .suspended:
            allowed = [.attached, .conflict]
        case .conflict:
            allowed = [.attached, .suspended]
        }
        guard allowed.contains(to) else {
            throw CollectionStoreManifestStoreError.invalidAttachmentTransition(from: from, to: to)
        }
    }

    static func validateMigrationTransition(
        from: StoreMigrationState,
        to: StoreMigrationState
    ) throws {
        if from == to { return }
        let allowed: Set<StoreMigrationState>
        switch from {
        case .notStarted:
            allowed = [.copying]
        case .copying:
            allowed = [.copying, .validating]
        case .validating:
            allowed = [.validating, .committed]
        case .committed:
            allowed = []
        }
        guard allowed.contains(to) else {
            throw CollectionStoreManifestStoreError.invalidMigrationTransition(from: from, to: to)
        }
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

enum CollectionStoreLocationKind: String, Equatable, Sendable {
    case explicit
    case legacyDefault
}

struct CollectionStoreLocation: Equatable, Sendable {
    var url: URL
    var kind: CollectionStoreLocationKind
}

/// The current app used an unnamed structured configuration, whose default
/// store is resolved by SwiftData as `default.store` below Application Support.
/// This helper keeps discovery explicit and injectable; production startup must
/// call it before classifying an install as fresh.
enum CollectionStoreDiscovery {
    static func locations(
        applicationSupportURL: URL,
        explicitStructuredStoreURL: URL
    ) -> [CollectionStoreLocation] {
        var result = [
            CollectionStoreLocation(
                url: explicitStructuredStoreURL,
                kind: .explicit
            )
        ]
        let legacyURL = applicationSupportURL.appendingPathComponent("default.store")
        if legacyURL.standardizedFileURL != explicitStructuredStoreURL.standardizedFileURL {
            result.append(CollectionStoreLocation(url: legacyURL, kind: .legacyDefault))
        }
        return result
    }

    static func existingLocation(
        locations: [CollectionStoreLocation],
        fileManager: FileManager = .default
    ) -> CollectionStoreLocation? {
        locations.first { location in
            fileManager.fileExists(atPath: location.url.path)
                || fileManager.fileExists(atPath: "\(location.url.path)-wal")
                || fileManager.fileExists(atPath: "\(location.url.path)-shm")
        }
    }
}
