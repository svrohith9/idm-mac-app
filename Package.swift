// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "IDMMacApp",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "IDMMacApp",
            targets: ["IDMMacApp"]
        )
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "IDMMacApp",
            dependencies: [],
            path: "Sources/IDMMacApp",
            resources: []
        )
    ]
)
