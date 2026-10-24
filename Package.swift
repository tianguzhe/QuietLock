// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "QuietLockCore",
    platforms: [.macOS(.v14)],
    products: [.library(name: "QuietLockCore", targets: ["QuietLockCore"])],
    targets: [
        .target(name: "QuietLockCore"),
        .testTarget(name: "QuietLockCoreTests", dependencies: ["QuietLockCore"])
    ]
)
