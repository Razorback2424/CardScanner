// Read-only preflight of a membership batch against a verified production
// envelope. This is a descriptor-union check, NOT a full live publisher build.
import CryptoKit
import Foundation
import PokemonCatalogCore

let arguments = CommandLine.arguments
guard arguments.count == 6 else {
    fatalError("Usage: audit ENVELOPE PIN_XCCONFIG ISOLATED_CANDIDATE_ROOT PRODUCTION_INPUT REPORT")
}
let envelopeData = try Data(contentsOf: URL(fileURLWithPath: arguments[1]))
let configuration = try String(contentsOfFile: arguments[2], encoding: .utf8)
guard let keyLine = configuration.split(separator: "\n").first(where: {
    $0.hasPrefix("POKEMON_CATALOG_PINNED_KEYS = ")
}) else { fatalError("Missing public key pins") }
let rawPins = keyLine.dropFirst("POKEMON_CATALOG_PINNED_KEYS = ".count)
let keys = try rawPins.split(separator: ";").map { entry -> PokemonCatalogSignatureVerifier.PinnedKey in
    let fields = entry.split(separator: ":", maxSplits: 1)
    guard fields.count == 2, let bytes = PokemonCatalogBase64URL.decode(String(fields[1])) else {
        fatalError("Invalid public key pin")
    }
    return .init(id: String(fields[0]), publicKey: try .init(rawRepresentation: bytes))
}
let envelope = try PokemonCatalogJSON.decode(PokemonCatalogReleaseEnvelope.self, from: envelopeData)
let active = try PokemonCatalogSignatureVerifier.verify(envelope: envelope, keys: keys)
let candidateRoot = URL(fileURLWithPath: arguments[3], isDirectory: true)
let payloadData = try Data(contentsOf: candidateRoot.appendingPathComponent("catalog-payload.json"))
let batch = try PokemonCatalogJSON.decode(PokemonCatalogRelease.self, from: payloadData)
let snapshot = try PokemonCatalogJSON.decode(PokemonCatalogSnapshot.self,
    from: Data(contentsOf: candidateRoot.appendingPathComponent("pokemon-catalog-snapshot.json")))
let review = try PokemonCatalogJSON.decode(PokemonCatalogReviewReport.self,
    from: Data(contentsOf: candidateRoot.appendingPathComponent("review-report.json")))
try PokemonCatalogCandidateValidator.validate(.init(release: batch, snapshot: snapshot, report: review))
let inputData = try Data(contentsOf: URL(fileURLWithPath: arguments[4]))
let inputs = try PokemonCatalogJSON.decode(PokemonCatalogHumanInputFile.self, from: inputData)

let activeIDs = Set(active.sets.map { $0.providerSetID })
let batchIDs = Set(batch.sets.map { $0.providerSetID })
precondition(activeIDs.isDisjoint(with: batchIDs), "Batch must contain only new descriptors")
let merged = PokemonCatalogRelease(catalogKind: PokemonCatalogRelease.currentCatalogKind,
    revision: active.revision + 1, generatedAt: Date(), sets: active.sets + batch.sets)
try PokemonCatalogReleaseValidator.validate(merged)
let byID = Dictionary(uniqueKeysWithValues: merged.sets.map { ($0.providerSetID, $0) })
precondition(Set(inputs.sets.map { $0.providerSetID }) == Set(byID.keys), "Production input/descriptor coverage differs")
for input in inputs.sets {
    let descriptor = byID[input.providerSetID]!
    precondition(input.recognitionKind == descriptor.recognitionKind)
    precondition(input.scanEnabled == descriptor.scanEnabled)
    precondition(input.membershipRecognition == descriptor.membershipRecognition, "Membership differs from production input")
}
let classification = PokemonCatalogChangeClassifier.classify(previousRelease: active, currentRelease: merged)
precondition(classification.changeClass == .newSet)
precondition(classification.changedProviderSetIDs.isEmpty, "Existing descriptor changed")
precondition(classification.addedProviderSetIDs.count == batch.sets.count)
let members = batch.sets.flatMap { $0.membershipRecognition?.members ?? [] }
precondition(Set(members.map { $0.providerCardID }).count == members.count)
let report: [String: Any] = [
    "schemaVersion": 1,
    "date": "2026-11-02",
    "scope": "Verified production signature and full descriptor union; not a fresh full-provider candidate",
    "activeRevision": active.revision,
    "activeEnvelopeSHA256": SHA256.hash(data: envelopeData).map { String(format: "%02x", $0) }.joined(),
    "productionInputSHA256": SHA256.hash(data: inputData).map { String(format: "%02x", $0) }.joined(),
    "isolatedPayloadSHA256": SHA256.hash(data: payloadData).map { String(format: "%02x", $0) }.joined(),
    "verifiedKeyIDPresent": !envelope.keyID.isEmpty,
    "activeDescriptorsPreserved": active.sets.count,
    "newDescriptors": batch.sets.count,
    "newMemberships": members.count,
    "unionDescriptors": merged.sets.count,
    "normalChangeClass": classification.changeClass.rawValue,
    "productionInputMembershipMatches": true,
    "isolatedCandidateArtifactsConsistent": true,
    "signedOrPublished": false,
    "remainingGates": ["Full live production candidate", "Protected signing and publication", "Installed scanner/portfolio and exact-price validation"]
]
let reportURL = URL(fileURLWithPath: arguments[5])
try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: reportURL)
print("Verified revision \(active.revision); preserved \(active.sets.count) descriptors; \(members.count) memberships / \(merged.sets.count) union descriptors; protected newSet route.")
