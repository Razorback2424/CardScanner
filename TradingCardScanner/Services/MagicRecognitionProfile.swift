import CryptoKit
import Foundation
import MagicCatalogCore

/// App-local classification only. These values do not extend signed schema 1 authority.
/// Unknown wire values throw on decoding rather than falling back to an enabled route.
enum MagicRecognitionRoute: String, Codable, Sendable {
    case modernFooter
    case legacyCollectorNumber
    case legacyNoCollectorNumber
    case unknown
}

struct MagicRecognitionProfile: Equatable, Sendable {
    let route: MagicRecognitionRoute
    let acquisitionEnabled: Bool

    static let disabled = Self(route: .unknown, acquisitionEnabled: false)
}

/// Exact provider printing identity, independent of finish. Overrides describe reviewed
/// visible features; they cannot enable acquisition or move a printing to another set.
struct MagicRecognitionPrintingOverride: Codable, Equatable, Sendable {
    let printingID: String
    let setCode: String
    let route: MagicRecognitionRoute
    let reviewReference: String
}

/// Immutable local projection. No card-level completeness or freshness is implied by
/// its generation or by the optional index generation; those gates belong to the pilot.
struct MagicRecognitionProfileSnapshot: Sendable {
    static let currentVersion = 1
    // Official Exodus release day: https://mtg-jp.com/products/0000112/
    static let collectorNumberStart = "1998-06-15"
    static let supportedLegacyLayouts: Set<String> = ["normal"]

    let version: Int
    let generation: String
    let catalogContext: String
    let catalogRevision: Int?
    let indexGeneration: String?
    private let defaults: [String: MagicRecognitionProfile]
    private let overridesByID: [UUID: MagicRecognitionPrintingOverride]

    enum ValidationError: Error {
        case unsupportedVersion
        case duplicateSet
        case invalidOverride
        case invalidIndexGeneration
        case staleActivation
    }

    init(descriptors: [MagicCatalogSetDescriptor], version: Int = currentVersion,
         overrides: [MagicRecognitionPrintingOverride] = [], indexGeneration: String? = nil,
         catalogRevision: Int? = nil) throws {
        guard version == Self.currentVersion else { throw ValidationError.unsupportedVersion }
        if let indexGeneration, indexGeneration.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw ValidationError.invalidIndexGeneration
        }
        var defaults: [String: MagicRecognitionProfile] = [:]
        var setIDs: Set<String> = []
        for descriptor in descriptors {
            let code = MagicCatalogPolicy.normalizedCode(descriptor.code)
            guard !code.isEmpty, defaults[code] == nil,
                  setIDs.insert(descriptor.scryfallSetID.lowercased()).inserted else {
                throw ValidationError.duplicateSet
            }
            defaults[code] = Self.defaultProfile(descriptor)
        }
        var byID: [UUID: MagicRecognitionPrintingOverride] = [:]
        for override in overrides {
            let code = MagicCatalogPolicy.normalizedCode(override.setCode)
            guard let id = UUID(uuidString: override.printingID), byID[id] == nil,
                  defaults[code] != nil,
                  !override.reviewReference.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ValidationError.invalidOverride
            }
            byID[id] = .init(printingID: id.uuidString.lowercased(), setCode: code,
                             route: override.route, reviewReference: override.reviewReference)
        }
        let sortedDescriptors = descriptors.sorted {
            MagicCatalogPolicy.normalizedCode($0.code) < MagicCatalogPolicy.normalizedCode($1.code)
        }
        let context = Self.digest(try MagicCatalogJSON.encode(sortedDescriptors))
        let identity = Identity(version: version, catalogContext: context, catalogRevision: catalogRevision,
                                indexGeneration: indexGeneration,
                                overrides: byID.values.sorted { $0.printingID < $1.printingID })
        self.version = version
        self.catalogContext = context
        self.catalogRevision = catalogRevision
        self.indexGeneration = indexGeneration
        self.defaults = defaults
        self.overridesByID = byID
        self.generation = "magic-local-profiles-v\(version)-" + Self.digest(try MagicCatalogJSON.encode(identity))
    }

    func profile(setCode: String, printingID: String? = nil) -> MagicRecognitionProfile {
        let code = MagicCatalogPolicy.normalizedCode(setCode)
        guard let base = defaults[code] else { return .disabled }
        guard let printingID else { return base }
        guard let id = UUID(uuidString: printingID) else { return .disabled }
        guard let override = overridesByID[id] else { return base }
        guard override.setCode == code else { return .disabled }
        // Historical/unknown overrides always remain disabled in B1. A modern
        // classification can only retain existing modern descriptor authority.
        return .init(route: override.route,
                     acquisitionEnabled: override.route == .modernFooter && base.acquisitionEnabled)
    }

    private static func defaultProfile(_ descriptor: MagicCatalogSetDescriptor) -> MagicRecognitionProfile {
        // Keep the existing modern projection exactly, including token/art routing.
        if descriptor.scanEnabled {
            return .init(route: .modernFooter, acquisitionEnabled: true)
        }
        guard descriptor.browseEnabled, descriptor.routingKind == nil,
              let day = descriptor.releaseDate, MagicCatalogDate.parseDay(day) != nil else { return .disabled }
        let route: MagicRecognitionRoute
        if day >= MagicCatalogPolicy.modernFooterStart { route = .modernFooter }
        else if day >= collectorNumberStart { route = .legacyCollectorNumber }
        else { route = .legacyNoCollectorNumber }
        return .init(route: route, acquisitionEnabled: false)
    }

    private struct Identity: Encodable {
        let version: Int
        let catalogContext: String
        let catalogRevision: Int?
        let indexGeneration: String?
        let overrides: [MagicRecognitionPrintingOverride]
    }

    private static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

/// Compare-and-publish activation for future local historical requests/choices.
/// Callers capture `generation` and recheck it at lookup and immediately before save.
/// This store has no OCR or acquisition registration in the inert B1 slice.
actor MagicRecognitionProfileStore {
    private(set) var snapshot: MagicRecognitionProfileSnapshot

    init(snapshot: MagicRecognitionProfileSnapshot) {
        self.snapshot = snapshot
    }

    func isCurrent(_ capturedGeneration: String) -> Bool {
        snapshot.generation == capturedGeneration
    }

    @discardableResult
    func activate(_ next: MagicRecognitionProfileSnapshot, expectedGeneration: String) throws -> Bool {
        guard isCurrent(expectedGeneration) else {
            throw MagicRecognitionProfileSnapshot.ValidationError.staleActivation
        }
        guard next.generation != snapshot.generation else { return false }
        snapshot = next
        return true
    }
}
