import Foundation

/// Exact, reviewed physical-language exclusions. These live beside descriptors
/// so correcting a legacy card never changes its historical recognition route.
public struct PokemonCatalogEnglishExclusions: Codable, Equatable, Sendable {
    public struct Card: Codable, Equatable, Sendable {
        public let providerCardID: String
        public let canonicalName: String
        public let evidenceURLs: [String]

        public init(providerCardID: String, canonicalName: String, evidenceURLs: [String]) {
            self.providerCardID = providerCardID
            self.canonicalName = canonicalName
            self.evidenceURLs = evidenceURLs
        }
    }

    public struct Variant: Codable, Equatable, Sendable {
        public let providerCardID: String
        public let canonicalName: String
        public let variantID: String
        public let providerType: String
        public let providerSize: String
        public let providerStamps: [String]
        public let physicalLanguage: String
        public let evidenceURLs: [String]

        public init(providerCardID: String, canonicalName: String, variantID: String,
                    providerType: String, providerSize: String, providerStamps: [String],
                    physicalLanguage: String, evidenceURLs: [String]) {
            self.providerCardID = providerCardID
            self.canonicalName = canonicalName
            self.variantID = variantID
            self.providerType = providerType
            self.providerSize = providerSize
            self.providerStamps = providerStamps
            self.physicalLanguage = physicalLanguage
            self.evidenceURLs = evidenceURLs
        }

        public func matches(type: String?, size: String?, foil: String?, stamps: [String]?, subtype: String?) -> Bool {
            type == providerType && size == providerSize && (foil ?? "").isEmpty
                && (subtype == nil || subtype == "unlimited")
                && (stamps ?? []).sorted() == providerStamps.sorted()
        }
    }

    public let cards: [Card]
    public let variants: [Variant]

    public init(cards: [Card] = [], variants: [Variant] = []) {
        self.cards = cards
        self.variants = variants
    }

    public func excludes(cardID: String, variantID: String? = nil) -> Bool {
        cards.contains { $0.providerCardID == cardID }
            || variants.contains { $0.providerCardID == cardID && $0.variantID == variantID }
    }

    public var providerSetIDs: Set<String> {
        Set((cards.map(\.providerCardID) + variants.map(\.providerCardID)).compactMap {
            $0.split(separator: "-", maxSplits: 1).first.map(String.init)
        })
    }

    public func validate() throws {
        func validIdentity(_ id: String, _ name: String, _ urls: [String]) -> Bool {
            let parts = id.split(separator: "-", maxSplits: 1)
            let hosts = urls.compactMap { raw -> String? in
                guard let url = URL(string: raw), url.scheme == "https", url.user == nil,
                      url.password == nil, !url.path.isEmpty else { return nil }
                return url.host?.lowercased()
            }
            return parts.count == 2 && !PokemonCatalogTextNormalization.canonicalMembershipName(name).isEmpty
                && hosts.count >= 2 && hosts.count == urls.count && Set(hosts).count == hosts.count
        }
        let cardIDs = cards.map(\.providerCardID)
        let variantKeys = variants.map { $0.providerCardID + ":" + $0.variantID }
        guard Set(cardIDs).count == cardIDs.count, Set(variantKeys).count == variantKeys.count,
              cards.allSatisfy({ validIdentity($0.providerCardID, $0.canonicalName, $0.evidenceURLs) }),
              variants.allSatisfy({ row in
                  validIdentity(row.providerCardID, row.canonicalName, row.evidenceURLs)
                    && !cardIDs.contains(row.providerCardID)
                    && ["normal", "holo", "reverse"].contains(row.providerType)
                    && row.providerSize == "standard" && !row.providerStamps.isEmpty
                    && Set(row.providerStamps).count == row.providerStamps.count
                    && row.providerStamps.allSatisfy { !$0.isEmpty && $0 != "1st-edition"
                        && $0 == $0.lowercased() && $0.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" } }
                    && row.variantID == "pokemonStamp|\(row.providerType)|\(row.providerStamps.sorted().joined(separator: ","))|"
                    && ["pt", "nl", "de", "es", "it", "fr", "zh", "ko", "ja", "pl"].contains(row.physicalLanguage)
              }) else {
            throw PokemonCatalogReleaseValidator.ValidationError.invalidDescriptor("invalid English-only exclusions")
        }
    }
}
