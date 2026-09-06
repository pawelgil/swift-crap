// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "swift-crap",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "CrapCore", targets: ["CrapCore"]),
        .library(name: "CrapSyntax", targets: ["CrapSyntax"]),
        .library(name: "CrapCoverage", targets: ["CrapCoverage"]),
        .executable(name: "swift-crap", targets: ["CrapCLI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-crypto.git", exact: "4.5.2"),
        .package(url: "https://github.com/swiftlang/swift-syntax.git", exact: "603.0.2"),
    ],
    targets: [
        .target(name: "CrapCore"),
        .target(name: "CrapCoverage", dependencies: ["CrapCore"]),
        .target(name: "CrapSyntax", dependencies: [
            "CrapCore",
            .product(name: "SwiftIfConfig", package: "swift-syntax"),
            .product(name: "SwiftSyntax", package: "swift-syntax"),
            .product(name: "SwiftParser", package: "swift-syntax"),
            .product(name: "SwiftParserDiagnostics", package: "swift-syntax"),
        ]),
        .target(name: "CrapApplication", dependencies: ["CrapCore"]),
        .executableTarget(name: "CrapCLI", dependencies: [
            "CrapApplication", "CrapCore", "CrapCoverage", "CrapSyntax",
            .product(name: "Crypto", package: "swift-crypto"),
            .product(name: "SwiftIfConfig", package: "swift-syntax"),
        ]),
        .testTarget(name: "CrapCoreTests", dependencies: ["CrapCore"]),
        .testTarget(name: "CrapCoverageTests", dependencies: ["CrapCoverage", "CrapCore"]),
        .testTarget(name: "CrapSyntaxTests", dependencies: ["CrapSyntax", "CrapCore"]),
        .testTarget(name: "CrapApplicationTests", dependencies: ["CrapApplication", "CrapCore"]),
        .testTarget(name: "CrapCLITests", dependencies: ["CrapCLI", "CrapApplication"]),
        .testTarget(name: "IntegrationTests", dependencies: ["CrapCore", "CrapCoverage", "CrapSyntax"]),
    ],
)
