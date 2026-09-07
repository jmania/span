// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SummitNetwork",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "summit-export", targets: ["SummitExporter"]),
        .executable(name: "SummitNetworkApp", targets: ["SummitNetworkApp"]),
    ],
    targets: [
        .target(
            name: "SummitCore",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ApplicationServices"),
            ]
        ),
        .executableTarget(name: "SummitExporter", dependencies: ["SummitCore"]),
        .executableTarget(name: "SummitNetworkApp", dependencies: ["SummitCore"]),
        .testTarget(name: "SummitCoreTests", dependencies: ["SummitCore"]),
    ]
)
