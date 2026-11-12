// Build with scripts/build_yugioh_publisher.sh.
// Local files only. This executable has no deployment or credential provisioning.
import CryptoKit
import Foundation

@main
enum YuGiOhCatalogPublisher {
    static func main() {
        do { try run() }
        catch {
            FileHandle.standardError.write(Data("Yu-Gi-Oh publication rejected: \(error)\n".utf8))
            exit(1)
        }
    }
    static func run() throws {
        let args = Array(CommandLine.arguments.dropFirst())
        guard let command = args.first, args.count % 2 == 1 else { throw Failure.arguments }
        var options: [String: String] = [:]
        for index in stride(from: 1, to: args.count, by: 2) {
            guard args[index].hasPrefix("--"), options[args[index]] == nil else { throw Failure.arguments }
            options[args[index]] = args[index + 1]
        }
        func required(_ name: String) throws -> String {
            guard let value = options["--" + name], !value.isEmpty else { throw Failure.arguments }
            return value
        }
        func file(_ name: String) throws -> URL { URL(fileURLWithPath: try required(name)) }
        let keyData = try read(file("keys"), limit: 32_768)
        let encodedKeys = try JSONDecoder().decode([String: String].self, from: keyData)
        let keys = try encodedKeys.mapValues { encoded in
            guard let raw = Data(base64Encoded: encoded) else { throw Failure.keys }
            return try Curve25519.Signing.PublicKey(rawRepresentation: raw)
        }
        guard !keys.isEmpty, Set(keys.values.map(\.rawRepresentation)).count == keys.count else { throw Failure.keys }
        func verified(_ url: URL) throws -> (Data, YuGiOhCandidateEnvelope, YuGiOhCandidateManifest) {
            let bytes = try read(url, limit: YuGiOhReleaseWire.maximumEnvelopeBytes)
            let envelope = try JSONDecoder().decode(YuGiOhCandidateEnvelope.self, from: bytes)
            let manifest = try YuGiOhReleaseWire.verify(envelope, keys: keys, state: .approved, now: .now)
            try validateCatalog(envelope.catalog, manifest: manifest)
            return (bytes, envelope, manifest)
        }
        switch command {
        case "verify", "export-parent":
            let (_, envelope, manifest) = try verified(file("input"))
            if let expected = options["--expected-revision"], Int(expected) != manifest.revision { throw Failure.revision }
            if command == "export-parent" { try envelope.catalog.write(to: file("output"), options: .atomic) }
            print(manifest.revision)
        case "approve":
            let bytes = try read(file("catalog"), limit: YuGiOhReleaseWire.maximumCatalogBytes)
            let catalog = try object(bytes)
            guard let revision = Int(try required("revision")), revision > 0,
                  let generation = catalog["generation"] as? String,
                  let captured = catalog["capturedAt"] as? String else { throw Failure.revision }
            let parentBytes: Data
            let parentRevision: Int
            let checkpointSHA256: String?
            let ancestors: [Int: String]?
            if let parent = options["--parent-release"] {
                let (_, envelope, manifest) = try verified(URL(fileURLWithPath: parent))
                parentBytes = envelope.catalog; parentRevision = manifest.revision
                checkpointSHA256 = manifest.checkpointBaseSHA256
                ancestors = manifest.ancestryIncludingSelf
            } else {
                parentBytes = try read(file("bundle"), limit: YuGiOhReleaseWire.maximumCatalogBytes)
                parentRevision = 0
                checkpointSHA256 = YuGiOhReleaseWire.hash(parentBytes)
                ancestors = nil
            }
            guard revision > parentRevision else { throw Failure.revision }
            try transition(from: parentBytes, to: bytes)
            let keyID = try required("key-id")
            let keyBytes = try read(file("private-key-file"), limit: 128)
            let key = try Curve25519.Signing.PrivateKey(rawRepresentation: keyBytes)
            guard keys[keyID]?.rawRepresentation == key.publicKey.rawRepresentation else { throw Failure.keys }
            let manifest = YuGiOhCandidateManifest(schemaVersion: 2, revision: revision, generation: generation,
                policyVersion: YuGiOhReleaseWire.policy, path: "yugioh/v1/releases/\(revision)/catalog.json",
                sha256: YuGiOhReleaseWire.hash(bytes), bytes: bytes.count, status: YuGiOhPublicationState.approved.rawValue,
                capturedAt: captured, parentSHA256: YuGiOhReleaseWire.hash(parentBytes), reviewID: try required("review-id"),
                parentRevision: parentRevision > 0 ? parentRevision : nil, checkpointSHA256: checkpointSHA256,
                ancestors: ancestors)
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
            let payload = try encoder.encode(manifest)
            let envelope = YuGiOhCandidateEnvelope(keyID: keyID, payload: YuGiOhReleaseWire.encodeURL(payload),
                signature: YuGiOhReleaseWire.encodeURL(try key.signature(for: payload)), catalog: bytes)
            _ = try YuGiOhReleaseWire.verify(envelope, keys: keys, state: .approved, now: .now)
            try validateCatalog(bytes, manifest: manifest)
            let signedBytes = try encoder.encode(envelope)
            guard signedBytes.count <= YuGiOhReleaseWire.maximumEnvelopeBytes else { throw YuGiOhCandidateError.oversized }
            try immutable(signedBytes, at: file("output"))
            print(revision)
        case "promote":
            let (bytes, envelope, manifest) = try verified(file("input"))
            let root = try file("site-root").appendingPathComponent("yugioh/v1")
            let pointer = root.appendingPathComponent("current.json")
            let parentBytes: Data
            let parentRevision: Int
            if FileManager.default.fileExists(atPath: pointer.path) {
                let (previousBytes, previous, previousManifest) = try verified(pointer)
                if previousManifest.revision == manifest.revision {
                    guard previousBytes == bytes else { throw Failure.immutable }
                    print(manifest.revision); return
                }
                guard manifest.revision > previousManifest.revision else { throw Failure.revision }
                if let ancestors = manifest.ancestors {
                    guard ancestors == previousManifest.ancestryIncludingSelf,
                          manifest.checkpointSHA256 == previousManifest.checkpointBaseSHA256 else { throw Failure.parent }
                }
                parentBytes = previous.catalog
                parentRevision = previousManifest.revision
            } else {
                parentBytes = try read(file("bundle"), limit: YuGiOhReleaseWire.maximumCatalogBytes)
                parentRevision = 0
            }
            guard manifest.parentSHA256 == YuGiOhReleaseWire.hash(parentBytes) else { throw Failure.parent }
            guard manifest.parentRevision == (parentRevision > 0 ? parentRevision : nil) else { throw Failure.parent }
            try transition(from: parentBytes, to: envelope.catalog)
            let release = root.appendingPathComponent("releases/\(manifest.revision)")
            try immutable(envelope.catalog, at: release.appendingPathComponent("catalog.json"))
            try immutable(bytes, at: release.appendingPathComponent("catalog-release.json"))
            // Re-read and verify before advancing any pointer. An interrupted
            // immutable upload leaves the old approved parent in place.
            _ = try verified(release.appendingPathComponent("catalog-release.json"))
            guard try read(release.appendingPathComponent("catalog.json"), limit: YuGiOhReleaseWire.maximumCatalogBytes) == envelope.catalog else { throw Failure.immutable }
            if FileManager.default.fileExists(atPath: pointer.path) {
                try read(pointer, limit: YuGiOhReleaseWire.maximumEnvelopeBytes).write(to: root.appendingPathComponent("previous.json"), options: .atomic)
            }
            try bytes.write(to: pointer, options: .atomic)
            print(manifest.revision)
        default: throw Failure.arguments
        }
    }

    enum Failure: Error { case arguments, keys, revision, parent, immutable, catalog }
    static func read(_ url: URL, limit: Int) throws -> Data {
        let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
        let bytes = try handle.read(upToCount: limit + 1) ?? Data()
        guard bytes.count <= limit else { throw YuGiOhCandidateError.oversized }
        return bytes
    }
    static func object(_ bytes: Data) throws -> [String: Any] {
        guard let object = try JSONSerialization.jsonObject(with: bytes) as? [String: Any] else { throw Failure.catalog }
        return object
    }
    static func immutable(_ bytes: Data, at url: URL) throws {
        if FileManager.default.fileExists(atPath: url.path) {
            guard try read(url, limit: YuGiOhReleaseWire.maximumEnvelopeBytes) == bytes else { throw Failure.immutable }
        } else {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let temporary = url.deletingLastPathComponent().appendingPathComponent(".yugioh-upload-\(UUID())")
            defer { try? FileManager.default.removeItem(at: temporary) }
            try bytes.write(to: temporary, options: .atomic)
            // Exclusive hard-link creation publishes complete bytes without
            // Foundation's unsupported atomic + withoutOverwriting combination.
            do { try FileManager.default.linkItem(at: temporary, to: url) }
            catch {
                guard (try? read(url, limit: YuGiOhReleaseWire.maximumEnvelopeBytes)) == bytes else { throw error }
            }
        }
    }
    static func validateCatalog(_ bytes: Data, manifest: YuGiOhCandidateManifest) throws {
        // Execute the real app loader, including every typed schema, identity,
        // edition, membership, quantity and automatic-eligibility predicate.
        _ = try YuGiOhCatalog(data: bytes)
        let catalog = try object(bytes)
        guard catalog["schemaVersion"] as? Int == 1, catalog["policyVersion"] as? String == YuGiOhReleaseWire.policy,
              catalog["generation"] as? String == manifest.generation,
              catalog["capturedAt"] as? String == manifest.capturedAt,
              let captured = YuGiOhReleaseWire.date(manifest.capturedAt),
              let marketRows = catalog["printings"] as? [[String: Any]], !marketRows.isEmpty else { throw Failure.catalog }
        let rows = marketRows + (catalog["referencePrintings"] as? [[String: Any]] ?? [])
        var timestamps = Set<String>()
        for row in rows {
            guard let members = row["m"] as? [[String: Any]] else { throw Failure.catalog }
            for member in members {
                guard let stamp = member["s"] as? String else { throw Failure.catalog }
                timestamps.insert(stamp)
            }
        }
        guard timestamps.allSatisfy({ YuGiOhReleaseWire.date($0).map { $0 <= captured } == true }) else { throw Failure.catalog }
    }
    static func transition(from parent: Data, to next: Data) throws {
        let old = try YuGiOhCatalog(data: parent)
        let new = try YuGiOhCatalog(data: next)
        guard old.generation != new.generation || parent == next else { throw Failure.catalog }
        try YuGiOhCatalog.validateTransition(from: old, to: new, reviewedSameSnapshot: true)
    }
}
