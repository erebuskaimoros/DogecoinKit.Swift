// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "DogecoinKit",
    platforms: [
        .iOS(.v13),
        .macOS(.v12),
    ],
    products: [
        .library(name: "DogecoinKit", targets: ["DogecoinKit"]),
    ],
    dependencies: [
        .package(
            url: "https://github.com/erebuskaimoros/BitcoinCore.Swift.git",
            revision: "21c29bd2438b168fffabaf8ff8ea89e4e53cf15f"
        ),
        .package(url: "https://github.com/attaswift/BigInt.git", exact: "5.3.0"),
        .package(url: "https://github.com/horizontalsystems/HdWalletKit.Swift.git", exact: "1.3.1"),
        .package(url: "https://github.com/horizontalsystems/HsToolKit.Swift.git", exact: "2.0.5"),
        .package(url: "https://github.com/greymass/swift-scrypt.git", exact: "1.0.2"),
    ],
    targets: [
        .target(
            name: "DogecoinKit",
            dependencies: [
                "BigInt",
                .product(name: "BitcoinCore", package: "BitcoinCore.Swift"),
                .product(name: "HdWalletKit", package: "HdWalletKit.Swift"),
                .product(name: "HsToolKit", package: "HsToolKit.Swift"),
                .product(name: "Scrypt", package: "swift-scrypt"),
            ],
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "DogecoinKitTests",
            dependencies: [
                "DogecoinKit",
                .product(name: "BitcoinCore", package: "BitcoinCore.Swift"),
                .product(name: "HdWalletKit", package: "HdWalletKit.Swift"),
            ]
        ),
    ]
)
