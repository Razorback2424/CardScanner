// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "MagicCatalogCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v13)
    ],
    products: [
        .library(name: "MagicCatalogCore", targets: ["MagicCatalogCore"]),
        .executable(
            name: "magic-catalog-publisher",
            targets: ["magic-catalog-publisher"]
        )
    ],
    targets: [
        .target(name: "MagicCatalogCore"),
        .executableTarget(
            name: "magic-catalog-publisher",
            dependencies: ["MagicCatalogCore"]
        ),
        .testTarget(
            name: "MagicCatalogCoreTests",
            dependencies: ["MagicCatalogCore"],
            resources: [.process("Fixtures")]
        )
    ]
)
