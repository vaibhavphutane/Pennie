// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "WriteDock",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "WriteDock", targets: ["WriteDock"])],
    targets: [
        .target(name: "WriteDockCore"),
        .executableTarget(name: "WriteDock", dependencies: ["WriteDockCore"], resources: [.process("Resources")]),
        .testTarget(name: "WriteDockCoreTests", dependencies: ["WriteDockCore"])
    ]
)
