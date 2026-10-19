// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Strata",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Strata", targets: ["Strata"]),
        .executable(name: "strata-scan", targets: ["strata-scan"]),
        .library(name: "StrataCore", targets: ["StrataCore"]),
    ],
    targets: [
        .target(name: "StrataCore"),
        .executableTarget(name: "Strata", dependencies: ["StrataCore"]),
        .executableTarget(name: "strata-scan", dependencies: ["StrataCore"]),
        .executableTarget(name: "strata-selftest", dependencies: ["StrataCore"]),
    ],
    swiftLanguageModes: [.v5]
)
