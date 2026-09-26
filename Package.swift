// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Drift",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "Drift", targets: ["DriftApp"]),
        .library(name: "DriftCore", targets: ["DriftCore"])
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.9.2"),
        .package(url: "https://github.com/jaywcjlove/PermissionFlow", exact: "2.11.2")
    ],
    targets: [
        .target(name: "DriftCore", path: "Sources/DriftCore"),
        .executableTarget(
            name: "DriftApp",
            dependencies: [
                "DriftCore",
                .product(name: "Sparkle", package: "Sparkle"),
                .product(name: "PermissionFlow", package: "PermissionFlow")
            ],
            path: "Sources/DriftApp",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("Carbon"),
                .linkedFramework("IOKit"),
                .linkedFramework("ServiceManagement")
            ]
        ),
        .testTarget(
            name: "DriftCoreTests",
            dependencies: ["DriftCore"],
            path: "Tests/DriftCoreTests"
        ),
        .testTarget(
            name: "DriftAppTests",
            dependencies: ["DriftApp"],
            path: "Tests/DriftAppTests"
        )
    ]
)
