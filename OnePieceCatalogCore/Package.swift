// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "OnePieceCatalogCore",
    platforms: [.iOS(.v17), .macOS(.v13)],
    products: [
        .library(name: "OnePieceCatalogCore", targets: ["OnePieceCatalogCore"]),
        .executable(name: "one-piece-catalog-publisher", targets: ["one-piece-catalog-publisher"])
    ],
    targets: [
        .target(name: "OnePieceCatalogCore"),
        .executableTarget(name: "one-piece-catalog-publisher", dependencies: ["OnePieceCatalogCore"]),
        .testTarget(name: "OnePieceCatalogCoreTests", dependencies: ["OnePieceCatalogCore"],
                    resources: [.process("Fixtures")])
    ]
)
