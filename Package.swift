// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Tajpo",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Tajpo", targets: ["Tajpo"])],
    targets: [
        .executableTarget(name: "Tajpo", path: "Sources/Tajpo", resources: [.process("Resources")]),
        .testTarget(name: "TajpoTests", dependencies: ["Tajpo"])
    ]
)
