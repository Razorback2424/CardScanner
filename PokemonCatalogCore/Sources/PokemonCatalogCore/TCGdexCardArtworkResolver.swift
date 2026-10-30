import Foundation
import ImageIO

/// Repairs omissions in TCGdex's image manifest using only the exact provider
/// series/set/local ID. Never searches another language, set, or card number.
public struct PokemonCatalogTCGdexCardArtworkResolver: Sendable {
    public typealias Loader = PokemonCatalogArtworkProbe.Loader
    private let loader: Loader

    public init(loader: @escaping Loader = { request in
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        return (data, response)
    }) {
        self.loader = loader
    }

    public func resolve(
        language: String = "en",
        seriesID: String,
        setID: String,
        cardID: String,
        localID: String
    ) async -> PokemonCatalogResolvedCardArtwork? {
        // Preserve provider case and zero padding. Treat each value as one
        // path component; malformed identities must never escape that path.
        let components = [language, seriesID, setID, localID]
        guard ["en", "ja"].contains(language),
              components.allSatisfy(Self.isPathComponent),
              cardID == setID + "-" + localID else { return nil }
        let base = components.reduce(URL(string: "https://assets.tcgdex.net")!) {
            $0.appendingPathComponent($1)
        }
        async let highRequest = variant(base: base, size: "high")
        async let lowRequest = variant(base: base, size: "low")
        let (high, low) = await (highRequest, lowRequest)
        guard !Task.isCancelled, let image = high ?? low else { return nil }
        return .init(thumbnail: (low ?? image).absoluteString,
                     image: image.absoluteString, source: .tcgdexCDNProbe)
    }

    private static func isPathComponent(_ value: String) -> Bool {
        !value.isEmpty && value != "." && value != ".."
            && value.unicodeScalars.allSatisfy {
                CharacterSet.alphanumerics.contains($0) || "-_.".unicodeScalars.contains($0)
            }
    }

    private func variant(base: URL, size: String) async -> URL? {
        for format in ["png", "webp"] {
            guard !Task.isCancelled else { return nil }
            let url = base.appendingPathComponent(size + "." + format)
            var request = URLRequest(url: url)
            request.timeoutInterval = 3
            request.setValue("image/*", forHTTPHeaderField: "Accept")
            guard let (data, response) = try? await loader(request),
                  response.url == url,
                  (200..<300).contains(response.statusCode),
                  response.mimeType?.lowercased().hasPrefix("image/") == true,
                  !data.isEmpty, data.count <= 8 * 1_024 * 1_024,
                  let source = CGImageSourceCreateWithData(data as CFData, nil),
                  CGImageSourceGetStatus(source) == .statusComplete,
                  CGImageSourceCreateImageAtIndex(source, 0, nil) != nil else { continue }
            return url
        }
        return nil
    }
}
