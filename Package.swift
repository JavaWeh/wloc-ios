// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "WLocCore",
    platforms: [.macOS(.v12), .iOS(.v16)],
    products: [.library(name: "WLocCore", targets: ["WLocCore"])],
    targets: [
        .target(name: "WLocCore", path: "WLoc/Core"),
        .testTarget(name: "WLocCoreTests", dependencies: ["WLocCore"], path: "Tests")
    ]
)

