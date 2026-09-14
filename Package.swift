// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Tajpo",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "TajpoCore", targets: ["TajpoCore"]),
        .executable(name: "Tajpo", targets: ["Tajpo"])
    ],
    targets: [
        .target(
            name: "TajpoCore",
            path: "Sources/TajpoCore",
            resources: [.process("Resources")]
        ),
        .executableTarget(
            name: "Tajpo",
            dependencies: ["TajpoCore"],
            path: "Sources/Tajpo",
            exclude: ["Info.plist", "Tajpo.entitlements"]
        ),
        .testTarget(
            name: "TajpoTests",
            dependencies: ["TajpoCore"]
        )
    ]
)
