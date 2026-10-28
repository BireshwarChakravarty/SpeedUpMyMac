// swift-tools-version:5.9
import PackageDescription

var products: [Product] = [
    .library(name: "BurnishCore", targets: ["BurnishCore"]),
    .executable(name: "burnish", targets: ["burnish"]),
]

var targets: [Target] = [
    .target(name: "BurnishCore", path: "Sources/BurnishCore"),
    .executableTarget(name: "burnish", dependencies: ["BurnishCore"], path: "Sources/burnish"),
    .testTarget(name: "BurnishCoreTests", dependencies: ["BurnishCore"], path: "Tests/BurnishCoreTests"),
]

// The SwiftUI app only builds on macOS; the engine and CLI also build on Linux so CI can test them.
#if os(macOS)
products.append(.executable(name: "BurnishApp", targets: ["BurnishApp"]))
targets.append(.executableTarget(name: "BurnishApp", dependencies: ["BurnishCore"], path: "Sources/BurnishApp"))
#endif

let package = Package(
    name: "Burnish",
    platforms: [.macOS(.v14)],
    products: products,
    targets: targets
)
