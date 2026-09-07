// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SummitNetwork",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "summit-export", targets: ["SummitExporter"]),
    ],
    targets: [
        .executableTarget(name: "SummitExporter"),
        .testTarget(name: "SummitExporterTests", dependencies: ["SummitExporter"]),
    ]
)
