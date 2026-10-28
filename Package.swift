// swift-tools-version:5.9
import PackageDescription

var products: [Product] = [
    .library(name: "RootCore", targets: ["RootCore"]),
    .executable(name: "root", targets: ["root"]),
]

var targets: [Target] = [
    .target(name: "RootCore", path: "Sources/RootCore"),
    .executableTarget(name: "root", dependencies: ["RootCore"], path: "Sources/root"),
    .testTarget(name: "RootCoreTests", dependencies: ["RootCore"], path: "Tests/RootCoreTests"),
]

// The SwiftUI app only builds on macOS; the engine and CLI also build on Linux so CI can test them.
#if os(macOS)
products.append(.executable(name: "RootApp", targets: ["RootApp"]))
targets.append(.executableTarget(name: "RootApp", dependencies: ["RootCore"], path: "Sources/RootApp"))
#endif

let package = Package(
    name: "Root",
    platforms: [.macOS(.v14)],
    products: products,
    targets: targets
)
