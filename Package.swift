// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "Mill",
    platforms: [.macOS(.v12)],
    products: [
        .library(name: "Mill", targets: ["Mill"]),
        .executable(name: "mill", targets: ["MillCLI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/SecondMouseAU/OCCTSwift.git", exact: "3.0.0"),
    ],
    targets: [
        .target(name: "Mill", dependencies: [.product(name: "OCCTSwift", package: "OCCTSwift")]),
        .executableTarget(name: "MillCLI", dependencies: ["Mill"]),
        .testTarget(name: "MillTests", dependencies: ["Mill"], resources: [.copy("Fixtures")]),
    ]
)
