// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "BetterWisprShared",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "BetterWisprShared", targets: ["BetterWisprShared"])],
    targets: [
        .target(name: "BetterWisprShared"),
        .testTarget(name: "BetterWisprSharedTests", dependencies: ["BetterWisprShared"])
    ],
    swiftLanguageModes: [.v6]
)
