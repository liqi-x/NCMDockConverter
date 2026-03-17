// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NCMDockConverter",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "NCMDockConverter", targets: ["NCMDockConverter"])
    ],
    targets: [
        .executableTarget(
            name: "NCMDockConverter",
            path: "Sources/NCMDockConverter"
        )
    ]
)
