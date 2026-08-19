// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ContextLauncherKit",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "ContextLauncherKit", targets: ["ContextLauncherKit"]),
        .executable(name: "ContextLauncherApp", targets: ["ContextLauncherApp"]),
        .executable(name: "context", targets: ["context"])
    ],
    targets: [
        .target(name: "ContextLauncherKit"),
        .executableTarget(name: "ContextLauncherApp", dependencies: ["ContextLauncherKit"]),
        .executableTarget(name: "context", dependencies: ["ContextLauncherKit"]),
        .testTarget(name: "ContextLauncherKitTests", dependencies: ["ContextLauncherKit", "ContextLauncherApp"])
    ]
)
