// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NCMConverter",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "NCMConverter", targets: ["NCMConverter"])
    ],
    targets: [
        .executableTarget(
            name: "NCMConverter",
            path: "Sources/NCMConverter"
        )
    ]
)
