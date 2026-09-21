import Foundation

/// Small, provider-neutral acceptance gate for artwork URLs.
///
/// A response is usable only when the server both succeeds and identifies a
/// non-empty image body. In particular, some image CDNs return a non-empty
/// placeholder page with a misleading image MIME type on HTTP 404.
public struct PokemonCatalogArtworkProbe: Sendable {
    public typealias Loader = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)

    private let loader: Loader

    public init(
        loader: @escaping Loader = { request in
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw URLError(.badServerResponse)
            }
            return (data, http)
        }
    ) {
        self.loader = loader
    }

    public func accepts(_ url: URL) async -> Bool {
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("image/*", forHTTPHeaderField: "Accept")

        guard let (data, response) = try? await loader(request) else { return false }
        // Keep this before MIME/body checks. A 404 can still carry image/png
        // and a large placeholder body on some image CDNs.
        guard (200..<300).contains(response.statusCode) else { return false }
        guard let contentType = response.value(forHTTPHeaderField: "Content-Type")?
            .split(separator: ";", maxSplits: 1, omittingEmptySubsequences: true)
            .first,
              contentType.trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
                .hasPrefix("image/") else {
            return false
        }
        return !data.isEmpty
    }
}
