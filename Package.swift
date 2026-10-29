// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Pennie",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "Pennie", targets: ["Pennie"])],
    targets: [
        .target(name: "PennieCore"),
        .executableTarget(name: "Pennie", dependencies: ["PennieCore"], resources: [.process("Resources")]),
        .testTarget(name: "PennieCoreTests", dependencies: ["PennieCore"])
    ]
)
