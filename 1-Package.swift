// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Tajpo",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Tajpo", targets: ["Tajpo"])],
    targets: [
        .executableTarget(name: "Tajpo", path: "Sources/Tajpo"),
        .testTarget(name: "TajpoTests", dependencies: ["Tajpo"])
    ]
)
