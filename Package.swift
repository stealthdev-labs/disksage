// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DiskSage",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "DiskSage", targets: ["DiskSage"])
    ],
    targets: [
        .executableTarget(
            name: "DiskSage",
            path: "Sources/DiskSage"
        ),
        .testTarget(
            name: "DiskSageTests",
            dependencies: ["DiskSage"],
            path: "Tests/DiskSageTests"
        )
    ]
)
