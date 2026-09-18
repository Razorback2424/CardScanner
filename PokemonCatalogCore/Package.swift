// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "PokemonCatalogCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "PokemonCatalogCore",
            targets: ["PokemonCatalogCore"]
        ),
        .executable(
            name: "pokemon-catalog-publisher",
            targets: ["pokemon-catalog-publisher"]
        )
    ],
    targets: [
        .target(
            name: "PokemonCatalogCore"
        ),
        .executableTarget(
            name: "pokemon-catalog-publisher",
            dependencies: ["PokemonCatalogCore"]
        ),
        .testTarget(
            name: "PokemonCatalogCoreTests",
            dependencies: ["PokemonCatalogCore"],
            resources: [
                .process("Fixtures")
            ]
        )
    ]
)
