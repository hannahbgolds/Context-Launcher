// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ContextLauncherKit",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "ContextLauncherKit", targets: ["ContextLauncherKit"])
    ],
    targets: [
        .target(name: "ContextLauncherKit"),
        .testTarget(name: "ContextLauncherKitTests", dependencies: ["ContextLauncherKit"])
    ]
)
