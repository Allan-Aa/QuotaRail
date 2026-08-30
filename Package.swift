// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "QuotaRail",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "QuotaRail", targets: ["QuotaRail"])
    ],
    targets: [
        .target(
            name: "QuotaRailCore",
            path: "Sources/QuotaRailCore"
        ),
        .executableTarget(
            name: "QuotaRail",
            dependencies: ["QuotaRailCore"],
            path: "Sources/QuotaRail",
            resources: [.copy("Resources/Brand")]
        ),
        .executableTarget(
            name: "QuotaRailCoreChecks",
            dependencies: ["QuotaRailCore"],
            path: "Checks"
        )
    ]
)
