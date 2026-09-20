import Foundation

/// The one provider-content identity shared by the publisher and the device.
///
/// This is deliberately separate from the app's lightweight set probe. The
/// signed value describes the detailed inputs needed to reproduce a checklist;
/// the probe only decides whether downloading those details is worth doing.
public enum PokemonCatalogProviderFingerprint {
    public static let version = "provider-content-v1"

    public static func v1(
        providerSet: PokemonCatalogProviderSet,
        cardDetails: [String: PokemonCatalogProviderCard]
    ) -> String? {
        let detailsByID = Dictionary(
            cardDetails.map { (normalizeID($0.key), $0.value) },
            uniquingKeysWith: { first, _ in first }
        )
        var fields: [String] = [
            version,
            value(normalizeID(providerSet.id)),
            value(providerSet.name),
            // Only raw provider payload values belong here. Publisher-side
            // resolvedLogo/resolvedSymbol are descriptor enrichment and are
            // intentionally excluded so the device can reproduce this hash.
            value(providerSet.logo),
            value(providerSet.symbol),
            value(providerSet.releaseDate)
        ]
        appendCount(providerSet.cardCount, to: &fields)

        let cards = providerSet.cards.sorted {
            let left = (normalizeID($0.id), normalize($0.localID), normalize($0.name))
            let right = (normalizeID($1.id), normalize($1.localID), normalize($1.name))
            if left.0 != right.0 { return left.0 < right.0 }
            if left.1 != right.1 { return left.1 < right.1 }
            return left.2 < right.2
        }
        for brief in cards {
            guard let detail = detailsByID[normalizeID(brief.id)] else { return nil }
            fields += [
                value(normalizeID(brief.id)),
                value(brief.localID),
                value(brief.name),
                value(brief.image)
            ]
            // The brief is the identity/artwork input used by the materializer;
            // the detail contributes only variant expansion evidence.
            if let variants = detail.variants {
                fields += [
                    value(variants.firstEdition),
                    value(variants.holo),
                    value(variants.normal),
                    value(variants.reverse),
                    value(variants.wPromo)
                ]
            } else {
                fields.append(value(nil as Bool?))
                fields.append(value(nil as Bool?))
                fields.append(value(nil as Bool?))
                fields.append(value(nil as Bool?))
                fields.append(value(nil as Bool?))
            }

            let detailed = (detail.variantsDetailed ?? []).sorted {
                detailedSortKey($0).lexicographicallyPrecedes(detailedSortKey($1))
            }
            fields.append(value(detailed.count))
            for variant in detailed {
                fields += [
                    value(variant.type),
                    value(variant.subtype),
                    valueList(variant.stamp),
                    value(variant.foil),
                    value(variant.size),
                    value(variant.variantID),
                    valueList(variant.languages)
                ]
            }
        }
        return PokemonCatalogFingerprint.string(fields.joined(separator: "\u{1F}"))
    }

    private static func appendCount(
        _ count: PokemonCatalogProviderCardCount?,
        to fields: inout [String]
    ) {
        guard let count else {
            fields.append(contentsOf: repeatElement(value(nil as Int?), count: 6))
            return
        }
        fields += [
            value(count.total), value(count.official), value(count.normal),
            value(count.reverse), value(count.holo), value(count.firstEd)
        ]
    }

    private static func detailedSortKey(
        _ variant: PokemonCatalogProviderDetailedVariant
    ) -> String {
        [
            value(variant.type), value(variant.subtype), valueList(variant.stamp),
            value(variant.foil), value(variant.size), value(variant.variantID),
            valueList(variant.languages)
        ].joined(separator: "\u{1E}")
    }

    private static func normalizeID(_ value: String) -> String {
        normalize(value).lowercased()
    }

    private static func normalize(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func value(_ value: String?) -> String {
        guard let value else { return "<missing>" }
        let normalized = normalize(value)
        return normalized.isEmpty ? "<empty>" : normalized
    }

    private static func value(_ value: Int) -> String { String(value) }

    private static func value(_ value: Int?) -> String {
        value.map(String.init) ?? "<missing>"
    }

    private static func value(_ value: Bool) -> String { value ? "true" : "false" }

    private static func value(_ value: Bool?) -> String {
        value.map(Self.value) ?? "<missing>"
    }

    private static func valueList(_ values: [String]?) -> String {
        guard let values else { return "<missing>" }
        let normalized = values.map(normalize).sorted()
        return normalized.isEmpty ? "<empty>" : normalized.joined(separator: "\u{1E}")
    }
}
