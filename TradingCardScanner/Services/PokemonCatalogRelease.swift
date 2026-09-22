import PokemonCatalogCore

// The app keeps these aliases at its existing internal call sites while the
// platform-neutral package owns the wire contract used by the publisher and
// runtime verifier. There is deliberately no second Codable definition in
// the iOS target.
typealias PokemonCatalogReleaseEnvelope = PokemonCatalogCore.PokemonCatalogReleaseEnvelope
typealias PokemonCatalogRelease = PokemonCatalogCore.PokemonCatalogRelease
typealias PokemonCatalogSetDescriptor = PokemonCatalogCore.PokemonCatalogSetDescriptor
typealias CatalogCardArtwork = PokemonCatalogCore.PokemonCatalogCardArtwork
typealias PokemonCatalogMembershipRecognition = PokemonCatalogCore.PokemonCatalogMembershipRecognition
typealias Base64URL = PokemonCatalogCore.PokemonCatalogBase64URL
