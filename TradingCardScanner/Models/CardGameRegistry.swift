import Foundation

struct CardGameCapabilities: OptionSet, Sendable {
    let rawValue: Int
    static let scan = Self(rawValue: 1 << 0)
    static let browse = Self(rawValue: 1 << 1)
    static let pricing = Self(rawValue: 1 << 2)
    static let sealed = Self(rawValue: 1 << 3)
    /// Writing to the existing CloudKit-compatible collection requires an
    /// independently verified mixed-client policy for each newly added game.
    static let collectionWrite = Self(rawValue: 1 << 4)
    static let gradedPricing = Self(rawValue: 1 << 5)
}

struct CardGameDescriptor: Sendable, Identifiable {
    let game: CardGame
    let displayName: String
    let sortOrder: Int
    let capabilities: CardGameCapabilities
    var id: CardGame { game }
}

/// Descriptors are the enumeration authority; unknown stored IDs never become
/// another game just because a module is unavailable. Runtime injection is a
/// separate boundary from identity decoding.
struct CardGameRegistry: Sendable {
    private let descriptors: [CardGame: CardGameDescriptor]
    private let variantPolicies: [CardGame: any GameVariantPolicy]

    init(descriptors: [CardGameDescriptor], variantPolicies: [CardGame: any GameVariantPolicy] = [:]) {
        precondition(Set(descriptors.map(\.game)).count == descriptors.count,
                     "Game registration must be unique")
        self.descriptors = Dictionary(uniqueKeysWithValues: descriptors.map { ($0.game, $0) })
        precondition(Set(variantPolicies.keys).isSubset(of: Set(descriptors.map(\.game))),
                     "Variant policies require a registered game")
        self.variantPolicies = variantPolicies
    }

    func descriptor(for game: CardGame) -> CardGameDescriptor? { descriptors[game] }
    func variantPolicy(for game: CardGame) -> (any GameVariantPolicy)? { variantPolicies[game] }
    func replacingVariantPolicy(_ policy: any GameVariantPolicy, for game: CardGame) -> Self {
        var policies = variantPolicies
        guard descriptors[game] != nil else { return self }
        policies[game] = policy
        return Self(descriptors: Array(descriptors.values), variantPolicies: policies)
    }
    var variantLockMenu: [GameVariantLockOptions] {
        games(supporting: .scan).compactMap { game in
            guard let descriptor = descriptors[game],
                  let options = variantPolicies[game]?.lockOptions,
                  !options.isEmpty else { return nil }
            return .init(game: game, displayName: descriptor.displayName, options: options)
        }
    }

    func games(supporting capability: CardGameCapabilities) -> [CardGame] {
        descriptors.values.filter { $0.capabilities.contains(capability) }
            .sorted {
                $0.sortOrder == $1.sortOrder
                    ? $0.game.rawValue < $1.game.rawValue : $0.sortOrder < $1.sortOrder
            }.map(\.game)
    }

    func supports(_ game: CardGame, _ capability: CardGameCapabilities) -> Bool {
        descriptors[game]?.capabilities.contains(capability) == true
    }

    var enabledGames: [CardGame] { games(supporting: .scan) }

    static let standard = CardGameRegistry(descriptors: [
        PokemonGameRuntime.descriptor,
        MagicGameRuntime.descriptor,
        // Identity/presentation only. No One Piece feature or provider is
        // enabled by adding this descriptor.
        .init(game: .onePiece, displayName: "One Piece", sortOrder: 2, capabilities: []),
        .init(game: .lorcana, displayName: "Disney Lorcana", sortOrder: 3, capabilities: [])
    ], variantPolicies: [.pokemon: PokemonVariantPolicy(), .magic: MagicVariantPolicy()])
}
