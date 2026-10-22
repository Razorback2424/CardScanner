// Compile with TradingCardScanner/Games/YuGiOh/YuGiOhReleaseWire.swift.
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
            if let parent = options["--parent-release"] {
                let (_, envelope, manifest) = try verified(URL(fileURLWithPath: parent))
                parentBytes = envelope.catalog; parentRevision = manifest.revision
            } else {
                parentBytes = try read(file("bundle"), limit: YuGiOhReleaseWire.maximumCatalogBytes)
                parentRevision = 0
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
                capturedAt: captured, parentSHA256: YuGiOhReleaseWire.hash(parentBytes), reviewID: try required("review-id"))
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
            let payload = try encoder.encode(manifest)
            let envelope = YuGiOhCandidateEnvelope(keyID: keyID, payload: YuGiOhReleaseWire.encodeURL(payload),
                signature: YuGiOhReleaseWire.encodeURL(try key.signature(for: payload)), catalog: bytes)
            _ = try YuGiOhReleaseWire.verify(envelope, keys: keys, state: .approved, now: .now)
            try validateCatalog(bytes, manifest: manifest)
            try immutable(encoder.encode(envelope), at: file("output"))
            print(revision)
        case "promote":
            let (bytes, envelope, manifest) = try verified(file("input"))
            let root = try file("site-root").appendingPathComponent("yugioh/v1")
            let pointer = root.appendingPathComponent("current.json")
            let parentBytes: Data
            if FileManager.default.fileExists(atPath: pointer.path) {
                let (previousBytes, previous, previousManifest) = try verified(pointer)
                if previousManifest.revision == manifest.revision {
                    guard previousBytes == bytes else { throw Failure.immutable }
                    print(manifest.revision); return
                }
                guard manifest.revision > previousManifest.revision else { throw Failure.revision }
                parentBytes = previous.catalog
            } else { parentBytes = try read(file("bundle"), limit: YuGiOhReleaseWire.maximumCatalogBytes) }
            guard manifest.parentSHA256 == YuGiOhReleaseWire.hash(parentBytes) else { throw Failure.parent }
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
        let catalog = try object(bytes)
        guard catalog["schemaVersion"] as? Int == 1, catalog["policyVersion"] as? String == YuGiOhReleaseWire.policy,
              catalog["generation"] as? String == manifest.generation,
              catalog["capturedAt"] as? String == manifest.capturedAt,
              let captured = YuGiOhReleaseWire.date(manifest.capturedAt),
              let rows = catalog["printings"] as? [[String: Any]], !rows.isEmpty else { throw Failure.catalog }
        var ids = Set<String>()
        for row in rows {
            guard let id = row["id"] as? String, UUID(uuidString: id) != nil, ids.insert(id).inserted,
                  let editions = row["e"] as? [String], Set(editions).isSubset(of: ["yugioh1stEdition", "yugiohUnlimited", "yugiohLimited"]),
                  let members = row["m"] as? [[String: Any]] else { throw Failure.catalog }
            for member in members {
                guard let edition = member["e"] as? String, editions.contains(edition),
                      let stamp = member["s"] as? String, let date = YuGiOhReleaseWire.date(stamp), date <= captured,
                      let hash = member["h"] as? String, hash.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil else { throw Failure.catalog }
            }
        }
    }
    static func transition(from parent: Data, to next: Data) throws {
        let old = try object(parent), new = try object(next)
        guard let oldStamp = old["capturedAt"] as? String, let oldDate = YuGiOhReleaseWire.date(oldStamp),
              let newStamp = new["capturedAt"] as? String, let newDate = YuGiOhReleaseWire.date(newStamp), newDate >= oldDate,
              old["generation"] as? String != new["generation"] as? String || parent == next,
              let oldRows = old["printings"] as? [[String: Any]], let newRows = new["printings"] as? [[String: Any]],
              let oldCards = old["cards"] as? [[String: Any]], let newCards = new["cards"] as? [[String: Any]] else { throw Failure.catalog }
        let grouped = Dictionary(grouping: newRows, by: { $0["id"] as? String ?? "" })
        for row in oldRows {
            guard let id = row["id"] as? String, let matches = grouped[id], matches.count == 1, let other = matches.first,
                  let oldIndex = row["k"] as? Int, oldCards.indices.contains(oldIndex),
                  let newIndex = other["k"] as? Int, newCards.indices.contains(newIndex),
                  oldCards[oldIndex]["id"] as? String == newCards[newIndex]["id"] as? String else { throw Failure.catalog }
            for field in ["p", "c", "g", "r", "art", "pn"] {
                guard NSDictionary(dictionary: [field: row[field] ?? NSNull()]) == NSDictionary(dictionary: [field: other[field] ?? NSNull()]) else { throw Failure.catalog }
            }
        }
    }
}
