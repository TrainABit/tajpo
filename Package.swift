// swift-tools-version: 6.0
import PackageDescription

// TajpoCore holds all platform-independent logic (prompts, streaming, error
// mapping, validation, geometry) so it can be tested on any platform.
// The macOS app target is only declared on macOS.
var targets: [Target] = [
    .target(name: "TajpoCore"),
    .testTarget(name: "TajpoTests", dependencies: ["TajpoCore"])
]
var products: [Product] = []

#if os(macOS)
targets.append(.executableTarget(name: "Tajpo", dependencies: ["TajpoCore"]))
products.append(.executable(name: "Tajpo", targets: ["Tajpo"]))
#endif

let package = Package(
    name: "Tajpo",
    platforms: [.macOS(.v14)],
    products: products,
    targets: targets
)
