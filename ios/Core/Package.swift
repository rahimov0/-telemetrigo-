// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "KrovaCore",
    platforms: [.iOS(.v17), .macOS(.v13)],
    products: [.library(name: "KrovaCore", targets: ["KrovaCore"])],
    targets: [
        .target(name: "KrovaCore"),
        .testTarget(name: "KrovaCoreTests", dependencies: ["KrovaCore"])
    ]
)
