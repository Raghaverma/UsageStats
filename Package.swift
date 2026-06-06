// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "QuotaBar",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "QuotaBar", targets: ["QuotaBar"])
    ],
    targets: [
        .target(name: "QuotaBarDomain"),
        .target(name: "QuotaBarInfrastructure", dependencies: ["QuotaBarDomain"]),
        .target(name: "QuotaBarProviders", dependencies: ["QuotaBarDomain"]),
        .target(name: "QuotaBarApplication", dependencies: ["QuotaBarDomain"]),
        .target(name: "QuotaBarPresentation", dependencies: ["QuotaBarDomain"]),
        .target(name: "QuotaBarFeatures", dependencies: [
            "QuotaBarDomain", "QuotaBarApplication", "QuotaBarPresentation"
        ]),
        .target(name: "QuotaBarBootstrap", dependencies: [
            "QuotaBarDomain", "QuotaBarApplication",
            "QuotaBarFeatures", "QuotaBarPresentation"
        ]),
        .executableTarget(
            name: "QuotaBar",
            dependencies: [
                "QuotaBarDomain", "QuotaBarInfrastructure", "QuotaBarProviders",
                "QuotaBarApplication", "QuotaBarPresentation",
                "QuotaBarFeatures", "QuotaBarBootstrap"
            ],
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "QuotaBarTests",
            dependencies: [
                "QuotaBar", "QuotaBarDomain", "QuotaBarInfrastructure",
                "QuotaBarProviders", "QuotaBarApplication",
                "QuotaBarPresentation", "QuotaBarFeatures", "QuotaBarBootstrap"
            ],
            exclude: ["Fixtures"]
        )
    ]
)
