// swift-tools-version:5.9
import PackageDescription

var products: [Product] = [
    .library(name: "SpruceCore", targets: ["SpruceCore"]),
    .executable(name: "spruce", targets: ["spruce"]),
]

var targets: [Target] = [
    .target(name: "SpruceCore", path: "Sources/SpruceCore"),
    .executableTarget(name: "spruce", dependencies: ["SpruceCore"], path: "Sources/spruce"),
    .testTarget(name: "SpruceCoreTests", dependencies: ["SpruceCore"], path: "Tests/SpruceCoreTests"),
]

// The SwiftUI app only builds on macOS; the engine and CLI also build on Linux so CI can test them.
#if os(macOS)
products.append(.executable(name: "SpruceApp", targets: ["SpruceApp"]))
targets.append(.executableTarget(name: "SpruceApp", dependencies: ["SpruceCore"], path: "Sources/SpruceApp"))
#endif

let package = Package(
    name: "Spruce",
    platforms: [.macOS(.v14)],
    products: products,
    targets: targets
)
