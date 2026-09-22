import Foundation

/// The two artwork files published by the local set-artwork catalog.
enum PokemonSetArtworkKind: String, Sendable {
    case logo
    case symbol
}

/// Provider-owned artwork fallbacks for the Browse catalog.
///
/// The provider identity stays in `CatalogSet` and `CatalogCardSummary`; this
/// type only derives alternate sources from that identity. Keeping the policy
/// here means a provider can be replaced without changing every view that
/// displays a card or set.
enum PokemonArtworkFallbacks {
    enum Candidate: Equatable, Sendable {
        case remote(URL)
        case bundled(String)
    }

    struct SetSource: Equatable, Sendable {
        let candidates: [Candidate]
    }

    /// The source repository uses a few historical ids that do not exactly
    /// match TCGdex. This compatibility map is only for legacy snapshots that
    /// predate signed `bundledArtworkSourceID` metadata; new mappings belong
    /// in the signed catalog descriptor.
    private static let localSourceIDs: [String: String] = [
        "base1": "base1",
        "bog": "bp",
        "cel25cc": "cel25c",
        "me02": "me2",
        "sm3.5": "sm35",
        "sm7.5": "sm75",
        "sma": "sma",
        "sv05": "sv5",
        "sv07": "sv7",
        "sv08": "sv8",
        "sv08.5": "sv8pt5",
        "sve": "sve",
        "swsh9tg": "swsh9tg",
        "swsh10tg": "swsh10tg",
        "swsh11tg": "swsh11tg",
        "swsh12.5gg": "swsh12pt5gg",
        "swsh12tg": "swsh12tg",
        "swsh4.5sv": "swsh45sv"
    ]

    static func localAssetName(
        forProviderID providerID: String,
        sourceID: String? = nil,
        kind: PokemonSetArtworkKind
    ) -> String? {
        let normalizedID = providerID.lowercased()
        let hasBundledArtwork: Bool
        if let sourceID {
            hasBundledArtwork = !sourceID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        } else {
            hasBundledArtwork = localSourceIDs[normalizedID] != nil
        }
        guard hasBundledArtwork else { return nil }

        // `sourceID` identifies the reviewed source artifact; the compiled
        // asset name remains keyed by provider ID for compatibility with the
        // existing asset catalog and its generated names.
        let safeID = normalizedID.replacingOccurrences(of: ".", with: "_")
        return "PokemonSetArtwork_\(safeID)_\(kind.rawValue)"
    }

    static func setSource(
        for set: CatalogSet,
        kind: PokemonSetArtworkKind
    ) -> SetSource {
        let requestedURL = kind == .logo ? set.logoURL : set.symbolURL
        let alternateURL = kind == .logo ? set.symbolURL : set.logoURL
        let alternateKind: PokemonSetArtworkKind = kind == .logo ? .symbol : .logo
        var candidates: [Candidate] = []

        func append(_ candidate: Candidate?) {
            guard let candidate, !candidates.contains(candidate) else { return }
            candidates.append(candidate)
        }

        func appendRemoteVariants(_ url: URL) {
            // Catalog releases preserve the provider's extensionless TCGdex
            // stems. The set-artwork CDN answers those stems with HTML, so
            // try the renderable PNG derivative before the original URL.
            if let explicitPNGURL = Self.explicitPNGURL(from: url) {
                append(.remote(explicitPNGURL))
            }
            append(.remote(url))
            guard let extensionlessURL = Self.extensionlessPNGURL(from: url) else { return }
            append(.remote(extensionlessURL))
            // The current assets host answers the bare stem with a short HTML
            // guidance response, while its explicit WebP derivative is the
            // renderable content-negotiated form. Keep the bare stem for
            // providers/edge caches that do negotiate it; the image cache
            // validates decoding before persisting any response.
            append(Self.webpURL(fromExtensionlessPNGURL: extensionlessURL).map(Candidate.remote))
        }

        func appendRemote(_ url: URL?, includingSymbolPrefixSibling: Bool = false) {
            guard let url else { return }
            appendRemoteVariants(url)
            guard includingSymbolPrefixSibling,
                  let siblingURL = Self.siblingSymbolPrefixURL(from: url) else {
                return
            }
            appendRemoteVariants(siblingURL)
        }

        // The requested provider artwork is authoritative when it exists. A
        // bundled copy of that same kind is next so an offline set directory
        // cannot make a tile wait for a network timeout before it can render.
        appendRemote(requestedURL, includingSymbolPrefixSibling: kind == .symbol)
        if set.game == .pokemon {
            append(
                localAssetName(
                    forProviderID: set.providerID,
                    sourceID: set.bundledArtworkSourceID,
                    kind: kind
                ).map(Candidate.bundled)
            )
        }

        // Symbols and logos are visually interchangeable only as a last resort.
        appendRemote(alternateURL, includingSymbolPrefixSibling: alternateKind == .symbol)
        if set.game == .pokemon {
            append(
                localAssetName(
                    forProviderID: set.providerID,
                    sourceID: set.bundledArtworkSourceID,
                    kind: alternateKind
                ).map(Candidate.bundled)
            )
        }

        // Card artwork is intentionally a sequential last resort. The
        // publisher stores at most three already-known card image URLs in the
        // snapshot so a missing set logo never turns into a collage or another
        // network discovery policy on the device.
        if set.game == .pokemon {
            for url in set.artworkFallbackURLs ?? [] {
                append(.remote(url))
            }
        }

        return SetSource(candidates: candidates)
    }

    /// TCGdex may omit a renderable `.png` derivative and answer the bare stem
    /// with HTML guidance. Preserve that compatibility rung, then try the
    /// explicit `.webp` derivative; `CatalogImageCache` rejects non-image bodies.
    private static func extensionlessPNGURL(from url: URL) -> URL? {
        guard url.host?.lowercased() == "assets.tcgdex.net",
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.path.lowercased().hasSuffix(".png") else {
            return nil
        }
        components.path.removeLast(4)
        return components.url
    }

    private static func explicitPNGURL(from url: URL) -> URL? {
        guard url.host?.lowercased() == "assets.tcgdex.net",
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              !components.path.isEmpty,
              !components.path.hasSuffix("/"),
              url.pathExtension.isEmpty else {
            return nil
        }
        components.path.append(".png")
        return components.url
    }

    private static func webpURL(fromExtensionlessPNGURL url: URL) -> URL? {
        guard url.host?.lowercased() == "assets.tcgdex.net" else { return nil }
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        components.path.append(".webp")
        return components.url
    }

    /// TCGdex snapshot symbols use both `/univ/` and `/en/` path prefixes.
    /// Neither prefix is universally authoritative, so keep the stored URL
    /// first and add its sibling only for symbol candidates.
    private static func siblingSymbolPrefixURL(from url: URL) -> URL? {
        guard url.host?.lowercased() == "assets.tcgdex.net",
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }

        let prefix: String
        let siblingPrefix: String
        if components.path.hasPrefix("/univ/") {
            prefix = "/univ/"
            siblingPrefix = "/en/"
        } else if components.path.hasPrefix("/en/") {
            prefix = "/en/"
            siblingPrefix = "/univ/"
        } else {
            return nil
        }
        components.path = siblingPrefix + String(components.path.dropFirst(prefix.count))
        return components.url
    }
}

/// The provider order for a card artwork request. TCGdex remains authoritative
/// when present; the derived Limitless URL is always the last remote candidate.
struct CatalogCardArtworkSource: Equatable, Sendable {
    let primaryURL: URL?
    let fallbacks: [URL]

    init(
        game: CardGame?,
        setCode: String?,
        collectorNumber: String?,
        thumbnailURL: URL?,
        imageURL: URL?,
        prefersFullSize: Bool,
        limitlessArtworkAuthorized: Bool? = nil
    ) {
        let providerURLs = prefersFullSize
            ? [imageURL, thumbnailURL]
            : [thumbnailURL, imageURL]
        let derivedURL: URL? = {
            guard game == .pokemon,
                  let setCode,
                  let collectorNumber,
                  let limitless = LimitlessArtwork.urls(
                      setCode: setCode,
                      collectorNumber: collectorNumber,
                      authorizedBySignedRegistry: limitlessArtworkAuthorized
                  ) else {
                return nil
            }
            return prefersFullSize ? limitless.full : limitless.small
        }()
        let urls = Self.uniqueURLs(providerURLs + [derivedURL])
        primaryURL = urls.first
        fallbacks = Array(urls.dropFirst())
    }

    var remoteCandidates: [PokemonArtworkFallbacks.Candidate] {
        var seen: Set<URL> = []
        return ([primaryURL] + fallbacks.map(Optional.some)).compactMap { url in
            guard let url, seen.insert(url).inserted else { return nil }
            return .remote(url)
        }
    }

    private static func uniqueURLs(_ urls: [URL?]) -> [URL] {
        var seen = Set<URL>()
        return urls.compactMap { url in
            guard let url, seen.insert(url).inserted else { return nil }
            return url
        }
    }
}

/// Pure derivation of the English TPCi artwork paths used by Limitless.
///
/// Limitless returns a 403 for unknown card keys. The closed set allow-list
/// avoids turning arbitrary OCR or imported text into a third-party request,
/// while still allowing the provider's known TPCi-era catalog to grow without
/// baking card URLs into the bundled snapshot.
enum LimitlessArtwork {
    private static let baseURL = "https://limitlesstcg.nyc3.cdn.digitaloceanspaces.com/tpci"

    /// Known English TPCi-era set codes. Pre-TPCi sets and the explicitly
    /// unsupported sets are intentionally absent. A code can still have no
    /// individual image on Limitless; the image loader treats that as a normal
    /// terminal failure and preserves the placeholder.
    static let supportedSetCodes: Set<String> = [
        "HS", "UL", "UD", "TM",
        "BLW", "EPO", "NVI", "NXD", "DEX", "DRX", "BCR", "PLS", "PLF", "PLB", "LTR",
        "CL", "DCR", "DRV",
        "XY", "FLF", "FFI", "PHF", "PRC", "ROS", "AOR", "BKT", "BKP", "FCO", "STS", "EVO",
        "KSS",
        "SUM", "GRI", "BUS", "SLG", "CIN", "UPR", "FLI", "CES", "DRM", "LOT", "TEU", "CEL",
        "UNB", "UNM", "HIF", "CEC", "GEN", "FUT2020",
        "SSH", "RCL", "DAA", "CPA", "VIV", "SHF", "BST", "CRE", "EVS", "FST", "BRS",
        "ASR", "LOR", "SIT", "CRZ", "PGO",
        "SVI", "PAL", "OBF", "MEW", "PAR", "PAF", "TEF", "TWM", "SFA", "SCR", "SSP",
        "PRE", "JTG", "DRI", "BLK", "WHT", "SVE",
        "SMA", "MEG", "PFL", "ASC", "POR", "CRI", "PBL", "MEE"
    ]

    /// Printed keys that are intentionally outside the current TPCi allow-list
    /// and therefore need an explicit future artwork decision before they can
    /// become remote fallback requests.
    static let knownUncoveredSetCodes: Set<String> = [
        "BOG", "AQ", "SK", "EX5.5", "EXU", "MFB", "RR", "XYA"
    ]

    static func urls(
        setCode: String,
        collectorNumber: String,
        authorizedBySignedRegistry: Bool? = nil
    ) -> (small: URL, full: URL)? {
        let code = setCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let authorized = authorizedBySignedRegistry ?? supportedSetCodes.contains(code)
        guard authorized,
              !knownUncoveredSetCodes.contains(code),
              let number = normalizedCollectorNumber(collectorNumber) else {
            return nil
        }

        let stem = "\(baseURL)/\(code)/\(code)_\(number)_R_EN"
        guard let small = URL(string: stem + "_XS.png"),
              let full = URL(string: stem + ".png") else {
            return nil
        }
        return (small: small, full: full)
    }

    private static func normalizedCollectorNumber(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let scalars = Array(trimmed.unicodeScalars)
        guard !scalars.isEmpty else { return nil }

        guard let firstDigit = scalars.firstIndex(where: isASCIIDigit) else {
            return nil
        }
        let prefix = scalars[..<firstDigit]
        guard prefix.allSatisfy(isASCIIUppercaseLetter) else { return nil }

        var end = firstDigit
        while end < scalars.count, isASCIIDigit(scalars[end]) {
            end += 1
        }
        // A suffix such as 040a or 103b is not a Limitless key. Reject it
        // rather than silently serving the unsuffixed card.
        guard end == scalars.count else { return nil }

        let digits = String(String.UnicodeScalarView(scalars[firstDigit..<end]))
        guard Int(digits) != nil else { return nil }
        if prefix.isEmpty {
            return String(repeating: "0", count: max(0, 3 - digits.count)) + digits
        }

        let stripped = String(digits.drop { $0 == "0" })
        let prefixString = String(String.UnicodeScalarView(prefix))
        return "\(prefixString)\(stripped.isEmpty ? "0" : stripped)"
    }

    private static func isASCIIDigit(_ scalar: Unicode.Scalar) -> Bool {
        (48...57).contains(scalar.value)
    }

    private static func isASCIIUppercaseLetter(_ scalar: Unicode.Scalar) -> Bool {
        (65...90).contains(scalar.value)
    }
}
