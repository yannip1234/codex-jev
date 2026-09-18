// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "JevCodex",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "JevCodex", targets: ["JevCodex"])],
    targets: [
        .executableTarget(name: "JevCodex"),
        .testTarget(name: "JevCodexTests", dependencies: ["JevCodex"])
    ]
)
