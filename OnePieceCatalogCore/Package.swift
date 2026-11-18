// swift-tools-version: 5.9
import PackageDescription

// Apple platforms use CryptoKit. Linux, where CI signs and tests the catalog,
// uses swift-crypto, which implements the same API. The dependency is declared
// only on Linux so the app's Xcode package graph does not change.
#if os(Linux)
let cryptoDependencies: [Package.Dependency] = [
    .package(url: "https://github.com/apple/swift-crypto.git", exact: "3.15.1")
]
let cryptoProducts: [Target.Dependency] = [.product(name: "Crypto", package: "swift-crypto")]
#else
let cryptoDependencies: [Package.Dependency] = []
let cryptoProducts: [Target.Dependency] = []
#endif

let package = Package(
    name: "OnePieceCatalogCore",
    platforms: [.iOS(.v17), .macOS(.v13)],
    products: [
        .library(name: "OnePieceCatalogCore", targets: ["OnePieceCatalogCore"]),
        .executable(name: "one-piece-catalog-publisher", targets: ["one-piece-catalog-publisher"])
    ],
    dependencies: cryptoDependencies,
    targets: [
        .target(name: "OnePieceCatalogCore", dependencies: cryptoProducts),
        .executableTarget(name: "one-piece-catalog-publisher",
                          dependencies: ["OnePieceCatalogCore"] + cryptoProducts),
        .testTarget(name: "OnePieceCatalogCoreTests", dependencies: ["OnePieceCatalogCore"] + cryptoProducts,
                    resources: [.process("Fixtures")])
    ]
)
