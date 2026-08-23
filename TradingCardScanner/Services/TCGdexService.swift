import Foundation

enum TCGdexError: LocalizedError {
    case invalidURL
    case cardNotFound
    case badResponse

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Could not build the TCGdex request."
        case .cardNotFound: return "That identifier did not match a card in TCGdex."
        case .badResponse: return "TCGdex returned an unexpected response."
        }
    }
}

struct TCGdexService {
    func fetchCard(setID: String, localID: String) async throws -> TCGdexCard {
        guard let url = URL(string: "https://api.tcgdex.net/v2/en/sets/\(setID)/\(localID)") else {
            throw TCGdexError.invalidURL
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 8

        // Respect normal HTTP cache validation. Unlike returnCacheDataElseLoad,
        // this allows mutable pricing data to refresh when the server says it should.
        request.cachePolicy = .useProtocolCachePolicy

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw TCGdexError.badResponse
        }

        if http.statusCode == 404 {
            throw TCGdexError.cardNotFound
        }

        guard (200..<300).contains(http.statusCode) else {
            throw TCGdexError.badResponse
        }

        return try JSONDecoder().decode(TCGdexCard.self, from: data)
    }
}
